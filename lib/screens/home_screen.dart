import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/content_item.dart';
import '../navigation.dart';
import '../playback.dart';
import '../services/recommendations.dart';
import '../services/storage_service.dart';
import '../state/app_state.dart';
import '../utils/daily_shuffle.dart';
import '../utils/genre_translations.dart';
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
  @override
  void initState() {
    super.initState();
    // refresh continue-watching when returning to home
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(userProvider.notifier).refresh();
      _setupRecommendations();
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

  @override
  Widget build(BuildContext context) {
    ref.watch(catalogRevProvider); // rebuild after imports
    final catalog = ref.watch(catalogProvider);
    final t = ref.watch(stringsProvider);
    final settings = ref.watch(settingsProvider);
    final user = ref.watch(userProvider);

    void open(ContentItem i) => AppNav.detail(context, i);

    final rows = <Widget>[];

    // Keep Watching
    final continueItems = <(ContentItem, ProgressEntry)>[];
    for (final e in user.continueWatching) {
      final item = catalog.getById(e.itemId);
      if (item != null) continueItems.add((item, e));
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
            ),
        ],
      ));
    }

    // Most Popular — curated by popularity (vote_average), highest first, stable.
    final mostPopular = catalog.mostPopular(count: 30);
    rows.add(ContentRow(
      title: t['most_popular']!,
      count: mostPopular.length,
      cards: [
        for (final i in mostPopular)
          PosterCard(item: i, movieLabel: t['movie']!, onPressed: () => open(i)),
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
          PosterCard(item: i, movieLabel: t['movie']!, onPressed: () => open(i)),
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

    // Genre rows (>= 4 items): most-popular within the genre, shuffled daily.
    for (final entry in catalog.genreRows()) {
      final byPop = entry.value.toList()
        ..sort((a, b) => b.popularity.compareTo(a.popularity));
      rows.add(ContentRow(
        title: translateGenre(entry.key),
        count: entry.value.length,
        cards: [
          for (final i
              in dailyShuffled(byPop.take(24).toList(), salt: entry.key).take(20))
            PosterCard(item: i, movieLabel: t['movie']!, onPressed: () => open(i)),
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
      child: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 90),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Wrapped so that when D-pad focus travels back UP from the rows
            // onto a hero control, the page scrolls the hero into view (cards
            // get this via their own EnsureVisibleOnFocus; the hero needs it
            // too, otherwise focus lands off-screen and the hero feels stuck).
            EnsureVisibleOnFocus(
              alignment: 0,
              child: HeroCarousel(
                items: featured,
                t: t,
                isRtl: settings.isRtl,
                autoplay: settings.prefs['autoplay'] != 'off',
                onPlay: (i) => i is Movie
                    ? playItem(context, ref, i)
                    : playItem(context, ref, i),
                onMoreInfo: open,
                onToggleList: (i) =>
                    ref.read(userProvider.notifier).toggle(i.id),
                isInList: (i) => user.watchlistIds.contains(i.id),
              ),
            ),
            const SizedBox(height: 24),
            ...rows,
          ],
        ),
      ),
    );
  }
}
