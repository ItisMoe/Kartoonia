import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/catalog_source.dart';
import '../../models/content_item.dart';
import '../../navigation.dart';
import '../../playback.dart';
import '../../services/storage_service.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../../utils/genre_translations.dart';
import '../../widgets/catalog_image.dart';

/// Portrait title page: a backdrop header, metadata, the primary actions and a
/// vertical episode list (for shows) with a season selector.
class PhoneDetailScreen extends ConsumerStatefulWidget {
  final String itemId;
  const PhoneDetailScreen({super.key, required this.itemId});
  @override
  ConsumerState<PhoneDetailScreen> createState() => _PhoneDetailScreenState();
}

class _PhoneDetailScreenState extends ConsumerState<PhoneDetailScreen> {
  int _seasonIdx = 0;
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

  @override
  Widget build(BuildContext context) {
    ref.watch(catalogRevProvider);
    final catalog = ref.watch(catalogProvider);
    final t = ref.watch(stringsProvider);
    final user = ref.watch(userProvider);
    final base = catalog.getById(widget.itemId);

    if (base == null) {
      return Scaffold(
        backgroundColor: AppColors.bg1,
        appBar: AppBar(backgroundColor: Colors.transparent),
        body: Center(
          child: Text(t['noResults']!,
              style: const TextStyle(color: AppColors.inkMute, fontSize: 16)),
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
    final genreLine = item.genres.map(translateGenre).join(' · ');
    final size = MediaQuery.of(context).size;

    final chips = <String>[];
    if (item.year != null) chips.add('${item.year}');
    if (item is Show) {
      chips.add('${item.seasonCount} ${t['seasons']}');
      chips.add('${item.totalEpisodes} ${t['episodes']}');
    } else {
      chips.add(t['movie']!);
    }

    return Scaffold(
      backgroundColor: AppColors.bg1,
      body: Stack(children: [
        CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: SizedBox(
                height: (size.height * 0.5).clamp(300.0, 520.0),
                child: Stack(fit: StackFit.expand, children: [
                  CatalogImage(
                      url: item.backdropUrl, fallbackUrl: item.thumbnailUrl),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [AppColors.bg1, Color(0x000F1430), Color(0x4D0F1430)],
                        stops: [0.01, 0.55, 1],
                      ),
                    ),
                  ),
                ]),
              ),
            ),
            SliverToBoxAdapter(
              child: Transform.translate(
                offset: const Offset(0, -40),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title,
                          style: const TextStyle(
                              fontFamily: Fonts.display,
                              fontFamilyFallback: Fonts.fallback,
                              fontWeight: FontWeight.w600,
                              fontSize: 32,
                              height: 1.05,
                              color: AppColors.ink)),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          for (final c in chips) _Chiplet(c),
                        ],
                      ),
                      if (genreLine.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Text(genreLine,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary2)),
                      ],
                      const SizedBox(height: 16),
                      // Primary Play
                      _PrimaryButton(
                        label: hasProgress ? t['resume']! : t['play']!,
                        icon: Icons.play_arrow,
                        onTap: () => playItem(context, ref, item),
                      ),
                      const SizedBox(height: 12),
                      Row(children: [
                        Expanded(
                          child: _SecondaryButton(
                            label: item is Movie
                                ? t['trailer_btn']!
                                : t['theme_btn']!,
                            icon: Icons.smart_display_outlined,
                            onTap: () {
                              final query = item is Movie
                                  ? '${item.title} trailer'
                                  : '${item.title} arabic theme song';
                              AppNav.youtube(context, query, item.title);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _SecondaryButton(
                            label: inList ? t['inList']! : t['myList']!,
                            icon: inList ? Icons.check : Icons.add,
                            highlight: inList,
                            onTap: () {
                              ref.read(userProvider.notifier).toggle(primary.id);
                              setState(() {});
                            },
                          ),
                        ),
                      ]),
                      if (item.descriptionAr.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        Text(item.descriptionAr,
                            style: const TextStyle(
                                fontSize: 15,
                                height: 1.5,
                                color: AppColors.inkSoft)),
                      ],
                      const SizedBox(height: 22),
                      if (alt != null) ...[
                        _sourceToggle(item.source, base.source, alt.source, t),
                        const SizedBox(height: 18),
                      ],
                      if (item is Show) _episodes(item, t),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        // Back button
        Positioned(
          top: 0,
          left: 0,
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.maybePop(context),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.4),
                  ),
                  child: const Icon(Icons.arrow_back,
                      size: 22, color: AppColors.ink),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  /// Arabic Toons / Stardima picker, shown only for titles in both sources.
  Widget _sourceToggle(CatalogSource selected, CatalogSource atSource,
      CatalogSource stSource, Map<String, String> t) {
    Widget chip(CatalogSource src) {
      final on = src == selected;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _selectedSource = src),
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient: on
                ? const LinearGradient(colors: AppColors.primaryGradient)
                : null,
            color: on ? null : AppColors.bg2,
          ),
          child: Text(
              src == CatalogSource.stardima
                  ? t['source_badge_st']!
                  : t['source_badge_at']!,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: on ? AppColors.onPrimary : AppColors.inkSoft)),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Text(t['source_label']!,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.inkMute)),
        const SizedBox(width: 12),
        chip(atSource),
        chip(stSource),
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
        Text(t['episodes']!,
            style: const TextStyle(
                fontFamily: Fonts.display,
                fontFamilyFallback: Fonts.fallback,
                fontWeight: FontWeight.w600,
                fontSize: 22,
                color: AppColors.ink)),
        if (show.seasons.length > 1) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 38,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: show.seasons.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (context, i) {
                final selected = i == idx;
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => setState(() => _seasonIdx = i),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      gradient: selected
                          ? const LinearGradient(
                              colors: AppColors.primaryGradient)
                          : null,
                      color: selected ? null : AppColors.bg2,
                    ),
                    child: Text('${t['season']} ${show.seasons[i].seasonNumber}',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: selected
                                ? AppColors.onPrimary
                                : AppColors.inkSoft)),
                  ),
                );
              },
            ),
          ),
        ],
        const SizedBox(height: 14),
        for (final ep in season.episodes)
          _EpisodeRow(
            episode: ep,
            seasonLabel: '${t['season']} ${season.seasonNumber}',
            epLabel: '${t['epShort']}${ep.episodeNumber}',
            progress: () {
              final p = storage.getProgress(ep.episodeUrl);
              return p != null && p.duration > 0 ? p.fraction : null;
            }(),
            onTap: () => playItem(context, ref, show, episode: ep),
          ),
      ],
    );
  }
}

class _Chiplet extends StatelessWidget {
  final String label;
  const _Chiplet(this.label);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(7)),
        child: Text(label,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.inkSoft)),
      );
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _PrimaryButton(
      {required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: const LinearGradient(colors: AppColors.primaryGradient),
          boxShadow: [
            BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 10)),
          ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 24, color: AppColors.onPrimary),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.onPrimary)),
        ]),
      ),
    );
  }
}

class _SecondaryButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool highlight;
  final VoidCallback onTap;
  const _SecondaryButton(
      {required this.label,
      required this.icon,
      this.highlight = false,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final fg = highlight ? const Color(0xFFBDFFF4) : AppColors.ink;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: highlight
              ? AppColors.accent.withValues(alpha: 0.18)
              : Colors.white.withValues(alpha: 0.12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 20, color: fg),
          const SizedBox(width: 8),
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800, color: fg)),
          ),
        ]),
      ),
    );
  }
}

class _EpisodeRow extends StatelessWidget {
  final Episode episode;
  final String seasonLabel;
  final String epLabel;
  final double? progress;
  final VoidCallback onTap;
  const _EpisodeRow({
    required this.episode,
    required this.seasonLabel,
    required this.epLabel,
    required this.progress,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColors.bg2,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
        ),
        child: Row(children: [
          SizedBox(
            width: 42,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${episode.episodeNumber}',
                  style: const TextStyle(
                      fontFamily: Fonts.display,
                      fontFamilyFallback: Fonts.fallback,
                      fontWeight: FontWeight.w700,
                      fontSize: 30,
                      height: 1,
                      color: AppColors.primary2)),
              Text(epLabel,
                  style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1,
                      color: AppColors.inkMute)),
            ]),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(episode.episodeTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        height: 1.2,
                        color: AppColors.ink)),
                if (progress != null && progress! > 0) ...[
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: progress!.clamp(0, 1),
                      minHeight: 4,
                      backgroundColor: const Color(0x33FFFFFF),
                      valueColor:
                          const AlwaysStoppedAnimation(AppColors.primary),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          const Icon(Icons.play_circle_fill, size: 30, color: AppColors.inkSoft),
        ]),
      ),
    );
  }
}
