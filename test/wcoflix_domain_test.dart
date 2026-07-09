import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/services/wcoflix/wcoflix_domain.dart';

void main() {
  setUp(WcoflixDomain.resetForTest);

  group('rewrite', () {
    const base = 'https://www.wcofun.net';

    test('rehomes a dead-mirror absolute URL onto the active base', () {
      expect(
        WcoflixDomain.rewrite(
            'https://www.wcoflix.tv/anime/one-piece', base),
        'https://www.wcofun.net/anime/one-piece',
      );
    });

    test('keeps query strings when rehoming', () {
      expect(
        WcoflixDomain.rewrite(
            'https://www.wcoflix.tv/x?season=all&lang=dub', base),
        'https://www.wcofun.net/x?season=all&lang=dub',
      );
    });

    test('absolutizes a relative path against the active base', () {
      expect(WcoflixDomain.rewrite('/anime/naruto', base),
          'https://www.wcofun.net/anime/naruto');
      expect(WcoflixDomain.rewrite('anime/naruto', base),
          'https://www.wcofun.net/anime/naruto');
    });

    test('leaves the playback embed host untouched', () {
      const embed =
          'https://embed.wcostream.com/inc/embed/index.php?pid=1&embed=neptun';
      expect(WcoflixDomain.rewrite(embed, base), embed);
    });

    test('leaves a URL already on the active base unchanged', () {
      const u = 'https://www.wcofun.net/anime/bleach';
      expect(WcoflixDomain.rewrite(u, base), u);
    });
  });

  group('activeBase', () {
    test('picks the first mirror that serves real HTML', () async {
      final hit = <String>[];
      final base = await WcoflixDomain.activeBase((url) async {
        hit.add(url);
        // Primary (wcofun.net) is Cloudflare-challenged; the next serves content.
        if (url.contains('wcofun.net')) return '<html>Just a moment...</html>';
        return '<html><div class="sidebar-titles"></div></html>';
      });
      expect(base, 'https://www.wcostream.tv');
      expect(hit.first, contains('wcofun.net')); // tried the primary first
    });

    test('caches the resolved mirror (probes once)', () async {
      var calls = 0;
      Future<String> get(String url) async {
        calls++;
        return '<html>real</html>';
      }

      final a = await WcoflixDomain.activeBase(get);
      final b = await WcoflixDomain.activeBase(get);
      expect(a, b);
      expect(calls, 1);
    });

    test('falls back to the primary base when every mirror is blocked',
        () async {
      final base = await WcoflixDomain.activeBase(
          (_) async => '<html>Just a moment</html>');
      expect(base, 'https://www.wcofun.net');
    });
  });
}
