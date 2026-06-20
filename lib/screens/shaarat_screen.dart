import 'package:flutter/material.dart';
import '../widgets/shaarat_reel.dart';

/// TV شارات feed — full-screen vertical reels, D-pad up/down between them.
class ShaaratScreen extends StatelessWidget {
  const ShaaratScreen({super.key});
  @override
  Widget build(BuildContext context) => const ShaaratFeedView(isTv: true);
}
