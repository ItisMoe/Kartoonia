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

/// A fully-loaded WCOFlix show: the series page's poster/plot plus its episodes.
/// The site lists newest-first and mixes dub + sub variants of the same number;
/// we prefer the dubbed variant, dedupe by number, and order ascending.
Show wcoflixShowFromSeries(String pageUrl, WcoSeries series, String title,
    {TmdbData? tmdb}) {
  final byNumber = <int, Episode>{};
  var seq = 0;
  for (final link in series.episodes) {
    final meta = parseTitleMeta(link.title);
    final number = meta.episode ?? ++seq;
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
      seasonNumber: 1,
    );
  }
  final episodes = byNumber.values.toList()
    ..sort((a, b) => a.episodeNumber.compareTo(b.episodeNumber));

  // A movie / one-off page lists no episodes — it is itself directly playable.
  // Model it as a single-episode show so the existing player path works.
  if (episodes.isEmpty) {
    episodes.add(Episode(
      episodeNumber: 1,
      episodeTitle: title,
      episodeUrl: pageUrl,
      servers: const [],
      seasonNumber: 1,
    ));
  }

  final season = Season(
    seasonNumber: 1,
    seasonTitle: '',
    id: '${wcoflixId(pageUrl)}_s1',
    thumbnailUrl: series.poster ?? '',
    pageUrl: pageUrl,
    totalEpisodes: episodes.length,
    episodes: episodes,
  );

  return Show(
    id: wcoflixId(pageUrl),
    title: title,
    thumbnailUrl: series.poster ?? tmdb?.posterUrlW500 ?? '',
    description: series.plot.isNotEmpty ? series.plot : (tmdb?.overviewEn ?? ''),
    tmdb: tmdb,
    totalEpisodes: episodes.length,
    seasonCount: 1,
    seasons: [season],
    episodes: episodes,
    pageUrl: pageUrl,
    source: CatalogSource.wcoflix,
  );
}
