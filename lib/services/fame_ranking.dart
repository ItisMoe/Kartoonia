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
