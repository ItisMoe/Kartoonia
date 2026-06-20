import 'package:flutter/material.dart';

import '../theme/theme.dart';

/// Where the CRT screen sits inside each room illustration, as fractions of the
/// IMAGE (left, top, right, bottom). Measured against the art; fine-tune by eye.
const Rect kTvRoomScreen = Rect.fromLTRB(0.421, 0.310, 0.605, 0.600); // tv-clean
const Rect kPhoneRoomScreen =
    Rect.fromLTRB(0.401, 0.362, 0.720, 0.622); // phone-clean

const double _kTvAspect = 1376 / 768;
const double _kPhoneAspect = 768 / 1376;

/// The "boy watching an old TV" frame for the شارات reels. Paints the room
/// illustration full-bleed and places [crtChild] (the live theme video, or the
/// show's poster in audio mode) precisely inside the CRT's glowing screen, with
/// a subtle scanline + vignette overlay so it reads as if it's really on the TV.
///
/// The screen rect is given in image fractions; because the art is drawn with
/// `BoxFit.cover` (and may be cropped to fill the device), the rect is remapped
/// through the same cover transform so the video stays glued to the bezel on any
/// aspect ratio.
class TvRoomStage extends StatelessWidget {
  final bool isTv;

  /// True while the next reel is resolving — the CRT shows a small "tuning in"
  /// spinner and the content is faded out (the art's painted glow shows through).
  final bool loading;

  /// What plays inside the CRT: the shared `Video` (video mode) or a poster.
  final Widget crtChild;

  const TvRoomStage({
    super.key,
    required this.isTv,
    required this.loading,
    required this.crtChild,
  });

  @override
  Widget build(BuildContext context) {
    final asset = isTv ? 'assets/tv-clean.png' : 'assets/phone-clean.png';
    final aspect = isTv ? _kTvAspect : _kPhoneAspect;
    final frac = isTv ? kTvRoomScreen : kPhoneRoomScreen;

    return LayoutBuilder(builder: (context, c) {
      final box = Size(c.maxWidth, c.maxHeight);
      final screen = _coverRect(box, aspect, frac);
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(asset, fit: BoxFit.cover),
          Positioned.fromRect(
            rect: screen,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(screen.shortestSide * 0.06),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AnimatedOpacity(
                    opacity: loading ? 0 : 1,
                    duration: const Duration(milliseconds: 220),
                    child: crtChild,
                  ),
                  const IgnorePointer(child: _CrtOverlay()),
                  if (loading)
                    const Center(
                      child: SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(
                            strokeWidth: 2.4, color: Colors.white70),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }

  /// Map a fractional rect on the image into device pixels under `BoxFit.cover`.
  static Rect _coverRect(Size box, double imgAspect, Rect frac) {
    final boxAspect = box.width / box.height;
    final double dispW, dispH;
    if (boxAspect > imgAspect) {
      dispW = box.width;
      dispH = box.width / imgAspect;
    } else {
      dispH = box.height;
      dispW = box.height * imgAspect;
    }
    final offX = (box.width - dispW) / 2;
    final offY = (box.height - dispH) / 2;
    return Rect.fromLTWH(
      offX + frac.left * dispW,
      offY + frac.top * dispH,
      frac.width * dispW,
      frac.height * dispH,
    );
  }
}

/// Faint CRT treatment confined to the screen rect: a soft inner vignette, a
/// glassy top sheen, and thin scanlines — all low-opacity so the video stays
/// clearly visible while melting into the painted glow.
class _CrtOverlay extends StatelessWidget {
  const _CrtOverlay();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CustomPaint(painter: _ScanlinePainter()),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              radius: 0.9,
              colors: [
                Colors.transparent,
                Colors.black.withValues(alpha: 0.28),
              ],
              stops: const [0.6, 1.0],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.center,
              colors: [
                Colors.white.withValues(alpha: 0.10),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ScanlinePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = AppColors.bg1.withValues(alpha: 0.06);
    for (var y = 0.0; y < size.height; y += 3) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ScanlinePainter oldDelegate) => false;
}
