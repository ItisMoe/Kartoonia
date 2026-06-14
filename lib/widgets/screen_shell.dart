import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/theme.dart';
import 'top_bar.dart';
import 'tv_scaler.dart';

/// Wraps a screen with the persistent top bar + content on the scaled 1920×1080
/// canvas, with **separate focus scopes** for the tabs and the content.
///
/// Directional focus traversal is bounded by the nearest [FocusScope], so
/// LEFT/RIGHT within the content can never leak up to the tabs. Crossing is
/// explicit: UP from the top of the content jumps to the tabs; DOWN from the
/// tabs re-enters the content.
class ScreenShell extends StatefulWidget {
  final String current;
  final Widget child;
  final bool showChrome;
  final Color? background;

  const ScreenShell({
    super.key,
    required this.current,
    required this.child,
    this.showChrome = true,
    this.background,
  });

  @override
  State<ScreenShell> createState() => _ScreenShellState();
}

class _ScreenShellState extends State<ScreenShell> {
  final FocusScopeNode _tabsScope = FocusScopeNode(debugLabel: 'tabs');
  final FocusScopeNode _contentScope = FocusScopeNode(debugLabel: 'content');

  @override
  void dispose() {
    _tabsScope.dispose();
    _contentScope.dispose();
    super.dispose();
  }

  KeyEventResult _contentKeys(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      // Move up within the content; if already at the top, cross to the tabs.
      final moved = _contentScope.focusInDirection(TraversalDirection.up);
      if (!moved && widget.showChrome) {
        _tabsScope.requestFocus();
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored; // left/right/down use default (scoped) traversal
  }

  KeyEventResult _tabKeys(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _contentScope.requestFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final content = FocusScope(
      node: _contentScope,
      child: Focus(
        skipTraversal: true,
        canRequestFocus: false,
        onKeyEvent: _contentKeys,
        child: widget.child,
      ),
    );

    return TvScaler(
      child: ColoredBox(
        color: widget.background ?? AppColors.bg1,
        child: Stack(children: [
          Positioned.fill(child: content),
          if (widget.showChrome)
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: FocusScope(
                node: _tabsScope,
                child: Focus(
                  skipTraversal: true,
                  canRequestFocus: false,
                  onKeyEvent: _tabKeys,
                  child: TopBar(current: widget.current),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
