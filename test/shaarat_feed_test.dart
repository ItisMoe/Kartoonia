import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/models/content_item.dart';
import 'package:kartoonia/services/shaarat_feed.dart';

Show _show(String id, {int? tmdbId, int votes = 100, bool animation = true}) =>
    Show(
      id: id,
      title: id,
      thumbnailUrl: '',
      description: '',
      tmdb: TmdbData(
        voteCount: votes,
        tmdbId: tmdbId,
        tmdbGenres: animation ? const ['Animation'] : const ['Drama'],
      ),
      totalEpisodes: 1,
      seasonCount: 1,
      seasons: const [],
      episodes: const [],
    );

void main() {
  test('keeps only famous animated shows, deduped by tmdbId', () {
    final shows = [
      _show('a', tmdbId: 1),
      _show('b', tmdbId: 1), // dup tmdbId -> dropped
      _show('c', tmdbId: 2, animation: false), // not animation -> dropped
      _show('d', tmdbId: 3, votes: 0), // not famous -> dropped
      _show('e', tmdbId: 4),
    ];
    final q = shaaratQueue(shows, rng: Random(1));
    expect(q.map((s) => s.id).toSet(), {'a', 'e'});
  });

  test('deterministic for a given rng seed', () {
    final shows = [for (var i = 0; i < 8; i++) _show('s$i', tmdbId: i)];
    final a = shaaratQueue(shows, rng: Random(7));
    final b = shaaratQueue(shows, rng: Random(7));
    expect(a.map((s) => s.id).toList(), b.map((s) => s.id).toList());
  });

  test('queue is capped to the most popular slice', () {
    // More famous shows than the cap: only the top-voted make the pool.
    final shows = [
      for (var i = 0; i < kShaaratPopularCap + 40; i++)
        _show('s$i', tmdbId: i, votes: 100 + i),
    ];
    final q = shaaratQueue(shows, rng: Random(3));
    expect(q.length, kShaaratPopularCap);
    // The 40 lowest-voted (s0..s39) fell outside the popular slice.
    expect(q.any((s) => s.id == 's0'), isFalse);
    expect(q.any((s) => s.id == 's39'), isFalse);
    // The very top show is always in the pool (somewhere — order is random).
    expect(q.any((s) => s.id == 's${kShaaratPopularCap + 39}'), isTrue);
  });

  test('order is a plain shuffle — no fame weighting inside the slice', () {
    // A dominant-fame show must NOT trend to the front: over many rolls its
    // average position matches a low-fame show's (uniform shuffle).
    final shows = [
      _show('hit', tmdbId: 1, votes: 500000),
      for (var i = 0; i < 9; i++) _show('low$i', tmdbId: 100 + i, votes: 25),
    ];
    var hitAvg = 0.0, lowAvg = 0.0;
    const runs = 400;
    for (var r = 0; r < runs; r++) {
      final q = shaaratQueue(shows, rng: Random(r));
      hitAvg += q.indexWhere((s) => s.id == 'hit');
      lowAvg += q.indexWhere((s) => s.id == 'low0');
    }
    // Both average near the middle (4.5 of 0..9); allow generous noise.
    expect((hitAvg / runs - lowAvg / runs).abs(), lessThan(1.0));
  });
}
