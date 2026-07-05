import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/content_item.dart';
import '../services/wcoflix/wcoflix_adapter.dart';
import '../services/wcoflix/wcoflix_catalog.dart';
import '../services/wcoflix/wcoflix_parsers.dart';
import 'app_state.dart';

/// Riverpod wiring for the WCOFlix "Everything" universe. All of this is inert
/// while [everythingModeProvider] is false (the default) — the Arabic path is
/// untouched.

/// Persisted Everything-mode toggle. Off = the bundled Arabic-dubbed catalog.
class EverythingModeNotifier extends Notifier<bool> {
  @override
  bool build() => ref.read(storageProvider).getEverythingMode();

  Future<void> set(bool on) async {
    if (on == state) return;
    await ref.read(storageProvider).setEverythingMode(on);
    state = on;
  }

  Future<void> toggle() => set(!state);
}

final everythingModeProvider =
    NotifierProvider<EverythingModeNotifier, bool>(EverythingModeNotifier.new);

/// Single live WCOFlix catalog client (its own TTL cache) for the app's life.
final wcoflixCatalogProvider = Provider<WcoflixCatalog>((ref) => WcoflixCatalog());

List<ContentItem> _cards(List<WcoLink> links) =>
    [for (final l in links) wcoflixShowStub(l)];

/// Curated home rows (each a list of card stubs). Cached by the catalog client.
final wcoPopularProvider = FutureProvider<List<ContentItem>>(
    (ref) async => _cards(await ref.read(wcoflixCatalogProvider).popular()));
final wcoLatestProvider = FutureProvider<List<ContentItem>>(
    (ref) async => _cards(await ref.read(wcoflixCatalogProvider).latest()));
final wcoCartoonsProvider = FutureProvider<List<ContentItem>>(
    (ref) async => _cards(await ref.read(wcoflixCatalogProvider).cartoons()));
final wcoDubbedProvider = FutureProvider<List<ContentItem>>(
    (ref) async => _cards(await ref.read(wcoflixCatalogProvider).dubbedAnime()));
final wcoMoviesProvider = FutureProvider<List<ContentItem>>(
    (ref) async => _cards(await ref.read(wcoflixCatalogProvider).movies()));

/// A browse category by key ('cartoons'|'dubbed'|'movies'|'ova').
final wcoCategoryProvider =
    FutureProvider.family<List<ContentItem>, String>((ref, key) async {
  final c = ref.read(wcoflixCatalogProvider);
  switch (key) {
    case 'dubbed':
      return _cards(await c.dubbedAnime());
    case 'movies':
      return _cards(await c.movies());
    case 'ova':
      return _cards(await c.ova());
    case 'cartoons':
    default:
      return _cards(await c.cartoons());
  }
});

/// Combined "TV Shows" browse pool for Everything mode: cartoons + dubbed
/// anime, deduped by id. The grid renders lazily, so the large list is cheap.
final wcoTvBrowseProvider = FutureProvider<List<ContentItem>>((ref) async {
  final c = ref.read(wcoflixCatalogProvider);
  final cartoons = await c.cartoons();
  final dubbed = await c.dubbedAnime();
  final seen = <String>{};
  final out = <ContentItem>[];
  for (final l in [...cartoons, ...dubbed]) {
    final s = wcoflixShowStub(l);
    if (seen.add(s.id)) out.add(s);
  }
  return out;
});

/// Live full-catalog search (series). Debounce at the call site.
final wcoSearchProvider =
    FutureProvider.family<List<ContentItem>, String>((ref, query) async {
  final q = query.trim();
  if (q.isEmpty) return const [];
  return _cards(await ref.read(wcoflixCatalogProvider).search(q));
});

/// Full show (poster/plot/episodes) for a WCOFlix series page URL.
final wcoSeriesProvider =
    FutureProvider.family<Show, String>((ref, pageUrl) async {
  final c = ref.read(wcoflixCatalogProvider);
  final series = await c.seriesDetail(pageUrl);
  // Title: reuse the stub's cleaned title derived from the slug if the page
  // has none. The series page rarely exposes a clean title, so fall back to the
  // slug's words.
  final slug = wcoflixId(pageUrl).replaceAll('-', ' ');
  final title = slug.isEmpty
      ? pageUrl
      : slug.split(' ').map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
  return wcoflixShowFromSeries(pageUrl, series, title);
});
