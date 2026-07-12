import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../navigation.dart';
import '../screens/phone/phone_nav.dart';
import '../services/player_service.dart';
import '../services/shaarat_feed.dart';
import '../services/shaarat_resolver.dart';
import '../services/youtube_stream_resolver.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import 'focusable.dart';
import 'tv_room_stage.dart';

/// Hard cap on how long a single reel may play. Show themes are short, but the
/// carateen `/music` mp3s can run far longer — past this the feed just moves on
/// to the next title's music.
const Duration _kMaxTheme = Duration(minutes: 4);

/// Warm amber accent echoing the CRT's glow, used to tint the "Enter show" pill
/// so it reads as part of the room scene.
const Color _kCrtGlow = Color(0xFFFFC46B);

/// The شارات reels feed, shared by the TV screen and the phone tab. A vertical
/// `PageView` of famous animated shows; the active reel plays its Arabic theme
/// song on the app's ONE shared [PlayerService] (same one-decoder rule as the
/// trailer/main players), framed inside the illustrated "boy watching an old TV"
/// room ([TvRoomStage]) — the live theme video sits inside the CRT. The footer
/// overlays a now-playing pill, a playback-status line, the title and a small
/// "Enter show" button.
///
/// The theme plays once (capped at [_kMaxTheme]) and the feed auto-advances to
/// the next reel; the end of the queue re-rolls for an endless feed. The order
/// is a pure shuffle of the most popular titles — no engagement ranking.
///
/// Two play modes (Settings `shaarat` pref) only change what's on the CRT:
/// `video` plays the theme video inside the TV; `audio` shows the show's poster
/// on the TV and plays only the theme audio.
class ShaaratFeedView extends ConsumerStatefulWidget {
  /// Drives input (D-pad vs. swipe) and audio-mode framing (backdrop vs poster).
  final bool isTv;

  /// Whether this view is currently the visible tab. The phone shell keeps every
  /// tab alive in an `IndexedStack`, so the reel must only play when selected.
  /// TV pushes it as a route, so it defaults to active.
  final bool active;

  const ShaaratFeedView({super.key, required this.isTv, this.active = true});

  @override
  ConsumerState<ShaaratFeedView> createState() => _ShaaratFeedViewState();
}

class _ShaaratFeedViewState extends ConsumerState<ShaaratFeedView>
    with WidgetsBindingObserver, RouteAware {
  final PageController _pc = PageController();
  late ShaaratResolver _resolver;
  List<ShaaratItem> _queue = const [];

  /// Warmed stream-URL resolutions, keyed by YouTube videoId. Filled by
  /// [_prefetch] for the next reels (and by [_activate] for the current one) so a
  /// swipe usually skips the ~1–2s manifest extraction. Cleared on [_restart]
  /// since the resolved URLs are time-limited.
  final Map<String, Future<YoutubePlayback?>> _pbCache = {};

  int _active = 0;
  int _loadToken = 0; // bumps to cancel in-flight resolves
  int _skips = 0; // consecutive un-playable reels (loop guard)

  bool _started = false; // whether playback is currently driven by this view
  bool _loading = false;
  bool _playing = false; // shared player's playing state (for the status line)
  bool _allFailed = false;
  bool _appResumed = true;
  bool _covered = false; // a route is pushed on top of us

  /// Live subscriptions to the shared player (completion/length-cap →
  /// auto-advance; playing → status line). Cancelled whenever this view stops
  /// driving playback.
  final List<StreamSubscription> _subs = [];

  /// One-shot latch for the [_kMaxTheme] length cap: position events keep
  /// arriving while the next reel is being resolved, so without it a single
  /// over-long track would advance the feed several pages at once.
  bool _capFired = false;

  final FocusNode _enterFocus = FocusNode(debugLabel: 'shaaratEnter');

  Player get _player => PlayerService.instance.player;

  bool get _shouldPlay =>
      widget.active && !_covered && _appResumed && mounted && _queue.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Make sure the shared player + its render controller exist before ANYTHING
    // touches them — `_subscribe` (in `_syncPlayback`), the `Video(controller:)`
    // in build, and the lifecycle pause all read the non-null getters. On a
    // fresh launch (opening شارات before any other video has played) the player
    // would otherwise still be null and the null-check would crash the tab to a
    // blank screen. ensureCreated() is idempotent.
    PlayerService.instance.ensureCreated();
    _resolver = ShaaratResolver(ref.read(storageProvider));
    _buildQueue();
  }

  void _buildQueue() {
    final catalog = ref.read(catalogProvider);
    _queue = shaaratItemQueue(
      catalog.shows,
      catalog.music,
      (t) => catalog.showForThemeTitle(t.title),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) routeObserver.subscribe(this, route);
    _syncPlayback();
  }

  @override
  void didUpdateWidget(covariant ShaaratFeedView old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _syncPlayback();
  }

  // RouteAware: pause when something is pushed over us, resume on return.
  @override
  void didPushNext() {
    _covered = true;
    _syncPlayback();
  }

  @override
  void didPopNext() {
    _covered = false;
    _syncPlayback();
  }

  /// Start or stop playback to match [_shouldPlay].
  void _syncPlayback() {
    if (_shouldPlay) {
      if (!_started) {
        _started = true;
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
        _subscribe();
        _restart();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          // Suppress the ambient screensaver while this tab drives playback —
          // the reels auto-advance with no input, so the TV idle-overlay would
          // otherwise drift in over a playing theme (same flag PlayerScreen
          // uses). Cleared again when we stop driving playback / dispose.
          _suppressScreensaver(true);
          if (widget.isTv) _enterFocus.requestFocus();
        });
      }
    } else {
      if (_started) {
        _started = false;
        _stopPlayer();
        _suppressScreensaver(false);
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
        // Clear the loading state so the CRT static (its animation timer) stops
        // when we leave the tab — otherwise a reel left mid-resolve keeps the
        // snow running on the kept-alive phone tab.
        if (mounted) setState(() => _loading = false);
      }
    }
  }

  void _suppressScreensaver(bool on) {
    ref.read(playerActiveProvider.notifier).state = on;
  }

  /// Subscribe to the shared player: completion (or the [_kMaxTheme] length
  /// cap) auto-advances the feed; playing-state drives the status line.
  void _subscribe() {
    if (_subs.isNotEmpty) return;
    // The service's LIVE views drop events the shared player still emits for
    // the previous media while a reel is being swapped in (a stray completed
    // or a >cap position would advance the feed off a reel that just loaded).
    final svc = PlayerService.instance;
    _subs.addAll([
      svc.completedLive.listen((done) {
        if (done && _shouldPlay && _started && !_loading) {
          _advance();
        }
      }),
      // Length cap: a track that runs past [_kMaxTheme] (long carateen mp3s)
      // moves the feed along instead of monopolizing it.
      svc.positionLive.listen((pos) {
        if (pos >= _kMaxTheme &&
            !_capFired &&
            _shouldPlay &&
            _started &&
            !_loading) {
          _capFired = true;
          _advance();
        }
      }),
      svc.playingLive.listen((pl) {
        if (mounted && _playing != pl) setState(() => _playing = pl);
      }),
    ]);
  }

  Future<void> _unsubscribe() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
  }

  /// Move to the next reel, or re-roll into a fresh order at the end so the feed
  /// is endless.
  void _advance() {
    final next = _active + 1;
    next < _queue.length ? _goTo(next) : _restart();
  }

  /// Re-roll the queue and jump back to the top. Called every time the feed
  /// becomes active (a fresh TV push, or re-selecting the phone tab), so each
  /// visit opens on a fresh random shuffle of the popular titles instead of
  /// replaying the show you saw last time.
  void _restart() {
    _buildQueue();
    _pbCache.clear(); // drop possibly-expired stream URLs from a prior visit
    _active = 0;
    _skips = 0;
    _allFailed = false;
    if (_pc.hasClients) _pc.jumpToPage(0);
    if (mounted) setState(() {});
    _activate(0);
  }

  /// Resolve and play the reel at [index]. Skips to the next reel when the theme
  /// can't be found or won't play.
  Future<void> _activate(int index) async {
    if (_queue.isEmpty) return;
    final token = ++_loadToken;
    _capFired = false; // a new reel-view: the length cap re-arms
    if (mounted) setState(() => _loading = true);
    PlayerService.instance.ensureCreated();
    // Claim the player for this activation: the returned generation stamps
    // every open it issues. If the feed is stopped/covered while a resolve is
    // still in flight (the user pressed "Enter show" mid-load), the late open()
    // becomes a no-op instead of hijacking whatever screen owns the player by
    // then.
    final session = await PlayerService.instance.stop();
    final entry = _queue[index];

    // Carateen music: play the mp3 directly (no YouTube resolve). The CRT shows
    // the track cover (audio-only framing) regardless of the video/audio pref.
    if (entry.isMusic) {
      try {
        await PlayerService.instance.open(entry.audioUrl!,
            headers: entry.audioHeaders ?? const {}, session: session);
      } catch (_) {
        if (token == _loadToken && mounted) _skip(index);
        return;
      }
      if (token != _loadToken || !mounted) return;
      _player.setPlaylistMode(PlaylistMode.none);
      _skips = 0;
      setState(() => _loading = false);
      _prefetch(index);
      return;
    }

    final show = entry.show!;
    final id = await _resolver.videoIdFor(show);
    if (token != _loadToken || !mounted) return;
    if (id == null) return _skip(index);

    // Resolve the playable streams, retrying a couple of times before giving up
    // on this reel — a transient extraction miss usually succeeds on a retry
    // (a failed resolve is evicted from [_pbCache], so each attempt re-extracts).
    YoutubePlayback? pb;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future.delayed(Duration(milliseconds: 500 * attempt));
        if (token != _loadToken || !mounted) return;
      }
      pb = await _playbackFor(id); // reuses a prefetched resolve when warm
      if (token != _loadToken || !mounted) return;
      if (pb != null) break;
    }
    if (pb == null) return _skip(index);

    final audioOnly = ref.read(settingsProvider).prefs['shaarat'] == 'audio';
    try {
      await _playActive(pb, audioOnly, session);
    } catch (_) {
      if (token == _loadToken && mounted) _skip(index);
      return;
    }
    if (token != _loadToken || !mounted) return;
    // Play the theme ONCE; completion auto-advances (see [_subscribe]).
    _player.setPlaylistMode(PlaylistMode.none);
    _skips = 0;
    setState(() => _loading = false);
    _prefetch(index);
  }

  /// Open the active reel. The CRT screen is small, so reels prefer the MUXED
  /// (combined audio+video, ~360-480p AVC) stream: it needs no external-audio
  /// attach (the play-order reload that made video restart mid-reel can't
  /// happen) and avoids the heavy VP9/AV1 variants that stutter on weak TV
  /// decoders. Adaptive video+audio is only a fallback when no muxed exists.
  Future<void> _playActive(YoutubePlayback pb, bool audioOnly, int session) async {
    if (audioOnly) {
      // Prefer the progressive MUXED stream even in audio mode: it's the same
      // stream the (working) video mode plays and reliably carries audio. The
      // adaptive audio-only URL is throttled by YouTube unless fed extra range
      // params libmpv doesn't send, so opening it bare often plays nothing —
      // that's the "audio mode is silent" bug. Fall back to it only if no muxed
      // exists. The video track decodes to no surface (poster covers the CRT).
      final url = pb.muxedFallbackUrl ?? pb.audioUrl;
      if (url == null) throw Exception('no audio stream');
      await PlayerService.instance.open(url, session: session);
      return;
    }
    final muxed = pb.muxedFallbackUrl;
    if (muxed != null) {
      await PlayerService.instance.open(muxed, session: session);
      return;
    }
    if (pb.videos.isNotEmpty) {
      final v = pb.videos.first;
      await PlayerService.instance.openWithAudio(v.url,
          audioUrl: v.muxed ? null : pb.audioUrl, session: session);
      return;
    }
    throw Exception('no playable stream');
  }

  /// Resolve a videoId's playback options, deduped + cached. Failed/empty
  /// resolves are evicted so a later attempt can retry. No decoder is touched —
  /// this is just the network manifest extraction — so it is safe to run ahead.
  Future<YoutubePlayback?> _playbackFor(String id) {
    final existing = _pbCache[id];
    if (existing != null) return existing;
    final future =
        YoutubeStreamResolver.resolvePlayback(id).catchError((_) => null);
    _pbCache[id] = future;
    future.then((pb) {
      if (pb == null) _pbCache.remove(id);
    });
    return future;
  }

  /// Warm the next couple of reels: resolve each videoId, then pre-extract its
  /// stream URLs so swiping plays almost instantly. Limited to 2 ahead because
  /// the resolved URLs expire. Fire-and-forget; results are cached.
  void _prefetch(int index) {
    for (var i = index + 1; i <= index + 2 && i < _queue.length; i++) {
      final show = _queue[i].show;
      if (show == null || _queue[i].isMusic) continue; // mp3 needs no prefetch
      _resolver.videoIdFor(show).then((id) {
        if (id != null && mounted) _playbackFor(id);
      });
    }
  }

  void _skip(int index) {
    _skips++;
    if (_skips > _queue.length) {
      setState(() {
        _loading = false;
        _allFailed = true;
      });
      return;
    }
    final next = index + 1;
    if (next < _queue.length) {
      _goTo(next);
    } else {
      setState(() => _loading = false); // reached the end; leave as-is
    }
  }

  void _goTo(int index) {
    _pc.animateToPage(index,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
  }

  void _onPageChanged(int index) {
    setState(() => _active = index);
    if (_shouldPlay) _activate(index);
  }

  Future<void> _stopPlayer() async {
    _loadToken++; // cancel any in-flight resolve
    await _unsubscribe();
    _player.setPlaylistMode(PlaylistMode.none);
    await PlayerService.instance.stop();
  }

  void _enterShow(ShaaratItem entry) {
    final show = entry.show;
    if (show == null) return; // unlinked music track — nothing to open
    widget.isTv
        ? AppNav.detail(context, show)
        : openPhoneDetail(context, show);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _appResumed = true;
      _syncPlayback();
    } else {
      _appResumed = false;
      _player.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    routeObserver.unsubscribe(this);
    _loadToken++;
    _unsubscribe();
    if (_started) {
      _player.setPlaylistMode(PlaylistMode.none);
      PlayerService.instance.stop();
      _suppressScreensaver(false);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    }
    _pc.dispose();
    _enterFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);

    if (_queue.isEmpty || _allFailed) {
      return _MessageScreen(
        message: t['shaarat_empty']!,
        showBack: widget.isTv,
        backLabel: t['back']!,
      );
    }

    final active = _queue[_active];
    // Music tracks are audio-only by nature (mp3 → show the cover on the CRT);
    // show themes honour the video/audio pref.
    final audioMode =
        active.isMusic || ref.watch(settingsProvider).prefs['shaarat'] == 'audio';

    // What plays inside the CRT: the ONE shared video surface (mounted once and
    // reused across pages — re-creating a `Video` per page detaches the shared
    // decoder's texture), or the active entry's poster/cover in audio mode.
    final Widget crtChild = audioMode
        ? Image.network(active.posterUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const ColoredBox(color: AppColors.bg2))
        : Video(
            controller: PlayerService.instance.controller,
            controls: NoVideoControls,
            fit: BoxFit.cover,
            fill: Colors.black,
          );

    final feed = Stack(
      children: [
        // The illustrated room + CRT, a single static overlay for the whole
        // feed (the art is fixed; only the CRT content changes). The PageView
        // below is a transparent gesture/index source. `IgnorePointer` lets
        // phone swipes reach it.
        Positioned.fill(
          child: IgnorePointer(
            child: TvRoomStage(
              isTv: widget.isTv,
              loading: _loading,
              crtChild: crtChild,
            ),
          ),
        ),
        Positioned.fill(
          child: PageView.builder(
            controller: _pc,
            scrollDirection: Axis.vertical,
            physics: widget.isTv
                ? const NeverScrollableScrollPhysics()
                : const BouncingScrollPhysics(),
            onPageChanged: _onPageChanged,
            itemCount: _queue.length,
            itemBuilder: (context, i) => const SizedBox.expand(),
          ),
        ),
        _Footer(
          item: active,
          t: t,
          statusLabel: _loading ? t['shaarat_loading']! : t['shaarat_playing']!,
          enterFocus: _enterFocus,
          onEnter: () => _enterShow(active),
        ),
        if (widget.isTv)
          Positioned(
            top: 28,
            left: 28,
            child: Focusable(
              onPressed: () => Navigator.maybePop(context),
              builder: (context, focused) => Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: focused
                      ? Colors.white
                      : Colors.black.withValues(alpha: 0.5),
                ),
                child: Icon(Icons.arrow_back,
                    color: focused ? AppColors.onFocus : Colors.white, size: 24),
              ),
            ),
          ),
      ],
    );

    final body = ColoredBox(color: Colors.black, child: feed);
    if (!widget.isTv) return body;

    // TV: a focused footer button receives OK/left/right; up/down bubble here to
    // move between reels.
    return Focus(
      skipTraversal: true,
      canRequestFocus: false,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
          if (_active < _queue.length - 1) _goTo(_active + 1);
          return KeyEventResult.handled;
        }
        if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
          if (_active > 0) _goTo(_active - 1);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: body,
    );
  }
}

/// Bottom-anchored overlay: now-playing pill, a tiny playback-status line, the
/// title, and a small "Enter show" button.
class _Footer extends StatelessWidget {
  final ShaaratItem item;
  final Map<String, String> t;

  /// "Loading…" / "Playing" — small text so the user can tell, especially in
  /// audio mode, why it's silent (still resolving) vs. actually playing.
  final String statusLabel;
  final FocusNode enterFocus;
  final VoidCallback onEnter;
  const _Footer({
    required this.item,
    required this.t,
    required this.statusLabel,
    required this.enterFocus,
    required this.onEnter,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          // A soft scrim, not a heavy bar — the text reads while the room stays
          // visible, so the footer feels part of the scene.
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black.withValues(alpha: 0.66), Colors.transparent],
            stops: const [0, 1],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 54, 22, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // now-playing pill + status
              Row(mainAxisSize: MainAxisSize.min, children: [
                Flexible(
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      const Icon(Icons.music_note,
                          size: 13, color: AppColors.primary2),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text('${item.title} — ${t['shaarat_now']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.inkSoft)),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(width: 8),
                Text(statusLabel,
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.6))),
              ]),
              const SizedBox(height: 10),
              Text(item.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.white)),
              if (item.subtitle.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(item.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.white.withValues(alpha: 0.72))),
              ],
              const SizedBox(height: 10),
              // Compact "Enter show" chip that belongs to the room: frosted dark
              // glass with a warm amber edge whose soft bloom reads like the
              // CRT's light spilling into the scene. Focus (TV) blooms it
              // brighter and flips it to a clear white target.
              // "Enter show" — greyed & inert for a music track with no linked
              // catalog show (still focusable so D-pad nav isn't trapped).
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Focusable(
                  focusNode: enterFocus,
                  onPressed: item.canEnter ? onEnter : () {},
                  builder: (context, focused) => _EnterChip(
                    focused: focused && item.canEnter,
                    enabled: item.canEnter,
                    label: t['shaarat_enter']!,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The small "Enter show" call-to-action. Frosted glass + an amber edge and an
/// outer [_kCrtGlow] bloom so it reads as CRT light caught on a surface in the
/// room rather than a flat button on top. [focused] (TV) brightens it.
class _EnterChip extends StatelessWidget {
  final bool focused;
  final bool enabled;
  final String label;
  const _EnterChip(
      {required this.focused, required this.label, this.enabled = true});

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      // Inert, dimmed variant for an unlinked music track: no amber glow, muted
      // text — reads as "no show to enter" without removing the row.
      return Opacity(
        opacity: 0.4,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Container(
            height: 30,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.32),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: Colors.white24, width: 1.2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.play_arrow, size: 15, color: Colors.white54),
                const SizedBox(width: 5),
                Text(label,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.white54)),
              ],
            ),
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(15),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: focused
                ? Colors.white.withValues(alpha: 0.92)
                : Colors.black.withValues(alpha: 0.32),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(
              color: focused ? Colors.white : _kCrtGlow.withValues(alpha: 0.85),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: _kCrtGlow.withValues(alpha: focused ? 0.6 : 0.38),
                blurRadius: focused ? 22 : 16,
                spreadRadius: focused ? 2 : 1,
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.play_arrow,
                  size: 15, color: focused ? AppColors.onFocus : _kCrtGlow),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: focused ? AppColors.onFocus : Colors.white)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Centered message (empty pool / all reels failed), with an optional back button.
class _MessageScreen extends StatelessWidget {
  final String message;
  final bool showBack;
  final String backLabel;
  const _MessageScreen({
    required this.message,
    required this.showBack,
    required this.backLabel,
  });

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.bg1,
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.music_off, size: 56, color: AppColors.inkMute),
          const SizedBox(height: 16),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  color: AppColors.inkSoft)),
          if (showBack) ...[
            const SizedBox(height: 24),
            Focusable(
              autofocus: true,
              onPressed: () => Navigator.maybePop(context),
              builder: (context, focused) => Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
                decoration: BoxDecoration(
                    color: focused ? Colors.white : AppColors.bg2,
                    borderRadius: BorderRadius.circular(999)),
                child: Text(backLabel,
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: focused ? AppColors.onFocus : AppColors.ink)),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}
