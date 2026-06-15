import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/services/stardima_resolver.dart';

void main() {
  group('hyperwatchingCodeFromHtml', () {
    test('finds the iframe code from a plain iframe src', () {
      const html =
          '<iframe src="https://hyperwatching.com/iframe/abc_DEF-123"></iframe>';
      expect(hyperwatchingCodeFromHtml(html), 'abc_DEF-123');
    });

    test('finds the code via the www host', () {
      const html = 'x = "https://www.hyperwatching.com/iframe/Zz09";';
      expect(hyperwatchingCodeFromHtml(html), 'Zz09');
    });

    test('finds the code inside a JSON watch_url', () {
      const html =
          '{"watch_url":"https:\\/\\/hyperwatching.com\\/iframe\\/q1w2e3"}';
      // The escaped slashes are html-unescaped/handled by the pattern set.
      expect(hyperwatchingCodeFromHtml(html.replaceAll(r'\/', '/')), 'q1w2e3');
    });

    test('handles html-escaped ampersands around the url', () {
      const html =
          '&lt;meta property="og:video" content="https://hyperwatching.com/iframe/k9k9"&gt;';
      expect(hyperwatchingCodeFromHtml(html), 'k9k9');
    });

    test('returns null when no iframe present', () {
      expect(hyperwatchingCodeFromHtml('<html>nothing here</html>'), isNull);
    });
  });

  group('parseIframeServers', () {
    test('extracts csrf token and the server list', () {
      const html = '''
        var config = { csrf: "tok3n-value", other: 1 };
        servers = [ {id:"3", name:"Lulustream"}, {id:"5", name:"Streamhg"} ];
      ''';
      final r = parseIframeServers(html);
      expect(r.csrf, 'tok3n-value');
      expect(r.servers.length, 2);
      expect(r.servers[0], ('3', 'Lulustream'));
      expect(r.servers[1], ('5', 'Streamhg'));
    });

    test('null csrf when absent', () {
      final r = parseIframeServers('id:"1", name:"X"');
      expect(r.csrf, isNull);
      expect(r.servers.single, ('1', 'X'));
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
