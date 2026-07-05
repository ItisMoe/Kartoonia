/// WCOFlix (wcoflix.tv) live-catalog constants. The base URL is an ordered
/// fallback list because these sites rename domains often; callers try each in
/// order until one responds. Verified live 2026-07-05: wcofun.net/.org now
/// 301-redirect to wcoflix.tv.
const List<String> wcoflixBaseUrls = [
  'https://www.wcoflix.tv',
  'https://www.wcofun.net',
  'https://www.wcofun.org',
];

/// The host that serves the getvid player embeds.
const String kWcoflixEmbedHost = 'https://embed.wcostream.com';

/// A stable desktop browser UA. The getvid CDN encodes the UA into its media
/// tokens, so the exact same value must be used to fetch and to play.
const String kWcoflixUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

/// Headers the getvid CDN requires on the media request (Phase 2 playback).
const Map<String, String> kWcoflixMediaHeaders = {
  'User-Agent': kWcoflixUserAgent,
  'Referer': '$kWcoflixEmbedHost/',
};
