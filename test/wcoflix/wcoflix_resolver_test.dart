import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/services/wcoflix/wcoflix_quality.dart';
import 'package:kartoonia/services/wcoflix/wcoflix_resolver.dart';

String fx(String n) => File('test/fixtures/wcoflix/$n').readAsStringSync();

void main() {
  test('m3u8 path yields 720p-first ordered HLS streams', () async {
    const epHtml =
        '<iframe id="anime-js-1" src="https://h.example/frame"></iframe>';
    final streams = await resolveWcoflixM3u8(epHtml, fetch: (url) async {
      if (url.contains('frame')) {
        return '<source src="https://h.example/vid/master.m3u8">';
      }
      return fx('hls_master.m3u8');
    });
    expect(streams, isNotEmpty);
    expect(streams.first.quality, WcoQuality.p720); // default 720p first
    expect(streams.first.type, 'hls');
    expect(streams.first.headers['User-Agent'], isNotEmpty);
  });

  test('resolveWcoflix uses getvid hook when set for non-m3u8 pages', () async {
    wcoflixGetvidResolver = (embedUrl) async => {
          WcoQuality.p576: 'https://s/getvid?evid=A',
          WcoQuality.p720: 'https://s/getvid?evid=B',
        };
    addTearDown(() => wcoflixGetvidResolver = null);

    final streams = await resolveWcoflix('https://x/ep', fetch: (url) async {
      return '<iframe id="cizgi-js-0" src="https://embed.wcostream.com/inc/embed/index.php?x=1"></iframe>';
    });
    expect(streams.first.quality, WcoQuality.p720); // 720p first
    expect(streams.first.type, 'mp4');
  });
}
