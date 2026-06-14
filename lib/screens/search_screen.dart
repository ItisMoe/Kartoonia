import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/content_item.dart';
import '../navigation.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../theme/layout.dart';
import '../widgets/content_card.dart';
import '../widgets/ensure_visible.dart';
import '../widgets/focusable.dart';
import '../widgets/screen_shell.dart';
import '../widgets/selectable_chip.dart';

const _kbEn = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
const _kbAr = 'ابتثجحخدذرزسشصضطظعغفقكلمنهوي';

class SearchScreen extends ConsumerWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(catalogRevProvider);
    final catalog = ref.watch(catalogProvider);
    final t = ref.watch(stringsProvider);
    final s = ref.watch(searchProvider);
    final notifier = ref.read(searchProvider.notifier);

    bool passFilter(ContentItem x) {
      if (s.filter == 'tv') return x is Show;
      if (s.filter == 'movies') return x is Movie;
      return true;
    }

    final q = s.query.trim();
    final List<ContentItem> results = q.isEmpty
        ? catalog.all.where((x) => x.tmdb != null).where(passFilter).take(12).toList()
        : catalog.search(q).where(passFilter).toList();

    return ScreenShell(
      current: 'search',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Spacing.pad, 150, Spacing.pad, 48),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // keyboard side
            SizedBox(
              width: 560,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // field
                  Container(
                    height: 84,
                    padding: const EdgeInsets.symmetric(horizontal: 26),
                    decoration: BoxDecoration(
                      color: AppColors.bg2,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: Colors.white.withValues(alpha: 0.06), width: 2),
                    ),
                    child: Row(children: [
                      const Icon(Icons.search,
                          size: 30, color: AppColors.inkMute),
                      const SizedBox(width: 18),
                      Expanded(
                        child: Text(
                          s.query.isEmpty ? t['searchPlaceholder']! : s.query,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 30,
                            fontWeight: FontWeight.w800,
                            color: s.query.isEmpty
                                ? AppColors.inkMute
                                : AppColors.ink,
                          ),
                        ),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 18),
                  // script toggle
                  Row(children: [
                    Text(t['kbHint']!,
                        style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.inkMute)),
                    const SizedBox(width: 12),
                    SelectableChip(
                        label: t['kbLatin']!,
                        selected: s.kbScript == 'en',
                        onPressed: () => notifier.setScript('en')),
                    const SizedBox(width: 10),
                    SelectableChip(
                        label: t['kbArabic']!,
                        selected: s.kbScript == 'ar',
                        onPressed: () => notifier.setScript('ar')),
                  ]),
                  const SizedBox(height: 16),
                  _Keyboard(
                    script: s.kbScript,
                    onKey: notifier.type,
                    onSpace: () => notifier.type(' '),
                    onDelete: notifier.backspace,
                    onClear: notifier.clear,
                    spaceLabel: t['space']!,
                    clearLabel: t['clear']!,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 56),
            // results side
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    for (final f in const ['all', 'tv', 'movies'])
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: SelectableChip(
                          label: t['filter_$f']!,
                          selected: s.filter == f,
                          onPressed: () => notifier.setFilter(f),
                        ),
                      ),
                  ]),
                  const SizedBox(height: 20),
                  Text(
                    q.isEmpty
                        ? t['row_popular']!
                        : '${t['resultsFor']} · ${results.length}',
                    style: const TextStyle(
                        fontFamily: Fonts.display,
                        fontFamilyFallback: Fonts.fallback,
                        fontWeight: FontWeight.w500,
                        fontSize: 30,
                        color: AppColors.ink),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: results.isEmpty
                        ? _empty(t, q.isEmpty)
                        : GridView.builder(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: Dims.resultCols,
                              mainAxisSpacing: 22,
                              crossAxisSpacing: 22,
                              childAspectRatio: Dims.cardW / Dims.cardH,
                            ),
                            itemCount: results.length,
                            itemBuilder: (context, i) => EnsureVisibleOnFocus(
                              child: PosterCard(
                                item: results[i],
                                expand: true,
                                movieLabel: t['movie']!,
                                onPressed: () =>
                                    AppNav.detail(context, results[i]),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _empty(Map<String, String> t, bool startTyping) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(30)),
            child: const Icon(Icons.search, size: 60, color: AppColors.inkMute),
          ),
          const SizedBox(height: 22),
          Text(startTyping ? t['startTyping']! : t['noResults']!,
              style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppColors.inkMute)),
        ]),
      );
}

class _Keyboard extends StatelessWidget {
  final String script;
  final void Function(String) onKey;
  final VoidCallback onSpace;
  final VoidCallback onDelete;
  final VoidCallback onClear;
  final String spaceLabel;
  final String clearLabel;

  const _Keyboard({
    required this.script,
    required this.onKey,
    required this.onSpace,
    required this.onDelete,
    required this.onClear,
    required this.spaceLabel,
    required this.clearLabel,
  });

  @override
  Widget build(BuildContext context) {
    final keys = (script == 'ar' ? _kbAr : _kbEn).split('');
    const cols = 6;
    const gap = 12.0;
    return LayoutBuilder(builder: (context, c) {
      final keyW = (c.maxWidth - gap * (cols - 1)) / cols;
      Widget tile(String label, VoidCallback onTap,
              {bool util = false, int span = 1}) =>
          _KeyTile(
            label: label,
            onPressed: onTap,
            util: util,
            width: keyW * span + gap * (span - 1),
          );
      return Directionality(
        textDirection: script == 'ar' ? TextDirection.rtl : TextDirection.ltr,
        child: Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final k in keys) tile(k, () => onKey(k)),
            tile(spaceLabel, onSpace, util: true, span: 2),
            _KeyTile(
                label: '',
                icon: Icons.backspace_outlined,
                onPressed: onDelete,
                util: true,
                width: keyW),
            tile(clearLabel, onClear, util: true, span: 2),
          ],
        ),
      );
    });
  }
}

class _KeyTile extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onPressed;
  final bool util;
  final double width;
  const _KeyTile({
    required this.label,
    this.icon,
    required this.onPressed,
    required this.util,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    return Focusable(
      onPressed: onPressed,
      builder: (context, focused) {
        final bg = focused
            ? Colors.white
            : (util ? AppColors.bg2 : AppColors.bg3);
        final fg = focused
            ? AppColors.onFocus
            : (util ? AppColors.inkSoft : AppColors.ink);
        return AnimatedScale(
          scale: focused ? 1.06 : 1,
          duration: const Duration(milliseconds: 130),
          child: Container(
            width: width,
            height: Dims.keyH,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: bg, borderRadius: BorderRadius.circular(Radii.key)),
            child: icon != null
                ? Icon(icon, size: 26, color: fg)
                : Text(label,
                    style: TextStyle(
                        fontSize: util ? 20 : 28,
                        fontWeight: FontWeight.w800,
                        color: fg)),
          ),
        );
      },
    );
  }
}
