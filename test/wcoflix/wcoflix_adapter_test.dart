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

  test('wcoflixShowFromSeries: groups into seasons (data-season + title)', () {
    const series = WcoSeries('poster.jpg', '', [
      WcoLink('s2e2', 'Season 2 Episode 2'),
      WcoLink('s2e1', 'Season 2 Episode 1'),
      WcoLink('s1e2', 'Show', season: 1),
      WcoLink('s1e1', 'Show', season: 1),
    ]);
    final show = wcoflixShowFromSeries(
        'https://www.wcoflix.tv/anime/show', series, 'Show');
    expect(show.seasonCount, 2);
    expect(show.seasons.map((s) => s.seasonNumber), [1, 2]);
    // seasons ascending, episodes ascending within each
    expect(show.seasons[1].episodes.map((e) => e.episodeNumber), [1, 2]);
    expect(show.seasons[1].episodes.first.seasonNumber, 2);
    expect(show.totalEpisodes, 4);
  });

  test('wcoflixCardStub: movie TMDB type -> Movie, else Show', () {
    const movieTmdb = TmdbData(mediaType: 'movie', posterUrlW500: 'p.jpg');
    final movie = wcoflixCardStub(
        const WcoLink('https://www.wcoflix.tv/some-film', 'Some Film'),
        tmdb: movieTmdb);
    expect(movie, isA<Movie>());
    expect((movie as Movie).pageUrl, 'https://www.wcoflix.tv/some-film');
    expect(movie.source, CatalogSource.wcoflix);

    const tvTmdb = TmdbData(mediaType: 'tv');
    final show = wcoflixCardStub(
        const WcoLink('https://www.wcoflix.tv/anime/a-show', 'A Show'),
        tmdb: tvTmdb);
    expect(show, isA<Show>());
  });
}
