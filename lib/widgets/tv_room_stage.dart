import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

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
                  crtChild,
                  // CRT "snow" while the next theme resolves: it covers the
                  // media swap, then crossfades away to reveal the new video —
                  // like changing channels on an old TV. Doubles as the loading
                  // state (no spinner needed).
                  AnimatedOpacity(
                    opacity: loading ? 1 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: _CrtStatic(active: loading),
                  ),
                  const IgnorePointer(child: _CrtOverlay()),
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

/// Animated CRT "snow" / static — the between-reels loading state inside the TV
/// screen. A handful of grey-noise frames are generated ONCE and cycled on a
/// timer (no per-frame CPU noise generation, no shader compile), so it stays
/// smooth on weak Android-TV GPUs. Drawn unfiltered and scaled up for chunky,
/// authentic static. The timer only runs while [active].
class _CrtStatic extends StatefulWidget {
  final bool active;
  const _CrtStatic({required this.active});

  @override
  State<_CrtStatic> createState() => _CrtStaticState();
}

class _CrtStaticState extends State<_CrtStatic> {
  static const _frameCount = 8;
  static const _w = 120;
  static const _h = 90;

  final List<ui.Image> _frames = [];
  int _i = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _generate();
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(covariant _CrtStatic old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) _start();
    if (!widget.active && old.active) _stop();
  }

  Future<void> _generate() async {
    final rnd = math.Random();
    final imgs = <ui.Image>[];
    for (var f = 0; f < _frameCount; f++) {
      final bytes = Uint8List(_w * _h * 4);
      for (var p = 0; p < _w * _h; p++) {
        final v = rnd.nextInt(256); // grey snow
        final o = p * 4;
        bytes[o] = v;
        bytes[o + 1] = v;
        bytes[o + 2] = v;
        bytes[o + 3] = 255;
      }
      imgs.add(await _decode(bytes));
      if (!mounted) {
        for (final im in imgs) {
          im.dispose();
        }
        return;
      }
    }
    setState(() => _frames
      ..clear()
      ..addAll(imgs));
  }

  Future<ui.Image> _decode(Uint8List bytes) {
    final c = Completer<ui.Image>();
    ui.decodeImageFromPixels(bytes, _w, _h, ui.PixelFormat.rgba8888, c.complete);
    return c.future;
  }

  void _start() {
    _timer ??= Timer.periodic(const Duration(milliseconds: 60), (_) {
      if (_frames.isEmpty) return;
      setState(() => _i = (_i + 1) % _frames.length);
    });
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _stop();
    for (final im in _frames) {
      im.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_frames.isEmpty) return const ColoredBox(color: Color(0xFF0B0B0B));
    return CustomPaint(
      painter: _NoisePainter(_frames[_i % _frames.length]),
      willChange: true,
      size: Size.infinite,
    );
  }
}

class _NoisePainter extends CustomPainter {
  final ui.Image image;
  _NoisePainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..filterQuality = FilterQuality.none;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _NoisePainter old) => old.image != image;
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
