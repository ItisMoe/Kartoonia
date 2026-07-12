import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/content_item.dart';
import '../services/device_perf.dart';
import '../theme/theme.dart';
import '../theme/layout.dart';
import '../utils/genre_translations.dart';
import 'catalog_image.dart';
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
  // A Netflix-style billboard carousel: each slide is a large 16:9 backdrop card
  // that fills the hero band's height, with the neighbouring titles peeking on
  // each side (via the PageView viewport fraction). Title + actions overlay the
  // current card's lower edge.
  static const double _viewportFraction = 0.72;

  int _index = 0;
  Timer? _timer;
  bool _focusInside = false;
  late final PageController _controller =
      PageController(viewportFraction: _viewportFraction);

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

  void _onPageChanged(int i) {
    setState(() => _index = i);
    _emitBackdrop();
  }

  void _goTo(int i) {
    _controller.animateToPage(i,
        duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
    _start();
  }

  void _step(int delta) {
    final n = widget.items.length;
    if (n <= 1) return;
    _goTo((_index + delta + n) % n);
  }

  /// D-pad Left/Right on the hero: first move focus between the hero's OWN
  /// action buttons; past the row's edge flip to the prev/next featured card.
  /// The traversal is done by hand over this widget's focusable descendants —
  /// the earlier FocusScope-wide `focusInDirection` scanned the whole screen,
  /// so focus escaped to the nav/content rows and the card flip never fired.
  KeyEventResult _onKey(FocusNode node, KeyEvent e) {
    if (e is! KeyDownEvent && e is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    if (k != LogicalKeyboardKey.arrowLeft &&
        k != LogicalKeyboardKey.arrowRight) {
      return KeyEventResult.ignored;
    }
    final left = k == LogicalKeyboardKey.arrowLeft;
    final current = FocusManager.instance.primaryFocus;
    if (current != null) {
      final next = _heroNeighbor(node, current, left: left);
      if (next != null) {
        next.requestFocus();
        return KeyEventResult.handled;
      }
    }
    // No hero button further that way → change card. In RTL the "next" title
    // sits to the LEFT.
    final forward = left == widget.isRtl;
    _step(forward ? 1 : -1);
    return KeyEventResult.handled;
  }

  /// The nearest focusable INSIDE the hero strictly to the left/right of
  /// [current] **on the same row**, or null when [current] is already the
  /// outermost one in that direction. (A hero-local FocusScope +
  /// focusInDirection would be the framework way to scope this, but a nested
  /// scope confines VERTICAL traversal too — D-pad down could no longer leave
  /// the hero for the content rows.)
  FocusNode? _heroNeighbor(FocusNode hero, FocusNode current,
      {required bool left}) {
    final c = current.rect.center;
    FocusNode? best;
    var bestDx = double.infinity;
    for (final n in hero.traversalDescendants) {
      if (n == current || !n.canRequestFocus) continue;
      final center = n.rect.center;
      // Same row only: a horizontal move must never jump diagonally to a
      // focusable on another (future) row of the hero.
      if ((center.dy - c.dy).abs() > current.rect.height) continue;
      final dx = center.dx - c.dx;
      if (left ? dx >= -0.5 : dx <= 0.5) continue; // not strictly that way
      if (dx.abs() < bestDx) {
        bestDx = dx.abs();
        best = n;
      }
    }
    return best;
  }

  void _start() {
    _timer?.cancel();
    if (!widget.autoplay || widget.items.length <= 1) return;
    // Low-spec boxes rotate half as often.
    final period = DevicePerf.lowSpec
        ? const Duration(milliseconds: 12000)
        : const Duration(milliseconds: 6500);
    _timer = Timer.periodic(period, (_) {
      if (_focusInside || !mounted || !_controller.hasClients) return;
      final n = widget.items.length;
      _controller.animateToPage((_index + 1) % n,
          duration: const Duration(milliseconds: 550),
          curve: Curves.easeOutCubic);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
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

  /// Title + meta + action pills + dots, overlaid on the current card's lower
  /// edge (leading-aligned, RTL-aware).
  Widget _overlay(ContentItem s) {
    final t = widget.t;
    return Align(
      alignment:
          widget.isRtl ? Alignment.bottomRight : Alignment.bottomLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(40, 0, 40, 34),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment:
              widget.isRtl ? CrossAxisAlignment.end : CrossAxisAlignment.start,
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
                fontSize: 54,
                height: 1.0,
                letterSpacing: -0.5,
                color: AppColors.ink,
                shadows: [Shadow(color: Color(0xCC000000), blurRadius: 18)],
              ),
            ),
            const SizedBox(height: 12),
            Text(_metaLine(s),
                style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.inkSoft,
                    shadows: [Shadow(color: Color(0xAA000000), blurRadius: 12)])),
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
          ],
        ),
      ),
    );
  }

  /// One slide: a large rounded 16:9 backdrop card. The current card carries the
  /// text overlay; neighbours are dimmed and slightly shrunk so they read as a
  /// peek of what's next/previous.
  Widget _slide(int i) {
    final item = widget.items[i];
    final isCurrent = i == _index;
    final card = ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Overscanned a touch to hide the thin pillar bars baked into many
          // animated-title backdrops.
          Transform.scale(
            scale: 1.03,
            child: CatalogImage(
                url: item.backdropUrl, fallbackUrl: item.thumbnailUrl),
          ),
          // Legibility scrims: bottom (for the text) + a leading side wash.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.bottomCenter,
                end: Alignment.topCenter,
                colors: [Color(0xF2070914), Color(0x59070914), Colors.transparent],
                stops: [0, 0.5, 1],
              ),
            ),
          ),
          if (isCurrent)
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: widget.isRtl
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  end: widget.isRtl
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  colors: const [Color(0x99070914), Colors.transparent],
                  stops: const [0, 0.6],
                ),
              ),
            ),
          if (isCurrent) _overlay(item)
          // Non-current cards are dimmed so the centre reads as the focus.
          else
            const ColoredBox(color: Color(0x73070914)),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      child: AnimatedScale(
        scale: isCurrent ? 1.0 : 0.93,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        child: Center(
          child: AspectRatio(aspectRatio: 16 / 9, child: card),
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

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (f) => _focusInside = f,
      onKeyEvent: _onKey,
      child: Padding(
        // Nudge the billboard down off the very top of the screen.
        padding: const EdgeInsets.only(top: 44),
        child: SizedBox(
          height: Dims.heroH,
          width: double.infinity,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.items.length,
            onPageChanged: _onPageChanged,
            padEnds: true,
            itemBuilder: (context, i) => _slide(i),
          ),
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
