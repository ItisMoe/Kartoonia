# Design: "Everything" mode — WCOFlix (WatchNixtoons2) catalog + original/Arabic audio switch

Date: 2026-07-05
Status: Approved (owner delegated approval; brainstormed autonomously)

## 1. Goal

Kartoonia today plays only Arabic‑dubbed cartoons (Arabic Toons + Stardima, two bundled
catalogs merged in memory). We are adding a second, optional universe: the full cartoon /
dubbed‑anime library that the **WatchNixtoons2** Kodi addon exposes, which scrapes
**wcoflix.tv** (formerly wcofun.net / watchcartoononline). Requirements from the owner:

1. Keep an **Arabic‑dubbed‑only mode** as the default (today's behavior, undisturbed).
2. Add an **"Everything" mode** the user can switch on, surfacing the whole WCOFlix library.
3. Keep it **neat**: home/browse show mostly *popular* things; **search reaches the whole
   catalog**. (Owner asked for both curated popular rows **and** full A–Z browse.)
4. Inside a title, let the user pick **Original vs Arabic‑dubbed** audio when both exist
   ("unified audio switch"). Titles with no Arabic dub appear only in Everything mode.
5. **Reliable playback** with **multiple resolutions**, defaulting to **720p** when available.
6. Scope: **cartoons + English/Arabic‑dubbed anime**, popular‑first, mature/ecchi filtered out.
7. Do not break the existing Arabic experience.

## 2. Key research findings (authoritative, verified live 2026-07-05)

Source of truth: the WatchNixtoons2 addon (`christianhaitian/plugin.video.watchnixtoons2`) and
the actively‑maintained **ZenDownloader** (`NobilityDeviant/ZenDownloader`), cross‑checked
against live `wcoflix.tv` HTML.

### 2.1 Domain
`www.wcofun.net` / `.org` now **301 → `https://www.wcoflix.tv`**. Base URL = `https://www.wcoflix.tv`.
The embed host is `https://embed.wcostream.com`. Treat the base URL as **configurable** (these
sites rename often); ship a small ordered fallback list.

### 2.2 Catalogs = live HTML scrapes (NOT a bundled JSON)
Unlike Arabic Toons / Stardima (static JSON), WCOFlix is a live site of tens of thousands of
titles. It must be fetched on demand and cached. Verified live markers:

| Row / list            | URL                        | Scrape target (still present live) |
|-----------------------|----------------------------|------------------------------------|
| Popular & Ongoing     | `/` (homepage)             | `"sidebar-titles"` block → `<a href>…</a>` pairs |
| Latest Releases       | `/last-50-recent-release`  | `recent-release-episodes` anchors (+ thumb) |
| Cartoons (A–Z)        | `/cartoon-list`            | `"ddmcc"` block → `<li><a href>…</a>` |
| Dubbed Anime (A–Z)    | `/dubbed-anime-list`       | same `ddmcc` shape |
| Subbed Anime (A–Z)    | `/subbed-anime-list`       | same (excluded by content scope, see §6) |
| Movies                | `/movie-list`              | `ddmcc`; items are directly playable |
| OVA                   | `/ova-list`                | `ddmcc`; directly playable |
| Genres                | `/search-by-genre`, `/search-by-genre/<g>` | dropdown `ddmcc` |
| Search (series)       | POST `/search` `{catara:q, konuara:'series'}`, Referer `/` | result anchors |
| Search (episodes)     | POST `/search` `{catara:q, konuara:'episodes'}` | result anchors |
| Series → episodes     | GET series page            | `"sidebar_right3"` block anchors; `og:image`=poster; `Info:` `<p>`=plot |

Titles carry **English** names (e.g. `black-torch-episode-1-english-dubbed`). "English Dubbed"
vs "English Subbed" is encoded in the slug/title.

### 2.3 Playback resolution (the crux) — TWO embed types
The episode page contains one player iframe, found by id in order `anime-js-0`, `anime-js-1`,
`cizgi-js-0`. `src` = the embed URL.

**Type A — "getvid" (wcostream), ad‑gated, needs JS:**
`embed.wcostream.com/inc/embed/index.php?file=…&fullhd=1&pid=…&h=…&t=…&embed=neptun`.
`index.php` is an **ad announcement gate** (`<title>Announcement</title>`, a 10s countdown
Close button). `pre-init.js` generates a random `nonce`, runs adblock‑bait detection, POSTs
`/ad-verify` `{nonce,status:'clear'|'blocked',id:pid}`, then redirects to
`video-js.php?<same query>&n=<nonce>`. The real player runs
`$.getJSON("<getvidlink URL>", function(response){ … })` where the response is
`{enc, hd, fhd, server, cdn}`. Playable URL = `server + "/getvid?evid=" + token`:
`enc`→576p, `hd`→**720p**, `fhd`→**1080p** (progressive mp4; served after HEAD 302 redirects).
Required media headers: exact `User-Agent` + `Referer: https://embed.wcostream.com/`.

Replaying the ad‑verify handshake over plain HTTP was **insufficient** (204 from `/ad-verify`,
but `video-js.php` still returned the gate) — the gate is genuinely server‑side/session‑bound.
ZenDownloader, the reference tool, drives a **real headless browser** for exactly this step and
comments *"IDK how to execute the js, so we still have to use selenium."* → We do the same with
a hidden Android **WebView** (see §5.3).

**Type B — "m3u8" (`anime-js-1`), pure HTTP, no ad gate:**
Frame contains `<source src="…index.m3u8">` (or a `getRedirectedUrl("…")` / `"src":"…index.m3u8"`).
That HLS master lists `#EXT-X-STREAM-INF … x576/x720/x1080` variants plus separate
`#EXT-X-MEDIA:TYPE=AUDIO … LANGUAGE="eng"` renditions. libmpv plays HLS + external audio
natively. Preferred path when available (cleaner, no ad gate, true adaptive/720p).

### 2.4 Quality model (from ZenDownloader `Quality.kt`)
`LOW=576p (enc/vsd)`, `MED=720p (hd/vhd)`, `HIGH=1080p (fhd/vfhd)`. Default selection = **720p**,
falling back MED→LOW / MED→HIGH per `Quality.bestQuality`.

## 3. Non‑negotiable constraints

- **Additive & isolated.** The Arabic‑dubbed path (`CatalogService.loadMerged`, `token_service`,
  `stardima_resolver`, existing screens) must keep working untouched. Everything mode is a
  parallel data path gated behind a persisted flag defaulting **off**.
- Reuse existing seams: `ContentItem`/`Show`/`Movie`, `CatalogSource` enum, and
  `resolvePlayback(source, url)` (`playback_resolver.dart`) already branch by source — we add a
  `wcoflix` source and a `wcoflix_resolver.dart` beside `stardima_resolver.dart`.
- Pure parsing functions must be **unit‑testable off‑device** against captured live HTML, exactly
  like `stardima_resolver`'s exposed pure fns (`parseWatchServers`, `bestStreamUrl`, …).

## 4. Architecture overview

```
                 ┌─────────────────────────── mode flag (persisted, default OFF) ───────────┐
                 │                                                                           │
   Arabic mode (today)                                            Everything mode (new)
   CatalogService.loadMerged()  ───────────────►  home/browse/search/detail/player
   (in‑memory JSON, unchanged)                    │
                                                  ├── WcoflixCatalog (live scrape + cache)  §5.1
                                                  │      rows / A–Z browse / search / episodes
                                                  ├── ContentItem adapter (source=wcoflix)  §5.2
                                                  ├── WcoflixResolver                        §5.3
                                                  │      episode → (m3u8 HTTP | getvid WebView)
                                                  │      → List<PlayableServer> w/ quality tags
                                                  └── Unified audio switch (Arabic ↔ original) §5.4
```

## 5. Components

### 5.1 `WcoflixCatalog` service (`lib/services/wcoflix/wcoflix_catalog.dart`)
Live catalog access with a memory + disk cache (TTL ~6–12h; A–Z lists change slowly, "Latest"
short TTL). All network via `http` with browser headers + the base‑URL fallback list.

Pure parser functions (each unit‑tested against captured fixtures in `test/fixtures/wcoflix/`):
- `parseSidebarTitles(html)` → popular/ongoing `[(url,title)]`.
- `parseRecentReleases(html)` → latest `[(url,title,thumb)]`.
- `parseDdmccList(html)` → A–Z catalog `[(url,title)]` (cartoon/dubbed/movie/ova lists, genres).
- `parseSearchResults(html)` → `[(url,title)]`.
- `parseEpisodeList(html)` → `{poster, plot, episodes:[(url,title)]}` from `sidebar_right3`.
- `parseTitleMeta(title)` → `{cleanTitle, isDub, isSub, season?, episode?}` (port of addon
  `getTitleInfo` + "English Dubbed/Subbed" stripping).

Public API (async, cached): `popular()`, `latest()`, `cartoons()`, `dubbedAnime()`, `movies()`,
`ova()`, `genres()`, `byGenre(g)`, `search(q, type)`, `seriesDetail(url)`.

### 5.2 WCOFlix → `ContentItem` adapter (`lib/services/wcoflix/wcoflix_adapter.dart`)
Maps scraped rows to the existing model so all render/search/detail paths stay source‑agnostic:
- Series page URL → `Show`; episode anchors → flattened `Episode` list (each `episodeUrl` = the
  wcoflix page URL used by the resolver). Movies/OVA → `Movie` with `pageUrl`.
- `source = CatalogSource.wcoflix`. `id` = slug. Poster/plot from the series page (`og:image`,
  `Info:`). No TMDB block (like Stardima) — art falls back to scraped thumb; fame/popularity
  ordering falls back to source order (Popular row is already popularity‑ranked upstream).
- These items are created **lazily** (detail time), not held as one giant in‑memory list — the
  catalog is remote. Rows/browse hold lightweight card stubs (title + poster + url).

### 5.3 `WcoflixResolver` (`lib/services/wcoflix/wcoflix_resolver.dart`) + `resolvePlayback` branch
Given an episode/movie page URL, produce `List<PlayableServer>` (existing type), one per
available quality, tagged `576p/720p/1080p`, with the correct CDN headers. Pipeline:

1. GET episode page → pick iframe by id (`anime-js-0` → `anime-js-1` → `cizgi-js-0`). `anime-js-1`
   ⇒ **m3u8 mode**.
2. **m3u8 mode (pure HTTP):** fetch frame → extract `index.m3u8` → parse master → one server per
   `x576/x720/x1080` variant (+ English audio rendition passed to libmpv). `type='hls'`.
   Referer = frame origin.
3. **getvid mode (WebView):** run the headless WebView resolver (§5.5) to obtain
   `server/getvid?evid=<token>` for `enc/hd/fhd`. One `PlayableServer` per returned quality.
   `type='mp4'`, headers `{User-Agent, Referer: https://embed.wcostream.com/}`. Cache the frame's
   getvidlink so re‑resolving other qualities is instant.
4. Order results best‑first but let the **player default to 720p** (see §5.4). Provide a public
   pure `parseHlsMaster(text)` and `parseGetvidJson(json)` for unit tests.

`resolvePlayback` gains:
```dart
case CatalogSource.wcoflix:
  final streams = await resolveWcoflix(pageUrl);        // List<QualityStream>
  return [ for each stream → PlayableServer(number, label:'720p', url, headers) ];
```
The player's server picker doubles as the **resolution picker** (labels are `576p/720p/1080p`).

### 5.4 Player: default 720p + resolution picker
The player already has a server picker and failover. We: (a) sort resolved servers so the
**720p** entry (MED, or best≤720 fallback per `Quality.bestQuality`) is selected first; (b) label
entries by resolution; (c) persist the user's last chosen resolution as a preference
(`prefs['wcoflixQuality']`, default `720p`). Existing stall‑confirmed failover and `alang=ara,ar`
audio handling are unchanged (Arabic audio only applies to Arabic sources; WCOFlix streams pick
English audio).

### 5.5 Headless WebView resolver (Android) — `lib/services/wcoflix/adgate_webview.dart`
A hidden `HeadlessInAppWebView` (package `flutter_inappwebview`) that mirrors ZenDownloader's
selenium step for getvid embeds only:
1. Load the `index.php` embed URL (browser UA).
2. Wait for `#announcement` / `#close-btn`; inject `HIDE_AD` JS (redirects to `video-js.php`).
3. In the video‑js page, read the frame source, find `$.getJSON("<getvidlink>"`; inject the
   `changeUrlToVideoFunction` JS that fetches getvidlink and posts back
   `{enc,hd,fhd,server}` via a JS handler channel.
4. Return the quality→url map; tear down the WebView.
Timeout‑guarded (~20s), single reused instance, off the video render path. This is the one
piece that **requires on‑device/emulator verification** and is therefore isolated behind a
narrow interface (`Future<Map<Quality,String>> resolveGetvid(String embedUrl)`) so the rest of
the resolver is testable without it.

### 5.6 UI integration
- **Mode toggle:** Settings switch "Show everything (beta)" + a header/browse affordance to flip
  it; persisted in `StorageService` (`everythingMode`, default false). A `modeProvider` in
  `app_state.dart`. When ON, home/browse/search read from `WcoflixCatalog`; when OFF, unchanged.
- **Home (Everything):** rows = Popular & Ongoing, Latest, Cartoons (sample), Dubbed Anime
  (sample), by‑genre rows. "Neat + popular" per §1.3.
- **Browse (Everything):** category tabs (Cartoons / Dubbed Anime / Movies / OVA / Genres) with
  A–Z sections (reuse the existing A–Z browse bar / `ddmcc` letters).
- **Search (Everything):** live POST search across the whole catalog (series + episodes +
  movies), debounced; reuse the existing search UI + voice search.
- **Detail (unified audio switch):** extends today's cross‑source toggle (`alternateFor`). For an
  Arabic title, look up a WCOFlix original by English/original title (cached); for a WCOFlix
  title, look up an Arabic dub. Show an **Audio: [Arabic] [Original]** control; the chosen side
  drives which `source`/URL `resolvePlayback` uses. Fuzzy title match with a confidence gate;
  no match ⇒ no switch shown (title still fully playable in its own source).

## 6. Content scope filtering (cartoons + dubbed anime, mature removed)
- Include: `/cartoon-list`, `/dubbed-anime-list`, `/movie-list`, `/ova-list` (dub‑leaning).
  Exclude `/subbed-anime-list` from browse rows (still reachable by search so "search finds
  anything" holds).
- Drop items whose genre (via `/search-by-genre`) is in a mature blocklist (Ecchi, Hentai,
  Harem, Josei, Seinen‑mature, etc.). Maintain a small blocklist constant.
- Prefer "English Dubbed" entries in curated rows; keep subbed reachable only via search.

## 7. Phasing (each phase = its own plan/PR, independently valuable)

- **Phase 1 — Foundation (off‑device, fully unit‑tested):** `CatalogSource.wcoflix`; all pure
  parsers for catalog (§5.1) and stream sources (`parseHlsMaster`, `parseGetvidJson`, iframe/
  getvidlink extraction) validated against captured live fixtures; `WcoflixCatalog` networking +
  cache; the m3u8 (HTTP) resolver path; `resolvePlayback` wcoflix branch for m3u8; Quality model
  + 720p default. **No UI, no WebView yet** — safe, additive, verifiable now.
- **Phase 2 — getvid WebView resolver (needs device):** `flutter_inappwebview` headless ad‑gate
  resolver (§5.5); wire into the resolver; quality caching. Verify on emulator/device.
- **Phase 3 — Everything‑mode UI:** mode toggle + provider; home/browse/search wired to
  `WcoflixCatalog`; resolution picker labels + persisted preference.
- **Phase 4 — Unified audio switch:** Arabic ↔ original matching + detail control.

## 8. Risks & mitigations
- **Site markup / domain churn:** isolate every scrape in a named pure parser with fixtures;
  configurable base‑URL fallback list; fail soft to Arabic mode.
- **Ad‑gate hardening:** WebView mirrors the reference tool; timeout + m3u8 preference reduce
  reliance on getvid. If WebView fails, that title reports "unavailable" without affecting others.
- **Legal/robustness:** same posture as the existing Stardima/Arabic scrapers already in the app.
- **Performance:** remote catalog is lazy + cached; never merged into the in‑memory library, so
  Arabic‑mode memory/startup is unchanged.

## 9. Out of scope (YAGNI)
Premium `user.wco.tv` login, Trakt, downloads, subbed‑anime browse rows, TMDB enrichment of
WCOFlix items, cross‑device sync of Everything‑mode history beyond existing continue‑watching.
