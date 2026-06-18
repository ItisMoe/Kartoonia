import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shared D-pad focus wrapper. Tracks focus highlight and exposes it to a
/// builder so each control can render its own focus treatment (the design uses
/// white-bg/scale for pills & a white ring for cards). Activation (Enter /
/// Select / OK / tap) calls [onPressed]. Relies on Flutter's built-in
/// directional focus traversal for arrow-key navigation.
///
/// When [onLongPress] is supplied, a press-and-hold of OK / a touch long-press
/// fires it instead of [onPressed]. This path is opt-in: with [onLongPress]
/// null the widget behaves exactly as a plain immediate-activate control.
class Focusable extends StatefulWidget {
  final Widget Function(BuildContext context, bool focused) builder;
  final VoidCallback? onPressed;
  final VoidCallback? onLongPress;
  final bool autofocus;
  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocusChange;

  const Focusable({
    super.key,
    required this.builder,
    this.onPressed,
    this.onLongPress,
    this.autofocus = false,
    this.focusNode,
    this.onFocusChange,
  });

  @override
  State<Focusable> createState() => _FocusableState();
}

class _FocusableState extends State<Focusable> {
  bool _focused = false;

  // D-pad long-press tracking (only used when onLongPress is set).
  static const _longPressMs = 500;
  int _downAt = 0;
  bool _longFired = false;

  static bool _isSelectKey(LogicalKeyboardKey k) =>
      k == LogicalKeyboardKey.select ||
      k == LogicalKeyboardKey.enter ||
      k == LogicalKeyboardKey.numpadEnter ||
      k == LogicalKeyboardKey.space ||
      k == LogicalKeyboardKey.gameButtonA;

  /// Invoked by the OK/Enter ActivateIntent. Without [onLongPress] this is the
  /// classic immediate press. With it, the initial key-down only arms a timer;
  /// held repeats fire the long-press, and a plain press resolves on key-up.
  void _onActivate() {
    if (widget.onLongPress == null) {
      widget.onPressed?.call();
      return;
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_downAt == 0) {
      _downAt = now;
      _longFired = false;
    } else if (!_longFired && now - _downAt >= _longPressMs) {
      _longFired = true;
      widget.onLongPress!.call();
    }
  }

  /// Catches the OK/Enter key-UP (unmapped, so it bubbles here from the inner
  /// FocusableActionDetector) to fire the short press when no long-press fired.
  KeyEventResult _onParentKey(FocusNode node, KeyEvent event) {
    if (widget.onLongPress == null || event is! KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    if (!_isSelectKey(event.logicalKey)) return KeyEventResult.ignored;
    if (_downAt != 0 && !_longFired) widget.onPressed?.call();
    _downAt = 0;
    _longFired = false;
    return KeyEventResult.ignored; // observe only; don't consume
  }

  @override
  Widget build(BuildContext context) {
    final detector = FocusableActionDetector(
      autofocus: widget.autofocus,
      focusNode: widget.focusNode,
      mouseCursor: SystemMouseCursors.click,
      onShowFocusHighlight: (v) {
        if (v != _focused) setState(() => _focused = v);
        widget.onFocusChange?.call(v);
      },
      onShowHoverHighlight: (v) {
        if (v && !_focused) setState(() => _focused = true);
        if (!v && _focused) setState(() => _focused = false);
      },
      actions: {
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            _onActivate();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        onLongPress: widget.onLongPress,
        behavior: HitTestBehavior.opaque,
        child: widget.builder(context, _focused),
      ),
    );

    if (widget.onLongPress == null) return detector;
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: _onParentKey,
      child: detector,
    );
  }
}
