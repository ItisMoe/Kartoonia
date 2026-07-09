import '../../models/catalog_source.dart';
import '../../models/content_item.dart';
import 'wcoflix_parsers.dart';
import 'wcoflix_titles.dart';

/// Maps scraped WCOFlix data onto the app's normalized [ContentItem] model so
/// the existing rows/cards/detail/player render it unchanged. WCOFlix has no
/// TMDB block (like Stardima) — art falls back to the scraped thumbnail; every
/// item carries `source = CatalogSource.wcoflix`, which drives playback.

/// Stable id for a WCOFlix title = its `/anime/<slug>` (or last path segment).
String wcoflixId(String url) => seriesSlugFromUrl(url);

/// A browse/search/row card for a WCOFlix title. A TMDB-typed **movie** becomes
/// a directly-playable [Movie] (a clean Play button, no fake episode list); an
/// unknown/tv title becomes a [Show] stub whose episodes load lazily on the
/// detail screen (via [wcoflixShowFromSeries]).
ContentItem wcoflixCardStub(WcoLink link, {TmdbData? tmdb}) =>
    tmdb?.mediaType == 'movie'
        ? wcoflixMovieStub(link, tmdb: tmdb)
        : wcoflixShowStub(link, tmdb: tmdb);

/// A WCOFlix movie card: fully populated from the bundled TMDB art (poster,
/// backdrop, plot) so it needs no live fetch. `pageUrl` is the movie's watch
/// page, played directly through the wcoflix resolver.
Movie wcoflixMovieStub(WcoLink link, {TmdbData? tmdb}) {
  final meta = parseTitleMeta(link.title);
  return Movie(
    id: wcoflixId(link.url),
    title: meta.cleanTitle.isEmpty ? link.title : meta.cleanTitle,
    thumbnailUrl: link.thumb ?? tmdb?.posterUrlW500 ?? '',
    description: tmdb?.overviewEn ?? '',
    tmdb: tmdb,
    pageUrl: link.url,
    servers: const [],
    source: CatalogSource.wcoflix,
  );
}

/// A lightweight browse/search/row card: a [Show] with no episodes yet (they are
/// fetched lazily on the detail screen via [wcoflixShowFromSeries]). `pageUrl`
/// carries the series page so detail knows what to load.
Show wcoflixShowStub(WcoLink link, {TmdbData? tmdb}) {
  final meta = parseTitleMeta(link.title);
  return Show(
    id: wcoflixId(link.url),
    title: meta.cleanTitle.isEmpty ? link.title : meta.cleanTitle,
    thumbnailUrl: link.thumb ?? '',
    description: tmdb?.overviewEn ?? '',
    tmdb: tmdb,
    totalEpisodes: 0,
    seasonCount: 1,
    seasons: const [],
    episodes: const [],
    pageUrl: link.url,
    source: CatalogSource.wcoflix,
  );
}

/// A fully-loaded WCOFlix show: the series page's poster/plot plus its episodes,
/// grouped into the seasons the site exposes. The site lists newest-first and
/// mixes dub + sub variants of the same number; per season we prefer the dubbed
/// variant, dedupe by number, and order episodes (and seasons) ascending.
Show wcoflixShowFromSeries(String pageUrl, WcoSeries series, String title,
    {TmdbData? tmdb}) {
  // season -> (episode number -> Episode).
  final bySeason = <int, Map<int, Episode>>{};
  final seq = <int, int>{}; // per-season running counter for un-numbered items
  for (final link in series.episodes) {
    final meta = parseTitleMeta(link.title);
    final seasonNo = link.season ?? meta.season ?? 1;
    final number = meta.episode ?? (seq[seasonNo] = (seq[seasonNo] ?? 0) + 1);
    final byNumber = bySeason.putIfAbsent(seasonNo, () => {});
    final existing = byNumber[number];
    // Keep the first seen unless a dubbed variant supersedes a subbed one.
    if (existing != null) {
      final existingIsDub = existing.episodeTitle.contains('(Dub)');
      if (!(meta.isDub && !existingIsDub)) continue;
    }
    byNumber[number] = Episode(
      episodeNumber: number,
      episodeTitle: meta.episode != null
          ? 'Episode $number${meta.isDub ? ' (Dub)' : meta.isSub ? ' (Sub)' : ''}'
          : (meta.cleanTitle.isEmpty ? title : meta.cleanTitle),
      episodeUrl: link.url, // the wcoflix page URL the resolver plays
      servers: const [],
      seasonNumber: seasonNo,
    );
  }

  final seasonNos = bySeason.keys.toList()..sort();
  final seasons = <Season>[];
  final flat = <Episode>[];
  for (final n in seasonNos) {
    final eps = bySeason[n]!.values.toList()
      ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));
    flat.addAll(eps);
    seasons.add(Season(
      seasonNumber: n,
      seasonTitle: '',
      id: '${wcoflixId(pageUrl)}_s$n',
      thumbnailUrl: series.poster ?? '',
      pageUrl: pageUrl,
      totalEpisodes: eps.length,
      episodes: eps,
    ));
  }

  // A one-off page that lists no episodes — model it as a single-episode show
  // so the existing player path still works (movies are modeled separately as
  // [Movie] via [wcoflixCardStub]; this is the safety net for an odd series).
  if (seasons.isEmpty) {
    final ep = Episode(
      episodeNumber: 1,
      episodeTitle: title,
      episodeUrl: pageUrl,
      servers: const [],
      seasonNumber: 1,
    );
    flat.add(ep);
    seasons.add(Season(
      seasonNumber: 1,
      seasonTitle: '',
      id: '${wcoflixId(pageUrl)}_s1',
      thumbnailUrl: series.poster ?? '',
      pageUrl: pageUrl,
      totalEpisodes: 1,
      episodes: [ep],
    ));
  }

  return Show(
    id: wcoflixId(pageUrl),
    title: title,
    thumbnailUrl: series.poster ?? tmdb?.posterUrlW500 ?? '',
    description: series.plot.isNotEmpty ? series.plot : (tmdb?.overviewEn ?? ''),
    tmdb: tmdb,
    totalEpisodes: flat.length,
    seasonCount: seasons.length,
    seasons: seasons,
    episodes: flat,
    pageUrl: pageUrl,
    source: CatalogSource.wcoflix,
  );
}
