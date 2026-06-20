import 'package:flutter/material.dart';
import '../theme/theme.dart';

/// The Kartoonia mark: a rounded-gradient badge with a crisp play glyph and a
/// playful spark. Pure vector (CustomPainter) so it stays sharp at any size and
/// follows the brand gradient tokens.
class KartooniaMark extends StatelessWidget {
  final double size;
  const KartooniaMark({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _MarkPainter(AppColors.primaryGradient)),
    );
  }
}

class _MarkPainter extends CustomPainter {
  final List<Color> gradient;
  _MarkPainter(this.gradient);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;
    final badge = RRect.fromRectAndRadius(rect, Radius.circular(w * 0.30));

    // soft drop shadow
    canvas.drawRRect(
      badge.shift(const Offset(0, 6)),
      Paint()
        ..color = gradient.last.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );

    // gradient badge
    canvas.drawRRect(
      badge,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ).createShader(rect),
    );

    // play glyph — filled with rounded corners (stroke pass rounds the points)
    final play = Path()
      ..moveTo(w * 0.41, h * 0.31)
      ..lineTo(w * 0.41, h * 0.69)
      ..lineTo(w * 0.71, h * 0.50)
      ..close();
    canvas.drawPath(
      play,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 0.10
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(play, Paint()..color = Colors.white);

    // spark
    canvas.drawCircle(
      Offset(w * 0.76, h * 0.24),
      w * 0.055,
      Paint()..color = Colors.white.withValues(alpha: 0.92),
    );
  }

  @override
  bool shouldRepaint(covariant _MarkPainter old) => old.gradient != gradient;
}

/// Brand lockup: the [KartooniaMark] badge + "Kartoon·ia" / "كرتون·يا" wordmark.
class KartooniaBrand extends StatelessWidget {
  final String brandA;
  final String brandB;
  final double scale;
  const KartooniaBrand({
    super.key,
    required this.brandA,
    required this.brandB,
    this.scale = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        KartooniaMark(size: 46 * scale),
        SizedBox(width: 14 * scale),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: brandA, style: const TextStyle(color: AppColors.ink)),
            TextSpan(
                text: brandB,
                style: const TextStyle(color: AppColors.primary2)),
          ]),
          style: TextStyle(
            fontFamily: Fonts.display,
            fontFamilyFallback: Fonts.fallback,
            fontWeight: FontWeight.w600,
            fontSize: 30 * scale,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}
