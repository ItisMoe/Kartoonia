import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/content_item.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../../widgets/phone/phone_poster_card.dart';
import '../../widgets/voice_search_sheet.dart';
import 'phone_nav.dart';

/// Portrait search: a native text field (the OS keyboard), a voice button and a
/// 3-column results grid. Reuses [searchProvider] so voice transcripts flow in.
class PhoneSearchScreen extends ConsumerStatefulWidget {
  const PhoneSearchScreen({super.key});
  @override
  ConsumerState<PhoneSearchScreen> createState() => _PhoneSearchScreenState();
}

class _PhoneSearchScreenState extends ConsumerState<PhoneSearchScreen> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.text = ref.read(searchProvider).query;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(catalogRevProvider);
    // Keep the field in sync when the query changes elsewhere (voice search).
    ref.listen(searchProvider.select((s) => s.query), (_, q) {
      if (_controller.text != q) {
        _controller.value = TextEditingValue(
          text: q,
          selection: TextSelection.collapsed(offset: q.length),
        );
      }
    });

    final catalog = ref.watch(catalogProvider);
    final t = ref.watch(stringsProvider);
    final s = ref.watch(searchProvider);
    final notifier = ref.read(searchProvider.notifier);
    final voice = ref.watch(voiceProvider);

    bool passFilter(ContentItem x) {
      if (s.filter == 'tv') return x is Show;
      if (s.filter == 'movies') return x is Movie;
      return true;
    }

    final q = s.query.trim();
    final results = q.isEmpty
        ? catalog.all.where((x) => x.tmdb != null).where(passFilter).take(18).toList()
        : catalog.search(q).where(passFilter).toList();

    return SafeArea(
      bottom: false,
      child: Column(children: [
        // Search field
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.bg2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
            ),
            child: Row(children: [
              const Icon(Icons.search, size: 22, color: AppColors.inkMute),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _controller,
                  onChanged: notifier.setQuery,
                  textInputAction: TextInputAction.search,
                  style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink),
                  cursorColor: AppColors.primary,
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: t['searchPlaceholder'],
                    hintStyle: const TextStyle(
                        color: AppColors.inkMute, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              if (s.query.isNotEmpty)
                GestureDetector(
                  onTap: () {
                    notifier.clear();
                    _controller.clear();
                  },
                  child: const Icon(Icons.close,
                      size: 20, color: AppColors.inkMute),
                ),
              if (!voice.unavailable) ...[
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: () => startVoiceSearch(context),
                  child: Icon(Icons.mic,
                      size: 22,
                      color: voice.listening
                          ? AppColors.primary
                          : AppColors.inkSoft),
                ),
              ],
            ]),
          ),
        ),
        // Type filter chips
        SizedBox(
          height: 42,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: [
              for (final f in const ['all', 'tv', 'movies'])
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _FilterChip(
                    label: t['filter_$f']!,
                    selected: s.filter == f,
                    onTap: () => notifier.setFilter(f),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: results.isEmpty
              ? _empty(t, q.isEmpty)
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    mainAxisSpacing: 14,
                    crossAxisSpacing: 12,
                    childAspectRatio: 2 / 3,
                  ),
                  itemCount: results.length,
                  itemBuilder: (context, i) => PhonePosterCard(
                    item: results[i],
                    expand: true,
                    movieLabel: t['movie']!,
                    onPressed: () => openPhoneDetail(context, results[i]),
                  ),
                ),
        ),
      ]),
    );
  }

  Widget _empty(Map<String, String> t, bool startTyping) => Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(24)),
            child: const Icon(Icons.search, size: 46, color: AppColors.inkMute),
          ),
          const SizedBox(height: 18),
          Text(startTyping ? t['startTyping']! : t['noResults']!,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: AppColors.inkMute)),
        ]),
      );
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _FilterChip(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: selected
              ? const LinearGradient(colors: AppColors.primaryGradient)
              : null,
          color: selected ? null : AppColors.bg2,
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: selected ? AppColors.onPrimary : AppColors.inkSoft)),
      ),
    );
  }
}
