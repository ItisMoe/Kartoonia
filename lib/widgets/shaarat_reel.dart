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

const Color _kHeart = Color(0xFFFF5D7A);

/// The شارات reels feed, shared by the TV screen and the phone tab. A vertical
/// `PageView` of famous animated shows; the active reel plays its Arabic theme
/// song on the app's ONE shared [PlayerService] (same one-decoder rule as the
/// trailer/main players). The footer is an overlay (stable focus across pages):
/// a now-playing pill, the title, an "Enter show" button and a like heart.
///
/// Two play modes (Settings `shaarat` pref): `video` shows the 16:9 theme video
/// intact over a blurred backdrop; `audio` shows the poster (phone) / backdrop
/// (TV) and plays only the theme audio.
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
  bool _allFailed = false;
  bool _appResumed = true;
  bool _covered = false; // a route is pushed on top of us

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
    final likes = ref.read(shaaratLikesProvider);
    _queue = shaaratQueue(shows, likes);
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
    if (mounted) setState(() => _loading = true);
    PlayerService.instance.ensureCreated();
    await PlayerService.instance.stop();
    final show = _queue[index];

    final id = await _resolver.videoIdFor(show);
    if (token != _loadToken || !mounted) return;
    if (id == null) return _skip(index);

    final pb = await _playbackFor(id); // reuses a prefetched resolve when warm
    if (token != _loadToken || !mounted) return;
    if (pb == null) return _skip(index);

    final audioOnly = ref.read(settingsProvider).prefs['shaarat'] == 'audio';
    try {
      await _playActive(pb, audioOnly);
    } catch (_) {
      if (token == _loadToken && mounted) _skip(index);
      return;
    }
    if (token != _loadToken || !mounted) return;
    _player.setPlaylistMode(PlaylistMode.loop); // loop the theme while lingering
    _skips = 0;
    setState(() => _loading = false);
    _prefetch(index);
  }

  Future<void> _playActive(YoutubePlayback pb, bool audioOnly) async {
    if (audioOnly) {
      final url = pb.audioUrl ?? pb.muxedFallbackUrl;
      if (url == null) throw Exception('no audio stream');
      await PlayerService.instance.open(url);
      return;
    }
    if (pb.videos.isNotEmpty) {
      final v = pb.videos.first;
      await PlayerService.instance
          .openWithAudio(v.url, audioUrl: v.muxed ? null : pb.audioUrl);
      return;
    }
    final muxed = pb.muxedFallbackUrl;
    if (muxed == null) throw Exception('no playable stream');
    await PlayerService.instance.open(muxed);
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
    _player.setPlaylistMode(PlaylistMode.none);
    await PlayerService.instance.stop();
  }

  Future<void> _toggleLike(Show show) async {
    final liked = await ref.read(storageProvider).toggleShaaratLike(show.id);
    final next = {...ref.read(shaaratLikesProvider)};
    liked ? next.add(show.id) : next.remove(show.id);
    ref.read(shaaratLikesProvider.notifier).state = next;
  }

  void _enterShow(Show show) {
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
    // Keep the live like-set reflected on the heart.
    ref.watch(shaaratLikesProvider);

    if (_queue.isEmpty || _allFailed) {
      return _MessageScreen(
        message: t['shaarat_empty']!,
        showBack: widget.isTv,
        backLabel: t['back']!,
      );
    }

    final audioMode = ref.watch(settingsProvider).prefs['shaarat'] == 'audio';
    final feed = Stack(
      children: [
        PageView.builder(
          controller: _pc,
          scrollDirection: Axis.vertical,
          physics: widget.isTv
              ? const NeverScrollableScrollPhysics()
              : const BouncingScrollPhysics(),
          onPageChanged: _onPageChanged,
          itemCount: _queue.length,
          itemBuilder: (context, i) => _ReelBackground(
            show: _queue[i],
            isTv: widget.isTv,
            audioMode: audioMode,
          ),
        ),
        // ONE persistent video surface for the whole feed. It is mounted once
        // and reused across page changes — re-creating a `Video` per page (the
        // old approach) detached the shared decoder's texture every time you
        // swiped, so every reel after the first stayed stuck on its blurred
        // backdrop. We just swap the media on the shared player and fade this
        // surface in. `IgnorePointer` lets swipes reach the PageView beneath it.
        if (!audioMode)
          Positioned.fill(
            child: IgnorePointer(
              child: AnimatedOpacity(
                opacity: _loading ? 0 : 1,
                duration: const Duration(milliseconds: 200),
                child: Video(
                  controller: PlayerService.instance.controller,
                  controls: NoVideoControls,
                  fit: BoxFit.contain,
                  fill: Colors.transparent,
                ),
              ),
            ),
          ),
        if (_loading)
          const Center(
            child: CircularProgressIndicator(color: AppColors.primary),
          ),
        _Footer(
          show: _queue[_active],
          t: t,
          liked: ref.watch(shaaratLikesProvider).contains(_queue[_active].id),
          enterFocus: _enterFocus,
          onEnter: () => _enterShow(_queue[_active]),
          onLike: () => _toggleLike(_queue[_active]),
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

/// One reel's background: a blurred, dimmed backdrop (video mode) or a full-cover
/// poster/backdrop (audio mode). The playing video itself is a single shared
/// surface layered above the PageView, not part of this per-page background.
class _ReelBackground extends StatelessWidget {
  final Show show;
  final bool isTv;
  final bool audioMode;
  const _ReelBackground({
    required this.show,
    required this.isTv,
    required this.audioMode,
  });

  @override
  Widget build(BuildContext context) {
    final coverUrl = audioMode && !isTv ? show.posterUrl : show.backdropUrl;
    return Stack(
      fit: StackFit.expand,
      children: [
        // Cover image (blurred behind the video, sharp in audio mode).
        _NetImage(url: coverUrl, blur: !audioMode),
        Container(color: Colors.black.withValues(alpha: audioMode ? 0.25 : 0.45)),
      ],
    );
  }
}

class _NetImage extends StatelessWidget {
  final String url;
  final bool blur;
  const _NetImage({required this.url, required this.blur});

  @override
  Widget build(BuildContext context) {
    Widget img = Image.network(
      url,
      fit: BoxFit.cover,
      errorBuilder: (_, _, _) => const ColoredBox(color: AppColors.bg2),
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : const ColoredBox(color: AppColors.bg2),
    );
    if (blur) {
      img = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: img,
      );
    }
    return img;
  }
}

/// Bottom-anchored overlay: now-playing pill, title, and the Enter + heart row.
class _Footer extends StatelessWidget {
  final Show show;
  final Map<String, String> t;
  final bool liked;
  final FocusNode enterFocus;
  final VoidCallback onEnter;
  final VoidCallback onLike;
  const _Footer({
    required this.show,
    required this.t,
    required this.liked,
    required this.enterFocus,
    required this.onEnter,
    required this.onLike,
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
            colors: [Colors.black.withValues(alpha: 0.88), Colors.transparent],
            stops: const [0, 1],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 60, 22, 34),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // now-playing pill
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.music_note, size: 14, color: AppColors.primary2),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text('${show.title} — ${t['shaarat_now']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: AppColors.inkSoft)),
                  ),
                ]),
              ),
              const SizedBox(height: 12),
              Text(show.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: Colors.white)),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(
                  child: Focusable(
                    focusNode: enterFocus,
                    onPressed: onEnter,
                    builder: (context, focused) => Container(
                      height: 50,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: focused ? Colors.white : AppColors.primary,
                        borderRadius: BorderRadius.circular(25),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.play_arrow,
                              size: 22,
                              color: focused
                                  ? AppColors.onFocus
                                  : AppColors.onPrimary),
                          const SizedBox(width: 6),
                          Text(t['shaarat_enter']!,
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: focused
                                      ? AppColors.onFocus
                                      : AppColors.onPrimary)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Focusable(
                  onPressed: onLike,
                  builder: (context, focused) => Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: liked
                          ? _kHeart
                          : (focused
                              ? Colors.white
                              : Colors.white.withValues(alpha: 0.14)),
                    ),
                    child: Icon(
                      liked ? Icons.favorite : Icons.favorite_border,
                      size: 24,
                      color: liked
                          ? Colors.white
                          : (focused ? _kHeart : AppColors.inkSoft),
                    ),
                  ),
                ),
              ]),
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
