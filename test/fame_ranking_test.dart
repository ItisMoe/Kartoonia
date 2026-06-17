import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/models/content_item.dart';
import 'package:kartoonia/models/stardima_adapter.dart';
import 'package:kartoonia/services/fame_ranking.dart';

void main() {
  Movie movie({
    double? voteAverage,
    int? voteCount,
    double? popularity,
    List<String>? tmdbGenres,
    int? tmdbId,
  }) =>
      Movie(
        id: 'm',
        title: 't',
        thumbnailUrl: '',
        description: '',
        tmdb: (voteAverage == null &&
                voteCount == null &&
                popularity == null &&
                tmdbGenres == null &&
                tmdbId == null)
            ? null
            : TmdbData(
                voteAverage: voteAverage,
                voteCount: voteCount,
                popularity: popularity,
                tmdbGenres: tmdbGenres ?? const [],
                tmdbId: tmdbId,
              ),
        pageUrl: '',
        servers: const [],
      );

  group('TmdbData parsing', () {
    test('parses vote_count and popularity when present', () {
      final t = TmdbData.fromJson({
        'vote_average': 8.7,
        'vote_count': 5350,
        'popularity': 46.6875,
      });
      expect(t.voteAverage, 8.7);
      expect(t.voteCount, 5350);
      expect(t.popularity, 46.6875);
    });

    test('leaves vote_count and popularity null when absent', () {
      final t = TmdbData.fromJson({'vote_average': 8.7});
      expect(t.voteCount, isNull);
      expect(t.popularity, isNull);
    });
  });

  group('fame getters', () {
    test('weightedRating denoises a tiny-sample 10.0', () {
      final wr = movie(voteAverage: 10, voteCount: 2).weightedRating;
      expect(wr, closeTo(7.12, 0.05));
    });
    test('weightedRating keeps a high-count rating near its value', () {
      final wr = movie(voteAverage: 8.7, voteCount: 5350).weightedRating;
      expect(wr, closeTo(8.68, 0.05));
    });
    test('weightedRating falls back to raw vote_average pre-enrichment', () {
      expect(movie(voteAverage: 8).weightedRating, 8.0);
    });
    test('isFamous requires the vote_count floor', () {
      expect(movie(voteAverage: 9, voteCount: 5000).isFamous, isTrue);
      expect(movie(voteAverage: 10, voteCount: 2).isFamous, isFalse);
      expect(movie(voteAverage: 9).isFamous, isFalse);
    });
    test('fameScore is vote_count when known, else weighted rating', () {
      expect(movie(voteAverage: 8.7, voteCount: 5350).fameScore, 5350.0);
      expect(movie(voteAverage: 8).fameScore, 8.0);
    });
    test('isFamous is inclusive at the vote_count floor', () {
      expect(movie(voteAverage: 7, voteCount: kFameVoteFloor).isFamous, isTrue);
      expect(movie(voteAverage: 7, voteCount: kFameVoteFloor - 1).isFamous, isFalse);
    });
    test('isAnimation reads tmdb genres', () {
      expect(movie(voteAverage: 8, voteCount: 30, tmdbGenres: ['Animation']).isAnimation, isTrue);
      expect(movie(voteAverage: 8, voteCount: 30, tmdbGenres: ['Drama']).isAnimation, isFalse);
      expect(movie(voteAverage: 8, voteCount: 30).isAnimation, isFalse);
    });
  });

  group('famousPool', () {
    test('keeps only floor-clearing items, ordered by fame desc', () {
      final a = movie(voteAverage: 8, voteCount: 5000, tmdbGenres: ['Animation']);
      final b = movie(voteAverage: 9, voteCount: 100, tmdbGenres: ['Animation']);
      final c = movie(voteAverage: 10, voteCount: 2, tmdbGenres: ['Animation']);
      final d = movie(voteAverage: 9, tmdbGenres: ['Animation']);
      final pool = famousPool([c, b, a, d]);
      expect(pool, [a, b]);
    });
    test('breaks fame ties by tmdb popularity', () {
      final a = movie(voteAverage: 8, voteCount: 100, popularity: 5, tmdbGenres: ['Animation']);
      final b = movie(voteAverage: 8, voteCount: 100, popularity: 50, tmdbGenres: ['Animation']);
      expect(famousPool([a, b]), [b, a]);
    });
    test('falls back to weighted rating when nothing is famous', () {
      final a = movie(voteAverage: 8);
      final b = movie(voteAverage: 9);
      final z = movie();
      expect(famousPool([a, b, z]), [b, a]);
    });
    test('returns all items when there is no signal at all', () {
      expect(famousPool([movie(), movie()]).length, 2);
    });
  });

  group('famousPool cleanup', () {
    test('excludes non-animation famous titles', () {
      final cartoon = movie(voteAverage: 8, voteCount: 5000, tmdbGenres: ['Animation'], tmdbId: 1);
      final liveAction = movie(voteAverage: 8, voteCount: 9000, tmdbGenres: ['Drama'], tmdbId: 2);
      expect(famousPool([liveAction, cartoon]), [cartoon]);
    });
    test('treats Family as animation-eligible', () {
      final fam = movie(voteAverage: 8, voteCount: 5000, tmdbGenres: ['Family'], tmdbId: 3);
      expect(famousPool([fam]), [fam]);
    });
    test('dedupes titles that share a TMDB id', () {
      final a = movie(voteAverage: 8, voteCount: 5000, tmdbGenres: ['Animation'], tmdbId: 7);
      final b = movie(voteAverage: 8, voteCount: 5000, tmdbGenres: ['Animation'], tmdbId: 7);
      final c = movie(voteAverage: 8, voteCount: 4000, tmdbGenres: ['Animation'], tmdbId: 8);
      final pool = famousPool([a, b, c]);
      expect(pool.length, 2);
      expect(pool.map((m) => m.tmdbId), [7, 8]);
    });
  });

  group('StardimaAdapter enrichment', () {
    test('reads vote_count/popularity from an enriched tmdb block', () {
      final (_, movies) = StardimaAdapter.parse({
        'movies': [
          {
            'id': '1',
            'title': 'Famous Toon',
            'poster_url': 'p.jpg',
            'backdrop_url': 'b.jpg',
            'year': '2011',
            'category': 'Comedy',
            'play_url': 'http://x',
            'tmdb': {
              'vote_average': 8.7,
              'vote_count': 5350,
              'popularity': 46.6,
            },
          }
        ],
        'tvshows': const [],
      });
      final m = movies.single;
      expect(m.voteCount, 5350);
      expect(m.tmdbPopularity, 46.6);
      expect(m.isFamous, isTrue);
      expect(m.categories, ['Comedy']);
    });

    test('items without a tmdb block stay non-famous', () {
      final (_, movies) = StardimaAdapter.parse({
        'movies': [
          {'id': '2', 'title': 'Obscure', 'poster_url': 'p', 'play_url': 'u'}
        ],
        'tvshows': const [],
      });
      expect(movies.single.isFamous, isFalse);
    });
  });

  group('sortedForBrowse', () {
    test('enriched titles lead, ordered by vote_count desc', () {
      final a = movie(voteAverage: 7, voteCount: 100);
      final b = movie(voteAverage: 7, voteCount: 5000);
      final c = movie(voteAverage: 7, voteCount: 900);
      expect(sortedForBrowse([a, b, c]), [b, c, a]);
    });

    test('any enriched title outranks every un-enriched one', () {
      // vote_count 5 == fameScore 5.0 would lose to a 9.0 rating under
      // compareByFame; sortedForBrowse must still put the enriched title first.
      final enriched = movie(voteAverage: 1, voteCount: 5);
      final unrated = movie(voteAverage: 9);
      expect(sortedForBrowse([unrated, enriched]), [enriched, unrated]);
    });

    test('un-enriched titles fall back to weighted rating desc', () {
      final a = movie(voteAverage: 6);
      final b = movie(voteAverage: 9);
      expect(sortedForBrowse([a, b]), [b, a]);
    });

    test('keeps all items (drops nothing)', () {
      expect(sortedForBrowse([movie(), movie(), movie()]).length, 3);
    });

    test('empty in, empty out', () {
      expect(sortedForBrowse(<Movie>[]), isEmpty);
    });
  });
}
