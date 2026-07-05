import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'wcoflix_config.dart';
import 'wcoflix_quality.dart';
import 'wcoflix_stream_parsers.dart';

/// One resolved WCOFlix stream: a ready-to-open URL for a single quality plus
/// the headers the CDN requires. `type` is 'mp4' (getvid) or 'hls'.
class WcoStream {
  final WcoQuality quality;
  final String url;
  final String type;
  final Map<String, String> headers;
  const WcoStream(this.quality, this.url, this.type, this.headers);
}

/// Thrown when an episode/movie page can't be turned into any playable stream.
class WcoflixResolveException implements Exception {
  final String message;
  const WcoflixResolveException(this.message);
  @override
  String toString() => 'WcoflixResolveException: $message';
}

/// Simple I/O seam so the resolver's logic can be driven with fixtures in tests.
/// [get] does a GET (returns body); [post] does a POST with a raw body.
abstract class WcoHttp {
  Future<String> get(String url, {Map<String, String>? headers});
  Future<void> post(String url, String body, {Map<String, String>? headers});
  Future<void> sleep(Duration d);
}

class _RealHttp implements WcoHttp {
  final http.Client _c = http.Client();
  @override
  Future<String> get(String url, {Map<String, String>? headers}) async =>
      (await _c.get(Uri.parse(url), headers: headers)).body;
  @override
  Future<void> post(String url, String body,
          {Map<String, String>? headers}) async =>
      _c.post(Uri.parse(url), headers: headers, body: body);
  @override
  Future<void> sleep(Duration d) => Future<void>.delayed(d);
}

final _rand = Random.secure();
String _nonce() =>
    List.generate(16, (_) => _rand.nextInt(256).toRadixString(16).padLeft(2, '0'))
        .join();

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

/// Resolve a WCOFlix episode/movie page to per-quality streams (720p first),
/// exactly the way the WatchNixtoons2 Kodi addon does it — pure HTTP, no
/// browser/iframe:
///
///   1. episode page  -> the `*-js-N` player iframe (`.../inc/embed/index.php`)
///   2. ad-gate bypass -> GET the ad-bait, POST `/ad-verify` a `clear` nonce,
///      then request `video-js-old.php?...&n=<nonce>` (the legacy player that
///      isn't ad-walled). A short dwell after `/ad-verify` is required.
///   3. player HTML   -> a getvid `$.getJSON` link -> JSON `{enc,hd,fhd,server}`
///      -> `server/getvid?evid=<token>` mp4 (enc=576, hd=720, fhd=1080), OR a
///      plain HLS `<source>` for the non-getvid embeds.
///
/// [http] is injectable for tests; [dwell] is the post-`ad-verify` wait.
Future<List<WcoStream>> resolveWcoflix(
  String pageUrl, {
  WcoHttp? http,
  Duration dwell = const Duration(seconds: 5),
}) async {
  final io = http ?? _RealHttp();
  final headers = {'User-Agent': kWcoflixUserAgent};

  final epHtml = await io.get(pageUrl, headers: headers);
  var embed = pickEmbedIframe(epHtml);
  if (embed == null) {
    throw const WcoflixResolveException('no player iframe on the episode page');
  }
  embed = embed.replaceAll('&#038;', '&').replaceAll('&amp;', '&');

  // Ad-gate bypass for the wcostream index.php embed.
  if (embed.contains('inc/embed/index.php')) {
    final pid = RegExp(r'[&?]pid=([0-9]+)').firstMatch(embed)?.group(1) ?? '';
    final nonce = _nonce();
    final flag = '__abd_${_rand.nextInt(1 << 32).toRadixString(16)}';
    final ms = DateTime.now().millisecondsSinceEpoch;
    await io.get(
      '$kWcoflixEmbedHost/assets/ads/advertisement.js?flag=$flag&_=$ms',
      headers: {...headers, 'Accept': '*/*', 'Referer': embed},
    );
    await io.post(
      '$kWcoflixEmbedHost/ad-verify',
      jsonEncode({'nonce': nonce, 'status': 'clear', 'id': pid}),
      headers: {...headers, 'Content-Type': 'application/json', 'Referer': embed},
    );
    final player =
        '${embed.replaceFirst('inc/embed/index.php', 'inc/embed/video-js-old.php')}&n=$nonce';
    await io.sleep(dwell);
    return _fromPlayer(io, player, embed);
  }

  // Non-index embeds: request directly.
  return _fromPlayer(io, embed, embed);
}

/// Fetch the player page and turn it into ordered streams.
Future<List<WcoStream>> _fromPlayer(
    WcoHttp io, String playerUrl, String referer) async {
  final headers = {'User-Agent': kWcoflixUserAgent, 'Referer': referer};
  final html = await io.get(playerUrl, headers: headers);

  if (html.contains('high volume of requests')) {
    throw const WcoflixResolveException(
        'server temporarily blocking free videos');
  }

  // getvid path (the common one): JSON tokens -> server/getvid?evid=...
  if (html.contains('getvid?evid')) {
    final linkUrl = getvidLinkUrl(html);
    if (linkUrl == null) {
      throw const WcoflixResolveException('getvid player but no getvidlink URL');
    }
    final jsonText = await io.get(linkUrl, headers: {
      ...headers,
      'Accept': '*/*',
      'X-Requested-With': 'XMLHttpRequest',
    });
    final data = jsonDecode(jsonText) as Map<String, dynamic>;
    final urls = parseGetvidJson(data);
    final mediaHeaders = kWcoflixMediaHeaders;
    final streams = [
      for (final e in urls.entries)
        WcoStream(e.key, e.value, 'mp4', mediaHeaders),
    ];
    if (streams.isEmpty) {
      throw const WcoflixResolveException('getvidlink returned no tokens');
    }
    return _order(streams);
  }

  // Plain HLS embed: single master with in-stream variants (libmpv adapts).
  final hls = hlsSourceUrl(html);
  if (hls != null) {
    return [
      WcoStream(WcoQuality.p1080, hls, 'hls', {
        'User-Agent': kWcoflixUserAgent,
        'Referer': _origin(playerUrl),
      }),
    ];
  }

  throw const WcoflixResolveException('no getvid or HLS source in player page');
}
