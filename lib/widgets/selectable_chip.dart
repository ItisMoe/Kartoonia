import 'package:flutter/material.dart';
import '../theme/theme.dart';
import 'focusable.dart';

/// Shared chip/segment control matching the design's `.chip` / `.alpha` /
/// `.kb-tog` / `.set-opt`: idle = bg2 surface; selected = coral→amber gradient
/// with dark text; focused = white bg + dark text + scale 1.06.
class SelectableChip extends StatelessWidget {
  final String label;
  final bool selected;
  final bool disabled;
  final VoidCallback onPressed;
  final EdgeInsets padding;
  final double radius;
  final double fontSize;
  final bool autofocus;
  final double? minWidth;

  const SelectableChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onPressed,
    this.disabled = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 11),
    this.radius = Radii.chip,
    this.fontSize = 20,
    this.autofocus = false,
    this.minWidth,
  });

  @override
  Widget build(BuildContext context) {
    if (disabled) {
      return Opacity(
        opacity: 0.22,
        child: _box(false, false),
      );
    }
    return Focusable(
      autofocus: autofocus,
      onPressed: onPressed,
      builder: (context, focused) => AnimatedScale(
        scale: focused ? 1.06 : 1,
        duration: const Duration(milliseconds: 150),
        curve: ease,
        child: _box(selected, focused),
      ),
    );
  }

  Widget _box(bool sel, bool focused) {
    Color fg;
    Gradient? gradient;
    Color bg;
    if (focused) {
      bg = Colors.white;
      fg = AppColors.onFocus;
      gradient = null;
    } else if (sel) {
      bg = AppColors.primary;
      fg = AppColors.onPrimary;
      gradient = const LinearGradient(colors: AppColors.primaryGradient);
    } else {
      bg = AppColors.bg2;
      fg = AppColors.inkSoft;
      gradient = null;
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      constraints: minWidth != null ? BoxConstraints(minWidth: minWidth!) : null,
      alignment: Alignment.center,
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? bg : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: sel || focused
            ? null
            : Border.all(color: Colors.white.withValues(alpha: 0.06)),
        boxShadow: focused
            ? [
                BoxShadow(
                    color: Colors.black.withValues(alpha: 0.7),
                    blurRadius: 36,
                    offset: const Offset(0, 16)),
                BoxShadow(
                    color: Colors.white.withValues(alpha: 0.25),
                    spreadRadius: 4),
              ]
            : null,
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: fontSize, fontWeight: FontWeight.w800, color: fg)),
    );
  }
}
