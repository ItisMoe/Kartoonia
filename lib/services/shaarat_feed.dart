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

/// Build the combined شارات queue: the shuffled popular show themes
/// ([shaaratQueue]) interleaved with the carateen `/music` tracks so the songs
/// surface throughout the feed rather than all at the end. One music entry is
/// inserted every [musicEvery] show reels (2 → roughly a third of the feed is
/// carateen music, deliberately favoured); when there are no shows (a
/// carateen-only library) the feed is just the music. [linkOf] maps a track to
/// its catalog show (may be null). Re-rolled on every call (fresh order each
/// visit).
List<ShaaratItem> shaaratItemQueue(
  List<Show> shows,
  List<CarateenTrack> music,
  Show? Function(CarateenTrack) linkOf, {
  Random? rng,
  int musicEvery = 2,
}) {
  final r = rng ?? Random();
  final showItems =
      shaaratQueue(shows, rng: rng).map(ShaaratItem.fromShow).toList();
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

/// How many of the most famous shows the شارات feed draws from: the queue is
/// pure random WITHIN this top slice, so every reel is a well-known title while
/// the order itself carries no ranking at all.
const int kShaaratPopularCap = 120;

/// Uniformly-shuffled permutation of the MOST popular animated shows,
/// **re-rolled on every call** so each visit to the reels feed gets a fresh
/// order (never the same first show twice in a row). The pool is the
/// famous/animation pool cut to its [kShaaratPopularCap] highest fame scores;
/// within that slice the order is a plain uniform shuffle — no fame weighting
/// and no engagement ("favorite points") ranking, both removed by request:
/// as random as possible, but always among the popular titles. Pass [rng] to
/// make the roll deterministic in tests.
List<Show> shaaratQueue(List<Show> shows, {Random? rng}) {
  final pool = shaaratPool(shows)
    ..sort((a, b) => b.fameScore.compareTo(a.fameScore));
  final top = pool.length > kShaaratPopularCap
      ? pool.sublist(0, kShaaratPopularCap)
      : pool;
  top.shuffle(rng ?? Random());
  return top;
}
