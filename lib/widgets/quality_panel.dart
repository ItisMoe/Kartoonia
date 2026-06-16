import 'package:flutter/material.dart';
import '../theme/theme.dart';
import 'focusable.dart';

/// Right-side quality picker shared by the episode and trailer players. Generic
/// over its rows: the caller supplies option [labels] and which one is selected.
class QualityPanel extends StatelessWidget {
  final String title; // t['quality']
  final String subtitle; // t['chooseQuality']
  final String backLabel; // t['back']
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onClose;
  const QualityPanel({
    super.key,
    required this.title,
    required this.subtitle,
    required this.backLabel,
    required this.labels,
    required this.selectedIndex,
    required this.onSelect,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Container(
        width: 560,
        height: double.infinity,
        color: AppColors.bg1,
        padding: const EdgeInsets.fromLTRB(44, 80, 44, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(17),
                    gradient: const LinearGradient(
                        colors: AppColors.primaryGradient)),
                child: const Icon(Icons.high_quality,
                    size: 32, color: AppColors.onPrimary),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontFamily: Fonts.display,
                            fontFamilyFallback: Fonts.fallback,
                            fontWeight: FontWeight.w600,
                            fontSize: 38,
                            color: AppColors.ink)),
                    Text(subtitle,
                        style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: AppColors.inkMute)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 26),
            Expanded(
              child: ListView(
                children: [
                  for (int i = 0; i < labels.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _QualityRow(
                        label: labels[i],
                        selected: i == selectedIndex,
                        autofocus: i == selectedIndex,
                        onPressed: () => onSelect(i),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _PillButton(
                icon: Icons.close, label: backLabel, onPressed: onClose),
          ],
        ),
      ),
    );
  }
}

/// One selectable quality row (mirrors the player's server-option styling).
class _QualityRow extends StatelessWidget {
  final String label;
  final bool selected;
  final bool autofocus;
  final VoidCallback onPressed;
  const _QualityRow({
    required this.label,
    required this.selected,
    required this.autofocus,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Focusable(
      autofocus: autofocus,
      onPressed: onPressed,
      builder: (context, focused) {
        final bg = focused ? Colors.white : AppColors.bg2;
        final fg = focused ? AppColors.onFocus : AppColors.ink;
        return AnimatedScale(
          scale: focused ? 1.04 : 1,
          duration: const Duration(milliseconds: 150),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected && !focused
                    ? AppColors.accent
                    : Colors.white.withValues(alpha: 0.06),
                width: 2,
              ),
            ),
            child: Row(children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 25, fontWeight: FontWeight.w800, color: fg)),
              const Spacer(),
              if (selected)
                Icon(Icons.check,
                    color: focused ? AppColors.onFocus : AppColors.accent),
            ]),
          ),
        );
      },
    );
  }
}

/// Pill button used for the panel's close action (mirrors the player ctrl pill).
class _PillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  const _PillButton(
      {required this.icon, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Focusable(
      onPressed: onPressed,
      builder: (context, focused) {
        final fg = focused ? AppColors.onFocus : AppColors.ink;
        final bg =
            focused ? Colors.white : Colors.white.withValues(alpha: 0.12);
        return AnimatedScale(
          scale: focused ? 1.06 : 1,
          duration: const Duration(milliseconds: 150),
          child: Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999), color: bg),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 28, color: fg),
              const SizedBox(width: 10),
              Text(label,
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800, color: fg)),
            ]),
          ),
        );
      },
    );
  }
}
