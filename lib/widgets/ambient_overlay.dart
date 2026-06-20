import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/content_item.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../utils/screensaver_meta.dart';
import 'catalog_image.dart';

/// TV-only screensaver: after a few minutes of no input, crossfades through
/// famous backdrops with a Netflix-style title/meta card. Any key/pointer
/// dismisses it. Suppressed while the player is up. On phones it is an inert
/// pass-through.
class AmbientOverlay extends ConsumerStatefulWidget {
  final Widget child;
  const AmbientOverlay({super.key, required this.child});
  @override
  ConsumerState<AmbientOverlay> createState() => _AmbientOverlayState();
}

class _AmbientOverlayState extends ConsumerState<AmbientOverlay> {
  static const _idle = Duration(minutes: 3);
  static const _rotate = Duration(seconds: 9);
  Timer? _idleTimer;
  Timer? _rotateTimer;
  bool _active = false;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    // Observe ALL key events globally (an ancestor Focus would miss keys that
    // focused controls consume, so active navigation wouldn't reset the timer).
    HardwareKeyboard.instance.addHandler(_onKey);
    _arm();
  }

  bool _onKey(KeyEvent event) {
    final wasActive = _active;
    _wake();
    // While the screensaver is showing, the first key only dismisses it
    // (swallow it); otherwise let the key drive normal navigation.
    return wasActive;
  }

  void _arm() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idle, _show);
  }

  void _show() {
    if (ref.read(playerActiveProvider)) {
      _arm(); // never screensave over the player
      return;
    }
    setState(() {
      _active = true;
      _index = 0;
    });
    _rotateTimer?.cancel();
    _rotateTimer = Timer.periodic(_rotate, (_) {
      if (mounted) setState(() => _index++);
    });
  }

  void _wake() {
    _rotateTimer?.cancel();
    if (_active && mounted) setState(() => _active = false);
    _arm();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _idleTimer?.cancel();
    _rotateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTv = ref.watch(isTvProvider);
    if (!isTv) return widget.child;

    final t = ref.watch(stringsProvider);
    final pool = ref.read(catalogProvider).getFeaturedPool();
    final items = <ContentItem>[
      for (final i in pool)
        if (i.tmdb?.backdropUrl != null) i
    ];

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _wake(),
      onPointerMove: (_) => _wake(),
      child: Stack(children: [
        widget.child,
        if (_active && items.isNotEmpty)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _wake,
              child: ColoredBox(
                color: Colors.black,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 1200),
                      child: CatalogImage(
                        key: ValueKey(_index % items.length),
                        url: items[_index % items.length].backdropUrl,
                      ),
                    ),
                    // bottom scrim for legibility
                    const Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.center,
                            colors: [Color(0xCC000000), Color(0x00000000)],
                          ),
                        ),
                      ),
                    ),
                    // title + meta, bottom-left
                    Positioned(
                      left: 64,
                      right: 64,
                      bottom: 72,
                      child: _SaverInfo(
                        key: ValueKey('info_${_index % items.length}'),
                        item: items[_index % items.length],
                        meta: screensaverMeta(items[_index % items.length], t),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Title + meta line for the active screensaver slide. Fades/slides in each
/// time the key changes (i.e. every crossfade).
class _SaverInfo extends StatefulWidget {
  final ContentItem item;
  final String meta;
  const _SaverInfo({super.key, required this.item, required this.meta});
  @override
  State<_SaverInfo> createState() => _SaverInfoState();
}

class _SaverInfoState extends State<_SaverInfo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(parent: _c, curve: Curves.easeOut);
    return FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position:
            Tween(begin: const Offset(0, 0.12), end: Offset.zero).animate(fade),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Text(
                widget.item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: Fonts.display,
                  fontFamilyFallback: Fonts.fallback,
                  fontWeight: FontWeight.w600,
                  fontSize: 72,
                  height: 1.0,
                  letterSpacing: -1,
                  color: AppColors.ink,
                ),
              ),
            ),
            if (widget.meta.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                widget.meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 21,
                  letterSpacing: 0.5,
                  color: AppColors.inkSoft,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
