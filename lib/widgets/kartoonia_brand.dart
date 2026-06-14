import 'package:flutter/material.dart';
import '../theme/theme.dart';

/// Brand lockup: coral→amber rounded badge + "Kartoon·ia" / "كرتون·يا"
/// wordmark, matching the design's `.brand` / `.wordmark`.
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
    final badge = 46.0 * scale;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: badge,
          height: badge,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(13 * scale),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: AppColors.primaryGradient,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.55),
                blurRadius: 22,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child: Transform.rotate(
              angle: 0.14,
              child: Container(
                width: 16 * scale,
                height: 16 * scale,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(4),
                  ),
                ),
              ),
            ),
          ),
        ),
        SizedBox(width: 14 * scale),
        Text.rich(
          TextSpan(children: [
            TextSpan(
              text: brandA,
              style: TextStyle(color: AppColors.ink),
            ),
            TextSpan(
              text: brandB,
              style: const TextStyle(color: AppColors.primary2),
            ),
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
