# Famous-titles Home Picks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rank the Home screen's "picked" rows by a Bayesian fame score driven by TMDB `vote_count` (instead of raw `vote_average`) for both catalogs, with picks rotating once per day from a famous-titles pool.

**Architecture:** Add `vote_count` + `popularity` to the catalog data (one-time TMDB enrichment), parse them into `TmdbData`, compute a denoised `fameScore` on `ContentItem`, and select/sort the Home pools through a pure `fame_ranking.dart` helper. The model falls back to `vote_average` when the new fields are absent, so code ships independently of data.

**Tech Stack:** Flutter/Dart (Riverpod UI), `flutter_test`, Python 3 + `requests` for the offline TMDB enrichment scripts.

**Spec:** `docs/superpowers/specs/2026-06-16-famous-home-picks-design.md`

---

## File Structure

- **Modify** `lib/models/content_item.dart` — `TmdbData` gains `voteCount`/`popularity`; `ContentItem` gains fame tuning constants + `weightedRating`/`isFamous`/`fameScore` getters; the old `popularity` getter is removed.
- **Create** `lib/services/fame_ranking.dart` — pure, testable pool selection + comparator (`compareByFame`, `famousPool<T>`).
- **Modify** `lib/services/catalog_service.dart` — pool methods delegate to `fame_ranking.dart`.
- **Modify** `lib/models/stardima_adapter.dart` — read an enriched `tmdb` block when present (vote fields), keeping `category`-as-genre.
- **Modify** `lib/screens/home_screen.dart` — "Most Popular" row daily-rotates from the famous pool; genre sort uses `fameScore`.
- **Modify** `scrapping_scripts/arabictoons_scraping_tools/enrich_tmdb.py` — persist `vote_count` + `popularity` in the TMDB block.
- **Create** `scrapping_scripts/arabictoons_scraping_tools/enrich_extra.py` — light pass (Arabic Toons: add vote fields by id) + full match pass (Stardima: build tmdb blocks).
- **Create** `test/fame_ranking_test.dart` — fame getters + pool selection.
- **Modify** `test/catalog_parse_smoke_test.dart` — assert enriched fields survive parsing (Stardima).

**Out of scope (do not change):** Arabic Toons `genres`/`overview_*` parsing currently reads top-level keys that the bundled file nests under `ar`/`en`; that pre-existing gap is unrelated to this work. Leave playback, search, and browse untouched.

---

### Task 1: TmdbData gains vote_count + popularity

**Files:**
- Modify: `lib/models/content_item.dart:106-141` (the `TmdbData` class)
- Test: `test/fame_ranking_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/fame_ranking_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/models/content_item.dart';

void main() {
  group('TmdbData parsing', () {
    test('parses vote_count and popularity when present', () {
      final t = TmdbData.fromJson({
        'vote_average': 8.7,
        'vote_count': 5350,
        'popularity': 46.6875,
      });
      expect(t.voteAverage, 8.7);
      expect(t.voteCount, 5350);
      expect(t.popularity, 46.6875);
    });

    test('leaves vote_count and popularity null when absent', () {
      final t = TmdbData.fromJson({'vote_average': 8.7});
      expect(t.voteCount, isNull);
      expect(t.popularity, isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/fame_ranking_test.dart`
Expected: FAIL — `The getter 'voteCount' isn't defined for the type 'TmdbData'`.

- [ ] **Step 3: Add the fields**

In `lib/models/content_item.dart`, in `TmdbData`, add two fields next to `voteAverage` (after line 116/`final double? voteAverage;`):

```dart
  /// Total TMDB rating count — the best "is this famous" proxy. Internal only.
  final int? voteCount;

  /// TMDB trending score. Internal ranking signal only; never displayed.
  final double? popularity;
```

Add them to the const constructor parameter list (after `this.voteAverage,`):

```dart
    this.voteCount,
    this.popularity,
```

And to `fromJson` (after the `voteAverage:` line):

```dart
        voteCount: (j['vote_count'] as num?)?.toInt(),
        popularity: (j['popularity'] as num?)?.toDouble(),
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/fame_ranking_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/models/content_item.dart test/fame_ranking_test.dart
git commit -m "feat: parse TMDB vote_count + popularity into TmdbData"
```

---

### Task 2: ContentItem fame getters

**Files:**
- Modify: `lib/models/content_item.dart:188-194` (the `ContentItem` getters)
- Test: `test/fame_ranking_test.dart`

- [ ] **Step 1: Write the failing test**

Append to `test/fame_ranking_test.dart` (add a `Movie` builder helper at top of `main` body and a new group):

```dart
Movie _movie({double? voteAverage, int? voteCount, double? popularity}) => Movie(
      id: 'm',
      title: 't',
      thumbnailUrl: '',
      description: '',
      tmdb: (voteAverage == null && voteCount == null && popularity == null)
          ? null
          : TmdbData(
              voteAverage: voteAverage,
              voteCount: voteCount,
              popularity: popularity,
            ),
      pageUrl: '',
      servers: const [],
    );
```

```dart
  group('fame getters', () {
    test('weightedRating denoises a tiny-sample 10.0', () {
      // v=2, R=10, m=50, C=7 -> ~7.12 (pulled toward the mean)
      final wr = _movie(voteAverage: 10, voteCount: 2).weightedRating;
      expect(wr, closeTo(7.12, 0.05));
    });

    test('weightedRating keeps a high-count rating near its value', () {
      final wr = _movie(voteAverage: 8.7, voteCount: 5350).weightedRating;
      expect(wr, closeTo(8.68, 0.05));
    });

    test('weightedRating falls back to raw vote_average pre-enrichment', () {
      expect(_movie(voteAverage: 8).weightedRating, 8.0); // voteCount null
    });

    test('isFamous requires the vote_count floor', () {
      expect(_movie(voteAverage: 9, voteCount: 5000).isFamous, isTrue);
      expect(_movie(voteAverage: 10, voteCount: 2).isFamous, isFalse);
      expect(_movie(voteAverage: 9).isFamous, isFalse); // no vote_count
    });

    test('fameScore is vote_count when known, else weighted rating', () {
      expect(_movie(voteAverage: 8.7, voteCount: 5350).fameScore, 5350.0);
      expect(_movie(voteAverage: 8).fameScore, 8.0);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/fame_ranking_test.dart`
Expected: FAIL — `The getter 'weightedRating' isn't defined for the type 'Movie'`.

- [ ] **Step 3: Add constants + getters**

In `lib/models/content_item.dart`, add the tuning constants at top-level (just below the imports, before `class ServerSource`):

```dart
/// Internal fame-ranking tuning (never displayed). `kFameMeanVote` is the prior
/// mean rating (C), `kFameBayesPrior` the prior weight in votes (m), and
/// `kFameVoteFloor` the minimum vote_count for a title to enter the curated
/// "famous" Home pools.
const double kFameMeanVote = 7.0;
const double kFameBayesPrior = 50.0;
const int kFameVoteFloor = 20;
```

In the `ContentItem` sealed class, **replace** the existing `popularity` getter (the doc comment at 191-193 plus `double get popularity => tmdb?.voteAverage ?? 0;`) with:

```dart
  /// Raw TMDB rating count (internal). Null until the catalog is enriched.
  int? get voteCount => tmdb?.voteCount;

  /// TMDB trending score (internal tiebreak). Null until enriched.
  double? get tmdbPopularity => tmdb?.popularity;

  /// Bayesian weighted rating — denoises tiny-sample vote_averages (a 1–2 vote
  /// 10.0 gets pulled toward the catalog mean). Falls back to the raw
  /// vote_average when vote_count is unknown (pre-enrichment).
  double get weightedRating {
    final v = tmdb?.voteCount;
    final r = tmdb?.voteAverage ?? 0;
    if (v == null) return r;
    return (v / (v + kFameBayesPrior)) * r +
        (kFameBayesPrior / (v + kFameBayesPrior)) * kFameMeanVote;
  }

  /// Eligible for the curated "famous" Home pools.
  bool get isFamous => (tmdb?.voteCount ?? 0) >= kFameVoteFloor;

  /// Primary fame ranking scalar (higher = more famous). Uses vote_count when
  /// known — a title everyone watched accrues many votes — else the denoised
  /// rating so an un-enriched catalog still orders sensibly.
  double get fameScore {
    final v = tmdb?.voteCount;
    return v != null ? v.toDouble() : weightedRating;
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/fame_ranking_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Commit**

```bash
git add lib/models/content_item.dart test/fame_ranking_test.dart
git commit -m "feat: fameScore/weightedRating/isFamous on ContentItem"
```

---

### Task 3: Pure fame-ranking pool helper

**Files:**
- Create: `lib/services/fame_ranking.dart`
- Test: `test/fame_ranking_test.dart`

- [ ] **Step 1: Write the failing test**

Append to `test/fame_ranking_test.dart`:

```dart
  group('famousPool', () {
    test('keeps only floor-clearing items, ordered by fame desc', () {
      final a = _movie(voteAverage: 8, voteCount: 5000);
      final b = _movie(voteAverage: 9, voteCount: 100);
      final c = _movie(voteAverage: 10, voteCount: 2); // below floor
      final d = _movie(voteAverage: 9); // no vote_count
      final pool = famousPool([c, b, a, d]);
      expect(pool, [a, b]); // 5000 then 100; c & d dropped
    });

    test('breaks fame ties by tmdb popularity', () {
      final a = _movie(voteAverage: 8, voteCount: 100, popularity: 5);
      final b = _movie(voteAverage: 8, voteCount: 100, popularity: 50);
      expect(famousPool([a, b]), [b, a]);
    });

    test('falls back to weighted rating when nothing is famous', () {
      final a = _movie(voteAverage: 8); // no vote_count -> WR 8
      final b = _movie(voteAverage: 9); // WR 9
      final z = _movie(); // no tmdb -> WR 0, dropped from fallback
      expect(famousPool([a, b, z]), [b, a]);
    });

    test('returns all items when there is no signal at all', () {
      final a = _movie();
      final b = _movie();
      expect(famousPool([a, b]).length, 2);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/fame_ranking_test.dart`
Expected: FAIL — `The function 'famousPool' isn't defined` / missing import.

Add the import at the top of `test/fame_ranking_test.dart`:

```dart
import 'package:kartoonia/services/fame_ranking.dart';
```

- [ ] **Step 3: Create the helper**

Create `lib/services/fame_ranking.dart`:

```dart
import '../models/content_item.dart';

/// Pure ranking helpers for the Home "picked" rows. Kept separate from
/// CatalogService so the selection/ordering logic is unit-testable without any
/// asset I/O.

/// Sort comparator: most famous first, breaking ties by TMDB trending score.
int compareByFame(ContentItem a, ContentItem b) {
  final c = b.fameScore.compareTo(a.fameScore);
  if (c != 0) return c;
  return (b.tmdbPopularity ?? 0).compareTo(a.tmdbPopularity ?? 0);
}

/// The curated famous pool for [items], highest fame first.
///
/// Primary path: titles clearing the vote-count floor, sorted by fame. If none
/// clear it (e.g. a catalog not yet enriched), fall back to anything with a
/// positive weighted rating; if even that is empty, return the items as-is so
/// rows never render blank.
List<T> famousPool<T extends ContentItem>(List<T> items) {
  final famous = items.where((i) => i.isFamous).toList()..sort(compareByFame);
  if (famous.isNotEmpty) return famous;

  final rated = items.where((i) => i.weightedRating > 0).toList()
    ..sort((a, b) => b.weightedRating.compareTo(a.weightedRating));
  return rated.isNotEmpty ? rated : List<T>.of(items);
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/fame_ranking_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Commit**

```bash
git add lib/services/fame_ranking.dart test/fame_ranking_test.dart
git commit -m "feat: pure famousPool selection + compareByFame helper"
```

---

### Task 4: CatalogService delegates to famousPool

**Files:**
- Modify: `lib/services/catalog_service.dart:68-107`
- Test: covered by `test/fame_ranking_test.dart` (unit) + `test/catalog_parse_smoke_test.dart` (integration, unchanged)

- [ ] **Step 1: Add the import**

At the top of `lib/services/catalog_service.dart`, add:

```dart
import 'fame_ranking.dart';
```

- [ ] **Step 2: Replace the popularity-based pool methods**

Replace the block from `popularPool()` through `popularMovies()` (lines 69-86) with:

```dart
  /// Curated famous pool (denoised), highest fame first.
  List<ContentItem> popularPool() => famousPool(all);

  List<Show> popularShows() => famousPool(shows);

  List<Movie> popularMovies() => famousPool(movies);
```

The remaining methods (`mostPopular`, `getFeaturedPool`, `getTop10Pool`, etc.) already call these and need no change — confirm `getFeaturedPool()` still reads `popularPool().where((i) => i.tmdb?.backdropUrl != null)`.

- [ ] **Step 3: Run the full Dart test suite**

Run: `flutter test`
Expected: PASS — including `test/catalog_parse_smoke_test.dart` (bundled catalogs still parse) and `test/fame_ranking_test.dart`.

- [ ] **Step 4: Static analysis (catch the removed `popularity` getter)**

Run: `flutter analyze`
Expected: No errors. If `home_screen.dart:156` still references `.popularity`, it will be flagged — fixed in Task 6.

> Note: `flutter analyze` will report the `.popularity` reference in `home_screen.dart` until Task 6. That single error is expected here; everything else must be clean.

- [ ] **Step 5: Commit**

```bash
git add lib/services/catalog_service.dart
git commit -m "refactor: rank catalog pools via famousPool"
```

---

### Task 5: Stardima adapter reads enriched tmdb block

**Files:**
- Modify: `lib/models/stardima_adapter.dart:29-44`
- Test: `test/fame_ranking_test.dart`

- [ ] **Step 1: Write the failing test**

Append to `test/fame_ranking_test.dart`:

```dart
  group('StardimaAdapter enrichment', () {
    test('reads vote_count/popularity from an enriched tmdb block', () {
      final (_, movies) = StardimaAdapter.parse({
        'movies': [
          {
            'id': '1',
            'title': 'Famous Toon',
            'poster_url': 'p.jpg',
            'backdrop_url': 'b.jpg',
            'year': '2011',
            'category': 'Comedy',
            'play_url': 'http://x',
            'tmdb': {
              'vote_average': 8.7,
              'vote_count': 5350,
              'popularity': 46.6,
            },
          }
        ],
        'tvshows': const [],
      });
      final m = movies.single;
      expect(m.voteCount, 5350);
      expect(m.tmdbPopularity, 46.6);
      expect(m.isFamous, isTrue);
      expect(m.categories, ['Comedy']); // category still drives genres
    });

    test('items without a tmdb block stay non-famous', () {
      final (_, movies) = StardimaAdapter.parse({
        'movies': [
          {'id': '2', 'title': 'Obscure', 'poster_url': 'p', 'play_url': 'u'}
        ],
        'tvshows': const [],
      });
      expect(movies.single.isFamous, isFalse);
    });
  });
```

Add the import at the top of the test file:

```dart
import 'package:kartoonia/models/stardima_adapter.dart';
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/fame_ranking_test.dart`
Expected: FAIL — `voteCount` is `null` (adapter ignores the enriched block).

- [ ] **Step 3: Read the enriched block in `_tmdb`**

Replace `StardimaAdapter._tmdb` (lines 29-37) with:

```dart
  static TmdbData _tmdb(Map<String, dynamic> raw) {
    final t = raw['tmdb'];
    final e = t is Map ? t.cast<String, dynamic>() : null;
    return TmdbData(
      // Stardima already serves correctly-sized TMDB images; expose the poster
      // as the w500 variant the card getter prefers, and the backdrop as-is.
      posterUrlW500: _str(e?['poster_url_w500']) ?? _str(raw['poster_url']),
      posterUrl: _str(e?['poster_url']) ?? _str(raw['poster_url']),
      backdropUrl: _str(e?['backdrop_url']) ?? _str(raw['backdrop_url']),
      year: int.tryParse(_str(raw['year']) ?? '') ??
          (e?['year'] as num?)?.toInt(),
      // Keep the single source `category` as the item's genre (filter rail).
      genres: _category(raw),
      voteAverage: (e?['vote_average'] as num?)?.toDouble(),
      voteCount: (e?['vote_count'] as num?)?.toInt(),
      popularity: (e?['popularity'] as num?)?.toDouble(),
    );
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/fame_ranking_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/models/stardima_adapter.dart test/fame_ranking_test.dart
git commit -m "feat: Stardima adapter reads enriched TMDB vote fields"
```

---

### Task 6: Home "Most Popular" daily rotation + genre sort

**Files:**
- Modify: `lib/screens/home_screen.dart:85-94` and `:156`

- [ ] **Step 1: Make the Most Popular row daily-rotate from the famous pool**

Replace the "Most Popular" block (lines 85-94) with:

```dart
    // Most Popular — a daily-rotating sample of the famous pool, so the row
    // shows a different slice of well-known titles each day.
    final mostPopular =
        dailyShuffled(catalog.popularPool().take(80).toList(), salt: 'most')
            .take(30)
            .toList();
    rows.add(ContentRow(
      title: t['most_popular']!,
      count: mostPopular.length,
      cards: [
        for (final i in mostPopular)
          PosterCard(item: i, movieLabel: t['movie']!, onPressed: () => open(i)),
      ],
    ));
```

- [ ] **Step 2: Update the genre-row sort**

At line 156, change the sort key from `popularity` to `fameScore`:

```dart
      final byPop = entry.value.toList()
        ..sort((a, b) => b.fameScore.compareTo(a.fameScore));
```

- [ ] **Step 3: Verify analysis is now fully clean**

Run: `flutter analyze`
Expected: No errors (the `.popularity` reference is gone).

- [ ] **Step 4: Run the full suite**

Run: `flutter test`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/home_screen.dart
git commit -m "feat: daily-rotating Most Popular row + fame-sorted genre rows"
```

---

### Task 7: Persist vote_count + popularity in enrich_tmdb.py

**Files:**
- Modify: `scrapping_scripts/arabictoons_scraping_tools/enrich_tmdb.py:329-344` (the `build_tmdb_block` return dict)

- [ ] **Step 1: Add the two fields to the returned block**

In `build_tmdb_block`, in the returned dict, add after the `"vote_average": ...,` line:

```python
        "vote_count": en_d.get("vote_count", res.get("vote_count")),
        "popularity": en_d.get("popularity", res.get("popularity")),
```

- [ ] **Step 2: Sanity-check the script still imports**

Run: `python -c "import importlib.util,sys; spec=importlib.util.spec_from_file_location('e','scrapping_scripts/arabictoons_scraping_tools/enrich_tmdb.py'); m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m); print('build_tmdb_block' in dir(m))"`
Expected: prints `True` (module loads, function present; `main()` is guarded so nothing runs).

- [ ] **Step 3: Commit**

```bash
git add scrapping_scripts/arabictoons_scraping_tools/enrich_tmdb.py
git commit -m "feat: enrich_tmdb persists vote_count + popularity"
```

---

### Task 8: enrich_extra.py — light (Arabic Toons) + full (Stardima) passes

**Files:**
- Create: `scrapping_scripts/arabictoons_scraping_tools/enrich_extra.py`

- [ ] **Step 1: Create the script**

Create `scrapping_scripts/arabictoons_scraping_tools/enrich_extra.py`:

```python
#!/usr/bin/env python3
"""
Add fame signals (vote_count + popularity) to a catalog.

Two modes (chosen by --catalog):

  arabictoons : LIGHT pass. Items already have a matched `tmdb` block with a
                `tmdb_id`; fetch /{type}/{id} once and fill in vote_count +
                popularity. No re-matching, no image refetch.

  stardima    : FULL pass. Items have NO tmdb at all; match each title+year to
                TMDB (reusing enrich_tmdb's Arabic cleaning/alias/search) and
                build a full tmdb block (which now includes vote_count +
                popularity via enrich_tmdb.build_tmdb_block).

Resumable: saves every 25 items; rerun to continue. Reuses the TMDB key
resolution from enrich_tmdb (tmdb_key.txt / TMDB_TOKEN / TMDB_API_KEY / --key).

Usage:
  python enrich_extra.py --catalog arabictoons --input ../../assets/arabictoons_catalog.json
  python enrich_extra.py --catalog stardima    --input ../../assets/stardima_catalog.json
"""

import os
import sys
import json
import time
import argparse

import enrich_tmdb as E  # reuse session/key/search/build helpers


def save(cat, path):
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(cat, f, ensure_ascii=False, indent=2)
    for _ in range(8):
        try:
            os.replace(tmp, path)
            return
        except PermissionError:
            time.sleep(0.5)


def light_arabictoons(session, cat):
    """Fill vote_count + popularity on already-matched items."""
    items = [("tv", s) for s in cat.get("shows", [])] + \
            [("movie", m) for m in cat.get("movies", [])]
    todo = [(k, it) for k, it in items
            if isinstance(it.get("tmdb"), dict)
            and it["tmdb"].get("tmdb_id")
            and "vote_count" not in it["tmdb"]]
    print(f"arabictoons: {len(items)} items, {len(todo)} need vote_count.")
    done = 0
    for kind, it in todo:
        t = it["tmdb"]
        d = E.api_get(session, f"/{t.get('type', kind)}/{t['tmdb_id']}",
                      language="en") or {}
        t["vote_count"] = d.get("vote_count")
        t["popularity"] = d.get("popularity")
        time.sleep(E.SLEEP)
        done += 1
        if done % 25 == 0:
            save(cat, PATH)
            print(f"  [{done}/{len(todo)}]")
    return done


def full_stardima(session, cat):
    """Build tmdb blocks (with vote_count/popularity) for unmatched items."""
    items = [("movie", m) for m in cat.get("movies", [])] + \
            [("tv", s) for s in cat.get("tvshows", [])]
    todo = [(k, it) for k, it in items if not it.get("tmdb")]
    print(f"stardima: {len(items)} items, {len(todo)} to match.")
    matched = done = 0
    for kind, it in todo:
        res, conf, q = E.search_best(session, it, kind)
        if res and conf >= E.MIN_CONFIDENCE and res.get("poster_path"):
            it["tmdb"] = E.build_tmdb_block(session, res, kind, conf, q)
            matched += 1
        else:
            it["tmdb"] = None
        done += 1
        if done % 25 == 0:
            save(cat, PATH)
            print(f"  [{done}/{len(todo)}] matched={matched}")
    return matched


def main():
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    p = argparse.ArgumentParser()
    p.add_argument("--catalog", required=True, choices=["arabictoons", "stardima"])
    p.add_argument("--input", required=True)
    p.add_argument("--key", default=None)
    args, _ = p.parse_known_args()

    key = E.get_key()
    if not key:
        print("No TMDB key found (tmdb_key.txt / TMDB_TOKEN / TMDB_API_KEY / --key).")
        sys.exit(1)
    session = E.make_session(key)
    if not E.api_get(session, "/configuration"):
        print("Could not reach TMDB / key invalid.")
        sys.exit(1)
    print("TMDB key OK.")

    global PATH
    PATH = args.input
    cat = json.load(open(PATH, encoding="utf-8"))

    if args.catalog == "arabictoons":
        n = light_arabictoons(session, cat)
        save(cat, PATH)
        print(f"Done. filled vote_count on {n} items -> {PATH}")
    else:
        n = full_stardima(session, cat)
        save(cat, PATH)
        print(f"Done. matched {n} Stardima items -> {PATH}")


if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Verify it imports cleanly (no run)**

Run: `python -c "import importlib.util; s=importlib.util.spec_from_file_location('x','scrapping_scripts/arabictoons_scraping_tools/enrich_extra.py'); m=importlib.util.module_from_spec(s); s.loader.exec_module(m); print('ok')"`
Expected: prints `ok` (imports `enrich_tmdb`, defines functions; `main()` guarded).

- [ ] **Step 3: Commit**

```bash
git add scrapping_scripts/arabictoons_scraping_tools/enrich_extra.py
git commit -m "feat: enrich_extra (vote_count light pass + Stardima match pass)"
```

---

### Task 9: Run the enrichment passes (one-time data update)

**Files:**
- Modify (data): `assets/arabictoons_catalog.json`, `assets/stardima_catalog.json`

> The TMDB key already lives in `scrapping_scripts/arabictoons_scraping_tools/tmdb_key.txt` (gitignored). These commands hit the live TMDB API and are resumable — rerun if interrupted.

- [ ] **Step 1: Arabic Toons light pass**

Run:
```bash
cd scrapping_scripts/arabictoons_scraping_tools
python enrich_extra.py --catalog arabictoons --input ../../assets/arabictoons_catalog.json
```
Expected: `arabictoons: ~1210 items, ~800 need vote_count.` then progress to `Done. filled vote_count on N items`.

- [ ] **Step 2: Verify the famous titles now surface (Arabic Toons)**

Run (from repo root):
```bash
python - <<'PY'
import json
d=json.load(open('assets/arabictoons_catalog.json',encoding='utf-8'))
items=[it for it in d['shows']+d['movies'] if isinstance(it.get('tmdb'),dict) and it['tmdb'].get('vote_count')]
items.sort(key=lambda it: it['tmdb']['vote_count'], reverse=True)
print('with vote_count:', len(items))
for it in items[:15]:
    t=it['tmdb']; print(f"  {t['vote_count']:>6}  va={t.get('vote_average')}  {t.get('original_title')}")
PY
```
Expected: top entries are high-vote-count mainstream titles (thousands of votes), NOT the old 1–2 vote `10.0` items.

- [ ] **Step 3: Stardima full match pass**

Run:
```bash
cd scrapping_scripts/arabictoons_scraping_tools
python enrich_extra.py --catalog stardima --input ../../assets/stardima_catalog.json
```
Expected: `stardima: 1765 items, 1765 to match.` then progress with `matched=...`; final `Done. matched M Stardima items` (M roughly 900–1200).

- [ ] **Step 4: Verify Stardima now has fame signals**

Run (from repo root):
```bash
python - <<'PY'
import json
d=json.load(open('assets/stardima_catalog.json',encoding='utf-8'))
items=[it for it in d['movies']+d['tvshows'] if isinstance(it.get('tmdb'),dict) and it['tmdb'].get('vote_count')]
items.sort(key=lambda it: it['tmdb']['vote_count'], reverse=True)
print('matched with vote_count:', len(items))
for it in items[:15]:
    t=it['tmdb']; print(f"  {t['vote_count']:>6}  {it.get('title')}")
PY
```
Expected: a few hundred+ matched items; top entries are well-known titles.

- [ ] **Step 5: Confirm the app parses the enriched catalogs**

Run: `flutter test test/catalog_parse_smoke_test.dart`
Expected: PASS (both catalogs parse; no schema breakage).

- [ ] **Step 6: Commit the enriched data**

```bash
git add assets/arabictoons_catalog.json assets/stardima_catalog.json
git commit -m "data: enrich catalogs with TMDB vote_count + popularity"
```

---

### Task 10: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Full test suite**

Run: `flutter test`
Expected: PASS (all suites).

- [ ] **Step 2: Static analysis**

Run: `flutter analyze`
Expected: No issues.

- [ ] **Step 3: End-to-end pool spot check**

Run (from repo root) to confirm `popularPool` ordering picks famous titles for Arabic Toons:
```bash
python - <<'PY'
import json
d=json.load(open('assets/arabictoons_catalog.json',encoding='utf-8'))
def vc(it): 
    t=it.get('tmdb'); return (t or {}).get('vote_count') or 0
fam=[it for it in d['shows']+d['movies'] if vc(it)>=20]
fam.sort(key=vc,reverse=True)
print(f"famous pool size (vote_count>=20): {len(fam)}")
print("top 10 by fame:")
for it in fam[:10]:
    print("  ", vc(it), it['tmdb'].get('original_title'))
PY
```
Expected: a healthy pool (dozens–hundreds) led by recognizable titles. If the pool is tiny (<20), lower `kFameVoteFloor` in `content_item.dart` and the `>=20` filter here, re-run Tasks 6/10.

- [ ] **Step 4: Final confirmation**

Confirm: model + service + UI committed, both catalogs enriched and committed, `flutter test` and `flutter analyze` clean. The feature is complete.
```
```
