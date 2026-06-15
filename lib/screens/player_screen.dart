import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../models/catalog_source.dart';
import '../models/content_item.dart';
import '../services/playback_resolver.dart';
import '../services/storage_service.dart';
import '../services/video_engine.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../widgets/focusable.dart';
import '../widgets/tv_scaler.dart';

class PlayerArgs {
  final String itemId;

  /// Arabic Toons: the episode/movie PAGE url to fetch fresh tokens from.
  /// Stardima: the `play_url` to run through the resolver pipeline.
  final String pageUrl;
  final String title; // Arabic title (shown in the player header)
  final String episodeLabel;
  final int episodeNumber;
  final List<Episode>? episodes; // for prev/next (shows)
  final CatalogSource source;

  const PlayerArgs({
    required this.itemId,
    required this.pageUrl,
    required this.title,
    required this.episodeLabel,
    required this.episodeNumber,
    this.episodes,
    this.source = CatalogSource.arabicToons,
  });
}

const _controlsTimeout = Duration(milliseconds: 4200);
const _seekStep = Duration(seconds: 10);
const _saveInterval = Duration(seconds: 5);

class PlayerScreen extends ConsumerStatefulWidget {
  final PlayerArgs args;
  const PlayerScreen({super.key, required this.args});
  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen>
    with WidgetsBindingObserver {
  VideoPlayerController? _controller;

  // current episode (mutable for prev/next)
  late String _pageUrl;
  late String _epLabel;
  late int _epNumber;

  int _server = 1;
  List<int> _available = const [1];
  Map<int, PlayableServer> _serverMap = const {};
  int _retry = 0;
  int _reqId = 0;

  // Stardima resolution is expensive (multi-request pipeline), so cache the
  // resolved server list per play_url to make server-switching instant. Arabic
  // Toons must always re-fetch (tokens are IP/time-bound and expire).
  List<PlayableServer>? _resolvedCache;
  String? _resolvedFor;

  bool _loading = true;
  bool _error = false;
  bool _restored = false;
  bool _ended = false;

  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _playing = false;

  bool _controlsShown = true;
  Timer? _hideTimer;
  Timer? _saveTimer;
  bool _serverPanelOpen = false;

  // Focus: a scope for the whole player + a node for the play/pause button so
  // the D-pad always lands on a usable control when the controls appear.
  final FocusScopeNode _playerScope = FocusScopeNode(debugLabel: 'player');
  final FocusNode _playFocus = FocusNode(debugLabel: 'playPause');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _pageUrl = widget.args.pageUrl;
    _epLabel = widget.args.episodeLabel;
    _epNumber = widget.args.episodeNumber;
    // Stardima: always open the FIRST resolved link; Arabic Toons honors the
    // user's saved preferred server.
    _server = widget.args.source == CatalogSource.stardima
        ? 1
        : ref.read(storageProvider).getPreferredServer();

    _load(_server);
    _flashControls();
    _saveTimer = Timer.periodic(_saveInterval, (_) => _saveProgress());
    // land focus on play/pause once the controls are mounted
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _playFocus.requestFocus();
    });
  }

  void _onTick() {
    final c = _controller;
    if (c == null || !mounted) return;
    final v = c.value;
    if (v.hasError) {
      _onError();
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
      _onEnd();
    }
  }

  /// Resolve the playable server list for the current page/play url. Stardima
  /// results are cached per url; Arabic Toons always fetches fresh tokens.
  Future<List<PlayableServer>> _resolveServers() async {
    if (widget.args.source == CatalogSource.stardima) {
      if (_resolvedFor == _pageUrl && _resolvedCache != null) {
        return _resolvedCache!;
      }
      final servers = await resolvePlayback(widget.args.source, _pageUrl);
      _resolvedFor = _pageUrl;
      _resolvedCache = servers;
      return servers;
    }
    return resolvePlayback(widget.args.source, _pageUrl);
  }

  Future<void> _load(int server) async {
    final id = ++_reqId;
    setState(() {
      _loading = true;
      _error = false;
      _restored = false;
      _ended = false;
      _server = server;
    });

    // Release the outgoing controller BEFORE building the new one, and do it
    // through the app-wide VideoEngine so the release is serialized with any
    // controller a *previous screen* is still tearing down. Android devices
    // (especially TV boxes) allow only a handful of concurrent hardware video
    // decoders and release them asynchronously; creating the next ExoPlayer
    // while an old decoder is still being freed is what makes playback fail
    // intermittently. Awaiting here guarantees the pool is clear first.
    final old = _controller;
    _controller = null;
    old?.removeListener(_onTick);
    old?.setVolume(0);
    await VideoEngine.instance.release(old);
    if (id != _reqId || !mounted) return;

    VideoPlayerController? c;
    try {
      final servers = await _resolveServers();
      if (id != _reqId || !mounted) return;
      if (servers.isEmpty) throw Exception('no servers');
      _serverMap = {for (final s in servers) s.number: s};
      _available = servers.map((s) => s.number).toList();
      final pick = _serverMap[server] ?? servers.first;
      _server = pick.number;

      c = VideoPlayerController.networkUrl(
        Uri.parse(pick.url),
        httpHeaders: pick.headers,
      );
      _controller = c;
      // Cap loads so a dead/hanging host can't wedge the player forever.
      // Stardima fails fast to the next link; Arabic Toons gets a longer budget
      // for a fresh token fetch.
      final budget = widget.args.source == CatalogSource.stardima
          ? const Duration(seconds: 18)
          : const Duration(seconds: 30);
      await c.initialize().timeout(budget);
      if (id != _reqId || !mounted) {
        // Superseded or the screen is gone — release the controller we built.
        if (identical(_controller, c)) _controller = null;
        await VideoEngine.instance.release(c);
        return;
      }
      c.addListener(_onTick);
      _maybeRestore();
      await c.play();
      setState(() => _loading = false);
      _retry = 0;
    } catch (_) {
      // The init failed/timed out: release this controller (freeing its native
      // decoder) and clear the slot BEFORE deciding what to try next, so a flaky
      // host can never leak a decoder and the next attempt starts clean.
      if (identical(_controller, c)) _controller = null;
      await VideoEngine.instance.release(c);
      if (id != _reqId || !mounted) return;
      _onError();
    }
  }

  void _onError() {
    if (!mounted) return;
    // Arabic Toons benefits from retrying the same server (a fresh token fetch
    // can succeed). Stardima hosts that fail won't recover on retry, so move to
    // the next resolved link immediately — open them one by one.
    final maxRetry = widget.args.source == CatalogSource.stardima ? 0 : 2;
    if (_retry < maxRetry) {
      _retry++;
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) _load(_server);
      });
      return;
    }
    // Try the next link in order, one by one.
    final idx = _available.indexOf(_server);
    if (idx >= 0 && idx < _available.length - 1) {
      _retry = 0;
      _load(_available[idx + 1]);
      return;
    }
    // Every link failed. Drop the cached resolution so the manual Retry re-runs
    // the full resolver pipeline (the links may simply have gone stale).
    if (widget.args.source == CatalogSource.stardima) {
      _resolvedCache = null;
      _resolvedFor = null;
    }
    setState(() {
      _error = true;
      _loading = false;
    });
  }

  void _maybeRestore() {
    final c = _controller;
    if (_restored || c == null) return;
    final dur = c.value.duration.inSeconds;
    if (dur <= 0) return;
    _restored = true;
    final saved = ref.read(storageProvider).getProgress(_pageUrl);
    if (saved != null &&
        saved.currentTime > 10 &&
        saved.currentTime < dur - 10) {
      c.seekTo(Duration(seconds: saved.currentTime.round()));
    }
  }

  void _saveProgress() {
    if (_duration.inSeconds <= 0) return;
    ref.read(storageProvider).saveProgress(ProgressEntry(
          itemId: widget.args.itemId,
          episodeUrl: _pageUrl,
          episodeNumber: _epNumber,
          currentTime: _position.inSeconds.toDouble(),
          duration: _duration.inSeconds.toDouble(),
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ));
  }

  // ---- episode navigation ----
  int get _epIndex {
    final eps = widget.args.episodes;
    if (eps == null) return -1;
    return eps.indexWhere((e) => e.episodeUrl == _pageUrl);
  }

  bool get _hasPrev => _epIndex > 0;
  bool get _hasNext {
    final eps = widget.args.episodes;
    return eps != null && _epIndex >= 0 && _epIndex < eps.length - 1;
  }

  void _goEpisode(Episode ep) {
    _saveProgress();
    setState(() {
      _pageUrl = ep.episodeUrl;
      _epLabel = '${ref.read(stringsProvider)['epShort']}${ep.episodeNumber}';
      _epNumber = ep.episodeNumber;
      _position = Duration.zero;
      _duration = Duration.zero;
      _retry = 0;
    });
    _load(_server);
    _flashControls();
  }

  void _prev() {
    if (_hasPrev) _goEpisode(widget.args.episodes![_epIndex - 1]);
  }

  void _next() {
    if (_hasNext) _goEpisode(widget.args.episodes![_epIndex + 1]);
  }

  void _onEnd() {
    _saveProgressComplete();
    if (_hasNext) {
      _next();
    } else {
      Navigator.maybePop(context);
    }
  }

  void _saveProgressComplete() {
    if (_duration.inSeconds <= 0) return;
    ref.read(storageProvider).saveProgress(ProgressEntry(
          itemId: widget.args.itemId,
          episodeUrl: _pageUrl,
          episodeNumber: _epNumber,
          currentTime: _duration.inSeconds.toDouble(),
          duration: _duration.inSeconds.toDouble(),
          updatedAt: DateTime.now().millisecondsSinceEpoch,
        ));
  }

  // ---- controls ----
  void _flashControls() {
    if (!_controlsShown) setState(() => _controlsShown = true);
    _hideTimer?.cancel();
    _hideTimer = Timer(_controlsTimeout, () {
      if (mounted && _playing && !_serverPanelOpen) {
        setState(() => _controlsShown = false);
      }
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

  void _switchServer(int n) {
    setState(() {
      _serverPanelOpen = false;
      _retry = 0;
    });
    _load(n);
    _flashControls();
  }

  /// Tear down the native video controller (exactly one player at a time).
  /// Pause first so ExoPlayer stops emitting audio immediately, even if the
  /// async dispose lags behind the route teardown.
  void _disposeController() {
    final c = _controller;
    _controller = null;
    if (c == null) return;
    c.removeListener(_onTick);
    // Mute first: on some Android builds the platform-side dispose lags a frame
    // behind route teardown, so volume 0 guarantees no audio tail even if the
    // ExoPlayer release hasn't landed yet. Then pause + release.
    c.setVolume(0);
    c.pause();
    // Hand the release to the VideoEngine (can't await in a sync dispose). The
    // next screen's player awaits this same queue before it acquires a decoder,
    // so the hand-off never races the asynchronous native release.
    VideoEngine.instance.release(c);
  }

  /// Netflix-style: stop playback the moment the player is no longer on screen.
  /// `video_player` (ExoPlayer) keeps playing audio when the app is
  /// backgrounded, so pause it on any non-foreground state.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _saveProgress();
      _controller?.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveProgress();
    _hideTimer?.cancel();
    _saveTimer?.cancel();
    _disposeController(); // fully stop + dispose the video controller (frees audio)
    _playFocus.dispose();
    _playerScope.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// Catches every remote key so the user is never locked out: when the
  /// controls are hidden, the first key just reveals them (and keeps focus on a
  /// control); otherwise it resets the auto-hide timer and lets navigation run.
  KeyEventResult _playerKeys(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (!_controlsShown) {
      setState(() => _controlsShown = true);
      _flashControls();
      if (!_playFocus.hasFocus &&
          (FocusManager.instance.primaryFocus?.context == null)) {
        _playFocus.requestFocus();
      }
      return KeyEventResult.handled; // swallow the reveal press
    }
    _flashControls();
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    return PopScope(
      // Pop fires this BEFORE the route's fade-out + dispose, so stop audio here
      // for an instant, reliable cut the moment the user presses back — dispose
      // then releases the controller once the transition completes.
      onPopInvokedWithResult: (didPop, _) {
        _controller?.pause();
        _saveProgress();
      },
      child: FocusScope(
        node: _playerScope,
        child: Focus(
          autofocus: true,
          skipTraversal: true,
          onKeyEvent: _playerKeys,
          child: Scaffold(
            backgroundColor: Colors.black,
            body: Stack(children: [
              // The single player surface at NATIVE size (no canvas transform —
              // platform views mis-composite under a FittedBox).
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.black,
                  child: (_controller != null &&
                          _controller!.value.isInitialized)
                      ? Center(
                          child: AspectRatio(
                            aspectRatio: _controller!.value.aspectRatio,
                            child: VideoPlayer(_controller!),
                          ),
                        )
                      : const SizedBox.expand(),
                ),
              ),
              // Control overlays on the scaled 1920×1080 design canvas. The
              // backdrop MUST be transparent — an opaque one would paint over
              // (and hide) the video surface stacked beneath it.
              Positioned.fill(
                child: TvScaler(
                  background: Colors.transparent,
                  child: Stack(children: [
                    if (_loading && !_error)
                      Positioned.fill(
                        child: Center(
                          child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(
                                    color: AppColors.primary),
                                const SizedBox(height: 20),
                                Text(
                                    widget.args.source == CatalogSource.stardima
                                        ? t['resolving']!
                                        : t['preparing']!,
                                    style: const TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.ink)),
                              ]),
                        ),
                      ),
                    if (_error) Positioned.fill(child: _errorOverlay(t)),
                    if (!_error)
                      Positioned.fill(
                        child: AnimatedOpacity(
                          opacity: _controlsShown ? 1 : 0,
                          duration: const Duration(milliseconds: 350),
                          child: IgnorePointer(
                            ignoring: !_controlsShown,
                            child: _controls(t),
                          ),
                        ),
                      ),
                    if (_serverPanelOpen)
                      Positioned.fill(child: _serverPanel(t)),
                  ]),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _errorOverlay(Map<String, String> t) => Container(
        color: Colors.black.withValues(alpha: 0.85),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(48),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(t['failedAllServers']!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 24, color: AppColors.inkSoft, height: 1.4)),
          const SizedBox(height: 24),
          _CtrlButton(
            icon: Icons.refresh,
            label: t['retry'],
            autofocus: true,
            big: true,
            onPressed: () {
              _retry = 0;
              _load(1);
            },
          ),
        ]),
      );

  Widget _controls(Map<String, String> t) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Color(0xD9000000), Colors.transparent],
          stops: [0, 0.34],
        ),
      ),
      child: Stack(children: [
        // top
        Positioned(
          top: 48,
          left: Spacing.pad,
          right: Spacing.pad,
          child: Row(children: [
            _CtrlButton(
                icon: Icons.arrow_back,
                onPressed: () => Navigator.maybePop(context)),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.args.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontFamily: Fonts.display,
                          fontFamilyFallback: Fonts.fallback,
                          fontWeight: FontWeight.w500,
                          fontSize: 38,
                          color: AppColors.ink)),
                  Text(_epLabel,
                      style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color: AppColors.inkSoft)),
                ],
              ),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999)),
              child: Text.rich(TextSpan(children: [
                TextSpan(
                    text: '${t['nowPlaying']} ',
                    style: const TextStyle(color: AppColors.inkSoft)),
                TextSpan(
                    text: _serverMap[_server]?.label ?? '${t['server']} $_server',
                    style: const TextStyle(color: AppColors.ink)),
              ]),
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
        // bottom (native transport)
        Positioned(
          left: Spacing.pad,
          right: Spacing.pad,
          bottom: 56,
          child: Column(children: [
            // Force LTR so the seek bar always fills/drags left→right (start on
            // the left, end on the right) even when the app is in Arabic/RTL.
            Directionality(
              textDirection: TextDirection.ltr,
              child: _ScrubBar(
                position: _position,
                duration: _duration,
                onSeekBy: _seekBy,
              ),
            ),
            const SizedBox(height: 26),
            Directionality(
              textDirection: TextDirection.ltr,
              child:
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (widget.args.episodes != null)
                _CtrlButton(
                    icon: Icons.skip_previous,
                    onPressed: _hasPrev ? _prev : null),
              _CtrlButton(
                  icon: Icons.replay_10,
                  onPressed: () => _seekBy(-_seekStep)),
              _CtrlButton(
                icon: _playing ? Icons.pause : Icons.play_arrow,
                big: true,
                focusNode: _playFocus,
                onPressed: _togglePlay,
              ),
              _CtrlButton(
                  icon: Icons.forward_10,
                  onPressed: () => _seekBy(_seekStep)),
              if (widget.args.episodes != null)
                _CtrlButton(
                    icon: Icons.skip_next, onPressed: _hasNext ? _next : null),
              const SizedBox(width: 26),
              _CtrlButton(
                icon: Icons.dns_outlined,
                label: t['server'],
                onPressed: () {
                  setState(() => _serverPanelOpen = true);
                },
              ),
            ]),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _serverPanel(Map<String, String> t) {
    final servers = _available.isEmpty ? [1] : _available;
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Container(
        width: 560,
        height: double.infinity,
        color: AppColors.bg1,
        padding: const EdgeInsets.fromLTRB(44, 80, 44, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(17),
                    gradient:
                        const LinearGradient(colors: AppColors.primaryGradient)),
                child: const Icon(Icons.dns_outlined,
                    size: 32, color: AppColors.onPrimary),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t['servers']!,
                        style: const TextStyle(
                            fontFamily: Fonts.display,
                            fontFamilyFallback: Fonts.fallback,
                            fontWeight: FontWeight.w600,
                            fontSize: 38,
                            color: AppColors.ink)),
                    Text(t['chooseServer']!,
                        style: const TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: AppColors.inkMute)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 26),
            Expanded(
              child: ListView(
                children: [
                  for (int i = 0; i < servers.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: _ServerOption(
                        label: _serverMap[servers[i]]?.label ??
                            '${t['server']} ${servers[i]}',
                        selected: servers[i] == _server,
                        autofocus: servers[i] == _server,
                        onPressed: () => _switchServer(servers[i]),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _CtrlButton(
              icon: Icons.close,
              label: t['back'],
              onPressed: () => setState(() => _serverPanelOpen = false),
            ),
          ],
        ),
      ),
    );
  }

}

/// Circular / text control button (design `.ctrl`).
class _CtrlButton extends StatelessWidget {
  final IconData icon;
  final String? label;
  final VoidCallback? onPressed;
  final bool big;
  final bool autofocus;
  final FocusNode? focusNode;
  const _CtrlButton({
    required this.icon,
    this.label,
    this.onPressed,
    this.big = false,
    this.autofocus = false,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Opacity(
        opacity: disabled ? 0.35 : 1,
        child: Focusable(
          autofocus: autofocus,
          focusNode: focusNode,
          onPressed: onPressed,
          builder: (context, focused) {
            final size = big ? 80.0 : 64.0;
            final fg = focused ? AppColors.onFocus : AppColors.ink;
            final bg = focused
                ? Colors.white
                : Colors.white.withValues(alpha: 0.12);
            return AnimatedScale(
              scale: focused ? 1.06 : 1,
              duration: const Duration(milliseconds: 150),
              child: label == null
                  ? Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: bg),
                      child: Icon(icon, size: big ? 38 : 30, color: fg),
                    )
                  : Container(
                      height: 64,
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999), color: bg),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(icon, size: 28, color: fg),
                        const SizedBox(width: 10),
                        Text(label!,
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                color: fg)),
                      ]),
                    ),
            );
          },
        ),
      ),
    );
  }
}

/// Focusable scrub bar; D-pad LEFT/RIGHT seek ±10s, UP/DOWN move focus away.
class _ScrubBar extends StatelessWidget {
  final Duration position;
  final Duration duration;
  final void Function(Duration) onSeekBy;
  const _ScrubBar({
    required this.position,
    required this.duration,
    required this.onSeekBy,
  });

  String _fmt(Duration d) {
    final s = d.inSeconds;
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    final sec = (s % 60).toString().padLeft(2, '0');
    return h > 0
        ? '$h:${m.toString().padLeft(2, '0')}:$sec'
        : '$m:$sec';
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

class _ServerOption extends StatelessWidget {
  final String label;
  final bool selected;
  final bool autofocus;
  final VoidCallback onPressed;
  const _ServerOption({
    required this.label,
    required this.selected,
    required this.autofocus,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Focusable(
      autofocus: autofocus,
      onPressed: onPressed,
      builder: (context, focused) {
        final bg = focused ? Colors.white : AppColors.bg2;
        final fg = focused ? AppColors.onFocus : AppColors.ink;
        return AnimatedScale(
          scale: focused ? 1.04 : 1,
          duration: const Duration(milliseconds: 150),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected && !focused
                    ? AppColors.accent
                    : Colors.white.withValues(alpha: 0.06),
                width: 2,
              ),
            ),
            child: Row(children: [
              Text(label,
                  style: TextStyle(
                      fontSize: 25, fontWeight: FontWeight.w800, color: fg)),
              const Spacer(),
              if (selected)
                Icon(Icons.check,
                    color: focused ? AppColors.onFocus : AppColors.accent),
            ]),
          ),
        );
      },
    );
  }
}

