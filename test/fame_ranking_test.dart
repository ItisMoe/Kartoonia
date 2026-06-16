import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/models/content_item.dart';
import 'package:kartoonia/services/fame_ranking.dart';

void main() {
  Movie movie({double? voteAverage, int? voteCount, double? popularity}) => Movie(
        id: 'm',
        title: 't',
        thumbnailUrl: '',
        description: '',
        tmdb: (voteAverage == null && voteCount == null && popularity == null)
            ? null
            : TmdbData(
                voteAverage: voteAverage,
                voteCount: voteCount,
                popularity: popularity,
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
  });

  group('famousPool', () {
    test('keeps only floor-clearing items, ordered by fame desc', () {
      final a = movie(voteAverage: 8, voteCount: 5000);
      final b = movie(voteAverage: 9, voteCount: 100);
      final c = movie(voteAverage: 10, voteCount: 2);
      final d = movie(voteAverage: 9);
      final pool = famousPool([c, b, a, d]);
      expect(pool, [a, b]);
    });
    test('breaks fame ties by tmdb popularity', () {
      final a = movie(voteAverage: 8, voteCount: 100, popularity: 5);
      final b = movie(voteAverage: 8, voteCount: 100, popularity: 50);
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
}
