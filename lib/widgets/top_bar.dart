import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../theme/layout.dart';
import '../navigation.dart';
import '../playback.dart';
import 'focusable.dart';
import 'kartoonia_brand.dart';

/// Persistent top navigation bar (design `.topbar`). Hidden on the player.
class TopBar extends ConsumerWidget {
  /// One of: home, search, tv, movies, mylist, import, settings, ''.
  final String current;
  const TopBar({super.key, required this.current});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    return Container(
      height: Dims.topBarH,
      padding: const EdgeInsets.symmetric(horizontal: Spacing.pad),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xEB0A0D1F), Color(0x000A0D1F)],
        ),
      ),
      // Own traversal group so D-pad LEFT/RIGHT stays among the tabs and
      // content rows below never get horizontally "leaked" up into the tabs.
      child: FocusTraversalGroup(
        child: Row(
        children: [
          KartooniaBrand(brandA: t['brandA']!, brandB: t['brandB']!),
          const SizedBox(width: 32),
          _NavItem(
              label: t['nav_search']!,
              icon: Icons.search,
              active: current == 'search',
              onPressed: () => AppNav.search(context)),
          _NavItem(
              label: t['nav_home']!,
              active: current == 'home',
              onPressed: () => AppNav.home(context)),
          _NavItem(
              label: t['nav_tv']!,
              active: current == 'tv',
              onPressed: () => AppNav.browse(context, 'tv')),
          _NavItem(
              label: t['nav_movies']!,
              active: current == 'movies',
              onPressed: () => AppNav.browse(context, 'movies')),
          _NavItem(
              label: t['nav_shaarat']!,
              active: current == 'shaarat',
              onPressed: () => AppNav.shaarat(context)),
          _NavItem(
              label: t['nav_mylist']!,
              active: current == 'mylist',
              onPressed: () => AppNav.browse(context, 'mylist')),
          const Spacer(),
          // "Surprise me" — play a random cartoon from anywhere in the app.
          _CircleAction(
            icon: Icons.shuffle,
            tooltip: t['shuffle']!,
            onPressed: () => playRandom(context, ref),
          ),
          const SizedBox(width: 12),
          _CircleAction(
            icon: Icons.settings,
            tooltip: t['settings']!,
            onPressed: () => AppNav.settings(context),
          ),
        ],
      ),
      ),
    );
  }
}

/// Circular icon action on the right of the top bar (shuffle / settings).
class _CircleAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  const _CircleAction(
      {required this.icon, required this.tooltip, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Focusable(
      onPressed: onPressed,
      builder: (context, focused) => AnimatedScale(
        scale: focused ? 1.06 : 1,
        duration: const Duration(milliseconds: 160),
        child: Semantics(
          label: tooltip,
          button: true,
          child: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color:
                  focused ? Colors.white : Colors.white.withValues(alpha: 0.07),
            ),
            child: Icon(icon,
                size: 27,
                color: focused ? AppColors.onFocus : AppColors.inkSoft),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool active;
  final VoidCallback onPressed;
  const _NavItem({
    required this.label,
    this.icon,
    required this.active,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Focusable(
      onPressed: onPressed,
      builder: (context, focused) {
        final color = focused
            ? AppColors.onFocus
            : (active ? AppColors.ink : AppColors.inkMute);
        return AnimatedScale(
          scale: focused ? 1.06 : 1,
          duration: const Duration(milliseconds: 160),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.chip),
              color: focused ? Colors.white : Colors.transparent,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[
                Icon(icon, size: 22, color: color),
                const SizedBox(width: 9),
              ],
              Text(label,
                  style: TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w700, color: color)),
            ]),
          ),
        );
      },
    );
  }
}
