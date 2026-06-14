import 'package:flutter/material.dart';

/// Wraps a focusable subtree and scrolls it into view (in every enclosing
/// scrollable — the horizontal rail and the vertical page) whenever any
/// descendant gains focus. This reproduces the design's focus-follows-scroll
/// behaviour using Flutter's native focus system.
class EnsureVisibleOnFocus extends StatelessWidget {
  final Widget child;
  final double alignment;
  const EnsureVisibleOnFocus({
    super.key,
    required this.child,
    this.alignment = 0.1,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (focused) {
        if (!focused) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx = context;
          if (!ctx.mounted) return;
          Scrollable.ensureVisible(
            ctx,
            alignment: alignment,
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
          );
        });
      },
      child: child,
    );
  }
}
