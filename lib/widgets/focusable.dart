import 'package:flutter/material.dart';

/// Shared D-pad focus wrapper. Tracks focus highlight and exposes it to a
/// builder so each control can render its own focus treatment (the design uses
/// white-bg/scale for pills & a white ring for cards). Activation (Enter /
/// Select / OK / tap) calls [onPressed]. Relies on Flutter's built-in
/// directional focus traversal for arrow-key navigation.
class Focusable extends StatefulWidget {
  final Widget Function(BuildContext context, bool focused) builder;
  final VoidCallback? onPressed;
  final bool autofocus;
  final FocusNode? focusNode;
  final ValueChanged<bool>? onFocusChange;

  const Focusable({
    super.key,
    required this.builder,
    this.onPressed,
    this.autofocus = false,
    this.focusNode,
    this.onFocusChange,
  });

  @override
  State<Focusable> createState() => _FocusableState();
}

class _FocusableState extends State<Focusable> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return FocusableActionDetector(
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
            widget.onPressed?.call();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: widget.onPressed,
        behavior: HitTestBehavior.opaque,
        child: widget.builder(context, _focused),
      ),
    );
  }
}
