# Design — Library Modes · Carateen SpaceToon catalog · Spotlight hero

**Date:** 2026-07-12
**Branch base:** `feat/carateen-source`
**Status:** Approved (design), pending implementation plan

Three independent changes ship together because they touch the same screens
(Home, Browse, Settings) and the Carateen source:

1. **Library Modes** — replace the binary "Everything" toggle with five explicit
   catalog modes that scope **Home and Browse only**.
2. **Carateen SpaceToon catalog** — pull the missing `/api/sp/tvshows` library
   (422 shows incl. أبطال الكرة) so *every* carateen.tv title is in the app.
3. **Spotlight hero** — the Home hero becomes a backdrop-sized (16:9) card
   carousel (layout "A") instead of a full-bleed backdrop.

---

## 1. Library Modes

### Problem
Today the app has a single persisted `everythingMode` bool: OFF = one merged
Arabic library (ArabicToons + Stardima + Carateen) with an optional per-source
Browse *filter*; ON = WCOFlix only. The per-source filter is unreliable and
conflates "which sources exist" with "which are shown." The user wants distinct,
switchable **modes** instead.

### The five modes
A new `LibraryMode` enum (persisted as `kt/libraryMode`), each mapping to a set
of bundled sources plus whether the WCOFlix universe is included:

| Mode | id | Bundled sources | WCOFlix | Arabic label |
|------|----|-----------------|---------|--------------|
| Stardima + ArabicToons | `dubbed` | arabicToons, stardima | no | ستارديما + عرب تونز |
| Carateen | `carateen` | carateen | no | كراتين |
| Arabic (all three) | `arabic` | arabicToons, stardima, carateen | no | كل العربية |
| WCOFlix (coflix) | `wcoflix` | — | yes | WCOFlix |
| Everything | `everything` | arabicToons, stardima, carateen | yes (un-merged) | كل شيء |

`arabic` is the current default merged library; it stays the app default.

### Scope: Home + Browse ONLY
- **My List, Continue Watching, Search, Detail, playback** are mode-independent
  and unchanged. A title saved to My List in one mode shows identically in every
  mode. Cross-source twins and the detail-screen source picker stay global.
- Only the **Home pools** (hero, most-popular, top-10, genre rows, recent) and
  the **Browse grids** (Movies / TV) are scoped to the active mode.

### CatalogService becomes mode-aware
The service keeps loading **all three bundled catalogs merged** at boot (today's
`loadMergedInPlace`, unchanged) so switching modes never reloads or re-parses.
It gains an `activeMode` field and mode-scoped views:

- `LibraryMode.bundledSources` → `Set<CatalogSource>`.
- `viewItems(mode)` — the display pool for a mode:
  - **Single bundled source** (`carateen`): every item whose `source == carateen`,
    read from the full `_byId` index (this includes carateen twins that global
    merge collapsed into an AT/Stardima primary), deduped. Result = a *pure*
    Carateen catalog with Carateen art — the "own catalog" the user wants.
  - **Multiple bundled sources** (`dubbed`, `arabic`, `everything`'s Arabic half):
    `all` filtered to items `availableOn` any allowed source, using the existing
    collapsed primaries (today's behavior, just narrower). `arabic` = no filter.
- Fame pool / popular / genre rows / featured(hero) pool getters derive from
  `viewItems(activeMode)`. Memoization becomes keyed on `activeMode`; changing
  mode calls `_invalidateDerived()`. Mode changes are rare (Settings), so a
  recompute is cheap and acceptable.
- `setMode(LibraryMode)` updates `activeMode` + invalidates derived caches.

### WCOFlix in Everything mode (un-merged)
`everything` shows both universes **without cross-merging** them:
- **Home:** the Arabic hero + Arabic rows (from `viewItems` over the 3 bundled
  sources), then a labelled **WCOFlix** section of rows below (reusing the
  existing `wco*` providers). No title collapsing between the two universes.
- **Browse (Movies/TV):** a light top segmented control **[العربية | WCOFlix]**
  that swaps which universe's grid renders. This is a *universe* switch, not the
  removed per-source filter.
- `wcoflix` mode = WCOFlix only (today's Everything behavior).

### Settings: 5-way picker
Replace the Everything On/Off segmented control with a single-select list of the
five modes (Arabic labels above), writing `kt/libraryMode`. The block keeps its
current position and the same option-row styling.

### Browse per-source filter: removed
Delete the AT/Stardima/Carateen source-filter UI (TV dialog + phone rail) and the
`BrowseState.sourceFilter` field and its plumbing. Modes replace it. The
`availableOn` helper stays (used by `viewItems` and the detail picker).

### Storage migration
- New key `kt/libraryMode` (string id). Default `arabic`.
- One-time migration on read: if `kt/libraryMode` is unset but the legacy
  `kt/everythingMode` exists → `true` maps to `wcoflix`, `false` to `arabic`.
  Keep the old key read-only for the migration; stop writing it.

---

## 2. Carateen SpaceToon catalog (fix أبطال الكرة)

### Root cause
carateen.tv exposes **two** catalogs; the scraper only read the first:
- `/api/tvshows` → 336 "Telegram/يوفو" shows (currently scraped).
- `/api/sp/tvshows` → **422 SpaceToon-Go shows** (never scraped) — this is where
  أبطال الكرة (id 175, 127 eps) and its siblings (فرسان / فرسان الزمن /
  فرسان المجرة) live. Watch URL form: `carateen.tv/watch/sp/<showId>`.

### Verified feasibility (pure HTTP, no browser/captcha)
- `GET /api/sp/tvshows` → list of shows. Fields: `id, name, planet_name (category),
  cover_full_path, trailer_cover_full_path, ep_count, is_movie, rating,
  total_votes, release_year?`. Same AES envelope + static key
  (`7annaba3l_loves_crypto_safe_key!`) as the existing endpoints.
- `GET /api/sp/episodes?id=<showId>` → episodes. Fields: `id, number, season,
  cover_full_path, video_id, duration`.
- **Playback:** `POST /api/sp/episode/link` with JSON body `{"episodeId": <id>}`
  → AES-decrypt → `{ success, link: "<master .m3u8>", skip_intro, source:"hls" }`.
  The `link` is a master HLS playlist (270/480/720/1080p) that plays with just
  `User-Agent` + `Referer: https://carateen.tv/` — no signing/token. Confirmed
  live: `POST {episodeId:12896}` → `https://pegasus.5387692.xyz/api/sp/hls/…/playlist.m3u8`
  returning a valid 4-variant master.

### Scraper (`tool/carateen_scrape.py`)
Extend the existing scraper to also pull the sp catalog and merge into the same
`assets/carateen_catalog.json`:
- Add `/api/sp/tvshows` + `/api/sp/episodes?id=` fetch, normalized to the **same
  output schema** the adapter already parses (`tvshows[]`/`movies[]` with
  `seasons[].episodes[]`).
- **sp play_url form:** `https://carateen.tv/watch/sp/<showId>/<episodeId>` — the
  `sp` segment is the marker the resolver keys on.
- **Poster:** sp uses absolute `cover_full_path` (cdn.spacetoongo.com) — pass
  through as `poster_url` (no `/assets/img/posters/` prefix).
- **Category:** `planet_name` (e.g. رياضة, أكشن) → `category`.
- **Movies:** sp `is_movie == true` (or `ep_count <= 1`) → `movies[]`.
- **Seasons:** group episodes by the `season` field so أبطال الكرة renders its
  seasons (today the tg scraper emits a single season 1; sp preserves seasons).
- **De-dupe across catalogs:** sp ids and tg ids can collide numerically, so the
  merged item id must be namespaced (e.g. `sp_<id>` vs the existing bare `<id>`)
  and the adapter's `c_` prefix keeps them unique app-side. Keep both catalogs;
  do not drop tg titles.
- Re-run the scrape to regenerate `assets/carateen_catalog.json` (music JSON
  untouched).

### Adapter (`lib/models/carateen_adapter.dart`)
Mostly unchanged — sp items are normalized to the same JSON shape by the scraper.
Only additions:
- Accept an absolute `poster_url` as-is (already does via `_str`).
- No structural change to `_show`/`_movie`; sp seasons flow through the existing
  `seasons[].episodes[]` loop.

### Resolver (`lib/services/carateen_resolver.dart`)
Add an sp branch keyed on the `/watch/sp/…` URL form:
- `parseCarateenPlayUrl` recognizes `.../watch/sp/<show>/<episode>` and returns
  `(showId, episodeId, isSp: true)`.
- When `isSp`: `POST /api/sp/episode/link` body `{"episodeId": episodeId}` (JSON,
  same auth headers), decrypt, read `link` as the master `streamUrl`. Then reuse
  the **existing** master-playlist expansion (`parseHlsMasterVariants` /
  `orderCarateenVariants`) and `kCarateenMediaHeaders` unchanged — sp masters have
  the same shape, so the 720p-first variant picker just works.
- When not sp: today's `GET /api/episode?episodeId=&showId=` path, unchanged.

---

## 3. Spotlight hero (layout A)

### Change
`lib/widgets/hero_carousel.dart` goes from a full-bleed cross-fading backdrop to
a **centered backdrop-sized (16:9) card** carousel:
- One large rounded 16:9 card, sized to the backdrop image, centered in the hero
  band; **dimmed peek slivers** of the previous/next titles on each side (RTL:
  next on the left, prev on the right).
- Title + meta line + action pills (**شاهد الآن / معلومات / قائمتي**) sit **below**
  the card (not overlaid), followed by the progress dots.
- Auto-advance **slides** between titles (slide transition, cross-fade fallback on
  low-spec per `DevicePerf.lowSpec`), same 6.5s / 12s cadence and focus-pause
  behavior as today.
- Keep the existing blurred full-screen backdrop-fill behind the band
  (`_HeroBackdropFill`) for ambient bleed around the contained card;
  `onBackdrop` still fires per slide.
- **Focus/D-pad:** the three pills stay focusable (Watch autofocus). Left/Right on
  the card region (or on the dots) advances the carousel; Up/Down behave as today
  (scroll into view / into the rows). Peek cards are non-focusable decoration.

### Applies to both hero call sites
`home_screen.dart` uses `HeroCarousel` for both the Arabic hero (`getFeaturedPool`)
and the WCOFlix hero (`wcoHeroProvider`); the redesign is internal to the widget,
so both get it. Phone Home hero (if separate) mirrors the layout at phone scale.

---

## Out of scope / non-goals
- No change to playback engine, token logic, WCOFlix resolver, or Search.
- No cross-merging of WCOFlix with the Arabic catalogs in any mode.
- No new dependencies.

## Risks
- **sp id collisions** with tg ids — mitigated by namespaced ids in the scraper.
- **sp link host** (`pegasus.5387692.xyz`) may rotate; the resolver reads whatever
  `link` the API returns each play, so a host change needs no app update.
- **Mode-scoped memoization** must be invalidated on mode switch or Home shows a
  stale pool — covered by `_invalidateDerived()` in `setMode`.

## Rollout
Single feature branch off `feat/carateen-source`; version bump on release per the
"release version must match tag" rule.
