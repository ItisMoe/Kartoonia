# Merged Titles with In-Detail Source Toggle

**Date:** 2026-06-18
**Status:** Approved design — ready for implementation plan

## Problem

The catalog now loads both sources (Arabic Toons + Stardima) into one merged
library via `CatalogService.loadMerged()`. Titles present in both sources appear
**twice** — two cards, distinguished only by a small source badge. This clutters
search results and every other row.

## Goal

Collapse cross-source duplicates into a **single card** everywhere in the app.
The choice of source moves into the **detail screen**: a duplicated title opens
on Arabic Toons by default (resume-aware), and the user can toggle to Stardima,
which swaps the seasons/episodes shown (for shows) or the Play target (for
movies). Playback dispatches per the selected source, exactly as today.

## Decisions (locked)

| Decision | Choice |
|---|---|
| Scope of collapse | App-wide (search, Home rows, Browse, My List — every card) |
| Match key | TMDB id only (reuse existing `_duplicatedTmdbIds`). No fuzzy title matching. |
| Default source on open | Resume-aware: select the source with stored progress; else Arabic Toons |
| Toggle stickiness | Reset per open (recompute default each time the detail screen mounts) |
| UI shells | Both TV (`detail_screen`) and phone (`phone_detail_screen`) |

## Approach

**Collapse in the catalog lists; add a source toggle to the detail screen.**
Chosen over a `TitleGroup` wrapper model because it localizes the entire feature
to two places (the catalog service + the detail screens) and leaves cards, fame
ranking, search, and browse untouched — they already iterate `ContentItem`
lists, so they get the collapsed library for free.

## Components

### 1. `CatalogService.loadMerged()` — grouping

- A duplicated TMDB id = an id present in **both** sources (the existing
  `_duplicatedTmdbIds`). For each such id:
  - **primary** = the Arabic Toons copy
  - **alternate** = the Stardima copy
- Build `shows`, `movies`, and therefore `all` from **primaries only**: drop the
  Stardima twin of any duplicated id. Non-duplicated items — including
  Stardima-only titles — pass through unchanged.
- Keep `_byId` populated with **both** copies, so a progress/watchlist entry
  saved against a Stardima id still resolves via `getById`.
- Add a lookup:

  ```dart
  /// The other-source twin of [item] (Stardima <-> Arabic Toons), or null when
  /// the title exists in only one source.
  ContentItem? alternateFor(ContentItem item);
  ```

  Backed by a `Map<int /*tmdbId*/, Map<CatalogSource, ContentItem>>` built during
  `loadMerged()`.
- `isDuplicated(item)` stays (now expressed via `alternateFor != null`) but its
  only remaining consumer is the detail screen's toggle-visibility check.

> Fame ranking, featured/hero, top-10, genre rows, browse, and search all read
> the collapsed `all`/`shows`/`movies`, so duplicates can no longer double-count
> or appear twice. The primary carries the same TMDB `vote_count`, so ranking is
> unaffected.

### 2. Detail screens — source toggle (`detail_screen` + `phone_detail_screen`)

- On build, resolve `final alt = catalog.alternateFor(item)`.
- **No alternate** → screen renders exactly as today (no toggle).
- **Alternate present** → maintain a selected-source state:
  - **Default (resume-aware):** for each twin, check stored progress
    (`storage.progressForItem(id)` for movies; any episode progress for shows).
    If one twin has progress, select that source; otherwise Arabic Toons.
  - Recomputed each time the screen mounts (reset per open).
  - Render two D-pad-focusable chips (Arabic Toons / Stardima), styled like the
    existing season selector, placed **below** the Play/Trailer/My-List action
    row and **above** the episodes section.
  - The **selected** `ContentItem` drives: the Play/Resume target, the
    season/episode count chiplets, and the episodes list. Title, poster,
    backdrop, and description come from shared TMDB data and stay stable across a
    switch.

### 3. Playback — unchanged

`playItem(context, ref, selectedItem, episode: ...)` already dispatches by
`selectedItem.source`. No change needed.

### 4. User library identity

- **My List:** `toggle` writes the **primary** (Arabic Toons) id. "In list" is
  true when **either** twin's id is in `watchlistIds` (covers any pre-existing
  Stardima-id entries). Applies in both detail screens.
- **Continue Watching:** progress remains keyed per source. When building the CW
  card list, **collapse** any entry whose item belongs to a group down to the
  primary id and **dedupe**, so a title watched on either source surfaces as one
  card. Opening it lands on the resume-aware detail screen, which reselects the
  source that has progress.

### 5. Cleanup

- Remove the cross-source badge path: the `_sourceBadge` usage and `sourceLabel`
  argument in `search_screen` + `content_card`'s `PosterCard`, and the
  equivalent on the phone poster card if present. There are no longer two cards
  to disambiguate.
- Keep the `source_badge_at` / `source_badge_st` strings only if reused by the
  detail-screen toggle labels; otherwise drop them.

## Testing

- **Catalog grouping (`merged_catalog_test`, extended):**
  - A title with a TMDB id in both sources appears **once** in `all` and that
    copy is the Arabic Toons primary.
  - `alternateFor(primary)` returns the Stardima twin and vice-versa.
  - `alternateFor` is null for single-source titles.
  - `_byId` still resolves the alternate's id (CW/watchlist back-reference).
  - Total `all` length = (sum of both sources) − (count of duplicated ids).
- **Default-source selection (unit):** given stored progress on the Stardima
  twin, the resume-aware default selects Stardima; with no progress it selects
  Arabic Toons.
- **CW collapse (unit):** progress on a Stardima twin yields a single CW card
  bound to the primary id; progress on both twins of one title yields one card.

## Out of scope

- Fuzzy/title-based matching of un-enriched duplicates.
- Persisting the chosen source across sessions (reset per open).
- Any change to the playback resolvers themselves.
