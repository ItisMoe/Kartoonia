import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/app_state.dart';
import '../../widgets/shaarat_reel.dart';

/// Index of the شارات tab in the phone bottom nav / IndexedStack.
const int kShaaratPhoneTab = 4;

/// Phone شارات tab — vertical-swipe reels. Plays only while it is the selected
/// tab (the shell keeps every tab alive in an IndexedStack).
class PhoneShaaratScreen extends ConsumerWidget {
  const PhoneShaaratScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final active = ref.watch(phoneTabProvider) == kShaaratPhoneTab;
    return ShaaratFeedView(isTv: false, active: active);
  }
}
