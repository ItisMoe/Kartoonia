# Merged Titles with In-Detail Source Toggle — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collapse cross-source duplicate titles into a single card app-wide and move the Arabic Toons / Stardima choice into a resume-aware toggle on the detail screens.

**Architecture:** `CatalogService.loadMerged()` builds `all`/`shows`/`movies` from primaries only (Arabic Toons copy of any TMDB id present in both sources); the Stardima twin stays reachable via new `alternateFor`/`primaryFor` lookups and remains in `_byId`. Cards/search/browse/fame are untouched. The TV and phone detail screens gain a source toggle; Continue Watching dedupes by primary.

**Tech Stack:** Flutter, Riverpod, `flutter_test`.

## Global Constraints

- Match key is **TMDB id only** — reuse the existing `_duplicatedTmdbIds` set. No fuzzy/title matching.
- Primary of a duplicated pair is always the **Arabic Toons** copy.
- Default source on open is **resume-aware** (source with stored progress), else Arabic Toons. **Recomputed each mount** (reset per open).
- Apply to **both** `detail_screen` (TV) and `phone_detail_screen`.
- Run tests with `flutter test`; static check with `flutter analyze`.

---

### Task 1: Catalog grouping (alternateFor / primaryFor / collapsed lists)

**Files:**
- Modify: `lib/services/catalog_service.dart`
- Test: `test/merged_catalog_test.dart`

**Interfaces:**
- Produces:
  - `ContentItem? alternateFor(ContentItem item)` — the other-source twin, or null.
  - `ContentItem primaryFor(ContentItem item)` — the Arabic Toons primary of the group, or `item` itself.
  - `bool isDuplicated(ContentItem item)` — now `alternateFor(item) != null`.
  - `all`/`shows`/`movies` collapsed (primary-only); `_byId` keeps both copies.

- [ ] **Step 1: Update the existing test expectations and add grouping tests**

Replace the body of `test/merged_catalog_test.dart` with:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/services/catalog_service.dart';
import 'package:kartoonia/models/catalog_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loadMerged contains items from both sources', () async {
    final svc = await CatalogService.loadMerged();
    final at = svc.all.where((i) => i.source == CatalogSource.arabicToons);
    final st = svc.all.where((i) => i.source == CatalogSource.stardima);
    expect(at, isNotEmpty);
    expect(st, isNotEmpty);
  });

  test('duplicated titles collapse to the Arabic Toons primary', () async {
    final svc = await CatalogService.loadMerged();
    // Any Stardima item whose tmdbId is shared must NOT appear in `all`.
    for (final i in svc.all) {
      final alt = svc.alternateFor(i);
      if (alt != null) {
        expect(i.source, CatalogSource.arabicToons,
            reason: 'collapsed list should expose the Arabic Toons primary');
        expect(alt.source, CatalogSource.stardima);
        expect(svc.primaryFor(alt).id, i.id,
            reason: 'primaryFor(stardima twin) resolves to the AT primary');
      }
    }
  });

  test('alternateFor is symmetric and null for single-source titles', () async {
    final svc = await CatalogService.loadMerged();
    var pairs = 0;
    for (final i in svc.all) {
      final alt = svc.alternateFor(i);
      if (alt != null) {
        pairs++;
        // Round-trip: the alternate's alternate is the original.
        expect(svc.alternateFor(alt)?.id, i.id);
      }
      if (i.tmdbId == null) expect(alt, isNull);
    }
    expect(pairs, greaterThan(0), reason: 'fixtures contain shared titles');
  });

  test('both twin ids still resolve via getById', () async {
    final svc = await CatalogService.loadMerged();
    final dup = svc.all.firstWhere((i) => svc.alternateFor(i) != null);
    final alt = svc.alternateFor(dup)!;
    expect(svc.getById(dup.id), isNotNull);
    expect(svc.getById(alt.id), isNotNull);
  });

  test('isDuplicated is false for items without a tmdbId', () async {
    final svc = await CatalogService.loadMerged();
    for (final i in svc.all) {
      if (i.tmdbId == null) expect(svc.isDuplicated(i), isFalse);
    }
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `flutter test test/merged_catalog_test.dart`
Expected: FAIL — `alternateFor`/`primaryFor` are undefined, and collapse not yet implemented.

- [ ] **Step 3: Implement grouping in `catalog_service.dart`**

Add the group map field next to `_duplicatedTmdbIds`:

```dart
  /// tmdbId -> {source: item} for ids present in BOTH sources. Drives the
  /// detail-screen source toggle and the collapsed library.
  Map<int, Map<CatalogSource, ContentItem>> _groups = const {};
```

Replace the body of `loadMerged()` (the part after both sources are parsed into `atShows/atMovies/stShows/stMovies`) with:

```dart
    // Duplicate tmdbIds = ids present in BOTH sources.
    final atIds = {
      for (final i in [...atShows, ...atMovies])
        if (i.tmdbId != null) i.tmdbId!
    };
    final stIds = {
      for (final i in [...stShows, ...stMovies])
        if (i.tmdbId != null) i.tmdbId!
    };
    final dupIds = atIds.intersection(stIds);
    svc._duplicatedTmdbIds = dupIds;

    // Group the duplicated pairs by tmdbId+source (over the FULL set).
    final groups = <int, Map<CatalogSource, ContentItem>>{};
    for (final i in [...atShows, ...atMovies, ...stShows, ...stMovies]) {
      final id = i.tmdbId;
      if (id == null || !dupIds.contains(id)) continue;
      (groups[id] ??= {})[i.source] = i;
    }
    svc._groups = groups;

    // Collapsed library: keep every Arabic Toons item; drop the Stardima twin
    // of any duplicated id (it stays reachable via alternateFor/_byId).
    bool isDupStardima(ContentItem i) =>
        i.source == CatalogSource.stardima &&
        i.tmdbId != null &&
        dupIds.contains(i.tmdbId);
    svc.shows = [...atShows, ...stShows.where((s) => !isDupStardima(s))];
    svc.movies = [...atMovies, ...stMovies.where((m) => !isDupStardima(m))];
    svc.all = [...svc.shows, ...svc.movies];

    // _byId holds BOTH copies so progress/watchlist saved against either id
    // still resolves.
    svc._byId = {};
    for (final i in [...atShows, ...atMovies, ...stShows, ...stMovies]) {
      svc._byId.putIfAbsent(i.id, () => i);
    }
    return svc;
```

Replace `isDuplicated` and add the two lookups:

```dart
  /// True when this title exists in BOTH sources (so the detail screen offers a
  /// source toggle).
  bool isDuplicated(ContentItem item) => alternateFor(item) != null;

  /// The other-source twin of [item] (Arabic Toons <-> Stardima), or null when
  /// the title exists in only one source.
  ContentItem? alternateFor(ContentItem item) {
    final id = item.tmdbId;
    if (id == null) return null;
    final g = _groups[id];
    if (g == null) return null;
    final other = item.source == CatalogSource.arabicToons
        ? CatalogSource.stardima
        : CatalogSource.arabicToons;
    return g[other];
  }

  /// The Arabic Toons primary of [item]'s group, or [item] when it is not part
  /// of a cross-source group.
  ContentItem primaryFor(ContentItem item) {
    final id = item.tmdbId;
    if (id == null) return item;
    return _groups[id]?[CatalogSource.arabicToons] ?? item;
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `flutter test test/merged_catalog_test.dart`
Expected: PASS (all five tests).

- [ ] **Step 5: Commit**

```bash
git add lib/services/catalog_service.dart test/merged_catalog_test.dart
git commit -m "feat: collapse cross-source duplicate titles in catalog"
```

---

### Task 2: TV detail screen source toggle

**Files:**
- Modify: `lib/screens/detail_screen.dart`

**Interfaces:**
- Consumes: `catalog.alternateFor`, `catalog.primaryFor` (Task 1); existing `playItem`, `storage.progressForItem`.

- [ ] **Step 1: Track the selected source and compute a resume-aware default**

In `_DetailScreenState`, add a nullable selected-source field and resolve the active item in `build`. Replace the early part of `build` (from `final item = catalog.getById(widget.itemId);` through the `inList`/`hasProgress` lines) with:

```dart
    final base = catalog.getById(widget.itemId);
    if (base == null) {
      return ScreenShell(
        current: '',
        child: Center(
          child: Pill(
            label: t['back']!,
            icon: Icons.arrow_back,
            autofocus: true,
            onPressed: () => Navigator.maybePop(context),
          ),
        ),
      );
    }
    final storage = ref.read(storageProvider);
    final alt = catalog.alternateFor(base);
    // Resume-aware default (computed once per mount).
    _selectedSource ??= _defaultSource(storage, base, alt);
    final item = (alt != null && _selectedSource == alt.source) ? alt : base;
    final primary = catalog.primaryFor(base);

    final inList = user.watchlistIds.contains(primary.id) ||
        (alt != null && user.watchlistIds.contains(alt.id));
    final hasProgress = storage.progressForItem(item.id) > 0;
```

Remove the now-duplicated `final item = catalog.getById(widget.itemId);`, the old `if (item == null)` block, the old `final inList`, `final storage`, and `final hasProgress` lines that this replaces.

Add the field and helper to `_DetailScreenState`:

```dart
  CatalogSource? _selectedSource;

  /// Default to whichever twin has stored progress (so Resume works), else the
  /// Arabic Toons source.
  CatalogSource _defaultSource(
      StorageService storage, ContentItem base, ContentItem? alt) {
    if (alt != null && storage.progressForItem(alt.id) > 0 &&
        storage.progressForItem(base.id) <= 0) {
      return alt.source;
    }
    return base.source;
  }
```

Add imports at the top:

```dart
import '../models/catalog_source.dart';
import '../services/storage_service.dart';
```

- [ ] **Step 2: Point the My-List toggle at the primary id**

In the My List `Pill`'s `onPressed`, change `ref.read(userProvider.notifier).toggle(item.id);` to:

```dart
                      ref.read(userProvider.notifier).toggle(primary.id);
```

- [ ] **Step 3: Render the source toggle above the episodes**

Immediately before `if (item is Show) _episodes(item, t),` insert:

```dart
                if (alt != null) ...[
                  _sourceToggle(item.source, base.source, alt.source, t),
                  const SizedBox(height: 28),
                ],
```

Add the builder method to `_DetailScreenState`:

```dart
  Widget _sourceToggle(CatalogSource selected, CatalogSource atSource,
      CatalogSource stSource, Map<String, String> t) {
    Widget chip(CatalogSource src) => Padding(
          padding: const EdgeInsets.only(right: 10),
          child: SelectableChip(
            label: src == CatalogSource.stardima
                ? t['source_badge_st']!
                : t['source_badge_at']!,
            selected: src == selected,
            radius: 13,
            onPressed: () => setState(() => _selectedSource = src),
          ),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Text(t['source_label']!,
          style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: AppColors.inkMute)),
      const SizedBox(width: 16),
      chip(atSource),
      chip(stSource),
    ]);
  }
```

- [ ] **Step 4: Add the `source_label` string**

In `lib/i18n/strings.dart`, add to the English map (near `source_badge_at`): `'source_label': 'Source',` and to the Arabic map: `'source_label': 'المصدر',`.

- [ ] **Step 5: Reset the selected source when the season index would be stale**

In `_episodes`, the `_seasonIdx` may exceed a switched source's season count; it is already guarded by `_seasonIdx.clamp(0, show.seasons.length - 1)`, so no change is needed. Verify that line is present.

- [ ] **Step 6: Static check**

Run: `flutter analyze lib/screens/detail_screen.dart lib/i18n/strings.dart`
Expected: No issues (no undefined names, unused imports resolved).

- [ ] **Step 7: Commit**

```bash
git add lib/screens/detail_screen.dart lib/i18n/strings.dart
git commit -m "feat: source toggle on TV detail screen"
```

---

### Task 3: Phone detail screen source toggle

**Files:**
- Modify: `lib/screens/phone/phone_detail_screen.dart`

**Interfaces:**
- Consumes: `catalog.alternateFor`, `catalog.primaryFor`, `primaryFor` (Task 1); existing `playItem`.

- [ ] **Step 1: Track selected source + resume-aware default**

In `_PhoneDetailScreenState`, replace the lines from `final item = catalog.getById(widget.itemId);` through `final hasProgress = ...` with:

```dart
    final base = catalog.getById(widget.itemId);

    if (base == null) {
      return Scaffold(
        backgroundColor: AppColors.bg1,
        appBar: AppBar(backgroundColor: Colors.transparent),
        body: Center(
          child: Text(t['noResults']!,
              style: const TextStyle(color: AppColors.inkMute, fontSize: 16)),
        ),
      );
    }

    final storage = ref.read(storageProvider);
    final alt = catalog.alternateFor(base);
    _selectedSource ??= _defaultSource(storage, base, alt);
    final item = (alt != null && _selectedSource == alt.source) ? alt : base;
    final primary = catalog.primaryFor(base);

    final inList = user.watchlistIds.contains(primary.id) ||
        (alt != null && user.watchlistIds.contains(alt.id));
    final hasProgress = storage.progressForItem(item.id) > 0;
```

Remove the old `final item = catalog.getById(widget.itemId);`, the `if (item == null)` block it duplicates, and the old `final inList`/`final storage`/`final hasProgress` lines.

Add the field + helper to the state class:

```dart
  CatalogSource? _selectedSource;

  CatalogSource _defaultSource(
      StorageService storage, ContentItem base, ContentItem? alt) {
    if (alt != null && storage.progressForItem(alt.id) > 0 &&
        storage.progressForItem(base.id) <= 0) {
      return alt.source;
    }
    return base.source;
  }
```

Add imports:

```dart
import '../../models/catalog_source.dart';
import '../../services/storage_service.dart';
```

- [ ] **Step 2: Point My-List toggle at the primary id**

Change `ref.read(userProvider.notifier).toggle(item.id);` to `ref.read(userProvider.notifier).toggle(primary.id);`.

- [ ] **Step 3: Render the toggle before the episodes / description**

Immediately before `if (item is Show) _episodes(item, t),` insert:

```dart
                      if (alt != null) ...[
                        _sourceToggle(item.source, base.source, alt.source, t),
                        const SizedBox(height: 18),
                      ],
```

Add the builder to the state class:

```dart
  Widget _sourceToggle(CatalogSource selected, CatalogSource atSource,
      CatalogSource stSource, Map<String, String> t) {
    Widget chip(CatalogSource src) {
      final on = src == selected;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _selectedSource = src),
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            gradient:
                on ? const LinearGradient(colors: AppColors.primaryGradient) : null,
            color: on ? null : AppColors.bg2,
          ),
          child: Text(
              src == CatalogSource.stardima
                  ? t['source_badge_st']!
                  : t['source_badge_at']!,
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: on ? AppColors.onPrimary : AppColors.inkSoft)),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        Text(t['source_label']!,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: AppColors.inkMute)),
        const SizedBox(width: 12),
        chip(atSource),
        chip(stSource),
      ]),
    );
  }
```

- [ ] **Step 4: Static check**

Run: `flutter analyze lib/screens/phone/phone_detail_screen.dart`
Expected: No issues.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/phone/phone_detail_screen.dart
git commit -m "feat: source toggle on phone detail screen"
```

---

### Task 4: Collapse Continue Watching to one card per title

**Files:**
- Modify: `lib/screens/home_screen.dart`
- Modify: `lib/screens/phone/phone_home_screen.dart`

**Interfaces:**
- Consumes: `catalog.primaryFor` (Task 1).

- [ ] **Step 1: Dedupe the Keep-Watching list by primary id (TV)**

In `home_screen.dart`, replace the build loop:

```dart
    final continueItems = <(ContentItem, ProgressEntry)>[];
    for (final e in user.continueWatching) {
      final item = catalog.getById(e.itemId);
      if (item != null) continueItems.add((item, e));
    }
```

with (entries are already most-recent first, so the first occurrence of a group wins):

```dart
    final continueItems = <(ContentItem, ProgressEntry)>[];
    final seenGroups = <String>{};
    for (final e in user.continueWatching) {
      final item = catalog.getById(e.itemId);
      if (item == null) continue;
      final key = catalog.primaryFor(item).id;
      if (!seenGroups.add(key)) continue;
      continueItems.add((item, e));
    }
```

- [ ] **Step 2: Apply the identical change in phone home**

In `phone_home_screen.dart`, replace the same loop with the deduped version above (using the same `seenGroups` set).

- [ ] **Step 3: Static check**

Run: `flutter analyze lib/screens/home_screen.dart lib/screens/phone/phone_home_screen.dart`
Expected: No issues.

- [ ] **Step 4: Commit**

```bash
git add lib/screens/home_screen.dart lib/screens/phone/phone_home_screen.dart
git commit -m "feat: collapse continue-watching duplicates to one card"
```

---

### Task 5: Remove the now-redundant cross-source card badge

**Files:**
- Modify: `lib/widgets/content_card.dart`
- Modify: `lib/screens/search_screen.dart`
- Modify: `lib/screens/home_screen.dart`
- Modify: `lib/screens/browse_screen.dart`

**Interfaces:**
- Removes: `PosterCard.sourceLabel`, the `_sourceBadge` widget, and the per-screen `badge()` helpers. (The `source_badge_at`/`source_badge_st` strings stay — reused by the detail toggles.)

- [ ] **Step 1: Drop `sourceLabel` and `_sourceBadge` from the card**

In `lib/widgets/content_card.dart`: delete the `_sourceBadge` function (lines defining `Widget _sourceBadge(...)`), the `final String? sourceLabel;` field, its constructor param `this.sourceLabel,`, the doc comment for it, and the line `if (sourceLabel != null) _sourceBadge(sourceLabel!),`.

- [ ] **Step 2: Remove `badge()` + `sourceLabel:` usages in search**

In `lib/screens/search_screen.dart`: delete the `String? badge(ContentItem i) => ...` helper (and its comment) and remove the `sourceLabel: badge(results[i]),` argument from the `PosterCard`.

- [ ] **Step 3: Remove `badge()` + `sourceLabel:` usages in home**

In `lib/screens/home_screen.dart`: delete the `String? badge(ContentItem i) => ...` helper (and its comment) and remove every `sourceLabel: badge(...)` argument (5 call sites).

- [ ] **Step 4: Remove `badge()` + `sourceLabel:` usages in browse**

In `lib/screens/browse_screen.dart`: delete the `String? badge(ContentItem i) => ...` helper (and its comment) and remove every `sourceLabel: badge(...)` argument (3 call sites).

- [ ] **Step 5: Static check**

Run: `flutter analyze lib/widgets/content_card.dart lib/screens/search_screen.dart lib/screens/home_screen.dart lib/screens/browse_screen.dart`
Expected: No issues, no "unused" warnings for `badge`/`isDuplicated`.

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/content_card.dart lib/screens/search_screen.dart lib/screens/home_screen.dart lib/screens/browse_screen.dart
git commit -m "refactor: drop cross-source card badge (titles now collapsed)"
```

---

### Task 6: Full verification

- [ ] **Step 1: Run the whole test suite**

Run: `flutter test`
Expected: All tests pass.

- [ ] **Step 2: Analyze the whole project**

Run: `flutter analyze`
Expected: No new issues.

- [ ] **Step 3: Commit any incidental fixes**

```bash
git add -A
git commit -m "chore: verification fixes for merged-title source toggle"
```

(Skip if nothing changed.)

## Self-Review notes

- **Spec coverage:** grouping (T1), default-source/resume-aware + toggle on both shells (T2/T3), playback unchanged (no task needed — `playItem` dispatches by `item.source`), My-List identity (T2/T3 steps), Continue-Watching collapse (T4), badge cleanup (T5), testing (T1 + T6). All spec sections mapped.
- **Type consistency:** `alternateFor`/`primaryFor`/`isDuplicated`/`_defaultSource`/`_sourceToggle` signatures are identical wherever referenced.
- **No placeholders:** all steps carry concrete code/commands.
