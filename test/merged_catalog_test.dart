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

  test('duplicated titles collapse to the group primary', () async {
    final svc = await CatalogService.loadMerged();
    // With three normal-mode sources (Arabic Toons / Stardima / Carateen) the
    // collapsed list exposes each group's highest-priority member. Every item in
    // `all` that has a twin must therefore BE that primary, and every twin must
    // resolve back to it and come from a different source.
    for (final i in svc.all) {
      final alts = svc.alternatesFor(i);
      if (alts.isNotEmpty) {
        expect(svc.primaryFor(i).id, i.id,
            reason: 'collapsed list should expose the group primary');
        for (final a in alts) {
          expect(a.source, isNot(i.source));
          expect(svc.primaryFor(a).id, i.id,
              reason: 'primaryFor(twin) resolves to the primary');
        }
      }
    }
  });

  test('alternates are symmetric', () async {
    final svc = await CatalogService.loadMerged();
    var pairs = 0;
    for (final i in svc.all) {
      final alts = svc.alternatesFor(i);
      if (alts.isNotEmpty) pairs++;
      for (final a in alts) {
        // Round-trip: each twin lists the original among ITS twins.
        expect(svc.alternatesFor(a).map((x) => x.id), contains(i.id));
      }
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

  test('isDuplicated matches the presence of alternates', () async {
    final svc = await CatalogService.loadMerged();
    // Duplication is now cross-source (AT/ST by tmdbId, Carateen by title), so
    // it is defined purely by whether the item has any alternates — a tmdb-less
    // carateen twin counts.
    for (final i in svc.all) {
      expect(svc.isDuplicated(i), svc.alternatesFor(i).isNotEmpty);
    }
  });

  test('famous pools are memoized (same instance on repeat calls)', () async {
    final svc = await CatalogService.loadMerged();
    // Identity, not just equality: a second call must reuse the cached list
    // rather than re-filter/re-sort the whole catalog (the perf fix).
    expect(identical(svc.popularPool(), svc.popularPool()), isTrue);
    expect(identical(svc.getFeaturedPool(), svc.getFeaturedPool()), isTrue);
    expect(identical(svc.genreRows(), svc.genreRows()), isTrue);
  });
}
