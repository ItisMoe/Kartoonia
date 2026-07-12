import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/models/catalog_source.dart';
import 'package:kartoonia/models/library_mode.dart';

void main() {
  test('mode → bundled sources + wcoflix flags', () {
    expect(LibraryMode.dubbed.bundled,
        {CatalogSource.arabicToons, CatalogSource.stardima});
    expect(LibraryMode.carateen.bundled, {CatalogSource.carateen});
    expect(LibraryMode.arabic.bundled, {
      CatalogSource.arabicToons,
      CatalogSource.stardima,
      CatalogSource.carateen
    });
    expect(LibraryMode.wcoflix.showsArabic, isFalse);
    expect(LibraryMode.wcoflix.isWcoflixOnly, isTrue);
    expect(LibraryMode.everything.showsWcoflix, isTrue);
    expect(LibraryMode.everything.showsArabic, isTrue);
    expect(LibraryMode.everything.isWcoflixOnly, isFalse);
  });

  test('fromId round-trips and defaults to arabic', () {
    for (final m in LibraryMode.values) {
      expect(LibraryMode.fromId(m.id), m);
    }
    expect(LibraryMode.fromId('nonsense'), LibraryMode.arabic);
    expect(LibraryMode.fromId(null), LibraryMode.arabic);
  });
}
