import 'dart:async';
import 'package:flutter/material.dart';
import '../models/content_item.dart';
import '../services/device_perf.dart';
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

  /// Notifies the parent of the currently-shown slide's backdrop URL, so the
  /// shell can paint it (blurred) into the letterbox bars on non-16:9 panels.
  final void Function(String backdropUrl)? onBackdrop;

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
    this.onBackdrop,
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
    WidgetsBinding.instance.addPostFrameCallback((_) => _emitBackdrop());
  }

  /// Surface the current slide's backdrop to the parent (for the letterbox
  /// full-bleed fill). Runs after build so it never setState()s mid-build.
  void _emitBackdrop() {
    final cb = widget.onBackdrop;
    if (cb == null || widget.items.isEmpty) return;
    final i = _index < widget.items.length ? _index : 0;
    final s = widget.items[i];
    final url = s.backdropUrl.isNotEmpty ? s.backdropUrl : s.thumbnailUrl;
    if (url.isNotEmpty) cb(url);
  }

  void _setIndex(int i) {
    setState(() => _index = i);
    _emitBackdrop();
  }

  void _start() {
    _timer?.cancel();
    if (!widget.autoplay || widget.items.length <= 1) return;
    // Low-spec boxes rotate half as often: every rotation composites two
    // full-screen backdrops through the cross-fade, the biggest remaining
    // periodic GPU cost on a weak Mali.
    final period = DevicePerf.lowSpec
        ? const Duration(milliseconds: 12000)
        : const Duration(milliseconds: 6500);
    _timer = Timer.periodic(period, (_) {
      if (_focusInside) return;
      if (mounted) _setIndex((_index + 1) % widget.items.length);
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

  // Spotlight-card geometry (layout A). The card is sized to the backdrop
  // (16:9); title/pills/dots sit BELOW it, with dimmed peeks of the prev/next
  // titles on each side.
  static const double _cardH = 392; // 16:9 → ~697 wide
  static const double _peekW = 104;
  static const double _gap = 20;

  /// A dimmed, non-focusable sliver of a neighbouring title's backdrop.
  Widget _peek(ContentItem? item) {
    if (item == null) return const SizedBox(width: _peekW);
    return Opacity(
      opacity: 0.42,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: _peekW,
          height: _cardH * 0.84,
          child: OverflowBox(
            maxWidth: _cardH * 0.84 * 16 / 9,
            child: CatalogImage(
              url: item.backdropUrl,
              fallbackUrl: item.thumbnailUrl,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox(height: Dims.heroH);
    // The featured list can shrink across rebuilds (daily rotation / mode
    // switch); clamp so a stale _index can't range-error the whole Home screen.
    if (_index >= widget.items.length) _index = 0;
    final s = widget.items[_index];
    final t = widget.t;
    final n = widget.items.length;
    final prev = n > 1 ? widget.items[(_index - 1 + n) % n] : null;
    final next = n > 1 ? widget.items[(_index + 1) % n] : null;
    // RTL reads right→left: the "next" title peeks on the left, "prev" on the
    // right. LTR is the mirror.
    final leadingPeek = widget.isRtl ? next : prev;
    final trailingPeek = widget.isRtl ? prev : next;
    final crossAlign =
        widget.isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    // The backdrop card: rounded, overscanned a touch to hide baked-in pillar
    // bars, sliding (or cross-fading on low-spec) between titles.
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: AnimatedSwitcher(
          duration: Duration(milliseconds: DevicePerf.lowSpec ? 300 : 550),
          transitionBuilder: (child, anim) {
            if (DevicePerf.lowSpec) {
              return FadeTransition(opacity: anim, child: child);
            }
            final dir = widget.isRtl ? -1.0 : 1.0;
            return FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                        begin: Offset(0.12 * dir, 0), end: Offset.zero)
                    .animate(anim),
                child: child,
              ),
            );
          },
          child: Transform.scale(
            key: ValueKey(s.id),
            scale: 1.04,
            child: CatalogImage(url: s.backdropUrl, fallbackUrl: s.thumbnailUrl),
          ),
        ),
      ),
    );

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (f) => _focusInside = f,
      child: SizedBox(
        height: Dims.heroH,
        width: double.infinity,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Card row: peek · spotlight card · peek. Wrapped in a scale-down
            // FittedBox so it renders at natural (backdrop) size on a 1080p TV
            // and shrinks gracefully on any narrower/scaled panel (no overflow).
            SizedBox(
              height: _cardH,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  height: _cardH,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _peek(leadingPeek),
                      const SizedBox(width: _gap),
                      SizedBox(height: _cardH, child: card),
                      const SizedBox(width: _gap),
                      _peek(trailingPeek),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 22),
            // Title + meta + actions + dots, below the card.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Spacing.pad),
              child: Column(
                crossAxisAlignment: crossAlign,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    s.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: widget.isRtl ? TextAlign.right : TextAlign.left,
                    style: const TextStyle(
                      fontFamily: Fonts.display,
                      fontFamilyFallback: Fonts.fallback,
                      fontWeight: FontWeight.w600,
                      fontSize: 52,
                      height: 1.0,
                      letterSpacing: -0.5,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(_metaLine(s),
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.inkSoft)),
                  const SizedBox(height: 20),
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
                  const SizedBox(height: 20),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (int i = 0; i < widget.items.length; i++)
                        Padding(
                          padding: const EdgeInsetsDirectional.only(end: 12),
                          child: Focusable(
                            onPressed: () {
                              _setIndex(i);
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
                ],
              ),
            ),
          ],
        ),
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
