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
    final q = shaaratQueue(shows, const {}, daySalt: 'x');
    expect(q.map((s) => s.id).toSet(), {'a', 'e'});
  });

  test('deterministic for a given day/salt', () {
    final shows = [for (var i = 0; i < 8; i++) _show('s$i', tmdbId: i)];
    final a = shaaratQueue(shows, const {}, daySalt: 'same');
    final b = shaaratQueue(shows, const {}, daySalt: 'same');
    expect(a.map((s) => s.id).toList(), b.map((s) => s.id).toList());
  });

  test('liked shows trend earlier across many runs', () {
    final shows = [for (var i = 0; i < 20; i++) _show('s$i', tmdbId: i)];
    var likedAvg = 0.0, baseAvg = 0.0;
    const runs = 40;
    for (var r = 0; r < runs; r++) {
      final q = shaaratQueue(shows, {'s0'}, daySalt: 'run$r');
      likedAvg += q.indexWhere((s) => s.id == 's0');
      baseAvg += q.indexWhere((s) => s.id == 's1');
    }
    expect(likedAvg / runs, lessThan(baseAvg / runs));
  });
}
