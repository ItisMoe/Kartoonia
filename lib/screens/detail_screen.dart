import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/content_item.dart';
import '../navigation.dart';
import '../playback.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../utils/genre_translations.dart';
import '../widgets/catalog_image.dart';
import '../widgets/ensure_visible.dart';
import '../widgets/focusable.dart';
import '../widgets/pill.dart';
import '../widgets/screen_shell.dart';
import '../widgets/selectable_chip.dart';

class DetailScreen extends ConsumerStatefulWidget {
  final String itemId;
  const DetailScreen({super.key, required this.itemId});
  @override
  ConsumerState<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends ConsumerState<DetailScreen> {
  int _seasonIdx = 0;

  @override
  Widget build(BuildContext context) {
    ref.watch(catalogRevProvider);
    final catalog = ref.watch(catalogProvider);
    final t = ref.watch(stringsProvider);
    final user = ref.watch(userProvider);
    final item = catalog.getById(widget.itemId);

    if (item == null) {
      return ScreenShell(
        current: '',
        child: Center(
          child: Pill(
            label: t['back']!,
            icon: Icons.arrow_back,
            autofocus: true,
            onPressed: () => Navigator.maybePop(context),
          ),
        ),
      );
    }

    final inList = user.watchlistIds.contains(item.id);
    final storage = ref.read(storageProvider);
    final hasProgress = storage.progressForItem(item.id) > 0;

    // meta chiplets
    final chips = <Widget>[];
    if (item.year != null) chips.add(_chiplet('${item.year}'));
    if (item is Show) {
      chips.add(_chiplet('${item.seasonCount} ${t['seasons']}'));
      chips.add(_chiplet('${item.totalEpisodes} ${t['episodes']}'));
    } else {
      chips.add(_typeChiplet(t['movie']!));
    }

    final genreLine = item.genres.map(translateGenre).join(' · ');

    return ScreenShell(
      current: '',
      child: Stack(children: [
        // backdrop
        Positioned.fill(
            child: CatalogImage(
                url: item.backdropUrl, fallbackUrl: item.thumbnailUrl)),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [AppColors.bg1, Color(0x8C0F1430), Color(0x330F1430)],
                stops: [0.08, 0.6, 1],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: AlignmentDirectional.centerStart,
                end: AlignmentDirectional.centerEnd,
                colors: [
                  const Color(0xF20A0D1F),
                  const Color(0x8C0A0D1F),
                  AppColors.bg1.withValues(alpha: 0.15),
                ],
              ),
            ),
          ),
        ),
        // content
        Positioned.fill(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(Spacing.pad, 150, Spacing.pad, 60),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (genreLine.isNotEmpty)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                            color: AppColors.primary, shape: BoxShape.circle)),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(genreLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                              fontSize: 17,
                              color: AppColors.primary2)),
                    ),
                  ]),
                const SizedBox(height: 16),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 880),
                  child: Text(item.title,
                      style: const TextStyle(
                          fontFamily: Fonts.display,
                          fontFamilyFallback: Fonts.fallback,
                          fontWeight: FontWeight.w600,
                          fontSize: 86,
                          height: 0.96,
                          letterSpacing: -1,
                          color: AppColors.ink)),
                ),
                const SizedBox(height: 20),
                Wrap(spacing: 16, runSpacing: 10, children: chips),
                const SizedBox(height: 20),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Text(item.descriptionAr,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 25, height: 1.5, color: AppColors.inkSoft)),
                ),
                const SizedBox(height: 26),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Pill(
                    label: hasProgress ? t['resume']! : t['play']!,
                    icon: Icons.play_arrow,
                    variant: PillVariant.primary,
                    autofocus: true,
                    onPressed: () => playItem(context, ref, item),
                  ),
                  const SizedBox(width: 16),
                  // Trailer (movies) / theme-song (shows) via YouTube search.
                  Pill(
                    label: item is Movie ? t['trailer_btn']! : t['theme_btn']!,
                    icon: Icons.smart_display_outlined,
                    onPressed: () {
                      final year = item.year != null ? ' ${item.year}' : '';
                      final query = item is Movie
                          ? '${item.title}$year كرتون مدبلج عربي كامل'
                          : '${item.title} مدبلج عربي مقدمة';
                      AppNav.youtube(context, query, item.title);
                    },
                  ),
                  const SizedBox(width: 16),
                  Pill(
                    label: inList ? t['inList']! : t['myList']!,
                    icon: inList ? Icons.check : Icons.add,
                    variant: inList ? PillVariant.inList : PillVariant.normal,
                    onPressed: () {
                      ref.read(userProvider.notifier).toggle(item.id);
                      setState(() {});
                    },
                  ),
                ]),
                const SizedBox(height: 36),
                if (item is Show) _episodes(item, t),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  Widget _episodes(Show show, Map<String, String> t) {
    if (show.seasons.isEmpty) return const SizedBox.shrink();
    final idx = _seasonIdx.clamp(0, show.seasons.length - 1);
    final season = show.seasons[idx];
    final storage = ref.read(storageProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(t['episodes']!,
              style: const TextStyle(
                  fontFamily: Fonts.display,
                  fontFamilyFallback: Fonts.fallback,
                  fontWeight: FontWeight.w500,
                  fontSize: 30,
                  color: AppColors.ink)),
          const SizedBox(width: 20),
          Text('${t['season']} ${season.seasonNumber}',
              style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: AppColors.inkMute)),
        ]),
        // season selector
        if (show.seasons.length > 1) ...[
          const SizedBox(height: 16),
          SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: show.seasons.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) => EnsureVisibleOnFocus(
                child: Center(
                  child: SelectableChip(
                    label: '${t['season']} ${show.seasons[i].seasonNumber}',
                    selected: i == idx,
                    radius: 13,
                    onPressed: () => setState(() => _seasonIdx = i),
                  ),
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        SizedBox(
          height: 132,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: season.episodes.length,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (context, i) {
              final ep = season.episodes[i];
              final prog = storage.getProgress(ep.episodeUrl);
              return EnsureVisibleOnFocus(
                child: _EpisodeCard(
                  episode: ep,
                  progress: prog != null && prog.duration > 0
                      ? prog.fraction
                      : null,
                  epLabel: '${t['epShort']}${ep.episodeNumber}',
                  seasonLabel: '${t['season']} ${season.seasonNumber}',
                  autofocus: i == 0,
                  onPressed: () => playItem(context, ref, show, episode: ep),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _chiplet(String s) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8)),
        child: Text(s,
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppColors.inkSoft)),
      );

  Widget _typeChiplet(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.movie_outlined, size: 17, color: AppColors.inkSoft),
          const SizedBox(width: 7),
          Text(label,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.inkSoft)),
        ]),
      );
}

/// Image-free episode entry: a prominent episode number, the title, the season
/// line and an optional continue-watching progress bar. Fully D-pad focusable.
class _EpisodeCard extends StatelessWidget {
  final Episode episode;
  final double? progress;
  final String epLabel;
  final String seasonLabel;
  final bool autofocus;
  final VoidCallback onPressed;

  const _EpisodeCard({
    required this.episode,
    required this.progress,
    required this.epLabel,
    required this.seasonLabel,
    required this.autofocus,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Focusable(
      autofocus: autofocus,
      onPressed: onPressed,
      builder: (context, focused) {
        final bg = focused ? Colors.white : AppColors.bg2;
        final titleColor = focused ? AppColors.onFocus : AppColors.ink;
        final metaColor = focused ? const Color(0xB311142E) : AppColors.inkMute;
        final numColor = focused ? AppColors.onFocus : AppColors.primary2;
        return AnimatedScale(
          scale: focused ? 1.04 : 1,
          duration: const Duration(milliseconds: 160),
          curve: ease,
          child: Container(
            width: 360,
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(Radii.ep),
              border: Border.all(
                  color: focused
                      ? Colors.transparent
                      : Colors.white.withValues(alpha: 0.06),
                  width: 2),
              boxShadow: focused
                  ? [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.6),
                          blurRadius: 30,
                          offset: const Offset(0, 12))
                    ]
                  : null,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // big episode number
                SizedBox(
                  width: 64,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${episode.episodeNumber}',
                          style: TextStyle(
                              fontFamily: Fonts.display,
                              fontFamilyFallback: Fonts.fallback,
                              fontWeight: FontWeight.w700,
                              fontSize: 44,
                              height: 1,
                              color: numColor)),
                      Text(epLabel,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                              color: metaColor)),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(episode.episodeTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              height: 1.15,
                              color: titleColor)),
                      const SizedBox(height: 8),
                      Text(seasonLabel,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: metaColor)),
                      if (progress != null && progress! > 0) ...[
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: LinearProgressIndicator(
                            value: progress!.clamp(0, 1),
                            minHeight: 5,
                            backgroundColor: focused
                                ? const Color(0x2211142E)
                                : const Color(0x33FFFFFF),
                            valueColor: const AlwaysStoppedAnimation(
                                AppColors.primary),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(Icons.play_arrow,
                    size: 28,
                    color: focused ? AppColors.onFocus : AppColors.inkSoft),
              ],
            ),
          ),
        );
      },
    );
  }
}
