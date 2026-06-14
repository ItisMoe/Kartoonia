import 'package:http/http.dart' as http;

/// THE CRITICAL SERVICE (ported verbatim from the RN `tokenService.ts`).
///
/// Videos require fresh, IP-bound, time-limited tokens generated when the
/// episode page loads. They cannot be cached. Call [fetchFreshTokens] /
/// [getPlayableUrl] RIGHT BEFORE playback.
///
/// NEVER use `raw_url` from catalog.json for playback — it is stale.

/// Headers used to load the episode/movie HTML page.
const Map<String, String> kEpisodePageHeaders = {
  'User-Agent':
      'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
  'Referer': 'https://www.arabic-toons.com/',
  'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
  'Accept-Language': 'ar,en;q=0.9',
};

/// Headers the CDN requires on every stream/segment request (no Referer => 403).
const Map<String, String> kStreamHeaders = {
  'Referer': 'https://www.arabic-toons.com/',
  'User-Agent': 'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36',
  'Origin': 'https://www.arabic-toons.com',
};

class ServerLink {
  final int serverNumber;
  final String rawUrl; // full tokenized URL — use this to actually play
  final String cleanUrl; // base URL without tokens
  const ServerLink(this.serverNumber, this.rawUrl, this.cleanUrl);
}

class PlayableSource {
  final String url;
  final Map<String, String> headers;
  const PlayableSource(this.url, this.headers);
}

/// Extracts all server URLs (with tokens) from episode/movie page HTML.
///
/// Live pages deliver a single tokenized URL via `const videoSrc = "...";`.
/// Older / multi-server pages use `var serverN = "...?tkn=...";`.
/// Fallback: `<source src> / data-src / file: "....mp4"`.
List<ServerLink> extractServerLinks(String html) {
  final servers = <ServerLink>[];
  final seen = <int>{};

  void push(int n, String raw) {
    final rawUrl = raw.trim();
    if (!rawUrl.startsWith('http')) return;
    final cleanUrl = rawUrl.split('?').first;
    final path = cleanUrl.split('/').isNotEmpty ? cleanUrl.split('/').last : '';
    if (!path.contains('.')) return; // no extension => not a media file
    if (seen.contains(n)) return;
    seen.add(n);
    servers.add(ServerLink(n, rawUrl, cleanUrl));
  }

  // Pattern 1: numbered servers — var/let/const serverN = "...";
  final reServer = RegExp(
    r'''(?:var|let|const)\s+server(\d+)\s*=\s*["']([^"']{15,})["']''',
    caseSensitive: false,
  );
  for (final m in reServer.allMatches(html)) {
    push(int.parse(m.group(1)!), m.group(2)!);
  }

  // Pattern 2: single source — var/let/const videoSrc = "...";
  final reVideoSrc = RegExp(
    r'''(?:var|let|const)\s+videoSrc\s*=\s*["']([^"']{15,})["']''',
    caseSensitive: false,
  );
  final vm = reVideoSrc.firstMatch(html);
  if (vm != null) push(1, vm.group(1)!);

  // Pattern 3 (fallback): <source src> / data-src / file: "....mp4|m3u8|..."
  if (servers.isEmpty) {
    final reSrc = RegExp(
      r'''(?:src|data-src|file)\s*[:=]\s*["']([^"']*\.(?:mp4|m3u8|mkv|webm)[^"']*)["']''',
      caseSensitive: false,
    );
    var i = 1;
    for (final m in reSrc.allMatches(html)) {
      push(i++, m.group(1)!);
    }
  }

  servers.sort((a, b) => a.serverNumber.compareTo(b.serverNumber));
  return servers;
}

/// Fetches a fresh set of tokenized server URLs for an episode/movie page.
Future<List<ServerLink>> fetchFreshTokens(String episodePageUrl) async {
  final res = await http.get(
    Uri.parse(episodePageUrl),
    headers: kEpisodePageHeaders,
  );
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw Exception('Failed to fetch episode page: ${res.statusCode}');
  }
  return extractServerLinks(res.body);
}

/// Tokenized source for a specific server, falling back to the first available.
Future<PlayableSource> getPlayableUrl(
  String episodePageUrl, {
  int preferredServer = 1,
}) async {
  final servers = await fetchFreshTokens(episodePageUrl);
  if (servers.isEmpty) {
    throw Exception('No video servers found on this page');
  }
  final server = servers.firstWhere(
    (s) => s.serverNumber == preferredServer,
    orElse: () => servers.first,
  );
  return PlayableSource(server.rawUrl, kStreamHeaders);
}

/// How many distinct servers a page exposes (for the player's server tabs).
Future<List<int>> getAvailableServers(String episodePageUrl) async {
  final servers = await fetchFreshTokens(episodePageUrl);
  return servers.map((s) => s.serverNumber).toList();
}
