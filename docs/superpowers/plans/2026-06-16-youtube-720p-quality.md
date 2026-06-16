# YouTube 720p + Quality Picker Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Play YouTube trailers/theme songs at up to 720p (video-only stream + external audio), with a quality picker and a muxed-360p fallback.

**Architecture:** A new adaptive resolver turns a videoId into a `YoutubePlayback` (≤720 mp4-preferred video options + best audio URL + muxed fallback). `PlayerService.openWithAudio` opens a video-only stream and attaches the audio as an external track. `youtube_screen.dart` plays Auto, falls back to muxed on failure, and offers a shared `QualityPanel` (also retrofitted into the episode player).

**Tech Stack:** Flutter, media_kit (libmpv) 1.2.6, youtube_explode_dart 3.1.0, flutter_test.

---

## File Structure

- **Modify** `lib/services/youtube_stream_resolver.dart` — add models (`VideoStreamCandidate`, `AudioStreamCandidate`, `YtVideoOption`, `YoutubePlayback`), pure selectors (`pickBestAudioUrl`, `selectVideoOptions`), and the network `resolvePlayback`. Keep `MuxedOption`/`pickMuxedUrl`; remove the now-unused `resolve`.
- **Modify** `test/youtube_stream_resolver_test.dart` — tests for the new pure selectors.
- **Modify** `lib/services/player_service.dart` — add `openWithAudio`.
- **Create** `lib/widgets/quality_panel.dart` — shared right-side quality picker.
- **Modify** `lib/screens/player_screen.dart` — retrofit `_qualityPanel` to use `QualityPanel`.
- **Modify** `lib/screens/youtube_screen.dart` — resolve adaptive, play Auto + fallback, quality picker.

Test command: `flutter test` · Analysis: `flutter analyze`

---

## Task 1: Adaptive resolver models + pure selectors

**Files:**
- Modify: `lib/services/youtube_stream_resolver.dart`
- Test: `test/youtube_stream_resolver_test.dart`

- [ ] **Step 1: Add the failing tests**

Append these groups inside `main()` in `test/youtube_stream_resolver_test.dart` (it already imports `package:kartoonia/services/youtube_stream_resolver.dart` and `package:flutter_test/flutter_test.dart`):

```dart
  group('pickBestAudioUrl', () {
    test('returns null when empty', () {
      expect(pickBestAudioUrl(const []), isNull);
    });
    test('picks the highest bitrate', () {
      expect(
        pickBestAudioUrl(const [
          AudioStreamCandidate(bitrate: 128000, url: 'a', isMp4: true),
          AudioStreamCandidate(bitrate: 256000, url: 'b', isMp4: false),
        ]),
        'b',
      );
    });
    test('prefers mp4 on a bitrate tie', () {
      expect(
        pickBestAudioUrl(const [
          AudioStreamCandidate(bitrate: 128000, url: 'webm', isMp4: false),
          AudioStreamCandidate(bitrate: 128000, url: 'mp4', isMp4: true),
        ]),
        'mp4',
      );
    });
  });

  group('selectVideoOptions', () {
    test('caps at maxHeight and sorts high to low (all video-only)', () {
      final r = selectVideoOptions(const [
        VideoStreamCandidate(height: 360, url: '360', isMp4: true),
        VideoStreamCandidate(height: 1080, url: '1080', isMp4: true),
        VideoStreamCandidate(height: 720, url: '720', isMp4: true),
      ]);
      expect(r.map((o) => o.height).toList(), [720, 360]);
      expect(r.every((o) => o.muxed == false), isTrue);
    });
    test('prefers mp4 when a height has both mp4 and webm', () {
      final r = selectVideoOptions(const [
        VideoStreamCandidate(height: 720, url: '720webm', isMp4: false),
        VideoStreamCandidate(height: 720, url: '720mp4', isMp4: true),
      ]);
      expect(r.length, 1);
      expect(r.first.url, '720mp4');
    });
    test('keeps webm when a height has no mp4', () {
      final r = selectVideoOptions(const [
        VideoStreamCandidate(height: 480, url: '480webm', isMp4: false),
      ]);
      expect(r.single.url, '480webm');
    });
    test('empty when nothing is at or below the cap', () {
      expect(
        selectVideoOptions(const [
          VideoStreamCandidate(height: 1080, url: '1080', isMp4: true),
        ], maxHeight: 720),
        isEmpty,
      );
    });
  });
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/youtube_stream_resolver_test.dart`
Expected: FAIL — `AudioStreamCandidate` / `VideoStreamCandidate` / `pickBestAudioUrl` / `selectVideoOptions` undefined.

- [ ] **Step 3: Add models + pure selectors**

In `lib/services/youtube_stream_resolver.dart`, ABOVE the existing `class YoutubeStreamResolver` (keep `MuxedOption` and `pickMuxedUrl` as they are), add:

```dart
/// Network-free view of one video-only stream, for [selectVideoOptions].
class VideoStreamCandidate {
  final int height;
  final String url;
  final bool isMp4; // mp4/H.264 preferred for Android-TV hardware decode
  const VideoStreamCandidate(
      {required this.height, required this.url, required this.isMp4});
}

/// Network-free view of one audio-only stream, for [pickBestAudioUrl].
class AudioStreamCandidate {
  final int bitrate;
  final String url;
  final bool isMp4; // m4a/AAC preferred on a tie
  const AudioStreamCandidate(
      {required this.bitrate, required this.url, required this.isMp4});
}

/// A playable video option for the trailer picker. [muxed] true means the URL
/// already carries audio (no external audio track should be attached).
class YtVideoOption {
  final int height;
  final String url;
  final bool muxed;
  const YtVideoOption(
      {required this.height, required this.url, this.muxed = false});
}

/// Everything the trailer player needs: video options (paired with [audioUrl])
/// plus a muxed URL for the failure path.
class YoutubePlayback {
  final List<YtVideoOption> videos; // mp4-preferred, deduped, <=cap, high->low
  final String? audioUrl;
  final String? muxedFallbackUrl;
  const YoutubePlayback(
      {required this.videos,
      required this.audioUrl,
      required this.muxedFallbackUrl});
}

/// Best audio-only URL: highest bitrate; on a tie prefer mp4/m4a. Null if empty.
String? pickBestAudioUrl(List<AudioStreamCandidate> options) {
  if (options.isEmpty) return null;
  final sorted = [...options]..sort((a, b) {
      final byBitrate = b.bitrate.compareTo(a.bitrate);
      if (byBitrate != 0) return byBitrate;
      if (a.isMp4 == b.isMp4) return 0;
      return a.isMp4 ? -1 : 1; // mp4 first on tie
    });
  return sorted.first.url;
}

/// Video-only options at or below [maxHeight], one per distinct height (mp4
/// preferred when a height offers both), sorted high -> low.
List<YtVideoOption> selectVideoOptions(List<VideoStreamCandidate> options,
    {int maxHeight = 720}) {
  final byHeight = <int, VideoStreamCandidate>{};
  for (final o in options) {
    if (o.height <= 0 || o.height > maxHeight) continue;
    final existing = byHeight[o.height];
    if (existing == null || (!existing.isMp4 && o.isMp4)) {
      byHeight[o.height] = o;
    }
  }
  final heights = byHeight.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final h in heights)
      YtVideoOption(height: h, url: byHeight[h]!.url, muxed: false),
  ];
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/youtube_stream_resolver_test.dart`
Expected: PASS (existing `pickMuxedUrl` tests + 7 new ones).

- [ ] **Step 5: Commit**

```bash
git add lib/services/youtube_stream_resolver.dart test/youtube_stream_resolver_test.dart
git commit -m "feat: youtube adaptive stream models + pure selectors

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Network `resolvePlayback` (and drop unused `resolve`)

**Files:**
- Modify: `lib/services/youtube_stream_resolver.dart`

No unit test — wraps the youtube_explode network call (untested, like the existing `resolve`).

- [ ] **Step 1: Replace the `resolve` method body**

In `class YoutubeStreamResolver`, replace the entire `static Future<String?> resolve(String videoId) async { ... }` method with `resolvePlayback`:

```dart
  /// Resolve [videoId] into adaptive playback options (video-only <= [maxHeight]
  /// paired with the best audio, plus a muxed fallback). Returns null when
  /// nothing usable is found. Throws on transport errors (caller handles).
  ///
  /// If no usable audio-only stream exists, the video-only options are dropped
  /// (they would play silent) and only the muxed fallback remains.
  static Future<YoutubePlayback?> resolvePlayback(String videoId,
      {int maxHeight = 720}) async {
    final yt = YoutubeExplode();
    try {
      final manifest = await yt.videos.streamsClient.getManifest(videoId);
      final audioUrl = pickBestAudioUrl([
        for (final s in manifest.audioOnly)
          AudioStreamCandidate(
            bitrate: s.bitrate.bitsPerSecond,
            url: s.url.toString(),
            isMp4: s.container.name.toLowerCase() == 'mp4',
          ),
      ]);
      final videos = audioUrl == null
          ? const <YtVideoOption>[]
          : selectVideoOptions([
              for (final s in manifest.videoOnly)
                VideoStreamCandidate(
                  height: s.videoResolution.height,
                  url: s.url.toString(),
                  isMp4: s.container.name.toLowerCase() == 'mp4',
                ),
            ], maxHeight: maxHeight);
      final muxedFallbackUrl = pickMuxedUrl([
        for (final s in manifest.muxed)
          MuxedOption(
              height: s.videoResolution.height, url: s.url.toString()),
      ]);
      if (videos.isEmpty && muxedFallbackUrl == null) return null;
      return YoutubePlayback(
        videos: videos,
        audioUrl: audioUrl,
        muxedFallbackUrl: muxedFallbackUrl,
      );
    } finally {
      yt.close();
    }
  }
```

- [ ] **Step 2: Verify it analyzes cleanly**

Run: `flutter analyze lib/services/youtube_stream_resolver.dart`
Expected: No issues. (The `YoutubeExplode` import is already present.)

- [ ] **Step 3: Commit**

```bash
git add lib/services/youtube_stream_resolver.dart
git commit -m "feat: resolvePlayback returns adaptive youtube streams

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: `PlayerService.openWithAudio`

**Files:**
- Modify: `lib/services/player_service.dart`

No unit test — drives native libmpv.

- [ ] **Step 1: Add the method**

In `lib/services/player_service.dart`, directly after the existing `open(...)` method, add:

```dart
  /// Open a video-only [videoUrl] and attach [audioUrl] as an external audio
  /// track (how YouTube 720p+ is played: separate video + audio files). libmpv
  /// timestamp-syncs the two. When [audioUrl] is null this behaves like [open].
  Future<void> openWithAudio(
    String videoUrl, {
    String? audioUrl,
    Map<String, String> headers = const {},
  }) async {
    ensureCreated();
    await _player!.open(Media(videoUrl, httpHeaders: headers));
    if (audioUrl != null) {
      await _player!.setAudioTrack(AudioTrack.uri(audioUrl));
    }
  }
```

- [ ] **Step 2: Verify it analyzes cleanly**

Run: `flutter analyze lib/services/player_service.dart`
Expected: No issues. (`AudioTrack` is exported from the already-imported `package:media_kit/media_kit.dart`.)

- [ ] **Step 3: Commit**

```bash
git add lib/services/player_service.dart
git commit -m "feat: PlayerService.openWithAudio (video + external audio)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Shared `QualityPanel` widget + episode-player retrofit

**Files:**
- Create: `lib/widgets/quality_panel.dart`
- Modify: `lib/screens/player_screen.dart` (`_qualityPanel`)

No unit test — pure UI widget (no device harness; matches existing panel scope).

- [ ] **Step 1: Create the shared widget**

Create `lib/widgets/quality_panel.dart`:

```dart
import 'package:flutter/material.dart';
import '../theme/theme.dart';
import 'focusable.dart';

/// Right-side quality picker shared by the episode and trailer players. Generic
/// over its rows: the caller supplies option [labels] and which one is selected.
class QualityPanel extends StatelessWidget {
  final String title; // t['quality']
  final String subtitle; // t['chooseQuality']
  final String backLabel; // t['back']
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onClose;
  const QualityPanel({
    super.key,
    required this.title,
    required this.subtitle,
    required this.backLabel,
    required this.labels,
    required this.selectedIndex,
    required this.onSelect,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
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
                    gradient: const LinearGradient(
                        colors: AppColors.primaryGradient)),
                child: const Icon(Icons.high_quality,
                    size: 32, color: AppColors.onPrimary),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontFamily: Fonts.display,
                            fontFamilyFallback: Fonts.fallback,
                            fontWeight: FontWeight.w600,
                            fontSize: 38,
                            color: AppColors.ink)),
                    Text(subtitle,
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
                  for (int i = 0; i < labels.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _QualityRow(
                        label: labels[i],
                        selected: i == selectedIndex,
                        autofocus: i == selectedIndex,
                        onPressed: () => onSelect(i),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _PillButton(
                icon: Icons.close, label: backLabel, onPressed: onClose),
          ],
        ),
      ),
    );
  }
}

/// One selectable quality row (mirrors the player's server-option styling).
class _QualityRow extends StatelessWidget {
  final String label;
  final bool selected;
  final bool autofocus;
  final VoidCallback onPressed;
  const _QualityRow({
    required this.label,
    required this.selected,
    required this.autofocus,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Focusable(
      autofocus: autofocus,
      onPressed: onPressed,
      builder: (context, focused) {
        final bg = focused ? Colors.white : AppColors.bg2;
        final fg = focused ? AppColors.onFocus : AppColors.ink;
        return AnimatedScale(
          scale: focused ? 1.04 : 1,
          duration: const Duration(milliseconds: 150),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected && !focused
                    ? AppColors.accent
                    : Colors.white.withValues(alpha: 0.06),
                width: 2,
              ),
            ),
            child: Row(children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 25, fontWeight: FontWeight.w800, color: fg)),
              const Spacer(),
              if (selected)
                Icon(Icons.check,
                    color: focused ? AppColors.onFocus : AppColors.accent),
            ]),
          ),
        );
      },
    );
  }
}

/// Pill button used for the panel's close action (mirrors the player ctrl pill).
class _PillButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  const _PillButton(
      {required this.icon, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Focusable(
      onPressed: onPressed,
      builder: (context, focused) {
        final fg = focused ? AppColors.onFocus : AppColors.ink;
        final bg = focused ? Colors.white : Colors.white.withValues(alpha: 0.12);
        return AnimatedScale(
          scale: focused ? 1.06 : 1,
          duration: const Duration(milliseconds: 150),
          child: Container(
            height: 64,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999), color: bg),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 28, color: fg),
              const SizedBox(width: 10),
              Text(label,
                  style: TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800, color: fg)),
            ]),
          ),
        );
      },
    );
  }
}
```

- [ ] **Step 2: Retrofit the episode player to use it**

In `lib/screens/player_screen.dart`, add the import next to the other `../widgets/...` imports:

```dart
import '../widgets/quality_panel.dart';
```

Then replace the entire existing `_qualityPanel(Map<String, String> t)` method with this thin wrapper:

```dart
  Widget _qualityPanel(Map<String, String> t) {
    final options = buildQualityOptions(_videoTracks, autoLabel: t['autoQuality']!);
    final selectedIndex = options.indexWhere((o) => o.height == _quality);
    return QualityPanel(
      title: t['quality']!,
      subtitle: t['chooseQuality']!,
      backLabel: t['back']!,
      labels: [for (final o in options) o.label],
      selectedIndex: selectedIndex < 0 ? 0 : selectedIndex,
      onSelect: (i) => _setQuality(options[i].height),
      onClose: () => setState(() => _qualityPanelOpen = false),
    );
  }
```

- [ ] **Step 3: Verify it analyzes cleanly**

Run: `flutter analyze lib/widgets/quality_panel.dart lib/screens/player_screen.dart`
Expected: No issues. (`buildQualityOptions`, `_videoTracks`, `_quality`, `_setQuality`, `_qualityPanelOpen` already exist in `player_screen.dart`.)

- [ ] **Step 4: Run the full suite (no regressions)**

Run: `flutter test`
Expected: PASS (48 existing + the new resolver tests from Task 1).

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/quality_panel.dart lib/screens/player_screen.dart
git commit -m "refactor: extract shared QualityPanel; reuse in episode player

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: YouTube screen — adaptive play, fallback, picker

**Files:**
- Modify: `lib/screens/youtube_screen.dart`

No unit test — stream/UI wiring (no device harness). Pure logic it relies on is tested in Task 1.

- [ ] **Step 1: Add imports**

In `lib/screens/youtube_screen.dart`, add next to the existing imports:

```dart
import '../widgets/quality_panel.dart';
```
(`youtube_stream_resolver.dart` and `player_service.dart` are already imported.)

- [ ] **Step 2: Add picker state fields**

In `_YoutubeScreenState`, after the existing `bool _ended = false;` field, add:

```dart
  YoutubePlayback? _playback;
  int? _quality; // pinned height, or null for Auto
  bool _qualityPanelOpen = false;
```

- [ ] **Step 3: Generalize `_openAndWait` to take an opener**

Replace the existing `_openAndWait(String url, Duration budget)` method with a version that takes an open callback (so it works for both `openWithAudio` and `open`):

```dart
  /// Run [open], completing once playback starts (first known duration) or
  /// failing fast on a playback error / [budget] timeout. Subscribes before
  /// opening so the first event can't slip past.
  Future<void> _openAndWait(Future<void> Function() open, Duration budget) {
    final p = _player;
    final c = Completer<void>();
    var settled = false;
    late final StreamSubscription dSub;
    late final StreamSubscription eSub;
    void finish([Object? err]) {
      if (settled) return;
      settled = true;
      dSub.cancel();
      eSub.cancel();
      if (!c.isCompleted) {
        err == null ? c.complete() : c.completeError(err);
      }
    }

    dSub = p.stream.duration.listen((d) {
      if (d > Duration.zero) finish();
    });
    eSub = p.stream.error.listen((e) => finish(e));
    open().catchError((Object e) => finish(e));
    return c.future.timeout(budget, onTimeout: () {
      finish();
      throw TimeoutException('open timed out');
    });
  }
```

- [ ] **Step 4: Replace `_start` to resolve adaptive playback**

Replace the body of `_start()` between the `if (ids.isEmpty) return _fail();` line and its `} on YoutubeException` catch with the resolve-and-play flow. The full method becomes:

```dart
  Future<void> _start() async {
    try {
      final userKey = ref.read(storageProvider).getYoutubeKey();
      final ids =
          await YoutubeService.searchVideoIds(widget.query, apiKey: userKey);
      if (!mounted) return;
      if (ids.isEmpty) return _fail();

      // Try each candidate in relevance order until one resolves to playable
      // streams — the top hit is often age/geo-restricted or has no usable
      // streams, and one failure shouldn't sink the whole open.
      YoutubePlayback? playback;
      for (final id in ids) {
        try {
          playback = await YoutubeStreamResolver.resolvePlayback(id);
        } catch (e) {
          debugPrint('YouTube resolve failed for $id: $e');
          playback = null;
        }
        if (!mounted) return;
        if (playback != null) break;
      }
      if (playback == null) return _fail();
      _playback = playback;

      // Play Auto (best <=720 + audio); _playQuality falls back to muxed 360p.
      try {
        await _playQuality(null);
      } catch (e) {
        debugPrint('YouTube playback failed: $e');
        return _fail();
      }
      if (!mounted) return;
      setState(() => _loading = false);
      _flashControls();
    } on YoutubeException catch (e) {
      debugPrint('YouTube trailer failed: $e');
      _fail(e.kind == YoutubeErrorKind.quota
          ? 'yt_quota'
          : e.kind == YoutubeErrorKind.network
              ? 'yt_network'
              : 'yt_error');
    } catch (e) {
      debugPrint('YouTube trailer failed: $e');
      _fail();
    }
  }
```

- [ ] **Step 5: Add the play/quality helpers**

Add these methods right after `_start()`:

```dart
  /// The video option for [height] (null = Auto = best), or null if none exist.
  YtVideoOption? _videoForHeight(YoutubePlayback pb, int? height) {
    if (pb.videos.isEmpty) return null;
    if (height == null) return pb.videos.first;
    for (final v in pb.videos) {
      if (v.height == height) return v;
    }
    return pb.videos.first;
  }

  /// Open the requested quality (null = Auto). Tries the adaptive video+audio
  /// path; on failure falls back to the muxed 360p stream. Throws when nothing
  /// can be played.
  Future<void> _playQuality(int? height) async {
    final pb = _playback;
    if (pb == null) return;
    final video = _videoForHeight(pb, height);
    if (video != null) {
      try {
        await _openAndWait(
          () => PlayerService.instance.openWithAudio(
            video.url,
            audioUrl: video.muxed ? null : pb.audioUrl,
          ),
          const Duration(seconds: 30),
        );
        if (mounted) setState(() => _quality = height);
        return;
      } catch (e) {
        debugPrint('YouTube adaptive open failed, trying muxed: $e');
      }
    }
    final muxed = pb.muxedFallbackUrl;
    if (muxed == null) throw Exception('no playable youtube stream');
    await _openAndWait(
        () => PlayerService.instance.open(muxed), const Duration(seconds: 30));
    if (mounted) setState(() => _quality = null);
  }

  void _setQuality(int? height) {
    setState(() => _qualityPanelOpen = false);
    _playQuality(height).catchError((Object e) {
      debugPrint('YouTube quality switch failed: $e');
      if (mounted) _fail();
    });
    _flashControls();
  }

  List<String> _qualityLabels(Map<String, String> t) => [
        t['autoQuality']!,
        for (final v in (_playback?.videos ?? const <YtVideoOption>[]))
          '${v.height}p',
      ];

  bool get _hasQualityChoice => (_playback?.videos.length ?? 0) >= 2;
```

- [ ] **Step 6: Add the Quality button beside play/pause**

In `_transport(...)`, the play/pause `Focusable` is the second child of the inner `Column`. Wrap it in a centered `Row` that also shows the quality button when there's a choice. Replace the play/pause `Focusable(... _togglePlay ...)` widget with:

```dart
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Focusable(
                  focusNode: _playFocus,
                  onPressed: _togglePlay,
                  builder: (context, focused) => AnimatedScale(
                    scale: focused ? 1.06 : 1,
                    duration: const Duration(milliseconds: 150),
                    child: Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: focused
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.12),
                      ),
                      child: Icon(_playing ? Icons.pause : Icons.play_arrow,
                          size: 28,
                          color: focused ? AppColors.onFocus : AppColors.ink),
                    ),
                  ),
                ),
                if (_hasQualityChoice) ...[
                  const SizedBox(width: 18),
                  Focusable(
                    onPressed: () => setState(() => _qualityPanelOpen = true),
                    builder: (context, focused) => AnimatedScale(
                      scale: focused ? 1.06 : 1,
                      duration: const Duration(milliseconds: 150),
                      child: Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: focused
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.12),
                        ),
                        child: Icon(Icons.high_quality,
                            size: 28,
                            color: focused ? AppColors.onFocus : AppColors.ink),
                      ),
                    ),
                  ),
                ],
              ],
            ),
```

- [ ] **Step 7: Render the panel in the build Stack**

In `build(...)`, immediately after the `if (ready) Positioned.fill( ... _transport(t) ... )` block and before the `// back button` `Positioned(`, add:

```dart
          if (ready && _qualityPanelOpen)
            Positioned.fill(
              child: Builder(builder: (context) {
                final labels = _qualityLabels(t);
                final sel = _quality == null
                    ? 0
                    : labels.indexOf('${_quality}p');
                return QualityPanel(
                  title: t['quality']!,
                  subtitle: t['chooseQuality']!,
                  backLabel: t['back']!,
                  labels: labels,
                  selectedIndex: sel < 0 ? 0 : sel,
                  onSelect: (i) =>
                      _setQuality(i == 0 ? null : _playback!.videos[i - 1].height),
                  onClose: () => setState(() => _qualityPanelOpen = false),
                );
              }),
            ),
```

- [ ] **Step 8: Keep controls visible while the panel is open**

In `_flashControls()`, change the auto-hide guard:

```dart
      if (mounted && _playing) setState(() => _controlsShown = false);
```
to:

```dart
      if (mounted && _playing && !_qualityPanelOpen) {
        setState(() => _controlsShown = false);
      }
```

- [ ] **Step 9: Verify it analyzes cleanly**

Run: `flutter analyze lib/screens/youtube_screen.dart`
Expected: No issues. If the analyzer reports `resolve` is undefined anywhere else, confirm Task 2 removed it and nothing else references it (only this screen did).

- [ ] **Step 10: Commit**

```bash
git add lib/screens/youtube_screen.dart
git commit -m "feat: youtube 720p playback + quality picker with muxed fallback

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: Full verification

**Files:** none.

- [ ] **Step 1: Run the whole suite**

Run: `flutter test`
Expected: PASS — existing tests + the new `pickBestAudioUrl` / `selectVideoOptions` tests.

- [ ] **Step 2: Analyze the project**

Run: `flutter analyze`
Expected: No new issues in changed files (pre-existing `avoid_print` infos in `tool/test_token_fetch.dart` are unrelated).

- [ ] **Step 3: Manual smoke check (device/emulator, if available)**

Open a trailer/theme: confirm it plays sharper than before (≤720p), the Quality button appears with Auto + resolutions, switching changes quality (clip restarts), and a video with only muxed still plays at 360p with no Quality button.

---

## Self-Review Notes

- **Spec coverage:** adaptive resolver/models → Task 1–2; mp4 preference + ≤720 cap → Task 1; best audio → Task 1; muxed fallback selection → Task 2 (reuses `pickMuxedUrl`); `openWithAudio` → Task 3; shared panel + episode retrofit → Task 4; Auto play + fallback + picker + restart → Task 5; tests → Task 1; verification → Task 6. The "drop unused `resolve`" spec note → Task 2.
- **Type consistency:** `YoutubePlayback{videos, audioUrl, muxedFallbackUrl}`, `YtVideoOption{height,url,muxed}`, `VideoStreamCandidate{height,url,isMp4}`, `AudioStreamCandidate{bitrate,url,isMp4}`, `pickBestAudioUrl(List<AudioStreamCandidate>) -> String?`, `selectVideoOptions(List<VideoStreamCandidate>, {int maxHeight}) -> List<YtVideoOption>`, `resolvePlayback(String,{int maxHeight}) -> Future<YoutubePlayback?>`, `openWithAudio(String,{String? audioUrl, Map headers})`, `QualityPanel{title,subtitle,backLabel,labels,selectedIndex,onSelect,onClose}` — consistent across tasks.
- **Restart-on-switch** and **silent-video-without-audio guard** (drop video-only when `audioUrl == null`) are intentional per spec.
