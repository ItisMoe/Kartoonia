import 'wcoflix_config.dart';

/// Pure HTML parsers for the WCOFlix (wcoflix.tv) catalog. Each function slices
/// the relevant block by a stable marker (a quoted class attribute) and pulls
/// anchors out — mirroring the WatchNixtoons2 addon, re-verified against live
/// 2026-07-05 markup. Kept pure + exposed so they can be unit-tested against
/// captured HTML fixtures with no network.

/// A catalog anchor: absolute URL + display title (+ optional thumbnail).
class WcoLink {
  final String url;
  final String title;
  final String? thumb;
  const WcoLink(this.url, this.title, {this.thumb});
}

String _abs(String href) {
  if (href.startsWith('http')) return href;
  if (href.startsWith('//')) return 'https:$href';
  return '${wcoflixBaseUrls.first}${href.startsWith('/') ? '' : '/'}$href';
}

String _unescape(String s) => s
    .replaceAll('&amp;', '&')
    .replaceAll('&#038;', '&')
    .replaceAll('&#039;', "'")
    .replaceAll('&#39;', "'")
    .replaceAll('&#8217;', '’')
    .replaceAll('&#8216;', '‘')
    .replaceAll('&#8211;', '–')
    .replaceAll('&#8230;', '…')
    .replaceAll('&quot;', '"');

/// Slice from the first occurrence of [anchor] to the next [end] marker.
String _block(String html, String anchor, String end) {
  final start = html.indexOf(anchor);
  if (start == -1) return '';
  final stop = html.indexOf(end, start);
  return stop == -1 ? html.substring(start) : html.substring(start, stop);
}

// Anchor inner text may wrap a `<span class="film-name">` etc., so capture
// everything up to `</a>` (non-greedy) and strip inner tags afterwards.
final _reAnchor = RegExp(r'<a href="([^"]+)"[^>]*>(.*?)</a>', dotAll: true);
final _reTag = RegExp(r'<[^>]*>');
final _reWs = RegExp(r'\s+');

String _text(String inner) =>
    _unescape(inner.replaceAll(_reTag, ' ').replaceAll(_reWs, ' ').trim());

List<WcoLink> _anchors(String block) => [
      for (final m in _reAnchor.allMatches(block))
        WcoLink(_abs(m.group(1)!), _text(m.group(2)!)),
    ];

/// Homepage "Popular & Ongoing" — the `sidebar-titles` list.
List<WcoLink> parseSidebarTitles(String html) =>
    _anchors(_block(html, 'class="sidebar-titles"', '</ul>'));

/// A–Z catalog / genre result — the `ddmcc` list. Items are `<li><a ...>` in
/// per-letter `<ul>`s, so the whole region runs from `class="ddmcc"` to the
/// trailing `<script>` (the reklam/ad script right after the list). The block
/// opens with A–Z jump links (`href="#A"`); those are skipped.
List<WcoLink> parseDdmccList(String html) {
  final block = _block(html, 'class="ddmcc"', '<script');
  // Some lists (e.g. Dubbed Anime) wrap items as `<li data-id="N"><a …>` with
  // the anchor on the next line, so allow the optional attribute + whitespace.
  final re = RegExp(
      r'<li(?:\s+data-id="[0-9]+")?>\s*<a href="([^"]+)"[^>]*>(.*?)</a>',
      dotAll: true);
  return [
    for (final m in re.allMatches(block))
      if (!m.group(1)!.startsWith('#'))
        WcoLink(_abs(m.group(1)!), _text(m.group(2)!)),
  ];
}

/// POST /search results — anchors between the `submit` and `cizgiyazisi`
/// markers on the results page.
List<WcoLink> parseSearchResults(String html) {
  final start = html.indexOf('submit');
  final end = html.indexOf('cizgiyazisi', start == -1 ? 0 : start);
  final block =
      html.substring(start == -1 ? 0 : start, end == -1 ? html.length : end);
  return _anchors(block);
}

/// "Latest 50" recent releases — each entry carries a thumbnail image.
final _reRecent = RegExp(
  r'<div class="img">\s*<a href="([^"]+)">\s*<img[^>]*src="([^"]+)"[^>]*>\s*</a>\s*</div>\s*<div class="recent-release-episodes"><a href="[^"]*"[^>]*>([^<]+)</a>',
  dotAll: true,
);
List<WcoLink> parseRecentReleases(String html) => [
      for (final m in _reRecent.allMatches(html))
        WcoLink(_abs(m.group(1)!), _unescape(m.group(3)!.trim()),
            thumb: m.group(2)!.startsWith('http')
                ? m.group(2)
                : 'https:${m.group(2)}'),
    ];

/// Series page → poster (og:image), plot (Info: block), and this series'
/// episode anchors.
class WcoSeries {
  final String? poster;
  final String plot;
  final List<WcoLink> episodes;
  const WcoSeries(this.poster, this.plot, this.episodes);
}

/// Parse a `/anime/<slug>` series page. Episodes are flat `<a>` anchors whose
/// path starts with [seriesSlug] and contains `episode` — the current site no
/// longer wraps them in `sidebar_right3` (that block is now the site-wide
/// recent-releases sidebar). Dub and sub variants are both returned.
WcoSeries parseSeriesPage(String html, String seriesSlug) {
  String? poster;
  final og = RegExp(r'og:image"\s+content="([^"]+)"').firstMatch(html);
  if (og != null) poster = og.group(1);

  var plot = '';
  final info = html.indexOf('Info:');
  if (info != -1) {
    final p = RegExp(r'</h3>\s*<p>(.*?)</p>', dotAll: true)
        .firstMatch(html.substring(info));
    if (p != null) plot = _unescape(p.group(1)!.trim());
  }

  final base = '${wcoflixBaseUrls.first}/';
  final seen = <String>{};
  final eps = <WcoLink>[];
  for (final m in _reAnchor.allMatches(html)) {
    final url = _abs(m.group(1)!);
    final path = url.startsWith(base) ? url.substring(base.length) : url;
    if (path.startsWith(seriesSlug) &&
        path.contains('episode') &&
        seen.add(url)) {
      eps.add(WcoLink(url, _unescape(m.group(2)!.trim())));
    }
  }
  return WcoSeries(poster, plot, eps);
}

/// The `<slug>` of a `/anime/<slug>` series URL (or the last path segment).
String seriesSlugFromUrl(String url) {
  final path = Uri.tryParse(url)?.path ?? url;
  final seg = path.replaceFirst(RegExp(r'^/?(anime/)?'), '');
  return seg.replaceAll(RegExp(r'/+$'), '');
}
