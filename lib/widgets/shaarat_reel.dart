import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../models/content_item.dart';
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

/// Boost points awarded per engagement signal (graduated, stacking). Each is
/// granted at most once per reel-view; stronger intent earns more.
const double _kDwellBoost = 1; // stayed on the reel past [_kDwell]
const double _kCompleteBoost = 2; // theme played all the way to its end
const double _kEnterBoost = 4; // tapped "Enter show" from the reel
const Duration _kDwell = Duration(seconds: 8);

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
/// The theme plays once and the feed auto-advances to the next reel; the end of
/// the queue re-rolls for an endless feed. Engagement is tracked implicitly:
/// dwelling on, finishing, or entering a show's reel boosts how often it
/// resurfaces (see [_kDwellBoost]/[_kCompleteBoost]/[_kEnterBoost]).
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
  List<Show> _queue = const [];

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

  /// Engagement signals already awarded for the CURRENT reel-view, so each
  /// (dwell/complete/enter) boosts a show at most once per visit to its page.
  final Set<String> _awarded = {};
  Timer? _dwellTimer; // fires [_kDwellBoost] after lingering on a reel

  /// Live subscriptions to the shared player (completion → auto-advance; playing
  /// → status line). Cancelled whenever this view stops driving playback.
  final List<StreamSubscription> _subs = [];

  final FocusNode _enterFocus = FocusNode(debugLabel: 'shaaratEnter');

  Player get _player => PlayerService.instance.player;

  bool get _shouldPlay =>
      widget.active && !_covered && _appResumed && mounted && _queue.isNotEmpty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _resolver = ShaaratResolver(ref.read(storageProvider));
    _buildQueue();
  }

  void _buildQueue() {
    final shows = ref.read(catalogProvider).shows;
    final boosts = ref.read(shaaratBoostsProvider);
    _queue = shaaratQueue(shows, boosts);
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
          if (mounted && widget.isTv) _enterFocus.requestFocus();
        });
      }
    } else {
      if (_started) {
        _started = false;
        _stopPlayer();
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
      }
    }
  }

  /// Subscribe to the shared player: completion auto-advances the feed (and
  /// awards the completion boost); playing-state drives the status line.
  void _subscribe() {
    if (_subs.isNotEmpty) return;
    final p = _player;
    _subs.addAll([
      p.stream.completed.listen((done) {
        if (done && _shouldPlay && _started && !_loading) {
          _award(_kCompleteBoost);
          _advance();
        }
      }),
      p.stream.playing.listen((pl) {
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

  /// Award [points] to the active show, but only once per signal per reel-view.
  void _award(double points) {
    if (_queue.isEmpty) return;
    final show = _queue[_active];
    final key = '${show.id}:$points';
    if (!_awarded.add(key)) return;
    ref.read(storageProvider).addShaaratBoost(show.id, points);
    final next = {...ref.read(shaaratBoostsProvider)};
    next[show.id] = (next[show.id] ?? 0) + points;
    ref.read(shaaratBoostsProvider.notifier).state = next;
  }

  /// (Re)start the dwell timer for the active reel; fires the small dwell boost
  /// if the user lingers past [_kDwell].
  void _armDwell() {
    _dwellTimer?.cancel();
    _dwellTimer = Timer(_kDwell, () {
      if (_shouldPlay && _started) _award(_kDwellBoost);
    });
  }

  /// Re-roll the queue and jump back to the top. Called every time the feed
  /// becomes active (a fresh TV push, or re-selecting the phone tab), so each
  /// visit opens on a new, popularity-weighted random reel instead of replaying
  /// the show you saw last time.
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
    _awarded.clear(); // a new reel-view: engagement signals start fresh
    _dwellTimer?.cancel();
    if (mounted) setState(() => _loading = true);
    PlayerService.instance.ensureCreated();
    await PlayerService.instance.stop();
    final show = _queue[index];

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
      await _playActive(pb, audioOnly);
    } catch (_) {
      if (token == _loadToken && mounted) _skip(index);
      return;
    }
    if (token != _loadToken || !mounted) return;
    // Play the theme ONCE; completion auto-advances (see [_subscribe]).
    _player.setPlaylistMode(PlaylistMode.none);
    _skips = 0;
    setState(() => _loading = false);
    _armDwell();
    _prefetch(index);
  }

  /// Open the active reel. The CRT screen is small, so reels prefer the MUXED
  /// (combined audio+video, ~360-480p AVC) stream: it needs no external-audio
  /// attach (the play-order reload that made video restart mid-reel can't
  /// happen) and avoids the heavy VP9/AV1 variants that stutter on weak TV
  /// decoders. Adaptive video+audio is only a fallback when no muxed exists.
  Future<void> _playActive(YoutubePlayback pb, bool audioOnly) async {
    if (audioOnly) {
      final url = pb.audioUrl ?? pb.muxedFallbackUrl;
      if (url == null) throw Exception('no audio stream');
      await PlayerService.instance.open(url);
      return;
    }
    final muxed = pb.muxedFallbackUrl;
    if (muxed != null) {
      await PlayerService.instance.open(muxed);
      return;
    }
    if (pb.videos.isNotEmpty) {
      final v = pb.videos.first;
      await PlayerService.instance
          .openWithAudio(v.url, audioUrl: v.muxed ? null : pb.audioUrl);
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
      _resolver.videoIdFor(_queue[i]).then((id) {
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
    _dwellTimer?.cancel();
    await _unsubscribe();
    _player.setPlaylistMode(PlaylistMode.none);
    await PlayerService.instance.stop();
  }

  void _enterShow(Show show) {
    _award(_kEnterBoost); // strongest intent signal
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
    _dwellTimer?.cancel();
    _unsubscribe();
    if (_started) {
      _player.setPlaylistMode(PlaylistMode.none);
      PlayerService.instance.stop();
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

    final audioMode = ref.watch(settingsProvider).prefs['shaarat'] == 'audio';

    // What plays inside the CRT: the ONE shared video surface (mounted once and
    // reused across pages — re-creating a `Video` per page detaches the shared
    // decoder's texture), or the active show's poster in audio mode.
    final Widget crtChild = audioMode
        ? Image.network(_queue[_active].posterUrl,
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
          show: _queue[_active],
          t: t,
          statusLabel: _loading ? t['shaarat_loading']! : t['shaarat_playing']!,
          enterFocus: _enterFocus,
          onEnter: () => _enterShow(_queue[_active]),
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
/// title, and a small "Enter show" button. No like control — engagement is
/// implicit (see the boost signals on [_ShaaratFeedViewState]).
class _Footer extends StatelessWidget {
  final Show show;
  final Map<String, String> t;

  /// "Loading…" / "Playing" — small text so the user can tell, especially in
  /// audio mode, why it's silent (still resolving) vs. actually playing.
  final String statusLabel;
  final FocusNode enterFocus;
  final VoidCallback onEnter;
  const _Footer({
    required this.show,
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
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black.withValues(alpha: 0.9), Colors.transparent],
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
                        child: Text('${show.title} — ${t['shaarat_now']}',
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
              Text(show.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      color: Colors.white)),
              const SizedBox(height: 12),
              // Small "Enter show" pill, styled to belong to the room: frosted
              // dark glass with a warm amber edge + glow echoing the CRT light.
              // Focus (TV) brightens it to a clear white target.
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Focusable(
                  focusNode: enterFocus,
                  onPressed: onEnter,
                  builder: (context, focused) => ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: focused
                              ? Colors.white.withValues(alpha: 0.92)
                              : Colors.black.withValues(alpha: 0.42),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: focused
                                ? Colors.white
                                : _kCrtGlow.withValues(alpha: 0.7),
                            width: 1.4,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: _kCrtGlow
                                  .withValues(alpha: focused ? 0.55 : 0.3),
                              blurRadius: focused ? 18 : 12,
                              spreadRadius: focused ? 1 : 0,
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.play_arrow,
                                size: 17,
                                color: focused ? AppColors.onFocus : _kCrtGlow),
                            const SizedBox(width: 5),
                            Text(t['shaarat_enter']!,
                                style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: focused
                                        ? AppColors.onFocus
                                        : Colors.white)),
                          ],
                        ),
                      ),
                    ),
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
