import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/models/catalog_source.dart';
import 'package:kartoonia/services/wcoflix/wcoflix_config.dart';

void main() {
  test('wcoflix source exists and is not asset-backed', () {
    expect(CatalogSource.wcoflix.id, 'wcoflix');
    expect(CatalogSource.wcoflix.assetPath, isEmpty);
    expect(CatalogSource.fromId('wcoflix'), CatalogSource.wcoflix);
  });
  test('unknown id still falls back to arabicToons', () {
    expect(CatalogSource.fromId('nope'), CatalogSource.arabicToons);
  });
  test('config constants', () {
    // wcoflix.tv is the canonical mirror (wcofun.net 301-redirects to it); it
    // must be probed first so series pages arrive with their seasons/episodes.
    expect(wcoflixBaseUrls.first, 'https://www.wcoflix.tv');
    expect(kWcoflixEmbedHost, 'https://embed.wcostream.com');
    expect(kWcoflixMediaHeaders['Referer'], 'https://embed.wcostream.com/');
    // The getvid CDN binds tokens to this exact UA; must stay Chrome/149 in both
    // the resolve and playback paths (they share this one constant).
    expect(kWcoflixUserAgent, contains('Chrome/149'));
    expect(kWcoflixMediaHeaders['User-Agent'], contains('Chrome/149'));
  });
}
