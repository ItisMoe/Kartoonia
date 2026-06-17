import 'package:flutter/material.dart';
import '../theme/theme.dart';

/// Scales the fixed 1920×1080 design canvas to fit the real screen, preserving
/// aspect ratio (matches the prototype's #tv stage). Everything in the app is
/// laid out in canvas pixels, so the result is pixel-faithful to the design
/// regardless of panel resolution.
///
/// On phones the canvas is letterboxed inside the [SafeArea] so display cutouts
/// (camera notches in landscape) and the gesture/navigation bar never cover the
/// edge controls (top bar, player back button). TVs report zero insets, so the
/// SafeArea is a no-op there and the canvas still fills the panel.
class TvScaler extends StatelessWidget {
  final Widget child;

  /// Letterbox / backdrop colour painted behind the scaled canvas. Defaults to
  /// the opaque room colour for full screens; pass [Colors.transparent] when the
  /// scaled canvas is an *overlay* (e.g. the player controls) so whatever is
  /// painted beneath (the video surface) shows through.
  final Color background;

  const TvScaler({
    super.key,
    required this.child,
    this.background = AppColors.roomDeep,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: background,
      child: SafeArea(
        child: Center(
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(
              width: kCanvasW,
              height: kCanvasH,
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
