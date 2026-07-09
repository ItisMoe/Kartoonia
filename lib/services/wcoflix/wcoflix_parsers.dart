import 'wcoflix_config.dart';

/// Pure HTML parsers for the WCOFlix (wcoflix.tv) catalog. Each function slices
/// the relevant block by a stable marker (a quoted class attribute) and pulls
/// anchors out — mirroring the WatchNixtoons2 addon, re-verified against live
/// 2026-07-05 markup. Kept pure + exposed so they can be unit-tested against
/// captured HTML fixtures with no network.

/// A catalog anchor: absolute URL + display title (+ optional thumbnail).
/// [season] is set only for episode anchors on a series page, where the site
/// exposes the season (via a `data-season="sN-…"` attribute or a "Season N" in
/// the label); null for plain catalog/browse links.
class WcoLink {
  final String url;
  final String title;
  final String? thumb;
  final int? season;
  const WcoLink(this.url, this.title, {this.thumb, this.season});
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

// The two episode-anchor templates the site serves (either, or a mix, on one
// page — verified live 2026-07):
//  A. "dark-episode-item": relative href, a `data-season="sN-…"` attribute and
//     a `<span>Season N Episode M - …</span>` label.
//  B. "cat-eps / sonra": an absolute (often wcoflix.tv) href with the episode
//     name inline or in a `title="Watch …"` attribute; season only in the text.
final _reDarkEpisode = RegExp(
  r'<a\s+href="([^"]+)"\s+class="dark-episode-item"([^>]*)>\s*<span>(.*?)</span>',
  dotAll: true,
);
final _reSonraEpisode = RegExp(
  r'<a\s+href="([^"]+)"[^>]*\bclass="[^"]*\bsonra\b[^"]*"[^>]*>(.*?)</a>',
  dotAll: true,
);
final _reDataSeason = RegExp(r'data-season="s(\d+)');
final _reSeasonWord = RegExp(r'\bSeason\s+(\d+)', caseSensitive: false);

/// Extract the season number from (in priority) a `data-season` attribute, a
/// "Season N" in the label, or a `season-N` / `-sN-` slug in the URL; 1 when the
/// page gives no season at all (a single-season show).
int _episodeSeason(String attrs, String label, String url) {
  final ds = _reDataSeason.firstMatch(attrs)?.group(1);
  if (ds != null) return int.tryParse(ds) ?? 1;
  final st = _reSeasonWord.firstMatch(label)?.group(1);
  if (st != null) return int.tryParse(st) ?? 1;
  final su = RegExp(r'season-(\d+)').firstMatch(url)?.group(1);
  return su != null ? (int.tryParse(su) ?? 1) : 1;
}

/// Parse a `/anime/<slug>` series page → poster, plot, and the ordered episode
/// anchors (each carrying its season). Handles both anchor templates and any
/// mix of them; dub and sub variants are both returned (deduped downstream).
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

  final seen = <String>{};
  final eps = <WcoLink>[];

  // Template A — the richest: explicit season + a clean label.
  for (final m in _reDarkEpisode.allMatches(html)) {
    final url = _abs(m.group(1)!);
    if (!seen.add(url)) continue;
    final attrs = m.group(2) ?? '';
    final label = _text(m.group(3)!);
    eps.add(WcoLink(url, label, season: _episodeSeason(attrs, label, url)));
  }

  // Template B — inline/`title`-attr episode anchors.
  for (final m in _reSonraEpisode.allMatches(html)) {
    final url = _abs(m.group(1)!);
    if (!url.toLowerCase().contains('episode') &&
        !m.group(2)!.toLowerCase().contains('episode')) {
      continue; // a non-episode `.sonra` link (nav/related)
    }
    if (!seen.add(url)) continue;
    final label = _text(m.group(2)!);
    eps.add(WcoLink(url, label, season: _episodeSeason('', label, url)));
  }

  // Fallback for older markup: flat anchors whose slug/text names an episode.
  if (eps.isEmpty) {
    for (final m in _reAnchor.allMatches(html)) {
      final url = _abs(m.group(1)!);
      final label = _text(m.group(2)!);
      final hay = '${url.toLowerCase()} ${label.toLowerCase()}';
      if (hay.contains('episode') &&
          (url.contains(seriesSlug) || label.isNotEmpty) &&
          seen.add(url)) {
        eps.add(WcoLink(url, label, season: _episodeSeason('', label, url)));
      }
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
