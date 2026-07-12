import '../../models/content_item.dart';
import 'wcoflix_parsers.dart';

/// Fuzzy title matching used by the Arabic ↔ Original audio switch: it pairs an
/// Arabic-dubbed catalog title with its WCOFlix original (and vice-versa) by
/// comparing normalized English/original titles. Pure + testable.

final _reNonAlnum = RegExp(r'[^a-z0-9 ]');
final _reSpace = RegExp(r'\s+');
// "Season 2", "Part 3", "Episode 10" etc. — the ordinal AND its number.
final _reOrdinal =
    RegExp(r'\b(season|part|episode|series|vol|volume|chapter)\s+\d+\b');
// A standalone 4-digit release year like "2011".
final _reYear = RegExp(r'\b(?:19|20)\d{2}\b');
// Leftover noise words that shouldn't drive a match (articles/format markers).
final _reNoise = RegExp(
    r'\b(the|a|an|season|part|movie|film|special|ova|tv|series|english|dubbed|subbed|and)\b');

/// Normalize an English title for comparison: lowercase, drop punctuation,
/// season/part numbers, release years and format/article noise words.
String normTitle(String s) => s
    .toLowerCase()
    .replaceAll('&', ' and ')
    .replaceAll(_reNonAlnum, ' ')
    .replaceAll(_reOrdinal, ' ')
    .replaceAll(_reYear, ' ')
    .replaceAll(_reNoise, ' ')
    .replaceAll(_reSpace, ' ')
    .trim();

/// 0..1 similarity: 1 for an exact normalized match, else token Jaccard. Two
/// titles that merely share one common word (e.g. "Naruto" vs "Naruto
/// Shippuden") score 0.5 and fall below the default gate, avoiding wrong pairs.
double titleMatchScore(String a, String b) {
  final na = normTitle(a), nb = normTitle(b);
  if (na.isEmpty || nb.isEmpty) return 0;
  if (na == nb) return 1;
  final ta = na.split(' ').where((w) => w.isNotEmpty).toSet();
  final tb = nb.split(' ').where((w) => w.isNotEmpty).toSet();
  if (ta.isEmpty || tb.isEmpty) return 0;
  final inter = ta.intersection(tb).length;
  final union = ta.union(tb).length;
  return inter / union;
}

/// The best WCOFlix series link matching [query] (an English title), or null
/// when nothing clears [min]. Ties keep the first (search-rank order).
WcoLink? bestWcoflixMatch(String query, List<WcoLink> links,
    {double min = 0.6}) {
  WcoLink? best;
  var bestScore = 0.0;
  for (final l in links) {
    final s = titleMatchScore(query, l.title);
    if (s > bestScore) {
      bestScore = s;
      best = l;
    }
  }
  return bestScore >= min ? best : null;
}

/// Memoized [bestArabicMatch] keyed by the last queried title, shared by the
/// TV and phone detail screens (one instance per State). The O(catalog) scan
/// runs once per title instead of on every rebuild. Match against the
/// catalog's SHOWS only — the WCO side of the audio switch is only offered for
/// series, and matching against Arabic MOVIES paired series with same-named
/// films.
class ArabicMatchMemo {
  String? _title;
  ContentItem? _match;

  ContentItem? match(String title, List<ContentItem> shows) {
    if (_title != title) {
      _title = title;
      _match = bestArabicMatch(title, shows);
    }
    return _match;
  }
}

/// The best Arabic catalog item matching a WCOFlix English [title], compared
/// against each item's English + original TMDB titles, or null below [min].
ContentItem? bestArabicMatch(String title, List<ContentItem> items,
    {double min = 0.6}) {
  ContentItem? best;
  var bestScore = 0.0;
  for (final i in items) {
    final t = i.tmdb;
    for (final cand in [t?.enTitle, t?.originalTitle]) {
      if (cand == null || cand.isEmpty) continue;
      final s = titleMatchScore(title, cand);
      if (s > bestScore) {
        bestScore = s;
        best = i;
      }
    }
  }
  return bestScore >= min ? best : null;
}
