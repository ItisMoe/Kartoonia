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
///   - likes: a liked show gets an extra [likeBoost]× multiplier on top.
/// Uses the Efraimidis–Spirakis key `-ln(u)/w` (smaller key = earlier), which
/// yields a correct weighted permutation from independent uniforms. Pass [rng]
/// to make the roll deterministic in tests.
List<Show> shaaratQueue(
  List<Show> shows,
  Set<String> likedIds, {
  Random? rng,
  int likeBoost = 3,
}) {
  final pool = shaaratPool(shows);
  if (pool.length < 2) return pool;
  final r = rng ?? Random();
  final keyed = pool.map((s) {
    final fame = s.fameScore > 0 ? s.fameScore : 1.0;
    var w = sqrt(fame); // compress the heavy-tailed vote_count distribution
    if (likedIds.contains(s.id)) w *= likeBoost;
    final u = r.nextDouble().clamp(1e-12, 1.0);
    return (key: -log(u) / w, show: s);
  }).toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  return [for (final e in keyed) e.show];
}
