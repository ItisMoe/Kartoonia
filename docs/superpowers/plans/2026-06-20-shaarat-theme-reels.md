# شارات Theme-Song Reels — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a شارات tab — a vertical, swipeable reels feed of famous animated shows' Arabic theme songs (video or audio-only), each linking into the show, with a like that boosts ordering.

**Architecture:** A pure feed-ordering unit (`ShaaratFeed`) and a quota-safe resolver (`ShaaratResolver`, permanent per-show videoId cache) feed a shared `ShaaratFeedView` widget that plays each active reel on the existing single `PlayerService`. TV and phone screens wrap that view; persistence (likes, videoId cache, play-mode pref) lives in `StorageService`.

**Tech Stack:** Flutter, Riverpod, media_kit (shared player), youtube_explode_dart, shared_preferences.

## Global Constraints

- **One shared decoder:** all playback goes through `PlayerService.instance` (`open`/`openWithAudio`/`stop`); never construct a `Player`/`VideoController`. Call `stop()` (never dispose) on teardown.
- **YouTube quota:** each show is searched at most once ever, then its videoId is cached permanently. Stream URLs are re-extracted per play (no API quota).
- **Pool:** famous animated **shows only** — `isFamous && isAnimation`, deduped by TMDB id. Movies excluded.
- **Tab label key:** `nav_shaarat` → ar `شارات`, en `Theme Songs`. Enter button key `shaarat_enter` → ar `ادخل المسلسل`, en `Enter show`.
- **Play mode:** stored in the `kt/prefs` map under `shaarat`, values `'video'` (default) | `'audio'`.
- **RTL:** UI is Arabic-first; strings come from `stringsProvider`.

---

### Task 1: StorageService — likes, videoId cache, play-mode default

**Files:**
- Modify: `lib/services/storage_service.dart`
- Test: `test/shaarat_storage_test.dart`

**Interfaces:**
- Produces:
  - `List<String> getShaaratLikes()`
  - `bool isShaaratLiked(String showId)`
  - `Future<bool> toggleShaaratLike(String showId)` → returns new liked state
  - `String? getShaaratVideoId(String showId)` → `null` = never searched; `''` = searched, none found; non-empty = the videoId
  - `Future<void> setShaaratVideoId(String showId, String videoIdOrEmpty)`
  - `shaarat` key added to `getPrefs()` defaults as `'video'`

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kartoonia/services/storage_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('shaarat likes: toggle on/off and persist', () async {
    final s = await StorageService.create();
    expect(s.isShaaratLiked('show1'), false);
    expect(await s.toggleShaaratLike('show1'), true);
    expect(s.isShaaratLiked('show1'), true);
    expect(s.getShaaratLikes(), contains('show1'));
    expect(await s.toggleShaaratLike('show1'), false);
    expect(s.isShaaratLiked('show1'), false);
  });

  test('shaarat videoId cache: null until set, empty sentinel, real id', () async {
    final s = await StorageService.create();
    expect(s.getShaaratVideoId('show1'), isNull);
    await s.setShaaratVideoId('show1', '');
    expect(s.getShaaratVideoId('show1'), '');
    await s.setShaaratVideoId('show2', 'abc123');
    expect(s.getShaaratVideoId('show2'), 'abc123');
  });

  test('prefs default shaarat mode is video', () async {
    final s = await StorageService.create();
    expect(s.getPrefs()['shaarat'], 'video');
  });
}
```

- [ ] **Step 2: Run, verify it fails** — `flutter test test/shaarat_storage_test.dart` → FAIL (methods undefined).

- [ ] **Step 3: Implement.** Add to `StorageService`:

```dart
  static const _kShaaratLikes = 'kt/shaaratLikes';
  static const _kShaaratVideoIds = 'kt/shaaratVideoIds';

  // ---- شارات likes ----
  List<String> getShaaratLikes() =>
      _prefs.getStringList(_kShaaratLikes) ?? const [];

  bool isShaaratLiked(String showId) => getShaaratLikes().contains(showId);

  Future<bool> toggleShaaratLike(String showId) async {
    final ids = [...getShaaratLikes()];
    final present = ids.contains(showId);
    present ? ids.remove(showId) : ids.insert(0, showId);
    await _prefs.setStringList(_kShaaratLikes, ids);
    return !present;
  }

  // ---- شارات videoId cache (showId -> videoId | '' sentinel for "none") ----
  Map<String, String> _readShaaratVideoIds() {
    final raw = _prefs.getString(_kShaaratVideoIds);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map).map((k, v) => MapEntry('$k', '$v'));
    } catch (_) {
      return {};
    }
  }

  String? getShaaratVideoId(String showId) => _readShaaratVideoIds()[showId];

  Future<void> setShaaratVideoId(String showId, String videoIdOrEmpty) async {
    final m = _readShaaratVideoIds()..[showId] = videoIdOrEmpty;
    await _prefs.setString(_kShaaratVideoIds, jsonEncode(m));
  }
```

And add `'shaarat': 'video'` to the `defaults` map in `getPrefs()`.

- [ ] **Step 4: Run, verify pass** — `flutter test test/shaarat_storage_test.dart` → PASS.

- [ ] **Step 5: Commit** — `feat(shaarat): storage for likes, videoId cache, play-mode pref`

---

### Task 2: ShaaratFeed — pure feed ordering

**Files:**
- Create: `lib/services/shaarat_feed.dart`
- Test: `test/shaarat_feed_test.dart`

**Interfaces:**
- Consumes: `Show`, `ContentItem.isFamous/isAnimation/tmdbId` (content_item.dart).
- Produces: `List<Show> shaaratQueue(List<Show> shows, Set<String> likedIds, {String? daySalt, int likeBoost = 3})`
  — filters famous animated shows, dedupes by tmdbId, returns a weighted-random permutation (liked shows weighted ×`likeBoost`) that is deterministic per calendar day + `daySalt`.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/models/content_item.dart';
import 'package:kartoonia/services/shaarat_feed.dart';

Show _show(String id, {int? tmdbId, int votes = 100, bool animation = true}) =>
    Show(
      id: id,
      title: id,
      thumbnailUrl: '',
      description: '',
      tmdb: TmdbData(
        voteCount: votes,
        tmdbId: tmdbId,
        tmdbGenres: animation ? const ['Animation'] : const ['Drama'],
      ),
      totalEpisodes: 1,
      seasonCount: 1,
      seasons: const [],
      episodes: const [],
    );

void main() {
  test('keeps only famous animated shows, deduped by tmdbId', () {
    final shows = [
      _show('a', tmdbId: 1),
      _show('b', tmdbId: 1), // dup tmdbId -> dropped
      _show('c', tmdbId: 2, animation: false), // not animation -> dropped
      _show('d', tmdbId: 3, votes: 0), // not famous -> dropped
      _show('e', tmdbId: 4),
    ];
    final q = shaaratQueue(shows, const {}, daySalt: 'x');
    expect(q.map((s) => s.id).toSet(), {'a', 'e'});
  });

  test('deterministic for a given day/salt', () {
    final shows = [for (var i = 0; i < 8; i++) _show('s$i', tmdbId: i)];
    final a = shaaratQueue(shows, const {}, daySalt: 'same');
    final b = shaaratQueue(shows, const {}, daySalt: 'same');
    expect(a.map((s) => s.id).toList(), b.map((s) => s.id).toList());
  });

  test('liked shows trend earlier across many runs', () {
    final shows = [for (var i = 0; i < 20; i++) _show('s$i', tmdbId: i)];
    var likedAvg = 0.0, baseAvg = 0.0;
    const runs = 40;
    for (var r = 0; r < runs; r++) {
      final q = shaaratQueue(shows, {'s0'}, daySalt: 'run$r');
      likedAvg += q.indexWhere((s) => s.id == 's0');
      baseAvg += q.indexWhere((s) => s.id == 's1');
    }
    expect(likedAvg / runs, lessThan(baseAvg / runs));
  });
}
```

- [ ] **Step 2: Run, verify it fails** — `flutter test test/shaarat_feed_test.dart` → FAIL (no `shaarat_feed.dart`).

- [ ] **Step 3: Implement** `lib/services/shaarat_feed.dart`:

```dart
import 'dart:math';
import '../models/content_item.dart';

/// Eligible pool for the شارات reels: famous animated shows, deduped by TMDB id.
List<Show> shaaratPool(List<Show> shows) {
  final seen = <int>{};
  final out = <Show>[];
  for (final s in shows) {
    if (!(s.isFamous && s.isAnimation)) continue;
    final id = s.tmdbId;
    if (id != null && !seen.add(id)) continue;
    out.add(s);
  }
  return out;
}

/// Weighted-random permutation of the شارات pool, stable per calendar day +
/// [daySalt]. Liked shows get [likeBoost]× weight so they surface earlier and
/// more often. Uses the Efraimidis–Spirakis key `-ln(u)/w` (smaller = earlier).
List<Show> shaaratQueue(
  List<Show> shows,
  Set<String> likedIds, {
  String? daySalt,
  int likeBoost = 3,
}) {
  final pool = shaaratPool(shows);
  if (pool.length < 2) return pool;
  final now = DateTime.now();
  final salt = daySalt ?? '';
  final rng = Random('${now.year}-${now.month}-${now.day}-$salt'.hashCode);
  final keyed = pool.map((s) {
    final w = likedIds.contains(s.id) ? likeBoost.toDouble() : 1.0;
    final u = rng.nextDouble().clamp(1e-12, 1.0);
    return (key: -log(u) / w, show: s);
  }).toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  return [for (final e in keyed) e.show];
}
```

- [ ] **Step 4: Run, verify pass** — `flutter test test/shaarat_feed_test.dart` → PASS.

- [ ] **Step 5: Commit** — `feat(shaarat): pure feed ordering (famous-animation pool + weighted shuffle)`

---

### Task 3: ShaaratResolver — quota-safe videoId resolution

**Files:**
- Create: `lib/services/shaarat_resolver.dart`
- Test: `test/shaarat_resolver_test.dart`

**Interfaces:**
- Consumes: `StorageService.getShaaratVideoId/setShaaratVideoId`, `youtubeSearchQuery(item)`, a search function typed `Future<List<String>> Function(String query)` (defaults to `YoutubeService.searchVideoIds`, injectable for tests).
- Produces: class `ShaaratResolver(StorageService storage, {SearchFn search})` with `Future<String?> videoIdFor(Show show)` — null when no theme exists.

- [ ] **Step 1: Write the failing test**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kartoonia/models/content_item.dart';
import 'package:kartoonia/services/storage_service.dart';
import 'package:kartoonia/services/shaarat_resolver.dart';

Show _show(String id) => Show(
    id: id, title: id, thumbnailUrl: '', description: '',
    totalEpisodes: 1, seasonCount: 1, seasons: const [], episodes: const []);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('cache miss → searches once and caches the top id', () async {
    final s = await StorageService.create();
    var calls = 0;
    final r = ShaaratResolver(s, search: (q) async { calls++; return ['vid1']; });
    expect(await r.videoIdFor(_show('a')), 'vid1');
    expect(await r.videoIdFor(_show('a')), 'vid1'); // served from cache
    expect(calls, 1);
  });

  test('empty search result caches the negative sentinel (no re-search)', () async {
    final s = await StorageService.create();
    var calls = 0;
    final r = ShaaratResolver(s, search: (q) async { calls++; return []; });
    expect(await r.videoIdFor(_show('a')), isNull);
    expect(await r.videoIdFor(_show('a')), isNull);
    expect(calls, 1);
  });

  test('search throwing returns null without caching', () async {
    final s = await StorageService.create();
    final r = ShaaratResolver(s, search: (q) async => throw Exception('quota'));
    expect(await r.videoIdFor(_show('a')), isNull);
    expect(s.getShaaratVideoId('a'), isNull); // not cached → retried next time
  });
}
```

- [ ] **Step 2: Run, verify it fails** — `flutter test test/shaarat_resolver_test.dart` → FAIL.

- [ ] **Step 3: Implement** `lib/services/shaarat_resolver.dart`:

```dart
import '../models/content_item.dart';
import '../utils/youtube_query.dart';
import 'storage_service.dart';
import 'youtube_service.dart';

typedef SearchFn = Future<List<String>> Function(String query);

/// Resolves a show → its theme-song YouTube videoId, caching the result
/// permanently so each show costs at most one API search ever.
class ShaaratResolver {
  final StorageService storage;
  final SearchFn search;
  ShaaratResolver(this.storage, {SearchFn? search})
      : search = search ?? _defaultSearch;

  static Future<List<String>> _defaultSearch(String q) =>
      YoutubeService.searchVideoIds(q, max: 3);

  /// videoId for [show]'s theme, or null when none exists. Cache: null = never
  /// searched, '' = searched/none, non-empty = the id.
  Future<String?> videoIdFor(Show show) async {
    final cached = storage.getShaaratVideoId(show.id);
    if (cached != null) return cached.isEmpty ? null : cached;
    try {
      final ids = await search(youtubeSearchQuery(show));
      final id = ids.isNotEmpty ? ids.first : '';
      await storage.setShaaratVideoId(show.id, id);
      return id.isEmpty ? null : id;
    } catch (_) {
      return null; // transient (quota/network) — don't cache, retry later
    }
  }
}
```

- [ ] **Step 4: Run, verify pass** — `flutter test test/shaarat_resolver_test.dart` → PASS.

- [ ] **Step 5: Commit** — `feat(shaarat): quota-safe videoId resolver with permanent cache`

---

### Task 4: i18n strings

**Files:**
- Modify: `lib/i18n/strings.dart`

- [ ] **Step 1:** Add to BOTH the `en` and `ar` maps (values below). No test (static map).

en:
```dart
    'nav_shaarat': 'Theme Songs',
    'shaarat_enter': 'Enter show',
    'shaarat_now': 'Theme',
    'shaarat_mode': 'شارات Playback',
    'shaarat_mode_video': 'Video',
    'shaarat_mode_audio': 'Audio only',
    'shaarat_empty': 'No theme songs available yet.',
```
ar:
```dart
    'nav_shaarat': 'شارات',
    'shaarat_enter': 'ادخل المسلسل',
    'shaarat_now': 'شارة',
    'shaarat_mode': 'تشغيل الشارات',
    'shaarat_mode_video': 'فيديو',
    'shaarat_mode_audio': 'صوت فقط',
    'shaarat_empty': 'لا توجد شارات متاحة بعد.',
```

- [ ] **Step 2: Verify** — `flutter analyze lib/i18n/strings.dart` → no errors.
- [ ] **Step 3: Commit** — `feat(shaarat): i18n strings (ar/en)`

---

### Task 5: State + navigation wiring

**Files:**
- Modify: `lib/state/app_state.dart` (add `shaaratLikesProvider`; phone tab comment now 0..4)
- Modify: `lib/navigation.dart` (add `AppNav.shaarat`)
- Create: `lib/screens/shaarat_screen.dart` (stub returning `ShaaratFeedView(isTv:true)` — filled in Task 7)

**Interfaces:**
- Produces:
  - `final shaaratLikesProvider = StateProvider<Set<String>>(...)` seeded from `storage.getShaaratLikes()`.
  - `AppNav.shaarat(BuildContext c)` → pushes `ShaaratScreen` via `_tab` (replace-to-root like other tabs).

- [ ] **Step 1:** Add provider to `app_state.dart`:

```dart
/// Liked شارات show ids (boosts feed ordering). Seeded from storage; toggled
/// by the reel heart.
final shaaratLikesProvider = StateProvider<Set<String>>(
    (ref) => ref.read(storageProvider).getShaaratLikes().toSet());
```

- [ ] **Step 2:** Add to `navigation.dart` import + method:

```dart
import 'screens/shaarat_screen.dart';
// ...
  static void shaarat(BuildContext c) => _tab(c, const ShaaratScreen());
```

- [ ] **Step 3:** Create stub `lib/screens/shaarat_screen.dart`:

```dart
import 'package:flutter/material.dart';
import '../widgets/shaarat_reel.dart';

/// TV شارات feed (full-screen, D-pad up/down between reels).
class ShaaratScreen extends StatelessWidget {
  const ShaaratScreen({super.key});
  @override
  Widget build(BuildContext context) => const ShaaratFeedView(isTv: true);
}
```

- [ ] **Step 4: Verify compiles after Task 6** (depends on `ShaaratFeedView`). Run `flutter analyze` at end of Task 6.
- [ ] **Step 5: Commit** — `feat(shaarat): likes provider + navigation entry` (commit together with Task 6 since they co-depend).

---

### Task 6: ShaaratFeedView — the shared reel widget (player + UI)

**Files:**
- Create: `lib/widgets/shaarat_reel.dart`

**Interfaces:**
- Consumes: `catalogProvider.shows`, `shaaratLikesProvider`, `shaaratQueue`, `ShaaratResolver`, `YoutubeStreamResolver.resolvePlayback`, `PlayerService`, `settingsProvider` (`prefs['shaarat']`), `stringsProvider`, `isTvProvider`.
- Produces: `class ShaaratFeedView extends ConsumerStatefulWidget { final bool isTv; }`

**Responsibilities (single widget, mirrors YoutubeScreen lifecycle):**
- Build queue once in `initState` from `catalogProvider.shows` + `shaaratLikesProvider`; empty → show `shaarat_empty`.
- Vertical `PageView.builder` (`scrollDirection: Axis.vertical`).
- Track `_active`; on page settle call `_activate(i)`:
  - `PlayerService.instance.stop()`; resolve `videoId` via `ShaaratResolver`; null → `_skip(i)` (advance one page, guard against >N consecutive skips → show empty/end state).
  - `resolvePlayback(id)`; video mode → `openWithAudio(best.url, audioUrl: best.muxed ? null : pb.audioUrl)`; audio mode → `open(pb.audioUrl ?? pb.muxedFallbackUrl)`.
  - Prefetch `resolver.videoIdFor` for next 2 shows (fire-and-forget).
- Per page background: video mode → blurred dimmed `backdropUrl` (`Image.network` + `ImageFiltered`/`BackdropFilter`) with the `Video` widget (`BoxFit.contain`) only for the **active** page; audio mode → poster (phone) / backdrop (TV) `Image.network` cover. Non-active pages render just the background (no Video).
- Footer (both modes), bottom-anchored, RTL: now-playing pill (`♪ <title> — <shaarat_now>`), title, row of [Enter button (`shaarat_enter`) → `onEnter(show)`] + [heart toggle → `toggleShaaratLike` + update `shaaratLikesProvider`].
- `onEnter`: `isTv ? AppNav.detail(context, show) : openPhoneDetail(context, show)`.
- TV input: wrap footer actions in the app's `Focusable`; `PageView` driven by D-pad up/down via an `onKeyEvent` on a `Focus` that calls `_pageController.nextPage/previousPage`. Heart left of Enter so LEFT/RIGHT moves between them.
- Lifecycle: `WidgetsBindingObserver` → pause when not resumed; `dispose` → cancel subs + `PlayerService.instance.stop()`; keep page **portrait** on phone (do NOT force landscape — letterbox the 16:9 video inside the portrait page).
- Immersive: `SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky)` on init, restore `edgeToEdge` on dispose.

- [ ] **Step 1:** Implement the widget per the responsibilities above (full code written during execution; reuse `YoutubeScreen` patterns for the shared-player wiring, `_openAndWait`-style readiness, and skip-on-error).
- [ ] **Step 2: Analyze** — `flutter analyze lib/widgets/shaarat_reel.dart lib/screens/shaarat_screen.dart` → no errors.
- [ ] **Step 3: Commit** — `feat(shaarat): reel feed view (shared player, video/audio modes, like)` (with Task 5).

---

### Task 7: TV tab in TopBar

**Files:**
- Modify: `lib/widgets/top_bar.dart`

- [ ] **Step 1:** Add a `_NavItem` for شارات between Home and TV:

```dart
          _NavItem(
              label: t['nav_shaarat']!,
              active: current == 'shaarat',
              onPressed: () => AppNav.shaarat(context)),
```

(`ShaaratScreen` is full-screen and does not render `TopBar`; the tab highlight applies when navigating back through it is not needed — it pushes a chrome-less feed. The `current` arg is unused there.)

- [ ] **Step 2: Analyze** — `flutter analyze lib/widgets/top_bar.dart` → no errors.
- [ ] **Step 3: Commit** — `feat(shaarat): TV top-bar tab`

---

### Task 8: Phone tab

**Files:**
- Create: `lib/screens/phone/phone_shaarat_screen.dart`
- Modify: `lib/screens/phone/phone_root.dart`

- [ ] **Step 1:** Create `phone_shaarat_screen.dart`:

```dart
import 'package:flutter/material.dart';
import '../../widgets/shaarat_reel.dart';

/// Phone شارات tab — vertical swipe reels.
class PhoneShaaratScreen extends StatelessWidget {
  const PhoneShaaratScreen({super.key});
  @override
  Widget build(BuildContext context) => const ShaaratFeedView(isTv: false);
}
```

- [ ] **Step 2:** In `phone_root.dart` add `PhoneShaaratScreen()` as the 5th `IndexedStack` child and a 5th nav item `(Icons.music_note_rounded, t['nav_shaarat']!)` appended last (index 4). Update the doc comment to list 5 tabs.

- [ ] **Step 3: Analyze** — `flutter analyze lib/screens/phone/` → no errors.
- [ ] **Step 4: Commit** — `feat(shaarat): phone bottom-nav tab`

---

### Task 9: Settings play-mode toggle (TV + phone)

**Files:**
- Modify: `lib/screens/settings_screen.dart`
- Modify: `lib/screens/phone/phone_settings_screen.dart`

- [ ] **Step 1 (TV):** Add a `group` after the motion group:

```dart
              group(t['shaarat_mode']!, [
                opt(t['shaarat_mode_video']!,
                    settings.prefs['shaarat'] != 'audio',
                    () => sn.setPref('shaarat', 'video')),
                opt(t['shaarat_mode_audio']!,
                    settings.prefs['shaarat'] == 'audio',
                    () => sn.setPref('shaarat', 'audio')),
              ]),
```

- [ ] **Step 2 (phone):** Add a `_Group` after the motion group:

```dart
          _Group(
            label: t['shaarat_mode']!,
            child: Row(children: [
              _Opt(t['shaarat_mode_video']!, settings.prefs['shaarat'] != 'audio',
                  () => sn.setPref('shaarat', 'video')),
              const SizedBox(width: 12),
              _Opt(t['shaarat_mode_audio']!, settings.prefs['shaarat'] == 'audio',
                  () => sn.setPref('shaarat', 'audio')),
            ]),
          ),
```

- [ ] **Step 3: Analyze** — `flutter analyze lib/screens/settings_screen.dart lib/screens/phone/phone_settings_screen.dart` → no errors.
- [ ] **Step 4: Commit** — `feat(shaarat): settings video/audio play-mode toggle`

---

### Task 10: Full verification + release

**Files:** none (verification).

- [ ] **Step 1:** `flutter analyze` (whole project) → no new errors/warnings.
- [ ] **Step 2:** `flutter test` → all pass (existing + 3 new suites).
- [ ] **Step 3:** `dart format` the new/modified files; re-run analyze.
- [ ] **Step 4:** Bump `pubspec.yaml` `version:` to `1.9.0+<n>` ; commit `chore: release v1.9.0`.
- [ ] **Step 5:** Push `main`, tag `v1.9.0`, push the tag.

## Self-Review

- **Spec coverage:** tab placement (T5/T7/T8), pool & weighted/like order (T2), videoId cache + prefetch + quota (T1/T3/T6), video/audio modes (T6/T9), C-style footer + heart + Enter (T6), deep-link (T6), skip-on-failure (T6), persistence (T1), i18n (T4), empty pool (T6). ✓
- **Placeholder scan:** pure units fully coded; T6 is a structural spec for a heavy widget (full code written at execution time) — acceptable for an existing-codebase UI task following the `YoutubeScreen` pattern. ✓
- **Type consistency:** `getShaaratVideoId`/`setShaaratVideoId`, `shaaratQueue`, `ShaaratResolver.videoIdFor`, `ShaaratFeedView(isTv:)`, `shaaratLikesProvider`, `AppNav.shaarat` consistent across tasks. ✓
