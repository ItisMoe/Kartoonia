/// WCOFlix live-catalog constants. The base URL is an ordered fallback list
/// because these sites rename domains often; callers try each in order until one
/// responds.
///
/// Verified live 2026-07-11: `www.wcoflix.tv` is the current canonical domain —
/// it serves the full catalog and every series page WITH its seasons/episodes,
/// while `www.wcofun.net` now just `301`-redirects to it. wcoflix.tv MUST be
/// first: the domain probe picks the first base that returns real (non-challenge)
/// HTML, and rehomes every series/episode URL onto it — so if a redirecting
/// mirror were first, series pages would arrive as an empty redirect stub with
/// no episodes (which is exactly what made shows collapse to a single episode
/// with no seasons).
///
/// Cloudflare fronts these mirrors with a managed challenge and flips which
/// client fingerprint it trusts over time (plain Dart TLS-1.3 is currently
/// 403-challenged on wcoflix.tv). [WcoflixHttp] tries the native forced-TLS-1.2
/// client AND the plain http stack, using whichever clears — so keep both this
/// list and that dual-transport in sync when the site moves again.
const List<String> wcoflixBaseUrls = [
  'https://www.wcoflix.tv',
  'https://www.wcofun.net',
  'https://www.wcostream.tv',
  'https://www.wcoforever.net',
];

/// The host that serves the getvid player embeds.
const String kWcoflixEmbedHost = 'https://embed.wcostream.com';

/// A stable desktop browser UA. The getvid CDN encodes the UA into its media
/// tokens, so the exact same value must be used to fetch and to play — this one
/// constant feeds BOTH the resolve requests and the playback media headers, so
/// they can never drift apart.
///
/// Pinned to Chrome/149: verified live 2026-07 that the getvid edge (e.g.
/// `e03.wcostream.com/getvid?evid=…`) rejects the older Chrome/147 fingerprint
/// (token mint / playback 403) and serves the stream to Chrome/149. Bump this in
/// lockstep with the real desktop Chrome the site expects if playback ever
/// starts 403-ing again.
const String kWcoflixUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36';

/// Headers the getvid CDN requires on the media request (Phase 2 playback).
const Map<String, String> kWcoflixMediaHeaders = {
  'User-Agent': kWcoflixUserAgent,
  'Referer': '$kWcoflixEmbedHost/',
};
