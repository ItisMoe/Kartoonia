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

/// Weighted-random permutation of the شارات pool, stable per calendar day +
/// [daySalt] (random feel, but doesn't reshuffle on every open). Liked shows get
/// [likeBoost]× weight so they surface earlier and more often. Uses the
/// Efraimidis–Spirakis key `-ln(u)/w` (smaller key = earlier), which yields a
/// correct weighted permutation from independent uniforms.
List<Show> shaaratQueue(
  List<Show> shows,
  Set<String> likedIds, {
  String? daySalt,
  int likeBoost = 3,
}) {
  final pool = shaaratPool(shows);
  if (pool.length < 2) return pool;
  final now = DateTime.now();
  final salt = daySalt ?? '';
  final rng = Random('${now.year}-${now.month}-${now.day}-$salt'.hashCode);
  final keyed = pool.map((s) {
    final w = likedIds.contains(s.id) ? likeBoost.toDouble() : 1.0;
    final u = rng.nextDouble().clamp(1e-12, 1.0);
    return (key: -log(u) / w, show: s);
  }).toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  return [for (final e in keyed) e.show];
}
