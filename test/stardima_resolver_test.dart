import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/services/stardima_resolver.dart';

void main() {
  group('hyperwatchingCodeFromHtml', () {
    test('finds the v2 hashid from a plain iframe src', () {
      const html =
          '<iframe src="https://v2.hyperwatching.com/watch/B5yQl3W07FFa"></iframe>';
      expect(hyperwatchingCodeFromHtml(html), 'B5yQl3W07FFa');
    });

    test('finds the hashid inside an og:video meta tag', () {
      const html =
          '<meta property="og:video" content="https://v2.hyperwatching.com/watch/Zz09_x">';
      expect(hyperwatchingCodeFromHtml(html), 'Zz09_x');
    });

    test('still finds the legacy /iframe/ code', () {
      const html = 'x = "https://www.hyperwatching.com/iframe/q1w2e3";';
      expect(hyperwatchingCodeFromHtml(html), 'q1w2e3');
    });

    test('handles html-escaped markup around the url', () {
      const html =
          '&lt;meta content="https://v2.hyperwatching.com/watch/k9k9"&gt;';
      expect(hyperwatchingCodeFromHtml(html), 'k9k9');
    });

    test('returns null when no player present', () {
      expect(hyperwatchingCodeFromHtml('<html>nothing here</html>'), isNull);
    });
  });

  group('parseWatchServers', () {
    // The v2 watch page: csrf in a meta tag, servers as HTML-escaped JSON in
    // the Inertia `data-page` attribute.
    const page = '<meta name="csrf-token" content="tok3n-value">'
        '<div id="app" data-page="{&quot;props&quot;:{&quot;video&quot;:{'
        '&quot;hashid&quot;:&quot;ABC&quot;,&quot;servers&quot;:['
        '{&quot;id&quot;:496847,&quot;name&quot;:&quot;Uqload&quot;,&quot;status&quot;:&quot;completed&quot;},'
        '{&quot;id&quot;:0,&quot;name&quot;:&quot;Goodstream&quot;,&quot;status&quot;:&quot;processing&quot;},'
        '{&quot;id&quot;:496850,&quot;name&quot;:&quot;Lulustream&quot;,&quot;status&quot;:&quot;completed&quot;}'
        ']}}}"></div>';

    test('extracts csrf and only the completed, non-zero-id servers', () {
      final r = parseWatchServers(page);
      expect(r.csrf, 'tok3n-value');
      expect(r.servers, [('496847', 'Uqload'), ('496850', 'Lulustream')]);
    });

    test('empty server list when data-page is absent', () {
      final r = parseWatchServers('<meta name="csrf-token" content="t">');
      expect(r.csrf, 't');
      expect(r.servers, isEmpty);
    });
  });

  group('embedHostFromWatchUrl', () {
    test('decodes the real host embed from a strema.top wrapper', () {
      const w =
          'https://strema.top/embed2/?id=https%3A%2F%2Fuqload.is%2Fembed-gz3ij5i6km4o.html';
      expect(embedHostFromWatchUrl(w), 'https://uqload.is/embed-gz3ij5i6km4o.html');
    });

    test('returns a non-wrapper url unchanged', () {
      const w = 'https://lulustream.com/e/qp2v5e8pqtv1';
      expect(embedHostFromWatchUrl(w), w);
    });
  });

  group('bestStreamUrl', () {
    test('prefers master.m3u8 over other streams', () {
      const html = '''
        source: "https://cdn.example.com/hls/index-v1.m3u8?t=1"
        master: "https://cdn.example.com/hls/master.m3u8?t=1"
        mp4:    "https://cdn.example.com/file.mp4"
      ''';
      expect(bestStreamUrl(html),
          'https://cdn.example.com/hls/master.m3u8?t=1');
    });

    test('falls back to mp4 when no hls', () {
      const html = 'file: "https://cdn.example.com/video/clip.mp4?x=9"';
      expect(bestStreamUrl(html), 'https://cdn.example.com/video/clip.mp4?x=9');
    });

    test('un-escapes escaped leading slashes in the matched url', () {
      // Mirrors the Python regex: leading https:\/\/ may be escaped; interior
      // slashes are literal (its char-class excludes backslashes).
      const html = r'"file":"https:\/\/cdn.host/a/b/master.m3u8"';
      expect(bestStreamUrl(html), 'https://cdn.host/a/b/master.m3u8');
    });

    test('returns null when there is no media url', () {
      expect(bestStreamUrl('<html>no streams</html>'), isNull);
    });

    test('extracts a url hidden inside a packed JS block', () {
      // p,a,c,k,e,d block whose dictionary holds the stream pieces. Word
      // dictionary indices: 0=https,1=cdn,2=com,3=master,4=m3u8 ...
      // Token "5" (base) maps base36 single-chars to words. We build a tiny one.
      const packed =
          r"""eval(function(p,a,c,k,e,d){return p}('0://1.2/3.4',36,5,'https|cdn|com|master|m3u8'.split('|'),0,{}))""";
      final unpacked = unpackPacked(packed);
      expect(unpacked.contains('https://cdn.com/master.m3u8'), isTrue);
      expect(bestStreamUrl(packed), 'https://cdn.com/master.m3u8');
    });
  });
}
