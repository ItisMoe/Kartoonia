# Player Resolution Selector — Design

**Date:** 2026-06-16
**Status:** Approved (design), pending implementation plan
**Scope:** Episode/movie player only. YouTube trailer/theme 720p is explicitly **out of scope** (tracked separately — different code path, different failure modes).

## Problem

Episodes often play at low quality even when the source offers higher. Root cause is source-dependent:

- **Arabic Toons** (`token_service.dart`): the page exposes direct files (`serverN` / `videoSrc`), almost always a **single-quality `.mp4` per host**. The numbered "servers" are *different hosts, not qualities*. An `.mp4` has one video track — nothing to select; quality is whatever the file is.
- **Stardima** (`stardima_resolver.dart`): resolves to `.m3u8`. `bestStreamUrl()` prefers `master.m3u8`. A **master playlist** carries multiple variant qualities — the only path where selection is meaningful. Two ways it stays low:
  1. Many embed hosts return a **single-variant media playlist**, not a true master — one quality only.
  2. When it *is* a master, libmpv exposes variants as selectable video tracks, but the code never inspects or pins them, so the demuxer's default pick wins.

**Honest constraint:** a selector can only offer qualities the *extracted stream actually contains*. Single-`.mp4` and single-variant streams will only ever show "Auto." The higher quality visible on the website lives behind a URL the extractor doesn't reach; no player-side change can conjure it.

## Goals

1. Default to the **highest** available variant instead of the demuxer's default (the core "always low" fix).
2. Give the user a **Quality picker**: Auto + the resolutions the stream actually exposes (detected live, not a hardcoded 360/720/1080 list).
3. Degrade gracefully: when a stream has no real choice, the picker is disabled — which itself signals "this source is single-quality."

## Non-goals

- YouTube trailer/theme 720p (separate spec).
- Changing the extraction/resolver pipeline to find renditions the site hides.
- Persisting the quality choice (per decision: reset to Auto each episode).
- True seamless ABR (libmpv selects a variant per open; switching reloads that variant — acceptable).

## Decisions (confirmed)

- **Auto = highest, adaptive.** Default is Auto; Auto lands on the best variant. Specific picks pin that resolution.
- **No persistence.** Every episode starts on Auto; the picker is per-playback.
- **UI = side panel**, mirroring the existing Server panel (same TV remote focus flow).

## Components

### 1. `lib/services/video_quality.dart` — pure, unit-tested

Isolated selection math (mirrors the `playback_error_policy.dart` pattern). Operates on `media_kit`'s `VideoTrack` (which exposes `id`, `h`, `w`, `bitrate`, `fps`).

```
class QualityOption {
  final int? height;   // null = Auto
  final String label;  // 'Auto' or '720p'  (label text localized at call site)
}

/// Auto first, then one entry per DISTINCT real height (h != null && h > 0),
/// deduped, sorted high -> low.
List<QualityOption> buildQualityOptions(List<VideoTrack> tracks);

/// The VideoTrack whose h is closest to [height]; null if no track has a height.
VideoTrack? nearestTrackForHeight(List<VideoTrack> tracks, int height);

/// True only when >= 2 distinct real heights exist (drives the disabled state).
bool hasSelectableQualities(List<VideoTrack> tracks);
```

Notes:
- "Distinct height" dedupe avoids listing the same `720p` twice when a master has multiple 720p variants.
- Tracks with null/zero `h` (e.g. the synthetic `auto`/`no` tracks, audio-only artifacts) are ignored for option-building.
- `QualityOption.label` carries the bare `"${h}p"` for resolutions; the "Auto" string is localized where the panel is built, not hardcoded here.

### 2. `PlayerService` — the default-low fix

In `ensureCreated()`, after building the `Player`, set the libmpv property `hls-bitrate=max` via `NativePlayer`:

```
if (p.platform is NativePlayer) {
  (p.platform as NativePlayer).setProperty('hls-bitrate', 'max'); // fire-and-forget
}
```

This makes the **initial** variant pick the highest, independent of the UI. Set once on the long-lived shared player; survives every `open()`.

### 3. `PlayerScreen` — state + UI

State:
- Subscribe to `player.stream.tracks`; store `_videoTracks` (the `.video` list).
- `_selectedQuality` (`int?` height; `null` = Auto). **Reset to `null` on every `_load`.**
- `_qualityPanelOpen` (bool), managed exactly like `_serverPanelOpen` (keeps controls from auto-hiding while open).

UI:
- New **Quality** `_CtrlButton` beside the Server button (icon `Icons.high_quality` or `Icons.hd`), `onPressed` opens the panel. Disabled (`onPressed: null`, the existing greyed style) when `!hasSelectableQualities(_videoTracks)`.
- `_qualityPanel(t)` — cloned from `_serverPanel`: right-aligned panel, header, a list of `buildQualityOptions(...)` rendered with the existing `_ServerOption` widget (or a thin equivalent), check mark on the active option, Back button. Selecting calls `_setQuality`.

Selection:
```
void _setQuality(int? height) {
  setState(() { _qualityPanelOpen = false; _selectedQuality = height; });
  if (height == null) {
    _player.setVideoTrack(VideoTrack.auto());   // hls-bitrate=max keeps it on best
  } else {
    final track = nearestTrackForHeight(_videoTracks, height);
    if (track != null) _player.setVideoTrack(track);
  }
  _flashControls();
}
```

Auto leans on `hls-bitrate=max` so the common path needs **no** manual track switch (no reload); only an explicit resolution pick triggers a variant switch.

### 4. i18n — `lib/i18n/strings.dart`

Add to **both** the English and Arabic maps:
- `quality` — button label ("Quality" / "الجودة")
- `chooseQuality` — panel subtitle ("Choose quality" / "اختر الجودة")
- `autoQuality` — the Auto option label ("Auto" / "تلقائي")

## Data flow

```
open(url) ──> PlayerService has hls-bitrate=max ──> stream starts on best variant
          └─> player.stream.tracks fires ──> _videoTracks populated
                                          └─> Quality button enables iff >=2 distinct heights
user picks height ──> setVideoTrack(nearestTrackForHeight) ──> libmpv switches variant
user picks Auto   ──> setVideoTrack(VideoTrack.auto())     ──> back to default (best) selection
new _load (episode/server change) ──> _selectedQuality reset to null (Auto)
```

## Error / edge handling

- **No variants / single quality:** `hasSelectableQualities` false → button disabled. No crash, clear signal.
- **Requested height absent after a server switch:** options are rebuilt from the new track list; `_selectedQuality` already reset to Auto on `_load`, so no stale pin is applied to a stream that lacks it.
- **`setVideoTrack` on a stream mid-buffer:** acceptable brief reload; guarded only by the existing player error/stall handling — no special-casing.
- **Tracks arrive after the panel is opened:** panel reads `_videoTracks` from state; a `setState` on the tracks subscription refreshes it live.

## Testing

`test/video_quality_test.dart` (pure, no device needed):
- `buildQualityOptions`: dedupe of equal heights; high→low ordering; Auto always first; ignores null/zero-height tracks; labels are `"${h}p"`.
- `nearestTrackForHeight`: exact match; nearest when no exact (e.g. request 1080 with {1080,720,480} and with {720,480}); null when no track has a height.
- `hasSelectableQualities`: false for 0/1 distinct heights, true for ≥2.

UI and the `hls-bitrate` property are not unit-tested (no device harness), matching current test scope. The track-enumeration also serves as the live diagnostic for whether higher renditions exist on a given source.

## Diagnostic bonus

Opening any "looks low" stream now reveals, via the picker (or its disabled state), whether higher variants actually exist — distinguishing a player-side limit from a source-side single-quality stream.
