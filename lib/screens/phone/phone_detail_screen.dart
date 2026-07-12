import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/catalog_source.dart';
import '../../models/content_item.dart';
import '../../navigation.dart';
import '../../playback.dart';
import '../../services/default_source.dart';
import '../../services/fame_ranking.dart';
import '../../services/wcoflix/wcoflix_match.dart';
import '../../state/app_state.dart';
import '../../state/wcoflix_providers.dart';
import '../../theme/theme.dart';
import '../../utils/genre_translations.dart';
import '../../widgets/catalog_image.dart';
import '../../widgets/phone/phone_poster_card.dart';
import 'phone_nav.dart';

/// Portrait title page: a backdrop header, metadata, the primary actions and a
/// vertical episode list (for shows) with a season selector.
class PhoneDetailScreen extends ConsumerStatefulWidget {
  final String itemId;

  /// Passed for WCOFlix cards (not in the in-memory catalog); Arabic/Stardima
  /// still resolve by [itemId].
  final ContentItem? item;
  const PhoneDetailScreen({super.key, required this.itemId, this.item});
  @override
  ConsumerState<PhoneDetailScreen> createState() => _PhoneDetailScreenState();
}

class _PhoneDetailScreenState extends ConsumerState<PhoneDetailScreen> {
  int _seasonIdx = 0;
  CatalogSource? _selectedSource;
  bool? _original; // audio: true = Original (WCOFlix), false = Arabic dub

  // Memoized Arabic-catalog match for a WCOFlix title (shows only — see
  // [ArabicMatchMemo]).
  final _arMatch = ArabicMatchMemo();

  // Cache "More Like This" per item (see the TV detail screen for why).
  String? _simForId;
  List<ContentItem>? _simCache;
  List<ContentItem> _similar(ContentItem item) {
    if (item.source == CatalogSource.wcoflix) return const [];
    if (_simForId != item.id) {
      _simCache = similarTo(item, ref.read(catalogProvider).all);
      _simForId = item.id;
    }
    return _simCache!;
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(catalogRevProvider);
    final catalog = ref.watch(catalogProvider);
    final t = ref.watch(stringsProvider);
    final user = ref.watch(userProvider);
    var base = catalog.getById(widget.itemId) ?? widget.item;
    if (base != null &&
        base.source == CatalogSource.wcoflix &&
        base is Show &&
        base.episodes.isEmpty &&
        (base.pageUrl ?? '').isNotEmpty) {
      base = ref.watch(wcoSeriesProvider(base.pageUrl!)).asData?.value ?? base;
    }

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

    // Audio language pairing: Arabic-dubbed side + a WCOFlix "original". The
    // switch is episode-based, so it only applies when the WCOFlix side is a
    // Show; a WCOFlix Movie is rendered directly (no switch).
    final baseIsWco = base.source == CatalogSource.wcoflix;
    final baseIsWcoShow = baseIsWco && base is Show;
    ContentItem? arabicSide;
    ContentItem? originalSide;
    if (baseIsWcoShow) {
      originalSide = base; // narrowed to Show
      arabicSide = _arMatch.match(base.title, catalog.shows);
    } else if (!baseIsWco) {
      arabicSide = base;
      // Same media kind only — an Arabic movie pairs with a WCOFlix movie,
      // never the franchise's series (see the TV detail screen).
      originalSide = ref
          .watch(wcoflixOriginalProvider(wcoOriginalQueryFor(base)))
          .asData
          ?.value;
    }
    final hasAudioSwitch = arabicSide != null && originalSide != null;
    _original ??= baseIsWco;
    final showOriginal = hasAudioSwitch ? _original! : baseIsWcoShow;

    ContentItem langBase;
    if (showOriginal) {
      ContentItem wco = originalSide!;
      if (wco is Show && wco.episodes.isEmpty && (wco.pageUrl ?? '').isNotEmpty) {
        wco = ref.watch(wcoSeriesProvider(wco.pageUrl!)).asData?.value ?? wco;
      }
      langBase = wco;
    } else if (arabicSide != null) {
      langBase = arabicSide;
    } else {
      langBase = base; // WCOFlix Movie
    }

    final alt = catalog.alternateFor(langBase);
    // Resume-aware default source (computed once per mount).
    _selectedSource ??=
        defaultSourceFor(storage, langBase, [if (alt != null) alt]);
    final item = (alt != null && _selectedSource == alt.source) ? alt : langBase;
    final primary = catalog.primaryFor(langBase);

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
                      if (hasAudioSwitch) ...[
                        _audioToggle(showOriginal, t),
                        const SizedBox(height: 14),
                      ],
                      if (alt != null) ...[
                        _sourceToggle(
                            item.source, langBase.source, alt.source, t),
                        const SizedBox(height: 18),
                      ],
                      if (item is Show) _episodes(item, t),
                      const SizedBox(height: 24),
                      _similarRow(item, t),
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

  /// "More Like This": genre-matched titles (see [similarTo]) as a horizontal
  /// poster rail. Tapping one pushes its detail page.
  Widget _similarRow(ContentItem item, Map<String, String> t) {
    final sims = _similar(item);
    if (sims.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t['row_similar']!,
            style: const TextStyle(
                fontFamily: Fonts.display,
                fontFamilyFallback: Fonts.fallback,
                fontWeight: FontWeight.w600,
                fontSize: 22,
                color: AppColors.ink)),
        const SizedBox(height: 12),
        SizedBox(
          height: 116 * 3 / 2,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            clipBehavior: Clip.none,
            itemCount: sims.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, i) => PhonePosterCard(
              item: sims[i],
              movieLabel: t['movie']!,
              onPressed: () => openPhoneDetail(context, sims[i]),
            ),
          ),
        ),
      ],
    );
  }

  /// Audio picker (Arabic dub ↔ Original), shown when a title exists in both
  /// the Arabic catalog and WCOFlix. Switching swaps the language's source.
  Widget _audioToggle(bool original, Map<String, String> t) {
    Widget chip(bool isOrig, String label) {
      final on = isOrig == original;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() {
          _original = isOrig;
          _selectedSource = null;
          _seasonIdx = 0;
        }),
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
          child: Text(label,
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
        Text(t['audio_label']!,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.inkMute)),
        const SizedBox(width: 12),
        chip(false, t['audio_arabic']!),
        chip(true, t['audio_original']!),
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
