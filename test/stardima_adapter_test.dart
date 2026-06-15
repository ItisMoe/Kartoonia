import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/models/catalog_source.dart';
import 'package:kartoonia/models/stardima_adapter.dart';

void main() {
  final sample = {
    'movies': [
      {
        'id': 'mov1',
        'type': 'movie',
        'title': 'فيلم تجريبي',
        'description': 'وصف الفيلم',
        'poster_url': 'https://image.tmdb.org/t/p/w500/poster.jpg',
        'backdrop_url': 'https://image.tmdb.org/t/p/w1280/back.jpg',
        'year': '2011',
        'language': 'مدبلج',
        'category': 'أفلام باربي',
        'detail_url': 'https://www.stardima.com/movie/mov1',
        'play_url': 'https://www.stardima.com/play/mov1',
      },
      {
        'id': 'mov2',
        'type': 'movie',
        'title': 'بدون تصنيف',
        'description': '',
        'poster_url': 'p2',
        'backdrop_url': 'b2',
        'year': '',
        'language': '',
        'category': '', // uncategorised -> no category
        'detail_url': 'd2',
        'play_url': 'https://www.stardima.com/play/mov2',
      },
    ],
    'tvshows': [
      {
        'id': 'show1',
        'type': 'tvshow',
        'title': 'مسلسل',
        'description': 'وصف',
        'poster_url': 'https://image.tmdb.org/t/p/w500/sp.jpg',
        'backdrop_url': 'https://image.tmdb.org/t/p/w1280/sb.jpg',
        'year': '2016',
        'language': 'مدبلج',
        'category': 'كرتون',
        'detail_url': 'https://www.stardima.com/tvshow/show1',
        'seasons': [
          {
            'number': 1,
            'title': 'الموسم الأول',
            'episodes': [
              {
                'number': 2,
                'title': 'Ep Two',
                'play_url': 'https://www.stardima.com/tvshow/show1/play/15626',
              },
              {
                'number': 3,
                'title': 'Ep Three',
                'play_url': 'https://www.stardima.com/tvshow/show1/play/15627',
              },
            ],
          },
          {
            'number': 2,
            'title': 'الموسم الثاني',
            'episodes': [
              {
                'number': 1,
                'title': 'S2 One',
                'play_url': 'https://www.stardima.com/tvshow/show1/play/20001',
              },
            ],
          },
        ],
      },
    ],
  };

  test('parses movies into normalized Movie items', () {
    final (shows, movies) = StardimaAdapter.parse(sample);
    expect(movies.length, 2);

    final m = movies.first;
    expect(m.id, 'mov1');
    expect(m.title, 'فيلم تجريبي');
    expect(m.source, CatalogSource.stardima);
    // play_url is carried on pageUrl for the resolver.
    expect(m.pageUrl, 'https://www.stardima.com/play/mov1');
    expect(m.servers, isEmpty);
    // synthesized art + year + category
    expect(m.posterUrl, 'https://image.tmdb.org/t/p/w500/poster.jpg');
    expect(m.backdropUrl, 'https://image.tmdb.org/t/p/w1280/back.jpg');
    expect(m.year, 2011);
    expect(m.categories, ['أفلام باربي']);

    // blank category -> no category, blank year -> null
    expect(movies[1].categories, isEmpty);
    expect(movies[1].year, isNull);

    expect(shows.length, 1);
  });

  test('parses tvshows with seasons/episodes and play_urls', () {
    final (shows, _) = StardimaAdapter.parse(sample);
    final s = shows.single;
    expect(s.source, CatalogSource.stardima);
    expect(s.seasonCount, 2);
    expect(s.totalEpisodes, 3);
    expect(s.seasons.first.seasonNumber, 1);
    expect(s.seasons.first.episodes.length, 2);

    final ep = s.seasons.first.episodes.first;
    expect(ep.episodeNumber, 2);
    expect(ep.episodeTitle, 'Ep Two');
    // play_url lives on episodeUrl (what the player resolves).
    expect(ep.episodeUrl, 'https://www.stardima.com/tvshow/show1/play/15626');
    expect(ep.servers, isEmpty);

    // flattened episodes span all seasons, season number attached
    expect(s.episodes.length, 3);
    expect(s.episodes.last.seasonNumber, 2);
    expect(s.categories, ['كرتون']);
  });
}
