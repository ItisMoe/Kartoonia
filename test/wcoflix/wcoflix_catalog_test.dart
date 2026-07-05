import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/services/wcoflix/wcoflix_catalog.dart';

String fx(String n) => File('test/fixtures/wcoflix/$n').readAsStringSync();

void main() {
  test('popular() parses homepage via injected fetch + caches', () async {
    var calls = 0;
    final cat = WcoflixCatalog(fetch: (url, {post}) async {
      calls++;
      return fx('home.html');
    });
    final a = await cat.popular();
    final b = await cat.popular(); // cache hit, no 2nd fetch
    expect(a, isNotEmpty);
    expect(calls, 1);
    expect(a.length, b.length);
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

  test('seriesDetail parses episodes using slug from url', () async {
    final cat = WcoflixCatalog(fetch: (url, {post}) async => fx('series.html'));
    final s = await cat.seriesDetail('https://www.wcoflix.tv/anime/black-torch');
    expect(s.episodes, isNotEmpty);
    expect(s.episodes.first.url, contains('black-torch'));
  });
}
