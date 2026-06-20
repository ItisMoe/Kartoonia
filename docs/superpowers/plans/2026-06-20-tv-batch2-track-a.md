# TV Feature Batch 2 — Track A (Quick Wins) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the three no-special-hardware items from the batch-2 spec: new trailer/theme YouTube queries, a Netflix-style screensaver info card with a clock, and a modernized logo + launcher banner.

**Architecture:** Pure, unit-tested helper functions for the query string and the screensaver meta line keep logic out of widgets. The screensaver overlay is upgraded in place to retain the catalog item (not just its URL) so it can render title/meta, plus a live clock. The logo becomes a `CustomPainter` mark driven by the theme's `primaryGradient` tokens, so a palette refresh is a two-constant change; the Android-TV launcher banner is re-authored as a vector drawable using the same gradient.

**Tech Stack:** Flutter (Dart), Riverpod, Android vector drawables (`res/drawable`).

## Global Constraints

- minSdk is 30 (Android 11). TV-only features are gated by `ref.watch(isTvProvider)`.
- TMDB `vote_average` / `vote_count` are **NEVER displayed in the UI** (`lib/models/content_item.dart:123,227`). The screensaver meta line MUST NOT show a rating.
- Layout is authored on a fixed 1920×1080 canvas (`kCanvasW`/`kCanvasH`) and scaled; size things in those logical pixels.
- Package name is `kartoonia`; tests import `package:kartoonia/...`.
- Test runner: `flutter test`. Lint gate: `flutter analyze` (must stay clean).
- Genre display uses `translateGenre` from `lib/utils/genre_translations.dart`.
- Brand colors live in `lib/theme/theme.dart` `AppColors`; the brand gradient is `AppColors.primaryGradient` (`[primary, primary2]`).

---

### Task 1: Trailer / theme-song search query

**Files:**
- Create: `lib/utils/youtube_query.dart`
- Test: `test/youtube_query_test.dart`
- Modify: `lib/screens/detail_screen.dart:208-214`

**Interfaces:**
- Produces: `String youtubeSearchQuery(ContentItem item)` — returns `"<title> trailer"` for a `Movie`, `"<title> arabic theme song"` for anything else (shows).

- [ ] **Step 1: Write the failing test**

Create `test/youtube_query_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/models/content_item.dart';
import 'package:kartoonia/utils/youtube_query.dart';

Movie _movie(String title) => Movie(
      id: 'm1',
      title: title,
      thumbnailUrl: '',
      description: '',
      pageUrl: '',
      servers: const [],
    );

Show _show(String title) => Show(
      id: 's1',
      title: title,
      thumbnailUrl: '',
      description: '',
      totalEpisodes: 0,
      seasonCount: 1,
      seasons: const [],
      episodes: const [],
    );

void main() {
  group('youtubeSearchQuery', () {
    test('movie searches for a trailer', () {
      expect(youtubeSearchQuery(_movie('Cars')), 'Cars trailer');
    });

    test('show searches for the arabic theme song', () {
      expect(youtubeSearchQuery(_show('Pokemon')), 'Pokemon arabic theme song');
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/youtube_query_test.dart`
Expected: FAIL — `youtube_query.dart` does not exist / `youtubeSearchQuery` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `lib/utils/youtube_query.dart`:

```dart
import '../models/content_item.dart';

/// Builds the YouTube search query for the detail-screen trailer/theme button.
/// Movies look for a trailer; shows look for their Arabic theme song.
String youtubeSearchQuery(ContentItem item) =>
    item is Movie ? '${item.title} trailer' : '${item.title} arabic theme song';
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/youtube_query_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Wire it into the detail screen**

In `lib/screens/detail_screen.dart`, add the import near the other `../utils/` imports:

```dart
import '../utils/youtube_query.dart';
```

Replace the trailer/theme `onPressed` body (currently lines 208-214):

```dart
                    onPressed: () {
                      final year = item.year != null ? ' ${item.year}' : '';
                      final query = item is Movie
                          ? '${item.title}$year كرتون مدبلج عربي كامل'
                          : '${item.title} مدبلج عربي مقدمة';
                      AppNav.youtube(context, query, item.title);
                    },
```

with:

```dart
                    onPressed: () => AppNav.youtube(
                        context, youtubeSearchQuery(item), item.title),
```

- [ ] **Step 6: Verify analyze is clean**

Run: `flutter analyze`
Expected: No issues (no unused `year`/local warnings in `detail_screen.dart`).

- [ ] **Step 7: Commit**

```bash
git add lib/utils/youtube_query.dart test/youtube_query_test.dart lib/screens/detail_screen.dart
git commit -m "feat: trailer button searches '<title> trailer', theme searches '<title> arabic theme song'"
```

---

### Task 2: Screensaver — Netflix-style info card + live clock

**Files:**
- Create: `lib/utils/screensaver_meta.dart`
- Test: `test/screensaver_meta_test.dart`
- Modify: `lib/widgets/ambient_overlay.dart`

**Interfaces:**
- Consumes: `translateGenre` (`lib/utils/genre_translations.dart`), `ContentItem`/`Show`/`Movie` (`lib/models/content_item.dart`).
- Produces: `String screensaverMeta(ContentItem item, Map<String, String> t)` — a ` · `-joined line of `year`, type (`t['movie']` for movies, `"<seasonCount> <t['seasons']>"` for shows), then translated genres. Omits any missing part. Contains NO rating.

- [ ] **Step 1: Write the failing test**

Create `test/screensaver_meta_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/models/content_item.dart';
import 'package:kartoonia/utils/screensaver_meta.dart';

const _t = {'movie': 'فيلم', 'seasons': 'مواسم'};

Movie _movie({int? year, List<String> genres = const []}) => Movie(
      id: 'm1',
      title: 'X',
      thumbnailUrl: '',
      description: '',
      pageUrl: '',
      servers: const [],
      tmdb: TmdbData(year: year, genres: genres),
    );

Show _show({int seasonCount = 1, List<String> genres = const []}) => Show(
      id: 's1',
      title: 'X',
      thumbnailUrl: '',
      description: '',
      totalEpisodes: 0,
      seasonCount: seasonCount,
      seasons: const [],
      episodes: const [],
      tmdb: TmdbData(genres: genres),
    );

void main() {
  group('screensaverMeta', () {
    test('movie: year, type, translated genres', () {
      final line = screensaverMeta(
          _movie(year: 2019, genres: ['Action', 'Adventure']), _t);
      expect(line, '2019 · فيلم · أكشن · مغامرات');
    });

    test('show: season count uses the localized seasons word', () {
      final line = screensaverMeta(_show(seasonCount: 3, genres: ['Comedy']), _t);
      expect(line, '3 مواسم · كوميديا');
    });

    test('omits a missing year', () {
      expect(screensaverMeta(_movie(genres: ['Action']), _t), 'فيلم · أكشن');
    });

    test('never contains a rating-like decimal', () {
      final line = screensaverMeta(_movie(year: 2020, genres: ['Drama']), _t);
      expect(line.contains('.'), isFalse);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/screensaver_meta_test.dart`
Expected: FAIL — `screensaver_meta.dart` does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `lib/utils/screensaver_meta.dart`:

```dart
import '../models/content_item.dart';
import 'genre_translations.dart';

/// One-line metadata for the screensaver info card: year · type · genres.
/// Deliberately excludes any TMDB rating (never displayed app-wide).
String screensaverMeta(ContentItem item, Map<String, String> t) {
  final parts = <String>[];
  if (item.year != null) parts.add('${item.year}');
  if (item is Show) {
    parts.add('${item.seasonCount} ${t['seasons'] ?? ''}'.trim());
  } else {
    final movie = t['movie'];
    if (movie != null && movie.isNotEmpty) parts.add(movie);
  }
  parts.addAll(item.genres.map(translateGenre));
  return parts.where((p) => p.isNotEmpty).join(' · ');
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/screensaver_meta_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Keep the active item (not just the URL) in the overlay**

In `lib/widgets/ambient_overlay.dart`, add imports at the top (after the existing imports):

```dart
import '../models/content_item.dart';
import '../utils/screensaver_meta.dart';
```

Add a clock field and timer alongside the existing timers in `_AmbientOverlayState`:

```dart
  Timer? _clockTimer;
  TimeOfDay _now = TimeOfDay.now();
```

In `_show()`, start the clock ticking while the saver is visible. Replace the body of `_show()`'s `setState`/rotate block by inserting the clock timer right after `_rotateTimer = Timer.periodic(...)` block:

```dart
    _clockTimer?.cancel();
    _now = TimeOfDay.now();
    _clockTimer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() => _now = TimeOfDay.now());
    });
```

In `_wake()`, stop the clock — add after `_rotateTimer?.cancel();`:

```dart
    _clockTimer?.cancel();
```

In `dispose()`, add after `_rotateTimer?.cancel();`:

```dart
    _clockTimer?.cancel();
```

- [ ] **Step 6: Render title + meta + clock over the backdrop**

Still in `lib/widgets/ambient_overlay.dart`, replace the `build` method's backdrop list + `Stack` so it keeps items and draws the info card. Replace this current block:

```dart
    final pool = ref.read(catalogProvider).getFeaturedPool();
    final backdrops = [
      for (final i in pool)
        if (i.tmdb?.backdropUrl != null) i.backdropUrl
    ];
```

with:

```dart
    final t = ref.watch(stringsProvider);
    final pool = ref.read(catalogProvider).getFeaturedPool();
    final items = <ContentItem>[
      for (final i in pool)
        if (i.tmdb?.backdropUrl != null) i
    ];
```

Then replace the `if (_active && backdrops.isNotEmpty)` child with the version below (it references `items` and adds the scrim, info card, and clock):

```dart
        if (_active && items.isNotEmpty)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _wake,
              child: ColoredBox(
                color: Colors.black,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 1200),
                      child: CatalogImage(
                        key: ValueKey(_index % items.length),
                        url: items[_index % items.length].backdropUrl,
                      ),
                    ),
                    // bottom scrim for legibility
                    const Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.center,
                            colors: [Color(0xCC000000), Color(0x00000000)],
                          ),
                        ),
                      ),
                    ),
                    // live clock, top-right
                    Positioned(
                      top: 56,
                      right: 64,
                      child: Text(
                        _now.format(context),
                        style: const TextStyle(
                          fontFamily: Fonts.display,
                          fontWeight: FontWeight.w600,
                          fontSize: 40,
                          color: AppColors.ink,
                        ),
                      ),
                    ),
                    // title + meta, bottom-left
                    Positioned(
                      left: 64,
                      right: 64,
                      bottom: 72,
                      child: _SaverInfo(
                        key: ValueKey('info_${_index % items.length}'),
                        item: items[_index % items.length],
                        meta: screensaverMeta(items[_index % items.length], t),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
```

- [ ] **Step 7: Add the info-card widget**

Append to the end of `lib/widgets/ambient_overlay.dart`:

```dart
/// Title + meta line for the active screensaver slide. Fades/slides in each
/// time the key changes (i.e. every crossfade).
class _SaverInfo extends StatefulWidget {
  final ContentItem item;
  final String meta;
  const _SaverInfo({super.key, required this.item, required this.meta});
  @override
  State<_SaverInfo> createState() => _SaverInfoState();
}

class _SaverInfoState extends State<_SaverInfo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final fade = CurvedAnimation(parent: _c, curve: Curves.easeOut);
    return FadeTransition(
      opacity: fade,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, 0.12), end: Offset.zero)
            .animate(fade),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1100),
              child: Text(
                widget.item.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: Fonts.display,
                  fontFamilyFallback: Fonts.fallback,
                  fontWeight: FontWeight.w600,
                  fontSize: 72,
                  height: 1.0,
                  letterSpacing: -1,
                  color: AppColors.ink,
                ),
              ),
            ),
            if (widget.meta.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                widget.meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 26,
                  letterSpacing: 0.5,
                  color: AppColors.inkSoft,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 8: Verify analyze + tests**

Run: `flutter analyze`
Expected: No issues.
Run: `flutter test test/screensaver_meta_test.dart`
Expected: PASS.

- [ ] **Step 9: Commit**

```bash
git add lib/utils/screensaver_meta.dart test/screensaver_meta_test.dart lib/widgets/ambient_overlay.dart
git commit -m "feat: screensaver shows title, meta line, and a live clock over each backdrop"
```

---

### Task 3: Modern logo redesign (vector mark + palette checkpoint)

**Files:**
- Modify: `lib/theme/theme.dart` (add brand-gradient palette option)
- Modify: `lib/widgets/kartoonia_brand.dart` (replace badge with a `CustomPainter` mark; export a reusable `KartooniaMark`)

**Interfaces:**
- Produces: `class KartooniaMark extends StatelessWidget { const KartooniaMark({required double size}); }` — draws the standalone badge at `size` × `size`. Reused by the banner task.
- `KartooniaBrand` keeps its existing constructor (`brandA`, `brandB`, `scale`) so all three call sites (`top_bar.dart:35`, `splash_screen.dart:54`, `phone_home_screen.dart:186`) are unchanged.

- [ ] **Step 1: CHECKPOINT — confirm the palette with the user**

This step is a human decision, not code. Present these candidate brand gradients (the mark and banner both read `AppColors.primaryGradient`, so the choice is just which two hex values that constant holds):

- **A. Keep coral→amber (current):** `#FF6A4D → #FFB03A` — safest, already cohesive with every pill/focus state app-wide.
- **B. Sunset Pop (recommended refresh):** `#FF4D8D → #FF8A3D` — pinker, more vibrant/modern, still warm so it doesn't clash with the rest of the warm UI.
- **C. Aurora (boldest):** `#7C5CFF → #22D3EE` — violet→cyan; modern but would visually warrant re-theming the whole app (every pill/focus turns violet). Flag this trade-off if chosen.

Wait for the user's pick before proceeding. Default to **B** only if they explicitly defer.

- [ ] **Step 2: Apply the chosen palette**

In `lib/theme/theme.dart`, set `primary` and `primary2` to the chosen pair. For the recommended **B. Sunset Pop**:

```dart
  static const primary = Color(0xFFFF4D8D); // brand pink
  static const primary2 = Color(0xFFFF8A3D); // brand orange
```

(For A leave them; for C use `0xFF7C5CFF` / `0xFF22D3EE`.) Leave `onPrimary` (`#2A0E06`) as-is for A/B; for C change `onPrimary` to `Color(0xFF0B1020)`.

- [ ] **Step 3: Replace the brand widget with a painted mark**

Replace the entire contents of `lib/widgets/kartoonia_brand.dart` with:

```dart
import 'package:flutter/material.dart';
import '../theme/theme.dart';

/// The Kartoonia mark: a rounded-gradient badge with a crisp play glyph and a
/// playful spark. Pure vector (CustomPainter) so it stays sharp at any size and
/// follows the brand gradient tokens.
class KartooniaMark extends StatelessWidget {
  final double size;
  const KartooniaMark({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _MarkPainter(AppColors.primaryGradient)),
    );
  }
}

class _MarkPainter extends CustomPainter {
  final List<Color> gradient;
  _MarkPainter(this.gradient);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final rect = Offset.zero & size;
    final badge = RRect.fromRectAndRadius(rect, Radius.circular(w * 0.30));

    // soft drop shadow
    canvas.drawRRect(
      badge.shift(const Offset(0, 6)),
      Paint()
        ..color = gradient.last.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12),
    );

    // gradient badge
    canvas.drawRRect(
      badge,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ).createShader(rect),
    );

    // play glyph (rounded corners via stroke join)
    final play = Path()
      ..moveTo(w * 0.41, h * 0.31)
      ..lineTo(w * 0.41, h * 0.69)
      ..lineTo(w * 0.71, h * 0.50)
      ..close();
    canvas.drawPath(
      play,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = w * 0.10
        ..style = PaintingStyle.stroke,
    );
    canvas.drawPath(play, Paint()..color = Colors.white);

    // spark
    canvas.drawCircle(
      Offset(w * 0.76, h * 0.24),
      w * 0.055,
      Paint()..color = Colors.white.withValues(alpha: 0.92),
    );
  }

  @override
  bool shouldRepaint(covariant _MarkPainter old) => old.gradient != gradient;
}

/// Brand lockup: the [KartooniaMark] badge + "Kartoon·ia" / "كرتون·يا" wordmark.
class KartooniaBrand extends StatelessWidget {
  final String brandA;
  final String brandB;
  final double scale;
  const KartooniaBrand({
    super.key,
    required this.brandA,
    required this.brandB,
    this.scale = 1,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        KartooniaMark(size: 46 * scale),
        SizedBox(width: 14 * scale),
        Text.rich(
          TextSpan(children: [
            TextSpan(text: brandA, style: const TextStyle(color: AppColors.ink)),
            TextSpan(
                text: brandB,
                style: const TextStyle(color: AppColors.primary2)),
          ]),
          style: TextStyle(
            fontFamily: Fonts.display,
            fontFamilyFallback: Fonts.fallback,
            fontWeight: FontWeight.w600,
            fontSize: 30 * scale,
            letterSpacing: 0.3,
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Verify analyze**

Run: `flutter analyze`
Expected: No issues. (All three `KartooniaBrand` call sites compile unchanged.)

- [ ] **Step 5: CHECKPOINT — view it**

Run the app to the splash/home and confirm the new mark looks right at TV scale (splash uses `scale: 1.8`) and in the top bar. Adjust the play-glyph proportions only if visually off.

Run: `flutter run` (or the project's run skill)

- [ ] **Step 6: Commit**

```bash
git add lib/theme/theme.dart lib/widgets/kartoonia_brand.dart
git commit -m "feat: modern painted Kartoonia logo mark + refreshed brand gradient"
```

---

### Task 4: Modern Android-TV launcher banner

**Files:**
- Create: `android/app/src/main/res/drawable/banner.xml`
- Delete: `android/app/src/main/res/drawable/banner.png`
- Verify: `android/app/src/main/AndroidManifest.xml:19,29` (already `@drawable/banner` — unchanged)

**Interfaces:** none (build asset). The banner gradient hex MUST match the palette chosen in Task 3.

- [ ] **Step 1: Author the vector banner**

Create `android/app/src/main/res/drawable/banner.xml` (320×180, the Android-TV banner size). Gradient + play mark + spark, mirroring the logo. Replace the two gradient `android:color` stops if a non-default (Task 3) palette was chosen — values below are the recommended **B. Sunset Pop**:

```xml
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:aapt="http://schemas.android.com/aapt"
    android:width="320dp"
    android:height="180dp"
    android:viewportWidth="320"
    android:viewportHeight="180">

    <!-- gradient background -->
    <path android:pathData="M0,0 h320 v180 h-320 z">
        <aapt:attr name="android:fillColor">
            <gradient
                android:type="linear"
                android:startX="0" android:startY="0"
                android:endX="320" android:endY="180">
                <item android:offset="0.0" android:color="#FFFF4D8D"/>
                <item android:offset="1.0" android:color="#FFFF8A3D"/>
            </gradient>
        </aapt:attr>
    </path>

    <!-- play glyph -->
    <path
        android:pathData="M132,64 L132,116 L176,90 Z"
        android:fillColor="#FFFFFFFF"
        android:strokeColor="#FFFFFFFF"
        android:strokeWidth="10"
        android:strokeLineJoin="round"/>

    <!-- spark -->
    <path
        android:pathData="M196,58 m-9,0 a9,9 0 1,0 18,0 a9,9 0 1,0 -18,0"
        android:fillColor="#FFFFFFFF"
        android:fillAlpha="0.92"/>
</vector>
```

- [ ] **Step 2: Remove the old raster banner**

```bash
git rm android/app/src/main/res/drawable/banner.png
```

Expected: the file is staged for deletion. The manifest still references `@drawable/banner`, which now resolves to `banner.xml`.

- [ ] **Step 3: Verify the Android build resolves the resource**

Run: `flutter build apk --debug`
Expected: BUILD succeeds with no "resource banner not found" / duplicate-resource error.

- [ ] **Step 4: CHECKPOINT — view it on the launcher**

Install on the TV box (or emulator) and confirm the banner renders on the Android-TV home row. (User-facing visual check.)

- [ ] **Step 5: Commit**

```bash
git add android/app/src/main/res/drawable/banner.xml
git commit -m "feat: modern vector Android-TV launcher banner matching the new logo"
```

---

## Self-Review

**Spec coverage (Track A items):**
- Trailer/theme queries → Task 1 ✔ (`"<title> trailer"` / `"<title> arabic theme song"`).
- Screensaver Title + meta + clock → Task 2 ✔ (title, year·type·genres line, live clock; rating excluded per the spec's hard constraint).
- Logo redesign + new-palette-for-approval → Task 3 ✔ (painted `KartooniaMark`, palette checkpoint).
- Banner (code-drawn, no raster gen) → Task 4 ✔ (vector drawable launcher banner).
- Track B (voice) is intentionally a separate plan — not covered here.

**Placeholder scan:** No TBD/TODO; all code blocks complete; the two CHECKPOINT steps (palette, visual review) are genuine human-decision gates, not deferred code.

**Type consistency:** `youtubeSearchQuery(ContentItem)`, `screensaverMeta(ContentItem, Map<String,String>)`, `KartooniaMark({required double size})`, and `KartooniaBrand({brandA, brandB, scale})` are used consistently across tasks and match existing call sites. `_SaverInfo` is private to `ambient_overlay.dart`. Banner gradient hex is tied to the Task 3 palette choice (noted in both tasks).
