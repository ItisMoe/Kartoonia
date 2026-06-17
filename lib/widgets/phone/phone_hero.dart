import 'package:flutter/material.dart';
import '../../models/content_item.dart';
import '../../theme/theme.dart';
import '../catalog_image.dart';

/// Full-bleed featured banner at the top of the phone home feed (Netflix-style):
/// a tall backdrop fading into the page, the title, a genre line and the
/// My-List / Play / Info action row.
class PhoneHero extends StatelessWidget {
  final ContentItem item;
  final String genreLine;
  final bool inList;
  final String playLabel;
  final String myListLabel;
  final String infoLabel;
  final VoidCallback onPlay;
  final VoidCallback onInfo;
  final VoidCallback onToggleList;

  const PhoneHero({
    super.key,
    required this.item,
    required this.genreLine,
    required this.inList,
    required this.playLabel,
    required this.myListLabel,
    required this.infoLabel,
    required this.onPlay,
    required this.onInfo,
    required this.onToggleList,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final height = (size.height * 0.6).clamp(380.0, 620.0);

    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(fit: StackFit.expand, children: [
        CatalogImage(url: item.posterUrl, fallbackUrl: item.thumbnailUrl),
        // Fade the bottom of the poster into the page background.
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [AppColors.bg1, Color(0x000F1430), Color(0x330F1430)],
              stops: [0.02, 0.5, 1],
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 18,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (genreLine.isNotEmpty)
                Text(genreLine,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                        fontSize: 13,
                        color: AppColors.inkSoft)),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _IconAction(
                      icon: inList ? Icons.check : Icons.add,
                      label: myListLabel,
                      onTap: onToggleList),
                  const SizedBox(width: 22),
                  _PlayButton(label: playLabel, onTap: onPlay),
                  const SizedBox(width: 22),
                  _IconAction(
                      icon: Icons.info_outline,
                      label: infoLabel,
                      onTap: onInfo),
                ],
              ),
            ],
          ),
        ),
      ]),
    );
  }
}

class _PlayButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PlayButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: const LinearGradient(colors: AppColors.primaryGradient),
          boxShadow: [
            BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.45),
                blurRadius: 22,
                offset: const Offset(0, 10)),
          ],
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.play_arrow, size: 24, color: AppColors.onPrimary),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                  color: AppColors.onPrimary)),
        ]),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _IconAction(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 26, color: AppColors.ink),
        const SizedBox(height: 5),
        Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 12,
                color: AppColors.inkSoft)),
      ]),
    );
  }
}
