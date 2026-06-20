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
    final q = shaaratQueue(shows, const {}, rng: Random(1));
    expect(q.map((s) => s.id).toSet(), {'a', 'e'});
  });

  test('deterministic for a given rng seed', () {
    final shows = [for (var i = 0; i < 8; i++) _show('s$i', tmdbId: i)];
    final a = shaaratQueue(shows, const {}, rng: Random(7));
    final b = shaaratQueue(shows, const {}, rng: Random(7));
    expect(a.map((s) => s.id).toList(), b.map((s) => s.id).toList());
  });

  test('boosted shows trend earlier across many runs', () {
    // Equal votes so the engagement boost is the only signal in play.
    final shows = [for (var i = 0; i < 20; i++) _show('s$i', tmdbId: i)];
    var boostedAvg = 0.0, baseAvg = 0.0;
    const runs = 40;
    for (var r = 0; r < runs; r++) {
      final q = shaaratQueue(shows, {'s0': 7.0}, rng: Random(r));
      boostedAvg += q.indexWhere((s) => s.id == 's0');
      baseAvg += q.indexWhere((s) => s.id == 's1');
    }
    expect(boostedAvg / runs, lessThan(baseAvg / runs));
  });

  test('a bigger boost trends earlier than a smaller boost', () {
    final shows = [for (var i = 0; i < 20; i++) _show('s$i', tmdbId: i)];
    var bigAvg = 0.0, smallAvg = 0.0;
    const runs = 50;
    for (var r = 0; r < runs; r++) {
      final q = shaaratQueue(shows, {'s0': 8.0, 's1': 1.0}, rng: Random(r));
      bigAvg += q.indexWhere((s) => s.id == 's0');
      smallAvg += q.indexWhere((s) => s.id == 's1');
    }
    expect(bigAvg / runs, lessThan(smallAvg / runs));
  });

  test('more popular shows trend earlier across many runs', () {
    // A clearly-famous show vs a barely-famous one (both eligible).
    final shows = [
      _show('hit', tmdbId: 1, votes: 5000),
      for (var i = 0; i < 10; i++) _show('low$i', tmdbId: 100 + i, votes: 25),
    ];
    var hitAvg = 0.0, lowAvg = 0.0;
    const runs = 60;
    for (var r = 0; r < runs; r++) {
      final q = shaaratQueue(shows, const {}, rng: Random(r));
      hitAvg += q.indexWhere((s) => s.id == 'hit');
      lowAvg += q.indexWhere((s) => s.id == 'low0');
    }
    expect(hitAvg / runs, lessThan(lowAvg / runs));
  });
}
