import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/app_state.dart';
import 'catalog_image.dart';

/// TV-only screensaver: after a few minutes of no input, crossfades through
/// famous backdrops. Any key/pointer dismisses it. Suppressed while the player
/// is up. On phones it is an inert pass-through.
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

    final pool = ref.read(catalogProvider).getFeaturedPool();
    final backdrops = [
      for (final i in pool)
        if (i.tmdb?.backdropUrl != null) i.backdropUrl
    ];

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _wake(),
      onPointerMove: (_) => _wake(),
      child: Stack(children: [
        widget.child,
        if (_active && backdrops.isNotEmpty)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _wake,
              child: ColoredBox(
                color: Colors.black,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 1200),
                  child: CatalogImage(
                    key: ValueKey(_index % backdrops.length),
                    url: backdrops[_index % backdrops.length],
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
