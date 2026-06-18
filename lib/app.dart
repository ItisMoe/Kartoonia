import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'navigation.dart';
import 'screens/splash_screen.dart';
import 'state/app_state.dart';
import 'theme/theme.dart';
import 'widgets/ambient_overlay.dart';

class KartooniaApp extends ConsumerWidget {
  const KartooniaApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isRtl = ref.watch(settingsProvider).isRtl;
    return MaterialApp(
      title: 'Kartoonia',
      navigatorKey: appNavigatorKey,
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const SplashScreen(),
      builder: (context, child) {
        // Direction follows the chosen language. The Material provides a proper
        // DefaultTextStyle for every screen (without it, text outside a Scaffold
        // shows the framework's yellow double-underline error decoration).
        //
        // NOTE: the 1920×1080 design-canvas scaling is applied per-screen (in
        // ScreenShell / Splash), NOT globally — so full-screen platform views
        // (the video player + WebViews) render at native size instead of inside
        // a transform, which mis-composites them on Android.
        return Directionality(
          textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
          child: Material(
            type: MaterialType.transparency,
            child: AmbientOverlay(
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        );
      },
    );
  }
}
