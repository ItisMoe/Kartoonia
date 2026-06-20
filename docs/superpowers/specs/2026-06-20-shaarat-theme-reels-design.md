# شارات — Theme-Song Reels Feed

**Date:** 2026-06-20
**Status:** Approved design, ready for implementation plan
**Platforms:** Android TV + phone

## Summary

A new **شارات** ("theme songs") tab — a vertical, swipeable reels feed that
plays the Arabic dubbed theme songs of famous classic/popular animated shows
(Spacetoon / Cartoon Network / Disney — Conan, Beyblade, Gumball, Bakugan,
etc.). Each reel links straight into the show. The feed is built from titles
already in the catalog, so every reel can deep-link to a real Detail screen, and
each show's theme video is found via the existing YouTube search path.

## Goals

- A reels-style discovery surface for nostalgic/popular cartoon theme songs.
- Every reel can "Enter the show" (deep-link to the catalog Detail screen).
- Feels random but stays on the popular/classic set.
- Reuse the existing single shared player and YouTube resolution path — no new
  decoders, minimal YouTube API quota.

## Non-Goals

- No social graph: no like counts, comments, sharing, or download rail.
- No movies (theme songs are a show thing; movies are out of the pool).
- No new video extraction stack — reuse `youtube_explode` / `PlayerService`.

## User-Facing Behavior

### The tab
- **TV:** a `شارات` item in `TopBar`, placed between Home and TV, routed via a
  new `AppNav.shaarat(...)` to `ShaaratScreen`.
- **Phone:** a 5th item in `PhoneRoot`'s bottom nav (keep-alive in the
  `IndexedStack`), icon = music/play-note. `phoneTabProvider` now indexes
  0=Home, 1=Browse, 2=Search, 3=My List, 4=شارات (see Open Questions for order;
  default appends شارات last).

### One reel (card)
A full-screen vertical page. Composition depends on the Settings play mode:

- **Video mode (default):** the show's `backdropUrl` blurred + dimmed fills the
  screen; the 16:9 theme video plays **intact** (letterboxed), centered.
- **Audio-only mode:** the poster (phone) / backdrop (TV) fills the card; only
  the theme audio plays.

**Footer (identical in both modes), C-style, bottom-anchored:**
- A small now-playing bar: `♪ <title> — شارة` + a static equalizer motif.
- The show title (large, RTL).
- A footer row: **ادخل المسلسل** primary button + a small **heart** toggle
  beside it. No other actions.

### Interaction
- **Phone:** swipe up/down between reels (vertical `PageView`). Tap **ادخل
  المسلسل** → `PhoneDetailScreen`. Tap heart → toggle like.
- **TV:** D-pad **up/down** moves between reels; the focus ring lives on the
  footer row so **left/right** moves between the heart and the Enter button,
  **OK** activates. **Back** exits the tab. Enter → `DetailScreen`.
- A reel whose theme can't be found or won't play is **silently skipped** to the
  next one (never shows an error card mid-feed).

## Architecture

### Components (each independently testable)

1. **`ShaaratFeed` (pure, `lib/services/shaarat_feed.dart`)**
   Builds and orders the ordered list of shows for the session.
   - Input: the catalog's shows + the set of liked show ids.
   - Pool: `isFamous && isAnimation` **shows only**, deduped by TMDB id —
     identical predicate to `famousPool` in `fame_ranking.dart` (factor the
     predicate so both call it). Movies excluded.
   - Order: a **weighted daily shuffle**. Base weight 1.0; liked shows get a
     boost (e.g. ×3) so they surface earlier and more often. Implemented as a
     deterministic weighted permutation seeded by the calendar day (mirrors
     `dailyShuffled`) so the order is stable within a day/session but rotates
     daily. Avoid back-to-back repeats of the same TMDB id.
   - Output: `List<Show>` (the play queue). Pure — no I/O, unit-tested.

2. **`ShaaratResolver` (`lib/services/shaarat_resolver.dart`)**
   Resolves a `Show` → a playable theme (videoId + streams), with a permanent
   per-show videoId cache to protect YouTube API quota.
   - `Future<String?> videoIdFor(Show)`:
     1. Look up the show id in the **persistent videoId cache**
        (`StorageService`). Cache hit (real id) → return it. Cache hit
        (negative sentinel = "searched, none found") → return null without an
        API call.
     2. Miss → one `YoutubeService.searchVideoIds("<title> arabic theme song")`
        call, store the top id (or the negative sentinel) permanently, return.
   - Stream URLs themselves are **not** cached (they expire ~6h): the videoId is
     re-extracted to a stream via `YoutubeStreamResolver.resolvePlayback`
     **per play** — extraction costs **no API quota**.
   - Audio-only mode resolves/plays the **audio-only** stream
     (`YoutubePlayback.audioUrl`) when available — smaller and faster.

3. **`ShaaratScreen` (TV) + phone reel widget**
   The vertical `PageView`. On page-active:
   - Stop the shared player, resolve the active reel, open it on
     `PlayerService` (same one-decoder rule as `YoutubeScreen`).
   - **Prefetch:** kick off `ShaaratResolver.videoIdFor` for the next 1–2 reels
     in the background so swiping is instant (resolve videoId only; stream
     extraction happens when the page becomes active).
   - Reuses the same lifecycle discipline as `YoutubeScreen`: pause on
     lifecycle-not-resumed, `PlayerService.instance.stop()` (not dispose) on
     leave, phone orientation handling (the reel video is landscape inside a
     portrait page — keep the page portrait, letterbox the video; do **not**
     force landscape like the full trailer player).

### Persistence (StorageService additions)
- `kt/shaaratLikes` — `StringList` of liked show ids (same pattern as
  watchlist): `getShaaratLikes()`, `isShaaratLiked(id)`, `toggleShaaratLike(id)`.
- `kt/shaaratVideoIds` — JSON `{ showId: "videoId" | "" }` where `""` is the
  negative sentinel ("searched, none found"). `getShaaratVideoId(id)`,
  `setShaaratVideoId(id, videoIdOrEmpty)`. Permanent (never auto-expired).
- Play mode lives in the existing `kt/prefs` map as
  `shaaratMode: 'video' | 'audio'`, default `'video'` (added to `getPrefs()`
  defaults). Read/written through `SettingsNotifier.setPref`.

### State (app_state.dart)
- `shaaratLikesProvider` (Set<String>) exposed for the heart's reactive state,
  updated on toggle (mirrors the watchlist provider).
- Feed list is built once per session from `catalogProvider` + likes; rebuilt on
  `catalogRevProvider` change (source switch / import) like other catalog UI.

### Settings
- A new toggle row in both `settings_screen.dart` (TV) and
  `phone_settings_screen.dart` (phone): **"شارات: فيديو / صوت فقط"** (Video /
  Audio-only), bound to the `shaaratMode` pref. Follows the existing
  motion/autoplay toggle pattern.

### i18n
New keys in `lib/i18n/strings.dart` (ar + en): `nav_shaarat`, `shaarat_enter`
("ادخل المسلسل" / "Enter show"), `shaarat_now_playing`, `shaarat_mode_label`,
`shaarat_mode_video`, `shaarat_mode_audio`, `shaarat_empty` (no eligible shows).

## Data Flow (one reel becoming active)

```
page becomes active
  → ShaaratResolver.videoIdFor(show)        (cache hit → instant; miss → 1 search, cached forever)
      → null  → skip to next reel
      → id    → YoutubeStreamResolver.resolvePlayback(id)   (extraction, no quota)
                  → video mode: PlayerService.openWithAudio(best≤720 + audio)
                  → audio mode: PlayerService.open(audioUrl)
  → meanwhile: prefetch videoIdFor(next 1–2 shows) in background
Enter button → AppNav.detail(show)  /  openPhoneDetail(show)
Heart        → StorageService.toggleShaaratLike(show.id) → shaaratLikesProvider
```

## Error Handling
- Search miss / negative sentinel / extraction failure → **skip** to the next
  reel; the queue advances so the user never sees a dead card.
- YouTube quota / network errors from `YoutubeService` are caught per-reel and
  treated as a skip (the bundled key may be exhausted; the user's own key in
  Settings still applies via `getYoutubeKey()`).
- Empty pool (un-enriched catalog with no famous animation shows) → a single
  `shaarat_empty` placeholder instead of a blank feed.

## Performance / Quota
- Each show is searched **at most once ever** (then cached permanently), so
  steady-state tab usage costs ~0 API units. Worst case is first-run warm-up,
  bounded by the famous-show count and naturally rate-limited by swipe speed +
  the 1–2-ahead prefetch (we never bulk-search the whole pool).
- One shared decoder for all reels (same rule as the main/trailer player) — fast
  swiping can't exhaust the Android-TV decoder pool.

## Testing
- `ShaaratFeed`: pool filtering (shows-only, animation-only, dedupe), weighted
  order (liked boost, no back-to-back repeat), determinism within a day.
- `ShaaratResolver`: cache hit (no search), negative sentinel (no re-search),
  miss → search + store. Mock `YoutubeService`.
- `StorageService`: like toggle + videoId cache round-trips.
- Widget smoke test for the reel footer (title, Enter, heart toggle) is
  optional given the heavy player dependency.

## Open Questions (sensible defaults chosen; revisit if wrong)
- Phone bottom-nav position for شارات: default **appended last** (index 4).
- Liked-show weight multiplier: default **×3**.
- Prefetch depth: default **next 2** reels (videoId only).
