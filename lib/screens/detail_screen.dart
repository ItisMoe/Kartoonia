import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/catalog_source.dart';
import '../models/content_item.dart';
import '../navigation.dart';
import '../playback.dart';
import '../services/resume.dart';
import '../services/storage_service.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../utils/genre_translations.dart';
import '../utils/youtube_query.dart';
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
  // Null until the user picks a season chip; until then the screen defaults to
  // the season holding the smart-resume episode. Reset to null on a source
  // switch so the default recomputes against the new source's seasons.
  int? _seasonIdx;
  CatalogSource? _selectedSource;

  /// Default to whichever twin has stored progress (so Resume works), else the
  /// Arabic Toons source.
  CatalogSource _defaultSource(
      StorageService storage, ContentItem base, ContentItem? alt) {
    if (alt != null &&
        storage.progressForItem(alt.id) > 0 &&
        storage.progressForItem(base.id) <= 0) {
      return alt.source;
    }
    return base.source;
  }

  /// Play-button label. For a started show it names the resume episode
  /// ("Resume · S2·E3"); otherwise a plain Play/Resume.
  String _playLabel(ContentItem item, Episode? ep, bool hasProgress,
      Map<String, String> t) {
    if (item is Show && ep != null && hasProgress) {
      final season = item.seasonCount > 1 && ep.seasonNumber != null
          ? '${t['seasonShort']}${ep.seasonNumber}·'
          : '';
      return '${t['resume']!} · $season${t['epShort']}${ep.episodeNumber}';
    }
    return hasProgress ? t['resume']! : t['play']!;
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(catalogRevProvider);
    final catalog = ref.watch(catalogProvider);
    final t = ref.watch(stringsProvider);
    final user = ref.watch(userProvider);
    final base = catalog.getById(widget.itemId);

    if (base == null) {
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

    final storage = ref.read(storageProvider);
    final alt = catalog.alternateFor(base);
    // Resume-aware default source (computed once per mount).
    _selectedSource ??= _defaultSource(storage, base, alt);
    final item = (alt != null && _selectedSource == alt.source) ? alt : base;
    final primary = catalog.primaryFor(base);

    final inList = user.watchlistIds.contains(primary.id) ||
        (alt != null && user.watchlistIds.contains(alt.id));
    final hasProgress = storage.progressForItem(item.id) > 0;

    // Smart resume: the episode the Play/Resume button jumps to (the in-progress
    // one, else the next unwatched). Null for movies.
    final resumeEp = (item is Show && item.episodes.isNotEmpty)
        ? resumeTarget(item.episodes, (url) => storage.getProgress(url))
        : null;

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
                    label: _playLabel(item, resumeEp, hasProgress, t),
                    icon: Icons.play_arrow,
                    variant: PillVariant.primary,
                    autofocus: true,
                    onPressed: () =>
                        playItem(context, ref, item, episode: resumeEp),
                  ),
                  const SizedBox(width: 16),
                  // Trailer (movies) / theme-song (shows) via YouTube search.
                  Pill(
                    label: item is Movie ? t['trailer_btn']! : t['theme_btn']!,
                    icon: Icons.smart_display_outlined,
                    onPressed: () => AppNav.youtube(
                        context, youtubeSearchQuery(item), item.title),
                  ),
                  const SizedBox(width: 16),
                  Pill(
                    label: inList ? t['inList']! : t['myList']!,
                    icon: inList ? Icons.check : Icons.add,
                    variant: inList ? PillVariant.inList : PillVariant.normal,
                    onPressed: () {
                      ref.read(userProvider.notifier).toggle(primary.id);
                      setState(() {});
                    },
                  ),
                ]),
                const SizedBox(height: 36),
                if (alt != null) ...[
                  _sourceToggle(item.source, base.source, alt.source, t),
                  const SizedBox(height: 28),
                ],
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
    final storage = ref.read(storageProvider);
    ProgressEntry? progressOf(String url) => storage.getProgress(url);

    // Default to the season holding the smart-resume episode, and mark
    // unwatched episodes only once the show has actually been started.
    final target = show.episodes.isNotEmpty
        ? resumeTarget(show.episodes, progressOf)
        : null;
    final showStarted = hasAnyProgress(show.episodes, progressOf);
    final defaultIdx = target?.seasonNumber != null
        ? show.seasons.indexWhere((s) => s.seasonNumber == target!.seasonNumber)
        : 0;
    final idx = (_seasonIdx ?? (defaultIdx < 0 ? 0 : defaultIdx))
        .clamp(0, show.seasons.length - 1);
    final season = show.seasons[idx];

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
              final prog = progressOf(ep.episodeUrl);
              return EnsureVisibleOnFocus(
                child: _EpisodeCard(
                  episode: ep,
                  progress: prog != null && prog.duration > 0
                      ? prog.fraction
                      : null,
                  watchState: episodeWatchState(prog),
                  showUnwatchedDot: showStarted,
                  epLabel: '${t['epShort']}${ep.episodeNumber}',
                  seasonLabel: '${t['season']} ${season.seasonNumber}',
                  autofocus: target != null && ep.episodeUrl == target.episodeUrl,
                  onPressed: () => playItem(context, ref, show, episode: ep),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// Arabic Toons / Stardima picker, shown only for titles that exist in both
  /// sources. Switching swaps the seasons/episodes and Play target.
  Widget _sourceToggle(CatalogSource selected, CatalogSource atSource,
      CatalogSource stSource, Map<String, String> t) {
    Widget chip(CatalogSource src) => Padding(
          padding: const EdgeInsets.only(right: 10),
          child: SelectableChip(
            label: src == CatalogSource.stardima
                ? t['source_badge_st']!
                : t['source_badge_at']!,
            selected: src == selected,
            radius: 13,
            onPressed: () => setState(() {
              _selectedSource = src;
              _seasonIdx = null; // recompute default season for the new source
            }),
          ),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(t['source_label']!,
          style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: AppColors.inkMute)),
      const SizedBox(width: 16),
      chip(atSource),
      chip(stSource),
    ]);
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
  final EpisodeWatchState watchState;
  final bool showUnwatchedDot;
  final String epLabel;
  final String seasonLabel;
  final bool autofocus;
  final VoidCallback onPressed;

  const _EpisodeCard({
    required this.episode,
    required this.progress,
    required this.watchState,
    required this.showUnwatchedDot,
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
        final watched = watchState == EpisodeWatchState.watched;
        final bg = focused ? Colors.white : AppColors.bg2;
        final titleColor = focused ? AppColors.onFocus : AppColors.ink;
        final metaColor = focused ? const Color(0xB311142E) : AppColors.inkMute;
        final numColor = focused
            ? AppColors.onFocus
            : (watched ? AppColors.inkMute : AppColors.primary2);
        final showDot =
            showUnwatchedDot && watchState == EpisodeWatchState.unwatched;
        return AnimatedScale(
          scale: focused ? 1.04 : 1,
          duration: const Duration(milliseconds: 160),
          curve: ease,
          child: Stack(clipBehavior: Clip.none, children: [
          Container(
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
                Icon(
                    watched ? Icons.check_circle : Icons.play_arrow,
                    size: 28,
                    color: focused
                        ? AppColors.onFocus
                        : (watched ? AppColors.accent : AppColors.inkSoft)),
              ],
            ),
          ),
          // Unwatched marker: a small accent dot, shown only on shows the user
          // has already started so a fresh series isn't covered in dots.
          if (showDot)
            Positioned(
              top: -3,
              right: -3,
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.bg1, width: 3),
                ),
              ),
            ),
          ]),
        );
      },
    );
  }
}
