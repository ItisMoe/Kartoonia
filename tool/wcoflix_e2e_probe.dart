// Clean end-to-end: episode -> video-js.php (retry on announcement) -> getvid
// JSON -> byte-check IMMEDIATELY (fresh token). Proves the playback fix works.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../lib/services/wcoflix/wcoflix_config.dart';
import '../lib/services/wcoflix/wcoflix_parsers.dart';
import '../lib/services/wcoflix/wcoflix_stream_parsers.dart';
import '../lib/services/wcoflix/wcoflix_quality.dart';

const base = 'https://www.wcofun.net';
final _rand = Random.secure();
String _nonce() => List.generate(
    16, (_) => _rand.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

Future<void> main(List<String> args) async {
  final c = http.Client();
  final ua = {'User-Agent': kWcoflixUserAgent};
  final episodeUrl = args.isNotEmpty
      ? (args.first.startsWith('http') ? args.first : '$base${args.first}')
      : '$base/goodbye-lara-episode-1-english-subbed';
  stdout.writeln('page: $episodeUrl');

  final ep = await c.get(Uri.parse(episodeUrl), headers: ua);
  final embed = pickEmbedIframe(ep.body)!
      .replaceAll('&#038;', '&')
      .replaceAll('&amp;', '&');
  final pid = RegExp(r'[&?]pid=([0-9]+)').firstMatch(embed)?.group(1) ?? '';

  String? playerHtml;
  for (var attempt = 1; attempt <= 4 && playerHtml == null; attempt++) {
    final nonce = _nonce();
    final ms = DateTime.now().millisecondsSinceEpoch;
    final flag = '__abd_${_rand.nextInt(1 << 32).toRadixString(16)}';
    await c.get(
        Uri.parse('$kWcoflixEmbedHost/assets/ads/advertisement.js?flag=$flag&_=$ms'),
        headers: {...ua, 'Accept': '*/*', 'Referer': embed});
    await c.post(Uri.parse('$kWcoflixEmbedHost/ad-verify'),
        headers: {...ua, 'Content-Type': 'application/json', 'Referer': embed},
        body: jsonEncode({'nonce': nonce, 'status': 'clear', 'id': pid}));
    await Future<void>.delayed(const Duration(seconds: 5));
    final url = embed.replaceFirst('index.php', 'video-js.php') + '&n=$nonce';
    final r = await c.get(Uri.parse(url), headers: {...ua, 'Referer': embed});
    final ok = r.body.contains('getvid?evid') || r.body.contains('m3u8');
    stdout.writeln('attempt $attempt: HTTP ${r.statusCode} ok=$ok '
        'announce=${r.body.contains('PREMIUM')}');
    if (ok) playerHtml = r.body;
    else await Future<void>.delayed(const Duration(seconds: 3));
  }
  if (playerHtml == null) {
    stdout.writeln('FAIL: never got a real player page');
    exit(1);
  }

  final link = getvidLinkUrl(playerHtml);
  if (link == null) {
    stdout.writeln('hls=${hlsSourceUrl(playerHtml)}');
    exit(0);
  }
  final j = await c.get(Uri.parse(link), headers: {
    ...ua, 'Referer': '$kWcoflixEmbedHost/', 'Accept': '*/*',
    'X-Requested-With': 'XMLHttpRequest'
  });
  final data = jsonDecode(j.body) as Map<String, dynamic>;
  final urls = parseGetvidJson(data);
  final want = urls[WcoQuality.p720] ?? urls.values.first;
  stdout.writeln('media url: ${want.substring(0, want.length.clamp(0, 90))}...');
  final req = http.Request('GET', Uri.parse(want))
    ..headers.addAll({...kWcoflixMediaHeaders, 'Range': 'bytes=0-1023'})
    ..followRedirects = true;
  final resp = await http.Client().send(req);
  stdout.writeln('MEDIA: HTTP ${resp.statusCode} '
      'ct=${resp.headers['content-type']} '
      'range=${resp.headers['content-range']}');
  exit(resp.statusCode == 200 || resp.statusCode == 206 ? 0 : 1);
}
