import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/content_item.dart';
import '../navigation.dart';
import '../playback.dart';
import '../services/recommendations.dart';
import '../services/storage_service.dart';
import '../state/app_state.dart';
import '../state/wcoflix_providers.dart';
import '../theme/theme.dart';
import '../utils/daily_shuffle.dart';
import '../utils/genre_translations.dart';
import '../utils/image_prefetch.dart';
import '../widgets/catalog_image.dart';
import '../widgets/content_card.dart';
import '../widgets/content_row.dart';
import '../widgets/ensure_visible.dart';
import '../widgets/hero_carousel.dart';
import '../widgets/screen_shell.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  // Current hero backdrop URL, mirrored into the letterbox bars on non-16:9
  // panels so the hero reads edge-to-edge (see [_HeroBackdropFill]).
  //
  // A ValueNotifier, NOT setState: the hero autoplay reports a new backdrop
  // every ~6.5s, and a setState here rebuilt the ENTIRE Home screen (every
  // row, every card, every daily shuffle) on each rotation — a periodic jank
  // spike on weak boxes. Only the backdrop fill listens to this now.
  final ValueNotifier<String?> _heroBackdrop = ValueNotifier(null);

  void _onHeroBackdrop(String url) {
    _heroBackdrop.value = url;
  }

  @override
  void dispose() {
    _heroBackdrop.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // refresh continue-watching when returning to home
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(userProvider.notifier).refresh();
      _setupRecommendations();
      // Warm the famous-pool posters so the rows reveal smoothly as the user
      // scrolls (best-effort; covers most Home rows' art).
      if (mounted) prefetchPosters(context, ref.read(catalogProvider).popularPool());
    });
  }

  /// Publish the Google TV home-screen channel + wire deep links (best-effort,
  /// never blocks or crashes the UI).
  Future<void> _setupRecommendations() async {
    final catalog = ref.read(catalogProvider);
    // Refresh the recommended channel from the popular pool (TMDB art).
    Recommendations.publish(catalog.mostPopular(count: 20));
    Recommendations.onDeepLink(handleDeepLink);
    final initial = await Recommendations.initialDeepLink();
    if (initial != null) handleDeepLink(initial);
  }

  String _genreLine(ContentItem s) =>
      s.genres.take(2).map(translateGenre).join(' · ');

  /// Everything mode: leads with the most TMDB-famous titles (with posters +
  /// backdrops), the same way the Arabic Home ranks by popularity — a backdrop
  /// hero + a few fame-ranked rows. Deliberately NOT the raw A–Z lists or a
  /// "new episodes of any show" feed; the full catalog is in Browse + Search.
  Widget _everythingHome(BuildContext context, Map<String, String> t) {
    void open(ContentItem i) => AppNav.detail(context, i);
    final settings = ref.watch(settingsProvider);
    final user = ref.watch(userProvider);
    final famous = ref.watch(wcoFamousProvider);
    final series = ref.watch(wcoFamousSeriesProvider);
    final movies = ref.watch(wcoFamousMoviesProvider);
    final heroItems = ref.watch(wcoHeroProvider).valueOrNull ?? const [];

    // A row drawn from an async fame pool: `skip`/`take` slice it so one pool
    // can feed several distinct rows without repeating a title.
    Widget slice(AsyncValue<List<ContentItem>> pool, String title, int skip,
        int take,
        {bool showLoader = false}) {
      return pool.when(
        loading: () => showLoader ? _wcoLoadingRow(title) : const SizedBox.shrink(),
        error: (_, _) => const SizedBox.shrink(),
        data: (items) {
          final part = items.skip(skip).take(take).toList();
          return part.isEmpty
              ? const SizedBox.shrink()
              : ContentRow(
                  title: title,
                  count: part.length,
                  cards: [
                    for (final i in part)
                      PosterCard(
                          item: i, movieLabel: t['movie']!, onPressed: () => open(i)),
                  ],
                );
        },
      );
    }

    // A full page of popular content, all from the bundled (instant) catalog:
    // a mixed "Most Popular" lead, dedicated Series/Movies rows, then deeper
    // slices of the fame pool so the page keeps scrolling with familiar titles.
    final rows = <Widget>[
      slice(famous, t['most_popular']!, 0, 24, showLoader: true),
      slice(series, t['filter_tv']!, 0, 24),
      slice(movies, t['filter_movies']!, 0, 24),
      slice(famous, t['row_popular']!, 24, 24),
      slice(series, '${t['filter_tv']!} · ${t['row_new']!}', 24, 24),
      slice(movies, '${t['filter_movies']!} · ${t['spotlight']!}', 24, 24),
      slice(famous, t['topten']!, 48, 24),
      slice(series, '${t['filter_tv']!} · ${t['row_popular']!}', 48, 24),
      slice(movies, '${t['filter_movies']!} · ${t['row_popular']!}', 48, 24),
    ];

    final hero = heroItems.isEmpty
        ? const SizedBox(height: 130)
        : HeroCarousel(
            items: heroItems,
            t: t,
            isRtl: settings.isRtl,
            autoplay: settings.prefs['autoplay'] != 'off',
            onPlay: (i) => playItem(context, ref, i),
            onMoreInfo: open,
            onToggleList: (i) => ref.read(userProvider.notifier).toggle(i.id),
            isInList: (i) => user.watchlistIds.contains(i.id),
            onBackdrop: _onHeroBackdrop,
          );

    return ScreenShell(
      current: 'home',
      backdrop: _HeroBackdropFill(_heroBackdrop),
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: hero),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          SliverList(
            delegate:
                SliverChildBuilderDelegate((c, i) => rows[i], childCount: rows.length),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 90)),
        ],
      ),
    );
  }

  Widget _wcoLoadingRow(String title) => Padding(
        padding: const EdgeInsets.symmetric(
            horizontal: Spacing.pad, vertical: 22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontFamily: Fonts.display,
                    fontFamilyFallback: Fonts.fallback,
                    fontWeight: FontWeight.w500,
                    fontSize: 30,
                    color: AppColors.ink)),
            const SizedBox(height: 20),
            const SizedBox(
              height: 40,
              child: Center(
                  child: SizedBox(
                      width: 34,
                      height: 34,
                      child: CircularProgressIndicator(
                          strokeWidth: 3, color: AppColors.primary))),
            ),
          ],
        ),
      );

  /// Press-and-hold a Continue Watching card: Resume, or Remove (clears all of
  /// the title's progress so it leaves the row).
  void _continueWatchingMenu(
      BuildContext context, WidgetRef ref, ContentItem item,
      Map<String, String> t) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bg2,
        title: Text(t['remove_cw_q']!,
            style: const TextStyle(color: AppColors.ink)),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              playItem(context, ref, item);
            },
            child: Text(t['resume']!,
                style: const TextStyle(color: AppColors.inkSoft)),
          ),
          TextButton(
            onPressed: () async {
              await ref.read(storageProvider).removeProgressForItem(item.id);
              Recommendations.removeWatchNext(item.id);
              ref.read(userProvider.notifier).refresh();
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(t['remove']!,
                style: const TextStyle(
                    color: AppColors.primary2, fontWeight: FontWeight.w800)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t['cancel']!,
                style: const TextStyle(color: AppColors.inkSoft)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(catalogRevProvider); // rebuild after imports
    final t = ref.watch(stringsProvider);
    if (ref.watch(everythingModeProvider)) return _everythingHome(context, t);
    final catalog = ref.watch(catalogProvider);
    final settings = ref.watch(settingsProvider);
    final user = ref.watch(userProvider);

    void open(ContentItem i) => AppNav.detail(context, i);

    final rows = <Widget>[];

    // Keep Watching
    // Entries are most-recent first, so the first occurrence of a cross-source
    // group wins; the rest of the group is dropped so a title watched on either
    // source surfaces as one card.
    final continueItems = <(ContentItem, ProgressEntry)>[];
    final seenGroups = <String>{};
    for (final e in user.continueWatching) {
      final item = catalog.getById(e.itemId);
      if (item == null) continue;
      if (!seenGroups.add(catalog.primaryFor(item).id)) continue;
      continueItems.add((item, e));
    }
    if (continueItems.isNotEmpty) {
      rows.add(ContentRow(
        title: t['row_continue']!,
        cards: [
          for (final (item, e) in continueItems)
            PosterCard(
              item: item,
              wide: true,
              progress: e.fraction,
              movieLabel: t['movie']!,
              caption: item is Movie
                  ? t['movie']
                  : '${t['epShort']}${e.episodeNumber}',
              onPressed: () => playItem(context, ref, item),
              onLongPress: () => _continueWatchingMenu(context, ref, item, t),
            ),
        ],
      ));
    }

    // My List (watchlist) — poster row, most-recently-added first.
    final myList = [
      for (final id in user.watchlistIds)
        if (catalog.getById(id) != null) catalog.getById(id)!,
    ];
    if (myList.isNotEmpty) {
      rows.add(ContentRow(
        title: t['nav_mylist']!,
        count: myList.length,
        cards: [
          for (final i in myList)
            PosterCard(
                item: i,
                movieLabel: t['movie']!,
                onPressed: () => open(i)),
        ],
      ));
    }

    // Most Popular — a daily-rotating sample of the famous pool, so the row
    // shows a different slice of well-known titles each day.
    final mostPopular =
        dailyShuffled(catalog.popularPool().take(80).toList(), salt: 'most')
            .take(30)
            .toList();
    rows.add(ContentRow(
      title: t['most_popular']!,
      count: mostPopular.length,
      cards: [
        for (final i in mostPopular)
          PosterCard(
              item: i,
              movieLabel: t['movie']!,
              onPressed: () => open(i)),
      ],
    ));

    // Popular Now — drawn from the popular pool, shuffled once per day.
    final popular =
        dailyShuffled(catalog.popularPool().take(60).toList(), salt: 'popular')
            .take(20)
            .toList();
    rows.add(ContentRow(
      title: t['row_popular']!,
      count: popular.length,
      cards: [
        for (final i in popular)
          PosterCard(
              item: i,
              movieLabel: t['movie']!,
              onPressed: () => open(i)),
      ],
    ));

    // Top 10 Today — daily rotation drawn from the popular pool.
    final top10 =
        dailyShuffled(catalog.getTop10Pool().take(40).toList(), salt: 'top10')
            .take(10)
            .toList();
    rows.add(ContentRow(
      title: t['topten']!,
      top10Badge: true,
      cards: [
        for (int i = 0; i < top10.length; i++)
          Top10Card(item: top10[i], rank: i + 1, onPressed: () => open(top10[i])),
      ],
    ));

    // In the Spotlight (popular movies, landscape) — shuffled daily.
    final spotlight = dailyShuffled(
            catalog.popularMovies().take(30).toList(),
            salt: 'spotlight')
        .take(14)
        .toList();
    rows.add(ContentRow(
      title: t['spotlight']!,
      count: spotlight.length,
      cards: [
        for (final m in spotlight)
          BackdropCard(item: m, genreLine: _genreLine(m), onPressed: () => open(m)),
      ],
    ));

    // New Episodes (popular shows) — shuffled daily.
    final newShows =
        dailyShuffled(catalog.popularShows().take(40).toList(), salt: 'new')
            .take(20)
            .toList();
    rows.add(ContentRow(
      title: t['row_new']!,
      count: newShows.length,
      cards: [
        for (final s in newShows)
          PosterCard(item: s, movieLabel: t['movie']!, onPressed: () => open(s)),
      ],
    ));

    // Genre rows (>= 4 items): most-popular within the genre (genreRows is
    // already fame-sorted + memoized in CatalogService), shuffled daily.
    for (final entry in catalog.genreRows()) {
      rows.add(ContentRow(
        title: translateGenre(entry.key),
        count: entry.value.length,
        cards: [
          for (final i in dailyShuffled(
                  entry.value.take(24).toList(), salt: entry.key)
              .take(20))
            PosterCard(
              item: i,
              movieLabel: t['movie']!,
              onPressed: () => open(i)),
        ],
      ));
    }

    // Hero pool: most-popular titles with a backdrop, rotated daily.
    final featured =
        dailyShuffled(catalog.getFeaturedPool().take(20).toList(), salt: 'hero')
            .take(5)
            .toList();

    return ScreenShell(
      current: 'home',
      backdrop: _HeroBackdropFill(_heroBackdrop),
      // CustomScrollView so off-screen rows (the genre rows especially) build
      // lazily as they scroll into view instead of all at once.
      child: CustomScrollView(
        slivers: [
          // Wrapped so that when D-pad focus travels back UP from the rows onto
          // a hero control, the page scrolls the hero into view (cards get this
          // via their own EnsureVisibleOnFocus; the hero needs it too, otherwise
          // focus lands off-screen and the hero feels stuck).
          SliverToBoxAdapter(
            child: EnsureVisibleOnFocus(
              alignment: 0,
              child: HeroCarousel(
                items: featured,
                t: t,
                isRtl: settings.isRtl,
                autoplay: settings.prefs['autoplay'] != 'off',
                onPlay: (i) => playItem(context, ref, i),
                onMoreInfo: open,
                onToggleList: (i) =>
                    ref.read(userProvider.notifier).toggle(i.id),
                isInList: (i) => user.watchlistIds.contains(i.id),
                onBackdrop: _onHeroBackdrop,
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, i) => rows[i],
              childCount: rows.length,
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 90)),
        ],
      ),
    );
  }
}

/// A blurred, darkened full-screen copy of the current hero art, painted by
/// the shell behind the letterboxed canvas so the hero reads edge-to-edge on
/// non-16:9 panels.
///
/// Perf-critical on weak TV GPUs, twice over:
///  - On a true 16:9 panel the canvas leaves no letterbox bars, so the fill is
///    completely covered — yet the sigma-24 full-screen blur still had to be
///    composited every frame. Skip it entirely there (the common case).
///  - Listens to the backdrop URL via [ValueListenableBuilder], so a hero
///    rotation repaints ONLY this layer, never the Home tree around it.
class _HeroBackdropFill extends StatelessWidget {
  final ValueListenable<String?> backdropUrl;
  const _HeroBackdropFill(this.backdropUrl);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final is16by9 =
        size.height > 0 && (size.aspectRatio - 16 / 9).abs() < 0.01;
    if (size.isEmpty || is16by9) return const SizedBox.shrink();

    return ValueListenableBuilder<String?>(
      valueListenable: backdropUrl,
      builder: (context, url, _) {
        if (url == null || url.isEmpty) return const SizedBox.shrink();
        // Moderate sigma, isolated in its own layer: repaints only when the
        // hero art actually changes, not on every content-scroll frame.
        return RepaintBoundary(
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Stack(fit: StackFit.expand, children: [
              CatalogImage(url: url),
              const ColoredBox(color: Color(0x99070914)),
            ]),
          ),
        );
      },
    );
  }
}
