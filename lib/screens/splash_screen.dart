import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../widgets/kartoonia_brand.dart';
import '../widgets/tv_scaler.dart';
import 'home_screen.dart';
import 'phone/phone_root.dart';

/// Branded splash shown briefly while the app settles (catalog + storage are
/// loaded in main() before the first frame). Routes to the TV home (D-pad
/// 1920×1080 canvas) or the portrait phone shell depending on the form factor.
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
      final isTv = ref.read(isTvProvider);
      Navigator.of(context).pushReplacement(PageRouteBuilder(
        pageBuilder: (_, _, _) =>
            isTv ? const HomeScreen() : const PhoneRoot(),
        transitionsBuilder: (_, a, _, c) =>
            FadeTransition(opacity: a, child: c),
        transitionDuration: const Duration(milliseconds: 300),
      ));
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final isTv = ref.watch(isTvProvider);

    final logo = DecoratedBox(
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
            KartooniaBrand(
                brandA: t['brandA']!,
                brandB: t['brandB']!,
                scale: isTv ? 1.8 : 1.3),
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
    );

    // TV scales the splash onto the fixed canvas; phones fill the portrait
    // screen natively so the logo is centred, not letterboxed into a band.
    return isTv ? TvScaler(child: logo) : logo;
  }
}
