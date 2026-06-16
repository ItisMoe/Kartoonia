# YouTube 720p + Quality Picker — Design

**Date:** 2026-06-16
**Status:** Approved (design), pending implementation plan
**Scope:** YouTube trailer/theme player (`youtube_screen.dart`) + its resolver. Reuses the shared quality-panel UI introduced here for the episode player too.

## Problem

`YoutubeStreamResolver.resolve()` returns a single **muxed** stream URL, and YouTube caps muxed (progressive) streams at **360p**. 720p/1080p exist only as **adaptive** streams where video and audio are separate files. So trailers/theme songs always play at 360p, and there's no way to choose quality.

## Decisions (confirmed)

- **Picker** like the episode player: Auto + the resolutions YouTube actually offers.
- **Max/Auto target = 720p.** Auto picks the best video-only stream ≤720p.
- **Fallback to muxed 360p** if the adaptive (video-only + external audio) path fails to start.
- Shared quality-panel widget used by both the YouTube screen and the episode player (retrofit).
- Quality change **restarts** the clip (re-open from stored URLs) — acceptable for a short trailer; position-preservation is out of scope for v1.

## Approach

The only viable native path to 720p from YouTube is **video-only stream + external audio track**, played via media_kit/libmpv (`AudioTrack.uri(audioUrl)`). Rejected alternatives: iframe/WebView player (deliberately avoided earlier; bypasses the shared decoder) and a server-side muxing proxy (no backend).

**mp4/H.264 is preferred per resolution** for Android-TV hardware decoding — VP9/webm often falls to software decode on cheap TV boxes. We pick mp4 video-only where a resolution offers it, else fall through to whatever container that resolution has.

## Components

### 1. `lib/services/youtube_stream_resolver.dart` — adaptive resolution

Add models + a network resolver + **pure** selection helpers (the existing `MuxedOption`/`pickMuxedUrl` stay and are reused for the fallback):

```dart
class YtVideoOption {
  final int height;
  final String url;
  final bool muxed; // true => already has audio; do NOT attach external audio
}

class YoutubePlayback {
  final List<YtVideoOption> videos; // mp4-preferred, deduped by height, <=720, high->low
  final String? audioUrl;           // best audio-only, paired with video-only options
  final String? muxedFallbackUrl;   // best muxed (<=360) for the failure path
}
```

Pure helpers (testable with plain structs, no network — mirror the existing `MuxedOption` pattern):

```dart
// Reduced, network-free views fed by the resolver from youtube_explode types.
class VideoStreamCandidate { final int height; final String url; final bool isMp4; }
class AudioStreamCandidate { final int bitrate; final String url; final bool isMp4; }

/// Best audio-only URL: highest bitrate; on a tie prefer mp4/m4a. Null if empty.
String? pickBestAudioUrl(List<AudioStreamCandidate> options);

/// Video options <= [maxHeight], one per distinct height (mp4 preferred when a
/// height has both), sorted high->low. Empty when none qualify.
List<YtVideoOption> selectVideoOptions(List<VideoStreamCandidate> options, {int maxHeight = 720});
```

Network wrapper:

```dart
/// Resolve [videoId] into adaptive playback options. Returns null when nothing
/// usable is found. Throws on transport errors (caller handles).
static Future<YoutubePlayback?> resolvePlayback(String videoId, {int maxHeight = 720});
```

It reads `manifest.videoOnly` (→ `VideoStreamCandidate` via `videoResolution.height`, `url.toString()`, `container.name == 'mp4'`), `manifest.audioOnly` (→ `AudioStreamCandidate` via `bitrate.bitsPerSecond`, `container.name`), and `manifest.muxed` (→ existing `pickMuxedUrl` for `muxedFallbackUrl`). If `videos` is empty but a muxed fallback exists, the caller still plays 360p.

`resolve()` (old muxed-only method) is kept for now or removed once the screen no longer calls it — the plan will remove it if unused.

### 2. `lib/services/player_service.dart` — open video + external audio

```dart
Future<void> openWithAudio(String videoUrl, {String? audioUrl, Map<String, String> headers = const {}}) async {
  ensureCreated();
  await _player!.open(Media(videoUrl, httpHeaders: headers));
  if (audioUrl != null) await _player!.setAudioTrack(AudioTrack.uri(audioUrl));
}
```

Existing `open()` stays for muxed/episode use. libmpv timestamp-syncs the external audio (same source → aligned).

### 3. `lib/widgets/quality_panel.dart` — shared picker (new)

A generic right-side panel (extracted from the episode player's `_qualityPanel`): takes a header icon/title/subtitle, a list of `(label, selected)` rows, `onSelect(index)`, and `onClose`. Used by **both** the YouTube screen and the episode player. The episode player's inline `_qualityPanel` is retrofitted to call it so the two can't drift. Reuses the `quality`/`chooseQuality`/`autoQuality` strings.

### 4. `lib/screens/youtube_screen.dart` — picker + fallback

- `_start()`: `resolvePlayback(id)` (try candidates in order, as today), store `YoutubePlayback`. Play **Auto** = first (best) video via `openWithAudio(video.url, audioUrl: video.muxed ? null : audioUrl)`. If `_openAndWait` doesn't start within budget → `PlayerService.open(muxedFallbackUrl)` (360p). If that also fails → existing fail screen.
- State: `YoutubePlayback? _playback`, `int? _quality` (null = Auto).
- Quality button (shown only when `_playback != null && _playback.videos.length >= 2`) opens the shared panel; options = Auto + `_playback.videos` heights.
- `_setQuality(int? h)`: pick Auto (first video) or the matching height; `openWithAudio(...)` again from stored URLs (no re-network). Restarts the clip.

### Data flow

```
search ids -> resolvePlayback(id) -> YoutubePlayback{videos<=720 mp4-pref, audioUrl, muxedFallback}
  -> Auto: openWithAudio(bestVideo, audioUrl)   --start ok--> playing 720p
                                                 --fail/timeout--> open(muxedFallback) 360p
                                                                    --fail--> fail screen
user picks height -> openWithAudio(stored video.url, stored audioUrl)  (restart)
```

## Error handling

- Adaptive open fails (cipher/throttle/timeout) → muxed 360p fallback → fail screen.
- `resolvePlayback` returns null for a candidate → try next id (existing loop).
- Audio-only attach failing while video plays = silent video (low likelihood; the whole-open error path catches the common failures). Documented risk, not specially handled in v1.
- n-param throttling makes adaptive URLs slow → the open budget + muxed fallback cover it.

## Testing

Extend `test/youtube_stream_resolver_test.dart` (pure, no network):
- `pickBestAudioUrl`: highest bitrate wins; mp4 preferred on tie; null when empty.
- `selectVideoOptions`: ≤720 cap; one per distinct height; mp4 preferred when a height has both mp4+webm; high→low order; empty when none qualify.
- existing `pickMuxedUrl` tests stay (reused for fallback).

Resolver network call, `openWithAudio`, and UI are not unit-tested (no device harness) — matches current scope.

## Out of scope

- 1080p+ (cap is 720p).
- Position preservation across a quality switch (restart is fine for a trailer).
- Episode-player behavior changes beyond the shared-panel retrofit.
