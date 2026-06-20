# TV Feature Batch 2 — Design

**Date:** 2026-06-20
**Status:** Approved (pending user spec review)

Four independent work items for the Kartoonia Android-TV app, shipped as **two
tracks**:

- **Track A — Quick wins** (no special hardware to verify): trailer/theme
  queries, screensaver info card, logo + banner redesign.
- **Track B — Voice search fix** (must be verified on the user's real Android TV
  box): compact overlay, remove listening delay, fix "no result" on Arabic.

Each track gets its own implementation plan so Track A is never blocked on
hardware availability.

---

## 1. Voice search — fix real-device behavior (Track B)

### Problem (observed on a real Android TV box)
1. The listening UI is an oversized full-screen panel; the user wants a simple,
   compact experience "like the YouTube TV app."
2. There is a noticeable delay between tapping the mic and getting any "now
   listening" feedback.
3. Speaking produces **no result / no query text** — most often with Arabic.

### Root causes (from current code)
- **Oversized overlay:** `lib/widgets/voice_search_sheet.dart` renders a 360×360
  `_MicOrb` with 46px text centered full-screen. This is the "big panel." It is
  *not* the system dialog — recognition already runs in-app via
  `SpeechRecognizer.startListening` (no system UI).
- **Delay:** the recognizer is cold-created on tap in `MainActivity.startVoice`
  → `createSpeechRecognizer` → bind `RecognitionService` → `startListening` →
  wait for `onReadyForSpeech` before any feedback shows.
- **No result:** the device's default recognizer likely cannot handle `ar-SA`
  (no on-device Arabic model), returning `ERROR_NO_MATCH` /
  language-not-supported. The Dart layer (`voice_search_sheet.dart` `_run`)
  silently closes on any error, so the user sees nothing at all.

### Approach

**Native — extract recognition into a focused `VoiceRecognizer.kt`** (out of
`MainActivity.kt`; `MainActivity` keeps only channel wiring + permission
plumbing):

- **Pre-warm:** add a `prepare` method on the voice `MethodChannel`. The search
  screen calls it on mount so the `SpeechRecognizer` instance is created and the
  `RecognitionService` is bound *before* the user taps. `start` then only calls
  `startListening`, removing the cold-bind latency.
- **Force the capable recognizer:** set `EXTRA_PREFER_OFFLINE = false` to prefer
  the online (Google) recognizer, which supports Arabic where the on-device
  model usually does not. Continue passing `EXTRA_LANGUAGE`,
  `EXTRA_LANGUAGE_PREFERENCE`, and add a sane fallback.
- **Surface errors instead of silent close:** map `onError` codes to user
  messages. On `ERROR_NO_MATCH` / `ERROR_SPEECH_TIMEOUT`, show a brief "Didn't
  catch that — try again" and allow a retry rather than dismissing.
- **Temporary diagnostic:** during the device-verification step, display the raw
  error code on screen so the exact failure on the user's box is known before
  the final fix is locked in. Removed once the cause is confirmed.

**Flutter — compact YouTube-TV-style overlay** (`voice_search_sheet.dart`):

- Replace the full-screen orb with a **compact bar** (small mic + thin live
  waveform driven by `rms` + partial-text line). D-pad focus-trapped; Back
  cancels.
- Show "Listening…" feedback **immediately on open** (don't wait for
  `onReadyForSpeech`), backed by the pre-warmed recognizer so it's truthful.
- The Dart `VoiceSearchService` state machine (Idle / Initializing / Listening /
  Processing / Success / Error) is formalized to drive the bar and the
  retry/error affordance.

### Verification reality
The "no result" fix cannot be fully confirmed without the user's TV logcat. The
Track B plan includes an explicit **diagnose-on-device** checkpoint (run, read
the surfaced error code / logcat, confirm cause) before finalizing.

---

## 2. Trailer / theme-song queries (Track A)

`lib/screens/detail_screen.dart` (~line 209) builds the YouTube search query.
Replace with the user's chosen phrasing:

- Movie button → `"<title> trailer"`
- Show button → `"<title> arabic theme song"`

Drops the prior Arabic full-movie phrasing and the year suffix. Localized button
labels (`trailer_btn` / `theme_btn`) are unchanged.

---

## 3. Screensaver — Netflix-style info card (Track A)

`lib/widgets/ambient_overlay.dart` currently crossfades backdrop **URLs** only,
discarding the item, so no metadata can be shown.

### Approach
- Keep the **item** (not just its backdrop URL) for the active slide.
- Add a bottom-left **info card** over a subtle bottom scrim, fading in with each
  crossfade:
  - **Title** (large).
  - **Meta line**: year • TMDB rating • Movie/Series type, plus genre(s) when
    available. (Exact field sourcing confirmed against the catalog model in the
    plan.)
- Add a **live clock** in a top corner, updated each minute via a `Timer`.
- Optional gentle Ken-Burns drift on the backdrop (cheap; confirmed in plan).
- All additions are TV-only and suppressed while the player is active, exactly
  as the existing screensaver already gates.

---

## 4. Logo + banner (Track A)

### Logo (`lib/widgets/kartoonia_brand.dart`)
- Redraw the mark as a crisp **`CustomPainter`** vector — modern geometry with an
  integrated play/spark glyph rather than the current abstract white blob.
- **Palette:** the user is open to a new modern palette. The plan proposes a
  direction (the current coral→amber kept as a fallback option) for approval
  before implementation.
- Used everywhere the brand lockup appears (splash, top bar). Scales perfectly,
  no raster asset.

### Banner
- A reusable **code-drawn banner** composition for in-app use (e.g. splash/hero).
- The **Android TV launcher banner** is provided as a **vector drawable** (XML:
  gradient + logo paths), referenced from the manifest — no image generation
  required. The user can later swap in photographic artwork.

---

## Out of scope
- No change to the recognition transport (already native `SpeechRecognizer` over
  `MethodChannel`/`EventChannel`) beyond the fixes above.
- No new external image assets generated by the assistant (cannot produce
  photographic rasters); banner art the user may supply later is out of scope.
- No unrelated refactoring of the player, catalog, or search pipelines.
