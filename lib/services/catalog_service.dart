import '../models/catalog_source.dart';
import '../models/content_item.dart';
import 'catalog_loader.dart';
import 'fame_ranking.dart';

/// Loads, indexes and queries a bundled catalog. The active source (Arabic Toons
/// or Stardima) is chosen by the persisted setting; each has its own parser but
/// both normalize into the same [ContentItem] model, so every query/render path
/// below is source-agnostic.
/// Ported + extended from the RN `catalogService.ts` (adds genres; drops
/// ratings).

class CatalogService {
  /// The catalog currently loaded into memory.
  CatalogSource source;

  List<Show> shows = const [];
  List<Movie> movies = const [];
  List<ContentItem> all = const [];
  Map<String, ContentItem> _byId = const {};

  /// tmdbId -> {source: item} for ids present (exactly once) in BOTH sources.
  /// Drives the detail-screen source toggle and the collapsed library.
  Map<int, Map<CatalogSource, ContentItem>> _groups = const {};

  // Memoized famous pools + genre rows. Each [famousPool]/[genreRowsFor] pass
  // filters and sorts the WHOLE catalog (~3k items); Home alone asks for these
  // ~7× per build and rebuilds on every user/settings change. Computing once
  // and caching turns that from ~7 full sorts per frame into zero. Cleared by
  // [_invalidateDerived] whenever the loaded catalog changes.
  List<ContentItem>? _popularPool;
  List<Show>? _popularShows;
  List<Movie>? _popularMovies;
  List<ContentItem>? _featuredPool;
  List<MapEntry<String, List<ContentItem>>>? _genreRows;
  List<(ContentItem, String)>? _searchIndex;

  void _invalidateDerived() {
    _popularPool = null;
    _popularShows = null;
    _popularMovies = null;
    _featuredPool = null;
    _genreRows = null;
    _searchIndex = null;
  }

  CatalogService._(this.source);

  /// An empty, render-safe catalog — every query returns nothing. The app
  /// boots against this instantly (the splash shows while the real catalogs
  /// parse in background isolates), then [loadMergedInPlace] fills it in.
  factory CatalogService.empty() => CatalogService._(CatalogSource.arabicToons);

  static Future<CatalogService> load(CatalogSource source) async {
    final svc = CatalogService._(source);
    await svc._loadSource(source);
    return svc;
  }

  /// Load BOTH bundled catalogs into one merged library. A title present in
  /// both sources is collapsed to a single entry (its Arabic Toons primary);
  /// the Stardima twin stays reachable via [alternateFor] and [getById]. Items
  /// keep their own [ContentItem.source], so playback dispatches correctly.
  static Future<CatalogService> loadMerged() async {
    final svc = CatalogService._(CatalogSource.arabicToons);
    await svc.loadMergedInPlace();
    return svc;
  }

  /// [loadMerged], but populating THIS instance — so the app can hand an
  /// [CatalogService.empty] service to the UI immediately and fill it once the
  /// background parse lands. All heavy work (I/O, JSON decode, model build)
  /// happens off the UI isolate; sources load sequentially ON PURPOSE — two
  /// catalogs decoding at once doubles peak memory, which a 1 GB TV box
  /// can't afford.
  Future<void> loadMergedInPlace() async {
    // Arabic Toons (legacy schema). Loads the freshest valid data: a cached
    // GitHub download when present, else the bundled asset.
    final at = await loadCatalogModels(CatalogSource.arabicToons);
    final atShows = at.shows;
    final atMovies = at.movies;

    // Stardima (adapter).
    final st = await loadCatalogModels(CatalogSource.stardima);
    final stShows = st.shows;
    final stMovies = st.movies;
    final svc = this;

    // Index items by tmdbId per source. A tmdbId can map to more than one item
    // within a source (ambiguous/duplicate TMDB matches), so we count them.
    final atById = <int, List<ContentItem>>{};
    final stById = <int, List<ContentItem>>{};
    for (final i in [...atShows, ...atMovies]) {
      final id = i.tmdbId;
      if (id != null) (atById[id] ??= []).add(i);
    }
    for (final i in [...stShows, ...stMovies]) {
      final id = i.tmdbId;
      if (id != null) (stById[id] ??= []).add(i);
    }

    // Collapsible groups: a tmdbId present EXACTLY once in each source — a clean
    // 1:1 cross-source pair. Ambiguous ids (>1 per source) are left as separate
    // cards to avoid merging distinct titles that share a bad TMDB match.
    final groups = <int, Map<CatalogSource, ContentItem>>{};
    for (final entry in atById.entries) {
      final st = stById[entry.key];
      if (entry.value.length == 1 && st != null && st.length == 1) {
        groups[entry.key] = {
          CatalogSource.arabicToons: entry.value.first,
          CatalogSource.stardima: st.first,
        };
      }
    }
    svc._groups = groups;

    // Collapsed library: keep every Arabic Toons item; drop the Stardima twin
    // of each clean pair (it stays reachable via alternateFor/_byId).
    final collapsedStIds = {
      for (final g in groups.values) g[CatalogSource.stardima]!.id
    };
    svc.shows =
        [...atShows, ...stShows.where((s) => !collapsedStIds.contains(s.id))];
    svc.movies =
        [...atMovies, ...stMovies.where((m) => !collapsedStIds.contains(m.id))];
    svc.all = [...svc.shows, ...svc.movies];

    // _byId holds BOTH copies so progress/watchlist saved against either id
    // still resolves.
    svc._byId = {};
    for (final i in [...atShows, ...atMovies, ...stShows, ...stMovies]) {
      svc._byId.putIfAbsent(i.id, () => i);
    }
    svc._invalidateDerived();
  }

  /// True when this title exists in BOTH sources (so the detail screen offers a
  /// source toggle).
  bool isDuplicated(ContentItem item) => alternateFor(item) != null;

  /// The other-source twin of [item] (Arabic Toons <-> Stardima), or null when
  /// the title exists in only one source.
  ContentItem? alternateFor(ContentItem item) {
    final id = item.tmdbId;
    if (id == null) return null;
    final g = _groups[id];
    if (g == null) return null;
    final other = item.source == CatalogSource.arabicToons
        ? CatalogSource.stardima
        : CatalogSource.arabicToons;
    return g[other];
  }

  /// The Arabic Toons primary of [item]'s group, or [item] when it is not part
  /// of a cross-source group.
  ContentItem primaryFor(ContentItem item) {
    final id = item.tmdbId;
    if (id == null) return item;
    return _groups[id]?[CatalogSource.arabicToons] ?? item;
  }

  /// Swap the active catalog in place (re-fetch asset, re-parse, re-index) so
  /// the UI can rebuild against the newly selected source from scratch.
  Future<void> switchTo(CatalogSource next) async {
    if (next == source && _byId.isNotEmpty) return;
    await _loadSource(next);
  }

  Future<void> _loadSource(CatalogSource src) async {
    // WCOFlix is a live-scraped catalog served by WcoflixCatalog, not a bundled
    // asset — it is never loaded into this in-memory CatalogService. Guard here
    // so the enum stays exhaustive without touching the Arabic-mode paths.
    if (src == CatalogSource.wcoflix) {
      source = src;
      shows = const [];
      movies = const [];
      all = const [];
      _byId = const {};
      _invalidateDerived();
      return;
    }
    // Parsed off the UI isolate — a mid-session source switch used to freeze
    // the settings screen for the whole decode.
    final parsed = await loadCatalogModels(src);
    source = src;
    shows = parsed.shows;
    movies = parsed.movies;
    all = [...shows, ...movies];
    _byId = {for (final i in all) i.id: i};
    _invalidateDerived();
  }

  ContentItem? getById(String id) => _byId[id];

  // ---- Fame ranking (internal ordering only; vote_average is never shown) ----
  // All memoized (see [_invalidateDerived]) — these sort the whole catalog.
  /// Curated famous pool (denoised by vote_count), highest fame first.
  List<ContentItem> popularPool() => _popularPool ??= famousPool(all);

  List<Show> popularShows() => _popularShows ??= famousPool(shows);

  List<Movie> popularMovies() => _popularMovies ??= famousPool(movies);

  /// Highest-popularity titles for the curated "Most Popular" row.
  List<ContentItem> mostPopular({int count = 30}) =>
      popularPool().take(count).toList();

  // ---- Featured (hero): popular titles that have a backdrop ----
  /// Pool the rotating hero is drawn from: most-popular items with a backdrop.
  List<ContentItem> getFeaturedPool() {
    if (_featuredPool != null) return _featuredPool!;
    final pool = popularPool();
    final withBackdrop =
        pool.where((i) => i.tmdb?.backdropUrl != null).toList();
    return _featuredPool = withBackdrop.isNotEmpty ? withBackdrop : pool;
  }

  List<ContentItem> getFeatured({int count = 5}) =>
      getFeaturedPool().take(count).toList();

  /// Candidate pool for the rotating Top-10 row — drawn from the popular pool.
  List<ContentItem> getTop10Pool() => popularPool();

  /// Top-10 proxy (no ratings): most popular, in popularity order.
  List<ContentItem> getTop10() => getTop10Pool().take(10).toList();

  List<Show> getRecentShows({int count = 20}) => shows.take(count).toList();
  List<Movie> getRecentMovies({int count = 20}) => movies.take(count).toList();

  // ---- Search: Arabic title + English/original title + description + overviews
  // The English ([TmdbData.enTitle]) and original ([TmdbData.originalTitle])
  // titles let an Arabic-only catalog title still surface from a Latin query
  // (e.g. typing "Hunter" finds القناص = "Hunter x Hunter").
  List<ContentItem> search(String query) {
    final q = normalizeArSearch(query.toLowerCase().trim());
    if (q.isEmpty) return const [];
    // One normalized haystack per item, built once per catalog load (first
    // search pays it) instead of re-normalizing every field of every item on
    // EVERY keystroke — that was the whole-catalog × 6-fields typing lag.
    // Fields are joined with '\n' so a query can't accidentally match across
    // a field boundary.
    final index = _searchIndex ??= [
      for (final i in all)
        (
          i,
          normalizeArSearch([
            i.title,
            i.tmdb?.enTitle ?? '',
            i.tmdb?.originalTitle ?? '',
            i.description,
            i.tmdb?.overviewEn ?? '',
            i.tmdb?.overviewAr ?? '',
          ].join('\n').toLowerCase()),
        ),
    ];
    return [
      for (final (item, hay) in index)
        if (hay.contains(q)) item,
    ];
  }

  // ---- Genres ----
  List<String> getAllGenres() => genresIn(all);

  List<ContentItem> byGenre(String genre) =>
      all.where((i) => i.genres.contains(genre)).toList();

  /// Genre rows for Home: genres with >= [min] items, capped at [cap] rows,
  /// each row's items fame-sorted (most famous first). The sort lives here —
  /// memoized — because both Home screens used to re-sort every genre row on
  /// EVERY build, which the hero autoplay triggered continuously.
  /// Memoized (default args only) — the whole-catalog genre scan is expensive.
  List<MapEntry<String, List<ContentItem>>> genreRows(
      {int min = 4, int cap = 6}) {
    if (min == 4 && cap == 6) {
      return _genreRows ??= _fameSortedGenreRows(min: min, cap: cap);
    }
    return _fameSortedGenreRows(min: min, cap: cap);
  }

  List<MapEntry<String, List<ContentItem>>> _fameSortedGenreRows(
          {required int min, required int cap}) =>
      [
        for (final e in genreRowsFor(all, min: min, cap: cap))
          MapEntry(e.key,
              e.value..sort((a, b) => b.fameScore.compareTo(a.fameScore))),
      ];

  // ---- Browse filtering + sorting (no rating sort) ----
  List<ContentItem> browse(String kind) {
    switch (kind) {
      case 'movies':
        return List.of(movies);
      case 'tv':
        return List.of(shows);
      default:
        return List.of(all);
    }
  }
}

/// Arabic-aware first letter for the A–Z browse bar (from the design).
String firstLetterFor(String title, String script) {
  final t = title.trim();
  if (t.isEmpty) return '';
  var ch = t[0];
  if (script == 'ar') {
    ch = ch
        .replaceAll(RegExp('[آأإٱ]'), 'ا')
        .replaceAll('ى', 'ي')
        .replaceAll('ة', 'ه');
    return ch;
  }
  return ch.toUpperCase();
}

// Compiled once, not per call: search runs [normalizeArSearch] tens of
// thousands of times per keystroke (every item × every searchable field), and
// recompiling these regexes each time was pure overhead on the typing path.
final RegExp _reAlef = RegExp('[آأإٱ]');
final RegExp _reTashkeel = RegExp('[ً-ْٰ]');

/// Fold Arabic letter variants to a single canonical form so search matches
/// regardless of which form the user typed or the title stored: every alef
/// variant -> ا, taa marbuta -> ه, alef maqsura -> ي, waw/yaa-hamza -> و/ي,
/// and the bare hamza is dropped. Also strips tashkeel (diacritics).
String normalizeArSearch(String s) => s
    .replaceAll(_reAlef, 'ا')
    .replaceAll('ى', 'ي')
    .replaceAll('ئ', 'ي')
    .replaceAll('ة', 'ه')
    .replaceAll('ؤ', 'و')
    .replaceAll('ء', '')
    .replaceAll(_reTashkeel, '');

const alphaEn = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
const alphaAr = 'ابتثجحخدذرزسشصضطظعغفقكلمنهوي';
