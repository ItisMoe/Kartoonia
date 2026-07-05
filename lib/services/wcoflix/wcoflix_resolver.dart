import 'package:http/http.dart' as http;
import 'wcoflix_config.dart';
import 'wcoflix_quality.dart';
import 'wcoflix_stream_parsers.dart';

/// One resolved WCOFlix stream: a ready-to-open URL for a single quality, plus
/// the headers the CDN requires and (for HLS) the separate English audio track.
class WcoStream {
  final WcoQuality quality;
  final String url;
  final String type; // 'hls' | 'mp4'
  final Map<String, String> headers;
  final String? audioUrl;
  const WcoStream(this.quality, this.url, this.type, this.headers,
      {this.audioUrl});
}

/// Phase-2 hook: resolve the ad-gated getvid embed to per-quality URLs via a
/// headless WebView. Null in Phase 1 — m3u8 (anime-js-1) titles still play, and
/// getvid-only titles surface as "unavailable" until Phase 2 wires this up.
Future<Map<WcoQuality, String>> Function(String embedUrl)? wcoflixGetvidResolver;

final http.Client _client = http.Client();
Future<String> _get(String url) async {
  final res = await _client
      .get(Uri.parse(url), headers: {'User-Agent': kWcoflixUserAgent});
  return res.body;
}

String _origin(String url) {
  final u = Uri.tryParse(url);
  if (u == null || u.host.isEmpty) return url;
  return '${u.scheme}://${u.host}/';
}

/// Order resolved qualities so the 720p-default (via [WcoQuality.best]) is
/// first (the player selects `number:1`), then the rest highest-first.
List<WcoStream> _order(List<WcoStream> s) {
  if (s.isEmpty) return s;
  final want = WcoQuality.best(WcoQuality.p720, s.map((e) => e.quality).toList());
  s.sort((a, b) {
    if (a.quality == want && b.quality != want) return -1;
    if (b.quality == want && a.quality != want) return 1;
    return b.quality.resolution.compareTo(a.quality.resolution);
  });
  return s;
}

final _reMasterBare = RegExp(r'''https?:[^\s"']+\.m3u8''');
final _reMasterAttr = RegExp(r'''src="([^"]+\.m3u8)"''');

/// Pure-HTTP HLS path: episode HTML → anime-js-1 frame → index.m3u8 master →
/// per-resolution HLS streams (720p first). [fetch] is injectable for tests.
Future<List<WcoStream>> resolveWcoflixM3u8(String episodeHtml,
    {Future<String> Function(String)? fetch}) async {
  final get = fetch ?? _get;
  final frame = pickEmbedIframe(episodeHtml);
  if (frame == null) return const [];
  final frameHtml = await get(frame);
  final attr = _reMasterAttr.firstMatch(frameHtml);
  final masterUrl = attr != null
      ? attr.group(1)!
      : _reMasterBare.firstMatch(frameHtml)?.group(0);
  if (masterUrl == null) return const [];
  final masterText = await get(masterUrl);
  final referer = _origin(frame);
  final variants = parseHlsMaster(masterText, masterUrl);
  return _order([
    for (final v in variants)
      WcoStream(v.quality, v.url, 'hls',
          {'User-Agent': kWcoflixUserAgent, 'Referer': referer},
          audioUrl: v.audioUrl),
  ]);
}

/// Full episode/movie resolve: HLS when the page uses the anime-js-1 embed,
/// otherwise the getvid embed via the Phase-2 [wcoflixGetvidResolver] hook,
/// falling back to an HLS attempt (some pages carry both). [fetch] injectable.
Future<List<WcoStream>> resolveWcoflix(String pageUrl,
    {Future<String> Function(String)? fetch}) async {
  final get = fetch ?? _get;
  final epHtml = await get(pageUrl);
  if (!isM3u8Embed(epHtml)) {
    final frame = pickEmbedIframe(epHtml);
    final hook = wcoflixGetvidResolver;
    if (frame != null && hook != null) {
      final map = await hook(frame);
      final streams = [
        for (final e in map.entries)
          WcoStream(e.key, e.value, 'mp4', kWcoflixMediaHeaders),
      ];
      if (streams.isNotEmpty) return _order(streams);
    }
  }
  return resolveWcoflixM3u8(epHtml, fetch: get);
}
