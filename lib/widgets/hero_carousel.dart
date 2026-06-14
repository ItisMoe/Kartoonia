import 'dart:async';
import 'package:flutter/material.dart';
import '../models/content_item.dart';
import '../theme/theme.dart';
import '../theme/layout.dart';
import '../utils/genre_translations.dart';
import 'catalog_image.dart';
import 'focusable.dart';
import 'pill.dart';

class HeroCarousel extends StatefulWidget {
  final List<ContentItem> items;
  final Map<String, String> t;
  final bool isRtl;
  final bool autoplay;
  final void Function(ContentItem) onPlay;
  final void Function(ContentItem) onMoreInfo;
  final void Function(ContentItem) onToggleList;
  final bool Function(ContentItem) isInList;

  const HeroCarousel({
    super.key,
    required this.items,
    required this.t,
    required this.isRtl,
    required this.autoplay,
    required this.onPlay,
    required this.onMoreInfo,
    required this.onToggleList,
    required this.isInList,
  });

  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel> {
  int _index = 0;
  Timer? _timer;
  bool _focusInside = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _timer?.cancel();
    if (!widget.autoplay || widget.items.length <= 1) return;
    _timer = Timer.periodic(const Duration(milliseconds: 6500), (_) {
      if (_focusInside) return;
      if (mounted) setState(() => _index = (_index + 1) % widget.items.length);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _metaLine(ContentItem s) {
    final t = widget.t;
    final parts = <String>[];
    if (s.year != null) parts.add('${s.year}');
    final g = s.genres.take(2).map(translateGenre).join(' · ');
    if (g.isNotEmpty) parts.add(g);
    if (s is Show) {
      parts.add('${s.seasonCount} ${t['season']}');
    } else {
      parts.add(t['movie']!);
    }
    return parts.join('  •  ');
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox(height: Dims.heroH);
    final s = widget.items[_index];
    final t = widget.t;
    final align =
        widget.isRtl ? Alignment.centerRight : Alignment.centerLeft;

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (f) => _focusInside = f,
      child: SizedBox(
        height: Dims.heroH,
        width: double.infinity,
        child: Stack(children: [
          // cross-fading backdrop
          Positioned.fill(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 800),
              child: CatalogImage(
                key: ValueKey(s.id),
                url: s.backdropUrl,
                fallbackUrl: s.thumbnailUrl,
              ),
            ),
          ),
          // bottom + side scrims
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                  colors: [AppColors.bg1, Color(0x1F0F1430), Color(0x59080A16)],
                  stops: [0.01, 0.46, 1],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: widget.isRtl
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  end: widget.isRtl
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  colors: const [
                    Color(0xF0070914),
                    Color(0xB8070914),
                    Color(0x2E070914),
                    Colors.transparent,
                  ],
                  stops: const [0, 0.32, 0.62, 0.82],
                ),
              ),
            ),
          ),
          // content
          Positioned(
            left: widget.isRtl ? null : Spacing.pad,
            right: widget.isRtl ? Spacing.pad : null,
            bottom: 120,
            width: 760,
            child: Align(
              alignment: align,
              child: Column(
                crossAxisAlignment: widget.isRtl
                    ? CrossAxisAlignment.end
                    : CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                          color: AppColors.primary, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 10),
                    Text(t['featured']!,
                        style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 3,
                            fontSize: 17,
                            color: AppColors.primary2)),
                  ]),
                  const SizedBox(height: 18),
                  Text(
                    s.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: widget.isRtl ? TextAlign.right : TextAlign.left,
                    style: const TextStyle(
                      fontFamily: Fonts.display,
                      fontFamilyFallback: Fonts.fallback,
                      fontWeight: FontWeight.w600,
                      fontSize: 86,
                      height: 0.98,
                      letterSpacing: -1,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(_metaLine(s),
                      style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w800,
                          color: AppColors.inkSoft)),
                  const SizedBox(height: 16),
                  Text(
                    s.descriptionAr,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    textAlign: widget.isRtl ? TextAlign.right : TextAlign.left,
                    style: const TextStyle(
                        fontSize: 24, height: 1.5, color: AppColors.inkSoft),
                  ),
                  const SizedBox(height: 34),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Pill(
                      label: t['watchNow']!,
                      icon: Icons.play_arrow,
                      variant: PillVariant.primary,
                      autofocus: true,
                      onPressed: () => widget.onPlay(s),
                    ),
                    const SizedBox(width: 16),
                    Pill(
                      label: t['moreInfo']!,
                      icon: Icons.info_outline,
                      onPressed: () => widget.onMoreInfo(s),
                    ),
                    const SizedBox(width: 16),
                    _ListPill(
                      inList: widget.isInList(s),
                      t: t,
                      onPressed: () {
                        widget.onToggleList(s);
                        setState(() {});
                      },
                    ),
                  ]),
                ],
              ),
            ),
          ),
          // dots
          Positioned(
            left: widget.isRtl ? null : Spacing.pad,
            right: widget.isRtl ? Spacing.pad : null,
            bottom: 52,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < widget.items.length; i++)
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 12),
                    child: Focusable(
                      onPressed: () {
                        setState(() => _index = i);
                        _start();
                      },
                      builder: (context, focused) => AnimatedContainer(
                        duration: const Duration(milliseconds: 250),
                        width: i == _index ? 50 : 30,
                        height: 6,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          gradient: i == _index
                              ? const LinearGradient(
                                  colors: AppColors.primaryGradient)
                              : null,
                          color: i == _index
                              ? null
                              : Colors.white
                                  .withValues(alpha: focused ? 1 : 0.32),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _ListPill extends StatelessWidget {
  final bool inList;
  final Map<String, String> t;
  final VoidCallback onPressed;
  const _ListPill(
      {required this.inList, required this.t, required this.onPressed});
  @override
  Widget build(BuildContext context) {
    return Pill(
      label: inList ? t['inList']! : t['myList']!,
      icon: inList ? Icons.check : Icons.add,
      variant: inList ? PillVariant.inList : PillVariant.normal,
      onPressed: onPressed,
    );
  }
}
