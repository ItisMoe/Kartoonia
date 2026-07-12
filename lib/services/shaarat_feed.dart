import 'dart:math';
import '../models/carateen_music.dart';
import '../models/content_item.dart';

/// One entry in the شارات (theme-songs) feed. It is EITHER a catalog show whose
/// Arabic theme is resolved from YouTube ([show] set, [audioUrl] null), OR a
/// carateen.tv `/music` track played straight from its mp3 ([audioUrl] set).
/// A music track may still be linked to a catalog [show] (so "Enter show"
/// works); when it isn't, [show] is null and the feed greys that action out.
class ShaaratItem {
  /// Stable id — the show id, or `car_music_<track>` for a music entry.
  final String id;
  final String title;

  /// Artist line for music tracks; empty for show themes.
  final String subtitle;
  final String posterUrl;

  /// The catalog show to open from "Enter show". Null → greyed out.
  final Show? show;

  /// Non-null for a carateen music track: its mp3 URL (played directly, no
  /// YouTube resolve). Null → resolve [show]'s theme from YouTube.
  final String? audioUrl;
  final Map<String, String>? audioHeaders;

  const ShaaratItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.posterUrl,
    this.show,
    this.audioUrl,
    this.audioHeaders,
  });

  bool get isMusic => audioUrl != null;
  bool get canEnter => show != null;

  factory ShaaratItem.fromShow(Show s) => ShaaratItem(
        id: s.id,
        title: s.title,
        subtitle: '',
        posterUrl: s.posterUrl,
        show: s,
      );

  factory ShaaratItem.fromTrack(CarateenTrack t, {Show? linked}) => ShaaratItem(
        id: 'car_music_${t.track}',
        title: t.title,
        subtitle: t.artist,
        posterUrl: t.cover.isNotEmpty ? t.cover : (linked?.posterUrl ?? ''),
        show: linked,
        audioUrl: t.url,
        audioHeaders: CarateenTrack.headers,
      );
}

/// Build the combined شارات queue: the fame-weighted show themes ([shaaratQueue])
/// interleaved with the carateen `/music` tracks so the songs surface throughout
/// the feed rather than all at the end. One music entry is inserted every
/// [musicEvery] show reels; when there are no shows (a carateen-only library)
/// the feed is just the music. [linkOf] maps a track to its catalog show (may be
/// null). Re-rolled on every call (fresh order each visit).
List<ShaaratItem> shaaratItemQueue(
  List<Show> shows,
  Map<String, double> boosts,
  List<CarateenTrack> music,
  Show? Function(CarateenTrack) linkOf, {
  Random? rng,
  int musicEvery = 3,
}) {
  final r = rng ?? Random();
  final showItems =
      shaaratQueue(shows, boosts, rng: rng).map(ShaaratItem.fromShow).toList();
  final musicItems = [
    for (final t in music) ShaaratItem.fromTrack(t, linked: linkOf(t))
  ]..shuffle(r);

  if (showItems.isEmpty) return musicItems;
  if (musicItems.isEmpty) return showItems;

  final out = <ShaaratItem>[];
  var mi = 0;
  for (var i = 0; i < showItems.length; i++) {
    out.add(showItems[i]);
    if ((i + 1) % musicEvery == 0 && mi < musicItems.length) {
      out.add(musicItems[mi++]);
    }
  }
  // Append any music that didn't fit the interleave so nothing is dropped.
  out.addAll(musicItems.sublist(mi));
  return out;
}

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
