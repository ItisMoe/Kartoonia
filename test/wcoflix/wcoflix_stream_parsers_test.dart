import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/services/wcoflix/wcoflix_quality.dart';
import 'package:kartoonia/services/wcoflix/wcoflix_stream_parsers.dart';

String fx(String n) => File('test/fixtures/wcoflix/$n').readAsStringSync();

void main() {
  test('pickEmbedIframe finds the *-js-N frame src', () {
    const html =
        '<iframe rel="nofollow" id="cizgi-js-0" src="https://embed.wcostream.com/inc/embed/index.php?x=1"></iframe>';
    expect(pickEmbedIframe(html), 'https://embed.wcostream.com/inc/embed/index.php?x=1');
  });

  test('pickEmbedIframe finds the 2026 frameNew* embed (no -js-N id)', () {
    // Real shape from wcostream.tv (2026-07): id no longer matches *-js-N,
    // extra attributes, and h=/t= token params on the src.
    const html = '<iframe id="frameNewcizgifilmuploads0" '
        'src="https://embed.wcostream.com/inc/embed/index.php?file=Anime%20English%20Dubbed%2FClevatess%2FS02E01.flv&fullhd=1&pid=1021499&h=f16d&t=1783585612&embed=neptun" '
        'width="530" height="440" frameborder="0" allowfullscreen rel="nofollow" '
        'data-type="wco-embed"></iframe>';
    expect(
        pickEmbedIframe(html),
        'https://embed.wcostream.com/inc/embed/index.php?file=Anime%20English%20Dubbed%2FClevatess%2FS02E01.flv&fullhd=1&pid=1021499&h=f16d&t=1783585612&embed=neptun');
  });

  test('pickEmbedIframe ignores non-player iframes (login checker)', () {
    const html =
        '<iframe src="https://user.wcostream.tv/check-login" style="display: none;" id="login-checker"></iframe>';
    expect(pickEmbedIframe(html), isNull);
  });

  test('getvidLinkUrl handles the getRedirectedUrl(videoUrl) shape', () {
    const html = 'blah getRedirectedUrl(videoUrl) ... '
        r'$.getJSON("/inc/embed/getvidlink.php?v=neptun/x.mp4&embed=neptun&fullhd=1", function(){})';
    expect(getvidLinkUrl(html),
        'https://embed.wcostream.com/inc/embed/getvidlink.php?v=neptun/x.mp4&embed=neptun&fullhd=1&json');
  });

  test('getvidLinkUrl handles the legacy inline shape', () {
    const html = 'x "/inc/embed/getvidlink.php?evid=abc" y';
    expect(getvidLinkUrl(html),
        'https://embed.wcostream.com/inc/embed/getvidlink.php?evid=abc');
  });

  test('hlsSourceUrl finds a <source> m3u8', () {
    const html = '<video><source src="https://h.example/vid/master.m3u8"></video>';
    expect(hlsSourceUrl(html), 'https://h.example/vid/master.m3u8');
  });

  test('parseHlsMaster returns 576/720/1080 + english audio', () {
    final v =
        parseHlsMaster(fx('hls_master.m3u8'), 'https://h.example/vid/master.m3u8');
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
