import 'dart:convert';
import 'package:http/http.dart' as http;

/// Dart port of `resolver_scripts/stardima_resolver.py` + the stream-extraction
/// half of `stardima_player.py`.
///
/// Stardima items expose only a `play_url`. Turning that into something a video
/// player can open is a three-stage pipeline (mirrors the Python flow exactly —
/// same URLs, headers, referers and regexes):
///
///   1. play page          -> hyperwatching iframe `code`
///   2. iframe `code`      -> per-host embed links  (csrf + POST /link)
///   3. each embed page    -> the real `.m3u8` / `.mp4` stream URL
///
/// The Python VLC player additionally forces the Arabic audio rendition by
/// injecting `--audio-language` into LibVLC. `video_player` (ExoPlayer) exposes
/// no track-selection API, so we play the master manifest and let the engine
/// pick the default rendition — the request flow/headers are otherwise identical.

const String _star = 'https://www.stardima.com';
const String _hw = 'https://hyperwatching.com';
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
// 1) play page  ->  hyperwatching iframe code
// --------------------------------------------------------------------------- //
final List<RegExp> _codePatterns = [
  RegExp(r'https?://(?:www\.)?hyperwatching\.com/iframe/([A-Za-z0-9_\-]+)'),
  RegExp(r'"watch_url"\s*:\s*"[^"]*?/iframe/([A-Za-z0-9_\-]+)"'),
  RegExp(r'og:video"\s+content="[^"]*?/iframe/([A-Za-z0-9_\-]+)"'),
];

/// Pure: find the hyperwatching iframe code in already-fetched play-page HTML.
/// Exposed for testing; mirrors the Python `_hyperwatching_code` regexes.
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
// 2 + 3) iframe code  ->  per-host embed links
// --------------------------------------------------------------------------- //
/// Pure: parse the csrf token + `(id, name)` server list out of iframe HTML.
/// Exposed for testing; mirrors the Python `servers_for_code` regexes.
({String? csrf, List<(String, String)> servers}) parseIframeServers(
    String html) {
  final csrfMatch = RegExp(r'csrf:\s*"([^"]+)"').firstMatch(html);
  final servers = RegExp(r'id:\s*"(\d+)",\s*name:\s*"([^"]+)"')
      .allMatches(html)
      .map((m) => (m.group(1)!, m.group(2)!))
      .toList();
  return (csrf: csrfMatch?.group(1), servers: servers);
}

Future<List<_EmbedServer>> _serversForCode(String code) async {
  final iframe = '$_hw/iframe/$code';
  final res = await _client.get(
    Uri.parse(iframe),
    headers: {
      'User-Agent': _ua,
      'Accept-Language': 'ar,en;q=0.9',
      'Referer': '$_star/',
    },
  ).timeout(_timeout);

  final parsed = parseIframeServers(res.body);
  if (parsed.csrf == null) return const [];
  final csrf = parsed.csrf!;

  final headers = {
    'Content-Type': 'application/json',
    'X-CSRF-TOKEN': csrf,
    'X-Requested-With': 'XMLHttpRequest',
    'Referer': iframe,
    'Origin': _hw,
    'User-Agent': _ua,
  };

  final out = <_EmbedServer>[];
  for (final (sid, sname) in parsed.servers) {
    try {
      final r = await _client
          .post(
            Uri.parse('$_hw/api/videos/$code/link'),
            headers: headers,
            body: jsonEncode({'server_link_id': sid}),
          )
          .timeout(_timeout);
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final watch = j['watch_url'];
      if (watch is String && watch.isNotEmpty) {
        out.add(_EmbedServer(sname, watch));
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
        'no hyperwatching iframe found on play page');
  }
  final embeds = await _serversForCode(code);
  if (embeds.isEmpty) {
    throw const StardimaResolveException(
        'iframe found but no servers resolved');
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
