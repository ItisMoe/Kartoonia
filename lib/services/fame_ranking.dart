import '../models/content_item.dart';

/// Pure ranking helpers for the Home "picked" rows. Kept separate from
/// CatalogService so the selection/ordering logic is unit-testable without any
/// asset I/O.

/// Sort comparator: most famous first, breaking ties by TMDB trending score.
///
/// Ranks by [ContentItem.fameScore], which uses vote_count for enriched items
/// and a rating fallback for un-enriched ones — the two are on different scales,
/// so mixing them produces undefined ordering. This comparator is intended to be
/// called on an already-[ContentItem.isFamous]-filtered pool (as [famousPool]
/// does) to ensure only enriched items are compared.
int compareByFame(ContentItem a, ContentItem b) {
  final c = b.fameScore.compareTo(a.fameScore);
  if (c != 0) return c;
  return (b.tmdbPopularity ?? 0).compareTo(a.tmdbPopularity ?? 0);
}

/// The curated famous pool for [items], highest fame first.
///
/// Primary path: titles that clear the vote-count floor AND are Animation/Family
/// (drops live-action mismatches), sorted by fame and deduped by TMDB id (a
/// title that matched one TMDB entry several times appears once). If none
/// qualify (e.g. an un-enriched catalog), fall back to anything with a positive
/// weighted rating; if even that is empty, return the items as-is so rows never
/// render blank.
List<T> famousPool<T extends ContentItem>(List<T> items) {
  final famous = items.where((i) => i.isFamous && i.isAnimation).toList()
    ..sort(compareByFame);
  if (famous.isNotEmpty) return _dedupeByTmdbId(famous);

  final rated = items.where((i) => i.weightedRating > 0).toList()
    ..sort((a, b) => b.weightedRating.compareTo(a.weightedRating));
  if (rated.isNotEmpty) return _dedupeByTmdbId(rated);
  return List<T>.of(items);
}

/// Keep the first occurrence of each non-null TMDB id; items without an id are
/// all kept (nothing to dedupe on).
List<T> _dedupeByTmdbId<T extends ContentItem>(List<T> items) {
  final seen = <int>{};
  final out = <T>[];
  for (final i in items) {
    final id = i.tmdbId;
    if (id != null && !seen.add(id)) continue;
    out.add(i);
  }
  return out;
}

/// Browse ordering: every item kept, most-known first.
///
/// Partitions to avoid the vote_count-vs-rating scale mix that [compareByFame]
/// warns about: enriched titles (TMDB vote_count known) lead, ordered by
/// vote_count desc; the rest follow, ordered by denoised
/// [ContentItem.weightedRating] desc. Ties fall back to case-insensitive title
/// order so the grid is stable day-to-day.
List<T> sortedForBrowse<T extends ContentItem>(List<T> items) {
  final enriched = <T>[];
  final rest = <T>[];
  for (final i in items) {
    (i.voteCount != null ? enriched : rest).add(i);
  }
  int byTitle(T a, T b) =>
      a.title.toLowerCase().compareTo(b.title.toLowerCase());
  enriched.sort((a, b) {
    final c = (b.voteCount ?? 0).compareTo(a.voteCount ?? 0);
    return c != 0 ? c : byTitle(a, b);
  });
  rest.sort((a, b) {
    final c = b.weightedRating.compareTo(a.weightedRating);
    return c != 0 ? c : byTitle(a, b);
  });
  return [...enriched, ...rest];
}

/// Titles similar to [item] for the detail screen's "More Like This" row.
///
/// Ranked by shared-genre count (dominant), then a same-kind bonus (shows
/// suggest shows, movies suggest movies), then fame as the tiebreak. The item
/// itself and its cross-source twin (same tmdbId) are excluded, results are
/// deduped by tmdbId. When genre overlap can't fill [count] (genre-less
/// items), famous same-kind titles backfill so the row is never sparse.
List<ContentItem> similarTo(ContentItem item, List<ContentItem> all,
    {int count = 12}) {
  final own = item.genres.toSet();
  bool isShow(ContentItem o) => o is Show;
  bool excluded(ContentItem o) =>
      o.id == item.id || (item.tmdbId != null && o.tmdbId == item.tmdbId);

  final scored = <(double, ContentItem)>[];
  for (final o in all) {
    if (excluded(o)) continue;
    final shared = own.isEmpty ? 0 : o.genres.where(own.contains).length;
    if (shared == 0) continue;
    // Genre overlap dominates (1e6 per genre), same-kind is worth half a
    // genre, fame (vote_count, <1e5) only breaks ties within a bucket.
    final score = shared * 1e6 +
        (isShow(o) == isShow(item) ? 5e5 : 0) +
        (o.fameScore > 0 ? o.fameScore : 0);
    scored.add((score, o));
  }
  scored.sort((a, b) => b.$1.compareTo(a.$1));
  final out = _dedupeByTmdbId([for (final s in scored) s.$2]);

  if (out.length < count) {
    final have = {for (final o in out) o.id};
    for (final o in famousPool(all)) {
      if (out.length >= count) break;
      if (excluded(o) || have.contains(o.id)) continue;
      if (isShow(o) != isShow(item)) continue;
      out.add(o);
    }
  }
  return out.take(count).toList();
}

/// All distinct genres present across [items], sorted alphabetically.
List<String> genresIn(List<ContentItem> items) {
  final set = <String>{};
  for (final i in items) {
    set.addAll(i.genres);
  }
  return set.toList()..sort();
}

/// Genre groupings for [items]: genres with >= [min] items, capped at [cap]
/// rows. Each entry's value is every item in that genre, unsorted (callers
/// rank/shuffle as needed).
List<MapEntry<String, List<ContentItem>>> genreRowsFor(
  List<ContentItem> items, {
  int min = 4,
  int cap = 8,
}) {
  final out = <MapEntry<String, List<ContentItem>>>[];
  for (final g in genresIn(items)) {
    final inGenre = items.where((i) => i.genres.contains(g)).toList();
    if (inGenre.length >= min) out.add(MapEntry(g, inGenre));
    if (out.length >= cap) break;
  }
  return out;
}
