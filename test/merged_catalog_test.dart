import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/services/catalog_service.dart';
import 'package:kartoonia/models/catalog_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loadMerged contains items from both sources', () async {
    final svc = await CatalogService.loadMerged();
    final at = svc.all.where((i) => i.source == CatalogSource.arabicToons);
    final st = svc.all.where((i) => i.source == CatalogSource.stardima);
    expect(at, isNotEmpty);
    expect(st, isNotEmpty);
  });

  test('duplicated titles collapse to the Arabic Toons primary', () async {
    final svc = await CatalogService.loadMerged();
    // Any item in `all` that has a twin must be the Arabic Toons primary.
    for (final i in svc.all) {
      final alt = svc.alternateFor(i);
      if (alt != null) {
        expect(i.source, CatalogSource.arabicToons,
            reason: 'collapsed list should expose the Arabic Toons primary');
        expect(alt.source, CatalogSource.stardima);
        expect(svc.primaryFor(alt).id, i.id,
            reason: 'primaryFor(stardima twin) resolves to the AT primary');
      }
    }
  });

  test('alternateFor is symmetric and null for single-source titles', () async {
    final svc = await CatalogService.loadMerged();
    var pairs = 0;
    for (final i in svc.all) {
      final alt = svc.alternateFor(i);
      if (alt != null) {
        pairs++;
        // Round-trip: the alternate's alternate is the original.
        expect(svc.alternateFor(alt)?.id, i.id);
      }
      if (i.tmdbId == null) expect(alt, isNull);
    }
    expect(pairs, greaterThan(0), reason: 'fixtures contain shared titles');
  });

  test('both twin ids still resolve via getById', () async {
    final svc = await CatalogService.loadMerged();
    final dup = svc.all.firstWhere((i) => svc.alternateFor(i) != null);
    final alt = svc.alternateFor(dup)!;
    expect(svc.getById(dup.id), isNotNull);
    expect(svc.getById(alt.id), isNotNull);
  });

  test('isDuplicated is false for items without a tmdbId', () async {
    final svc = await CatalogService.loadMerged();
    for (final i in svc.all) {
      if (i.tmdbId == null) expect(svc.isDuplicated(i), isFalse);
    }
  });
}
