# Carateen source — design & feasibility findings (2026-07-11)

Status: **IMPLEMENTED (2026-07-12, v3.1.0).** The AES key was recovered — it's
CryptoJS **AES-256-CBC / Pkcs7**, key = the literal UTF-8 string
`7annaba3l_loves_crypto_safe_key!`, IV = hex of the `iv` field. Pure-HTTP
resolve verified end-to-end (no browser). The whole feature below is built,
unit-tested, and the resolver is live-verified; the one thing left is on-device
playback verification. See the `carateen-source` memory for the as-built notes.

## Goal (from user)
Add `carateen.tv` as a **normal-mode** playable source (parallel to Stardima), with:
- A switchable `CatalogSource.carateen` + bundled `assets/carateen_catalog.json`.
- In-app playback (streams, not a webview).
- **Everything mode:** when a WCOFlix title matches a Carateen title, show a "Play on Carateen" option.
- **Theme Songs:** a `/music`-sourced tab (browse + play audio) AND auto-offer a matching theme song on a title's detail/player even when the title has no episode video.

## What carateen.tv is (verified by probe)
- Cloudflare-fronted **Vue/Vite SPA** (jQuery+Bootstrap shell + hashed ES-module bundle). Not server-rendered.
- Content = Arabic cartoons + Spacetoon Go + anime. Media/covers on **`cdn.spacetoongo.com`**, played via the **Vidstack** HLS player (plain `.m3u8`, no DRM).
- Title URL: `carateen.tv/watch/<numeric_id>`. Theme songs under `/music`.
- Ad-gated: interacting fires pop-under / redirect ads to malvertising decoys (`fhvfd.com`, `viieuvkf.com`, …).

## The API (verified, decrypted via a JSON.parse hook in a real browser)
All responses are **AES-encrypted**: `{"iv":"<32 hex>","encryptedData":"<hex>"}`. Decryption happens in an axios **response interceptor** in `assets/chunk-CK_yr7N5.js`; the cipher is a bundled custom pure-JS implementation (64-bit limb math), key = a cross-chunk-obfuscated constant. Endpoints:

| Endpoint | Decrypted shape |
|---|---|
| `GET /api/tvshows` | full show catalog: `id, name, planet(+planet_name=genre), cover_full_path, ep_count, pref(desc), tags, min_age, is_movie, rating, views` |
| `GET /api/episodes?id=<showId>` | episode list: `id, title, show_id, video_id, hls_supported, thumbnail, season` |
| `GET /api/episode?id=<episodeId>` | **per-play source** (encrypted) → resolves the actual `.m3u8` (likely signed) on `cdn.spacetoongo.com` |
| `GET /api/sp/recentEpisodes`, `/api/sp/tvshows` | homepage feeds |

Pipeline: `tvshows` → `episodes?id=show` → `episode?id=ep` → `.m3u8`. Direct CDN URL guesses 404 → the stream URL must come from the decrypted `/api/episode` response.

## The blocker
On-device playback requires decrypting `/api/episode` at runtime → we need the **literal AES key + mode/cipher** ported to Dart. The key is buried behind cross-chunk obfuscation + a custom cipher. Recovering it is a dedicated reverse-engineering spike (webcrack gets us to the interceptor in `chunk-CK_yr7N5.js`, but string refs resolve across chunks and the cipher must be understood). **This is the go/no-go gate for the whole feature.**

### Fallback if the key resists Dart porting
Pre-resolve every episode's `.m3u8` at scrape time (browser decrypts), store URLs in `carateen_catalog.json`. Viable only if the `/api/episode` m3u8 URLs are stable/long-lived (unknown until we decrypt one — itself needs the key or a forced-playback capture). Weaker (links may expire), so key-in-Dart is preferred.

## Architecture (mirrors Stardima)
1. **`tool/carateen_scrape.py`** (Playwright + the probe's decrypt-capture) walks `/api/tvshows` + `/api/episodes` → `assets/carateen_catalog.json`; TMDB-match via existing `enrich_extra.py`.
2. **`CatalogSource.carateen`** enum + asset; parse in `catalog_loader`/`content_item` (Spacetoon shape → normalized `Show`/`Movie`).
3. **`lib/services/carateen_resolver.dart`** — Dart AES decrypt of `/api/episode?id=<ep>` → `ResolvedStream(.m3u8 + cdn headers)`; wired as `case CatalogSource.carateen` in `playback_resolver.dart`.
4. **Source switcher** (settings) gains Carateen alongside Arabic Toons / Stardima.
5. **Everything-mode cross-link** — scrape-time match index (title/year) → WCOFlix detail shows "Play on Carateen".
6. **Theme Songs** — `/music` scraper → catalog; new browsable tab (audio player) + auto-offer on matching titles.

## Recommended sequencing
1. **Spike (go/no-go):** recover the AES key, decrypt one `/api/episode`, play one real `.m3u8` end-to-end.
2. Scraper → `carateen_catalog.json` → TMDB enrich.
3. Dart resolver + source wiring; verify playback on device.
4. Everything-mode cross-link.
5. Theme Songs tab + auto-offer.
6. Version bump (pubspec == tag) + release. **Do not release until playback is verified on a real device** (in-app updater + TV launcher push to real users; a broken release is user-facing and the updater loops if version≠tag).

## Recon tool delivered
`tool/carateen_probe.py` — paste a `watch/<id>`/slug/`/music`/id, opens a real browser, blocks ad-redirects, captures the API + decrypted payloads + any media the player loads, prints a difficulty verdict. Run headful (`set PYTHONUTF8=1 && python tool\carateen_probe.py`) and click an episode to capture a live stream.
