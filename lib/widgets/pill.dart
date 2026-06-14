import 'package:flutter/material.dart';
import '../theme/theme.dart';
import 'focusable.dart';

enum PillVariant { normal, primary, inList }

/// Design `.pill` button — used for hero/detail CTAs and player text controls.
class Pill extends StatelessWidget {
  final String label;
  final IconData? icon;
  final PillVariant variant;
  final VoidCallback? onPressed;
  final bool autofocus;
  final double fontSize;

  const Pill({
    super.key,
    required this.label,
    this.icon,
    this.variant = PillVariant.normal,
    this.onPressed,
    this.autofocus = false,
    this.fontSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    return Focusable(
      autofocus: autofocus,
      onPressed: onPressed,
      builder: (context, focused) {
        Color bg;
        Color fg;
        Gradient? gradient;
        List<BoxShadow>? shadow;

        switch (variant) {
          case PillVariant.primary:
            bg = AppColors.primary;
            fg = AppColors.onPrimary;
            gradient = const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: AppColors.primaryGradient,
            );
            shadow = [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.5),
                blurRadius: 30,
                offset: const Offset(0, 14),
              ),
            ];
            break;
          case PillVariant.inList:
            bg = AppColors.accent.withValues(alpha: 0.20);
            fg = const Color(0xFFBDFFF4);
            break;
          case PillVariant.normal:
            bg = Colors.white.withValues(alpha: 0.14);
            fg = AppColors.ink;
            break;
        }

        if (focused) {
          gradient = null;
          bg = Colors.white;
          fg = AppColors.onFocus;
          shadow = [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.7),
              blurRadius: 36,
              offset: const Offset(0, 16),
            ),
            BoxShadow(
              color: Colors.white.withValues(alpha: 0.25),
              blurRadius: 0,
              spreadRadius: 4,
            ),
          ];
        }

        return AnimatedScale(
          scale: focused ? 1.06 : 1,
          duration: const Duration(milliseconds: 160),
          curve: ease,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 16),
            decoration: BoxDecoration(
              color: gradient == null ? bg : null,
              gradient: gradient,
              borderRadius: BorderRadius.circular(Radii.chip),
              boxShadow: shadow,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 26, color: fg),
                  const SizedBox(width: 12),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: Fonts.ui,
                    fontFamilyFallback: Fonts.fallback,
                    fontWeight: FontWeight.w800,
                    fontSize: fontSize,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
