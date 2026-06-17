import 'package:flutter/material.dart';
import '../../theme/theme.dart';

/// Titled horizontal rail for the phone home feed. Children are pre-built phone
/// cards; the rail scrolls with touch (no focus management needed).
class PhoneRow extends StatelessWidget {
  final String title;
  final bool top10Badge;
  final List<Widget> cards;

  /// Height of the rail; defaults to a poster card height.
  final double height;

  const PhoneRow({
    super.key,
    required this.title,
    required this.cards,
    this.top10Badge = false,
    this.height = 174,
  });

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(children: [
              Flexible(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: Fonts.display,
                      fontFamilyFallback: Fonts.fallback,
                      fontWeight: FontWeight.w600,
                      fontSize: 19,
                      color: AppColors.ink,
                    )),
              ),
              if (top10Badge) ...[
                const SizedBox(width: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    gradient:
                        const LinearGradient(colors: AppColors.primaryGradient),
                  ),
                  child: const Text('TOP 10',
                      style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.2,
                          color: AppColors.onPrimary)),
                ),
              ],
            ]),
          ),
          SizedBox(
            height: height,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: cards.length,
              separatorBuilder: (_, _) => const SizedBox(width: 10),
              itemBuilder: (context, i) => cards[i],
            ),
          ),
        ],
      ),
    );
  }
}
