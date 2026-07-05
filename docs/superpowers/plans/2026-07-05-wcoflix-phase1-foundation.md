# WCOFlix Everything Mode — Phase 1 (Foundation) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the safe, additive, fully unit‑tested foundation for a WCOFlix (wcoflix.tv) "Everything" catalog: the `wcoflix` catalog source, all pure HTML/stream parsers, the live catalog service with caching, the ContentItem adapter, and the pure‑HTTP (HLS/m3u8) playback path with a 720p‑default quality model. No UI and no WebView in this phase — those are Phases 2–4.

**Architecture:** Mirror the existing Stardima seam. WCOFlix items normalize into the same `ContentItem`/`Show`/`Movie` model and carry `source = CatalogSource.wcoflix`; `resolvePlayback(source, url)` gains a wcoflix branch. Catalog data is scraped live from wcoflix.tv (not bundled) and cached; every parse step is an exposed pure function tested against captured live‑HTML fixtures. Playback resolves an episode page to per‑resolution `PlayableServer`s; Phase 1 implements the m3u8/HLS path (pure HTTP), leaving the ad‑gated getvid path as a stub interface for Phase 2.

**Tech Stack:** Dart / Flutter, `http` ^1.2.2, `flutter_test`, `media_kit` (libmpv) for playback (already integrated). Riverpod for state (later phases).

## Global Constraints

- Base URL: `https://www.wcoflix.tv`; embed host `https://embed.wcostream.com`. Base URL MUST be a configurable ordered fallback list (sites rename often).
- Browser `User-Agent`: `Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36`.
- getvid media headers (Phase 2 playback, but define the constant now): `{ 'User-Agent': <UA>, 'Referer': 'https://embed.wcostream.com/' }`.
- Quality tags/resolutions: `576p` (enc/vsd), `720p` (hd/vhd, DEFAULT), `1080p` (fhd/vfhd).
- Additive only: do NOT modify `CatalogService.loadMerged`, `token_service.dart`, `stardima_resolver.dart`, or any screen. The Arabic path stays byte‑for‑byte behaviorally identical.
- Every pure parser is exposed (public top‑level fn) and unit‑tested against a fixture in `test/fixtures/wcoflix/`.
- Follow the existing style of `lib/services/stardima_resolver.dart` (doc comments explaining the scrape, exposed pure fns, a private `http.Client`).

---

### Task 1: `CatalogSource.wcoflix` + config

**Files:**
- Modify: `lib/models/catalog_source.dart`
- Create: `lib/services/wcoflix/wcoflix_config.dart`
- Test: `test/wcoflix/wcoflix_config_test.dart`

**Interfaces:**
- Produces: `CatalogSource.wcoflix` (enum value, `id:'wcoflix'`, `assetPath:''` — no bundled asset); `wcoflixBaseUrls` (`List<String>`), `kWcoflixEmbedHost` (`'https://embed.wcostream.com'`), `kWcoflixUserAgent` (`String`), `kWcoflixMediaHeaders` (`Map<String,String>`).

- [ ] **Step 1: Write the failing test**

```dart
// test/wcoflix/wcoflix_config_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/models/catalog_source.dart';
import 'package:kartoonia/services/wcoflix/wcoflix_config.dart';

void main() {
  test('wcoflix source exists and is not asset-backed', () {
    expect(CatalogSource.wcoflix.id, 'wcoflix');
    expect(CatalogSource.wcoflix.assetPath, isEmpty);
    expect(CatalogSource.fromId('wcoflix'), CatalogSource.wcoflix);
  });
  test('config constants', () {
    expect(wcoflixBaseUrls.first, 'https://www.wcoflix.tv');
    expect(kWcoflixEmbedHost, 'https://embed.wcostream.com');
    expect(kWcoflixMediaHeaders['Referer'], 'https://embed.wcostream.com/');
  });
}
```

(Note: replace `kartoonia` with the real package name from `pubspec.yaml` `name:` if different — check it first.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/wcoflix/wcoflix_config_test.dart`
Expected: FAIL — `wcoflix` not defined / file missing.

- [ ] **Step 3: Implement**

In `lib/models/catalog_source.dart`, add a third enum value (keep `arabicToons` the `fromId` fallback):

```dart
  stardima(
    id: 'stardima',
    assetPath: 'assets/stardima_catalog.json',
  ),
  wcoflix(
    id: 'wcoflix',
    assetPath: '', // live-scraped, not a bundled asset
  );
```

Create `lib/services/wcoflix/wcoflix_config.dart`:

```dart
/// WCOFlix (wcoflix.tv) live-catalog constants. The base URL is an ordered
/// fallback list because these sites rename domains often; callers try each in
/// order until one responds.
const List<String> wcoflixBaseUrls = [
  'https://www.wcoflix.tv',
  'https://www.wcofun.net',
  'https://www.wcofun.org',
];

const String kWcoflixEmbedHost = 'https://embed.wcostream.com';

const String kWcoflixUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

/// Headers the getvid CDN requires on the media request (Phase 2 playback).
const Map<String, String> kWcoflixMediaHeaders = {
  'User-Agent': kWcoflixUserAgent,
  'Referer': '$kWcoflixEmbedHost/',
};
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/wcoflix/wcoflix_config_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/models/catalog_source.dart lib/services/wcoflix/wcoflix_config.dart test/wcoflix/wcoflix_config_test.dart
git commit -m "feat(wcoflix): add wcoflix catalog source + config constants"
```

---

### Task 2: Title/quality model + `parseTitleMeta`

**Files:**
- Create: `lib/services/wcoflix/wcoflix_quality.dart`
- Create: `lib/services/wcoflix/wcoflix_titles.dart`
- Test: `test/wcoflix/wcoflix_titles_test.dart`

**Interfaces:**
- Produces:
  - `enum WcoQuality { p576, p720, p1080 }` with `int get resolution`, `String get tag` (`'576p'|'720p'|'1080p'`), `String get token` (`'enc'|'hd'|'fhd'`), and `static WcoQuality best(WcoQuality want, List<WcoQuality> have)` (720p‑default fallback per ZenDownloader `Quality.bestQuality`).
  - `TitleMeta parseTitleMeta(String rawTitle)` → `TitleMeta{ String cleanTitle; bool isDub; bool isSub; int? season; int? episode; }`.

- [ ] **Step 1: Write the failing test**

```dart
// test/wcoflix/wcoflix_titles_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/services/wcoflix/wcoflix_quality.dart';
import 'package:kartoonia/services/wcoflix/wcoflix_titles.dart';

void main() {
  group('WcoQuality.best (default 720p)', () {
    test('want 720 present -> 720', () {
      expect(WcoQuality.best(WcoQuality.p720,
          [WcoQuality.p576, WcoQuality.p720, WcoQuality.p1080]), WcoQuality.p720);
    });
    test('want 720 absent, has 1080 -> 1080', () {
      expect(WcoQuality.best(WcoQuality.p720, [WcoQuality.p576, WcoQuality.p1080]),
          WcoQuality.p1080);
    });
    test('want 720, only 576 -> 576', () {
      expect(WcoQuality.best(WcoQuality.p720, [WcoQuality.p576]), WcoQuality.p576);
    });
    test('tags and tokens', () {
      expect(WcoQuality.p720.tag, '720p');
      expect(WcoQuality.p1080.token, 'fhd');
      expect(WcoQuality.p576.resolution, 576);
    });
  });

  group('parseTitleMeta', () {
    test('dubbed episode', () {
      final m = parseTitleMeta('Black Torch Episode 1 English Dubbed');
      expect(m.cleanTitle, 'Black Torch');
      expect(m.isDub, isTrue);
      expect(m.episode, 1);
    });
    test('subbed flagged', () {
      final m = parseTitleMeta('Detective Conan Episode 900 English Subbed');
      expect(m.isSub, isTrue);
      expect(m.isDub, isFalse);
    });
    test('season + episode', () {
      final m = parseTitleMeta(
          'Ascendance of a Bookworm Season 4 Episode 10 English Dubbed');
      expect(m.cleanTitle, 'Ascendance of a Bookworm');
      expect(m.season, 4);
      expect(m.episode, 10);
    });
    test('movie (no episode)', () {
      final m = parseTitleMeta('Animal Farm 2025');
      expect(m.episode, isNull);
      expect(m.cleanTitle, 'Animal Farm 2025');
    });
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/wcoflix/wcoflix_titles_test.dart`
Expected: FAIL — files missing.

- [ ] **Step 3: Implement**

`lib/services/wcoflix/wcoflix_quality.dart`:

```dart
/// WCOFlix stream qualities. `token` is the JSON key in the getvidlink response
/// (`enc`=576p, `hd`=720p, `fhd`=1080p); stream URL = `server/getvid?evid=<token value>`.
enum WcoQuality {
  p576(576, '576p', 'enc'),
  p720(720, '720p', 'hd'),
  p1080(1080, '1080p', 'fhd');

  const WcoQuality(this.resolution, this.tag, this.token);
  final int resolution;
  final String tag;
  final String token;

  /// 720p-default selection with graceful fallback (ports ZenDownloader
  /// `Quality.bestQuality`): prefer the wanted tier, else step toward it.
  static WcoQuality best(WcoQuality want, List<WcoQuality> have) {
    if (have.isEmpty) return p576;
    if (have.contains(want)) return want;
    switch (want) {
      case p1080:
        return have.contains(p720) ? p720 : p576;
      case p720:
        return have.contains(p1080) ? p1080 : p576;
      case p576:
        return have.contains(p720) ? p720 : p1080;
    }
  }
}
```

`lib/services/wcoflix/wcoflix_titles.dart`:

```dart
/// Parsed WCOFlix item title: the show/movie name with the site's
/// "English Dubbed/Subbed" + "Season N Episode M" suffixes stripped, plus the
/// flags/numbers recovered from them. Ports the addon `getTitleInfo`.
class TitleMeta {
  final String cleanTitle;
  final bool isDub;
  final bool isSub;
  final int? season;
  final int? episode;
  const TitleMeta({
    required this.cleanTitle,
    required this.isDub,
    required this.isSub,
    this.season,
    this.episode,
  });
}

final _reEpisode = RegExp(r'\bEpisode\s+(\d+)', caseSensitive: false);
final _reSeason = RegExp(r'\bSeason\s+(\d+)', caseSensitive: false);

TitleMeta parseTitleMeta(String rawTitle) {
  final t = rawTitle.trim();
  final isDub = t.toLowerCase().contains('english dubbed');
  final isSub = t.toLowerCase().contains('english subbed');
  final season = int.tryParse(_reSeason.firstMatch(t)?.group(1) ?? '');
  final episode = int.tryParse(_reEpisode.firstMatch(t)?.group(1) ?? '');

  // Clean title = everything before "Season"/"Episode", with the dub/sub suffix
  // removed. If neither marker is present it's a movie-style title, kept as-is.
  var clean = t;
  final cut = [
    _reSeason.firstMatch(t)?.start,
    _reEpisode.firstMatch(t)?.start,
  ].whereType<int>().fold<int?>(null, (a, b) => a == null ? b : (b < a ? b : a));
  if (cut != null) clean = t.substring(0, cut);
  clean = clean
      .replaceAll(RegExp(r'English (Dubbed|Subbed)', caseSensitive: false), '')
      .trim()
      .replaceAll(RegExp(r'[\s\-–:]+$'), '')
      .trim();

  return TitleMeta(
    cleanTitle: clean.isEmpty ? t : clean,
    isDub: isDub,
    isSub: isSub,
    season: season,
    episode: episode,
  );
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/wcoflix/wcoflix_titles_test.dart`
Expected: PASS. (If `parseTitleMeta('Animal Farm 2025')` trims wrongly, adjust the trailing‑punctuation regex — the test is the spec.)

- [ ] **Step 5: Commit**

```bash
git add lib/services/wcoflix/wcoflix_quality.dart lib/services/wcoflix/wcoflix_titles.dart test/wcoflix/wcoflix_titles_test.dart
git commit -m "feat(wcoflix): quality model (720p default) + title parser"
```

---

### Task 3: Capture live-HTML fixtures

**Files:**
- Create: `test/fixtures/wcoflix/home.html`, `cartoon_list.html`, `series.html`, `search.html`, `hls_master.m3u8`, `getvidlink.json`

**Interfaces:**
- Produces: fixture files consumed by Tasks 4 and 6 tests.

- [ ] **Step 1: Capture fixtures**

Use the captured samples already in the session scratchpad (`home.html`, `clist.html`) and fetch a series page + a search result. To keep fixtures small and stable, trim each to the relevant block plus a little surrounding context (the parsers slice by the quoted class anchor, so keep that anchor intact). Commands (bash):

```bash
UA='Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
mkdir -p test/fixtures/wcoflix
curl -s -A "$UA" -L 'https://www.wcoflix.tv/' -o test/fixtures/wcoflix/home.html
curl -s -A "$UA" -L 'https://www.wcoflix.tv/cartoon-list' -o test/fixtures/wcoflix/cartoon_list.html
# a series page (pick any series slug, e.g. from cartoon_list); example:
curl -s -A "$UA" -L 'https://www.wcoflix.tv/anime/black-torch' -o test/fixtures/wcoflix/series.html
curl -s -A "$UA" -L --data 'catara=conan&konuara=series' -e 'https://www.wcoflix.tv/' 'https://www.wcoflix.tv/search' -o test/fixtures/wcoflix/search.html
```

For `hls_master.m3u8` and `getvidlink.json`, hand‑author minimal but realistic fixtures (the resolver parsers are tested against these; live capture needs the ad‑gate, deferred to Phase 2):

`test/fixtures/wcoflix/hls_master.m3u8`:
```
#EXTM3U
#EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID="aud",LANGUAGE="eng",NAME="English",DEFAULT=YES,URI="eng/audio.m3u8"
#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=1024x576,AUDIO="aud"
576/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=1500000,RESOLUTION=1280x720,AUDIO="aud"
720/index.m3u8
#EXT-X-STREAM-INF:BANDWIDTH=3000000,RESOLUTION=1920x1080,AUDIO="aud"
1080/index.m3u8
```

`test/fixtures/wcoflix/getvidlink.json`:
```json
{"server":"https://cizgy.wcostream.com","enc":"ENC576","hd":"HD720","fhd":"FHD1080","cdn":"https://cdn.wcostream.com"}
```

- [ ] **Step 2: Verify anchors present**

Run:
```bash
grep -c 'class="sidebar-titles"' test/fixtures/wcoflix/home.html
grep -c 'class="ddmcc"' test/fixtures/wcoflix/cartoon_list.html
grep -c 'sidebar_right3' test/fixtures/wcoflix/series.html
```
Expected: each ≥ 1. If the series fixture lacks `sidebar_right3`, pick a real series slug that resolves (a title page, not an episode page).

- [ ] **Step 3: Commit**

```bash
git add test/fixtures/wcoflix
git commit -m "test(wcoflix): capture live-HTML + stream fixtures"
```

---

### Task 4: Catalog HTML parsers

**Files:**
- Create: `lib/services/wcoflix/wcoflix_parsers.dart`
- Test: `test/wcoflix/wcoflix_parsers_test.dart`

**Interfaces:**
- Consumes: fixtures from Task 3.
- Produces (all pure):
  - `class WcoLink { final String url; final String title; final String? thumb; }`
  - `List<WcoLink> parseSidebarTitles(String html)` — homepage Popular & Ongoing.
  - `List<WcoLink> parseRecentReleases(String html)` — Latest (with thumb).
  - `List<WcoLink> parseDdmccList(String html)` — A–Z lists / genre results.
  - `List<WcoLink> parseSearchResults(String html)` — POST /search result page.
  - `class WcoSeries { final String? poster; final String plot; final List<WcoLink> episodes; }`
  - `WcoSeries parseSeriesPage(String html)` — episode list from `sidebar_right3`.

- [ ] **Step 1: Write failing tests**

```dart
// test/wcoflix/wcoflix_parsers_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/services/wcoflix/wcoflix_parsers.dart';

String fx(String n) => File('test/fixtures/wcoflix/$n').readAsStringSync();

void main() {
  test('parseSidebarTitles finds popular links', () {
    final list = parseSidebarTitles(fx('home.html'));
    expect(list, isNotEmpty);
    expect(list.first.url, startsWith('http'));
    expect(list.first.title, isNotEmpty);
  });
  test('parseDdmccList finds many A-Z series links', () {
    final list = parseDdmccList(fx('cartoon_list.html'));
    expect(list.length, greaterThan(50));
    expect(list.every((e) => e.url.contains('wcoflix') || e.url.startsWith('/')), isTrue);
  });
  test('parseSeriesPage returns episodes + meta', () {
    final s = parseSeriesPage(fx('series.html'));
    expect(s.episodes, isNotEmpty);
    expect(s.episodes.first.url, isNotEmpty);
  });
  test('parseSearchResults finds results', () {
    final list = parseSearchResults(fx('search.html'));
    expect(list, isNotEmpty);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/wcoflix/wcoflix_parsers_test.dart`
Expected: FAIL — file missing.

- [ ] **Step 3: Implement** (ports the addon regexes; slice by the quoted class anchor, then match anchors)

```dart
import 'wcoflix_config.dart';

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
    .replaceAll('&#8217;', '’')
    .replaceAll('&#8211;', '–')
    .replaceAll('&quot;', '"');

/// Slice from the first occurrence of a quoted class anchor to the next [end].
String _block(String html, String anchor, String end) {
  final start = html.indexOf(anchor);
  if (start == -1) return '';
  final stop = html.indexOf(end, start);
  return stop == -1 ? html.substring(start) : html.substring(start, stop);
}

final _reAnchor = RegExp(r'<a href="([^"]+)"[^>]*>([^<]+)</a>');

List<WcoLink> _anchors(String block) => [
      for (final m in _reAnchor.allMatches(block))
        WcoLink(_abs(m.group(1)!), _unescape(m.group(2)!.trim())),
    ];

/// Homepage "Popular & Ongoing" — the `sidebar-titles` list.
List<WcoLink> parseSidebarTitles(String html) =>
    _anchors(_block(html, 'class="sidebar-titles"', '</ul>'));

/// A–Z catalog / genre result — the `ddmcc` list. Anchors here are `<li><a ...>`.
List<WcoLink> parseDdmccList(String html) {
  final block = _block(html, 'class="ddmcc"', '</div>');
  final re = RegExp(r'<li><a href="([^"]+)"[^>]*>([^<]+)</a>');
  return [
    for (final m in re.allMatches(block))
      WcoLink(_abs(m.group(1)!), _unescape(m.group(2)!.trim())),
  ];
}

/// POST /search results — anchors between `submit` and `cizgiyazisi` markers.
List<WcoLink> parseSearchResults(String html) {
  final start = html.indexOf('submit');
  final end = html.indexOf('cizgiyazisi', start == -1 ? 0 : start);
  final block = html.substring(
      start == -1 ? 0 : start, end == -1 ? html.length : end);
  return _anchors(block);
}

/// "Latest 50" recent releases — each has a thumbnail image.
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

/// Series page → poster (og:image), plot (Info: block), and episode anchors
/// (the `sidebar_right3` block, up to `sidebar-all`).
class WcoSeries {
  final String? poster;
  final String plot;
  final List<WcoLink> episodes;
  const WcoSeries(this.poster, this.plot, this.episodes);
}

WcoSeries parseSeriesPage(String html) {
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

  final start = html.indexOf('"sidebar_right3"');
  final end = html.indexOf('"sidebar-all"', start == -1 ? 0 : start);
  final block = start == -1
      ? ''
      : html.substring(start, end == -1 ? html.length : end);
  final re = RegExp(r'<a href="([^"]+)[^>]*>([^<]+)');
  final eps = [
    for (final m in re.allMatches(block))
      WcoLink(_abs(m.group(1)!), _unescape(m.group(2)!.trim())),
  ];
  return WcoSeries(poster, plot, eps);
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/wcoflix/wcoflix_parsers_test.dart`
Expected: PASS. If a parser returns empty, open the fixture, find the exact anchor/attribute shape, and adjust that ONE regex; re‑run.

- [ ] **Step 5: Commit**

```bash
git add lib/services/wcoflix/wcoflix_parsers.dart test/wcoflix/wcoflix_parsers_test.dart
git commit -m "feat(wcoflix): pure catalog HTML parsers with live fixtures"
```

---

### Task 5: Stream-source parsers (m3u8 + getvid JSON + iframe pick)

**Files:**
- Create: `lib/services/wcoflix/wcoflix_stream_parsers.dart`
- Test: `test/wcoflix/wcoflix_stream_parsers_test.dart`

**Interfaces:**
- Consumes: `WcoQuality` (Task 2); fixtures `hls_master.m3u8`, `getvidlink.json` (Task 3).
- Produces (pure):
  - `String? pickEmbedIframe(String episodeHtml)` → the frame `src` for id `anime-js-0`/`anime-js-1`/`cizgi-js-0` (first found, in that order); null if none.
  - `bool isM3u8Embed(String episodeHtml)` → true when the chosen frame is `anime-js-1`.
  - `class HlsVariant { final WcoQuality quality; final String url; final String? audioUrl; }`
  - `List<HlsVariant> parseHlsMaster(String masterText, String masterUrl)` → per‑resolution variants (+ English audio URL) resolved absolute.
  - `Map<WcoQuality,String> parseGetvidJson(Map<String,dynamic> json)` → `{quality: 'server/getvid?evid=token'}`.

- [ ] **Step 1: Write failing tests**

```dart
// test/wcoflix/wcoflix_stream_parsers_test.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/services/wcoflix/wcoflix_quality.dart';
import 'package:kartoonia/services/wcoflix/wcoflix_stream_parsers.dart';

String fx(String n) => File('test/fixtures/wcoflix/$n').readAsStringSync();

void main() {
  test('pickEmbedIframe prefers anime-js-0 then cizgi-js-0', () {
    const html = '<iframe id="cizgi-js-0" src="https://embed.wcostream.com/inc/embed/index.php?x=1"></iframe>';
    expect(pickEmbedIframe(html), contains('index.php?x=1'));
    expect(isM3u8Embed(html), isFalse);
  });
  test('isM3u8Embed true for anime-js-1', () {
    const html = '<iframe id="anime-js-1" src="https://h.example/e.m3u8host"></iframe>';
    expect(isM3u8Embed(html), isTrue);
  });
  test('parseHlsMaster returns 576/720/1080 + audio', () {
    final v = parseHlsMaster(fx('hls_master.m3u8'), 'https://h.example/vid/master.m3u8');
    expect(v.map((e) => e.quality).toSet(),
        {WcoQuality.p576, WcoQuality.p720, WcoQuality.p1080});
    final p720 = v.firstWhere((e) => e.quality == WcoQuality.p720);
    expect(p720.url, 'https://h.example/vid/720/index.m3u8');
    expect(p720.audioUrl, 'https://h.example/vid/eng/audio.m3u8');
  });
  test('parseGetvidJson builds getvid urls', () {
    final j = jsonDecode(fx('getvidlink.json')) as Map<String, dynamic>;
    final m = parseGetvidJson(j);
    expect(m[WcoQuality.p720], 'https://cizgy.wcostream.com/getvid?evid=HD720');
    expect(m[WcoQuality.p1080], 'https://cizgy.wcostream.com/getvid?evid=FHD1080');
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/wcoflix/wcoflix_stream_parsers_test.dart`
Expected: FAIL — file missing.

- [ ] **Step 3: Implement**

```dart
import 'wcoflix_quality.dart';

/// The player iframe on an episode page, tried by id in the order ZenDownloader
/// uses. Returns the frame `src`, or null when no known player frame exists.
String? pickEmbedIframe(String episodeHtml) {
  for (final id in ['anime-js-0', 'anime-js-1', 'cizgi-js-0']) {
    final m = RegExp('id="$id"[^>]*\\ssrc="([^"]+)"').firstMatch(episodeHtml) ??
        RegExp('src="([^"]+)"[^>]*\\sid="$id"').firstMatch(episodeHtml);
    if (m != null) return m.group(1);
  }
  return null;
}

/// True when the active frame is `anime-js-1` — the pure-HTTP HLS embed.
bool isM3u8Embed(String episodeHtml) {
  final m3 = RegExp(r'id="anime-js-1"').firstMatch(episodeHtml);
  if (m3 == null) return false;
  // Only treat as m3u8 when anime-js-0 (getvid) is absent — anime-js-0 wins.
  return RegExp(r'id="anime-js-0"').firstMatch(episodeHtml) == null;
}

class HlsVariant {
  final WcoQuality quality;
  final String url;
  final String? audioUrl;
  const HlsVariant(this.quality, this.url, this.audioUrl);
}

String _resolve(String ref, String base) {
  if (ref.startsWith('http')) return ref;
  final root = base.substring(0, base.lastIndexOf('/'));
  return '$root/$ref';
}

/// Parse an HLS master: one [HlsVariant] per `#EXT-X-STREAM-INF` whose
/// RESOLUTION height is 576/720/1080, attaching the English audio rendition URI.
List<HlsVariant> parseHlsMaster(String masterText, String masterUrl) {
  final lines = masterText.split('\n').map((l) => l.trim()).toList();
  String? engAudio;
  for (final l in lines) {
    if (l.startsWith('#EXT-X-MEDIA:TYPE=AUDIO') && l.contains('LANGUAGE="eng')) {
      final u = RegExp(r'URI="([^"]+)"').firstMatch(l)?.group(1);
      if (u != null) engAudio = _resolve(u, masterUrl);
    }
  }
  final out = <HlsVariant>[];
  for (var i = 0; i < lines.length; i++) {
    if (!lines[i].startsWith('#EXT-X-STREAM-INF')) continue;
    for (final q in WcoQuality.values) {
      if (lines[i].contains('x${q.resolution}')) {
        final uri = (i + 1 < lines.length) ? lines[i + 1].trim() : '';
        if (uri.isNotEmpty && !uri.startsWith('#')) {
          out.add(HlsVariant(q, _resolve(uri, masterUrl), engAudio));
        }
      }
    }
  }
  return out;
}

/// Build the per-quality getvid URLs from a getvidlink JSON response.
Map<WcoQuality, String> parseGetvidJson(Map<String, dynamic> json) {
  final server = (json['server'] as String?)?.trimRight() ?? '';
  final out = <WcoQuality, String>{};
  for (final q in WcoQuality.values) {
    final token = json[q.token] as String?;
    if (server.isNotEmpty && token != null && token.isNotEmpty) {
      out[q] = '$server/getvid?evid=$token';
    }
  }
  return out;
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/wcoflix/wcoflix_stream_parsers_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/wcoflix/wcoflix_stream_parsers.dart test/wcoflix/wcoflix_stream_parsers_test.dart
git commit -m "feat(wcoflix): stream-source parsers (iframe pick, HLS master, getvid JSON)"
```

---

### Task 6: `WcoflixCatalog` service (networking + cache)

**Files:**
- Create: `lib/services/wcoflix/wcoflix_catalog.dart`
- Test: `test/wcoflix/wcoflix_catalog_test.dart`

**Interfaces:**
- Consumes: Task 1 config, Task 4 parsers.
- Produces: `class WcoflixCatalog` with an injectable fetcher for tests:
  - constructor `WcoflixCatalog({Future<String> Function(String url, {Map<String,String>? post})? fetch})`.
  - `Future<List<WcoLink>> popular()`, `latest()`, `cartoons()`, `dubbedAnime()`, `movies()`, `ova()`, `genres()`.
  - `Future<List<WcoLink>> byGenre(String slug)`, `Future<List<WcoLink>> search(String q, {String type='series'})`.
  - `Future<WcoSeries> seriesDetail(String url)`.
  - Results cached in‑memory per key with a TTL (default 6h); `latest()` TTL 30m.

- [ ] **Step 1: Write failing test** (inject a fake fetcher returning fixtures — no live network in tests)

```dart
// test/wcoflix/wcoflix_catalog_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/services/wcoflix/wcoflix_catalog.dart';

String fx(String n) => File('test/fixtures/wcoflix/$n').readAsStringSync();

void main() {
  test('popular() parses homepage via injected fetch + caches', () async {
    var calls = 0;
    final cat = WcoflixCatalog(fetch: (url, {post}) async {
      calls++;
      return fx('home.html');
    });
    final a = await cat.popular();
    final b = await cat.popular(); // cache hit
    expect(a, isNotEmpty);
    expect(calls, 1);
    expect(identical(a, b) || a.length == b.length, isTrue);
  });

  test('search posts catara/konuara', () async {
    Map<String, String>? seenPost;
    final cat = WcoflixCatalog(fetch: (url, {post}) async {
      seenPost = post;
      return fx('search.html');
    });
    final r = await cat.search('conan');
    expect(r, isNotEmpty);
    expect(seenPost?['catara'], 'conan');
    expect(seenPost?['konuara'], 'series');
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/wcoflix/wcoflix_catalog_test.dart`
Expected: FAIL — file missing.

- [ ] **Step 3: Implement**

```dart
import 'package:http/http.dart' as http;
import 'wcoflix_config.dart';
import 'wcoflix_parsers.dart';

typedef _Fetch = Future<String> Function(String url, {Map<String, String>? post});

class _Cached {
  final DateTime at;
  final List<WcoLink> data;
  _Cached(this.at, this.data);
}

/// Live WCOFlix catalog access with a simple TTL memory cache. All parsing is
/// delegated to the pure fns in `wcoflix_parsers.dart`; this class only does
/// I/O + caching, so it stays thin and the logic stays testable.
class WcoflixCatalog {
  WcoflixCatalog({_Fetch? fetch}) : _fetch = fetch ?? _defaultFetch;
  final _Fetch _fetch;
  final _cache = <String, _Cached>{};

  static final http.Client _client = http.Client();
  static Future<String> _defaultFetch(String url,
      {Map<String, String>? post}) async {
    final headers = {'User-Agent': kWcoflixUserAgent, 'Referer': '${wcoflixBaseUrls.first}/'};
    final res = post == null
        ? await _client.get(Uri.parse(url), headers: headers)
        : await _client.post(Uri.parse(url), headers: headers, body: post);
    return res.body;
  }

  Future<List<WcoLink>> _listed(String key, String path,
      List<WcoLink> Function(String) parse,
      {Duration ttl = const Duration(hours: 6), Map<String, String>? post}) async {
    final hit = _cache[key];
    if (hit != null && DateTime.now().difference(hit.at) < ttl) return hit.data;
    final url = path.startsWith('http') ? path : '${wcoflixBaseUrls.first}$path';
    final data = parse(await _fetch(url, post: post));
    _cache[key] = _Cached(DateTime.now(), data);
    return data;
  }

  Future<List<WcoLink>> popular() =>
      _listed('popular', '/', parseSidebarTitles);
  Future<List<WcoLink>> latest() => _listed(
      'latest', '/last-50-recent-release', parseRecentReleases,
      ttl: const Duration(minutes: 30));
  Future<List<WcoLink>> cartoons() =>
      _listed('cartoons', '/cartoon-list', parseDdmccList);
  Future<List<WcoLink>> dubbedAnime() =>
      _listed('dubbed', '/dubbed-anime-list', parseDdmccList);
  Future<List<WcoLink>> movies() =>
      _listed('movies', '/movie-list', parseDdmccList);
  Future<List<WcoLink>> ova() => _listed('ova', '/ova-list', parseDdmccList);
  Future<List<WcoLink>> genres() =>
      _listed('genres', '/search-by-genre', parseDdmccList);
  Future<List<WcoLink>> byGenre(String slug) =>
      _listed('genre:$slug', '/search-by-genre/$slug', parseDdmccList);

  Future<List<WcoLink>> search(String q, {String type = 'series'}) => _listed(
        'search:$type:$q',
        '${wcoflixBaseUrls.first}/search',
        parseSearchResults,
        ttl: const Duration(minutes: 10),
        post: {'catara': q, 'konuara': type},
      );

  final _seriesCache = <String, WcoSeries>{};
  Future<WcoSeries> seriesDetail(String url) async {
    final hit = _seriesCache[url];
    if (hit != null) return hit;
    final s = parseSeriesPage(await _fetch(url));
    _seriesCache[url] = s;
    return s;
  }
}
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/wcoflix/wcoflix_catalog_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/wcoflix/wcoflix_catalog.dart test/wcoflix/wcoflix_catalog_test.dart
git commit -m "feat(wcoflix): live catalog service with TTL cache + injectable fetch"
```

---

### Task 7: m3u8 resolver path + `resolvePlayback` branch

**Files:**
- Create: `lib/services/wcoflix/wcoflix_resolver.dart`
- Modify: `lib/services/playback_resolver.dart`
- Test: `test/wcoflix/wcoflix_resolver_test.dart`

**Interfaces:**
- Consumes: Task 2 `WcoQuality`, Task 5 stream parsers, `PlayableServer` (`playback_resolver.dart`).
- Produces:
  - `class WcoStream { final WcoQuality quality; final String url; final String type; final Map<String,String> headers; final String? audioUrl; }`
  - `Future<List<WcoStream>> resolveWcoflixM3u8(String episodeHtml, {required Future<String> Function(String) fetch})` — pure‑HTTP HLS path (Phase 1).
  - `Future<Map<WcoQuality,String>> Function(String embedUrl)? wcoflixGetvidResolver` — a settable hook, null in Phase 1 (Phase 2 injects the WebView resolver).
  - `resolvePlayback` gains `case CatalogSource.wcoflix:` returning `PlayableServer`s ordered so 720p (via `WcoQuality.best`) is `number:1`.

- [ ] **Step 1: Write failing test** (m3u8 path only; getvid hook null)

```dart
// test/wcoflix/wcoflix_resolver_test.dart
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/services/wcoflix/wcoflix_quality.dart';
import 'package:kartoonia/services/wcoflix/wcoflix_resolver.dart';

String fx(String n) => File('test/fixtures/wcoflix/$n').readAsStringSync();

void main() {
  test('m3u8 path yields 720p-first ordered streams', () async {
    const epHtml =
        '<iframe id="anime-js-1" src="https://h.example/frame"></iframe>';
    final streams = await resolveWcoflixM3u8(epHtml, fetch: (url) async {
      if (url.contains('frame')) {
        return '<source src="https://h.example/vid/master.m3u8">';
      }
      return fx('hls_master.m3u8');
    });
    expect(streams, isNotEmpty);
    // best() default is 720p and it must be first.
    expect(streams.first.quality, WcoQuality.p720);
    expect(streams.first.type, 'hls');
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/wcoflix/wcoflix_resolver_test.dart`
Expected: FAIL — file missing.

- [ ] **Step 3: Implement**

`lib/services/wcoflix/wcoflix_resolver.dart`:

```dart
import 'package:http/http.dart' as http;
import 'wcoflix_config.dart';
import 'wcoflix_quality.dart';
import 'wcoflix_stream_parsers.dart';

class WcoStream {
  final WcoQuality quality;
  final String url;
  final String type; // 'hls' | 'mp4'
  final Map<String, String> headers;
  final String? audioUrl;
  const WcoStream(this.quality, this.url, this.type, this.headers, this.audioUrl);
}

/// Phase-2 hook: resolve the ad-gated getvid embed to per-quality URLs via a
/// headless WebView. Null in Phase 1 (m3u8 titles still play).
Future<Map<WcoQuality, String>> Function(String embedUrl)? wcoflixGetvidResolver;

final http.Client _client = http.Client();
Future<String> _get(String url) async {
  final res = await _client.get(Uri.parse(url),
      headers: {'User-Agent': kWcoflixUserAgent});
  return res.body;
}

String _origin(String url) {
  final u = Uri.parse(url);
  return '${u.scheme}://${u.host}/';
}

/// Order resolved qualities so the 720p-default (via [WcoQuality.best]) is first.
List<WcoStream> _order(List<WcoStream> s) {
  if (s.isEmpty) return s;
  final have = s.map((e) => e.quality).toList();
  final want = WcoQuality.best(WcoQuality.p720, have);
  s.sort((a, b) {
    if (a.quality == want) return -1;
    if (b.quality == want) return 1;
    return b.quality.resolution.compareTo(a.quality.resolution);
  });
  return s;
}

/// Pure-HTTP HLS path: episode HTML → anime-js-1 frame → index.m3u8 master →
/// per-resolution HLS streams (720p first). [fetch] is injectable for tests.
Future<List<WcoStream>> resolveWcoflixM3u8(String episodeHtml,
    {Future<String> Function(String)? fetch}) async {
  final get = fetch ?? _get;
  final frame = pickEmbedIframe(episodeHtml);
  if (frame == null) return const [];
  final frameHtml = await get(frame);
  final masterMatch =
      RegExp(r'https?:[^\s"'"'"']+index\.m3u8').firstMatch(frameHtml) ??
          RegExp(r'src="([^"]+index\.m3u8)"').firstMatch(frameHtml);
  if (masterMatch == null) return const [];
  final masterUrl = masterMatch.group(0)!.startsWith('http')
      ? masterMatch.group(0)!
      : masterMatch.group(1)!;
  final masterText = await get(masterUrl);
  final referer = _origin(frame);
  final variants = parseHlsMaster(masterText, masterUrl);
  return _order([
    for (final v in variants)
      WcoStream(v.quality, v.url, 'hls',
          {'User-Agent': kWcoflixUserAgent, 'Referer': referer}, v.audioUrl),
  ]);
}

/// Full episode/movie resolve: HLS if present, else getvid via the Phase-2 hook.
Future<List<WcoStream>> resolveWcoflix(String pageUrl,
    {Future<String> Function(String)? fetch}) async {
  final get = fetch ?? _get;
  final epHtml = await get(pageUrl);
  if (!isM3u8Embed(epHtml)) {
    final frame = pickEmbedIframe(epHtml);
    final hook = wcoflixGetvidResolver;
    if (frame != null && hook != null) {
      final map = await hook(frame);
      final streams = [
        for (final e in map.entries)
          WcoStream(e.key, e.value, 'mp4', kWcoflixMediaHeaders, null),
      ];
      if (streams.isNotEmpty) return _order(streams);
    }
    // Fall through to try HLS anyway (some pages carry both).
  }
  return resolveWcoflixM3u8(epHtml, fetch: get);
}
```

Modify `lib/services/playback_resolver.dart` — add the import and branch:

```dart
import 'wcoflix/wcoflix_resolver.dart';
```
```dart
    case CatalogSource.wcoflix:
      final streams = await resolveWcoflix(pageOrPlayUrl);
      return [
        for (var i = 0; i < streams.length; i++)
          PlayableServer(
            number: i + 1,
            label: streams[i].quality.tag, // '720p' etc. → doubles as the res picker
            url: streams[i].url,
            headers: streams[i].headers,
          ),
      ];
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/wcoflix/wcoflix_resolver_test.dart`
Then the whole suite: `flutter test`
Expected: all PASS (existing tests unaffected — the change is additive).

- [ ] **Step 5: Commit**

```bash
git add lib/services/wcoflix/wcoflix_resolver.dart lib/services/playback_resolver.dart test/wcoflix/wcoflix_resolver_test.dart
git commit -m "feat(wcoflix): m3u8 HLS resolver + resolvePlayback branch (720p default)"
```

---

### Task 8: `flutter analyze` gate

**Files:** none (verification task).

- [ ] **Step 1:** Run `flutter analyze lib/services/wcoflix test/wcoflix`. Expected: no errors. Fix any lints (unused imports, the `PlayableServer.label` now carrying a resolution — that's intended).
- [ ] **Step 2:** Run the full suite `flutter test`. Expected: PASS.
- [ ] **Step 3: Commit** any lint fixes: `git commit -am "chore(wcoflix): analyzer clean"`.

---

## Self-Review

- **Spec coverage (Phase 1 scope):** `CatalogSource.wcoflix` (T1) ✓; catalog scrapers §5.1 (T4) ✓; title/quality model §2.4 (T2) ✓; stream parsers + m3u8 path §5.3 (T5, T7) ✓; live catalog service + cache §5.1 (T6) ✓; `resolvePlayback` branch + 720p default §5.3/5.4 (T7) ✓; fixtures for off‑device verification §3 (T3) ✓. Adapter (§5.2), WebView getvid (§5.5, Phase 2), UI (§5.6, Phase 3), audio switch (§5.4/Phase 4) are intentionally out of Phase 1 — the resolver exposes `wcoflixGetvidResolver` as the Phase‑2 seam.
- **Placeholder scan:** every code step has complete code; no TBD/TODO.
- **Type consistency:** `WcoLink`, `WcoSeries`, `WcoQuality`, `HlsVariant`, `WcoStream`, `resolveWcoflix`/`resolveWcoflixM3u8`, `parseGetvidJson`, `parseHlsMaster` names are used identically across tasks. `PlayableServer` fields (`number`,`label`,`url`,`headers`) match the existing class.
- **Package name:** tests import `package:kartoonia/...` — verify `name:` in `pubspec.yaml` and substitute if different before running.
