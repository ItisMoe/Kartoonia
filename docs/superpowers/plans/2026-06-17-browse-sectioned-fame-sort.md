# Browse: Sectioned + Fame-Sorted TV / Movies — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Movies and TV tabs surface known/classic titles first — a Home-style sectioned view by default and a flat fame-sorted grid whenever a letter or genre filter is active.

**Architecture:** Add pure, unit-tested ranking/grouping helpers to `fame_ranking.dart`, then drive `BrowseScreen` from `BrowseState` (`letter` + the already-present `category`) to pick between a sectioned render (reusing Home's `ContentRow`/`PosterCard`/`Top10Card`) and a flat `sortedForBrowse` grid. A filter button opens a D-pad genre picker that sets `category`.

**Tech Stack:** Flutter, Riverpod (Notifier providers), Dart `flutter_test`.

## Global Constraints

- TMDB signals (`vote_average`, `vote_count`, `popularity`) are **internal ranking only** — never rendered in the UI.
- Arabic-first, RTL by default; every new user-facing string is added to **both** the `en` and `ar` blocks of `lib/i18n/strings.dart`.
- Ranking helpers that touch no assets live in `lib/services/fame_ranking.dart` and are unit-tested without asset I/O.
- The **My List** tab is unchanged.
- Filter is **genre/category only**, **one genre at a time**.
- Letter and category **combine** (both applied → still a flat fame-sorted grid).
- Mode predicate (non-My-List tabs): sectioned when `letter == null && category == null`; flat grid otherwise.

---

### Task 1: `sortedForBrowse` ranking helper

Keeps every title (a browse list must show all of them) and orders known-first
without the vote_count-vs-rating scale-mixing that `compareByFame` warns about:
enriched titles (TMDB `vote_count` known) lead by `vote_count` desc, then the
rest by `weightedRating` desc, ties broken by title for day-to-day stability.

**Files:**
- Modify: `lib/services/fame_ranking.dart`
- Test: `test/fame_ranking_test.dart`

**Interfaces:**
- Consumes: `ContentItem.voteCount` (`int?`), `ContentItem.weightedRating` (`double`), `ContentItem.title` (`String`).
- Produces: `List<T> sortedForBrowse<T extends ContentItem>(List<T> items)`.

- [ ] **Step 1: Write the failing tests**

Add this group to the end of `main()` in `test/fame_ranking_test.dart` (the
`movie(...)` helper already exists at the top of the file):

```dart
  group('sortedForBrowse', () {
    test('enriched titles lead, ordered by vote_count desc', () {
      final a = movie(voteAverage: 7, voteCount: 100);
      final b = movie(voteAverage: 7, voteCount: 5000);
      final c = movie(voteAverage: 7, voteCount: 900);
      expect(sortedForBrowse([a, b, c]), [b, c, a]);
    });

    test('any enriched title outranks every un-enriched one', () {
      // vote_count 5 == fameScore 5.0 would lose to a 9.0 rating under
      // compareByFame; sortedForBrowse must still put the enriched title first.
      final enriched = movie(voteAverage: 1, voteCount: 5);
      final unrated = movie(voteAverage: 9);
      expect(sortedForBrowse([unrated, enriched]), [enriched, unrated]);
    });

    test('un-enriched titles fall back to weighted rating desc', () {
      final a = movie(voteAverage: 6);
      final b = movie(voteAverage: 9);
      expect(sortedForBrowse([a, b]), [b, a]);
    });

    test('keeps all items (drops nothing)', () {
      expect(sortedForBrowse([movie(), movie(), movie()]).length, 3);
    });

    test('empty in, empty out', () {
      expect(sortedForBrowse(<Movie>[]), isEmpty);
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/fame_ranking_test.dart`
Expected: FAIL — `The method 'sortedForBrowse' isn't defined`.

- [ ] **Step 3: Implement `sortedForBrowse`**

Append to `lib/services/fame_ranking.dart`:

```dart
/// Browse ordering: every item kept, most-known first.
///
/// Partitions to avoid the vote_count-vs-rating scale mix that [compareByFame]
/// warns about: enriched titles (TMDB vote_count known) lead, ordered by
/// vote_count desc; the rest follow, ordered by denoised
/// [ContentItem.weightedRating] desc. Ties fall back to case-insensitive title
/// order so the grid is stable day-to-day.
List<T> sortedForBrowse<T extends ContentItem>(List<T> items) {
  final enriched = <T>[];
  final rest = <T>[];
  for (final i in items) {
    (i.voteCount != null ? enriched : rest).add(i);
  }
  int byTitle(T a, T b) =>
      a.title.toLowerCase().compareTo(b.title.toLowerCase());
  enriched.sort((a, b) {
    final c = (b.voteCount ?? 0).compareTo(a.voteCount ?? 0);
    return c != 0 ? c : byTitle(a, b);
  });
  rest.sort((a, b) {
    final c = b.weightedRating.compareTo(a.weightedRating);
    return c != 0 ? c : byTitle(a, b);
  });
  return [...enriched, ...rest];
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/fame_ranking_test.dart`
Expected: PASS (all groups).

- [ ] **Step 5: Commit**

```bash
git add lib/services/fame_ranking.dart test/fame_ranking_test.dart
git commit -m "feat: add sortedForBrowse fame ordering helper"
```

---

### Task 2: Type-scoped genre helpers

Mode A builds genre rows from a single type's items (movies-only or shows-only),
and the filter picker needs the genres present in that type. Add two pure
helpers and make the existing `CatalogService` methods delegate to them (DRY).

**Files:**
- Modify: `lib/services/fame_ranking.dart`
- Modify: `lib/services/catalog_service.dart:115-137`
- Test: `test/fame_ranking_test.dart`

**Interfaces:**
- Consumes: `ContentItem.genres` (`List<String>`).
- Produces:
  - `List<String> genresIn(List<ContentItem> items)` — distinct genres, sorted.
  - `List<MapEntry<String, List<ContentItem>>> genreRowsFor(List<ContentItem> items, {int min = 4, int cap = 8})`.

- [ ] **Step 1: Write the failing tests**

Add to the end of `main()` in `test/fame_ranking_test.dart`:

```dart
  group('genre helpers', () {
    Movie withGenres(String id, List<String> g) => Movie(
          id: id,
          title: id,
          thumbnailUrl: '',
          description: '',
          tmdb: TmdbData(genres: g),
          pageUrl: '',
          servers: const [],
        );

    test('genresIn returns distinct genres sorted', () {
      final items = [
        withGenres('1', ['Comedy', 'Action']),
        withGenres('2', ['Action']),
      ];
      expect(genresIn(items), ['Action', 'Comedy']);
    });

    test('genreRowsFor keeps only genres at/above min, capped', () {
      final items = [
        for (var i = 0; i < 4; i++) withGenres('a$i', ['Action']),
        for (var i = 0; i < 3; i++) withGenres('c$i', ['Comedy']),
      ];
      final rows = genreRowsFor(items, min: 4);
      expect(rows.map((e) => e.key), ['Action']);
      expect(rows.single.value.length, 4);
    });
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/fame_ranking_test.dart`
Expected: FAIL — `genresIn`/`genreRowsFor` not defined.

- [ ] **Step 3: Implement the helpers**

Append to `lib/services/fame_ranking.dart`:

```dart
/// All distinct genres present across [items], sorted alphabetically.
List<String> genresIn(List<ContentItem> items) {
  final set = <String>{};
  for (final i in items) {
    set.addAll(i.genres);
  }
  return set.toList()..sort();
}

/// Genre groupings for [items]: genres with >= [min] items, capped at [cap]
/// rows. Each entry's value is every item in that genre, unsorted (callers
/// rank/shuffle as needed).
List<MapEntry<String, List<ContentItem>>> genreRowsFor(
  List<ContentItem> items, {
  int min = 4,
  int cap = 8,
}) {
  final out = <MapEntry<String, List<ContentItem>>>[];
  for (final g in genresIn(items)) {
    final inGenre = items.where((i) => i.genres.contains(g)).toList();
    if (inGenre.length >= min) out.add(MapEntry(g, inGenre));
    if (out.length >= cap) break;
  }
  return out;
}
```

- [ ] **Step 4: Delegate the existing CatalogService methods (DRY)**

In `lib/services/catalog_service.dart`, replace `getAllGenres()` (lines ~115-122)
and `genreRows()` (lines ~127-137) with delegations. Final state of that region:

```dart
  // ---- Genres ----
  List<String> getAllGenres() => genresIn(all);

  List<ContentItem> byGenre(String genre) =>
      all.where((i) => i.genres.contains(genre)).toList();

  /// Genre rows for Home: genres with >= [min] items, capped at [cap] rows.
  List<MapEntry<String, List<ContentItem>>> genreRows(
          {int min = 4, int cap = 6}) =>
      genreRowsFor(all, min: min, cap: cap);
```

(`fame_ranking.dart` is already imported in `catalog_service.dart`.)

- [ ] **Step 5: Run tests + analyze to verify nothing regressed**

Run: `flutter test test/fame_ranking_test.dart && flutter analyze lib/services/catalog_service.dart`
Expected: tests PASS; analyze reports no new issues.

- [ ] **Step 6: Commit**

```bash
git add lib/services/fame_ranking.dart lib/services/catalog_service.dart test/fame_ranking_test.dart
git commit -m "feat: add type-scoped genre helpers; delegate catalog genre methods"
```

---

### Task 3: Browse screen — sectioned view, fame-sorted grid, genre filter

Rewrite `BrowseScreen` to pick between Mode A (sectioned) and Mode B (flat
fame-sorted grid), add the leading Filter chip + a D-pad genre picker dialog,
and add the two new strings. No widget tests exist in this repo, so this task is
verified with `flutter analyze`, the existing suite, and a manual run.

**Files:**
- Modify: `lib/i18n/strings.dart` (en + ar blocks)
- Modify (full rewrite): `lib/screens/browse_screen.dart`

**Interfaces:**
- Consumes: `sortedForBrowse`, `famousPool`, `genresIn`, `genreRowsFor` (Tasks 1-2); `dailyShuffled(list, salt:)`; `firstLetterFor`, `alphaEn`, `alphaAr`; `browseProvider` notifier methods `setLetter`, `setScript`, `setCategory`; `ContentRow`, `PosterCard`, `Top10Card`.
- Produces: no new exported symbols (screen-internal).

- [ ] **Step 1: Add the two strings to the `en` block**

In `lib/i18n/strings.dart`, after the line `'browse_mylist': 'My List',` add:

```dart
    'browse_filter': 'Filter',
    'filter_all_genres': 'All Genres',
```

- [ ] **Step 2: Add the two strings to the `ar` block**

In `lib/i18n/strings.dart`, after the line `'browse_mylist': 'قائمتي',` add:

```dart
    'browse_filter': 'تصفية',
    'filter_all_genres': 'كل التصنيفات',
```

- [ ] **Step 3: Rewrite `browse_screen.dart`**

Replace the entire contents of `lib/screens/browse_screen.dart` with:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/content_item.dart';
import '../navigation.dart';
import '../services/catalog_service.dart';
import '../services/fame_ranking.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../theme/layout.dart';
import '../utils/daily_shuffle.dart';
import '../utils/genre_translations.dart';
import '../widgets/content_card.dart';
import '../widgets/content_row.dart';
import '../widgets/ensure_visible.dart';
import '../widgets/screen_shell.dart';
import '../widgets/selectable_chip.dart';

/// Browse TV Shows / Movies / My List. Movies and TV each render either a
/// Home-style sectioned view (default "All": no letter, no genre filter) or a
/// flat fame-sorted grid (a letter and/or a genre filter is active, sorted
/// known-first). My List is always a plain grid in its own order.
class BrowseScreen extends ConsumerWidget {
  final String kind; // 'tv' | 'movies' | 'mylist'
  const BrowseScreen({super.key, required this.kind});

  String _navKey() => kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(catalogRevProvider);
    final catalog = ref.watch(catalogProvider);
    final t = ref.watch(stringsProvider);
    final browse = ref.watch(browseProvider);
    final user = ref.watch(userProvider);

    final isMyList = kind == 'mylist';
    final title = kind == 'movies'
        ? t['browse_movies']!
        : isMyList
            ? t['browse_mylist']!
            : t['browse_tv']!;

    List<ContentItem> typeItems;
    if (kind == 'movies') {
      typeItems = catalog.movies;
    } else if (isMyList) {
      typeItems = user.watchlistIds
          .map(catalog.getById)
          .whereType<ContentItem>()
          .toList();
    } else {
      typeItems = catalog.shows;
    }

    final script = browse.alphaScript;
    final letter = browse.letter;
    final category = browse.category;

    // Sectioned (Mode A) only for the default, unfiltered Movies/TV view.
    final sectioned = !isMyList && letter == null && category == null;

    // Genre-filtered base — feeds both the grid and the alpha bar present-set.
    final base = (category == null)
        ? typeItems
        : typeItems.where((i) => i.genres.contains(category)).toList();

    List<ContentItem> shown;
    if (isMyList) {
      shown = typeItems;
    } else if (sectioned) {
      shown = base; // unused for rendering; header count uses typeItems
    } else {
      final filtered = letter == null
          ? base
          : base
              .where((s) => firstLetterFor(s.title, script) == letter)
              .toList();
      shown = sortedForBrowse(filtered);
    }

    void open(ContentItem i) => AppNav.detail(context, i);

    Widget grid(List<ContentItem> list) {
      if (list.isEmpty) {
        return SliverToBoxAdapter(
          child: SizedBox(
            height: 520,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(30)),
                    child: const Icon(Icons.favorite_border,
                        size: 58, color: AppColors.inkMute),
                  ),
                  const SizedBox(height: 22),
                  Text(isMyList ? t['mylist_empty']! : t['noResults']!,
                      style: const TextStyle(
                          fontSize: 25,
                          fontWeight: FontWeight.w700,
                          color: AppColors.inkMute)),
                ],
              ),
            ),
          ),
        );
      }
      return SliverPadding(
        padding: const EdgeInsets.fromLTRB(Spacing.pad, 0, Spacing.pad, 80),
        sliver: SliverGrid(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: Dims.browseCols,
            mainAxisSpacing: 28,
            crossAxisSpacing: 22,
            childAspectRatio: Dims.cardW / Dims.cardH,
          ),
          delegate: SliverChildBuilderDelegate(
            (context, i) => EnsureVisibleOnFocus(
              child: PosterCard(
                item: list[i],
                expand: true,
                autofocus: i == 0,
                movieLabel: t['movie']!,
                onPressed: () => open(list[i]),
              ),
            ),
            childCount: list.length,
          ),
        ),
      );
    }

    // Mode A: Home-style rows for a single type, no hero, daily-rotated.
    List<Widget> sectionRows() {
      final pool = famousPool(typeItems);
      final rows = <Widget>[];

      final mostPopular =
          dailyShuffled(pool.take(80).toList(), salt: 'b_most_$kind')
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

      final popular =
          dailyShuffled(pool.take(60).toList(), salt: 'b_pop_$kind')
              .take(20)
              .toList();
      rows.add(ContentRow(
        title: t['row_popular']!,
        count: popular.length,
        cards: [
          for (final i in popular)
            PosterCard(item: i, movieLabel: t['movie']!, onPressed: () => open(i)),
        ],
      ));

      final top10 =
          dailyShuffled(pool.take(40).toList(), salt: 'b_top_$kind')
              .take(10)
              .toList();
      rows.add(ContentRow(
        title: t['topten']!,
        top10Badge: true,
        cards: [
          for (int i = 0; i < top10.length; i++)
            Top10Card(
                item: top10[i], rank: i + 1, onPressed: () => open(top10[i])),
        ],
      ));

      for (final entry in genreRowsFor(typeItems)) {
        final byFame = entry.value.toList()
          ..sort((a, b) => b.fameScore.compareTo(a.fameScore));
        rows.add(ContentRow(
          title: translateGenre(entry.key),
          count: entry.value.length,
          cards: [
            for (final i in dailyShuffled(byFame.take(24).toList(),
                    salt: 'b_${entry.key}_$kind')
                .take(20))
              PosterCard(
                  item: i, movieLabel: t['movie']!, onPressed: () => open(i)),
          ],
        ));
      }
      return rows;
    }

    final present = isMyList
        ? <String>{}
        : base.map((s) => firstLetterFor(s.title, script)).toSet();
    final letters = (script == 'ar' ? alphaAr : alphaEn).split('');

    final headerCount =
        (isMyList || sectioned) ? typeItems.length : shown.length;

    return ScreenShell(
      current: _navKey(),
      background: AppColors.bg1,
      child: CustomScrollView(
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: 150)),
          SliverToBoxAdapter(
            child: Padding(
              padding:
                  const EdgeInsets.fromLTRB(Spacing.pad, 0, Spacing.pad, 30),
              child: Row(
                textBaseline: TextBaseline.alphabetic,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontFamily: Fonts.display,
                          fontFamilyFallback: Fonts.fallback,
                          fontWeight: FontWeight.w600,
                          fontSize: 56,
                          letterSpacing: -0.5,
                          color: AppColors.ink)),
                  const SizedBox(width: 16),
                  Text('$headerCount',
                      style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: AppColors.inkMute)),
                ],
              ),
            ),
          ),
          if (!isMyList)
            SliverToBoxAdapter(
              child: SizedBox(
                height: 70,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: Spacing.pad),
                  children: [
                    // Filter button — shows the active genre when one is set.
                    _railChip(SelectableChip(
                      label: category == null
                          ? t['browse_filter']!
                          : translateGenre(category),
                      selected: category != null,
                      radius: 13,
                      onPressed: () =>
                          _openFilter(context, ref, typeItems, category, t),
                    )),
                    const SizedBox(width: 16),
                    // script toggle
                    _railChip(SelectableChip(
                      label: t['kbLatin']!,
                      selected: script == 'en',
                      radius: 13,
                      minWidth: 56,
                      onPressed: () =>
                          ref.read(browseProvider.notifier).setScript('en'),
                    )),
                    _railChip(SelectableChip(
                      label: t['kbArabic']!,
                      selected: script == 'ar',
                      radius: 13,
                      minWidth: 56,
                      onPressed: () =>
                          ref.read(browseProvider.notifier).setScript('ar'),
                    )),
                    const SizedBox(width: 16),
                    _railChip(SelectableChip(
                      label: t['alpha_all']!,
                      selected: letter == null,
                      radius: 13,
                      onPressed: () =>
                          ref.read(browseProvider.notifier).setLetter(null),
                    )),
                    for (final L in letters)
                      _railChip(SelectableChip(
                        label: L,
                        selected: letter == L,
                        disabled: !present.contains(L),
                        radius: 13,
                        minWidth: 54,
                        onPressed: () =>
                            ref.read(browseProvider.notifier).setLetter(L),
                      )),
                  ],
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
          if (sectioned)
            SliverList(delegate: SliverChildListDelegate(sectionRows()))
          else
            grid(shown),
        ],
      ),
    );
  }

  Widget _railChip(Widget child) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: EnsureVisibleOnFocus(child: Center(child: child)),
      );

  /// D-pad genre picker. Selecting a genre sets the category filter (collapsing
  /// the sectioned view into a fame-sorted grid); "All Genres" clears it.
  Future<void> _openFilter(
    BuildContext context,
    WidgetRef ref,
    List<ContentItem> items,
    String? current,
    Map<String, String> t,
  ) {
    final genres = genresIn(items);
    return showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.bg2,
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 120, vertical: 80),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t['browse_filter']!,
                  style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink)),
              const SizedBox(height: 20),
              Flexible(
                child: SingleChildScrollView(
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SelectableChip(
                        label: t['filter_all_genres']!,
                        selected: current == null,
                        autofocus: true,
                        onPressed: () {
                          ref.read(browseProvider.notifier).setCategory(null);
                          Navigator.of(ctx).pop();
                        },
                      ),
                      for (final g in genres)
                        SelectableChip(
                          label: translateGenre(g),
                          selected: current == g,
                          onPressed: () {
                            ref.read(browseProvider.notifier).setCategory(g);
                            Navigator.of(ctx).pop();
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Analyze the changed files**

Run: `flutter analyze lib/screens/browse_screen.dart lib/i18n/strings.dart`
Expected: "No issues found!" (no new warnings/errors).

- [ ] **Step 5: Run the full test suite (no regressions)**

Run: `flutter test`
Expected: all tests PASS.

- [ ] **Step 6: Manual verification on a device/emulator**

Run: `flutter run` and check:
- Movies tab, "All" selected → shows Most Popular / Popular Now / Top 10 / genre
  rows, **no hero**, movies only. TV tab → same, shows only.
- Tap **Filter** → genre picker opens, D-pad navigable; pick a genre → view
  becomes a flat grid of that genre, well-known titles first; the Filter chip
  now shows the genre name (selected style).
- Pick a **letter** → flat grid for that letter, well-known titles first.
- Filter genre **and** a letter together → grid honors both.
- Filter → "All Genres", letter → "All" → returns to the sectioned view.
- **My List** tab unchanged.

- [ ] **Step 7: Commit**

```bash
git add lib/i18n/strings.dart lib/screens/browse_screen.dart
git commit -m "feat: sectioned + fame-sorted Browse with genre filter"
```

---

## Self-Review

**Spec coverage:**
- "All" fame-sorted + sectioned Home-like (single type, no hero) → Task 3 Mode A. ✓
- Sort when browsing by first letter → Task 3 Mode B via `sortedForBrowse`. ✓
- Filter button (genre, one at a time) → Task 3 filter chip + `_openFilter`. ✓
- Filtered view = flat fame-sorted list, not the Home look → Task 3 Mode B. ✓
- Daily-rotation rows (user's choice) → Task 3 `dailyShuffled` in `sectionRows`. ✓
- All-titles browse sort (no dropping) → Task 1 `sortedForBrowse`. ✓
- Letter + category combine; present-set reflects category → Task 3 `base`. ✓

**Placeholder scan:** none — all code blocks are complete.

**Type consistency:** `sortedForBrowse`, `genresIn`, `genreRowsFor` signatures
match between Tasks 1-2 (definitions) and Task 3 (calls). `setCategory`,
`setLetter`, `setScript` already exist on `BrowseNotifier` and need no change
(they don't clear each other, satisfying the combination rule).
```
