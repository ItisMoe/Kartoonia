import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/services/wcoflix/wcoflix_catalog.dart';

/// Fixture enriched catalog: two famous (with backdrop), one less-famous, one
/// with no backdrop — to exercise ordering + the hero backdrop filter.
String _catalog() => jsonEncode({
      'items': {
        '/anime/animaniacs': {
          't': 'Animaniacs',
          'tmdb': {
            'tmdb_id': 82,
            'vote_count': 775,
            'poster_url_w500': 'https://img/p/anim.jpg',
            'backdrop_url': 'https://img/b/anim.jpg',
            'en': {'title': 'Animaniacs', 'overview': 'Zany cartoon siblings.'},
          },
        },
        '/anime/pinky-and-the-brain': {
          't': 'Pinky and the Brain',
          'tmdb': {
            'tmdb_id': 99,
            'vote_count': 500,
            'poster_url_w500': 'https://img/p/pnb.jpg',
            'backdrop_url': 'https://img/b/pnb.jpg',
            'en': {'title': 'Pinky and the Brain', 'overview': 'Two lab mice.'},
          },
        },
        // A movie lives at the site root (no /anime/ prefix); its path must be
        // preserved verbatim by famousPool so playback fetches the right page.
        '/twas-the-night-before-christmas': {
          't': "'Twas the Night Before Christmas",
          'tmdb': {
            'tmdb_id': 7,
            'vote_count': 3,
            'poster_url_w500': 'https://img/p/xmas.jpg',
            'backdrop_url': null, // no backdrop -> excluded from hero
            'en': {'title': 'Twas the Night', 'overview': 'A holiday movie.'},
          },
        },
      },
    });

  WcoflixCatalog _cat() => WcoflixCatalog(
        fetch: (_, {post}) async => '',
        loadAsset: (name) async =>
            name.endsWith('wcoflix_catalog.json') ? _catalog() : '{}',
      );

void main() {
  test('artFor attaches TMDB by slug, bridging en.overview', () async {
    final cat = _cat();
    await cat.ensureArt();
    final t = cat.artFor('https://www.wcoflix.tv/anime/animaniacs');
    expect(t, isNotNull);
    expect(t!.tmdbId, 82);
    expect(t.voteCount, 775);
    expect(t.overviewEn, 'Zany cartoon siblings.');
    expect(t.backdropUrl, 'https://img/b/anim.jpg');
    // Query-string variant resolves to the same slug.
    expect(cat.artFor('/anime/animaniacs?season=all&lang=dub')?.tmdbId, 82);
  });

  test('famousPool ranks by vote_count desc and preserves paths', () async {
    final cat = _cat();
    final pool = await cat.famousPool(limit: 10);
    expect(pool.map((l) => l.title).toList(),
        ['Animaniacs', 'Pinky and the Brain', 'Twas the Night']);
    expect(pool.first.url, '/anime/animaniacs');
    // The movie keeps its root path (NOT rewritten to /anime/…).
    expect(pool.last.url, '/twas-the-night-before-christmas');
  });

  test('famousPool withBackdrop drops titles that have none', () async {
    final cat = _cat();
    final hero = await cat.famousPool(limit: 10, withBackdrop: true);
    expect(hero.map((l) => l.title).toList(),
        ['Animaniacs', 'Pinky and the Brain']); // Obscure Show excluded
  });
}
