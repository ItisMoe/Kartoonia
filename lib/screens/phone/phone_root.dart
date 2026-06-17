import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import 'phone_browse_screen.dart';
import 'phone_home_screen.dart';
import 'phone_mylist_screen.dart';
import 'phone_search_screen.dart';

/// Root of the portrait phone experience: four keep-alive tabs behind a
/// Netflix-style bottom navigation bar (Home · Browse · Search · My List).
/// Detail / Player / Settings are pushed on top via the normal navigator.
class PhoneRoot extends ConsumerWidget {
  const PhoneRoot({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final index = ref.watch(phoneTabProvider);

    return Scaffold(
      backgroundColor: AppColors.bg1,
      body: IndexedStack(
        index: index,
        children: const [
          PhoneHomeScreen(),
          PhoneBrowseScreen(),
          PhoneSearchScreen(),
          PhoneMyListScreen(),
        ],
      ),
      bottomNavigationBar: _PhoneNavBar(
        index: index,
        onTap: (i) => ref.read(phoneTabProvider.notifier).state = i,
        items: [
          (Icons.home_rounded, t['nav_home']!),
          (Icons.grid_view_rounded, t['nav_browse']!),
          (Icons.search_rounded, t['nav_search']!),
          (Icons.favorite_rounded, t['nav_mylist']!),
        ],
      ),
    );
  }
}

class _PhoneNavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final List<(IconData, String)> items;
  const _PhoneNavBar(
      {required this.index, required this.onTap, required this.items});

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.bg0,
        border: Border(top: BorderSide(color: Color(0x14FFFFFF))),
      ),
      padding: EdgeInsets.only(top: 8, bottom: 8 + bottomInset),
      child: Row(
        children: [
          for (int i = 0; i < items.length; i++)
            Expanded(
              child: _NavTab(
                icon: items[i].$1,
                label: items[i].$2,
                active: i == index,
                onTap: () => onTap(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  const _NavTab(
      {required this.icon,
      required this.label,
      required this.active,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.primary2 : AppColors.inkMute;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 25, color: color),
          const SizedBox(height: 4),
          Text(label,
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                  color: color)),
        ],
      ),
    );
  }
}
