/// WCOFlix live-catalog constants. The base URL is an ordered fallback list
/// because these sites rename domains often; callers try each in order until one
/// responds. Verified live 2026-07-08: `wcoflix.tv` is now DNS-dead; the working
/// mirror is `www.wcostream.tv` (also the WatchNixtoons2 addon default), with
/// `wcoforever.net` as the live fallback. All mirrors are behind a Cloudflare
/// managed challenge, so requests go through the native TLS-1.2 client
/// (see wcoflix_http.dart / NetChannel).
const List<String> wcoflixBaseUrls = [
  'https://www.wcostream.tv',
  'https://www.wcoforever.net',
  'https://www.wcoflix.tv',
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
