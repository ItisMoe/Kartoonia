import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models/catalog_source.dart';
import '../models/content_item.dart';
import '../models/stardima_adapter.dart';
import 'fame_ranking.dart';

/// Loads, indexes and queries a bundled catalog. The active source (Arabic Toons
/// or Stardima) is chosen by the persisted setting; each has its own parser but
/// both normalize into the same [ContentItem] model, so every query/render path
/// below is source-agnostic.
/// Ported + extended from the RN `catalogService.ts` (adds genres; drops
/// ratings).

class CatalogService {
  List<Map<String, dynamic>> _rawShows = [];
  List<Map<String, dynamic>> _rawMovies = [];

  /// The catalog currently loaded into memory.
  CatalogSource source;

  late List<Show> shows;
  late List<Movie> movies;
  late List<ContentItem> all;
  late Map<String, ContentItem> _byId;

  /// tmdbId -> {source: item} for ids present (exactly once) in BOTH sources.
  /// Drives the detail-screen source toggle and the collapsed library.
  Map<int, Map<CatalogSource, ContentItem>> _groups = const {};

  CatalogService._(this.source);

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

    // Arabic Toons (legacy schema).
    final atStr =
        await rootBundle.loadString(CatalogSource.arabicToons.assetPath);
    final atData = jsonDecode(atStr) as Map<String, dynamic>;
    final atShows = ((atData['shows'] as List?) ?? const [])
        .map((e) => Show.fromJson((e as Map).cast<String, dynamic>()))
        .toList();
    final atMovies = ((atData['movies'] as List?) ?? const [])
        .map((e) => Movie.fromJson((e as Map).cast<String, dynamic>()))
        .toList();

    // Stardima (adapter).
    final stStr = await rootBundle.loadString(CatalogSource.stardima.assetPath);
    final stData = jsonDecode(stStr) as Map<String, dynamic>;
    final (stShows, stMovies) = StardimaAdapter.parse(stData);

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
    return svc;
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
    final jsonStr = await rootBundle.loadString(src.assetPath);
    final data = jsonDecode(jsonStr) as Map<String, dynamic>;
    source = src;
    switch (src) {
      case CatalogSource.arabicToons:
        _rawShows = ((data['shows'] as List?) ?? const [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        _rawMovies = ((data['movies'] as List?) ?? const [])
            .map((e) => (e as Map).cast<String, dynamic>())
            .toList();
        shows = _rawShows.map(Show.fromJson).toList();
        movies = _rawMovies.map(Movie.fromJson).toList();
      case CatalogSource.stardima:
        _rawShows = const [];
        _rawMovies = const [];
        final (s, m) = StardimaAdapter.parse(data);
        shows = s;
        movies = m;
    }
    all = [...shows, ...movies];
    _byId = {for (final i in all) i.id: i};
  }

  ContentItem? getById(String id) => _byId[id];

  // ---- Fame ranking (internal ordering only; vote_average is never shown) ----
  /// Curated famous pool (denoised by vote_count), highest fame first.
  List<ContentItem> popularPool() => famousPool(all);

  List<Show> popularShows() => famousPool(shows);

  List<Movie> popularMovies() => famousPool(movies);

  /// Highest-popularity titles for the curated "Most Popular" row.
  List<ContentItem> mostPopular({int count = 30}) =>
      popularPool().take(count).toList();

  // ---- Featured (hero): popular titles that have a backdrop ----
  /// Pool the rotating hero is drawn from: most-popular items with a backdrop.
  List<ContentItem> getFeaturedPool() {
    final withBackdrop =
        popularPool().where((i) => i.tmdb?.backdropUrl != null).toList();
    return withBackdrop.isNotEmpty ? withBackdrop : popularPool();
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
    bool has(String s) => normalizeArSearch(s.toLowerCase()).contains(q);
    return all.where((i) {
      final t = i.tmdb;
      return has(i.title) ||
          has(t?.enTitle ?? '') ||
          has(t?.originalTitle ?? '') ||
          has(i.description) ||
          has(t?.overviewEn ?? '') ||
          has(t?.overviewAr ?? '');
    }).toList();
  }

  // ---- Genres ----
  List<String> getAllGenres() => genresIn(all);

  List<ContentItem> byGenre(String genre) =>
      all.where((i) => i.genres.contains(genre)).toList();

  /// Genre rows for Home: genres with >= [min] items, capped at [cap] rows.
  List<MapEntry<String, List<ContentItem>>> genreRows(
          {int min = 4, int cap = 6}) =>
      genreRowsFor(all, min: min, cap: cap);

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

/// Fold Arabic letter variants to a single canonical form so search matches
/// regardless of which form the user typed or the title stored: every alef
/// variant -> ا, taa marbuta -> ه, alef maqsura -> ي, waw/yaa-hamza -> و/ي,
/// and the bare hamza is dropped. Also strips tashkeel (diacritics).
String normalizeArSearch(String s) => s
    .replaceAll(RegExp('[آأإٱ]'), 'ا')
    .replaceAll('ى', 'ي')
    .replaceAll('ئ', 'ي')
    .replaceAll('ة', 'ه')
    .replaceAll('ؤ', 'و')
    .replaceAll('ء', '')
    .replaceAll(RegExp('[ً-ْٰ]'), '');

const alphaEn = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
const alphaAr = 'ابتثجحخدذرزسشصضطظعغفقكلمنهوي';
