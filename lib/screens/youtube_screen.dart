import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../services/youtube_service.dart';
import '../services/youtube_stream_resolver.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../widgets/focusable.dart';

/// In-app trailer / theme-song player. Searches YouTube for [query], extracts a
/// direct muxed stream URL (no iframe), and plays it in the app's own
/// `video_player` surface. Separate from the main streaming player. Disposes
/// cleanly on close (no audio continues).
class YoutubeScreen extends ConsumerStatefulWidget {
  final String query;
  final String title;
  const YoutubeScreen({super.key, required this.query, required this.title});
  @override
  ConsumerState<YoutubeScreen> createState() => _YoutubeScreenState();
}

class _YoutubeScreenState extends ConsumerState<YoutubeScreen>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _loading = true;
  bool _failed = false;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;
  bool _ended = false;

  bool _controlsShown = true;
  Timer? _hideTimer;

  final FocusNode _playFocus = FocusNode(debugLabel: 'ytPlayPause');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _start();
    _flashControls();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _playFocus.requestFocus();
    });
  }

  Future<void> _start() async {
    try {
      final userKey = ref.read(storageProvider).getYoutubeKey();
      final id = await YoutubeService.firstVideoId(widget.query, apiKey: userKey);
      if (!mounted) return;
      if (id == null) return _fail();
      final url = await YoutubeStreamResolver.resolve(id);
      if (!mounted) return;
      if (url == null) return _fail();

      final c = VideoPlayerController.networkUrl(Uri.parse(url));
      _controller = c;
      await c.initialize();
      if (!mounted) {
        await c.dispose();
        return;
      }
      c.addListener(_onTick);
      await c.play();
      setState(() => _loading = false);
    } catch (e) {
      debugPrint('YouTube trailer failed: $e');
      _fail();
    }
  }

  void _fail() {
    if (!mounted) return;
    setState(() {
      _loading = false;
      _failed = true;
    });
  }

  void _onTick() {
    final c = _controller;
    if (c == null || !mounted) return;
    final v = c.value;
    if (v.hasError) {
      _fail();
      return;
    }
    setState(() {
      _position = v.position;
      _duration = v.duration;
      _playing = v.isPlaying;
    });
    if (v.duration.inSeconds > 0 &&
        !_ended &&
        v.position >= v.duration - const Duration(milliseconds: 600)) {
      _ended = true;
      Navigator.maybePop(context);
    }
  }

  void _flashControls() {
    if (!_controlsShown) setState(() => _controlsShown = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 4200), () {
      if (mounted && _playing) setState(() => _controlsShown = false);
    });
  }

  void _togglePlay() {
    final c = _controller;
    if (c != null && c.value.isInitialized) {
      c.value.isPlaying ? c.pause() : c.play();
    }
    _flashControls();
  }

  void _seekBy(Duration delta) {
    final c = _controller;
    if (c == null) return;
    var target = _position + delta;
    if (target < Duration.zero) target = Duration.zero;
    if (_duration > Duration.zero && target > _duration) target = _duration;
    c.seekTo(target);
    setState(() => _position = target);
    _flashControls();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _controller?.pause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _hideTimer?.cancel();
    final c = _controller;
    _controller = null;
    c?.removeListener(_onTick);
    c?.pause();
    c?.dispose();
    _playFocus.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
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
    final c = _controller;
    final ready = c != null && c.value.isInitialized;
    return Focus(
      autofocus: true,
      skipTraversal: true,
      onKeyEvent: _keys,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(children: [
          if (ready)
            Positioned.fill(
              child: ColoredBox(
                color: Colors.black,
                child: Center(
                  child: AspectRatio(
                    aspectRatio: c.value.aspectRatio,
                    child: VideoPlayer(c),
                  ),
                ),
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
                Text(t['yt_none']!,
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
          if (ready && !_failed)
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
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: focused
                          ? Colors.white
                          : Colors.black.withValues(alpha: 0.5)),
                  child: Icon(Icons.arrow_back,
                      color: focused ? AppColors.onFocus : Colors.white,
                      size: 30),
                ),
              ),
            ),
          ),
        ]),
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
        padding: const EdgeInsets.fromLTRB(56, 0, 56, 56),
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
            const SizedBox(height: 26),
            Focusable(
              focusNode: _playFocus,
              onPressed: _togglePlay,
              builder: (context, focused) => AnimatedScale(
                scale: focused ? 1.06 : 1,
                duration: const Duration(milliseconds: 150),
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: focused
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.12),
                  ),
                  child: Icon(_playing ? Icons.pause : Icons.play_arrow,
                      size: 38,
                      color: focused ? AppColors.onFocus : AppColors.ink),
                ),
              ),
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
              fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.inkSoft)),
      const SizedBox(width: 22),
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
              height: 28,
              child: Stack(alignment: Alignment.centerLeft, children: [
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(6)),
                ),
                FractionallySizedBox(
                  widthFactor: frac,
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: AppColors.primaryGradient),
                        borderRadius: BorderRadius.circular(6)),
                  ),
                ),
                Align(
                  alignment: Alignment(frac * 2 - 1, 0),
                  child: Container(
                    width: focused ? 30 : 26,
                    height: focused ? 30 : 26,
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
      const SizedBox(width: 22),
      Text(_fmt(duration),
          style: const TextStyle(
              fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.inkSoft)),
    ]);
  }
}
