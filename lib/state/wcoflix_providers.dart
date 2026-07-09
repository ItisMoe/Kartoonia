import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/content_item.dart';
import '../services/wcoflix/wcoflix_adapter.dart';
import '../services/wcoflix/wcoflix_catalog.dart';
import '../services/wcoflix/wcoflix_match.dart';
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

/// Single live WCOFlix catalog client (snapshot fallback + session cache).
final wcoflixCatalogProvider = Provider<WcoflixCatalog>((ref) => WcoflixCatalog());

/// Build cards, attaching bundled TMDB art (poster/backdrop/popularity) when the
/// title was matched. [cat.ensureArt] must have completed first.
List<ContentItem> _cards(WcoflixCatalog cat, List<WcoLink> links) =>
    [for (final l in links) wcoflixCardStub(l, tmdb: cat.artFor(l.url))];

/// Snapshot-first: return the bundled snapshot immediately so a row never shows
/// empty, and kick off a background live fetch that refreshes this provider
/// (swapping in fresh titles) once it lands. Live wins once available.
Future<List<WcoLink>> _liveOrSnapshot(Ref ref, String key) async {
  final cat = ref.read(wcoflixCatalogProvider);
  await cat.ensureArt();
  final live = cat.live(key);
  if (live != null) return live;
  unawaited(cat.fetchLive(key).then((_) {
    if (cat.live(key) != null) ref.invalidateSelf();
  }));
  return cat.snapshot(key);
}

final wcoPopularProvider = FutureProvider<List<ContentItem>>((ref) async =>
    _cards(ref.read(wcoflixCatalogProvider), await _liveOrSnapshot(ref, 'popular')));
final wcoLatestProvider = FutureProvider<List<ContentItem>>((ref) async =>
    _cards(ref.read(wcoflixCatalogProvider), await _liveOrSnapshot(ref, 'latest')));
final wcoCartoonsProvider = FutureProvider<List<ContentItem>>((ref) async =>
    _cards(ref.read(wcoflixCatalogProvider), await _liveOrSnapshot(ref, 'cartoons')));
final wcoDubbedProvider = FutureProvider<List<ContentItem>>((ref) async =>
    _cards(ref.read(wcoflixCatalogProvider), await _liveOrSnapshot(ref, 'dubbed')));
final wcoMoviesProvider = FutureProvider<List<ContentItem>>((ref) async =>
    _cards(ref.read(wcoflixCatalogProvider), await _liveOrSnapshot(ref, 'movies')));

/// The Everything-mode Home pool: the most TMDB-famous titles (vote_count desc)
/// across the whole catalog, WITH posters/backdrops — so Home leads with the
/// familiar, well-known shows exactly like the Arabic Home (which ranks by
/// fame). Home slices this into rows + a backdrop hero. Deduped by TMDB id/title.
final wcoFamousProvider = FutureProvider<List<ContentItem>>((ref) async {
  final cat = ref.read(wcoflixCatalogProvider);
  return _cards(cat, await cat.famousPool(limit: 400));
});

/// Fame-ranked SERIES pool (a dedicated Home row).
final wcoFamousSeriesProvider = FutureProvider<List<ContentItem>>((ref) async {
  final cat = ref.read(wcoflixCatalogProvider);
  return _cards(cat, await cat.famousPool(limit: 120, type: 'tv'));
});

/// Fame-ranked MOVIES pool (a dedicated Home row).
final wcoFamousMoviesProvider = FutureProvider<List<ContentItem>>((ref) async {
  final cat = ref.read(wcoflixCatalogProvider);
  return _cards(cat, await cat.famousPool(limit: 120, type: 'movie'));
});

/// Fame-ranked pool restricted to titles that have a backdrop — the Home hero.
final wcoHeroProvider = FutureProvider<List<ContentItem>>((ref) async {
  final cat = ref.read(wcoflixCatalogProvider);
  return _cards(cat, await cat.famousPool(limit: 12, withBackdrop: true));
});

/// Combined "TV Shows" browse pool for Everything mode: cartoons + dubbed anime,
/// deduped by id. Snapshot-first for each half.
final wcoTvBrowseProvider = FutureProvider<List<ContentItem>>((ref) async {
  final cat = ref.read(wcoflixCatalogProvider);
  final cartoons = await _liveOrSnapshot(ref, 'cartoons');
  final dubbed = await _liveOrSnapshot(ref, 'dubbed');
  final seen = <String>{};
  final out = <ContentItem>[];
  for (final l in [...cartoons, ...dubbed]) {
    final s = wcoflixShowStub(l, tmdb: cat.artFor(l.url));
    if (seen.add(s.id)) out.add(s);
  }
  return out;
});

/// Everything-mode search — runs LOCALLY against the bundled enriched catalog
/// (8k+ titles with TMDB art). Instant, and immune to the Cloudflare wall that
/// the live POST /search now sits behind. Soft-fails to an empty list.
final wcoSearchProvider =
    FutureProvider.family<List<ContentItem>, String>((ref, query) async {
  final q = query.trim();
  if (q.isEmpty) return const [];
  final cat = ref.read(wcoflixCatalogProvider);
  return _cards(cat, await cat.searchLocal(q));
});

/// The WCOFlix "original" (English) match for an Arabic title, found by
/// searching the live catalog for [enTitle] and title-matching the results.
/// Returns a card stub (episodes load lazily via [wcoSeriesProvider]) or null
/// when there's no confident match. Powers the detail Audio: Arabic↔Original
/// switch. Fails soft: any error just yields null (no switch shown).
final wcoflixOriginalProvider =
    FutureProvider.family<Show?, String>((ref, enTitle) async {
  final q = enTitle.trim();
  if (q.length < 2) return null;
  try {
    final cat = ref.read(wcoflixCatalogProvider);
    final links = await cat.searchLocal(q);
    final match = bestWcoflixMatch(q, links);
    return match == null ? null : wcoflixShowStub(match, tmdb: cat.artFor(match.url));
  } catch (_) {
    return null;
  }
});

/// Full show (poster/plot/episodes) for a WCOFlix series page URL.
final wcoSeriesProvider =
    FutureProvider.family<Show, String>((ref, pageUrl) async {
  final c = ref.read(wcoflixCatalogProvider);
  await c.ensureArt();
  final series = await c.seriesDetail(pageUrl);
  final tmdb = c.artFor(pageUrl);
  // Prefer the TMDB English title when we have a match; else prettify the slug.
  final slug = wcoflixId(pageUrl).replaceAll('-', ' ');
  final title = tmdb?.enTitle?.isNotEmpty == true
      ? tmdb!.enTitle!
      : slug.isEmpty
          ? pageUrl
          : slug
              .split(' ')
              .map((w) =>
                  w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
              .join(' ');
  return wcoflixShowFromSeries(pageUrl, series, title, tmdb: tmdb);
});
