import 'catalog_source.dart';
import 'content_item.dart';

/// Adapts the `stardima_catalog.json` schema into the app's normalized
/// [ContentItem] model so the rest of the UI renders identically regardless of
/// source.
///
/// Stardima differs from Arabic Toons in every structural way:
///  - art/year/category live at the top level (no `tmdb` block);
///  - shows nest `seasons[] -> episodes[]` where each episode only has a
///    `play_url` (resolved at playback time, NOT a direct video URL);
///  - movies carry a single `play_url` instead of `servers[]`.
///
/// We synthesize a [TmdbData] from the flat poster/backdrop/year/category fields
/// so the existing art-resolution, search and home-row helpers work unchanged.
/// The single `category` string is surfaced as the item's sole genre/category.
class StardimaAdapter {
  /// Parse the decoded top-level Stardima document into normalized items.
  static (List<Show>, List<Movie>) parse(Map<String, dynamic> data) {
    final shows = ((data['tvshows'] as List?) ?? const [])
        .map((e) => _show((e as Map).cast<String, dynamic>()))
        .toList();
    final movies = ((data['movies'] as List?) ?? const [])
        .map((e) => _movie((e as Map).cast<String, dynamic>()))
        .toList();
    return (shows, movies);
  }

  static TmdbData _tmdb(Map<String, dynamic> raw) {
    final t = raw['tmdb'];
    final e = t is Map ? t.cast<String, dynamic>() : null;
    return TmdbData(
      // Stardima already serves correctly-sized TMDB images; expose the poster
      // as the w500 variant the card getter prefers, and the backdrop as-is.
      // Prefer enriched artwork when present, else the scraped flat fields.
      posterUrlW500: _str(e?['poster_url_w500']) ?? _str(raw['poster_url']),
      posterUrl: _str(e?['poster_url']) ?? _str(raw['poster_url']),
      backdropUrl: _str(e?['backdrop_url']) ?? _str(raw['backdrop_url']),
      year: int.tryParse(_str(raw['year']) ?? '') ??
          (e?['year'] as num?)?.toInt(),
      // Keep the single source `category` as the item's genre (filter rail).
      genres: _category(raw),
      voteAverage: (e?['vote_average'] as num?)?.toDouble(),
      voteCount: (e?['vote_count'] as num?)?.toInt(),
      popularity: (e?['popularity'] as num?)?.toDouble(),
    );
  }

  /// The single `category` field becomes the item's category list (empty when
  /// blank, so uncategorised items don't pollute the filter rail).
  static List<String> _category(Map<String, dynamic> raw) {
    final c = (_str(raw['category']) ?? '').trim();
    return c.isEmpty ? const [] : [c];
  }

  static Movie _movie(Map<String, dynamic> raw) => Movie(
        id: _str(raw['id']) ?? '',
        title: _str(raw['title']) ?? '',
        thumbnailUrl: _str(raw['poster_url']) ?? '',
        description: _str(raw['description']) ?? '',
        tmdb: _tmdb(raw),
        // pageUrl carries the play_url to resolve at playback time.
        pageUrl: _str(raw['play_url']) ?? '',
        servers: const [],
        source: CatalogSource.stardima,
      );

  static Show _show(Map<String, dynamic> raw) {
    final id = _str(raw['id']) ?? '';
    final poster = _str(raw['poster_url']) ?? '';
    final seasons = <Season>[];
    final flat = <Episode>[];

    final rawSeasons = (raw['seasons'] as List?) ?? const [];
    for (final s in rawSeasons) {
      final sm = (s as Map).cast<String, dynamic>();
      final n = (sm['number'] as num?)?.toInt() ?? (seasons.length + 1);
      final eps = <Episode>[];
      for (final e in (sm['episodes'] as List?) ?? const []) {
        final em = (e as Map).cast<String, dynamic>();
        eps.add(Episode(
          episodeNumber: (em['number'] as num?)?.toInt() ?? 0,
          episodeTitle: _str(em['title']) ?? '',
          // episodeUrl carries the play_url the resolver consumes.
          episodeUrl: _str(em['play_url']) ?? '',
          servers: const [],
          seasonNumber: n,
        ));
      }
      seasons.add(Season(
        seasonNumber: n,
        seasonTitle: _str(sm['title']) ?? '',
        id: '${id}_s$n',
        thumbnailUrl: poster,
        totalEpisodes: eps.length,
        episodes: eps,
      ));
      flat.addAll(eps);
    }

    return Show(
      id: id,
      title: _str(raw['title']) ?? '',
      thumbnailUrl: poster,
      description: _str(raw['description']) ?? '',
      tmdb: _tmdb(raw),
      totalEpisodes: flat.length,
      seasonCount: seasons.length,
      seasons: seasons,
      episodes: flat,
      source: CatalogSource.stardima,
    );
  }

  static String? _str(Object? v) => v?.toString();
}
