# Mobile Player Improvements — Design

Date: 2026-06-18
Status: Approved (scope + tap behavior confirmed by user)

## Problem

The player (`lib/screens/player_screen.dart`) is a single screen shared by TV and
phone. It was authored for TV (D-pad focus, fixed 1920×1080 canvas scaled to the
panel via `TvScaler`/`FittedBox`). On phones two things break:

1. **Controls never reappear after auto-hide.** The only thing that re-shows
   hidden controls is `_playerKeys`, an `onKeyEvent` handler — it fires on
   D-pad/keyboard only. Touch produces no key events, and the hidden control
   overlay is wrapped in `IgnorePointer`, so taps fall through to the video
   surface (which has `NoVideoControls`) and do nothing. There is no touch path
   to bring controls back.

2. **Buttons are too small.** Controls are laid out in canvas pixels (e.g. a 64px
   button on a 1920px canvas). That reads fine on a TV across the room but is
   tiny on a phone held at arm's length.

## Scope

Targeted fixes + touch polish. **TV behavior is unchanged** — every change gates
on `!_isTv` (already captured in the screen as `_isTv`). Layout stays on the
existing scaled canvas; we enlarge canvas-px values for phones and add a
phone-only touch layer. No playback/streaming/resolver logic is touched.

## Changes

### 1. Tap-to-toggle controls (core bug fix)
Add a full-screen `GestureDetector` in the outer `Stack`, layered above the
`Video` but below the `TvScaler` controls overlay, enabled only when `!_isTv`:
- Controls hidden → tap reveals them and restarts the auto-hide timer
  (`_flashControls()`).
- Controls shown → tap on an empty area **hides immediately**. Taps on actual
  buttons still hit the buttons (they live in the overlay above and absorb their
  own taps via their opaque `GestureDetector`s); only empty-area taps reach this
  detector.

Works because the hidden overlay is already `IgnorePointer(ignoring: !shown)`, so
taps fall through to the detector when hidden, and empty-area taps fall through
when shown.

### 2. Double-tap sides to seek ±10s
Same detector: `onDoubleTapDown` captures the x-position, `onDoubleTap` seeks
−10s (left half) / +10s (right half) and flashes the controls. Single-tap still
toggles; Flutter disambiguates single vs double tap.

### 3. Larger touch targets on phones (canvas-px, ~1.5×)
Thread a `phone` bool into the control widgets:
- `_CtrlButton`: circle 64→96, big 80→124; icon 30→44, big 38→58; label-pill
  height 64→92, label font 20→28, icon-in-pill 28→40.
- `_ScrubBar`: hit-area height 28→60, track 8→14, thumb 26→36 (focused 30→42);
  time-label font 22→28. Keeps tap/drag-to-seek.
- Top bar: enlarged back button; title/episode/server-chip fonts nudged up.

### 4. Wider/taller server panel on phones
Panel width 560→760, option vertical padding 22→30, larger row font. Easier to
tap.

## Risk
Low. The gesture layer is phone-only and additive; size changes are driven by a
`phone` flag. TV path untouched. Manual verification on a phone/emulator in
landscape: auto-hide → tap restores; tap empty hides; double-tap seeks; buttons
comfortably tappable; server panel usable.
