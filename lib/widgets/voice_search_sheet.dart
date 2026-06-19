import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';

/// Push the full-screen voice listening overlay and run one recognition session.
/// The overlay owns the session lifecycle: it starts listening on open, shows
/// live partial text + a mic that reacts to loudness, commits the final
/// transcript into the search box, and dismisses itself. Back / tapping cancels.
void startVoiceSearch(BuildContext context) {
  Navigator.of(context).push(PageRouteBuilder<void>(
    opaque: false,
    barrierColor: Colors.black.withValues(alpha: 0.82),
    pageBuilder: (_, _, _) => const VoiceSearchSheet(),
    transitionsBuilder: (_, anim, _, child) =>
        FadeTransition(opacity: anim, child: child),
    transitionDuration: const Duration(milliseconds: 180),
    reverseTransitionDuration: const Duration(milliseconds: 140),
  ));
}

/// The listening overlay. Mirrors the YouTube-app experience: an in-app mic
/// that pulses with your voice and shows the words as they are recognized,
/// rather than handing off to an inconsistent system dialog.
class VoiceSearchSheet extends ConsumerStatefulWidget {
  const VoiceSearchSheet({super.key});
  @override
  ConsumerState<VoiceSearchSheet> createState() => _VoiceSearchSheetState();
}

class _VoiceSearchSheetState extends ConsumerState<VoiceSearchSheet> {
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    // Kick off the session after the first frame so the route is mounted and
    // the overlay is already visible when the mic opens.
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    final notifier = ref.read(voiceProvider.notifier);
    final text = await notifier.start();
    if (!mounted) return;
    if (text != null && text.isNotEmpty) {
      ref.read(searchProvider.notifier).setQuery(text);
    }
    _close();
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    if (mounted) Navigator.of(context).maybePop();
  }

  /// Dismiss = abort the live session (the natural end-of-speech path resolves
  /// on its own via [_run]).
  void _cancel() {
    ref.read(voiceProvider.notifier).cancel();
    // _run() observes the null result and closes; nothing else to do here.
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final voice = ref.watch(voiceProvider);
    final hasPartial = voice.partial.isNotEmpty;
    return PopScope(
      // Back press cancels the session before the route pops.
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) return;
        ref.read(voiceProvider.notifier).cancel();
      },
      child: Focus(
        autofocus: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _cancel,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _MicOrb(level: voice.level),
                const SizedBox(height: 48),
                Text(
                  t['voiceListening']!,
                  style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AppColors.inkSoft),
                ),
                const SizedBox(height: 20),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 900),
                  child: Text(
                    hasPartial ? voice.partial : t['voiceSpeak']!,
                    textAlign: TextAlign.center,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontFamily: Fonts.display,
                      fontFamilyFallback: Fonts.fallback,
                      fontWeight: FontWeight.w600,
                      fontSize: hasPartial ? 46 : 32,
                      color: hasPartial ? AppColors.ink : AppColors.inkMute,
                    ),
                  ),
                ),
                const SizedBox(height: 56),
                Text(
                  t['voiceCancel']!,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.inkMute),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A microphone disc with two concentric rings that swell with the live mic
/// [level] (0..1). Gives immediate "it's hearing me" feedback on every device.
class _MicOrb extends StatelessWidget {
  final double level;
  const _MicOrb({required this.level});

  @override
  Widget build(BuildContext context) {
    // Ease the raw loudness so quiet speech still visibly moves the rings.
    final l = math.pow(level.clamp(0.0, 1.0), 0.6).toDouble();
    const base = 150.0;
    return SizedBox(
      width: 360,
      height: 360,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _ring(base + 150 * l, 0.10 + 0.06 * l),
          _ring(base + 80 * l, 0.16 + 0.10 * l),
          Container(
            width: base,
            height: base,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: AppColors.primaryGradient,
              ),
            ),
            child: const Icon(Icons.mic, size: 72, color: AppColors.onPrimary),
          ),
        ],
      ),
    );
  }

  Widget _ring(double size, double alpha) => AnimatedContainer(
        duration: const Duration(milliseconds: 90),
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.primary.withValues(alpha: alpha),
        ),
      );
}
