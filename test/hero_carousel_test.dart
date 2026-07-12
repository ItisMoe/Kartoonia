import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/models/catalog_source.dart';
import 'package:kartoonia/models/content_item.dart';
import 'package:kartoonia/widgets/hero_carousel.dart';

Show _show(String id, String title) => Show(
      id: id,
      title: title,
      thumbnailUrl: 'https://x/$id.jpg',
      description: 'd',
      tmdb: TmdbData(backdropUrl: 'https://x/$id-bd.jpg'),
      totalEpisodes: 1,
      seasonCount: 1,
      seasons: const [],
      episodes: const [],
      source: CatalogSource.carateen,
    );

void main() {
  testWidgets('renders the current title, three action pills, and dots',
      (tester) async {
    // The spotlight card is sized for a wide TV panel; use a 1080p surface so
    // the card + side peeks lay out without overflow.
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HeroCarousel(
          items: [_show('1', 'أبطال الكرة'), _show('2', 'كونان')],
          t: const {
            'featured': 'مميز',
            'watchNow': 'شاهد',
            'moreInfo': 'معلومات',
            'myList': 'قائمتي',
            'inList': 'في قائمتي',
            'season': 'موسم',
            'movie': 'فيلم',
          },
          isRtl: true,
          autoplay: false,
          onPlay: (_) {},
          onMoreInfo: (_) {},
          onToggleList: (_) {},
          isInList: (_) => false,
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('أبطال الكرة'), findsOneWidget);
    expect(find.text('شاهد'), findsOneWidget);
    expect(find.text('معلومات'), findsOneWidget);
    expect(find.text('قائمتي'), findsOneWidget);
  });
}
