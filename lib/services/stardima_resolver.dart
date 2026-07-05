import 'dart:convert';
import 'package:http/http.dart' as http;

/// Resolves a Stardima `play_url` to playable stream URLs.
///
/// Stardima items expose only a `play_url`. Turning that into something a video
/// player can open is a three-stage pipeline:
///
///   1. play page              -> the hyperwatching `hashid`
///   2. v2 watch page          -> per-host embed links (data-page JSON server
///                                list -> GET .../server/<id>/url per host)
///   3. each host embed page   -> the real `.m3u8` / `.mp4` stream URL
///
/// NOTE (2026-07): hyperwatching migrated its player from the old
/// `hyperwatching.com/iframe/<code>` (csrf + `POST /api/videos/<code>/link`)
/// to an Inertia.js app at `v2.hyperwatching.com/watch/<hashid>`. The server
/// list now lives in the page's `data-page` JSON, and each host embed is
/// fetched from `embed/<hashid>/server/<link_id>/url`, which returns a
/// `watch_url` pointing at a `strema.top/embed2/?id=<host-embed-url>` wrapper —
/// the real host URL is the `id` query param. Stage 3 (packed-JS unpack +
/// stream extraction) is unchanged: the hosts (Uqload, Lulustream, …) still
/// serve the same Dean-Edwards-packed `master.m3u8`.

const String _star = 'https://www.stardima.com';
const String _hw = 'https://v2.hyperwatching.com';
const String _ua =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

const Duration _timeout = Duration(seconds: 20);

/// A playable stream extracted from one host embed page.
class ResolvedStream {
  final String server; // host name, e.g. "Lulustream"
  final String streamUrl; // the .m3u8 / .mp4
  final String type; // 'hls' | 'mp4'
  final String referer; // host origin the CDN expects
  final String userAgent;

  const ResolvedStream({
    required this.server,
    required this.streamUrl,
    required this.type,
    required this.referer,
    required this.userAgent,
  });

  /// Headers the CDN requires on the manifest + every segment request.
  Map<String, String> get headers => {
        'Referer': referer,
        'User-Agent': userAgent,
        'Origin': referer.endsWith('/')
            ? referer.substring(0, referer.length - 1)
            : referer,
      };
}

class _EmbedServer {
  final String name;
  final String embedUrl;
  const _EmbedServer(this.name, this.embedUrl);
}

class _StreamInfo {
  final String streamUrl;
  final String type;
  final String referer;
  const _StreamInfo(this.streamUrl, this.type, this.referer);
}

/// Thrown when a play_url cannot be turned into any playable stream.
class StardimaResolveException implements Exception {
  final String message;
  const StardimaResolveException(this.message);
  @override
  String toString() => 'StardimaResolveException: $message';
}

final http.Client _client = http.Client();

// --------------------------------------------------------------------------- //
// 1) play page  ->  hyperwatching hashid
// --------------------------------------------------------------------------- //
final List<RegExp> _codePatterns = [
  // v2 `.../watch/<hashid>` (current) and legacy `.../iframe/<code>`.
  RegExp(
      r'https?://(?:www\.|v2\.)?hyperwatching\.com/(?:watch|iframe)/([A-Za-z0-9_\-]+)'),
  RegExp(r'"watch_url"\s*:\s*"[^"]*?/(?:watch|iframe)/([A-Za-z0-9_\-]+)"'),
  RegExp(r'og:video"\s+content="[^"]*?/(?:watch|iframe)/([A-Za-z0-9_\-]+)"'),
];

/// Pure: find the hyperwatching `hashid` (v2 `/watch/` or legacy `/iframe/`) in
/// already-fetched play-page HTML. Exposed for testing.
String? hyperwatchingCodeFromHtml(String html) {
  final body = _htmlUnescape(html);
  for (final p in _codePatterns) {
    final m = p.firstMatch(body);
    if (m != null) return m.group(1);
  }
  return null;
}

Future<String?> hyperwatchingCode(String playUrl) async {
  final res = await _client.get(
    Uri.parse(playUrl),
    headers: {
      'User-Agent': _ua,
      'Accept-Language': 'ar,en;q=0.9',
      'Referer': '$_star/',
    },
  ).timeout(_timeout);
  return hyperwatchingCodeFromHtml(res.body);
}

// --------------------------------------------------------------------------- //
// 2) v2 watch page  ->  per-host embed links
// --------------------------------------------------------------------------- //
/// Pure: parse the csrf token + `(linkId, name)` server list out of the v2
/// watch page. The server list is JSON inside the Inertia `data-page="..."`
/// attribute (HTML-escaped); only completed servers with a non-zero id are
/// playable. Exposed for testing.
({String? csrf, List<(String, String)> servers}) parseWatchServers(
    String html) {
  final csrf =
      RegExp(r'csrf-token"\s+content="([^"]+)"').firstMatch(html)?.group(1);
  final dp = RegExp(r'data-page="(.*?)"\s*>', dotAll: true).firstMatch(html);
  if (dp == null) return (csrf: csrf, servers: const []);
  try {
    final json =
        jsonDecode(_htmlUnescape(dp.group(1)!)) as Map<String, dynamic>;
    final video = (json['props'] as Map?)?['video'] as Map?;
    final servers = (video?['servers'] as List?) ?? const [];
    final out = <(String, String)>[];
    for (final s in servers) {
      if (s is! Map) continue;
      final id = s['id'];
      if (id == null || id == 0) continue; // 0 = still processing / no link
      final status = s['status'];
      if (status != null && status != 'completed') continue;
      out.add(('$id', '${s['name'] ?? 'Server'}'));
    }
    return (csrf: csrf, servers: out);
  } catch (_) {
    return (csrf: csrf, servers: const []);
  }
}

/// Pure: the real host embed URL behind a v2 `watch_url`. The endpoint returns
/// a `strema.top/embed2/?id=<host-embed-url>` wrapper whose iframe shell has no
/// stream — the playable host page is the url-decoded `id` query param.
/// Non-wrapper URLs are returned unchanged. Exposed for testing.
String embedHostFromWatchUrl(String watchUrl) {
  final id = Uri.tryParse(watchUrl)?.queryParameters['id'];
  return (id != null && id.startsWith('http')) ? id : watchUrl;
}

Future<List<_EmbedServer>> _serversForCode(String code) async {
  final watchPage = '$_hw/watch/$code';
  final res = await _client.get(
    Uri.parse(watchPage),
    headers: {
      'User-Agent': _ua,
      'Accept-Language': 'ar,en;q=0.9',
      'Referer': '$_star/',
    },
  ).timeout(_timeout);

  final parsed = parseWatchServers(res.body);
  if (parsed.servers.isEmpty) return const [];

  final headers = {
    'X-Requested-With': 'XMLHttpRequest',
    'Accept': 'application/json, text/plain, */*',
    'Referer': watchPage,
    'Origin': _hw,
    'User-Agent': _ua,
    if (parsed.csrf != null) 'X-CSRF-TOKEN': parsed.csrf!,
  };

  final out = <_EmbedServer>[];
  for (final (linkId, sname) in parsed.servers) {
    try {
      final r = await _client
          .get(
            Uri.parse('$_hw/embed/$code/server/$linkId/url'),
            headers: headers,
          )
          .timeout(_timeout);
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final watch = j['watch_url'];
      if (watch is String && watch.isNotEmpty) {
        out.add(_EmbedServer(sname, embedHostFromWatchUrl(watch)));
      }
    } catch (_) {
      // a single host failing must not sink the rest
    }
  }
  return out;
}

// --------------------------------------------------------------------------- //
// 3) embed page  ->  real stream (.m3u8 / .mp4), incl. packed-JS hosts
// --------------------------------------------------------------------------- //

/// `.m3u8` / `.mp4` anywhere in text (handles escaped `\/` slashes too).
final RegExp _streamUrlRe = RegExp(
  r'''https?:\\?/\\?/[^\s"'\\)\]]+?\.(?:m3u8|mp4)[^\s"'\\)\]]*''',
);

String _origin(String url) {
  final u = Uri.tryParse(url);
  if (u == null || u.scheme.isEmpty || u.host.isEmpty) return url;
  return '${u.scheme}://${u.host}/';
}

/// Pure: extract the best playable stream URL from embed-page HTML, searching
/// the raw page AND any unpacked `p,a,c,k,e,d` block. Prefers `master.m3u8`,
/// then any `.m3u8`, then `.mp4`. Returns null when nothing is found.
/// Exposed for testing; mirrors the Python `extract_stream` selection.
String? bestStreamUrl(String html) {
  final haystacks = <String>[html];
  final packed = unpackPacked(html);
  if (packed.isNotEmpty) haystacks.add(packed);

  final unique = <String>[];
  for (final hay in haystacks) {
    for (final m in _streamUrlRe.allMatches(hay)) {
      final u = m.group(0)!.replaceAll(r'\/', '/');
      if (!unique.contains(u)) unique.add(u);
    }
  }
  if (unique.isEmpty) return null;

  int rank(String u) {
    final lu = u.toLowerCase();
    if (lu.contains('master.m3u8')) return 0;
    if (lu.contains('.m3u8')) return 1;
    return 2;
  }

  var best = unique.first;
  for (final u in unique) {
    if (rank(u) < rank(best)) best = u;
  }
  return best;
}

Future<_StreamInfo> _extractStream(String embedUrl) async {
  final referer = _origin(embedUrl);
  final res = await _client.get(
    Uri.parse(embedUrl),
    headers: {
      'User-Agent': _ua,
      'Referer': referer,
      'Accept': '*/*',
      'Accept-Language': 'ar,en;q=0.9',
    },
  ).timeout(_timeout);

  final best = bestStreamUrl(res.body);
  if (best == null) {
    throw const StardimaResolveException(
        'No .m3u8 or .mp4 stream found in the embed page');
  }
  return _StreamInfo(
    best,
    best.toLowerCase().contains('.m3u8') ? 'hls' : 'mp4',
    referer,
  );
}

/// Decode a Dean-Edwards `eval(function(p,a,c,k,e,d){...})` packed block, so a
/// plain regex can find the `.m3u8` / `.mp4` hidden inside. Returns '' if none.
String unpackPacked(String src) {
  const digits =
      '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
  final out = <String>[];
  final blocks = RegExp(
    r"\}\('(.*?)',(\d+),(\d+),'(.*?)'\.split\('\|'\)",
    dotAll: true,
  );
  for (final m in blocks.allMatches(src)) {
    final payload = m.group(1)!;
    final base = int.parse(m.group(2)!);
    final count = int.parse(m.group(3)!);
    final words = m.group(4)!.split('|');

    String enc(int n) {
      if (n == 0) return '0';
      var s = '';
      var v = n;
      while (v > 0) {
        s = digits[v % base] + s;
        v ~/= base;
      }
      return s;
    }

    final table = <String, String>{};
    for (var i = 0; i < count; i++) {
      final key = enc(i);
      table[key] = (i < words.length && words[i].isNotEmpty) ? words[i] : key;
    }

    out.add(payload.replaceAllMapped(
        RegExp(r'\b\w+\b'), (mo) => table[mo.group(0)] ?? mo.group(0)!));
  }
  return out.join('\n');
}

/// Minimal HTML entity unescape — enough to expose iframe URLs that the page
/// HTML-escaped (`&amp;`, `&#x2F;`, `&#47;`, …) before the regex runs.
String _htmlUnescape(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&#38;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#34;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&#039;', "'")
    .replaceAll('&#x2F;', '/')
    .replaceAll('&#47;', '/')
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>');

// --------------------------------------------------------------------------- //
// public entry point
// --------------------------------------------------------------------------- //
/// Resolve a Stardima `play_url` to one-or-more playable streams (mostly HLS).
///
/// Mirrors `resolve()` then runs the player's `extract_stream` for every host in
/// parallel, keeping only the embeds that yield a real stream. Throws
/// [StardimaResolveException] when nothing is playable.
Future<List<ResolvedStream>> resolveStardima(String playUrl) async {
  final code = await hyperwatchingCode(playUrl);
  if (code == null) {
    throw const StardimaResolveException(
        'no hyperwatching player found on play page');
  }
  final embeds = await _serversForCode(code);
  if (embeds.isEmpty) {
    throw const StardimaResolveException(
        'watch page found but no servers resolved');
  }

  final results = await Future.wait(embeds.map((e) async {
    try {
      final info = await _extractStream(e.embedUrl);
      return ResolvedStream(
        server: e.name,
        streamUrl: info.streamUrl,
        type: info.type,
        referer: info.referer,
        userAgent: _ua,
      );
    } catch (_) {
      return null;
    }
  }));

  final streams = results.whereType<ResolvedStream>().toList();
  if (streams.isEmpty) {
    throw const StardimaResolveException(
        'servers found but none produced a playable stream');
  }
  return streams;
}
