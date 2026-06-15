import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/models/catalog_source.dart';
import 'package:kartoonia/models/content_item.dart';
import 'package:kartoonia/models/stardima_adapter.dart';

/// Parses the REAL bundled catalogs straight off disk (no rootBundle) to make
/// sure both adapters survive the actual data shapes end-to-end.
void main() {
  test('Stardima catalog parses into normalized items', () {
    final f = File('assets/stardima_catalog.json');
    expect(f.existsSync(), isTrue, reason: 'stardima_catalog.json missing');
    final data = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;

    final (shows, movies) = StardimaAdapter.parse(data);
    expect(shows, isNotEmpty);
    expect(movies, isNotEmpty);

    // Every item is tagged as Stardima and exposes a play target + art.
    for (final m in movies) {
      expect(m.source, CatalogSource.stardima);
      expect(m.pageUrl, isNotEmpty); // play_url for the resolver
    }
    final withEpisodes = shows.where((s) => s.episodes.isNotEmpty);
    expect(withEpisodes, isNotEmpty);
    for (final ep in withEpisodes.first.episodes) {
      expect(ep.episodeUrl, isNotEmpty); // play_url per episode
    }

    // Categories surface for filtering (some items are categorised).
    final cats = {for (final s in [...shows, ...movies]) ...s.categories};
    expect(cats, isNotEmpty);
  });

  test('Arabic Toons catalog still parses unchanged', () {
    final f = File('assets/arabictoons_catalog.json');
    expect(f.existsSync(), isTrue, reason: 'arabictoons_catalog.json missing');
    final data = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;

    final shows = ((data['shows'] as List?) ?? const [])
        .map((e) => Show.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    final movies = ((data['movies'] as List?) ?? const [])
        .map((e) => Movie.fromJson((e as Map).cast<String, dynamic>()))
        .toList();

    expect(shows, isNotEmpty);
    expect(movies, isNotEmpty);
    // Legacy items default to the Arabic Toons source + direct playback path.
    expect(shows.first.source, CatalogSource.arabicToons);
    expect(movies.first.source, CatalogSource.arabicToons);
    expect(shows.first.episodes.first.episodeUrl, isNotEmpty);
  });
}
