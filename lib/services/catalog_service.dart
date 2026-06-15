import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import '../models/catalog_source.dart';
import '../models/content_item.dart';
import '../models/stardima_adapter.dart';

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

  CatalogService._(this.source);

  static Future<CatalogService> load(CatalogSource source) async {
    final svc = CatalogService._(source);
    await svc._loadSource(source);
    return svc;
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

  // ---- Popularity (internal ordering only; vote_average is never shown) ----
  /// All items that have a popularity signal, highest first.
  List<ContentItem> popularPool() {
    final pool = all.where((i) => i.popularity > 0).toList()
      ..sort((a, b) => b.popularity.compareTo(a.popularity));
    return pool.isNotEmpty ? pool : List.of(all);
  }

  List<Show> popularShows() {
    final list = shows.where((s) => s.popularity > 0).toList()
      ..sort((a, b) => b.popularity.compareTo(a.popularity));
    return list.isNotEmpty ? list : List.of(shows);
  }

  List<Movie> popularMovies() {
    final list = movies.where((m) => m.popularity > 0).toList()
      ..sort((a, b) => b.popularity.compareTo(a.popularity));
    return list.isNotEmpty ? list : List.of(movies);
  }

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

  // ---- Search: title + description + overviews ----
  List<ContentItem> search(String query) {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return const [];
    return all.where((i) {
      final t = i.tmdb;
      return i.title.toLowerCase().contains(q) ||
          i.description.toLowerCase().contains(q) ||
          (t?.overviewEn ?? '').toLowerCase().contains(q) ||
          (t?.overviewAr ?? '').toLowerCase().contains(q);
    }).toList();
  }

  // ---- Genres ----
  List<String> getAllGenres() {
    final set = <String>{};
    for (final i in all) {
      set.addAll(i.genres);
    }
    final list = set.toList()..sort();
    return list;
  }

  List<ContentItem> byGenre(String genre) =>
      all.where((i) => i.genres.contains(genre)).toList();

  /// Genre rows for Home: genres with >= [min] items, capped at [cap] rows.
  List<MapEntry<String, List<ContentItem>>> genreRows(
      {int min = 4, int cap = 6}) {
    final out = <MapEntry<String, List<ContentItem>>>[];
    for (final g in getAllGenres()) {
      final items = byGenre(g);
      if (items.length >= min) out.add(MapEntry(g, items));
      if (out.length >= cap) break;
    }
    return out;
  }

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

const alphaEn = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
const alphaAr = 'ابتثجحخدذرزسشصضطظعغفقكلمنهوي';
