import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/catalog_source.dart';
import '../models/content_item.dart';
import '../navigation.dart';
import '../services/catalog_service.dart';
import '../services/fame_ranking.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../theme/layout.dart';
import '../utils/daily_shuffle.dart';
import '../utils/genre_translations.dart';
import '../widgets/content_card.dart';
import '../widgets/content_row.dart';
import '../widgets/ensure_visible.dart';
import '../widgets/screen_shell.dart';
import '../widgets/selectable_chip.dart';

/// Browse TV Shows / Movies / My List. Movies and TV each render either a
/// Home-style sectioned view (default "All": no letter, no genre filter) or a
/// flat fame-sorted grid (a letter and/or a genre filter is active, sorted
/// known-first). My List is always a plain grid in its own order.
class BrowseScreen extends ConsumerWidget {
  final String kind; // 'tv' | 'movies' | 'mylist'
  const BrowseScreen({super.key, required this.kind});

  String _navKey() => kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(catalogRevProvider);
    final catalog = ref.watch(catalogProvider);
    final t = ref.watch(stringsProvider);
    final browse = ref.watch(browseProvider);
    final user = ref.watch(userProvider);

    final isMyList = kind == 'mylist';
    final title = kind == 'movies'
        ? t['browse_movies']!
        : isMyList
            ? t['browse_mylist']!
            : t['browse_tv']!;

    List<ContentItem> typeItems;
    if (kind == 'movies') {
      typeItems = catalog.movies;
    } else if (isMyList) {
      typeItems = user.watchlistIds
          .map(catalog.getById)
          .whereType<ContentItem>()
          .toList();
    } else {
      typeItems = catalog.shows;
    }

    final script = browse.alphaScript;
    final letter = browse.letter;
    final category = browse.category;

    // Sectioned (Mode A) only for the default, unfiltered Movies/TV view.
    final sectioned = !isMyList && letter == null && category == null;

    // Genre-filtered base — feeds both the grid and the alpha bar present-set.
    final base = (category == null)
        ? typeItems
        : typeItems.where((i) => i.genres.contains(category)).toList();

    List<ContentItem> shown;
    if (isMyList) {
      shown = typeItems;
    } else if (sectioned) {
      shown = base; // unused for rendering; header count uses typeItems
    } else {
      final filtered = letter == null
          ? base
          : base
              .where((s) => firstLetterFor(s.title, script) == letter)
              .toList();
      shown = sortedForBrowse(filtered);
    }

    void open(ContentItem i) => AppNav.detail(context, i);

    // Source badge for titles present in BOTH catalogs (else null = no badge).
    String? badge(ContentItem i) => catalog.isDuplicated(i)
        ? (i.source == CatalogSource.stardima
            ? t['source_badge_st']
            : t['source_badge_at'])
        : null;

    Widget grid(List<ContentItem> list) {
      if (list.isEmpty) {
        return SliverToBoxAdapter(
          child: SizedBox(
            height: 520,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(30)),
                    child: const Icon(Icons.favorite_border,
                        size: 58, color: AppColors.inkMute),
                  ),
                  const SizedBox(height: 22),
                  Text(isMyList ? t['mylist_empty']! : t['noResults']!,
                      style: const TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w700,
                          color: AppColors.inkMute)),
                ],
              ),
            ),
          ),
        );
      }
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(Spacing.pad, 0, Spacing.pad, 80),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: Dims.browseCols,
            mainAxisSpacing: 28,
            crossAxisSpacing: 22,
            childAspectRatio: Dims.cardW / Dims.cardH,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => EnsureVisibleOnFocus(
              child: PosterCard(
                item: list[i],
                expand: true,
                autofocus: i == 0,
                movieLabel: t['movie']!,
                sourceLabel: badge(list[i]),
                onPressed: () => open(list[i]),
              ),
            ),
            childCount: list.length,
          ),
        ),
      );
    }

    // Mode A: Home-style rows for a single type, no hero, daily-rotated.
    List<Widget> sectionRows() {
      final pool = famousPool(typeItems);
      final rows = <Widget>[];

      final mostPopular =
          dailyShuffled(pool.take(80).toList(), salt: 'b_most_$kind')
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
                sourceLabel: badge(i),
                onPressed: () => open(i)),
        ],
      ));

      final popular =
          dailyShuffled(pool.take(60).toList(), salt: 'b_pop_$kind')
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
                sourceLabel: badge(i),
                onPressed: () => open(i)),
        ],
      ));

      final top10 =
          dailyShuffled(pool.take(40).toList(), salt: 'b_top_$kind')
              .take(10)
              .toList();
      rows.add(ContentRow(
        title: t['topten']!,
        top10Badge: true,
        cards: [
          for (int i = 0; i < top10.length; i++)
            Top10Card(
                item: top10[i], rank: i + 1, onPressed: () => open(top10[i])),
        ],
      ));

      for (final entry in genreRowsFor(typeItems)) {
        final byFame = entry.value.toList()
          ..sort((a, b) => b.fameScore.compareTo(a.fameScore));
        rows.add(ContentRow(
          title: translateGenre(entry.key),
          count: entry.value.length,
          cards: [
            for (final i in dailyShuffled(byFame.take(24).toList(),
                    salt: 'b_${entry.key}_$kind')
                .take(20))
              PosterCard(
                  item: i, movieLabel: t['movie']!, onPressed: () => open(i)),
          ],
        ));
      }
      return rows;
    }

    final present = isMyList
        ? <String>{}
        : base.map((s) => firstLetterFor(s.title, script)).toSet();
    final letters = (script == 'ar' ? alphaAr : alphaEn).split('');

    final headerCount =
        (isMyList || sectioned) ? typeItems.length : shown.length;

    return ScreenShell(
      current: _navKey(),
      background: AppColors.bg1,
      child: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: 150)),
          SliverToBoxAdapter(
            child: Padding(
              padding:
                  const EdgeInsets.fromLTRB(Spacing.pad, 0, Spacing.pad, 30),
              child: Row(
                textBaseline: TextBaseline.alphabetic,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontFamily: Fonts.display,
                          fontFamilyFallback: Fonts.fallback,
                          fontWeight: FontWeight.w600,
                          fontSize: 56,
                          letterSpacing: -0.5,
                          color: AppColors.ink)),
                  const SizedBox(width: 16),
                  Text('$headerCount',
                      style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppColors.inkMute)),
                ],
              ),
            ),
          ),
          if (!isMyList)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 70,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: Spacing.pad),
                  children: [
                    // Filter button — shows the active genre when one is set.
                    _railChip(SelectableChip(
                      label: category == null
                          ? t['browse_filter']!
                          : translateGenre(category),
                      selected: category != null,
                      radius: 13,
                      onPressed: () =>
                          _openFilter(context, ref, typeItems, category, t),
                    )),
                    const SizedBox(width: 16),
                    // script toggle
                    _railChip(SelectableChip(
                      label: t['kbLatin']!,
                      selected: script == 'en',
                      radius: 13,
                      minWidth: 56,
                      onPressed: () =>
                          ref.read(browseProvider.notifier).setScript('en'),
                    )),
                    _railChip(SelectableChip(
                      label: t['kbArabic']!,
                      selected: script == 'ar',
                      radius: 13,
                      minWidth: 56,
                      onPressed: () =>
                          ref.read(browseProvider.notifier).setScript('ar'),
                    )),
                    const SizedBox(width: 16),
                    _railChip(SelectableChip(
                      label: t['alpha_all']!,
                      selected: letter == null,
                      radius: 13,
                      onPressed: () =>
                          ref.read(browseProvider.notifier).setLetter(null),
                    )),
                    for (final L in letters)
                      _railChip(SelectableChip(
                        label: L,
                        selected: letter == L,
                        disabled: !present.contains(L),
                        radius: 13,
                        minWidth: 54,
                        onPressed: () =>
                            ref.read(browseProvider.notifier).setLetter(L),
                      )),
                  ],
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          if (sectioned)
            SliverList(delegate: SliverChildListDelegate(sectionRows()))
          else
            grid(shown),
        ],
      ),
    );
  }

  Widget _railChip(Widget child) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: EnsureVisibleOnFocus(child: Center(child: child)),
      );

  /// D-pad genre picker. Selecting a genre sets the category filter (collapsing
  /// the sectioned view into a fame-sorted grid); "All Genres" clears it.
  Future<void> _openFilter(
    BuildContext context,
    WidgetRef ref,
    List<ContentItem> items,
    String? current,
    Map<String, String> t,
  ) {
    final genres = genresIn(items);
    return showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.bg2,
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 120, vertical: 80),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t['browse_filter']!,
                  style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink)),
              const SizedBox(height: 20),
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SelectableChip(
                        label: t['filter_all_genres']!,
                        selected: current == null,
                        autofocus: true,
                        onPressed: () {
                          ref.read(browseProvider.notifier).setCategory(null);
                          Navigator.of(ctx).pop();
                        },
                      ),
                      for (final g in genres)
                        SelectableChip(
                          label: translateGenre(g),
                          selected: current == g,
                          onPressed: () {
                            ref.read(browseProvider.notifier).setCategory(g);
                            Navigator.of(ctx).pop();
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
