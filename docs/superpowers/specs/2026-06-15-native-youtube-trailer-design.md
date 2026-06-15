# Native YouTube trailer / theme-song playback

**Date:** 2026-06-15
**Status:** Approved (design)

## Goal

Replace the iframe-based YouTube trailer/theme-song player with playback in the
app's own native player. Keep the existing "search YouTube → first result" logic
exactly as it is today; only change *how the video plays* — extract the direct
stream URL (the way `yt-dlp` does) and feed it to the existing
`video_player`/ExoPlayer surface (the way the Python reference fed it to VLC).

## Reference behavior (the Python script)

The user's working Python prototype:

1. `yt_dlp.extract_info(url)` → resolves a direct, playable stream URL from a
   YouTube link (it reimplements YouTube's signature-cipher unscrambling).
2. `vlc.media_new(stream_url)` + `player.play()` → plays that URL in a native
   player, not an iframe.

Flutter equivalent:

| Python | Flutter |
|---|---|
| `yt_dlp.extract_info(...)['url']` | `youtube_explode_dart` → muxed stream URL |
| `vlc.media_new(url)` + `play()` | `VideoPlayerController.networkUrl(url)` (existing) |
| Tkinter window | `YoutubeScreen` Flutter UI |

## Trade-off (accepted)

YouTube hands clients a *scrambled* signature token; YouTube's own player JS
unscrambles it into a real `googlevideo.com` URL. The iframe uses YouTube's own
player, so unscrambling is internal and never breaks — but it is YouTube's
player (their chrome, a heavy WebView). `youtube_explode_dart`, like `yt-dlp`,
reimplements the unscrambling itself, producing a URL we can play in our own
player. The cost: when YouTube changes its cipher, extraction fails until the
package is bumped (same as periodically updating `yt-dlp`). On failure the user
sees a graceful "couldn't load" screen. This cost is accepted as the unavoidable
price of playing YouTube in our own player.

## Scope

### In scope
- Add `youtube_explode_dart` dependency.
- Remove `webview_flutter` and `webview_flutter_android` dependencies.
- New `YoutubeStreamResolver` service that turns a videoId into a playable URL.
- Rewrite `YoutubeScreen` to play via `video_player` with TV controls
  (play/pause, D-pad seek scrub bar, back, auto-close on end).
- Unit test for the muxed-stream selection logic.

### Out of scope
- The YouTube Data API search (`YoutubeService.firstVideoId`) is unchanged.
- The main streaming player (`player_screen.dart`) is untouched.
- Adaptive/1080p+ streams. We use muxed (single-file) streams ≤720p only.

## Architecture / units

### 1. `YoutubeService.firstVideoId(query)` — UNCHANGED
Existing YouTube Data API `search.list` call (`maxResults=1`). This is the
"which video" step and keeps working exactly as today.

### 2. `YoutubeStreamResolver` — NEW (`lib/services/youtube_stream_resolver.dart`)
Single responsibility: turn a videoId into a playable direct URL.

- `Future<String?> resolve(String videoId)`
  - Uses `YoutubeExplode`, reads the muxed stream manifest for the video.
  - Picks the highest-quality **muxed** stream whose height is ≤720p (falls back
    to the lowest available muxed stream if every muxed stream is >720p; returns
    `null` if there are no muxed streams at all).
  - Returns the chosen stream's `.url.toString()`.
  - Closes the `YoutubeExplode` instance in a `finally`.
- The muxed-stream selection is extracted into a small pure function
  (e.g. `pickMuxedUrl(Iterable<MuxedStreamInfo>)`) so it can be unit-tested
  without network access. This is the testable seam.

Isolating `youtube_explode_dart` behind this one service keeps the dependency in
a single place (swappable, like the Python `extract_stream_url` method).

### 3. `YoutubeScreen` — REWRITTEN (`lib/screens/youtube_screen.dart`)
Same purpose and entry point (`navigation.dart` `YoutubeScreen(query, title)`),
new internals.

Flow on open:
1. `firstVideoId(query)` (with the user's optional Settings API key, as today).
2. `YoutubeStreamResolver.resolve(id)`.
3. `VideoPlayerController.networkUrl(url)`, `initialize()`, autoplay.

UI:
- Reuses the existing **loading** state (`t['yt_searching']`) and **failure**
  state (`t['yt_none']` + focusable Back button) verbatim. Any of: no video id,
  no playable stream, or controller init error → failure state.
- Video surface: `VideoPlayer` inside an `AspectRatio` centered on black
  (mirrors `player_screen.dart`).
- TV controls (lean — this is a trailer, not an episode):
  - Autoplay on init.
  - **OK/Enter** toggles play/pause.
  - A focusable **scrub bar** (D-pad LEFT/RIGHT = ±10s), reusing the pattern of
    the existing `_ScrubBar` in `player_screen.dart` (position/duration labels,
    gradient fill, focus thumb). LTR-forced so it fills left→right under RTL.
  - **Back** button (existing) exits.
  - Auto-pop when the video reaches its end.
  - No server panel, no episode prev/next, no progress persistence.
- Disposal: pause then dispose the controller (no audio leak), matching
  `player_screen.dart`'s teardown. Pause on app background/lifecycle change.

## Error handling
- Network/transport/HTTP/quota error from the API search → failure state
  (caught as today).
- `resolve()` returns null (no muxed stream / cipher change / geo-block) →
  failure state.
- Controller `initialize()` throws or `value.hasError` → failure state.
- No webview fallback (webview removed).

## Testing
- `test/youtube_stream_resolver_test.dart`: unit-test `pickMuxedUrl` selection:
  - picks highest ≤720p when a mix is present,
  - falls back to lowest when all >720p,
  - returns null on empty input.
- Existing tests must still pass; `flutter analyze` clean.

## Files touched
- `pubspec.yaml` — add `youtube_explode_dart`; remove `webview_flutter*`.
- `lib/services/youtube_stream_resolver.dart` — new.
- `lib/screens/youtube_screen.dart` — rewritten (no webview).
- `test/youtube_stream_resolver_test.dart` — new.
