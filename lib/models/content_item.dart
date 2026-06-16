import '../utils/image_urls.dart';
import 'catalog_source.dart';

/// Internal fame-ranking tuning (never displayed). `kFameMeanVote` is the prior
/// mean rating (C), `kFameBayesPrior` the prior weight in votes (m), and
/// `kFameVoteFloor` the minimum vote_count for a title to enter the curated
/// "famous" Home pools.
const double kFameMeanVote = 7.0;
const double kFameBayesPrior = 50.0;
const int kFameVoteFloor = 20;

/// Typed catalog models. Parsed from the heterogeneous catalog.json:
///  - shows have no top-level id/description; episodes live under seasons[],
///    and they carry `ids` (per-season source ids) + optional tmdb.
///  - movies have id, description, page_url, servers, optional tmdb.
/// Both normalize into a uniform [ContentItem] with a stable id, a flattened
/// episodes list (season number attached), and tmdb-aware art resolution.

class ServerSource {
  final int serverNumber;
  final String url;
  final String rawUrl;

  const ServerSource({
    required this.serverNumber,
    required this.url,
    required this.rawUrl,
  });

  factory ServerSource.fromJson(Map<String, dynamic> j) => ServerSource(
        serverNumber: (j['server_number'] as num?)?.toInt() ?? 1,
        url: j['url'] as String? ?? '',
        rawUrl: j['raw_url'] as String? ?? '',
      );
}

class Episode {
  final int episodeNumber;
  final String? episodeId;
  final String episodeTitle;

  /// PAGE url — used to fetch fresh tokens, NOT the video url.
  final String episodeUrl;
  final List<ServerSource> servers;
  final int? seasonNumber;

  const Episode({
    required this.episodeNumber,
    this.episodeId,
    required this.episodeTitle,
    required this.episodeUrl,
    required this.servers,
    this.seasonNumber,
  });

  factory Episode.fromJson(Map<String, dynamic> j, {int? seasonNumber}) =>
      Episode(
        episodeNumber: (j['episode_number'] as num?)?.toInt() ?? 0,
        episodeId: j['episode_id']?.toString(),
        episodeTitle: j['episode_title'] as String? ?? '',
        episodeUrl: j['episode_url'] as String? ?? '',
        servers: ((j['servers'] as List?) ?? const [])
            .map((e) => ServerSource.fromJson(e as Map<String, dynamic>))
            .toList(),
        seasonNumber: seasonNumber,
      );

  /// Per-episode thumbnail from the arabic-toons CDN, with a fallback.
  String thumbnail(String fallback) => episodeId != null
      ? 'https://www.arabic-toons.com/images/anime/mqdefault_$episodeId.jpg'
      : fallback;
}

class Season {
  final int seasonNumber;
  final String seasonTitle;
  final String id; // season_id
  final String? slug;
  final String thumbnailUrl;
  final String? pageUrl;
  final int totalEpisodes;
  final List<Episode> episodes;

  const Season({
    required this.seasonNumber,
    required this.seasonTitle,
    required this.id,
    this.slug,
    required this.thumbnailUrl,
    this.pageUrl,
    required this.totalEpisodes,
    required this.episodes,
  });

  factory Season.fromJson(Map<String, dynamic> j) {
    final n = (j['season_number'] as num?)?.toInt() ?? 1;
    return Season(
      seasonNumber: n,
      seasonTitle: j['season_title'] as String? ?? '',
      id: j['id']?.toString() ?? '',
      slug: j['slug'] as String?,
      thumbnailUrl: j['thumbnail_url'] as String? ?? '',
      pageUrl: j['page_url'] as String?,
      totalEpisodes: (j['total_episodes'] as num?)?.toInt() ??
          ((j['episodes'] as List?)?.length ?? 0),
      episodes: ((j['episodes'] as List?) ?? const [])
          .map((e) =>
              Episode.fromJson(e as Map<String, dynamic>, seasonNumber: n))
          .toList(),
    );
  }
}

class TmdbData {
  final String? posterUrl;
  final String? posterUrlW500;
  final String? backdropUrl;
  final String? overviewAr;
  final String? overviewEn;
  final List<String> genres;
  final int? year;

  /// Internal popularity signal only — NEVER displayed in the UI.
  final double? voteAverage;

  /// Total TMDB rating count — the best "is this famous" proxy. Internal only.
  final int? voteCount;

  /// TMDB trending score. Internal ranking signal only; never displayed.
  final double? popularity;

  const TmdbData({
    this.posterUrl,
    this.posterUrlW500,
    this.backdropUrl,
    this.overviewAr,
    this.overviewEn,
    this.genres = const [],
    this.year,
    this.voteAverage,
    this.voteCount,
    this.popularity,
  });

  factory TmdbData.fromJson(Map<String, dynamic> j) => TmdbData(
        posterUrl: j['poster_url'] as String?,
        posterUrlW500: j['poster_url_w500'] as String?,
        backdropUrl: j['backdrop_url'] as String?,
        overviewAr: j['overview_ar'] as String?,
        overviewEn: j['overview_en'] as String?,
        genres: ((j['genres'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
        year: (j['year'] as num?)?.toInt(),
        voteAverage: (j['vote_average'] as num?)?.toDouble(),
        voteCount: (j['vote_count'] as num?)?.toInt(),
        popularity: (j['popularity'] as num?)?.toDouble(),
      );
}

/// Base for Show | Movie.
sealed class ContentItem {
  String get id;
  String get title;
  String get thumbnailUrl;
  String get description;
  TmdbData? get tmdb;
  String get type;

  /// Which catalog this item came from — drives the playback path (direct
  /// tokenized URL vs. the Stardima resolver).
  CatalogSource get source;

  /// Browse/filter categories. Arabic Toons uses [genres] (TMDB); Stardima maps
  /// its single `category` here. Empty when the item is uncategorised.
  List<String> get categories => genres;

  /// Card poster — tmdb w500 → tmdb poster(downsized) → thumbnail.
  String get posterUrl {
    final t = tmdb;
    if (t?.posterUrlW500 != null) return t!.posterUrlW500!;
    final p = tmdbCardPoster(t?.posterUrl);
    if (p != null) return p;
    return thumbnailUrl;
  }

  /// Hero/detail backdrop — tmdb backdrop → tmdb poster → thumbnail.
  String get backdropUrl {
    final t = tmdb;
    final b = tmdbHeroBackdrop(t?.backdropUrl);
    if (b != null) return b;
    if (t?.posterUrlW500 != null) return t!.posterUrlW500!;
    return thumbnailUrl;
  }

  /// Arabic-first description: tmdb overview_ar → overview_en → scraped → ''.
  String get descriptionAr {
    final t = tmdb;
    return t?.overviewAr?.isNotEmpty == true
        ? t!.overviewAr!
        : (description.isNotEmpty
            ? description
            : (t?.overviewEn ?? ''));
  }

  List<String> get genres => tmdb?.genres ?? const [];
  int? get year => tmdb?.year;

  /// Internal popularity score (TMDB vote average; never shown). Items without
  /// a tmdb match sort to the bottom.
  double get popularity => tmdb?.voteAverage ?? 0;

  /// Raw TMDB rating count (internal). Null until the catalog is enriched.
  int? get voteCount => tmdb?.voteCount;

  /// TMDB trending score (internal tiebreak). Null until enriched.
  double? get tmdbPopularity => tmdb?.popularity;

  /// Bayesian weighted rating — denoises tiny-sample vote_averages (a 1–2 vote
  /// 10.0 gets pulled toward the catalog mean). Falls back to the raw
  /// vote_average when vote_count is unknown (pre-enrichment).
  double get weightedRating {
    final v = tmdb?.voteCount;
    final r = tmdb?.voteAverage ?? 0;
    if (v == null) return r;
    return (v / (v + kFameBayesPrior)) * r +
        (kFameBayesPrior / (v + kFameBayesPrior)) * kFameMeanVote;
  }

  /// Eligible for the curated "famous" Home pools.
  bool get isFamous => (tmdb?.voteCount ?? 0) >= kFameVoteFloor;

  /// Primary fame ranking scalar (higher = more famous). Uses vote_count when
  /// known — a title everyone watched accrues many votes — else the denoised
  /// rating so an un-enriched catalog still orders sensibly.
  double get fameScore {
    final v = tmdb?.voteCount;
    return v != null ? v.toDouble() : weightedRating;
  }
}

class Show extends ContentItem {
  @override
  final String id;
  @override
  final String title;
  @override
  final String thumbnailUrl;
  @override
  final String description;
  @override
  final TmdbData? tmdb;

  final int totalEpisodes;
  final int seasonCount;
  final List<Season> seasons;
  final List<Episode> episodes; // flattened across all seasons
  final String? pageUrl;
  @override
  final CatalogSource source;

  Show({
    required this.id,
    required this.title,
    required this.thumbnailUrl,
    required this.description,
    this.tmdb,
    required this.totalEpisodes,
    required this.seasonCount,
    required this.seasons,
    required this.episodes,
    this.pageUrl,
    this.source = CatalogSource.arabicToons,
  });

  @override
  String get type => 'show';

  /// Stable id used for dedupe/merge: per-season source ids joined, or slug.
  static String computeId(Map<String, dynamic> raw) {
    final ids = (raw['ids'] as List?)?.map((e) => e.toString()).toList();
    if (ids != null && ids.isNotEmpty) return ids.join('_');
    return raw['slug']?.toString() ?? '';
  }

  factory Show.fromJson(Map<String, dynamic> raw) {
    final seasons = ((raw['seasons'] as List?) ?? const [])
        .map((e) => Season.fromJson(e as Map<String, dynamic>))
        .toList();
    final flat = <Episode>[];
    for (final s in seasons) {
      flat.addAll(s.episodes);
    }
    return Show(
      id: computeId(raw),
      title: raw['title'] as String? ?? '',
      thumbnailUrl: raw['thumbnail_url'] as String? ??
          (seasons.isNotEmpty ? seasons.first.thumbnailUrl : ''),
      description: raw['description'] as String? ?? '',
      tmdb: raw['tmdb'] != null
          ? TmdbData.fromJson(raw['tmdb'] as Map<String, dynamic>)
          : null,
      totalEpisodes: (raw['total_episodes'] as num?)?.toInt() ?? flat.length,
      seasonCount: (raw['season_count'] as num?)?.toInt() ?? seasons.length,
      seasons: seasons,
      episodes: flat,
      pageUrl: seasons.isNotEmpty ? seasons.first.pageUrl : null,
    );
  }
}

class Movie extends ContentItem {
  @override
  final String id;
  @override
  final String title;
  @override
  final String thumbnailUrl;
  @override
  final String description;
  @override
  final TmdbData? tmdb;

  final String pageUrl;
  final List<ServerSource> servers;
  @override
  final CatalogSource source;

  Movie({
    required this.id,
    required this.title,
    required this.thumbnailUrl,
    required this.description,
    this.tmdb,
    required this.pageUrl,
    required this.servers,
    this.source = CatalogSource.arabicToons,
  });

  @override
  String get type => 'movie';

  static String computeId(Map<String, dynamic> raw) => raw['id'].toString();

  factory Movie.fromJson(Map<String, dynamic> raw) => Movie(
        id: computeId(raw),
        title: raw['title'] as String? ?? '',
        thumbnailUrl: raw['thumbnail_url'] as String? ?? '',
        description: raw['description'] as String? ?? '',
        tmdb: raw['tmdb'] != null
            ? TmdbData.fromJson(raw['tmdb'] as Map<String, dynamic>)
            : null,
        pageUrl: raw['page_url'] as String? ?? '',
        servers: ((raw['servers'] as List?) ?? const [])
            .map((e) => ServerSource.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

bool isShow(ContentItem i) => i is Show;
bool isMovie(ContentItem i) => i is Movie;
