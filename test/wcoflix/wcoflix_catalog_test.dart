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

  test('seriesDetail parses episodes using the slug from the url', () async {
    final cat = WcoflixCatalog(fetch: (url, {post}) async => fx('series.html'));
    final s = await cat.seriesDetail('https://www.wcoflix.tv/anime/black-torch');
    expect(s.episodes, isNotEmpty);
    expect(s.episodes.first.url, contains('black-torch'));
  });
}
