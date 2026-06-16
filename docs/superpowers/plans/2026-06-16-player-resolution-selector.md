# Player Resolution Selector Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the episode/movie player a quality picker (Auto + the resolutions the stream actually exposes) and default to the highest variant instead of libmpv's default low pick.

**Architecture:** A pure `video_quality.dart` module turns the player's live `VideoTrack` list into picker options and maps a requested height to the nearest real variant. `PlayerService` sets the libmpv `hls-bitrate=max` property once so Auto lands on the best variant with no manual switch. `PlayerScreen` subscribes to the track stream, shows a "Quality" button + right-side panel (cloned from the Server panel), and pins a variant via `setVideoTrack` only on an explicit pick. Quality choice resets to Auto each episode (no persistence).

**Tech Stack:** Flutter, Riverpod, media_kit (libmpv) 1.2.6, flutter_test.

---

## File Structure

- **Create** `lib/services/video_quality.dart` — pure selection math (options, nearest-match, gate). No Flutter/UI deps beyond the `media_kit` `VideoTrack` type.
- **Create** `test/video_quality_test.dart` — unit tests for the pure module.
- **Modify** `lib/services/player_service.dart` — set `hls-bitrate=max` on the shared player at creation.
- **Modify** `lib/i18n/strings.dart` — add `quality`, `chooseQuality`, `autoQuality` to the English and Arabic maps.
- **Modify** `lib/screens/player_screen.dart` — track subscription, quality state, `_setQuality`, Quality button, `_qualityPanel`.

Test command for the whole suite: `flutter test`
Static analysis: `flutter analyze`

---

## Task 1: Pure quality-selection module

**Files:**
- Create: `lib/services/video_quality.dart`
- Test: `test/video_quality_test.dart`

- [ ] **Step 1: Write the failing test**

Create `test/video_quality_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:kartoonia/services/video_quality.dart';

VideoTrack _vt(String id, int? height) =>
    VideoTrack(id, null, null, h: height);

void main() {
  group('buildQualityOptions', () {
    test('Auto is always first and uses the supplied label', () {
      final opts = buildQualityOptions(const [], autoLabel: 'تلقائي');
      expect(opts.length, 1);
      expect(opts.first.height, isNull);
      expect(opts.first.label, 'تلقائي');
    });

    test('lists distinct heights high to low, labelled "<h>p"', () {
      final opts = buildQualityOptions(
        [_vt('1', 480), _vt('2', 1080), _vt('3', 720)],
        autoLabel: 'Auto',
      );
      expect(opts.map((o) => o.height).toList(), [null, 1080, 720, 480]);
      expect(opts.map((o) => o.label).toList(),
          ['Auto', '1080p', '720p', '480p']);
    });

    test('dedupes equal heights and ignores null/zero-height tracks', () {
      final opts = buildQualityOptions(
        [_vt('1', 720), _vt('2', 720), _vt('3', 0), _vt('4', null)],
        autoLabel: 'Auto',
      );
      expect(opts.map((o) => o.height).toList(), [null, 720]);
    });
  });

  group('nearestTrackForHeight', () {
    test('returns the exact match when present', () {
      final tracks = [_vt('a', 1080), _vt('b', 720), _vt('c', 480)];
      expect(nearestTrackForHeight(tracks, 720)?.id, 'b');
    });

    test('returns the closest height when no exact match', () {
      final tracks = [_vt('a', 720), _vt('b', 480)];
      expect(nearestTrackForHeight(tracks, 1080)?.id, 'a');
      expect(nearestTrackForHeight(tracks, 500)?.id, 'b');
    });

    test('returns null when no track has a usable height', () {
      expect(nearestTrackForHeight([_vt('a', null), _vt('b', 0)], 720), isNull);
    });
  });

  group('hasSelectableQualities', () {
    test('false for zero or one distinct height', () {
      expect(hasSelectableQualities(const []), isFalse);
      expect(hasSelectableQualities([_vt('a', 720), _vt('b', 720)]), isFalse);
    });

    test('true for two or more distinct heights', () {
      expect(hasSelectableQualities([_vt('a', 720), _vt('b', 480)]), isTrue);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/video_quality_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'kartoonia/services/video_quality.dart'` / target of URI doesn't exist.

- [ ] **Step 3: Write the implementation**

Create `lib/services/video_quality.dart`:

```dart
import 'package:media_kit/media_kit.dart';

/// One entry in the player's quality picker. [height] is the video height in
/// pixels (e.g. 720), or null for the adaptive "Auto" option. [label] is the
/// display string — the resolution rows are "<height>p"; the Auto row uses the
/// localized label passed into [buildQualityOptions].
class QualityOption {
  final int? height;
  final String label;
  const QualityOption({required this.height, required this.label});
}

/// Collect the distinct, usable heights (h present and > 0) from [tracks].
Set<int> _distinctHeights(List<VideoTrack> tracks) {
  final heights = <int>{};
  for (final tr in tracks) {
    final h = tr.h;
    if (h != null && h > 0) heights.add(h);
  }
  return heights;
}

/// Build the picker: Auto first (height null, [autoLabel]), then one row per
/// distinct real height, sorted high -> low and labelled "<height>p". Tracks
/// without a usable height (null/zero — e.g. synthetic auto/no tracks) are
/// dropped, and equal heights are deduped.
List<QualityOption> buildQualityOptions(
  List<VideoTrack> tracks, {
  required String autoLabel,
}) {
  final sorted = _distinctHeights(tracks).toList()
    ..sort((a, b) => b.compareTo(a));
  return [
    QualityOption(height: null, label: autoLabel),
    for (final h in sorted) QualityOption(height: h, label: '${h}p'),
  ];
}

/// The [VideoTrack] whose height is closest to [height]; null when no track has
/// a usable height.
VideoTrack? nearestTrackForHeight(List<VideoTrack> tracks, int height) {
  VideoTrack? best;
  int? bestDelta;
  for (final tr in tracks) {
    final h = tr.h;
    if (h == null || h <= 0) continue;
    final delta = (h - height).abs();
    if (bestDelta == null || delta < bestDelta) {
      best = tr;
      bestDelta = delta;
    }
  }
  return best;
}

/// Whether there is a real choice to offer: at least two distinct heights.
/// Drives the Quality button's enabled state — single-quality streams (a lone
/// .mp4 or single-variant HLS) have nothing to pick.
bool hasSelectableQualities(List<VideoTrack> tracks) =>
    _distinctHeights(tracks).length >= 2;
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `flutter test test/video_quality_test.dart`
Expected: PASS (all 8 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/services/video_quality.dart test/video_quality_test.dart
git commit -m "feat: add pure video-quality option/selection helpers"
```

---

## Task 2: Default to the highest HLS variant in PlayerService

**Files:**
- Modify: `lib/services/player_service.dart` (`ensureCreated`)

No unit test — this configures the native libmpv player and is verified via `flutter analyze` plus on-device behavior. (The existing service has no tests.)

- [ ] **Step 1: Set `hls-bitrate=max` when the shared player is created**

In `lib/services/player_service.dart`, replace the `ensureCreated` method body so the property is set right after the player is built. `NativePlayer` and `setProperty` are exported from `package:media_kit/media_kit.dart` (already imported).

Current:

```dart
  void ensureCreated() {
    if (_player != null) return;
    final p = Player();
    _player = p;
    _controller = VideoController(p);
  }
```

New:

```dart
  void ensureCreated() {
    if (_player != null) return;
    final p = Player();
    _player = p;
    _controller = VideoController(p);
    // libmpv otherwise opens whatever variant the HLS demuxer defaults to, which
    // is frequently the LOWEST entry in a master playlist. Force the highest so
    // "Auto" lands on the best quality with no manual track switch. Set once on
    // the long-lived shared player; it survives every open(). Fire-and-forget —
    // a native property nudge that must not block player creation.
    final platform = p.platform;
    if (platform is NativePlayer) {
      platform.setProperty('hls-bitrate', 'max');
    }
  }
```

- [ ] **Step 2: Verify it analyzes cleanly**

Run: `flutter analyze lib/services/player_service.dart`
Expected: No issues (no undefined `NativePlayer`/`setProperty`).

- [ ] **Step 3: Commit**

```bash
git add lib/services/player_service.dart
git commit -m "fix: default HLS playback to the highest variant (hls-bitrate=max)"
```

---

## Task 3: Localized strings for the quality picker

**Files:**
- Modify: `lib/i18n/strings.dart` (English map ~line 48-50, Arabic map ~line 152-154)

No unit test — static strings, covered by `flutter analyze`.

- [ ] **Step 1: Add the English strings**

In `lib/i18n/strings.dart`, in the English map, immediately after the `'chooseServer': 'Choose a server',` line, add:

```dart
    'quality': 'Quality',
    'chooseQuality': 'Choose quality',
    'autoQuality': 'Auto',
```

- [ ] **Step 2: Add the Arabic strings**

In the Arabic map, immediately after the `'chooseServer': 'اختر الخادم',` line, add:

```dart
    'quality': 'الجودة',
    'chooseQuality': 'اختر الجودة',
    'autoQuality': 'تلقائي',
```

- [ ] **Step 3: Verify it analyzes cleanly**

Run: `flutter analyze lib/i18n/strings.dart`
Expected: No issues.

- [ ] **Step 4: Commit**

```bash
git add lib/i18n/strings.dart
git commit -m "feat: add quality-picker strings (en/ar)"
```

---

## Task 4: Wire the quality picker into PlayerScreen

**Files:**
- Modify: `lib/screens/player_screen.dart`

No unit test — this is widget/stream wiring with no device harness, matching the current test scope (`_serverPanel` etc. are untested). The pure logic it calls is already covered by Task 1.

- [ ] **Step 1: Import the quality helpers**

At the top of `lib/screens/player_screen.dart`, add to the imports (next to the other `../services/...` imports):

```dart
import '../services/video_quality.dart';
```

- [ ] **Step 2: Add quality state fields**

In `_PlayerScreenState`, right after the existing `bool _serverPanelOpen = false;` field, add:

```dart
  bool _qualityPanelOpen = false;
  // Video tracks reported by libmpv for the current media. Populated from
  // p.stream.tracks; drives the quality picker. Empty until the stream loads.
  List<VideoTrack> _videoTracks = const [];
  // The pinned quality height (e.g. 720), or null for "Auto". Reset to Auto on
  // every _load — a pin must never carry into a stream that lacks that height.
  int? _quality;
```

- [ ] **Step 3: Subscribe to the track stream**

In `_subscribe()`, add another subscription to the `_subs.addAll([...])` list (e.g. right after the `p.stream.playing.listen(...)` entry):

```dart
      p.stream.tracks.listen((tracks) {
        if (mounted) setState(() => _videoTracks = tracks.video);
      }),
```

- [ ] **Step 4: Reset quality to Auto on each load**

In `_load(int server)`, inside the existing `setState(() { ... });` block at the top (the one that sets `_loading = true;`), add `_quality = null;` so every (re)load starts on Auto:

```dart
    setState(() {
      _loading = true;
      _error = false;
      _restored = false;
      _ended = false;
      _server = server;
      _quality = null;
    });
```

- [ ] **Step 5: Add the `_setQuality` handler**

Add this method to `_PlayerScreenState`, right after the existing `_switchServer` method:

```dart
  void _setQuality(int? height) {
    setState(() {
      _qualityPanelOpen = false;
      _quality = height;
    });
    if (height == null) {
      // Auto: hand back to libmpv's default selection, which hls-bitrate=max
      // keeps pinned to the best variant — no reload on the common path.
      _player.setVideoTrack(VideoTrack.auto());
    } else {
      final track = nearestTrackForHeight(_videoTracks, height);
      if (track != null) _player.setVideoTrack(track);
    }
    _flashControls();
  }
```

- [ ] **Step 6: Keep controls visible while the quality panel is open**

In `_flashControls()`, extend the auto-hide guard so an open quality panel also blocks hiding. Change:

```dart
      if (mounted && _playing && !_serverPanelOpen) {
```

to:

```dart
      if (mounted && _playing && !_serverPanelOpen && !_qualityPanelOpen) {
```

- [ ] **Step 7: Add the Quality button next to the Server button**

In `_controls(...)`, in the bottom transport `Row`, immediately before the existing Server `_CtrlButton` (the one with `icon: Icons.dns_outlined`), add:

```dart
              _CtrlButton(
                icon: Icons.high_quality,
                label: t['quality'],
                onPressed: hasSelectableQualities(_videoTracks)
                    ? () => setState(() => _qualityPanelOpen = true)
                    : null,
              ),
```

(The existing `_CtrlButton` already greys itself out when `onPressed` is null, so single-quality streams show a disabled button.)

- [ ] **Step 8: Render the quality panel**

In `build(...)`, find the line `if (_serverPanelOpen) Positioned.fill(child: _serverPanel(t)),` and add directly below it:

```dart
                    if (_qualityPanelOpen)
                      Positioned.fill(child: _qualityPanel(t)),
```

- [ ] **Step 9: Add the `_qualityPanel` widget method**

Add this method to `_PlayerScreenState`, right after the existing `_serverPanel` method (keep it inside the class, before the closing brace):

```dart
  Widget _qualityPanel(Map<String, String> t) {
    final options = buildQualityOptions(_videoTracks, autoLabel: t['autoQuality']!);
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Container(
        width: 560,
        height: double.infinity,
        color: AppColors.bg1,
        padding: const EdgeInsets.fromLTRB(44, 80, 44, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(17),
                    gradient:
                        const LinearGradient(colors: AppColors.primaryGradient)),
                child: const Icon(Icons.high_quality,
                    size: 32, color: AppColors.onPrimary),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t['quality']!,
                        style: const TextStyle(
                            fontFamily: Fonts.display,
                            fontFamilyFallback: Fonts.fallback,
                            fontWeight: FontWeight.w600,
                            fontSize: 38,
                            color: AppColors.ink)),
                    Text(t['chooseQuality']!,
                        style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: AppColors.inkMute)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 26),
            Expanded(
              child: ListView(
                children: [
                  for (int i = 0; i < options.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _ServerOption(
                        label: options[i].label,
                        selected: options[i].height == _quality,
                        autofocus: options[i].height == _quality,
                        onPressed: () => _setQuality(options[i].height),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _CtrlButton(
              icon: Icons.close,
              label: t['back'],
              onPressed: () => setState(() => _qualityPanelOpen = false),
            ),
          ],
        ),
      ),
    );
  }
```

- [ ] **Step 10: Verify it analyzes cleanly**

Run: `flutter analyze lib/screens/player_screen.dart`
Expected: No issues. (`VideoTrack` resolves via the existing `package:media_kit/media_kit.dart` import; `_ServerOption`, `_CtrlButton`, `AppColors`, `Fonts` are already in this file.)

- [ ] **Step 11: Commit**

```bash
git add lib/screens/player_screen.dart
git commit -m "feat: quality picker button + panel in player"
```

---

## Task 5: Full verification

**Files:** none (verification only)

- [ ] **Step 1: Run the whole test suite**

Run: `flutter test`
Expected: PASS, including the existing `playback_error_policy_test.dart` and the new `video_quality_test.dart`.

- [ ] **Step 2: Analyze the whole project**

Run: `flutter analyze`
Expected: No new issues introduced by these changes.

- [ ] **Step 3: Manual smoke check (on device/emulator, if available)**

Open a Stardima episode that resolves to a master playlist:
- Quality button is enabled; panel lists Auto + real resolutions (e.g. 1080p/720p/480p).
- Picking 480p visibly drops quality; picking Auto/1080p restores it.
Open an Arabic Toons `.mp4` episode:
- Quality button is greyed (single quality) — expected, not a bug.

---

## Self-Review Notes

- **Spec coverage:** Auto-default fix → Task 2; detected option list → Task 1 + Task 4 Step 9; nearest-match pinning → Task 1 + Task 4 Step 5; disabled-when-single-quality → Task 1 (`hasSelectableQualities`) + Task 4 Step 7; reset-to-Auto-per-episode → Task 4 Step 4; side-panel UI → Task 4 Steps 7-9; i18n → Task 3; tests → Task 1; diagnostic-via-track-list → inherent in Task 4 Step 3. All spec sections mapped.
- **Type consistency:** `QualityOption.height` (`int?`), `_quality` (`int?`), `buildQualityOptions(..., {required String autoLabel})`, `nearestTrackForHeight(List<VideoTrack>, int) -> VideoTrack?`, `hasSelectableQualities(List<VideoTrack>) -> bool`, `_setQuality(int?)` — names/signatures match across tasks.
- **No persistence / no YouTube changes** — intentionally absent, per spec non-goals.
