# شارات Reels — TV-Room Frame, Engagement Boost & Player Fixes

**Date:** 2026-06-20
**Status:** Approved design (pending user review)
**Builds on:** `2026-06-20-shaarat-theme-reels-design.md`

A batch of changes to the شارات (theme-song) reels feed: a new illustrated
"boy watching an old TV" player frame, replacement of the manual like-heart with
an implicit engagement boost, auto-advance between reels, a small playback-status
line, smaller footer buttons, and two player bug fixes (video re-playing from the
start; some titles freezing).

---

## 1. Player fixes

### 1.1 Video replays from the start ~2s in (reels + trailer)

**Root cause.** `PlayerService.openWithAudio` (`lib/services/player_service.dart:70`)
opens the video and lets it start playing, *then* attaches the external audio
track:

```dart
await _player!.open(Media(videoUrl));              // video plays immediately
if (audioUrl != null) await _player!.setAudioTrack(AudioTrack.uri(audioUrl)); // ~1-2s later
```

For YouTube 720p+ the video and audio are separate streams. Attaching the audio
track forces libmpv to rebuild its pipeline and re-seek the video to ~0, while the
freshly-added audio starts from its own 0 — so the video "jumps back" and the
audio doesn't.

**Fix.** Build the full graph before playback starts:

```dart
await _player!.open(Media(videoUrl, httpHeaders: headers), play: false);
if (audioUrl != null) await _player!.setAudioTrack(AudioTrack.uri(audioUrl));
await _player!.play();
```

`open(..., play: false)` then `play()` is a no-op behaviourally for the muxed
path (no external track) and fixes the adaptive path. The trailer's `_openAndWait`
(`lib/screens/youtube_screen.dart:185`) still settles on first `duration > 0`,
which fires regardless of `play`, so its loading gate is unaffected.

### 1.2 Some titles freeze mid-view

Two contributing causes, addressed by design rather than guessed at:

1. **The reload stall** above — partly fixed by 1.1.
2. **Heavy codecs on weak TV decoders.** A 720p VP9/AV1 variant can stutter or
   freeze on low-end Android-TV boxes.

**Design response for reels (see §2.4):** the CRT screen is *small*, so reels do
not need high resolution. Reels prefer the **muxed** (combined A/V, ~360–480p,
AVC) stream. This both removes the separate-audio path (so 1.1's bug class can't
occur in reels at all) and avoids the heaviest codecs — the most likely freeze
trigger. If a residual freeze remains after this change, it gets a focused
systematic-debugging pass with on-device logs; we do not pre-emptively add more
machinery.

---

## 2. The TV-Room player frame

### 2.1 Concept

Replace the plain blurred-backdrop / fullscreen-video presentation with an
illustrated dark bedroom: a boy watching a retro CRT, walls of posters and
scattered cartoon figures (Spacetoon-era: Grendizer, Conan, Goku, Yu-Gi-Oh,
Pokémon…). The live theme **video plays inside the CRT screen**. The room is
**always** the backdrop; the existing Video/Audio toggle controls only what is on
the CRT.

### 2.2 Assets

Two illustrations, already produced and in `assets/`:

| File | Size | Used by |
|------|------|---------|
| `assets/tv-clean.png` | 1376×768 (16:9) | TV (landscape) |
| `assets/phone-clean.png` | 768×1376 (9:16) | phone (portrait) |

Both must be registered under `flutter/assets` in `pubspec.yaml`. (Note the
known Windows asset file-lock quirk — overwrite in place, don't `os.replace`.)

### 2.3 Screen rectangle

The CRT screen position is stored as a normalized `Rect` (LTRB as fractions of
the image) per asset, in a small const map — resolution-independent and easy to
nudge:

```dart
// fractions of the asset's width/height; fine-tuned by eye against the art
const kTvRoomScreen   = Rect.fromLTRB(0.430, 0.335, 0.570, 0.570); // tv-clean
const kPhoneRoomScreen= Rect.fromLTRB(0.390, 0.360, 0.660, 0.580); // phone-clean
```

These are starting values measured from the art; the implementer tunes them
visually until the video sits flush in the bezel.

### 2.4 Rendering

A new widget `TvRoomStage` composes, back-to-front:

1. The room image (`Image.asset`, `BoxFit.cover`, full-bleed).
2. The CRT content, positioned into the screen rect via a `LayoutBuilder` +
   `Positioned` (rect fractions × the laid-out size):
   - **Video mode:** the shared `Video` surface (`PlayerService.controller`),
     `BoxFit.cover`, clipped with `ClipRRect` (small corner radius matching the
     CRT), inset ~1–2px so it doesn't bleed past the bezel.
   - **Audio mode:** the show's poster (`Image.network`), same clip/fit.
   - While `_loading`, the slot stays empty (the art's painted glow shows
     through) — no black hole.
3. A subtle CRT overlay confined to the screen rect: a faint scanline texture +
   soft inner vignette + a low-opacity additive bloom so the moving video melts
   into the painted glow.

The reel feed keeps its **one shared video surface** rule — `TvRoomStage` renders
the single `PlayerService` `Video`, just positioned into the rect instead of
full-bleed. Swiping still swaps media on the shared player (no per-page `Video`).

`ShaaratFeedView._ReelBackground` is replaced by `TvRoomStage`. The
blurred-backdrop code (`lib/widgets/shaarat_reel.dart:414-463`) is removed.

### 2.5 Reel stream selection

In `ShaaratFeedView._playActive`, reels prefer the muxed stream first (small CRT,
stability, no external-audio path):

- **Video mode:** `pb.muxedFallbackUrl` → `PlayerService.open(muxed)`. Only if
  null, fall back to the adaptive `pb.videos.first` + external audio (now safe via
  §1.1).
- **Audio mode:** unchanged (`pb.audioUrl ?? pb.muxedFallbackUrl`).

---

## 3. Auto-advance

Currently the active reel loops forever
(`_player.setPlaylistMode(PlaylistMode.loop)`, `lib/widgets/shaarat_reel.dart:178`).

**New behaviour:** the theme plays once to its end, then the feed advances to the
next reel.

- Drop the `loop` playlist mode.
- `ShaaratFeedView` subscribes to `PlayerService.instance.player.stream.completed`
  (mirroring the trailer screen). On a completed event, when this view is the
  active driver and not loading: award the completion boost (§4) and
  `_goTo(_active + 1)`.
- **End of queue:** re-roll via the existing `_restart()` so the feed is endless
  (fresh popularity-weighted order), rather than dead-ending.
- The subscription is cancelled in `dispose`/`_stopPlayer`, and guarded by the
  same `_loadToken`/`active` checks so a stale completion can't advance a
  backgrounded feed.

---

## 4. Engagement boost (replaces the like-heart)

### 4.1 Signals (graduated, stacking)

A show accumulates **boost points** from three implicit signals; stronger intent
= more points:

| Signal | When | Points |
|--------|------|--------|
| Dwell | stayed on the reel ≥ `kDwell` (8s) before leaving | +1 |
| Completion | theme played to its end (§3) | +2 |
| Enter | tapped "Enter show" from the reel | +4 |

Each signal is awarded **at most once per reel-view** (a visit to that page),
debounced by a per-view `Set<signal>` so re-buffering or a quick back-and-forth
can't farm points.

### 4.2 Storage & state

- Replace `kt/shaaratLikes` (StringList) with `kt/shaaratBoosts` — a JSON map
  `showId -> double`. Old likes are ignored (no migration needed; the feature is
  young). `StorageService` gains:
  - `Map<String,double> getShaaratBoosts()`
  - `Future<void> addShaaratBoost(String showId, double points)`
- Replace `shaaratLikesProvider` (`Set<String>`) with
  `shaaratBoostsProvider` (`Map<String,double>`), seeded from storage.

### 4.3 Ranking

`shaaratQueue` takes the boost map instead of the like set. The per-show weight
becomes:

```dart
var w = sqrt(fame);                 // existing popularity compression
w *= 1 + kBoostK * log(1 + score);  // diminishing-returns engagement multiplier
```

`kBoostK ≈ 0.6` (a show with several stacked engagements roughly doubles its
weight; returns taper so one obsessively-watched show never dominates). No hard
cap needed — `log` self-limits. Deterministic with an injected `Random` for
tests, as today.

### 4.4 UI impact

The heart button and `_toggleLike` are removed from the footer (§5).

---

## 5. Footer: smaller buttons + status line

`_Footer` (`lib/widgets/shaarat_reel.dart:466`) changes:

- **Remove** the 50×50 heart button and its row.
- **Shrink** the "Enter show" button substantially: from `height: 50` /
  `fontSize: 18` to a compact pill (~`height: 34`, `fontSize: 13`, smaller icon
  and padding). It no longer shares a row with the heart, so it can be an
  intrinsic-width pill rather than `Expanded`.
- **Status line:** a tiny text (`fontSize: 11`, low opacity) above or beside the
  now-playing pill showing playback state — `t['shaarat_loading']` ("Loading…")
  while resolving/opening, `t['shaarat_playing']` ("Playing") once playing. This
  is driven by `_loading` plus a `player.stream.playing` subscription. Its real
  value is in **audio mode**, where there's no video to confirm something is
  happening — the user can see *why* it's silent (still loading) vs. playing.

New i18n keys (ar + en) in `lib/i18n/strings.dart`: `shaarat_loading`,
`shaarat_playing`. The now-playing pill and title shrink slightly to sit
comfortably over the room art's bottom gradient.

---

## 6. Components touched

| File | Change |
|------|--------|
| `lib/services/player_service.dart` | `openWithAudio` play-order fix (§1.1) |
| `lib/widgets/tv_room_stage.dart` (new) | room + CRT compositing (§2.4) |
| `lib/widgets/shaarat_reel.dart` | use `TvRoomStage`; muxed-first; auto-advance + completed sub; boost tracking; footer rework; status line |
| `lib/services/shaarat_feed.dart` | `shaaratQueue(shows, boosts, …)` weight (§4.3) |
| `lib/services/storage_service.dart` | boost map read/write; drop likes |
| `lib/state/app_state.dart` | `shaaratBoostsProvider` replaces `shaaratLikesProvider` |
| `lib/i18n/strings.dart` | `shaarat_loading`, `shaarat_playing` |
| `pubspec.yaml` | register `tv-clean.png`, `phone-clean.png` |

## 7. Testing

- **Unit (`test/shaarat_feed_test.dart`):** weighting with boost scores —
  graduated points change order deterministically; zero-boost matches prior
  fame-only behaviour; `log` diminishing returns (a huge score doesn't fully
  crowd out others).
- **Unit (`test/shaarat_storage_test.dart`):** boost map round-trips;
  `addShaaratBoost` accumulates; absent show reads 0.
- **Manual / on-device:** video sits flush in the CRT on both TV and phone;
  audio mode shows the poster on the CRT + status line; theme plays once and
  auto-advances; end-of-queue re-rolls; no mid-reel restart; trailer (720p)
  still starts cleanly after the play-order fix.

## 8. Out of scope / YAGNI

- No per-character art work — the room art is a fixed illustration.
- No angled/perspective CRT (assets are face-on by design).
- No boost decay over time, no "reset boosts" UI (can add later if wanted).
- No quality picker for reels (muxed-first is deliberate).
