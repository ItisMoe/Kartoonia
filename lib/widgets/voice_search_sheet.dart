import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';

/// Push the compact voice listening overlay and run one recognition session.
/// The overlay owns the session lifecycle: it starts listening on open, shows
/// live partial text + a mic that reacts to loudness, commits the final
/// transcript into the search box, and dismisses itself. Back / tapping cancels.
void startVoiceSearch(BuildContext context) {
  Navigator.of(context).push(PageRouteBuilder<void>(
    opaque: false,
    barrierColor: Colors.black.withValues(alpha: 0.78),
    pageBuilder: (_, _, _) => const VoiceSearchSheet(),
    transitionsBuilder: (_, anim, _, child) =>
        FadeTransition(opacity: anim, child: child),
    transitionDuration: const Duration(milliseconds: 160),
    reverseTransitionDuration: const Duration(milliseconds: 120),
  ));
}

/// The listening overlay — a single compact bar near the bottom of the screen,
/// the way the YouTube TV app does it (no giant full-screen panel). Shows
/// "Listening…" instantly, the words as they are recognized, and a brief
/// "didn't catch that" when nothing is understood.
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
      _close();
      return;
    }
    // No transcript. If recognition failed (not a user cancel), linger briefly
    // so the "didn't catch that" message is readable before we dismiss.
    if (ref.read(voiceProvider).errored) {
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return;
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
    final partial = voice.partial;

    final header = voice.errored
        ? t['voiceNoMatch']!
        : voice.processing
            ? t['voiceProcessing']!
            : t['voiceListening']!;
    final body = partial.isNotEmpty
        ? partial
        : (voice.errored ? '' : t['voiceSpeak']!);

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
          child: Align(
            alignment: const Alignment(0, 0.84),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 64),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1040),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 22),
                  decoration: BoxDecoration(
                    color: AppColors.bg2.withValues(alpha: 0.97),
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.06), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.5),
                        blurRadius: 40,
                        offset: const Offset(0, 18),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      _MicDot(level: voice.level, phase: voice.phase),
                      const SizedBox(width: 24),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              header,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 1.2,
                                color: voice.errored
                                    ? AppColors.gold
                                    : AppColors.primary2,
                              ),
                            ),
                            if (body.isNotEmpty) ...[
                              const SizedBox(height: 8),
                              Text(
                                body,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: Fonts.display,
                                  fontFamilyFallback: Fonts.fallback,
                                  fontWeight: FontWeight.w600,
                                  fontSize: partial.isNotEmpty ? 34 : 26,
                                  height: 1.1,
                                  color: partial.isNotEmpty
                                      ? AppColors.ink
                                      : AppColors.inkMute,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(width: 20),
                      if (voice.listening)
                        _Wave(level: voice.level)
                      else
                        Text(
                          t['voiceCancel']!,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.inkMute,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact gradient mic that swells gently with the live [level]. Swaps to a
/// spinner while processing and a muted icon on error.
class _MicDot extends StatelessWidget {
  final double level;
  final VoicePhase phase;
  const _MicDot({required this.level, required this.phase});

  @override
  Widget build(BuildContext context) {
    final processing = phase == VoicePhase.processing;
    final errored = phase == VoicePhase.error;
    final pulse = 1.0 + 0.12 * level.clamp(0.0, 1.0);
    return SizedBox(
      width: 76,
      height: 76,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // reactive halo
          if (phase == VoicePhase.listening)
            AnimatedContainer(
              duration: const Duration(milliseconds: 90),
              width: 56 + 22 * level.clamp(0.0, 1.0),
              height: 56 + 22 * level.clamp(0.0, 1.0),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary
                    .withValues(alpha: 0.18 + 0.12 * level.clamp(0.0, 1.0)),
              ),
            ),
          Transform.scale(
            scale: phase == VoicePhase.listening ? pulse : 1,
            child: Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: errored
                    ? null
                    : const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: AppColors.primaryGradient,
                      ),
                color: errored ? AppColors.bg3 : null,
              ),
              child: processing
                  ? const Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(
                          strokeWidth: 3, color: AppColors.onPrimary),
                    )
                  : Icon(errored ? Icons.mic_off : Icons.mic,
                      size: 30,
                      color: errored ? AppColors.inkMute : AppColors.onPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small equalizer of bars that ride the live mic [level]. Purely reactive
/// (no controller) — the rms stream updates [level] often enough to feel alive.
class _Wave extends StatelessWidget {
  final double level;
  const _Wave({required this.level});

  static const _factors = [0.45, 0.75, 1.0, 0.7, 0.5];

  @override
  Widget build(BuildContext context) {
    final l = level.clamp(0.0, 1.0);
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        for (final f in _factors) ...[
          AnimatedContainer(
            duration: const Duration(milliseconds: 110),
            width: 6,
            height: 8 + 34 * l * f,
            decoration: BoxDecoration(
              color: AppColors.primary2,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
          const SizedBox(width: 5),
        ],
      ],
    );
  }
}
