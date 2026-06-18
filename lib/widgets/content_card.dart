import 'package:flutter/material.dart';
import '../models/content_item.dart';
import '../theme/theme.dart';
import '../theme/layout.dart';
import 'catalog_image.dart';
import 'focusable.dart';

TextStyle _displayStyle(double size, [FontWeight w = FontWeight.w500]) =>
    TextStyle(
      fontFamily: Fonts.display,
      fontFamilyFallback: Fonts.fallback,
      fontWeight: w,
      fontSize: size,
      color: AppColors.ink,
      height: 1.05,
    );

/// White focus ring (design `.card-ring`) drawn just outside the card.
class _CardRing extends StatelessWidget {
  final bool visible;
  final double radius;
  const _CardRing({required this.visible, required this.radius});
  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: -4,
      top: -4,
      right: -4,
      bottom: -4,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 160),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius + 4),
              border: Border.all(color: Colors.white, width: 5),
              boxShadow: const [
                BoxShadow(color: Color(0x52000000), blurRadius: 1.5),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Small corner tag naming the catalog source. Shown only on titles that exist
/// in both sources, so the two duplicate cards are distinguishable.
Widget _sourceBadge(String label) => Positioned(
      top: 12,
      left: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0x9E050710),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.w800, fontSize: 13, color: Colors.white)),
      ),
    );

Widget _movieTag(BuildContext context, String label) => Positioned(
      top: 12,
      right: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0x9E050710),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.movie_outlined, size: 15, color: Colors.white),
          const SizedBox(width: 5),
          Text(label,
              style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 14, color: Colors.white)),
        ]),
      ),
    );

const _scrim = DecoratedBox(
  decoration: BoxDecoration(
    gradient: LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [Color(0xEB050710), Color(0x00050710)],
      stops: [0.0, 0.46],
    ),
  ),
);

class PosterCard extends StatelessWidget {
  final ContentItem item;
  final VoidCallback onPressed;
  final double? progress; // 0..1 continue-watching bar
  final String? caption; // gold resume caption (e.g. "م1 · ح3")
  final bool wide;
  final bool autofocus;
  final bool expand; // fill parent (for grid cells) instead of fixed size
  final String movieLabel;
  final String? sourceLabel; // catalog-source badge for cross-source duplicates
  final VoidCallback? onLongPress; // press-and-hold OK / touch long-press

  const PosterCard({
    super.key,
    required this.item,
    required this.onPressed,
    this.progress,
    this.caption,
    this.wide = false,
    this.autofocus = false,
    this.expand = false,
    this.movieLabel = 'فيلم',
    this.sourceLabel,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final w = wide ? Dims.wideW : Dims.cardW;
    final h = wide ? Dims.wideH : Dims.cardH;
    final isMovie = item is Movie;

    return Focusable(
      autofocus: autofocus,
      onPressed: onPressed,
      onLongPress: onLongPress,
      builder: (context, focused) {
        final stack = Stack(clipBehavior: Clip.none, children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(Radii.card),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: focused ? 0.8 : 0.55),
                          blurRadius: focused ? 60 : 40,
                          offset: const Offset(0, 18),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(Radii.card),
                      child: Stack(fit: StackFit.expand, children: [
                        CatalogImage(
                          url: wide ? item.backdropUrl : item.posterUrl,
                          fallbackUrl: item.thumbnailUrl,
                        ),
                        const Positioned(
                            left: 0, right: 0, bottom: 0, height: 160, child: _scrim),
                        if (isMovie) _movieTag(context, movieLabel),
                        if (sourceLabel != null) _sourceBadge(sourceLabel!),
                        if (caption != null)
                          Positioned(
                            left: 16,
                            right: 16,
                            bottom: progress != null ? 44 : 30,
                            child: Row(children: [
                              const Icon(Icons.play_circle_fill,
                                  size: 16, color: AppColors.gold),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(caption!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: AppColors.gold,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                        letterSpacing: 0.4)),
                              ),
                            ]),
                          ),
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: progress != null
                              ? 30
                              : (caption != null ? 52 : 16),
                          child: Text(
                            item.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: _displayStyle(wide ? 26 : 24),
                          ),
                        ),
                        if (progress != null && progress! > 0)
                          Positioned(
                            left: 14,
                            right: 14,
                            bottom: 14,
                            child: _ProgressBar(value: progress!),
                          ),
                      ]),
                    ),
                  ),
                ),
          _CardRing(visible: focused, radius: Radii.card),
        ]);

        final content = AnimatedScale(
          scale: focused ? 1.04 : 1,
          duration: const Duration(milliseconds: 200),
          curve: ease,
          child: Transform.translate(
            offset: Offset(0, focused ? -3 : 0),
            child: stack,
          ),
        );

        return expand
            ? SizedBox.expand(child: content)
            : SizedBox(width: w, height: h, child: content);
      },
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final double value;
  const _ProgressBar({required this.value});
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 6,
        child: Stack(children: [
          const Positioned.fill(
              child: ColoredBox(color: Color(0x40FFFFFF))),
          FractionallySizedBox(
            widthFactor: value.clamp(0, 1),
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: AppColors.primaryGradient),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Landscape "spotlight" card — backdrop art + title + genre line.
class BackdropCard extends StatelessWidget {
  final ContentItem item;
  final VoidCallback onPressed;
  final String genreLine;
  const BackdropCard({
    super.key,
    required this.item,
    required this.onPressed,
    this.genreLine = '',
  });

  @override
  Widget build(BuildContext context) {
    return Focusable(
      onPressed: onPressed,
      builder: (context, focused) {
        return AnimatedScale(
          scale: focused ? 1.04 : 1,
          duration: const Duration(milliseconds: 200),
          curve: ease,
          child: SizedBox(
            width: Dims.backdropW,
            height: Dims.backdropH,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.card),
                  child: Stack(fit: StackFit.expand, children: [
                    CatalogImage(
                        url: item.backdropUrl, fallbackUrl: item.thumbnailUrl),
                    const Positioned(
                        left: 0, right: 0, bottom: 0, height: 200, child: _scrim),
                    Positioned(
                      left: 22,
                      right: 22,
                      bottom: 20,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(item.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: _displayStyle(30)),
                          if (genreLine.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(genreLine,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.inkSoft)),
                          ],
                        ],
                      ),
                    ),
                  ]),
                ),
              ),
              _CardRing(visible: focused, radius: Radii.card),
            ]),
          ),
        );
      },
    );
  }
}

/// Top-10 card — giant outlined rank numeral beside a poster.
class Top10Card extends StatelessWidget {
  final ContentItem item;
  final int rank;
  final VoidCallback onPressed;
  const Top10Card({
    super.key,
    required this.item,
    required this.rank,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Focusable(
      onPressed: onPressed,
      builder: (context, focused) {
        return AnimatedScale(
          scale: focused ? 1.04 : 1,
          duration: const Duration(milliseconds: 200),
          curve: ease,
          child: SizedBox(
            width: Dims.top10W,
            height: Dims.top10H,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Transform.translate(
                  offset: const Offset(34, 0), // overlap the poster
                  child: Text(
                    '$rank',
                    style: TextStyle(
                      fontFamily: Fonts.display,
                      fontWeight: FontWeight.w700,
                      fontSize: Dims.top10RankSize,
                      height: 0.72,
                      foreground: Paint()
                        ..style = PaintingStyle.stroke
                        ..strokeWidth = 5
                        ..color = focused
                            ? Colors.white
                            : const Color(0xA6ADB8E0),
                    ),
                  ),
                ),
                SizedBox(
                  width: Dims.top10PosterW,
                  height: Dims.top10H,
                  child: Stack(clipBehavior: Clip.none, children: [
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(Radii.card),
                        child: Stack(fit: StackFit.expand, children: [
                          CatalogImage(
                              url: item.posterUrl,
                              fallbackUrl: item.thumbnailUrl),
                          const Positioned(
                              left: 0, right: 0, bottom: 0, height: 120, child: _scrim),
                          Positioned(
                            left: 14,
                            right: 14,
                            bottom: 14,
                            child: Text(item.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: _displayStyle(20)),
                          ),
                        ]),
                      ),
                    ),
                    _CardRing(visible: focused, radius: Radii.card),
                  ]),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
