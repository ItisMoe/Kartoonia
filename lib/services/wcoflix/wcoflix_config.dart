/// WCOFlix live-catalog constants. The base URL is an ordered fallback list
/// because these sites rename domains often; callers try each in order until one
/// responds.
///
/// Verified live 2026-07-09: `www.wcofun.net` is the current canonical domain
/// and the ONLY mirror that currently passes Cloudflare's managed challenge —
/// and crucially it passes via the plain Dart HTTP stack, while the OTHER
/// mirrors (wcostream.tv / wcoforever.net / wcoflix.tv) now 403-challenge every
/// client including the forced-TLS-1.2 one. Cloudflare flipped which fingerprint
/// it trusts, so [WcoflixHttp] now tries the native TLS-1.2 client AND falls
/// back to plain http, using whichever clears the challenge (see wcoflix_http.dart).
const List<String> wcoflixBaseUrls = [
  'https://www.wcofun.net',
  'https://www.wcostream.tv',
  'https://www.wcoforever.net',
  'https://www.wcoflix.tv',
];

/// The host that serves the getvid player embeds.
const String kWcoflixEmbedHost = 'https://embed.wcostream.com';

/// A stable desktop browser UA. The getvid CDN encodes the UA into its media
/// tokens, so the exact same value must be used to fetch and to play. Kept in
/// lockstep with the WatchNixtoons2 addon's UA (Chrome/147) — it is the exact
/// fingerprint the addon uses to clear Cloudflare and the ad-gate.
const String kWcoflixUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/147.0.0.0 Safari/537.36';

/// Headers the getvid CDN requires on the media request (Phase 2 playback).
const Map<String, String> kWcoflixMediaHeaders = {
  'User-Agent': kWcoflixUserAgent,
  'Referer': '$kWcoflixEmbedHost/',
};
