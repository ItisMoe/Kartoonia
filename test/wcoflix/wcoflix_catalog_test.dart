import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/services/wcoflix/wcoflix_catalog.dart';

String fx(String n) => File('test/fixtures/wcoflix/$n').readAsStringSync();

void main() {
  test('snapshot loads from the injected asset', () async {
    final cat = WcoflixCatalog(
        loadAsset: (_) async =>
            '{"popular":[{"u":"https://www.wcoflix.tv/anime/a","t":"A"}]}');
    final s = await cat.snapshot('popular');
    expect(s.single.title, 'A');
    expect(await cat.snapshot('missing'), isEmpty);
  });

  test('fetchLive stores a non-empty live result; live() returns it', () async {
    var calls = 0;
    final cat = WcoflixCatalog(fetch: (url, {post}) async {
      calls++;
      return fx('home.html');
    });
    expect(cat.live('popular'), isNull);
    await cat.fetchLive('popular');
    expect(cat.live('popular'), isNotEmpty);
    await cat.fetchLive('popular'); // cached — no 2nd fetch
    expect(calls, 1);
  });

  test('fetchLive soft-fails on a Cloudflare challenge (live stays null)',
      () async {
    final cat = WcoflixCatalog(
        fetch: (url, {post}) async => '<html><title>Just a moment...</title>');
    await cat.fetchLive('popular');
    expect(cat.live('popular'), isNull);
  });

  test('search posts catara/konuara', () async {
    Map<String, String>? seenPost;
    final cat = WcoflixCatalog(fetch: (url, {post}) async {
      seenPost = post;
      return fx('search.html');
    });
    final r = await cat.search('conan');
    expect(r, isNotEmpty);
    expect(seenPost?['catara'], 'conan');
    expect(seenPost?['konuara'], 'series');
  });

  test('search soft-fails to empty on network error', () async {
    final cat = WcoflixCatalog(fetch: (url, {post}) async => throw 'net down');
    expect(await cat.search('x'), isEmpty);
  });

  // A tiny enriched-catalog asset: two wco paths map to the SAME tmdb id/title
  // (a dub + sub duplicate), plus a movie and an unrelated series.
  const catalogJson = '''
  {"items": {
    "/anime/batman-beyond": {"t": "Batman Beyond",
      "tmdb": {"tmdb_id": 1, "type": "tv", "vote_count": 900,
        "backdrop_url": "https://image.tmdb.org/t/p/original/b.jpg",
        "poster_url_w500": "https://image.tmdb.org/t/p/w500/b.jpg",
        "en": {"title": "Batman Beyond"}}},
    "/batman-beyond-dub": {"t": "Batman Beyond",
      "tmdb": {"tmdb_id": 1, "type": "tv", "vote_count": 800,
        "poster_url_w500": "https://image.tmdb.org/t/p/w500/b2.jpg",
        "en": {"title": "Batman Beyond"}}},
    "/the-batman-movie": {"t": "The Batman",
      "tmdb": {"tmdb_id": 2, "type": "movie", "vote_count": 700,
        "poster_url_w500": "https://image.tmdb.org/t/p/w500/m.jpg",
        "en": {"title": "The Batman"}}},
    "/anime/naruto": {"t": "Naruto",
      "tmdb": {"tmdb_id": 3, "type": "tv", "vote_count": 500,
        "en": {"title": "Naruto"}}}
  }}''';

  WcoflixCatalog enriched() => WcoflixCatalog(
      fetch: (url, {post}) async => '',
      loadAsset: (name) async =>
          name.contains('catalog') ? catalogJson : '{}');

  test('searchLocal matches title (case/space-insensitive), no network',
      () async {
    final cat = enriched();
    final r = await cat.searchLocal('batman');
    expect(r.map((e) => e.title), contains('Batman Beyond'));
    expect(r.map((e) => e.title), contains('The Batman'));
    expect(await cat.searchLocal('NARUTO'), isNotEmpty);
    expect(await cat.searchLocal('zzz-nope'), isEmpty);
  });

  test('famousPool dedupes by tmdb id/title and can filter by type', () async {
    final cat = enriched();
    final all = await cat.famousPool();
    // The dub+sub Batman Beyond pair collapses to ONE entry.
    expect(all.where((e) => e.title == 'Batman Beyond').length, 1);
    final movies = await cat.famousPool(type: 'movie');
    expect(movies.map((e) => e.title), ['The Batman']);
    final series = await cat.famousPool(type: 'tv');
    expect(series.map((e) => e.title), containsAll(['Batman Beyond', 'Naruto']));
  });

  test('seriesDetail parses episodes using the slug from the url', () async {
    final cat = WcoflixCatalog(fetch: (url, {post}) async => fx('series.html'));
    final s = await cat.seriesDetail('https://www.wcoflix.tv/anime/black-torch');
    expect(s.episodes, isNotEmpty);
    expect(s.episodes.first.url, contains('black-torch'));
  });
}
