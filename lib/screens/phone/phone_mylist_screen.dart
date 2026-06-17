import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/content_item.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../../widgets/phone/phone_poster_card.dart';
import 'phone_nav.dart';

/// Portrait My List: a 3-column grid of saved titles, or an empty-state CTA
/// that jumps to Browse.
class PhoneMyListScreen extends ConsumerWidget {
  const PhoneMyListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(catalogRevProvider);
    final catalog = ref.watch(catalogProvider);
    final t = ref.watch(stringsProvider);
    final user = ref.watch(userProvider);

    final items = user.watchlistIds
        .map(catalog.getById)
        .whereType<ContentItem>()
        .toList();

    return SafeArea(
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Text(t['browse_mylist']!,
                style: const TextStyle(
                    fontFamily: Fonts.display,
                    fontFamilyFallback: Fonts.fallback,
                    fontWeight: FontWeight.w600,
                    fontSize: 30,
                    color: AppColors.ink)),
          ),
          Expanded(
            child: items.isEmpty
                ? _empty(context, ref, t)
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 12,
                      childAspectRatio: 2 / 3,
                    ),
                    itemCount: items.length,
                    itemBuilder: (context, i) => PhonePosterCard(
                      item: items[i],
                      expand: true,
                      movieLabel: t['movie']!,
                      onPressed: () => openPhoneDetail(context, items[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context, WidgetRef ref, Map<String, String> t) =>
      Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(24)),
            child: const Icon(Icons.favorite_border,
                size: 46, color: AppColors.inkMute),
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(t['mylist_empty']!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.inkMute)),
          ),
          const SizedBox(height: 20),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => ref.read(phoneTabProvider.notifier).state = 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                gradient:
                    const LinearGradient(colors: AppColors.primaryGradient),
              ),
              child: Text(t['nav_browse']!,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: AppColors.onPrimary)),
            ),
          ),
        ]),
      );
}
