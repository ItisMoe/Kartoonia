import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/models/catalog_source.dart';
import 'package:kartoonia/models/content_item.dart';
import 'package:kartoonia/services/wcoflix/wcoflix_adapter.dart';
import 'package:kartoonia/services/wcoflix/wcoflix_parsers.dart';

void main() {
  test('wcoflixShowStub cleans title, sets id/pageUrl/source', () {
    final s = wcoflixShowStub(
        const WcoLink('https://www.wcoflix.tv/anime/black-torch', 'Black Torch'));
    expect(s.id, 'black-torch');
    expect(s.title, 'Black Torch');
    expect(s.source, CatalogSource.wcoflix);
    expect(s.pageUrl, 'https://www.wcoflix.tv/anime/black-torch');
    expect(s.episodes, isEmpty);
  });

  test('wcoflixShowFromSeries: dubbed-preferred, deduped, ascending', () {
    const series = WcoSeries('poster.jpg', 'A plot.', [
      WcoLink('u2', 'Black Torch Episode 2 English Dubbed'),
      WcoLink('u1', 'Black Torch Episode 1 English Dubbed'),
      WcoLink('u1s', 'Black Torch Episode 1 English Subbed'),
    ]);
    final show = wcoflixShowFromSeries(
        'https://www.wcoflix.tv/anime/black-torch', series, 'Black Torch');
    expect(show.episodes.length, 2); // ep1 dub kept, ep1 sub dropped
    expect(show.episodes.first.episodeNumber, 1);
    expect(show.episodes.first.episodeUrl, 'u1');
    expect(show.episodes.last.episodeNumber, 2);
    expect(show.thumbnailUrl, 'poster.jpg');
    expect(show.description, 'A plot.');
    expect(show.source, CatalogSource.wcoflix);
  });

  test('wcoflixShowFromSeries: movie/one-off -> single playable episode', () {
    final show = wcoflixShowFromSeries(
        'https://www.wcoflix.tv/anime/some-movie',
        const WcoSeries(null, '', []),
        'Some Movie');
    expect(show.episodes.single.episodeUrl,
        'https://www.wcoflix.tv/anime/some-movie');
    expect(show is Show, isTrue);
  });
}
