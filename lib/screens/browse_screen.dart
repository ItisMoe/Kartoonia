import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/content_item.dart';
import '../navigation.dart';
import '../services/catalog_service.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../theme/layout.dart';
import '../widgets/content_card.dart';
import '../widgets/ensure_visible.dart';
import '../widgets/screen_shell.dart';
import '../widgets/selectable_chip.dart';

/// Browse TV Shows / Movies / My List with an A–Z alpha bar (design `.browse`).
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

    final title = kind == 'movies'
        ? t['browse_movies']!
        : kind == 'mylist'
            ? t['browse_mylist']!
            : t['browse_tv']!;

    List<ContentItem> items;
    if (kind == 'movies') {
      items = catalog.movies;
    } else if (kind == 'mylist') {
      items = user.watchlistIds
          .map(catalog.getById)
          .whereType<ContentItem>()
          .toList();
    } else {
      items = catalog.shows;
    }

    final isMyList = kind == 'mylist';

    // A–Z first-letter browsing for every catalog source — Arabic Toons and
    // Stardima behave identically (no per-source category chips).
    final script = browse.alphaScript;
    final letter = browse.letter;

    List<ContentItem> shown;
    if (isMyList) {
      shown = items;
    } else {
      shown = letter == null
          ? items
          : items
              .where((s) => firstLetterFor(s.title, script) == letter)
              .toList();
    }

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
                onPressed: () => AppNav.detail(context, list[i]),
              ),
            ),
            childCount: list.length,
          ),
        ),
      );
    }

    final present = isMyList
        ? <String>{}
        : items.map((s) => firstLetterFor(s.title, script)).toSet();
    final letters = (script == 'ar' ? alphaAr : alphaEn).split('');

    return ScreenShell(
      current: _navKey(),
      background: AppColors.bg1,
      child: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: 150)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Spacing.pad, 0, Spacing.pad, 30),
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
                  Text('${shown.length}',
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
                  padding: const EdgeInsets.symmetric(horizontal: Spacing.pad),
                  children: [
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
          grid(shown),
        ],
      ),
    );
  }

  Widget _railChip(Widget child) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: EnsureVisibleOnFocus(child: Center(child: child)),
      );
}
