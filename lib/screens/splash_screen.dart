import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../widgets/kartoonia_brand.dart';
import '../widgets/tv_scaler.dart';
import 'home_screen.dart';
import 'phone/phone_root.dart';

/// Branded splash shown briefly while the app settles (catalog + storage are
/// loaded in main() before the first frame). The mark pops in, the wordmark and
/// tagline rise behind it, soft brand-coloured orbs drift in the background, and
/// a gradient dot-loader pulses — then it routes to the TV home (D-pad 1920×1080
/// canvas) or the portrait phone shell depending on form factor.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with TickerProviderStateMixin {
  // One-shot entrance choreography.
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1150),
  )..forward();

  // Looping ambient motion (drifting orbs + loader dots).
  late final AnimationController _ambient = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  )..repeat();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Let the entrance play (and linger a touch) before routing on.
      await Future.delayed(const Duration(milliseconds: 1550));
      if (!mounted) return;
      final isTv = ref.read(isTvProvider);
      Navigator.of(context).pushReplacement(PageRouteBuilder(
        pageBuilder: (_, _, _) => isTv ? const HomeScreen() : const PhoneRoot(),
        transitionsBuilder: (_, a, _, c) =>
            FadeTransition(opacity: a, child: c),
        transitionDuration: const Duration(milliseconds: 400),
      ));
    });
  }

  @override
  void dispose() {
    _intro.dispose();
    _ambient.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final isTv = ref.watch(isTvProvider);

    final view = _SplashView(
      isTv: isTv,
      brandA: t['brandA']!,
      brandB: t['brandB']!,
      tagline: t['splashTagline'] ?? '',
      intro: _intro,
      ambient: _ambient,
    );

    // TV scales the splash onto the fixed canvas; phones fill the screen
    // natively so the logo is centred, not letterboxed into a band.
    return isTv ? TvScaler(child: view) : view;
  }
}

class _SplashView extends StatelessWidget {
  final bool isTv;
  final String brandA;
  final String brandB;
  final String tagline;
  final Animation<double> intro;
  final Animation<double> ambient;
  const _SplashView({
    required this.isTv,
    required this.brandA,
    required this.brandB,
    required this.tagline,
    required this.intro,
    required this.ambient,
  });

  @override
  Widget build(BuildContext context) {
    final markSize = isTv ? 150.0 : 108.0;
    final wordSize = isTv ? 58.0 : 44.0;
    final tagSize = isTv ? 24.0 : 17.0;

    // Eased sub-animations carved out of the single intro controller.
    final markScale = CurvedAnimation(
        parent: intro, curve: const Interval(0.0, 0.62, curve: Curves.easeOutBack));
    final markFade = CurvedAnimation(
        parent: intro, curve: const Interval(0.0, 0.40, curve: Curves.easeOut));
    final wordFade = CurvedAnimation(
        parent: intro, curve: const Interval(0.34, 0.80, curve: Curves.easeOut));
    final tagFade = CurvedAnimation(
        parent: intro, curve: const Interval(0.58, 1.0, curve: Curves.easeOut));

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.5),
          radius: 1.2,
          colors: [AppColors.stageTop, AppColors.roomDeep],
        ),
      ),
      child: SizedBox.expand(
        child: Stack(
          children: [
            // soft drifting brand orbs (depth, kid-friendly without noise)
            _Orbs(ambient: ambient, isTv: isTv),
            // subtle vignette to seat the content
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.center,
                    radius: 0.9,
                    colors: [Color(0x00000000), Color(0x66000000)],
                    stops: [0.55, 1.0],
                  ),
                ),
              ),
            ),
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // mark with a glow that swells in
                  AnimatedBuilder(
                    animation: intro,
                    builder: (context, child) {
                      final s = markScale.value;
                      return Opacity(
                        opacity: markFade.value,
                        child: Transform.scale(
                          scale: 0.6 + 0.4 * s,
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: AppColors.primary
                                      .withValues(alpha: 0.45 * markFade.value),
                                  blurRadius: markSize * 0.6,
                                  spreadRadius: markSize * 0.06,
                                ),
                              ],
                            ),
                            child: child,
                          ),
                        ),
                      );
                    },
                    child: KartooniaMark(size: markSize),
                  ),
                  SizedBox(height: isTv ? 36 : 26),
                  // wordmark rises + fades in
                  _RiseFade(
                    animation: wordFade,
                    dy: 0.5,
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                            text: brandA,
                            style: const TextStyle(color: AppColors.ink)),
                        TextSpan(
                            text: brandB,
                            style: const TextStyle(color: AppColors.primary2)),
                      ]),
                      style: TextStyle(
                        fontFamily: Fonts.display,
                        fontFamilyFallback: Fonts.fallback,
                        fontWeight: FontWeight.w600,
                        fontSize: wordSize,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  if (tagline.isNotEmpty) ...[
                    SizedBox(height: isTv ? 16 : 12),
                    _RiseFade(
                      animation: tagFade,
                      dy: 0.6,
                      child: Text(
                        tagline,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: tagSize,
                          letterSpacing: 0.5,
                          color: AppColors.inkMute,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            // gradient dot-loader, lower third
            Align(
              alignment: const Alignment(0, 0.78),
              child: FadeTransition(
                opacity: tagFade,
                child: _DotLoader(ambient: ambient, isTv: isTv),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Fades [child] in while sliding it up by [dy] of its own height.
class _RiseFade extends StatelessWidget {
  final Animation<double> animation;
  final double dy;
  final Widget child;
  const _RiseFade(
      {required this.animation, required this.dy, required this.child});

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: animation,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, c) => Transform.translate(
          offset: Offset(0, dy * 40 * (1 - animation.value)),
          child: c,
        ),
        child: child,
      ),
    );
  }
}

/// Three soft, brand-coloured radial orbs drifting slowly for depth.
class _Orbs extends StatelessWidget {
  final Animation<double> ambient;
  final bool isTv;
  const _Orbs({required this.ambient, required this.isTv});

  @override
  Widget build(BuildContext context) {
    final unit = isTv ? 1.0 : 0.62;
    return AnimatedBuilder(
      animation: ambient,
      builder: (context, _) {
        final p = ambient.value * 2 * math.pi;
        return Stack(children: [
          _orb(const Alignment(-0.85, -0.7), 520 * unit, AppColors.primary,
              0.20, math.sin(p) * 14, math.cos(p) * 10),
          _orb(const Alignment(0.9, -0.55), 460 * unit, AppColors.primary2,
              0.18, math.cos(p) * 16, math.sin(p) * 12),
          _orb(const Alignment(0.0, 1.05), 600 * unit, AppColors.accent, 0.14,
              math.sin(p + 1.6) * 18, math.cos(p + 1.6) * 8),
        ]);
      },
    );
  }

  Widget _orb(Alignment a, double size, Color color, double alpha, double dx,
      double dy) {
    return Align(
      alignment: a,
      child: Transform.translate(
        offset: Offset(dx, dy),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)],
            ),
          ),
        ),
      ),
    );
  }
}

/// A row of three dots that pulse in sequence, tinted with the brand gradient.
class _DotLoader extends StatelessWidget {
  final Animation<double> ambient;
  final bool isTv;
  const _DotLoader({required this.ambient, required this.isTv});

  @override
  Widget build(BuildContext context) {
    final dot = isTv ? 12.0 : 9.0;
    return AnimatedBuilder(
      animation: ambient,
      builder: (context, _) {
        final t = ambient.value * 2 * math.pi;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++) ...[
              Builder(builder: (context) {
                // staggered 0..1 pulse per dot
                final v = 0.5 + 0.5 * math.sin(t * 3 - i * 0.9);
                return Container(
                  width: dot,
                  height: dot,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Color.lerp(
                        AppColors.primary, AppColors.primary2, i / 2)!
                        .withValues(alpha: 0.45 + 0.55 * v),
                  ),
                );
              }),
              if (i < 2) SizedBox(width: dot),
            ],
          ],
        );
      },
    );
  }
}
