import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../widgets/kartoonia_brand.dart';
import '../widgets/tv_scaler.dart';
import 'home_screen.dart';

/// Branded splash shown briefly while the app settles (catalog + storage are
/// loaded in main() before the first frame).
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 800));
      if (!mounted) return;
      Navigator.of(context).pushReplacement(PageRouteBuilder(
        pageBuilder: (_, _, _) => const HomeScreen(),
        transitionsBuilder: (_, a, _, c) =>
            FadeTransition(opacity: a, child: c),
        transitionDuration: const Duration(milliseconds: 300),
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    return TvScaler(
        child: DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -0.6),
          radius: 1.1,
          colors: [AppColors.stageTop, AppColors.roomDeep],
        ),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            KartooniaBrand(brandA: t['brandA']!, brandB: t['brandB']!, scale: 1.8),
            const SizedBox(height: 40),
            const SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(
                  color: AppColors.primary, strokeWidth: 3),
            ),
          ],
        ),
      ),
    ));
  }
}
