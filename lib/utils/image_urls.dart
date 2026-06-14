// Image URL helpers + the CDN Referer header.
//
// TMDB serves a size segment in the path (e.g. /original/); `original` is
// 2000px+ and too heavy for TV — downsize per usage. The arabic-toons
// thumbnail CDN requires a Referer header.

/// Headers required when loading arabic-toons.com catalog images.
const Map<String, String> kImageHeaders = {
  'Referer': 'https://www.arabic-toons.com/',
  'User-Agent':
      'Mozilla/5.0 (Linux; Android 11; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
};

String? tmdbCardPoster(String? url) =>
    url?.replaceFirst('/original/', '/w500/');

String? tmdbHeroBackdrop(String? url) =>
    url?.replaceFirst('/original/', '/w1280/');

/// Only TMDB images are public + sized; arabic-toons images need the Referer.
bool needsReferer(String url) => url.contains('arabic-toons.com');
