# Kartoonia TV — Feature Batch (June 2026)

Design for a batch of TV-focused features. Scope was set by the user; the kids /
parental-PIN lock was explicitly excluded.

## Goals

Improve the lean-back (Android TV / Google TV) experience with: binge-friendly
playback, a single merged library across both catalog sources, faster Home
scrolling, recency affordances, a screensaver, and small polish items.

## Context (current state, verified in code)

- `CatalogService` loads **one** source at a time (Arabic Toons *or* Stardima),
  chosen by a persisted setting and switchable in Settings. Both parse into the
  same `ContentItem` model. Each item carries its own `source`, which drives the
  playback path (`playback_resolver.dart`).
- Episode auto-advance **already exists**: `player_screen.dart` `_onEnd()` jumps
  to the next episode on `completed`. There is no visible end-card or cancel.
- A **My List screen already exists**: TopBar → `BrowseScreen(kind: 'mylist')`.
- Home (`home_screen.dart`) builds **all** rows eagerly inside a
  `SingleChildScrollView` + `Column`.
- The Subtitles on/off setting exists but is **not wired** to any player track.
- `Focusable` supports `onPressed` only (no long-press).
- Stardima items carry `tmdb_id` when enriched (`stardima_adapter.dart`).

## Decisions (from brainstorming)

- **Trailers:** improve the YouTube search query (Arabic-dub oriented). No TMDB
  API integration — TMDB trailers are original-language, not Arabic-dubbed.
- **Cross-source library:** fully **merge** both catalogs into one library.
  **Do not dedupe** — show both copies when a title exists in both sources.
  Distinguish duplicates with a small **source badge** on the poster card,
  shown only for titles present in both sources.
- **Subtitles:** remove the setting entirely (all content is dubbed).
- **Screensaver idle timeout:** 3 minutes.

---

## Features

### 1. Auto-play next end-card

**Files:** `lib/screens/player_screen.dart`

When the shared player reports `completed` and the current show has a next
episode, show a card (bottom-trailing) instead of jumping silently:

- Card content: poster/title of the next episode + label "الحلقة N".
- If `autoplay != 'off'`: an **8-second countdown** ("التالي خلال 8…"), a
  **Play now** button (autofocus), and a **Cancel** button. At 0 it advances via
  the existing `_next()`.
- If `autoplay == 'off'`: same card, **no countdown** — manual **Play next** /
  **Cancel**.
- **Cancel** dismisses the card and leaves the finished frame with controls
  available (no auto-advance, no pop).
- Movies, or a show's last episode: behave as today (`Navigator.maybePop`).

Implementation: a countdown `Timer` started in `_onEnd()`; `_ended`/card state
drives an overlay in the player `Stack`. The timer is cancelled on Cancel, on a
new `_load`, and in `dispose`. The current immediate `_next()` in `_onEnd()` is
replaced by showing the card.

### 2. Merged catalog (no dedup, source badge)

**Files:** `lib/services/catalog_service.dart`, `lib/main.dart`, `lib/app.dart`,
`lib/state/app_state.dart`, `lib/screens/settings_screen.dart`,
`lib/widgets/content_card.dart`

- New `CatalogService.loadMerged()`: load **both** assets, parse each (Arabic
  Toons via `Show/Movie.fromJson`, Stardima via `StardimaAdapter.parse`),
  concatenate into `shows` / `movies` / `all`, and index `_byId`. No dedup.
- ID collisions across sources are possible but unlikely; if `_byId` would
  collide, keep first-inserted (Arabic Toons) and skip the colliding id so the
  map stays well-formed. (Both copies still appear in `all`/lists; only `getById`
  resolves to one.)
- **Duplicate detection for the badge:** compute
  `Set<int> duplicatedTmdbIds` = TMDB ids that appear in **both** sources.
  Expose `bool isDuplicated(ContentItem)` (item has a `tmdbId` in that set).
- **Source badge:** `PosterCard` (and the wide/backdrop variants as needed) gain
  an optional `sourceLabel` string; screens pass it when `isDuplicated(item)` is
  true. Rendered as a small corner chip ("Arabic Toons" / "Stardima", localized).
  Non-duplicated items render with no badge.
- **Remove the source switcher:** delete the Settings "Source" group; remove
  `catalogSourceProvider`, `CatalogSourceNotifier`, `catalogSwitchingProvider`,
  and the related strings; drop `storage.getCatalogSource()/setCatalogSource`
  usage from `main.dart`. Keep the `CatalogSource` enum (items still need it for
  playback) and `assetPath`.
- `main.dart` calls `CatalogService.loadMerged()` and removes the catalog-source
  override.

### 3. My List row on Home

**Files:** `lib/screens/home_screen.dart`

When the watchlist is non-empty, insert a "My List" `ContentRow` of poster cards
immediately after the Continue Watching row, each linking to detail. Uses the
existing `userProvider.watchlistIds` resolved via `catalog.getById`.

### 4. Recent searches

**Files:** `lib/services/storage_service.dart`, `lib/state/app_state.dart`,
`lib/screens/search_screen.dart`

- Storage: `kt/recentSearches` (StringList, max 8, most-recent first, distinct).
  Methods: `getRecentSearches()`, `addRecentSearch(q)`, `clearRecentSearches()`.
- A query is recorded when a non-empty query yields ≥1 result (recorded on
  navigation away / selection, to avoid saving every keystroke prefix). Simpler
  acceptable variant: record the current query when the user opens a result.
- UI: when the query is empty, render recent queries as `SelectableChip`s above
  the popular grid, plus a "Clear" chip. Tapping a chip calls
  `searchProvider.setQuery(...)`.

### 5. Lazy Home rows

**Files:** `lib/screens/home_screen.dart`

Replace `SingleChildScrollView` + `Column([hero, ...rows])` with a
`CustomScrollView`: hero as the first `SliverToBoxAdapter`, then a
`SliverList(SliverChildBuilderDelegate(...))` over the row list so off-screen
rows construct on demand. Row data (the item lists) is still computed once in
`build`; only widget construction is deferred. Continue-Watching and My List
rows remain the first entries.

### 6. Ambient / screensaver

**Files:** new `lib/widgets/ambient_overlay.dart`, wired in `lib/app.dart`

- TV-only (`isTvProvider`). An app-level overlay wrapping the navigator child.
- Idle tracking: a `Focus`/`Listener` (hardware-key + pointer) resets a
  3-minute `Timer`. On fire, fade in a full-screen crossfading slideshow of
  backdrops from `catalog.getFeaturedPool()`, with a subtle clock + brand mark.
- Any key/pointer dismisses instantly (fade out) and resets the timer.
- **Suppressed while the player is active** so it never covers playback: the
  player route is full-screen and key events flow there; gate the overlay so it
  does not arm while a `PlayerScreen` is the top route (e.g. via a simple
  "player active" flag provider set in player init/dispose, or by checking the
  current route). Chosen: a `playerActiveProvider` bool toggled by PlayerScreen.

### 7. Continue Watching remove

**Files:** `lib/widgets/focusable.dart`, `lib/services/storage_service.dart`,
`lib/screens/home_screen.dart`

- Add optional `onLongPress` to `Focusable` (D-pad press-and-hold center / touch
  long-press), without changing existing call sites.
- Long-pressing a Continue-Watching card opens a small dialog: **Resume** (plays)
  / **Remove** (deletes progress) / Cancel.
- Storage: `removeProgress(String episodeUrl)` and
  `removeProgressForItem(String itemId)` (clears all episodes of a show). Remove
  uses `removeProgressForItem` so the whole show leaves the row. Then
  `userProvider.refresh()`.

### 8. Better trailers (YouTube query)

**Files:** `lib/screens/detail_screen.dart`

Make the query Arabic-dub oriented:
- Movies: `'<title> <year?> كرتون مدبلج عربي كامل'`.
- Shows: `'<title> مدبلج عربي مقدمة'` (theme/intro).

(Existing `AppNav.youtube(context, query, title)` flow is unchanged.)

### 9. Remove subtitles

**Files:** `lib/screens/settings_screen.dart`, `lib/services/storage_service.dart`,
`lib/i18n/strings.dart`

Remove the Subtitles settings group, drop `subtitles` from the prefs defaults in
`getPrefs()`, and remove the now-unused `set_subtitles` (and any subtitle-only)
strings. No player wiring exists to unwind.

---

## Out of scope

- Kids mode / parental PIN lock (explicitly excluded).
- TMDB API integration for trailers.
- Cross-source episode merging (a show in both sources stays as two separate
  entries; we do not stitch their episode lists).

## Testing / verification

- `flutter analyze` clean.
- Manual TV run: merged Home shows titles from both sources; a known shared title
  shows two cards, the duplicates carrying source badges.
- Finish an episode → end-card appears, counts down, advances; Cancel stops it.
- Search empty state shows recent chips; selecting one runs the search.
- Idle 3 min on a non-player screen → screensaver; any key dismisses; never
  appears over the player.
- Long-press a Continue-Watching card → Remove clears it from the row.
- Settings no longer shows Source or Subtitles groups.

## Risks

- Merged catalog increases startup parse work (two assets) — covered by the
  splash; both assets are already bundled.
- Duplicate titles without a `tmdb_id` in one source won't get a badge (can't be
  detected) — acceptable; enriched items are the common case.
- Removing the source switcher reverses a previously-intentional delta, per the
  user's explicit request. The `deltas` / `stardima-dual-catalog` memories must
  be updated after implementation.
