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
    final recent = ref.watch(recentSearchesProvider);
    final voice = ref.watch(voiceProvider);
    final listening = voice == VoiceStatus.listening;

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
                          s.query.isNotEmpty
                              ? s.query
                              : (listening
                                  ? t['voiceListening']!
                                  : t['searchPlaceholder']!),
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
                      const SizedBox(width: 14),
                      _MicButton(
                        status: voice,
                        onPressed: () =>
                            ref.read(voiceProvider.notifier).toggle(),
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
                  if (q.isEmpty && recent.isNotEmpty) ...[
                    Row(children: [
                      Text(t['recent_searches']!,
                          style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                              color: AppColors.inkSoft)),
                      const SizedBox(width: 12),
                      SelectableChip(
                          label: t['clear']!,
                          selected: false,
                          onPressed: () => notifier.clearRecent()),
                    ]),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final r in recent)
                          SelectableChip(
                              label: r,
                              selected: false,
                              onPressed: () => notifier.setQuery(r)),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
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
                                onPressed: () {
                                  notifier.record();
                                  AppNav.detail(context, results[i]);
                                },
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

/// Voice-search trigger inside the search field. Pulses while listening and
/// shows a muted mic-off icon when speech recognition is unavailable.
class _MicButton extends StatelessWidget {
  final VoiceStatus status;
  final VoidCallback onPressed;
  const _MicButton({required this.status, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final listening = status == VoiceStatus.listening;
    final unavailable = status == VoiceStatus.unavailable;
    return Focusable(
      onPressed: onPressed,
      builder: (context, focused) {
        final bg = listening
            ? AppColors.primary
            : (focused ? Colors.white : AppColors.bg3);
        final fg = listening
            ? Colors.white
            : focused
                ? AppColors.onFocus
                : (unavailable ? AppColors.inkMute : AppColors.inkSoft);
        return AnimatedScale(
          scale: focused ? 1.06 : 1,
          duration: const Duration(milliseconds: 130),
          child: _Pulse(
            active: listening,
            child: Container(
              width: 56,
              height: 56,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
              child: Icon(unavailable ? Icons.mic_off : Icons.mic,
                  size: 28, color: fg),
            ),
          ),
        );
      },
    );
  }
}

/// Expanding-ring pulse behind its [child] while [active]. Inert otherwise.
class _Pulse extends StatefulWidget {
  final bool active;
  final Widget child;
  const _Pulse({required this.active, required this.child});

  @override
  State<_Pulse> createState() => _PulseState();
}

class _PulseState extends State<_Pulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void initState() {
    super.initState();
    if (widget.active) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_Pulse old) {
    super.didUpdateWidget(old);
    if (widget.active && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.active && _c.isAnimating) {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = _c.value;
        return Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 56 + 22 * t,
              height: 56 + 22 * t,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.25 * (1 - t)),
              ),
            ),
            child!,
          ],
        );
      },
      child: widget.child,
    );
  }
}
