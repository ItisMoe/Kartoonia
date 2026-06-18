import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/content_item.dart';
import '../../playback.dart';
import '../../services/storage_service.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';
import '../../utils/daily_shuffle.dart';
import '../../utils/genre_translations.dart';
import '../../widgets/catalog_image.dart';
import '../../widgets/kartoonia_brand.dart';
import '../../widgets/phone/phone_hero.dart';
import '../../widgets/phone/phone_poster_card.dart';
import '../../widgets/phone/phone_row.dart';
import 'phone_nav.dart';

/// Netflix-style portrait home feed: a featured hero followed by horizontal
/// rails, all drawn from the same catalog pools as the TV home.
class PhoneHomeScreen extends ConsumerStatefulWidget {
  const PhoneHomeScreen({super.key});
  @override
  ConsumerState<PhoneHomeScreen> createState() => _PhoneHomeScreenState();
}

class _PhoneHomeScreenState extends ConsumerState<PhoneHomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => ref.read(userProvider.notifier).refresh());
  }

  String _genreLine(ContentItem s) =>
      s.genres.take(2).map(translateGenre).join(' · ');

  @override
  Widget build(BuildContext context) {
    ref.watch(catalogRevProvider);
    final catalog = ref.watch(catalogProvider);
    final t = ref.watch(stringsProvider);
    final user = ref.watch(userProvider);

    void open(ContentItem i) => openPhoneDetail(context, i);
    final movieLabel = t['movie']!;

    PhonePosterCard card(ContentItem i) =>
        PhonePosterCard(item: i, movieLabel: movieLabel, onPressed: () => open(i));

    final rows = <Widget>[];

    // Keep Watching
    // Entries are most-recent first, so the first occurrence of a cross-source
    // group wins; the rest of the group is dropped so a title watched on either
    // source surfaces as one card.
    final continueItems = <(ContentItem, ProgressEntry)>[];
    final seenGroups = <String>{};
    for (final e in user.continueWatching) {
      final item = catalog.getById(e.itemId);
      if (item == null) continue;
      if (!seenGroups.add(catalog.primaryFor(item).id)) continue;
      continueItems.add((item, e));
    }
    if (continueItems.isNotEmpty) {
      rows.add(PhoneRow(
        title: t['row_continue']!,
        cards: [
          for (final (item, e) in continueItems)
            PhonePosterCard(
              item: item,
              movieLabel: movieLabel,
              progress: e.fraction,
              caption: item is Movie ? movieLabel : '${t['epShort']}${e.episodeNumber}',
              onPressed: () => playItem(context, ref, item),
            ),
        ],
      ));
    }

    final mostPopular =
        dailyShuffled(catalog.popularPool().take(80).toList(), salt: 'most')
            .take(30)
            .toList();
    rows.add(PhoneRow(
        title: t['most_popular']!, cards: [for (final i in mostPopular) card(i)]));

    final popular =
        dailyShuffled(catalog.popularPool().take(60).toList(), salt: 'popular')
            .take(20)
            .toList();
    rows.add(PhoneRow(
        title: t['row_popular']!, cards: [for (final i in popular) card(i)]));

    // Top 10 — ranked numerals beside the poster.
    final top10 =
        dailyShuffled(catalog.getTop10Pool().take(40).toList(), salt: 'top10')
            .take(10)
            .toList();
    rows.add(PhoneRow(
      title: t['topten']!,
      top10Badge: true,
      height: 178,
      cards: [
        for (int i = 0; i < top10.length; i++)
          _PhoneTop10Card(
              item: top10[i], rank: i + 1, onTap: () => open(top10[i])),
      ],
    ));

    final spotlight =
        dailyShuffled(catalog.popularMovies().take(30).toList(), salt: 'spotlight')
            .take(14)
            .toList();
    rows.add(PhoneRow(
        title: t['spotlight']!, cards: [for (final m in spotlight) card(m)]));

    final newShows =
        dailyShuffled(catalog.popularShows().take(40).toList(), salt: 'new')
            .take(20)
            .toList();
    rows.add(
        PhoneRow(title: t['row_new']!, cards: [for (final s in newShows) card(s)]));

    for (final entry in catalog.genreRows()) {
      final byPop = entry.value.toList()
        ..sort((a, b) => b.fameScore.compareTo(a.fameScore));
      rows.add(PhoneRow(
        title: translateGenre(entry.key),
        cards: [
          for (final i
              in dailyShuffled(byPop.take(24).toList(), salt: entry.key).take(20))
            card(i),
        ],
      ));
    }

    final featured =
        dailyShuffled(catalog.getFeaturedPool().take(20).toList(), salt: 'hero')
            .take(5)
            .toList();
    final hero = featured.isNotEmpty ? featured.first : null;

    return Stack(children: [
      ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (hero != null)
            PhoneHero(
              item: hero,
              genreLine: _genreLine(hero),
              inList: user.watchlistIds.contains(hero.id),
              playLabel: t['play']!,
              myListLabel: t['myList']!,
              infoLabel: t['moreInfo']!,
              onPlay: () => playItem(context, ref, hero),
              onInfo: () => open(hero),
              onToggleList: () => ref.read(userProvider.notifier).toggle(hero.id),
            )
          else
            const SizedBox(height: 80),
          const SizedBox(height: 16),
          ...rows,
        ],
      ),
      // Floating top bar over the hero: brand + settings gear.
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: _HomeTopBar(t: t),
      ),
    ]);
  }
}

class _HomeTopBar extends StatelessWidget {
  final Map<String, String> t;
  const _HomeTopBar({required this.t});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
        child: Row(children: [
          KartooniaBrand(brandA: t['brandA']!, brandB: t['brandB']!, scale: 0.62),
          const Spacer(),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => openPhoneSettings(context),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.35),
              ),
              child: const Icon(Icons.settings, size: 22, color: AppColors.ink),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Ranked Top-10 card: a large outlined numeral overlapping a poster.
class _PhoneTop10Card extends StatelessWidget {
  final ContentItem item;
  final int rank;
  final VoidCallback onTap;
  const _PhoneTop10Card(
      {required this.item, required this.rank, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Transform.translate(
            offset: const Offset(16, 0),
            child: Text('$rank',
                style: TextStyle(
                  fontFamily: Fonts.display,
                  fontWeight: FontWeight.w700,
                  fontSize: 132,
                  height: 0.72,
                  foreground: Paint()
                    ..style = PaintingStyle.stroke
                    ..strokeWidth = 3
                    ..color = const Color(0xA6ADB8E0),
                )),
          ),
          SizedBox(
            width: 110,
            height: 165,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: CatalogImage(
                  url: item.posterUrl, fallbackUrl: item.thumbnailUrl),
            ),
          ),
        ],
      ),
    );
  }
}
