import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/models/content_item.dart';
import 'package:kartoonia/utils/screensaver_meta.dart';

const _t = {'movie': 'فيلم', 'seasons': 'مواسم'};

Movie _movie({int? year, List<String> genres = const []}) => Movie(
      id: 'm1',
      title: 'X',
      thumbnailUrl: '',
      description: '',
      pageUrl: '',
      servers: const [],
      tmdb: TmdbData(year: year, genres: genres),
    );

Show _show({int seasonCount = 1, List<String> genres = const []}) => Show(
      id: 's1',
      title: 'X',
      thumbnailUrl: '',
      description: '',
      totalEpisodes: 0,
      seasonCount: seasonCount,
      seasons: const [],
      episodes: const [],
      tmdb: TmdbData(genres: genres),
    );

void main() {
  group('screensaverMeta', () {
    test('movie: year, type, translated genres', () {
      final line = screensaverMeta(
          _movie(year: 2019, genres: ['Action', 'Adventure']), _t);
      expect(line, '2019 · فيلم · أكشن · مغامرات');
    });

    test('show: season count uses the localized seasons word', () {
      final line =
          screensaverMeta(_show(seasonCount: 3, genres: ['Comedy']), _t);
      expect(line, '3 مواسم · كوميديا');
    });

    test('omits a missing year', () {
      expect(screensaverMeta(_movie(genres: ['Action']), _t), 'فيلم · أكشن');
    });

    test('never contains a rating-like decimal', () {
      final line = screensaverMeta(_movie(year: 2020, genres: ['Drama']), _t);
      expect(line.contains('.'), isFalse);
    });
  });
}
