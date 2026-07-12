import 'catalog_source.dart';
import 'content_item.dart';

/// Adapts `carateen_catalog.json` (produced by `tool/carateen_scrape.py`) into
/// the app's normalized [ContentItem] model, exactly like [StardimaAdapter].
///
/// carateen items carry:
///  - flat art/category/year fields (no `tmdb` block — synthesized here);
///  - shows nest `seasons[] -> episodes[]` where each episode has a `play_url`
///    of the form `https://carateen.tv/watch/<showId>/<episodeId>` that the
///    carateen resolver decrypts into an `.m3u8` at playback time;
///  - single-episode films are emitted as `movies[]` with one `play_url`.
class CarateenAdapter {
  static (List<Show>, List<Movie>) parse(Map<String, dynamic> data) {
    final shows = ((data['tvshows'] as List?) ?? const [])
        .map((e) => _show((e as Map).cast<String, dynamic>()))
        .toList();
    final movies = ((data['movies'] as List?) ?? const [])
        .map((e) => _movie((e as Map).cast<String, dynamic>()))
        .toList();
    return (shows, movies);
  }

  static TmdbData _tmdb(Map<String, dynamic> raw) => TmdbData(
        // carateen serves its own posters (webp); expose as the w500 variant the
        // card getter prefers so no TMDB rewrite is attempted on it.
        posterUrlW500: _str(raw['poster_url']),
        posterUrl: _str(raw['poster_url']),
        backdropUrl: _str(raw['poster_url']),
        year: (raw['year'] as num?)?.toInt(),
        genres: _category(raw),
        // vote proxy: carateen's own rating/vote count keeps famous-pool ordering
        // sane even without a TMDB match.
        voteAverage: (raw['rating'] as num?)?.toDouble(),
        voteCount: (raw['total_votes'] as num?)?.toInt() ??
            (raw['views'] as num?)?.toInt(),
      );

  static List<String> _category(Map<String, dynamic> raw) {
    final c = (_str(raw['category']) ?? '').trim();
    return c.isEmpty ? const [] : [c];
  }

  static Movie _movie(Map<String, dynamic> raw) => Movie(
        id: 'c_${_str(raw['id']) ?? ''}',
        title: _str(raw['title']) ?? '',
        thumbnailUrl: _str(raw['poster_url']) ?? '',
        description: _str(raw['description']) ?? '',
        tmdb: _tmdb(raw),
        pageUrl: _str(raw['play_url']) ?? '',
        servers: const [],
        source: CatalogSource.carateen,
      );

  static Show _show(Map<String, dynamic> raw) {
    final id = 'c_${_str(raw['id']) ?? ''}';
    final poster = _str(raw['poster_url']) ?? '';
    final seasons = <Season>[];
    final flat = <Episode>[];

    for (final s in (raw['seasons'] as List?) ?? const []) {
      final sm = (s as Map).cast<String, dynamic>();
      final n = (sm['number'] as num?)?.toInt() ?? (seasons.length + 1);
      final eps = <Episode>[];
      var i = 0;
      for (final e in (sm['episodes'] as List?) ?? const []) {
        final em = (e as Map).cast<String, dynamic>();
        i++;
        eps.add(Episode(
          episodeNumber: (em['number'] as num?)?.toInt() ?? i,
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
      source: CatalogSource.carateen,
    );
  }

  static String? _str(Object? v) => v?.toString();
}
