import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/models/content_item.dart';
import 'package:kartoonia/utils/youtube_query.dart';

Movie _movie(String title) => Movie(
      id: 'm1',
      title: title,
      thumbnailUrl: '',
      description: '',
      pageUrl: '',
      servers: const [],
    );

Show _show(String title) => Show(
      id: 's1',
      title: title,
      thumbnailUrl: '',
      description: '',
      totalEpisodes: 0,
      seasonCount: 1,
      seasons: const [],
      episodes: const [],
    );

void main() {
  group('youtubeSearchQuery', () {
    test('movie searches for a trailer', () {
      expect(youtubeSearchQuery(_movie('Cars')), 'Cars trailer');
    });

    test('show searches for the arabic theme song', () {
      expect(youtubeSearchQuery(_show('Pokemon')), 'Pokemon arabic theme song');
    });
  });
}
