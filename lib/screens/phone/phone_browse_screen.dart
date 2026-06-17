import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/content_item.dart';
import '../../services/fame_ranking.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../../utils/genre_translations.dart';
import '../../widgets/phone/phone_poster_card.dart';
import '../../widgets/selectable_chip.dart';
import 'phone_nav.dart';

/// Portrait Browse: a TV/Movies type toggle, a horizontal genre filter rail and
/// a fame-sorted 3-column poster grid.
class PhoneBrowseScreen extends ConsumerStatefulWidget {
  const PhoneBrowseScreen({super.key});
  @override
  ConsumerState<PhoneBrowseScreen> createState() => _PhoneBrowseScreenState();
}

class _PhoneBrowseScreenState extends ConsumerState<PhoneBrowseScreen> {
  String _kind = 'tv'; // 'tv' | 'movies'
  String? _genre;

  @override
  Widget build(BuildContext context) {
    ref.watch(catalogRevProvider);
    final catalog = ref.watch(catalogProvider);
    final t = ref.watch(stringsProvider);

    final List<ContentItem> typeItems =
        _kind == 'movies' ? catalog.movies : catalog.shows;
    final genres = genresIn(typeItems);
    // Drop a stale genre filter when switching to a type that lacks it.
    if (_genre != null && !genres.contains(_genre)) _genre = null;

    final base = _genre == null
        ? typeItems
        : typeItems.where((i) => i.genres.contains(_genre)).toList();
    final shown = sortedForBrowse(base);

    return SafeArea(
      bottom: false,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(t['nav_browse']!,
                      style: const TextStyle(
                          fontFamily: Fonts.display,
                          fontFamilyFallback: Fonts.fallback,
                          fontWeight: FontWeight.w600,
                          fontSize: 30,
                          color: AppColors.ink)),
                  const SizedBox(width: 12),
                  Text('${shown.length}',
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.inkMute)),
                ],
              ),
            ),
          ),
          // Type toggle
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(children: [
                _Toggle(
                    label: t['browse_tv']!,
                    selected: _kind == 'tv',
                    onTap: () => setState(() => _kind = 'tv')),
                const SizedBox(width: 10),
                _Toggle(
                    label: t['browse_movies']!,
                    selected: _kind == 'movies',
                    onTap: () => setState(() => _kind = 'movies')),
              ]),
            ),
          ),
          // Genre filter rail
          if (genres.isNotEmpty)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: SelectableChip(
                        label: t['filter_all_genres']!,
                        selected: _genre == null,
                        fontSize: 14,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        onPressed: () => setState(() => _genre = null),
                      ),
                    ),
                    for (final g in genres)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: SelectableChip(
                          label: translateGenre(g),
                          selected: _genre == g,
                          fontSize: 14,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                          onPressed: () => setState(() => _genre = g),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 14,
                crossAxisSpacing: 12,
                childAspectRatio: 2 / 3,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => PhonePosterCard(
                  item: shown[i],
                  expand: true,
                  movieLabel: t['movie']!,
                  onPressed: () => openPhoneDetail(context, shown[i]),
                ),
                childCount: shown.length,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Toggle(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: selected
              ? const LinearGradient(colors: AppColors.primaryGradient)
              : null,
          color: selected ? null : AppColors.bg2,
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: selected ? AppColors.onPrimary : AppColors.inkSoft)),
      ),
    );
  }
}
