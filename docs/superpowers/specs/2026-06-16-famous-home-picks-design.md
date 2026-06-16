# Famous-titles home picks — design

**Date:** 2026-06-16
**Status:** Approved (pending spec review)
**Applies to:** both catalogs — Arabic Toons and Stardima

## Problem

Every "picked" row on the Home screen — Most Popular, Popular Now, Top 10,
In the Spotlight, New Episodes, genre rows, and the hero carousel — is ranked by
a single field: TMDB `vote_average`, stored on `ContentItem.popularity`. That
field is a poor popularity signal:

- The current top picks (`Les Ailes du Dragon`, `火麟飞`, `Groove High`,
  `O Leiteiro`, …) all sit at `vote_average = 10.0`, which almost always means
  **1–2 votes on an obscure title**, not real popularity.
- 478 of ~1,210 Arabic Toons titles have `vote_average = 0` (no signal at all).
- Genuinely famous titles (Gumball, Disney films, Cartoon Network shows) carry
  *moderate* averages (7–8) but **thousands of votes**, so they get buried.

The catalog stores `tmdb_id`, English `original_title`, `year`, and genres, but
**not** the two fields that actually measure fame: TMDB's real `popularity`
(trending) and `vote_count`.

### Validation (real TMDB data, 2026-06-16)

| Title                         | vote_average | vote_count | popularity |
|-------------------------------|--------------|------------|------------|
| The Amazing World of Gumball  | 8.7          | 5,350      | 46.7       |
| The Lion King (2019)          | 7.1          | 10,752     | 11.4       |
| "Ski Heroes" (current #1 pick)| 0.0          | 0          | 0.03       |

`vote_count` cleanly separates the famous from the noise.

## Goals

1. Home "picked" rows surface genuinely famous/classic cartoons (mainstream hits
   like Gumball, Disney films, Cartoon Network shows, and long-running classics)
   for **both** catalogs.
2. Fully automatic, data-driven ranking — **no hand-maintained title lists**.
3. The picks rotate **once per day** so Home shows a different slice each day.

## Non-goals

- No per-open reshuffle (daily cadence chosen).
- No manual/editorial "classics" allowlist.
- No change to playback, search semantics, or browse/A–Z behavior.
- `vote_average`, `vote_count`, and `popularity` remain **internal**; never shown
  in the UI.

## Approach

The fix is primarily in the **data** plus the **ranking function**. The UI layout
does not change.

### 1. Data enrichment (one-time, automatic)

Persist the two fame fields onto each TMDB block:

- `vote_count` — best "is this famous" proxy.
- `popularity` — TMDB trending score (secondary signal / tiebreak).

**Arabic Toons** (`assets/arabictoons_catalog.json`): ~800 items already have a
matched `tmdb` block with `tmdb_id`. A lightweight pass fetches
`/{tv|movie}/{tmdb_id}` once per item and adds `vote_count` + `popularity`. No
re-matching, no image refetch. Items whose `tmdb` is `null` are left as-is.

**Stardima** (`assets/stardima_catalog.json`): has **no** TMDB data at all
(0 / 1,765). It needs the full matching pass (Arabic title + year → TMDB search →
best match), reusing the Arabic-title cleaning + alias logic already in
`enrich_tmdb.py`. Each matched item gets a `tmdb` block including `vote_count` and
`popularity`. Expected match rate ≈ 50–70%; unmatched items keep their scraped
poster/metadata and simply fall out of the famous pool.

Key handling: TMDB v4 token lives in
`scrapping_scripts/arabictoons_scraping_tools/tmdb_key.txt`, which is
**gitignored** and must never be committed.

### 2. Fame score (ranking)

Replace the raw `vote_average` sort with a **Bayesian weighted rating** that
denoises the 1-vote = 10.0 problem:

```
WR = (v / (v + m)) * R + (m / (v + m)) * C
```

where `v` = vote_count, `R` = vote_average, `C` = catalog mean vote (~7),
`m` = a vote floor (titles with few votes get pulled toward the mean).

The **famous pool** is then: items above a `vote_count` floor, ordered by fame.
Primary ordering is by `vote_count` (fame), with `WR` as a quality gate so a
famous-but-poorly-rated title can't dominate, and `popularity` as a final
tiebreak. Concrete thresholds (`m`, `C`, vote floor) are tunable constants
chosen during implementation against the real distribution.

Items below the floor (1–2 votes, or `vote_count = 0`, or no `tmdb`) are
**excluded from the picked pools** but remain fully searchable and visible in
genre/browse rows (genre rows must never go empty).

### 3. Model + catalog changes

- `TmdbData`: add optional `voteCount` (`vote_count`) and `tmdbPopularity`
  (`popularity`), parsed defensively (absent → `null`).
- `ContentItem`: replace `popularity` getter with a `fameScore` getter computed
  from `voteCount` + `vote_average` (Bayesian WR). When `voteCount` is absent,
  `fameScore` **falls back to `vote_average`** so the app behaves exactly as
  today until enrichment runs.
- `CatalogService`: `popularPool`, `popularShows`, `popularMovies`,
  `getFeaturedPool`, `getTop10Pool`, `mostPopular`, and genre-row sorting all
  rank by `fameScore` and apply the vote floor to the picked pools.

### 4. Home screen behavior (daily rotation)

Cadence stays **once per day** (the app already daily-shuffles most rows via
`dailyShuffled`). The change is *what they draw from*:

- **"Most Popular"** is currently a static top-30 (`mostPopular`, unshuffled).
  Make it a daily-rotating sample drawn from a larger famous pool, so it varies
  day to day like the other rows.
- All picked rows draw from the new `fameScore`-ranked famous pool, so each day
  presents a different slice of genuinely-known titles.

No layout, card, or navigation changes.

### 5. Graceful degradation / rollout

Because the new fields are optional and `fameScore` falls back to
`vote_average`, the **code change ships independently of the data**. Order:

1. Land model + catalog + home changes (fallback keeps current behavior).
2. Run Arabic Toons enrichment pass → famous picks improve immediately.
3. Run Stardima matching pass → Stardima picks improve.

Nothing breaks if a title never receives a `vote_count`.

## Testing

- **Pure-function unit tests** (no I/O), the existing test style:
  - `fameScore`: 1-vote-10.0 noise ranks below a 5,000-vote 8.0 title; absent
    `voteCount` falls back to `vote_average`; `vote_count = 0` is filtered.
  - Catalog pools: famous pool excludes below-floor items; genre rows still
    return all items even when none clear the floor.
  - Daily rotation: `mostPopular`/picked rows produce a deterministic but
    date-dependent ordering (same within a day, differs across days).
- **Enrichment scripts**: validated by re-running against a handful of known
  titles (Gumball, Lion King) and asserting `vote_count`/`popularity` are
  written; full runs are manual/one-time, not CI.

## Risks / open questions

- Stardima Arabic-title match rate is uncertain (≈50–70%); unmatched titles stay
  out of picks. Acceptable per "automatic, no manual lists."
- Thresholds (`m`, floor) need one tuning pass against the real vote_count
  distribution after enrichment; pick conservative defaults first.
- Enrichment runtime: Stardima full pass is ~1,765 items × a few API calls;
  resumable via the existing every-N-items save.
