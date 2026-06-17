import 'package:flutter/material.dart';
import '../../models/content_item.dart';
import '../../theme/theme.dart';
import '../catalog_image.dart';

/// Touch poster card for the phone UI — a tappable 2:3 poster with an optional
/// continue-watching progress bar, a movie tag and a gold resume caption. Unlike
/// the TV [PosterCard] it has no D-pad focus ring; it gives press feedback with
/// a brief scale-down instead.
class PhonePosterCard extends StatefulWidget {
  final ContentItem item;
  final VoidCallback onPressed;
  final double? progress; // 0..1 continue-watching bar
  final String? caption; // gold resume caption
  final String movieLabel;
  final double width;

  /// Fill the parent (grid cells) instead of using [width].
  final bool expand;

  const PhonePosterCard({
    super.key,
    required this.item,
    required this.onPressed,
    this.progress,
    this.caption,
    this.movieLabel = 'فيلم',
    this.width = 116,
    this.expand = false,
  });

  @override
  State<PhonePosterCard> createState() => _PhonePosterCardState();
}

class _PhonePosterCardState extends State<PhonePosterCard> {
  bool _down = false;
  void _set(bool v) {
    if (v != _down) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final isMovie = item is Movie;
    final progress = widget.progress;

    final card = ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(fit: StackFit.expand, children: [
        CatalogImage(url: item.posterUrl, fallbackUrl: item.thumbnailUrl),
        const Positioned(
            left: 0, right: 0, bottom: 0, height: 90, child: _Scrim()),
        if (isMovie)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0x9E050710),
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.movie_outlined, size: 11, color: Colors.white),
                const SizedBox(width: 4),
                Text(widget.movieLabel,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 10,
                        color: Colors.white)),
              ]),
            ),
          ),
        if (widget.caption != null)
          Positioned(
            left: 8,
            right: 8,
            bottom: progress != null ? 16 : 8,
            child: Row(children: [
              const Icon(Icons.play_circle_fill, size: 12, color: AppColors.gold),
              const SizedBox(width: 4),
              Flexible(
                child: Text(widget.caption!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: AppColors.gold,
                        fontWeight: FontWeight.w800,
                        fontSize: 11)),
              ),
            ]),
          ),
        if (progress != null && progress > 0)
          Positioned(
            left: 6,
            right: 6,
            bottom: 6,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: progress.clamp(0, 1),
                minHeight: 4,
                backgroundColor: const Color(0x40FFFFFF),
                valueColor: const AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),
          ),
      ]),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onPressed,
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      child: AnimatedScale(
        scale: _down ? 0.95 : 1,
        duration: const Duration(milliseconds: 120),
        child: widget.expand
            ? AspectRatio(aspectRatio: 2 / 3, child: card)
            : SizedBox(
                width: widget.width,
                height: widget.width * 3 / 2,
                child: card,
              ),
      ),
    );
  }
}

class _Scrim extends StatelessWidget {
  const _Scrim();
  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Color(0xCC050710), Color(0x00050710)],
          ),
        ),
      );
}
