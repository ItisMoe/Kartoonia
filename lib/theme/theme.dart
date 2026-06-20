import 'package:flutter/material.dart';

/// Kartoonia design tokens — ported verbatim from the design handoff
/// (`app/styles.css` :root). Dark cinematic kids streaming UI, authored at
/// 1920×1080 and scaled to the viewport.
class AppColors {
  static const bg0 = Color(0xFF0A0D1F); // deepest
  static const bg1 = Color(0xFF0F1430); // app base
  static const bg2 = Color(0xFF161C44); // raised surface
  static const bg3 = Color(0xFF1F2757); // card / chip
  static const ink = Color(0xFFFFFFFF);
  static const inkSoft = Color(0xFFC4CBE8);
  static const inkMute = Color(0xFF8B93BD);
  static const primary = Color(0xFFFF4E79); // vivid rose
  static const primary2 = Color(0xFFFFA23A); // warm amber
  static const accent = Color(0xFF4AD6C8); // teal pop
  static const gold = Color(0xFFFFD56B);
  static const onPrimary = Color(0xFF2A0E06); // dark text on coral/amber
  static const onFocus = Color(0xFF11142E); // dark text on white focus

  static const stageTop = Color(0xFF11142E);
  static const roomDeep = Color(0xFF05060D);

  static const primaryGradient = [primary, primary2];
}

class Radii {
  static const double card = 18;
  static const double lg = 26;
  static const double chip = 999;
  static const double key = 14;
  static const double ep = 16;
}

class Spacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double pad = 64; // screen side padding in the 1920 canvas
}

/// Font families. Latin display = Fredoka; Latin UI = Nunito; Arabic = Cairo.
/// Cairo is the global fallback so Arabic always renders.
class Fonts {
  static const display = 'Fredoka';
  static const ui = 'Nunito';
  static const arabic = 'Cairo';
  static const fallback = ['Cairo', 'Nunito'];
}

/// The fixed design canvas. Everything is laid out in these logical pixels and
/// scaled to fit the real screen (matches the prototype's #tv 1920×1080 stage).
const double kCanvasW = 1920;
const double kCanvasH = 1080;

const ease = Cubic(0.22, 0.61, 0.36, 1);

ThemeData buildAppTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: AppColors.bg1,
    canvasColor: AppColors.bg1,
    colorScheme: base.colorScheme.copyWith(
      primary: AppColors.primary,
      secondary: AppColors.accent,
      surface: AppColors.bg2,
    ),
    textTheme: base.textTheme.apply(
      fontFamily: Fonts.ui,
      fontFamilyFallback: Fonts.fallback,
      bodyColor: AppColors.ink,
      displayColor: AppColors.ink,
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
  );
}
