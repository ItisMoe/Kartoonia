/// Parsed WCOFlix item title: the show/movie name with the site's
/// "English Dubbed/Subbed" + "Season N Episode M" suffixes stripped, plus the
/// flags/numbers recovered from them. Loosely ports the addon `getTitleInfo`.
class TitleMeta {
  final String cleanTitle;
  final bool isDub;
  final bool isSub;
  final int? season;
  final int? episode;
  const TitleMeta({
    required this.cleanTitle,
    required this.isDub,
    required this.isSub,
    this.season,
    this.episode,
  });
}

final _reEpisode = RegExp(r'\bEpisode\s+(\d+)', caseSensitive: false);
final _reSeason = RegExp(r'\bSeason\s+(\d+)', caseSensitive: false);
final _reTrailingPunct = RegExp(r'[\s\-–:]+$');

TitleMeta parseTitleMeta(String rawTitle) {
  final t = rawTitle.trim();
  final lower = t.toLowerCase();
  final isDub = lower.contains('english dubbed');
  final isSub = lower.contains('english subbed');
  final season = int.tryParse(_reSeason.firstMatch(t)?.group(1) ?? '');
  final episode = int.tryParse(_reEpisode.firstMatch(t)?.group(1) ?? '');

  // Clean title = everything before the first "Season"/"Episode" marker, with
  // the dub/sub suffix removed. With neither marker it's a movie-style title,
  // kept as-is (only the dub/sub words stripped).
  final cuts = <int>[
    if (_reSeason.firstMatch(t) != null) _reSeason.firstMatch(t)!.start,
    if (_reEpisode.firstMatch(t) != null) _reEpisode.firstMatch(t)!.start,
  ];
  var clean = cuts.isEmpty ? t : t.substring(0, cuts.reduce((a, b) => a < b ? a : b));
  clean = clean
      .replaceAll(RegExp(r'English (Dubbed|Subbed)', caseSensitive: false), '')
      .trim()
      .replaceAll(_reTrailingPunct, '')
      .trim();

  return TitleMeta(
    cleanTitle: clean.isEmpty ? t : clean,
    isDub: isDub,
    isSub: isSub,
    season: season,
    episode: episode,
  );
}
