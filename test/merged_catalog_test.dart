import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/services/catalog_service.dart';
import 'package:kartoonia/models/catalog_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loadMerged contains items from both sources', () async {
    final svc = await CatalogService.loadMerged();
    final sources = svc.all.map((i) => i.source).toSet();
    expect(
        sources,
        containsAll(<CatalogSource>{
          CatalogSource.arabicToons,
          CatalogSource.stardima,
        }));
    final at = svc.all.where((i) => i.source == CatalogSource.arabicToons);
    final st = svc.all.where((i) => i.source == CatalogSource.stardima);
    expect(at, isNotEmpty);
    expect(st, isNotEmpty);
    // No dedup: total equals sum of both source lists.
    expect(svc.all.length, at.length + st.length);
  });

  test('isDuplicated is false for items without a tmdbId', () async {
    final svc = await CatalogService.loadMerged();
    for (final i in svc.all) {
      if (i.tmdbId == null) {
        expect(svc.isDuplicated(i), isFalse);
      }
    }
  });
}
