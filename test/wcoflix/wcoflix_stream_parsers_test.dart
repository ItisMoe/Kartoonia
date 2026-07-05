import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/services/wcoflix/wcoflix_quality.dart';
import 'package:kartoonia/services/wcoflix/wcoflix_stream_parsers.dart';

String fx(String n) => File('test/fixtures/wcoflix/$n').readAsStringSync();

void main() {
  test('pickEmbedIframe finds cizgi-js-0 frame src', () {
    const html =
        '<iframe id="cizgi-js-0" src="https://embed.wcostream.com/inc/embed/index.php?x=1"></iframe>';
    expect(pickEmbedIframe(html), contains('index.php?x=1'));
    expect(isM3u8Embed(html), isFalse);
  });

  test('isM3u8Embed true for anime-js-1 alone', () {
    const html = '<iframe id="anime-js-1" src="https://h.example/frame"></iframe>';
    expect(isM3u8Embed(html), isTrue);
  });

  test('isM3u8Embed false when anime-js-0 also present', () {
    const html = '<iframe id="anime-js-0" src="a"></iframe>'
        '<iframe id="anime-js-1" src="b"></iframe>';
    expect(isM3u8Embed(html), isFalse);
  });

  test('parseHlsMaster returns 576/720/1080 + english audio', () {
    final v = parseHlsMaster(fx('hls_master.m3u8'), 'https://h.example/vid/master.m3u8');
    expect(v.map((e) => e.quality).toSet(),
        {WcoQuality.p576, WcoQuality.p720, WcoQuality.p1080});
    final p720 = v.firstWhere((e) => e.quality == WcoQuality.p720);
    expect(p720.url, 'https://h.example/vid/720/index.m3u8');
    expect(p720.audioUrl, 'https://h.example/vid/eng/audio.m3u8');
  });

  test('parseGetvidJson builds getvid urls', () {
    final j = jsonDecode(fx('getvidlink.json')) as Map<String, dynamic>;
    final m = parseGetvidJson(j);
    expect(m[WcoQuality.p720], 'https://cizgy.wcostream.com/getvid?evid=HD720');
    expect(m[WcoQuality.p1080], 'https://cizgy.wcostream.com/getvid?evid=FHD1080');
    expect(m[WcoQuality.p576], 'https://cizgy.wcostream.com/getvid?evid=ENC576');
  });
}
