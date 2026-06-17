# Browse: Sectioned + Fame-Sorted TV / Movies

**Date:** 2026-06-17
**Status:** Approved, ready for implementation plan

## Problem

The Movies and TV tabs (`BrowseScreen`) currently render a flat poster grid in
**raw catalog order** — no popularity/fame sorting at all. The "All" chip is
selected by default (good), but well-known/classic titles are not surfaced
first. There is also no way to narrow "All" down to a category.

Home, by contrast, already builds fame-ranked sectioned rows (Most Popular,
Popular Now, Top 10, genre rows) using existing helpers (`famousPool`,
`compareByFame`, `genreRows`, `popularPool`, `dailyShuffled`).

## Goal

Bring Home-style ranking and structure into Browse, scoped to a single type per
tab, plus a genre filter — while keeping a plain fame-sorted list whenever the
user has narrowed the view (by letter or by genre).

## Design

### Two display modes per tab

Each of the Movies and TV tabs renders one of two modes, chosen by the active
filter state. (The **My List** tab is unchanged — it stays a simple list.)

**Mode A — Sectioned (default: "All" active, i.e. no letter AND no category)**

Mirrors the Home layout **minus the hero carousel**, scoped to a single type
(Movies tab → movies only; TV tab → shows only), with daily rotation:

- **Most Popular** — daily-shuffled slice of the single-type famous pool
- **Popular Now** — daily-shuffled famous pool (different salt)
- **Top 10** — daily-rotating, ranked badge cards
- **Genre / category rows** — one row per genre with ≥ 4 items, each fame-sorted
  then daily-shuffled — exactly like Home's genre rows, but scoped to the type.

Row ordering follows Home's **daily-rotation** behavior (the famous pool
reshuffled each day), per the user's choice — not strict static order.

**Mode B — Flat grid (a letter OR a genre filter is active)**

The existing poster grid, but sorted **known-first** in **strict, stable fame
order** (same order every day). Applies to both letter-browsing and
genre-filtering.

### Controls

The alpha-bar rail keeps its current visual style. From leading to trailing:

- **Filter button** (new, leads the rail) → opens a D-pad-navigable overlay list
  of the catalog's genres/categories. Selecting one → Mode B for that category;
  an "All genres" entry clears the category filter.
- **Script toggle** (عربي / Latin) — unchanged.
- **All** chip — clears the letter (returns toward Mode A if no category set).
- **A–Z letters** — tapping a letter → Mode B.

**Combination rule:** letter and category combine. If both are set, the grid
filters by category AND letter, fame-sorted. The A–Z bar's enabled letters and
the header count reflect the active category (i.e. the `present` set and count
are computed over the category-filtered list, not the whole type).

Mode selection predicate (non-My-List tabs):

```
sectioned (Mode A)  when  letter == null && category == null
flat grid (Mode B)  otherwise
```

### Ranking detail (important)

`famousPool` (used by Home's curated rows) **drops** un-famous titles — correct
for curated rows, but wrong for a browse list that must show **every** title.

So the flat grid (Mode B) gets a **new** helper, `sortedForBrowse(items)`, that
keeps all titles and partitions them to avoid the vote_count-vs-rating
scale-mixing that `compareByFame`'s doc warns about:

1. Enriched titles (have TMDB `vote_count`) first, sorted by `vote_count` desc.
2. Then the rest, sorted by `weightedRating` desc.
3. Stable within ties (e.g. fall back to title order) so the grid is
   deterministic day-to-day.

This helper lives in `fame_ranking.dart` and is unit-tested independently of
asset I/O.

The Mode A curated rows continue to use `famousPool` / `dailyShuffled`, scoped
to a single type.

## Files touched

- **`lib/services/fame_ranking.dart`** — add `sortedForBrowse()` (+ unit tests).
- **`lib/services/catalog_service.dart`** — add single-type helpers: genre rows
  and pools scoped to movies-only or shows-only (so Mode A can build per-type
  sections without pulling the other type in). Reuse existing
  `popularShows()` / `popularMovies()` where they fit.
- **`lib/screens/browse_screen.dart`** — the two-mode render, the filter button,
  and the overlay genre picker. Sectioned mode reuses `ContentRow`, `PosterCard`,
  `Top10Card`, `BackdropCard` as Home does.
- **`lib/state/app_state.dart`** — wire the already-present (currently unused)
  `category` field via `setCategory`; ensure `setLetter` / `setCategory`
  interplay matches the combination rule.
- **`lib/i18n/strings.dart`** — add "Filter" and "All genres" labels (AR + EN).

## Out of scope

- No hero/slideshow in Browse.
- No changes to playback, catalog data, or the My List tab.
- Filter facets other than genre/category (no source or year filter).
- Multi-select genre filter (one genre at a time).
