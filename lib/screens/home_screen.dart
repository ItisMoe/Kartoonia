import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/content_item.dart';
import '../navigation.dart';
import '../playback.dart';
import '../services/recommendations.dart';
import '../services/storage_service.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../utils/daily_shuffle.dart';
import '../utils/genre_translations.dart';
import '../utils/image_prefetch.dart';
import '../widgets/content_card.dart';
import '../widgets/content_row.dart';
import '../widgets/ensure_visible.dart';
import '../widgets/hero_carousel.dart';
import '../widgets/screen_shell.dart';

/// Shown at most once per app launch: the "pick up where you left off" prompt
/// only fires the first time Home mounts, not on every tab return.
bool _resumePromptShownThisSession = false;

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
      // Warm the famous-pool posters so the rows reveal smoothly as the user
      // scrolls (best-effort; covers most Home rows' art).
      if (mounted) prefetchPosters(context, ref.read(catalogProvider).popularPool());
      _maybeShowResumePrompt();
    });
  }

  /// On the first Home mount of the session, offer to resume the most recently
  /// watched title if there is one.
  void _maybeShowResumePrompt() {
    if (_resumePromptShownThisSession) return;
    final catalog = ref.read(catalogProvider);
    final cw = ref.read(userProvider).continueWatching;
    ContentItem? item;
    for (final e in cw) {
      final found = catalog.getById(e.itemId);
      if (found != null) {
        item = found;
        break;
      }
    }
    if (item == null) return;
    _resumePromptShownThisSession = true;
    final t = ref.read(stringsProvider);
    final resumeItem = item;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bg2,
        title: Text(t['resume_prompt']!,
            style: const TextStyle(color: AppColors.ink)),
        content: Text(resumeItem.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                color: AppColors.inkSoft,
                fontSize: 22,
                fontWeight: FontWeight.w800)),
        actions: [
          TextButton(
            autofocus: true,
            onPressed: () {
              Navigator.pop(ctx);
              playItem(context, ref, resumeItem);
            },
            child: Text(t['resume']!,
                style: const TextStyle(
                    color: AppColors.primary2, fontWeight: FontWeight.w800)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t['dismiss']!,
                style: const TextStyle(color: AppColors.inkSoft)),
          ),
        ],
      ),
    );
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
    final catalog = ref.watch(catalogProvider);
    final t = ref.watch(stringsProvider);
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

    // Genre rows (>= 4 items): most-popular within the genre, shuffled daily.
    for (final entry in catalog.genreRows()) {
      final byPop = entry.value.toList()
        ..sort((a, b) => b.fameScore.compareTo(a.fameScore));
      rows.add(ContentRow(
        title: translateGenre(entry.key),
        count: entry.value.length,
        cards: [
          for (final i
              in dailyShuffled(byPop.take(24).toList(), salt: entry.key).take(20))
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
