# Kartoonia TV Feature Batch — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a batch of Android-TV features to Kartoonia: merged dual-source library, auto-play next end-card, My List Home row, recent searches, lazy Home rows, screensaver, continue-watching removal, better trailer queries, and removal of the subtitles setting.

**Architecture:** Flutter + Riverpod. One shared libmpv player. Catalog parsed from two bundled JSON assets into a single normalized `ContentItem` model. Pure-logic additions (storage, catalog merge, duplicate detection, query builder) get unit tests; UI changes are verified with `flutter analyze` + manual TV run.

**Tech Stack:** Flutter, flutter_riverpod, media_kit, shared_preferences, flutter_test.

## Global Constraints

- Dart/Flutter; follow existing file patterns and `flutter_lints` (^6.0.0).
- Riverpod providers live in `lib/state/app_state.dart`.
- Persistence keys are namespaced `kt/...` in `lib/services/storage_service.dart`.
- All user-facing strings go through `lib/i18n/strings.dart` (`ar` + `en` maps), read via `stringsProvider`. Arabic is the primary language; content is all Arabic-dubbed.
- The `CatalogSource` enum stays (drives per-item playback path); only the *active-source switching* is removed.
- Each item already carries `source`; never hardcode a playback path.
- After every task: `flutter analyze` must be clean. Run `flutter test` after tasks that touch tested logic.
- Commit after each task.

---

### Task 1: Remove the Subtitles setting

**Files:**
- Modify: `lib/screens/settings_screen.dart`
- Modify: `lib/services/storage_service.dart:143`
- Modify: `lib/i18n/strings.dart`

**Interfaces:**
- Produces: `getPrefs()` defaults no longer contain a `subtitles` key.

- [ ] **Step 1: Remove the Subtitles group from Settings**

In `lib/screens/settings_screen.dart`, delete the entire `group(t['set_subtitles']!, [...])` block (the one with `settings.prefs['subtitles']`).

- [ ] **Step 2: Drop `subtitles` from prefs defaults**

In `lib/services/storage_service.dart`, change:

```dart
final defaults = {'motion': 'off', 'autoplay': 'on', 'subtitles': 'off'};
```
to:
```dart
final defaults = {'motion': 'off', 'autoplay': 'on'};
```
Also update the `_kPrefs` comment `// motion/autoplay/subtitles` → `// motion/autoplay`.

- [ ] **Step 3: Remove unused subtitle strings**

In `lib/i18n/strings.dart`, remove the `set_subtitles` entry from both the `ar` and `en` maps. (Search for `set_subtitles`; leave `on`/`off` — they are shared.)

- [ ] **Step 4: Verify analyze + existing tests**

Run: `flutter analyze`
Expected: No issues. (No test references `subtitles`; confirm with `grep -r subtitles lib test`.)

- [ ] **Step 5: Commit**

```bash
git add lib/screens/settings_screen.dart lib/services/storage_service.dart lib/i18n/strings.dart
git commit -m "feat: remove unused subtitles setting (content is all dubbed)"
```

---

### Task 2: Arabic-dub-oriented trailer queries

**Files:**
- Modify: `lib/screens/detail_screen.dart:162-167`

**Interfaces:**
- Consumes: existing `AppNav.youtube(context, query, title)`.

- [ ] **Step 1: Update the trailer/theme query**

In `lib/screens/detail_screen.dart`, replace the `onPressed` body of the trailer Pill:

```dart
onPressed: () {
  final year = item.year != null ? ' ${item.year}' : '';
  final query = item is Movie
      ? '${item.title}$year كرتون مدبلج عربي كامل'
      : '${item.title} مدبلج عربي مقدمة';
  AppNav.youtube(context, query, item.title);
},
```

- [ ] **Step 2: Verify analyze**

Run: `flutter analyze`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add lib/screens/detail_screen.dart
git commit -m "feat: Arabic-dub-oriented YouTube trailer/theme queries"
```

---

### Task 3: Storage — recent searches + progress removal

**Files:**
- Modify: `lib/services/storage_service.dart`
- Create: `test/recent_and_progress_test.dart`

**Interfaces:**
- Produces:
  - `List<String> getRecentSearches()`
  - `Future<void> addRecentSearch(String q)` — trims, ignores empty, de-dupes (case-insensitive), most-recent first, max 8.
  - `Future<void> clearRecentSearches()`
  - `Future<void> removeProgress(String episodeUrl)`
  - `Future<void> removeProgressForItem(String itemId)`

- [ ] **Step 1: Write the failing test**

Create `test/recent_and_progress_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kartoonia/services/storage_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('recent searches: dedupe, order, cap at 8', () async {
    final s = await StorageService.create();
    await s.addRecentSearch('Tom');
    await s.addRecentSearch('  '); // ignored
    await s.addRecentSearch('Jerry');
    await s.addRecentSearch('tom'); // dupe of Tom (case-insensitive) -> moves to front
    expect(s.getRecentSearches().take(2).toList(), ['tom', 'Jerry']);

    for (var i = 0; i < 10; i++) {
      await s.addRecentSearch('q$i');
    }
    expect(s.getRecentSearches().length, 8);
    expect(s.getRecentSearches().first, 'q9');

    await s.clearRecentSearches();
    expect(s.getRecentSearches(), isEmpty);
  });

  test('removeProgressForItem clears all episodes of a show', () async {
    final s = await StorageService.create();
    await s.saveProgress(const ProgressEntry(
        itemId: 'show1', episodeUrl: 'u1', episodeNumber: 1,
        currentTime: 10, duration: 100, updatedAt: 1));
    await s.saveProgress(const ProgressEntry(
        itemId: 'show1', episodeUrl: 'u2', episodeNumber: 2,
        currentTime: 10, duration: 100, updatedAt: 2));
    await s.saveProgress(const ProgressEntry(
        itemId: 'other', episodeUrl: 'u3', episodeNumber: 1,
        currentTime: 10, duration: 100, updatedAt: 3));

    await s.removeProgressForItem('show1');
    expect(s.getProgress('u1'), isNull);
    expect(s.getProgress('u2'), isNull);
    expect(s.getProgress('u3'), isNotNull);

    await s.removeProgress('u3');
    expect(s.getProgress('u3'), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/recent_and_progress_test.dart`
Expected: FAIL — `getRecentSearches`/`removeProgress*` not defined.

- [ ] **Step 3: Implement the storage methods**

In `lib/services/storage_service.dart`, add a key constant near the others:

```dart
static const _kRecentSearches = 'kt/recentSearches';
```

Add these methods inside `StorageService` (after the progress section):

```dart
// ---- Recent searches ----
List<String> getRecentSearches() =>
    _prefs.getStringList(_kRecentSearches) ?? const [];

Future<void> addRecentSearch(String q) async {
  final query = q.trim();
  if (query.isEmpty) return;
  final list = [...getRecentSearches()]
    ..removeWhere((e) => e.toLowerCase() == query.toLowerCase());
  list.insert(0, query);
  await _prefs.setStringList(
      _kRecentSearches, list.take(8).toList());
}

Future<void> clearRecentSearches() => _prefs.remove(_kRecentSearches);
```

Add these to the progress section (after `progressForItem`):

```dart
Future<void> removeProgress(String episodeUrl) async {
  final map = _readProgress()..remove(episodeUrl);
  await _prefs.setString(
      _kProgress, jsonEncode(map.map((k, v) => MapEntry(k, v.toJson()))));
}

Future<void> removeProgressForItem(String itemId) async {
  final map = _readProgress()
    ..removeWhere((_, v) => v.itemId == itemId);
  await _prefs.setString(
      _kProgress, jsonEncode(map.map((k, v) => MapEntry(k, v.toJson()))));
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/recent_and_progress_test.dart`
Expected: PASS (both tests).

- [ ] **Step 5: Commit**

```bash
git add lib/services/storage_service.dart test/recent_and_progress_test.dart
git commit -m "feat: storage for recent searches and progress removal"
```

---

### Task 4: Merged catalog (load both sources, no dedup, duplicate detection)

**Files:**
- Modify: `lib/services/catalog_service.dart`
- Modify: `lib/main.dart:32-33,38`
- Test: `test/merged_catalog_test.dart`

**Interfaces:**
- Produces:
  - `static Future<CatalogService> loadMerged()` — loads BOTH assets, concatenates items, indexes by id (first writer wins on collision).
  - `bool isDuplicated(ContentItem item)` — true when the item's `tmdbId` appears in BOTH sources.
- Consumes (Task 5): `isDuplicated`, plus existing `item.source`.

- [ ] **Step 1: Write the failing test**

Create `test/merged_catalog_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:kartoonia/services/catalog_service.dart';
import 'package:kartoonia/models/catalog_source.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loadMerged contains items from both sources', () async {
    final svc = await CatalogService.loadMerged();
    final sources = svc.all.map((i) => i.source).toSet();
    expect(sources, containsAll(<CatalogSource>{
      CatalogSource.arabicToons,
      CatalogSource.stardima,
    }));
    // No dedup: total equals sum of both source lists.
    final at = svc.all.where((i) => i.source == CatalogSource.arabicToons);
    final st = svc.all.where((i) => i.source == CatalogSource.stardima);
    expect(at, isNotEmpty);
    expect(st, isNotEmpty);
  });

  test('isDuplicated is true only for tmdbIds present in both sources', () async {
    final svc = await CatalogService.loadMerged();
    for (final i in svc.all) {
      final id = i.tmdbId;
      if (id == null) {
        expect(svc.isDuplicated(i), isFalse);
      }
    }
    // At least the API contract holds; concrete overlap depends on data.
    expect(svc.isDuplicated, isNotNull);
  });
}
```

> Note: `loadMerged` uses `rootBundle`, which in tests reads from the asset
> bundle. `TestWidgetsFlutterBinding.ensureInitialized()` + the assets declared
> in `pubspec.yaml` make this work (the existing `catalog_parse_smoke_test`
> reads the same files from disk; if `rootBundle` is unavailable in the test
> host, fall back to `File('assets/...')` reads inside the test — but try
> `rootBundle` first).

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/merged_catalog_test.dart`
Expected: FAIL — `loadMerged`/`isDuplicated` not defined.

- [ ] **Step 3: Implement merged loading + duplicate set**

In `lib/services/catalog_service.dart`, add a field and the new loader. Add near the other fields:

```dart
/// TMDB ids that appear in BOTH catalog sources — used to badge duplicates.
Set<int> _duplicatedTmdbIds = const {};
```

Add the factory + helper (alongside `load`):

```dart
/// Load BOTH bundled catalogs into one merged library. No dedup: a title that
/// exists in both sources appears twice (distinguished by a source badge in the
/// UI). Items keep their own `source`, so playback dispatches correctly.
static Future<CatalogService> loadMerged() async {
  final svc = CatalogService._(CatalogSource.arabicToons);
  // Arabic Toons (legacy schema).
  final atStr = await rootBundle.loadString(CatalogSource.arabicToons.assetPath);
  final atData = jsonDecode(atStr) as Map<String, dynamic>;
  final atShows = ((atData['shows'] as List?) ?? const [])
      .map((e) => Show.fromJson((e as Map).cast<String, dynamic>()))
      .toList();
  final atMovies = ((atData['movies'] as List?) ?? const [])
      .map((e) => Movie.fromJson((e as Map).cast<String, dynamic>()))
      .toList();
  // Stardima (adapter).
  final stStr = await rootBundle.loadString(CatalogSource.stardima.assetPath);
  final stData = jsonDecode(stStr) as Map<String, dynamic>;
  final (stShows, stMovies) = StardimaAdapter.parse(stData);

  svc.shows = [...atShows, ...stShows];
  svc.movies = [...atMovies, ...stMovies];
  svc.all = [...svc.shows, ...svc.movies];
  // First writer wins on id collision so getById stays well-formed; both copies
  // still live in `all`/lists for rendering.
  svc._byId = {};
  for (final i in svc.all) {
    svc._byId.putIfAbsent(i.id, () => i);
  }
  // Duplicate tmdbIds = ids present in BOTH sources.
  final atIds = {
    for (final i in [...atShows, ...atMovies])
      if (i.tmdbId != null) i.tmdbId!
  };
  final stIds = {
    for (final i in [...stShows, ...stMovies])
      if (i.tmdbId != null) i.tmdbId!
  };
  svc._duplicatedTmdbIds = atIds.intersection(stIds);
  return svc;
}

/// True when this item's title exists in BOTH catalog sources (so the UI badges
/// it to disambiguate the two copies).
bool isDuplicated(ContentItem item) {
  final id = item.tmdbId;
  return id != null && _duplicatedTmdbIds.contains(id);
}
```

> `_byId` is declared `late`; the loop above assigns it directly, so remove the
> `late` if the analyzer complains, or assign `svc._byId = {...}` in one go. Keep
> the existing `load()`/`_loadSource()` for the unit tests that use them.

- [ ] **Step 4: Wire `main.dart` to load merged**

In `lib/main.dart`, replace:

```dart
final catalog = await CatalogService.load(storage.getCatalogSource());
```
with:
```dart
final catalog = await CatalogService.loadMerged();
```

Leave the `catalogProvider.overrideWithValue(catalog)` line as-is.

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/merged_catalog_test.dart test/catalog_parse_smoke_test.dart`
Expected: PASS. Then `flutter analyze` clean.

- [ ] **Step 6: Commit**

```bash
git add lib/services/catalog_service.dart lib/main.dart test/merged_catalog_test.dart
git commit -m "feat: merged dual-source catalog with duplicate detection"
```

---

### Task 5: Remove source switcher + add source badge on cards

**Files:**
- Modify: `lib/state/app_state.dart` (remove source-switch providers)
- Modify: `lib/screens/settings_screen.dart` (remove Source group)
- Modify: `lib/widgets/content_card.dart` (add optional `sourceLabel`)
- Modify: `lib/screens/home_screen.dart`, `lib/screens/browse_screen.dart`, `lib/screens/search_screen.dart` (pass `sourceLabel` for duplicated items)
- Modify: `lib/i18n/strings.dart` (add `source_badge_at`/`source_badge_st`; remove now-unused source strings)

**Interfaces:**
- Consumes: `catalog.isDuplicated(item)`, `item.source` (Task 4).
- Produces: `PosterCard(..., String? sourceLabel)` renders a small corner chip when non-null.

- [ ] **Step 1: Remove source-switch providers**

In `lib/state/app_state.dart`, delete: `catalogSwitchingProvider`, the entire `CatalogSourceNotifier` class, and `catalogSourceProvider`. Remove the now-unused `import '../models/catalog_source.dart';` only if nothing else uses it (the `setSource`/`reset`/`clear` calls go away with the class). Keep `catalogRevProvider` (still used by import/rebuild paths).

- [ ] **Step 2: Remove the Source group from Settings**

In `lib/screens/settings_screen.dart`: delete the `group(t['set_source']!, [...])` block, the following `set_source_hint` Padding, and the now-unused locals `final source = ...` and `final switching = ...`. Remove the `import '../models/catalog_source.dart';` if unused after.

- [ ] **Step 3: Add localized badge strings**

In `lib/i18n/strings.dart`, add to both maps:
- `ar`: `'source_badge_at': 'عربيتونز', 'source_badge_st': 'ستارديما',`
- `en`: `'source_badge_at': 'Arabic Toons', 'source_badge_st': 'Stardima',`

Remove now-unused `set_source`, `set_source_hint`, `source_arabictoons`, `source_stardima` from both maps.

- [ ] **Step 4: Add `sourceLabel` to `PosterCard`**

In `lib/widgets/content_card.dart`, add an optional `final String? sourceLabel;` field + constructor param to `PosterCard`. In its `build`, overlay a small chip in the top-start corner of the poster when `sourceLabel != null`:

```dart
if (sourceLabel != null)
  PositionedDirectional(
    top: 8,
    start: 8,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(sourceLabel!,
          style: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w800, color: Colors.white)),
    ),
  ),
```

(Place it inside the poster `Stack`. If `PosterCard`'s art is not already a `Stack`, wrap the image in one. Match the existing widget's structure.)

- [ ] **Step 5: Pass `sourceLabel` from the screens**

Add a helper used at each `PosterCard` call site that renders catalog items. In each screen that has `catalog` in scope, define:

```dart
String? badge(ContentItem i) => catalog.isDuplicated(i)
    ? (i.source == CatalogSource.stardima
        ? t['source_badge_st']
        : t['source_badge_at'])
    : null;
```

Then pass `sourceLabel: badge(i)` to `PosterCard(...)` in `home_screen.dart` (Most Popular, Popular, New, genre rows, My List row from Task 6), `browse_screen.dart` (grid + section rows), and `search_screen.dart` (results grid). Add `import '../models/catalog_source.dart';` where needed.

- [ ] **Step 6: Verify analyze + run**

Run: `flutter analyze`
Expected: No issues (no dangling references to the removed providers).

- [ ] **Step 7: Commit**

```bash
git add lib/state/app_state.dart lib/screens/settings_screen.dart lib/widgets/content_card.dart lib/screens/home_screen.dart lib/screens/browse_screen.dart lib/screens/search_screen.dart lib/i18n/strings.dart
git commit -m "feat: drop source switcher; badge titles present in both sources"
```

---

### Task 6: My List row on Home

**Files:**
- Modify: `lib/screens/home_screen.dart`

**Interfaces:**
- Consumes: `userProvider.watchlistIds`, `catalog.getById`, `badge(i)` (Task 5).

- [ ] **Step 1: Insert the My List row after Continue Watching**

In `lib/screens/home_screen.dart`, after the Continue Watching `if (continueItems.isNotEmpty) { rows.add(...) }` block, add:

```dart
// My List (watchlist) — poster row, most-recently-added first.
final myList = [
  for (final id in user.watchlistIds)
    if (catalog.getById(id) != null) catalog.getById(id)!,
];
if (myList.isNotEmpty) {
  rows.add(ContentRow(
    title: t['nav_mylist']!,
    count: myList.length,
    cards: [
      for (final i in myList)
        PosterCard(
            item: i,
            movieLabel: t['movie']!,
            sourceLabel: badge(i),
            onPressed: () => open(i)),
    ],
  ));
}
```

(`badge` is the helper added in Task 5; if Task 6 runs before Task 5's helper exists in this file, add the helper here.)

- [ ] **Step 2: Verify analyze**

Run: `flutter analyze`
Expected: No issues.

- [ ] **Step 3: Commit**

```bash
git add lib/screens/home_screen.dart
git commit -m "feat: My List row on Home"
```

---

### Task 7: Recent searches UI

**Files:**
- Modify: `lib/state/app_state.dart` (recent-searches provider + record-on-open)
- Modify: `lib/screens/search_screen.dart`
- Modify: `lib/navigation.dart` OR `search_screen.dart` (record on result open)
- Modify: `lib/i18n/strings.dart` (add `recent_searches`, `clear` reuse)

**Interfaces:**
- Consumes: `StorageService.getRecentSearches/addRecentSearch/clearRecentSearches` (Task 3).
- Produces: `recentSearchesProvider` (StateProvider<List<String>>) seeded from storage; `SearchNotifier.record()` persists + updates it.

- [ ] **Step 1: Add provider + record method**

In `lib/state/app_state.dart`, add:

```dart
/// Persisted recent search queries (most-recent first), surfaced on the empty
/// Search screen. Seeded from storage; updated when a search is "used".
final recentSearchesProvider = StateProvider<List<String>>(
    (ref) => ref.read(storageProvider).getRecentSearches());
```

Add to `SearchNotifier`:

```dart
/// Persist the current query as a recent search (called when the user opens a
/// result), then refresh the recent list.
Future<void> record() async {
  final q = state.query.trim();
  if (q.isEmpty) return;
  await ref.read(storageProvider).addRecentSearch(q);
  ref.read(recentSearchesProvider.notifier).state =
      ref.read(storageProvider).getRecentSearches();
}

Future<void> clearRecent() async {
  await ref.read(storageProvider).clearRecentSearches();
  ref.read(recentSearchesProvider.notifier).state = const [];
}
```

- [ ] **Step 2: Record when a result is opened**

In `lib/screens/search_screen.dart`, change the result card `onPressed` to record first:

```dart
onPressed: () {
  notifier.record();
  AppNav.detail(context, results[i]);
},
```

- [ ] **Step 3: Show recent chips on the empty state**

In `lib/screens/search_screen.dart`, when `q.isEmpty`, render recent-search chips above the popular grid. Read `final recent = ref.watch(recentSearchesProvider);`. Insert before the results header (only when `q.isEmpty && recent.isNotEmpty`):

```dart
if (q.isEmpty && recent.isNotEmpty) ...[
  Row(children: [
    Text(t['recent_searches']!,
        style: const TextStyle(
            fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.inkSoft)),
    const SizedBox(width: 12),
    SelectableChip(
        label: t['clear']!,
        selected: false,
        onPressed: () => notifier.clearRecent()),
  ]),
  const SizedBox(height: 14),
  Wrap(
    spacing: 10,
    runSpacing: 10,
    children: [
      for (final r in recent)
        SelectableChip(
            label: r,
            selected: false,
            onPressed: () => notifier.setQuery(r)),
    ],
  ),
  const SizedBox(height: 24),
],
```

- [ ] **Step 4: Add the string**

In `lib/i18n/strings.dart`, add `'recent_searches'` to both maps: `ar` → `'عمليات البحث الأخيرة'`, `en` → `'Recent searches'`. (`clear` already exists.)

- [ ] **Step 5: Verify analyze**

Run: `flutter analyze`
Expected: No issues.

- [ ] **Step 6: Commit**

```bash
git add lib/state/app_state.dart lib/screens/search_screen.dart lib/i18n/strings.dart
git commit -m "feat: recent searches on the Search screen"
```

---

### Task 8: Lazy Home rows

**Files:**
- Modify: `lib/screens/home_screen.dart`

**Interfaces:**
- No new API. Converts the eager `Column` to a sliver list so off-screen rows build lazily.

- [ ] **Step 1: Convert the Home body to a CustomScrollView**

In `lib/screens/home_screen.dart` `build`, replace the returned `ScreenShell(... SingleChildScrollView(child: Column([hero, SizedBox, ...rows])))` with a `CustomScrollView`:

```dart
return ScreenShell(
  current: 'home',
  child: CustomScrollView(
    slivers: [
      SliverToBoxAdapter(
        child: EnsureVisibleOnFocus(
          alignment: 0,
          child: HeroCarousel(
            items: featured,
            t: t,
            isRtl: settings.isRtl,
            autoplay: settings.prefs['autoplay'] != 'off',
            onPlay: (i) => playItem(context, ref, i),
            onMoreInfo: open,
            onToggleList: (i) => ref.read(userProvider.notifier).toggle(i.id),
            isInList: (i) => user.watchlistIds.contains(i.id),
          ),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 24)),
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, i) => rows[i],
          childCount: rows.length,
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 90)),
    ],
  ),
);
```

(The `rows` list is still built once above; only widget construction is deferred. The simplified `onPlay` drops the redundant `i is Movie ? ... : ...` ternary that called the same function on both branches.)

- [ ] **Step 2: Verify analyze + manual scroll**

Run: `flutter analyze`
Expected: No issues. Manual: Home scrolls; D-pad focus still scrolls rows into view (cards already use `EnsureVisibleOnFocus`).

- [ ] **Step 3: Commit**

```bash
git add lib/screens/home_screen.dart
git commit -m "perf: lazy Home rows via CustomScrollView slivers"
```

---

### Task 9: Long-press support + Continue Watching removal

**Files:**
- Modify: `lib/widgets/focusable.dart` (add `onLongPress`)
- Modify: `lib/screens/home_screen.dart` (long-press a CW card → Resume/Remove dialog)
- Modify: `lib/i18n/strings.dart` (`remove`, `remove_cw_q`)

**Interfaces:**
- Consumes: `StorageService.removeProgressForItem` (Task 3), `userProvider.refresh()`.
- Produces: `Focusable(..., VoidCallback? onLongPress)` — fires on D-pad press-and-hold (long select) / touch long-press, without affecting existing call sites.

- [ ] **Step 1: Add `onLongPress` to Focusable**

In `lib/widgets/focusable.dart`, add `final VoidCallback? onLongPress;` to the constructor (optional, defaults null). Wire it into the existing gesture/key handling:
- Touch: pass `onLongPress: onLongPress` to the underlying `GestureDetector`/`InkWell`.
- D-pad: in the key handler, on `LogicalKeyboardKey.select`/`enter` **long-press** — detect via a key-repeat (`KeyRepeatEvent`) on select firing `onLongPress` once, while a short `KeyDownEvent`/`KeyUpEvent` fires `onPressed`. Keep existing `onPressed` behavior intact when `onLongPress` is null.

> Read the current `focusable.dart` key handling and integrate minimally;
> existing call sites pass no `onLongPress`, so behavior is unchanged for them.

- [ ] **Step 2: Add strings**

In `lib/i18n/strings.dart`, add to both maps: `remove` (`ar` `'إزالة'`, `en` `'Remove'`) and `remove_cw_q` (`ar` `'إزالة من متابعة المشاهدة؟'`, `en` `'Remove from Continue Watching?'`).

- [ ] **Step 3: Long-press a Continue Watching card**

In `lib/screens/home_screen.dart`, give the Continue Watching `PosterCard` an `onLongPress` that opens a dialog with Resume / Remove / Cancel. Remove calls:

```dart
onLongPress: () => showDialog<void>(
  context: context,
  builder: (ctx) => AlertDialog(
    backgroundColor: AppColors.bg2,
    title: Text(t['remove_cw_q']!,
        style: const TextStyle(color: AppColors.ink)),
    actions: [
      TextButton(
          onPressed: () { Navigator.pop(ctx); playItem(context, ref, item); },
          child: Text(t['resume']!)),
      TextButton(
          onPressed: () async {
            await ref.read(storageProvider).removeProgressForItem(item.id);
            ref.read(userProvider.notifier).refresh();
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: Text(t['remove']!)),
      TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(t['cancel']!)),
    ],
  ),
),
```

(Requires `PosterCard` to forward an `onLongPress` to its `Focusable`. Add the optional param to `PosterCard` and pass it through.)

- [ ] **Step 4: Verify analyze + manual**

Run: `flutter analyze`
Expected: No issues. Manual: long-press (hold center) a Continue Watching card → dialog; Remove clears the show from the row.

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/focusable.dart lib/widgets/content_card.dart lib/screens/home_screen.dart lib/i18n/strings.dart
git commit -m "feat: long-press to remove a Continue Watching entry"
```

---

### Task 10: Auto-play next end-card

**Files:**
- Modify: `lib/screens/player_screen.dart`
- Modify: `lib/i18n/strings.dart` (`next_episode`, `playing_in`, `play_now`)

**Interfaces:**
- Consumes: existing `_hasNext`, `_next()`, `widget.args.episodes`, `settingsProvider` autoplay pref.

- [ ] **Step 1: Add strings**

In `lib/i18n/strings.dart`, add to both maps: `next_episode` (`ar` `'الحلقة التالية'`, `en` `'Next episode'`), `play_now` (`ar` `'تشغيل الآن'`, `en` `'Play now'`), `playing_in` (`ar` `'التالي خلال'`, `en` `'Up next in'`).

- [ ] **Step 2: Add end-card state + countdown**

In `_PlayerScreenState`, add fields:

```dart
bool _showNextCard = false;
int _nextCountdown = 8;
Timer? _nextTimer;
```

Replace `_onEnd()` body:

```dart
void _onEnd() {
  _saveProgressComplete();
  if (!_hasNext) {
    Navigator.maybePop(context);
    return;
  }
  final autoplay = ref.read(settingsProvider).prefs['autoplay'] != 'off';
  setState(() {
    _showNextCard = true;
    _nextCountdown = 8;
    _controlsShown = true;
  });
  if (autoplay) {
    _nextTimer?.cancel();
    _nextTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _nextCountdown--);
      if (_nextCountdown <= 0) _playNextFromCard();
    });
  }
}

void _playNextFromCard() {
  _nextTimer?.cancel();
  setState(() => _showNextCard = false);
  _next();
}

void _cancelNextCard() {
  _nextTimer?.cancel();
  setState(() => _showNextCard = false);
}
```

In `_goEpisode` and `dispose`, cancel the timer and hide the card: add `_nextTimer?.cancel();` to `dispose`, and in `_goEpisode` set `_showNextCard = false` and cancel `_nextTimer`.

- [ ] **Step 3: Render the end-card overlay**

In `build`'s player `Stack` (inside the `TvScaler` child `Stack`, after the controls), add:

```dart
if (_showNextCard)
  Positioned(
    right: Spacing.pad,
    bottom: 56,
    child: _NextCard(
      title: widget.args.title,
      epLabel: _hasNext
          ? '${t['epShort']}${widget.args.episodes![_epIndex + 1].episodeNumber}'
          : '',
      countdown: (_nextTimer?.isActive ?? false) ? _nextCountdown : null,
      playLabel: t['play_now']!,
      cancelLabel: t['back']!,
      upNextLabel: t['playing_in']!,
      nextLabel: t['next_episode']!,
      onPlay: _playNextFromCard,
      onCancel: _cancelNextCard,
    ),
  ),
```

Add a `_NextCard` stateless widget at the bottom of the file (two `_CtrlButton`s: Play now (autofocus) + Cancel, with a countdown line when `countdown != null`). Use existing `_CtrlButton` for the buttons.

- [ ] **Step 4: Verify analyze + manual**

Run: `flutter analyze`
Expected: No issues. Manual: finish an episode (or seek near end) → card appears; with autoplay on it counts down and advances; Play now advances immediately; Cancel dismisses and leaves the finished frame. Last episode → still pops.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/player_screen.dart lib/i18n/strings.dart
git commit -m "feat: auto-play next end-card with countdown and cancel"
```

---

### Task 11: Ambient / screensaver overlay

**Files:**
- Create: `lib/widgets/ambient_overlay.dart`
- Modify: `lib/state/app_state.dart` (`playerActiveProvider`)
- Modify: `lib/screens/player_screen.dart` (toggle `playerActiveProvider`)
- Modify: `lib/app.dart` (wrap navigator child with the overlay on TV)

**Interfaces:**
- Consumes: `isTvProvider`, `catalogProvider.getFeaturedPool()`, `playerActiveProvider`.
- Produces: `playerActiveProvider` (StateProvider<bool>); `AmbientOverlay` widget.

- [ ] **Step 1: Add `playerActiveProvider`**

In `lib/state/app_state.dart`:

```dart
/// True while the full-screen player is mounted — suppresses the screensaver.
final playerActiveProvider = StateProvider<bool>((ref) => false);
```

- [ ] **Step 2: Toggle it from the player**

In `lib/screens/player_screen.dart` `initState`, after `super.initState()`:

```dart
WidgetsBinding.instance.addPostFrameCallback(
    (_) => ref.read(playerActiveProvider.notifier).state = true);
```

In `dispose`, before `super.dispose()`:

```dart
ref.read(playerActiveProvider.notifier).state = false;
```

(Use a captured `ref` safely; `dispose` runs before the element unmounts, so `ref.read` is valid here as elsewhere in this file.)

- [ ] **Step 3: Implement the overlay**

Create `lib/widgets/ambient_overlay.dart`:

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../state/app_state.dart';
import '../widgets/catalog_image.dart';

/// TV-only screensaver: after 3 minutes of no input, crossfades through famous
/// backdrops. Any key/pointer dismisses it. Suppressed while the player is up.
class AmbientOverlay extends ConsumerStatefulWidget {
  final Widget child;
  const AmbientOverlay({super.key, required this.child});
  @override
  ConsumerState<AmbientOverlay> createState() => _AmbientOverlayState();
}

class _AmbientOverlayState extends ConsumerState<AmbientOverlay> {
  static const _idle = Duration(minutes: 3);
  static const _rotate = Duration(seconds: 9);
  Timer? _idleTimer;
  Timer? _rotateTimer;
  bool _active = false;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _arm();
  }

  void _arm() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idle, _show);
  }

  void _show() {
    if (ref.read(playerActiveProvider)) {
      _arm(); // never screensave over the player
      return;
    }
    setState(() {
      _active = true;
      _index = 0;
    });
    _rotateTimer?.cancel();
    _rotateTimer = Timer.periodic(_rotate, (_) {
      if (mounted) setState(() => _index++);
    });
  }

  void _wake() {
    _rotateTimer?.cancel();
    if (_active) setState(() => _active = false);
    _arm();
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    _rotateTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isTv = ref.watch(isTvProvider);
    if (!isTv) return widget.child;

    final pool = ref.read(catalogProvider).getFeaturedPool();
    final backdrops = [
      for (final i in pool)
        if (i.tmdb?.backdropUrl != null) i.backdropUrl
    ];

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _wake(),
      onPointerMove: (_) => _wake(),
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: (_, _) {
          _wake();
          return KeyEventResult.ignored; // wake, but let the key act normally
        },
        child: Stack(children: [
          widget.child,
          if (_active && backdrops.isNotEmpty)
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _wake,
                child: Container(
                  color: Colors.black,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 1200),
                    child: CatalogImage(
                      key: ValueKey(_index % backdrops.length),
                      url: backdrops[_index % backdrops.length],
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
```

> Verify `CatalogImage`'s constructor params (`url`, optional `fallbackUrl`)
> match usage in `detail_screen.dart`; adjust if the API differs.

- [ ] **Step 4: Wrap the app with the overlay**

In `lib/app.dart`, wrap the `Material` child with `AmbientOverlay`:

```dart
child: AmbientOverlay(
  child: child ?? const SizedBox.shrink(),
),
```

Add `import 'widgets/ambient_overlay.dart';`. The overlay reads `isTvProvider` and no-ops on phones.

- [ ] **Step 5: Verify analyze + manual**

Run: `flutter analyze`
Expected: No issues. Manual (or temporarily lower `_idle` to 10s): on a non-player screen the slideshow appears and any key dismisses it; it never appears over the player. Restore `_idle` to 3 minutes before committing.

- [ ] **Step 6: Commit**

```bash
git add lib/widgets/ambient_overlay.dart lib/state/app_state.dart lib/screens/player_screen.dart lib/app.dart
git commit -m "feat: TV ambient screensaver after 3 min idle"
```

---

### Task 12: Final verification + memory update

**Files:**
- Modify (outside repo): memory files `deltas.md`, `stardima-dual-catalog.md`, `MEMORY.md`.

- [ ] **Step 1: Full analyze + test**

Run: `flutter analyze && flutter test`
Expected: analyze clean; all tests pass.

- [ ] **Step 2: Manual smoke on TV**

Verify each feature per the spec's "Testing / verification" list.

- [ ] **Step 3: Update memory**

Update the `deltas` and `stardima-dual-catalog` memories to record that the source switcher was removed and both catalogs are now merged (no dedup, source-badged duplicates). Keep `MEMORY.md` index lines in sync.

- [ ] **Step 4: Commit any remaining changes**

```bash
git add -A
git commit -m "chore: TV feature batch verification"
```

---

## Self-Review notes

- **Spec coverage:** (1) end-card → Task 10; (2) merged catalog + badge → Tasks 4–5; (3) My List row → Task 6; (4) recent searches → Tasks 3,7; (5) lazy rows → Task 8; (6) screensaver → Task 11; (7) CW remove → Tasks 3,9; (8) trailers → Task 2; (9) subtitles removal → Task 1. All covered.
- **Type consistency:** `loadMerged`/`isDuplicated` (Task 4) used in Task 5/11; `removeProgressForItem` (Task 3) used in Task 9; `getRecentSearches/addRecentSearch/clearRecentSearches` (Task 3) used in Task 7; `playerActiveProvider` (Task 11) toggled in player. Consistent.
- **Ordering:** Task 6 references `badge()` from Task 5; if executed in number order, Task 5 adds the helper to `home_screen.dart` first. Task 9 adds `onLongPress` passthrough to `PosterCard` which Task 5 also edits — both touch `content_card.dart`; execute in order to avoid conflicts.
