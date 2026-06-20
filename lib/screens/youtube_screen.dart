import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import '../services/player_service.dart';
import '../services/youtube_service.dart';
import '../services/youtube_stream_resolver.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../widgets/focusable.dart';

/// In-app trailer / theme-song player. Searches YouTube for [query], extracts a
/// direct muxed stream URL (no iframe), and plays it on the app's ONE shared
/// player (see [PlayerService]). Reuses the same decoder as the main player so
/// opening many trailers can't exhaust the Android-TV decoder pool.
class YoutubeScreen extends ConsumerStatefulWidget {
  final String query;
  final String title;
  const YoutubeScreen({super.key, required this.query, required this.title});
  @override
  ConsumerState<YoutubeScreen> createState() => _YoutubeScreenState();
}

class _YoutubeScreenState extends ConsumerState<YoutubeScreen>
    with WidgetsBindingObserver {
  Player get _player => PlayerService.instance.player;
  final List<StreamSubscription> _subs = [];

  bool _loading = true;
  bool _failed = false;
  String _failKey = 'yt_none'; // which message to show on the failure screen

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _ended = false;

  YoutubePlayback? _playback;

  bool _controlsShown = true;
  Timer? _hideTimer;

  final FocusNode _playFocus = FocusNode(debugLabel: 'ytPlayPause');

  // Phones watch in landscape; captured here so dispose can restore portrait.
  late final bool _isTv = ref.read(isTvProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    if (!_isTv) {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
    PlayerService.instance.ensureCreated();
    _subscribe();
    _start();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _playFocus.requestFocus();
    });
  }

  /// Wire this screen to the shared player's streams; cancelled on dispose.
  void _subscribe() {
    final p = _player;
    _subs.addAll([
      p.stream.position.listen((pos) {
        if (mounted) setState(() => _position = pos);
      }),
      p.stream.duration.listen((d) {
        if (mounted) setState(() => _duration = d);
      }),
      p.stream.playing.listen((pl) {
        if (mounted) setState(() => _playing = pl);
      }),
      p.stream.completed.listen((done) {
        if (done && mounted && !_ended && !_loading) {
          _ended = true;
          Navigator.maybePop(context);
        }
      }),
      p.stream.error.listen((_) {
        if (mounted && !_loading) _fail();
      }),
    ]);
  }

  /// Search → resolve → play, retried up to [_kMaxAttempts] times before giving
  /// up. A transient extraction/network miss commonly succeeds on a second try
  /// (the same reason a manual retry works), so we do it automatically. Quota
  /// errors won't recover on retry, so they fail fast.
  static const _kMaxAttempts = 3;

  Future<void> _start() async {
    var failKey = 'yt_none';
    for (var attempt = 1; attempt <= _kMaxAttempts; attempt++) {
      try {
        if (await _attemptOpen()) return; // playing
      } on YoutubeException catch (e) {
        if (!mounted) return;
        if (e.kind == YoutubeErrorKind.quota) return _fail('yt_quota');
        failKey = e.kind == YoutubeErrorKind.network ? 'yt_network' : 'yt_error';
        debugPrint('YouTube attempt $attempt failed: $e');
      } catch (e) {
        if (!mounted) return;
        debugPrint('YouTube attempt $attempt failed: $e');
      }
      if (!mounted) return;
      if (attempt < _kMaxAttempts) {
        await Future.delayed(Duration(milliseconds: 600 * attempt));
        if (!mounted) return;
      }
    }
    _fail(failKey);
  }

  /// One open attempt. Returns true once playback has started; false on a
  /// retryable miss (no search hits / nothing playable). Throws YoutubeException
  /// and other errors up to [_start]'s retry loop.
  Future<bool> _attemptOpen() async {
    final userKey = ref.read(storageProvider).getYoutubeKey();
    final ids =
        await YoutubeService.searchVideoIds(widget.query, apiKey: userKey);
    if (!mounted) return false;
    if (ids.isEmpty) return false;

    // Try each candidate in relevance order until one resolves to playable
    // streams — the top hit is often age/geo-restricted or has no usable
    // streams, and one failure shouldn't sink the whole open.
    YoutubePlayback? playback;
    for (final id in ids) {
      try {
        playback = await YoutubeStreamResolver.resolvePlayback(id);
      } catch (e) {
        debugPrint('YouTube resolve failed for $id: $e');
        playback = null;
      }
      if (!mounted) return false;
      if (playback != null) break;
    }
    if (playback == null) return false;
    _playback = playback;

    // Play Auto (best <=720 + audio); _playQuality falls back to muxed 360p.
    // Throws on failure → retried by [_start].
    await _playQuality(null);
    if (!mounted) return false;
    setState(() => _loading = false);
    // Now that playback is actually ready (and _playing has flipped true),
    // start the auto-hide countdown. Flashing during loading was a no-op:
    // the timer's `_playing` guard skipped hiding, so controls stuck on.
    _flashControls();
    return true;
  }

  /// The video option for [height] (null = Auto = best), or null if none exist.
  YtVideoOption? _videoForHeight(YoutubePlayback pb, int? height) {
    if (pb.videos.isEmpty) return null;
    if (height == null) return pb.videos.first;
    for (final v in pb.videos) {
      if (v.height == height) return v;
    }
    return pb.videos.first;
  }

  /// Open the requested quality (null = Auto). Tries the adaptive video+audio
  /// path; on failure falls back to the muxed 360p stream. Throws when nothing
  /// can be played.
  Future<void> _playQuality(int? height) async {
    final pb = _playback;
    if (pb == null) return;
    final video = _videoForHeight(pb, height);
    if (video != null) {
      try {
        await _openAndWait(
          () => PlayerService.instance.openWithAudio(
            video.url,
            audioUrl: video.muxed ? null : pb.audioUrl,
          ),
          const Duration(seconds: 30),
        );
        return;
      } catch (e) {
        debugPrint('YouTube adaptive open failed, trying muxed: $e');
      }
    }
    final muxed = pb.muxedFallbackUrl;
    if (muxed == null) throw Exception('no playable youtube stream');
    await _openAndWait(
        () => PlayerService.instance.open(muxed), const Duration(seconds: 30));
  }

  /// Run [open], completing once playback starts (first known duration) or
  /// failing fast on a playback error / [budget] timeout. Subscribes before
  /// opening so the first event can't slip past.
  Future<void> _openAndWait(Future<void> Function() open, Duration budget) {
    final p = _player;
    final c = Completer<void>();
    var settled = false;
    late final StreamSubscription dSub;
    late final StreamSubscription eSub;
    void finish([Object? err]) {
      if (settled) return;
      settled = true;
      dSub.cancel();
      eSub.cancel();
      if (!c.isCompleted) {
        err == null ? c.complete() : c.completeError(err);
      }
    }

    dSub = p.stream.duration.listen((d) {
      if (d > Duration.zero) finish();
    });
    eSub = p.stream.error.listen((e) => finish(e));
    open().catchError((Object e) => finish(e));
    return c.future.timeout(budget, onTimeout: () {
      finish();
      throw TimeoutException('open timed out');
    });
  }

  void _fail([String msgKey = 'yt_none']) {
    // Stop playback (keeps the shared player + its decoder alive) and show the
    // failure screen.
    PlayerService.instance.stop();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _failed = true;
      _failKey = msgKey;
    });
  }

  void _flashControls() {
    if (!_controlsShown) setState(() => _controlsShown = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 4200), () {
      if (mounted && _playing) {
        setState(() => _controlsShown = false);
      }
    });
  }

  void _togglePlay() {
    _player.playOrPause();
    _flashControls();
  }

  void _seekBy(Duration delta) {
    var target = _position + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (_duration > Duration.zero && target > _duration) target = _duration;
    _player.seek(target);
    setState(() => _position = target);
    _flashControls();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _player.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    for (final s in _subs) {
      s.cancel();
    }
    // Stop playback but keep the shared player alive (decoder reused, never
    // re-acquired) — same lifecycle rule as the main player.
    PlayerService.instance.stop();
    _playFocus.dispose();
    // Safety net; the back path restores orientation in onPopInvokedWithResult.
    _restorePhoneOrientation();
    super.dispose();
  }

  /// Restore edge-to-edge UI and (on phones) portrait after the landscape
  /// trailer. Issued on back press (reliable) and again in dispose (fallback) —
  /// see the main player for why dispose-only is flaky on Android.
  void _restorePhoneOrientation() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    if (!_isTv) {
      SystemChrome.setPreferredOrientations(
          const [DeviceOrientation.portraitUp]);
    }
  }

  /// Any key reveals the controls (and resets the auto-hide timer) when hidden.
  KeyEventResult _keys(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (!_controlsShown) {
      _flashControls();
      if (!_playFocus.hasFocus) _playFocus.requestFocus();
      return KeyEventResult.handled;
    }
    _flashControls();
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final ready = !_loading && !_failed;
    return PopScope(
      // Stop audio the instant back is pressed — before the fade-out + dispose
      // — and restore portrait while the activity is still resumed.
      onPopInvokedWithResult: (didPop, _) {
        _player.pause();
        if (didPop) _restorePhoneOrientation();
      },
      child: Focus(
      autofocus: true,
      skipTraversal: true,
      onKeyEvent: _keys,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          // The single shared player surface (letterboxed by media_kit itself).
          Positioned.fill(
            child: Video(
              controller: PlayerService.instance.controller,
              controls: NoVideoControls,
              fit: BoxFit.contain,
              fill: Colors.black,
            ),
          ),
          if (_loading)
            Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const CircularProgressIndicator(color: AppColors.primary),
                const SizedBox(height: 20),
                Text(t['yt_searching']!,
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink)),
              ]),
            ),
          if (_failed)
            Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.error_outline,
                    size: 56, color: AppColors.inkMute),
                const SizedBox(height: 16),
                Text(t[_failKey] ?? t['yt_none']!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: AppColors.inkSoft)),
                const SizedBox(height: 24),
                Focusable(
                  autofocus: true,
                  onPressed: () => Navigator.maybePop(context),
                  builder: (context, focused) => Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 30, vertical: 14),
                    decoration: BoxDecoration(
                        color: focused ? Colors.white : AppColors.bg2,
                        borderRadius: BorderRadius.circular(999)),
                    child: Text(t['back']!,
                        style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: focused ? AppColors.onFocus : AppColors.ink)),
                  ),
                ),
              ]),
            ),
          // transport controls (only once playback is ready)
          if (ready)
            Positioned.fill(
              child: AnimatedOpacity(
                opacity: _controlsShown ? 1 : 0,
                duration: const Duration(milliseconds: 350),
                child: IgnorePointer(
                  ignoring: !_controlsShown,
                  child: _transport(t),
                ),
              ),
            ),
          // back button
          Positioned(
            top: 36,
            left: 36,
            child: Focusable(
              autofocus: false,
              onPressed: () => Navigator.maybePop(context),
              builder: (context, focused) => AnimatedScale(
                scale: focused ? 1.06 : 1,
                duration: const Duration(milliseconds: 150),
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: focused
                          ? Colors.white
                          : Colors.black.withValues(alpha: 0.5)),
                  child: Icon(Icons.arrow_back,
                      color: focused ? AppColors.onFocus : Colors.white,
                      size: 24),
                ),
              ),
            ),
          ),
        ]),
      ),
      ),
    );
  }

  Widget _transport(Map<String, String> t) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xD9000000), Colors.transparent],
          stops: [0, 0.34],
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(44, 0, 44, 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Directionality(
              textDirection: TextDirection.ltr,
              child: _YtScrubBar(
                position: _position,
                duration: _duration,
                onSeekBy: _seekBy,
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Focusable(
                  focusNode: _playFocus,
                  onPressed: _togglePlay,
                  builder: (context, focused) => AnimatedScale(
                    scale: focused ? 1.06 : 1,
                    duration: const Duration(milliseconds: 150),
                    child: Container(
                      width: 54,
                      height: 54,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: focused
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.12),
                      ),
                      child: Icon(_playing ? Icons.pause : Icons.play_arrow,
                          size: 28,
                          color: focused ? AppColors.onFocus : AppColors.ink),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Focusable scrub bar; D-pad LEFT/RIGHT seek ±10s. Mirrors the main player's
/// scrub bar so the trailer player feels consistent.
class _YtScrubBar extends StatelessWidget {
  final Duration position;
  final Duration duration;
  final void Function(Duration) onSeekBy;
  const _YtScrubBar({
    required this.position,
    required this.duration,
    required this.onSeekBy,
  });

  String _fmt(Duration d) {
    final s = d.inSeconds;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = (s % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$sec' : '$m:$sec';
  }

  @override
  Widget build(BuildContext context) {
    final frac = duration.inMilliseconds > 0
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    return Row(children: [
      Text(_fmt(position),
          style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.inkSoft)),
      const SizedBox(width: 16),
      Expanded(
        child: Focus(
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
              return KeyEventResult.ignored;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
              onSeekBy(const Duration(seconds: -10));
              return KeyEventResult.handled;
            }
            if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
              onSeekBy(const Duration(seconds: 10));
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: Builder(builder: (context) {
            final focused = Focus.of(context).hasFocus;
            return SizedBox(
              height: 20,
              child: Stack(alignment: Alignment.centerLeft, children: [
                Container(
                  height: 5,
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(6)),
                ),
                FractionallySizedBox(
                  widthFactor: frac,
                  child: Container(
                    height: 5,
                    decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: AppColors.primaryGradient),
                        borderRadius: BorderRadius.circular(6)),
                  ),
                ),
                Align(
                  alignment: Alignment(frac * 2 - 1, 0),
                  child: Container(
                    width: focused ? 20 : 16,
                    height: focused ? 20 : 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      boxShadow: [
                        if (focused)
                          BoxShadow(
                              color: Colors.white.withValues(alpha: 0.3),
                              blurRadius: 0,
                              spreadRadius: 8),
                        BoxShadow(
                            color: Colors.black.withValues(alpha: 0.5),
                            blurRadius: 14,
                            offset: const Offset(0, 4)),
                      ],
                    ),
                  ),
                ),
              ]),
            );
          }),
        ),
      ),
      const SizedBox(width: 16),
      Text(_fmt(duration),
          style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.inkSoft)),
    ]);
  }
}
