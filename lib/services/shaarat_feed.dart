import 'dart:math';
import '../models/content_item.dart';

/// Eligible pool for the شارات reels: famous animated shows, deduped by TMDB id.
/// Mirrors the predicate used by Home's famous pool (vote-count floor +
/// Animation/Family), but shows-only — movies have trailers, not theme songs.
List<Show> shaaratPool(List<Show> shows) {
  final seen = <int>{};
  final out = <Show>[];
  for (final s in shows) {
    if (!(s.isFamous && s.isAnimation)) continue;
    final id = s.tmdbId;
    if (id != null && !seen.add(id)) continue;
    out.add(s);
  }
  return out;
}

/// Weighted-random permutation of the شارات pool, **re-rolled on every call** so
/// each visit to the reels feed gets a fresh order (never the same first show
/// twice in a row). Two weights stack:
///   - popularity: a show's [Show.fameScore] (TMDB vote_count) compressed by
///     `sqrt` so the most famous cartoons strongly trend to the top while every
///     show still keeps a real chance of appearing — "stress on popularity"
///     without degenerating into a fixed sort.
///   - engagement: a show's accumulated boost score (from [boosts]) applies a
///     diminishing-returns multiplier `1 + boostK·ln(1+score)`, so shows you
///     actually watch/finish/open trend earlier without one obsessed-over show
///     ever crowding out the rest.
/// Uses the Efraimidis–Spirakis key `-ln(u)/w` (smaller key = earlier), which
/// yields a correct weighted permutation from independent uniforms. Pass [rng]
/// to make the roll deterministic in tests.
List<Show> shaaratQueue(
  List<Show> shows,
  Map<String, double> boosts, {
  Random? rng,
  double boostK = 0.6,
}) {
  final pool = shaaratPool(shows);
  if (pool.length < 2) return pool;
  final r = rng ?? Random();
  final keyed = pool.map((s) {
    final fame = s.fameScore > 0 ? s.fameScore : 1.0;
    var w = sqrt(fame); // compress the heavy-tailed vote_count distribution
    final score = boosts[s.id] ?? 0;
    if (score > 0) w *= 1 + boostK * log(1 + score);
    final u = r.nextDouble().clamp(1e-12, 1.0);
    return (key: -log(u) / w, show: s);
  }).toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  return [for (final e in keyed) e.show];
}
