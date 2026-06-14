import 'package:flutter/material.dart';
import '../theme/theme.dart';
import '../theme/layout.dart';
import 'ensure_visible.dart';

/// A titled horizontal rail (design `.row`). Children are pre-built cards;
/// each is wrapped so focusing it scrolls it into view.
class ContentRow extends StatelessWidget {
  final String title;
  final int? count;
  final bool top10Badge;
  final List<Widget> cards;

  const ContentRow({
    super.key,
    required this.title,
    required this.cards,
    this.count,
    this.top10Badge = false,
  });

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 36),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Spacing.pad, 0, Spacing.pad, 16),
            child: Row(
              textBaseline: TextBaseline.alphabetic,
              crossAxisAlignment: CrossAxisAlignment.baseline,
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: Fonts.display,
                      fontFamilyFallback: Fonts.fallback,
                      fontWeight: FontWeight.w500,
                      fontSize: 32,
                      letterSpacing: 0.2,
                      color: AppColors.ink,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                if (top10Badge)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(7),
                      gradient: const LinearGradient(
                          colors: AppColors.primaryGradient),
                    ),
                    child: const Text('TOP 10',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.5,
                            color: AppColors.onPrimary)),
                  )
                else if (count != null)
                  Text('$count',
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.inkMute)),
              ],
            ),
          ),
          SizedBox(
            height: _railHeight,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                  horizontal: Spacing.pad, vertical: 6),
              itemCount: cards.length,
              clipBehavior: Clip.none,
              separatorBuilder: (_, _) => const SizedBox(width: Dims.rowGap),
              itemBuilder: (context, i) =>
                  Center(child: EnsureVisibleOnFocus(child: cards[i])),
            ),
          ),
        ],
      ),
    );
  }

  // tall enough for the largest card + focus lift
  double get _railHeight => Dims.cardH + 24;
}
