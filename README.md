# Kartoonia (كرتونيا)

> Arabic cartoons & anime for Android TV / Google TV — a 10‑foot, D‑pad‑first streaming client built in Flutter.

Kartoonia is a leanback (TV) streaming app that aggregates Arabic‑dubbed cartoons and anime from two independent catalog backends — **Arabic Toons** and **Stardima** — behind a single, source‑agnostic UI. It is a from‑scratch Flutter rewrite of an earlier React Native app: the *backend* (catalog parsing, token/stream resolution, storage) was ported with zero feature loss, while the *UI* is a clean implementation of a dedicated design handoff.

The hard problem this app solves is **playback**: neither backend exposes a stable video URL. Arabic Toons requires fresh, IP‑bound, time‑limited tokens scraped from the episode page at the moment of play; Stardima requires a multi‑stage scrape (play page → iframe → host embeds → `.m3u8`). Both ultimately feed a single ExoPlayer surface with the exact CDN headers each origin demands.

---

## Download

📺 **[Download the latest APK](https://github.com/ItisMoe/Kartoonia/releases/latest/download/Kartoonia.apk)** · [All releases](https://github.com/ItisMoe/Kartoonia/releases/latest)

Sideload the APK onto your Android TV / Google TV device (Android 11+). On most devices: enable **Settings → System → Developer options → Install unknown apps** (or **Apps → Security**), then install via a file manager / [Downloader](https://www.aftvnews.com/downloader/) app using the link above. For a quick manual install over USB/ADB:

```bash
adb install Kartoonia.apk
```

### Install with the Downloader app (easiest on a TV)

The [**Downloader**](https://www.aftvnews.com/downloader/) app (free, on the Play Store / Amazon Appstore) is the standard way to sideload onto a TV with just a remote — no file manager or PC needed.

**Downloader code: `6954638`**

1. Install **Downloader** from your TV's app store and open it.
2. In the **Home** tab's URL box, enter `6954638` (or paste the full APK URL: `https://github.com/ItisMoe/Kartoonia/releases/latest/download/Kartoonia.apk`).
3. Press **Go** → **Download**. When it finishes, choose **Install**, then **Done → Delete** to remove the downloaded APK.
4. First time only: Downloader will prompt you to allow installs from unknown sources — enable it, then back out and retry the install.

#### About the code

The code `6954638` is issued by the free [aftv.news](https://aftv.news/code) service and redirects to the latest-APK URL above. Because that URL points at `releases/latest`, **the code keeps working across new releases** — no need to regenerate it when you publish a new version. If you ever need to re-point or refresh it, go to **https://aftv.news/code** and paste `https://github.com/ItisMoe/Kartoonia/releases/latest/download/Kartoonia.apk` again.

---

## Table of contents

- [Download](#download)
- [Features](#features)
- [Tech stack](#tech-stack)
- [Architecture overview](#architecture-overview)
- [The playback pipeline (the critical path)](#the-playback-pipeline-the-critical-path)
- [Data model & catalogs](#data-model--catalogs)
- [State management](#state-management)
- [Project layout](#project-layout)
- [Getting started](#getting-started)
- [Building & releasing](#building--releasing)
- [Configuration](#configuration)
- [Testing](#testing)
- [Maintenance guide](#maintenance-guide)
- [Troubleshooting](#troubleshooting)

---

## Features

- **Dual catalog sources** — switch between Arabic Toons and Stardima at runtime from Settings; the choice is persisted and the whole UI re‑renders from the newly selected source. Both normalize into one model, so every screen is source‑agnostic.
- **Live token / stream resolution** — video URLs are resolved *immediately before* playback (never cached for Arabic Toons), with the precise `Referer`/`User-Agent`/`Origin` headers forwarded to ExoPlayer for the manifest and every segment.
- **TV‑first navigation** — full D‑pad / remote focus model (spatial directional traversal, focus rings, tab↔content focus split), landscape‑locked, no touchscreen required.
- **Home experience** — rotating hero carousel plus curated rows (Most Popular, Popular Now, Top 10, Movie spotlight, New, and genre rows), with a date‑seeded daily shuffle so the home page feels fresh without reordering Continue Watching.
- **Continue Watching** — per‑episode progress saved every 5 s and on exit, restored on resume, surfaced as a wide progress row.
- **My List (watchlist)** — toggle titles into a persisted list.
- **Browse** — by TV / Movies / My List, with an Arabic‑aware A–Z alphabet bar (EN/AR script toggle) for Arabic Toons and category filters for Stardima.
- **Bilingual search** — on‑screen EN/AR keyboard plus **voice search** (on‑device speech‑to‑text; the mic button hides itself when no recognizer/permission is available).
- **Native trailer / theme‑song playback** — YouTube Data API search → `youtube_explode_dart` muxed stream → played in the app's own ExoPlayer surface (no iframe / WebView).
- **Google TV recommendations** — publishes a home‑screen recommendation channel via `androidx.tvprovider`; deep links (`kartoonia://item/<id>`) open straight into Detail.
- **Bilingual UI** — Arabic (RTL) and English (LTR); ratings are intentionally hidden everywhere.

---

## Tech stack

| Concern | Choice |
|---|---|
| Framework | Flutter (Dart SDK `^3.12.1`; developed on Flutter 3.44.x) |
| State management | [`flutter_riverpod`](https://pub.dev/packages/flutter_riverpod) `^2.6.1` |
| Video playback | [`video_player`](https://pub.dev/packages/video_player) `^2.9.2` (ExoPlayer; `httpHeaders` forwarded per‑request) |
| Networking | [`http`](https://pub.dev/packages/http) `^1.2.2` |
| Image loading | [`cached_network_image`](https://pub.dev/packages/cached_network_image) `^3.4.1` |
| Persistence | [`shared_preferences`](https://pub.dev/packages/shared_preferences) `^2.3.3` |
| Voice search | In-app Android `SpeechRecognizer` via a platform channel (no plugin) |
| YouTube stream extraction | [`youtube_explode_dart`](https://pub.dev/packages/youtube_explode_dart) `^3.1.0` |
| Launcher icon | [`flutter_launcher_icons`](https://pub.dev/packages/flutter_launcher_icons) `^0.14.4` (dev) |
| Native (Android) | Kotlin, `androidx.tvprovider:1.0.0`, Java 17, `minSdk 30` (Android 11), `compileSdk 36` |

Fonts: **Fredoka** (Latin display), **Nunito** (Latin UI), **Cairo** (Arabic).

---

## Architecture overview

The app is a single-Activity Flutter app driven by Riverpod providers. Services are constructed **before the first frame** (the branded splash covers the async init) and injected via `ProviderScope` overrides.

```
main()
 ├─ StorageService.create()                 # SharedPreferences-backed
 ├─ CatalogService.load(persistedSource)    # parse the bundled JSON catalog
 └─ runApp(ProviderScope(overrides: [...], KartooniaApp))

KartooniaApp (app.dart)
 └─ MaterialApp(home: SplashScreen)
     └─ Directionality follows the chosen language (RTL for Arabic)

Screens (lib/screens):  Splash → Home → {Browse, Search, Detail → Player, YouTube, Settings}
```

Two design decisions worth calling out:

- **The 1920×1080 design canvas is scaled per‑screen (`ScreenShell` / `Splash`), not globally.** Scaling the whole app would wrap full‑screen platform views (the video player) inside a transform and mis‑composite them on Android. Overlays are still scaled via `TvScaler`; the video surface renders at native size.
- **A single `Material` wrapper** in `app.dart` provides a proper `DefaultTextStyle` everywhere, which is why screens use `ColoredBox` rather than `Scaffold` and never show Flutter's yellow double‑underline text‑error decoration.

---

## The playback pipeline (the critical path)

This is the most important — and most fragile — part of the app. Both backends are scraped, and **scraping breaks when the upstream site changes**. Everything funnels through one entry point:

```dart
// lib/services/playback_resolver.dart
Future<List<PlayableServer>> resolvePlayback(CatalogSource source, String pageOrPlayUrl)
```

A `PlayableServer` is a ready‑to‑open `url` + the `headers` the CDN requires + a label/number for the player's server picker. The player itself is source‑agnostic; it just opens URLs and forwards headers.

### Arabic Toons — fresh token scrape

`lib/services/token_service.dart`

1. `fetchFreshTokens(pageUrl)` GETs the episode/movie **page** HTML with browser‑like headers (`kEpisodePageHeaders`).
2. `extractServerLinks(html)` runs three regex strategies, in order:
   - numbered servers: `var/let/const serverN = "...?tkn=..."`
   - single source: `var/let/const videoSrc = "..."`
   - fallback: `src` / `data-src` / `file:` pointing at `.mp4|.m3u8|.mkv|.webm`
   - …keeping only `http(s)` URLs whose path has a media extension, de‑duped by server number and sorted.
3. The tokenized `rawUrl` is played directly, with `kStreamHeaders` (`Referer` / `User-Agent` / `Origin`) attached.

> **Two rules that must never be broken:**
> 1. **Never reuse `raw_url` from the catalog JSON** — those tokens are stale. Always re‑scrape at play time.
> 2. **Always send `kStreamHeaders`** on every manifest *and* segment request — without `Referer` the CDN returns `403`.

### Stardima — multi‑stage embed resolution

`lib/services/stardima_resolver.dart` (a faithful Dart port of the project's Python `resolver_scripts/`)

A Stardima item only carries a `play_url`. Turning it into a stream is a three‑stage pipeline:

1. **play page → hyperwatching iframe `code`** (`hyperwatchingCode`)
2. **iframe `code` → per‑host embed links** — parse the CSRF token + server list, then `POST /api/videos/<code>/link` for each host (`parseIframeServers` + `_serversForCode`)
3. **each embed page → real `.m3u8` / `.mp4`** — regex over the page *and* any Dean‑Edwards `eval(p,a,c,k,e,d)` packed block (`unpackPacked`), preferring `master.m3u8` → any `.m3u8` → `.mp4` (`bestStreamUrl`)

Every host becomes a numbered server with its own `Referer`/`UA`/`Origin`. The pure parsing functions (`hyperwatchingCodeFromHtml`, `parseIframeServers`, `bestStreamUrl`, `unpackPacked`) are unit‑tested so a regex regression is caught fast.

Because this pipeline is expensive (multiple round‑trips), the player **caches Stardima resolution per `play_url`** for instant server switching. Arabic Toons is never cached (tokens expire).

> **Known limitation:** the original Python/VLC prototype forced the Arabic audio rendition via LibVLC `--audio-language`. `video_player`/ExoPlayer exposes no track‑selection API, so Stardima HLS plays the engine's default audio rendition.

### Player resilience

`lib/screens/player_screen.dart` retries the same server, then advances across available servers, then shows an error+retry UI. The seek bar is forced LTR (so it fills left→right even in Arabic), seeks fire on drag‑end, progress restores when >10 s in, and `onEnd` advances to the next episode across flattened seasons.

---

## Data model & catalogs

Both backends parse into the **same** normalized model (`lib/models/content_item.dart`):

```
ContentItem (sealed)
 ├─ Show   → seasons[] → episodes[] (also flattened into `episodes`)
 └─ Movie  → page_url + servers[]
```

Shared getters resolve art and text with graceful fallbacks:

- **poster** → TMDB `w500` → downsized TMDB poster → catalog thumbnail
- **backdrop** → TMDB backdrop → TMDB poster → thumbnail
- **description** → TMDB `overview_ar` → catalog description → `overview_en`
- **popularity** → TMDB `vote_average` — used only for internal ordering, **never displayed**

Source‑specific parsing lives behind the model:

- **Arabic Toons** uses `Show.fromJson` / `Movie.fromJson`. Shows derive a stable id from `ids[]` (joined) or `slug`; `episode_url` / movie `page_url` are the **page** URLs used for token fetching.
- **Stardima** uses `StardimaAdapter` (`lib/models/stardima_adapter.dart`), which synthesizes a `TmdbData` from the flat `poster_url`/`backdrop_url`/`year`/`category` fields and maps the single `category` string into the item's genres/categories. Each item is tagged `source: stardima`, and `play_url` is carried in the `pageUrl` / `episodeUrl` fields for the resolver.

`CatalogService` (`lib/services/catalog_service.dart`) loads the bundled asset for the active source, indexes by id, and serves every query path (search, genres, browse, featured/hero pool, Top 10, popular rows). `switchTo()` swaps the source in place.

### Catalog assets

Both catalogs ship as bundled assets registered in `pubspec.yaml`:

- `assets/arabictoons_catalog.json`
- `assets/stardima_catalog.json`

These are large, generated JSON files (the scraper scripts that produce them live outside the app). The active source defaults to **Arabic Toons** on first launch.

---

## State management

Riverpod providers (`lib/state/app_state.dart`):

| Provider | Purpose |
|---|---|
| `storageProvider`, `catalogProvider` | Injected at startup via overrides |
| `catalogSourceProvider` | Active catalog source; `setSource()` persists, reloads, resets filters, bumps the rev |
| `catalogRevProvider`, `catalogSwitchingProvider` | Force catalog‑bound screens to rebuild during/after a switch |
| `settingsProvider` | Language (`ar`/`en`) + playback prefs (motion / autoplay / subtitles) |
| `stringsProvider` | The active i18n string table |
| `ytKeyProvider` | User‑set YouTube Data API key override |
| `userProvider` | Watchlist + Continue Watching |
| `browseProvider`, `searchProvider` | Transient browse/search UI state |
| `voiceProvider`, `voiceServiceProvider` | Voice‑search session + recognizer |

---

## Project layout

```
lib/
├─ main.dart                 # async init + ProviderScope
├─ app.dart                  # MaterialApp, RTL direction, global Material wrapper
├─ navigation.dart           # AppNav + deep-link handling
├─ config.dart               # bundled default YouTube API key
├─ models/
│  ├─ content_item.dart      # ContentItem / Show / Movie / Episode / Season / TmdbData
│  ├─ catalog_source.dart    # the two-source enum (id + asset path)
│  └─ stardima_adapter.dart  # Stardima JSON → normalized model
├─ services/
│  ├─ catalog_service.dart   # load / index / query the active catalog
│  ├─ token_service.dart     # Arabic Toons fresh-token scrape  ← critical
│  ├─ stardima_resolver.dart # Stardima embed→stream pipeline   ← critical
│  ├─ playback_resolver.dart # single source-agnostic entry point
│  ├─ storage_service.dart   # SharedPreferences: watchlist, progress, prefs
│  ├─ youtube_service.dart   # YouTube Data API search
│  ├─ youtube_stream_resolver.dart # videoId → muxed stream URL
│  ├─ voice_search_service.dart
│  └─ recommendations.dart   # Google TV reco channel bridge
├─ state/app_state.dart      # all Riverpod providers
├─ screens/                  # splash, home, browse, detail, player, search, settings, youtube
├─ widgets/                  # cards, rows, hero carousel, top bar, focusable, tv_scaler, …
├─ theme/                    # theme + layout tokens
├─ i18n/strings.dart         # AR/EN string tables
└─ utils/                    # image_urls, daily_shuffle, genre_translations

android/
├─ app/src/main/AndroidManifest.xml          # leanback, permissions, deep links
├─ app/src/main/kotlin/.../MainActivity.kt   # MethodChannel + deep-link capture
├─ app/src/main/kotlin/.../Recommendations.kt# TV reco channel
└─ app/build.gradle.kts                       # minSdk 30, compileSdk 36, signing

assets/  (catalogs, fonts, icons)
test/    (unit tests)
```

---

## Getting started

### Prerequisites

- **Flutter SDK** with Dart `^3.12.1` (developed against Flutter 3.44.x).
- **Android toolchain**: Android SDK with API 36 (`compileSdk`), Java 17.
- A **target device**: an Android TV / Google TV device or the Android TV emulator (the app is `landscape`‑locked and leanback‑oriented). It will also run on a regular Android phone/tablet for development.

### Install & run

```bash
flutter pub get
flutter devices            # find your Android TV / emulator id
flutter run -d <device-id>
```

> **Tip:** for the TV experience use an **Android TV (1080p) emulator** or a real device and navigate with the D‑pad / remote (arrow keys + Enter on the emulator).

---

## Building & releasing

### Debug / profile

```bash
flutter run --profile -d <device-id>
flutter build apk --profile
```

### Release

Release builds are minified and resource‑shrunk (R8/ProGuard enabled in `build.gradle.kts`).

```bash
flutter build apk --release        # APK (sideload onto a TV)
flutter build appbundle --release  # AAB (Play Store)
```

**Signing.** If `android/key.properties` exists, release builds sign with the configured keystore; otherwise they fall back to the debug key. Create `android/key.properties` (do **not** commit it):

```properties
storeFile=/absolute/path/to/keystore.jks
storePassword=********
keyAlias=********
keyPassword=********
```

Output artifacts are named `Kartoonia-v<versionName>` (see `archivesName`).

### Launcher icon & TV banner

The adaptive launcher icon is generated by `flutter_launcher_icons`:

```bash
dart run flutter_launcher_icons
```

The Android TV home‑row **banner** is supplied separately via `android:banner="@drawable/banner"` in the manifest (not generated by the icon tool).

---

## Configuration

| What | Where | Notes |
|---|---|---|
| Bundled YouTube Data API key | `lib/config.dart` (`kYoutubeApiKey`) | Used only for the on‑demand trailer/theme‑song search. Users can override it in Settings (persisted as `kt/ytKey`); user key takes precedence over the bundled one. |
| Default catalog source | `StorageService.getCatalogSource()` | Defaults to Arabic Toons; user‑switchable in Settings. |
| Default UI language | `StorageService.getLang()` | Defaults to **English**; switchable in Settings. |
| Playback prefs | `kt/prefs` | `motion` (off), `autoplay` (on), `subtitles` (off). |
| Application ID | `android/app/build.gradle.kts` | `com.kartoonia.kartoonia`. |

### Permissions (Android)

- `INTERNET` — networking.
- `RECORD_AUDIO` — voice search (mic is declared optional; the voice button hides itself when unavailable).
- `com.android.providers.tv.permission.WRITE_EPG_DATA` — publish Google TV recommendation channels.

The manifest also declares `leanback`, `touchscreen`, and `microphone` features as **not required**, and adds package‑visibility `<queries>` for the speech recognizer (required on Android 11+).

---

## Testing

Unit tests cover the fragile, pure logic — catalog parsing and the scraper regex/selection paths:

```bash
flutter test
```

| Test | Covers |
|---|---|
| `test/token_service_test.dart` | Arabic Toons server‑link extraction regexes |
| `test/stardima_resolver_test.dart` | hyperwatching code, iframe parse, best‑stream selection, packed‑JS unpacking |
| `test/stardima_adapter_test.dart` | Stardima JSON → normalized model |
| `test/catalog_parse_smoke_test.dart` | Catalog parsing smoke test |
| `test/youtube_stream_resolver_test.dart` | Muxed stream selection (`pickMuxedUrl`) |
| `test/voice_search_service_test.dart` | Voice search service |

There is also a manual probe at `tool/test_token_fetch.dart` for verifying live token extraction against a real Arabic Toons page during debugging.

---

## Maintenance guide

The catalogs and the playback resolvers depend on **third‑party websites we don't control**. Most maintenance is reacting to upstream changes.

### "Videos won't play" — diagnose by source

1. **Confirm which source is active** (Settings). Arabic Toons and Stardima fail for completely different reasons.
2. **Arabic Toons:** run `tool/test_token_fetch.dart` against a known episode page. If no servers are extracted, the page markup changed — update the regexes in `extractServerLinks` (`token_service.dart`) and the matching test. If extraction works but playback `403`s, the CDN changed its header requirements — update `kStreamHeaders`.
3. **Stardima:** the three‑stage pipeline is the usual suspect. Re‑check each stage's regexes/endpoints in `stardima_resolver.dart` against the live pages (`hyperwatchingCode` → `parseIframeServers`/`_serversForCode` → `bestStreamUrl`). The pure functions are unit‑tested, so update the test fixtures alongside the regexes.

### "Trailers stopped loading"

A blank → "couldn't load" trailer is almost always a **YouTube signature‑cipher change**, not a bug in our code. Fix = bump `youtube_explode_dart` in `pubspec.yaml` (the same as periodically updating `yt-dlp`). Note muxed/progressive streams are intentionally **360p‑capped** by YouTube — higher resolutions only exist as separate video‑only/audio‑only tracks a single‑URL player can't combine.

### Refreshing catalogs

The catalog JSON files are generated artifacts produced by external scraper scripts (outside this repo's app code). To refresh content, regenerate `assets/arabictoons_catalog.json` / `assets/stardima_catalog.json` and rebuild. Keep both registered in `pubspec.yaml`.

### Adding a new catalog source

The architecture is built for this:

1. Add a case to the `CatalogSource` enum (id + asset path).
2. Write an adapter that parses the new JSON into `Show`/`Movie` (see `StardimaAdapter`).
3. Wire the parse case into `CatalogService._loadSource`.
4. Add a playback branch to `resolvePlayback` returning `PlayableServer`s with correct headers.
5. Add unit tests for the parser and any scraper regexes.

Everything downstream (screens, search, art, rows, player) stays unchanged because it only deals with the normalized model and `PlayableServer`.

### Conventions

- **Keep the player source‑agnostic.** All source‑specific logic belongs in the resolver/adapter layer, behind `resolvePlayback` and `CatalogService`.
- **Never display ratings.** `vote_average` is internal ordering only; `match_confidence`/`match_source` are never shown.
- **Match surrounding code style** — Riverpod `Notifier`s for state, small focused widgets, and comments that explain *why* (especially around the scraping and platform‑view scaling decisions).

---

## Troubleshooting

| Symptom | Likely cause / fix |
|---|---|
| Video plays then `403`s on segments | Missing/changed CDN headers — verify `kStreamHeaders` (Arabic Toons) or the per‑host `headers` (Stardima). |
| "No video servers found" (Arabic Toons) | Page markup changed — update `extractServerLinks` regexes. |
| Stardima item won't resolve | One of the three pipeline stages broke — check `stardima_resolver.dart` against live pages. |
| Trailer screen blank / "couldn't load" | Bump `youtube_explode_dart` (YouTube cipher change). |
| Voice button missing | No speech recognizer or mic permission denied — expected behavior; the button hides itself. |
| Video surface looks stretched/mis‑composited | Don't move the 1920×1080 scaling back into the global `app.dart` builder — it must stay per‑screen so platform views render at native size. |
| Yellow double‑underline under text | A screen bypassed the global `Material` wrapper — ensure text renders within it. |
| Build fails on `compileSdk`/`minSdk` | Needs `compileSdk 36`, `minSdk 30`, Java 17. |

---

*Kartoonia is a personal/educational project that aggregates publicly available content from third‑party sites; respect the terms of service of those sources and applicable copyright law in your jurisdiction.*
