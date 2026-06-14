import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/services/token_service.dart';

void main() {
  group('extractServerLinks', () {
    test('extracts numbered server vars sorted by number', () {
      const html = '''
        <script>
          var server2 = "https://stream.foupix.com:8443/x/2/ep.mp4?tkn=bbb&tms=2";
          var server1 = "https://stream.foupix.com:8443/x/1/ep.mp4?tkn=aaa&tms=1";
        </script>
      ''';
      final links = extractServerLinks(html);
      expect(links.length, 2);
      expect(links[0].serverNumber, 1);
      expect(links[1].serverNumber, 2);
      expect(links[0].cleanUrl,
          'https://stream.foupix.com:8443/x/1/ep.mp4');
      expect(links[0].rawUrl.contains('tkn=aaa'), isTrue);
    });

    test('extracts single videoSrc as server 1', () {
      const html =
          'const videoSrc = "https://stream.foupix.com:8443/y/movie.mp4?tkn=zzz&tms=9";';
      final links = extractServerLinks(html);
      expect(links.length, 1);
      expect(links.first.serverNumber, 1);
      expect(links.first.cleanUrl,
          'https://stream.foupix.com:8443/y/movie.mp4');
    });

    test('fallback src/data-src for media extensions', () {
      const html =
          '<source src="https://cdn.example.com/path/clip.m3u8?a=1" />';
      final links = extractServerLinks(html);
      expect(links.length, 1);
      expect(links.first.cleanUrl, 'https://cdn.example.com/path/clip.m3u8');
    });

    test('ignores non-http and extensionless urls', () {
      const html = '''
        var server1 = "ftp://nope.example.com/file.mp4?tkn=aaaaaaaaaaaaaaaa";
        var server2 = "https://no-extension-here.example.com/playlong?tkn=bbbbbbbbbbb";
      ''';
      final links = extractServerLinks(html);
      expect(links, isEmpty);
    });

    test('dedupes same server number', () {
      const html = '''
        var server1 = "https://a.example.com/one.mp4?tkn=aaaaaaaaaaaaaaaa";
        var server1 = "https://a.example.com/two.mp4?tkn=bbbbbbbbbbbbbbbb";
      ''';
      final links = extractServerLinks(html);
      expect(links.length, 1);
      expect(links.first.cleanUrl, 'https://a.example.com/one.mp4');
    });
  });
}
