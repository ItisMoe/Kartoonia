import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'device_perf.dart';

/// The app's ONE and ONLY video player.
///
/// ## Why a single shared instance
///
/// Android devices — especially TV boxes — expose only a handful of hardware
/// video decoders (MediaCodec). The old design built a brand-new player (and
/// therefore acquired a fresh decoder) for every episode and every trailer, and
/// released it on screen teardown. Releases that were slow, hung, or raced the
/// next acquire leaked decoders permanently, so after opening a handful of
/// videos the pool was exhausted and NOTHING played again until the app was
/// killed and relaunched.
///
/// This service sidesteps that entirely: it creates exactly one libmpv [Player]
/// (and its render [VideoController]) the first time playback is needed and
/// keeps it alive for the whole process. Every screen — the main player and the
/// YouTube trailer player — reuses it and merely *swaps the media* via [open].
/// A decoder is acquired once and never re-acquired, so the pool can't drain no
/// matter how many episodes are opened.
///
/// The player is intentionally **never disposed**; screens call [stop] on
/// teardown to halt playback and free CPU/network while keeping the instance
/// (and its decoder) warm for the next open.
class PlayerService {
  PlayerService._();
  static final PlayerService instance = PlayerService._();

  Player? _player;
  VideoController? _controller;

  // Ownership generation for the shared player. Because every screen swaps
  // media on the SAME player, an open() that was still in flight when its
  // screen stopped/was covered (a شارات reel resolving as the user enters a
  // show, a player screen backed out of mid-load) used to land LATE and hijack
  // playback for whoever owned the player next — "it opened the previous
  // show". Every [stop] bumps the generation and returns it; [open]/
  // [openWithAudio] callers pass the generation their own stop() returned, and
  // a call whose generation is stale becomes a no-op.
  int _session = 0;

  // The generation that most recently ISSUED an open on the player. A stale
  // open's cleanup must not stop the player once the live generation has
  // issued its own open: that open is queued behind the stale one and replaces
  // its media anyway, so a stop here would execute after it and kill the
  // rightful owner's playback instead of the stray media.
  int _openIssued = -1;

  // True only while the media on the player is one the CURRENT generation
  // opened; false between a [stop] and the next landed open. Gates
  // [positionLive]/[playingLive]/[completedLive].
  bool _mediaLive = false;

  /// The shared player. Only valid after [ensureCreated] (called for you by
  /// [open]); screens call [ensureCreated] in `initState` before wiring streams.
  Player get player => _player!;

  /// The shared render controller passed to the `Video` widget.
  VideoController get controller => _controller!;

  bool get isCreated => _player != null;

  /// The raw player streams keep emitting the PREVIOUS media's state (its
  /// position, a stray completed) between a [stop] and the next open landing —
  /// acting on those queued phantom episodes and skipped resume seeks. These
  /// views drop everything emitted while no current-generation media is live,
  /// so screens can subscribe without re-discovering that guard.
  ///
  /// `duration` and `error` are deliberately NOT gated: load flows wait on the
  /// first duration/error event to detect readiness/failure, and those can
  /// fire before the open() call itself returns (i.e. before the gate opens).
  Stream<Duration> get positionLive =>
      player.stream.position.where((_) => _mediaLive);
  Stream<bool> get playingLive =>
      player.stream.playing.where((_) => _mediaLive);
  Stream<bool> get completedLive =>
      player.stream.completed.where((_) => _mediaLive);

  /// Lazily build the single player + controller. No-op after the first call.
  void ensureCreated() {
    if (_player != null) return;
    final p = Player();
    _player = p;
    _controller = VideoController(p, configuration: _androidVideoConfig());
    // libmpv otherwise opens whatever variant the HLS demuxer defaults to, which
    // is frequently the LOWEST entry in a master playlist. Force the highest so
    // "Auto" lands on the best quality with no manual track switch. Set once on
    // the long-lived shared player; it survives every open(). Fire-and-forget —
    // a native property nudge that must not block player creation.
    final platform = p.platform;
    if (platform is NativePlayer) {
      // Low-spec boxes (weak decoder / Wi-Fi) default to a mid HLS variant
      // (~720p-class, 4 Mbps) instead of the master playlist's top entry —
      // forcing max there stuttered mid-episode. The in-player resolution
      // picker still lets the user select any variant manually.
      platform.setProperty(
          'hls-bitrate', DevicePerf.lowSpec ? '4000000' : 'max');
      // Prefer the Arabic audio rendition on multi-language streams (some
      // Stardima HLS masters carry several). Restores what the Python
      // prototype did with VLC's --audio-language; ExoPlayer couldn't, libmpv
      // can. Streams without an Arabic track just play their default.
      platform.setProperty('alang', 'ara,ar');
    }
  }

  /// Render config for the shared [VideoController].
  ///
  /// On Android we render with `vo=mediacodec_embed` + `hwdec=mediacodec`: the
  /// hardware decoder writes decoded frames STRAIGHT to the output surface, so
  /// there is no per-frame libmpv GL render pass and no decode→system-RAM copy
  /// (what `auto-safe`/`mediacodec-copy` does). On weak TV boxes those two costs
  /// were what dropped playback to ~5-10 fps once Impeller (the correct, but on
  /// this GPU expensive, texture compositor) was restored — the box's video
  /// hardware does the heavy lifting instead of the GPU/CPU, and Flutter only
  /// composites one hardware surface. The default (gpu/auto-safe) is kept on
  /// desktop/other platforms, which don't have mediacodec.
  VideoControllerConfiguration _androidVideoConfig() {
    if (!kIsWeb && Platform.isAndroid) {
      return const VideoControllerConfiguration(
        vo: 'mediacodec_embed',
        hwdec: 'mediacodec',
      );
    }
    return const VideoControllerConfiguration();
  }

  /// Point the shared player at [url] and start playback. Reuses the existing
  /// decoder — does NOT create a new player. [headers] are forwarded to libmpv
  /// for the manifest and every segment (Referer/UA/Origin for the CDN).
  ///
  /// Decoding is always media_kit's hardware default. v2.2.6/v2.2.7 forced or
  /// user-selected software decode for Everything-mode media chasing a
  /// "shifting solid colors, audio fine" picture — but the picture stayed
  /// scrambled under EVERY decoder, which proved the received bitstream itself
  /// was garbage: the wcostream embed serves a decoy stream to clients its
  /// anti-bot scoring flags. The real fix is in WcoflixHttp (plain-transport
  /// resolve for wcostream.com), not the decoder.
  /// [session] must be the generation the caller's own [stop] returned. A stale
  /// generation means another screen has since stopped or taken over the
  /// player, so this open is silently dropped.
  Future<void> open(
    String url, {
    Map<String, String> headers = const {},
    required int session,
  }) async {
    ensureCreated();
    if (session != _session) return;
    _openIssued = session;
    await _player!.open(Media(url, httpHeaders: headers));
    if (await _dropIfStale(session)) return;
    _mediaLive = true;
  }

  /// Open a video-only [videoUrl] and attach [audioUrl] as an external audio
  /// track (how YouTube 720p+ is played: separate video + audio files). libmpv
  /// timestamp-syncs the two. When [audioUrl] is null this behaves like [open].
  Future<void> openWithAudio(
    String videoUrl, {
    String? audioUrl,
    Map<String, String> headers = const {},
    required int session,
  }) async {
    ensureCreated();
    if (session != _session) return;
    _openIssued = session;
    // Open WITHOUT auto-playing, attach the external audio, THEN play — so the
    // full graph exists before playback starts. Opening with play:true lets the
    // video run for ~1-2s and then attaching the audio track forces libmpv to
    // rebuild and re-seek the video to 0 (audio starts from its own 0), which
    // looked like the video "replaying from the start" while audio kept going.
    await _player!.open(Media(videoUrl, httpHeaders: headers), play: false);
    if (await _dropIfStale(session)) return;
    _mediaLive = true;
    if (audioUrl != null) {
      await _player!.setAudioTrack(AudioTrack.uri(audioUrl));
      if (await _dropIfStale(session)) return;
    }
    await _player!.play();
    await _dropIfStale(session);
  }

  /// True (after silencing any stray media) when [session] went stale — a stop()
  /// raced in while this call's open was executing. The silencing stop is
  /// skipped once the LIVE generation has issued its own open: that open is
  /// queued behind ours and replaces the stray media anyway, and a stop here
  /// would execute after it and kill the rightful owner's playback.
  Future<bool> _dropIfStale(int session) async {
    if (session == _session) return false;
    if (_openIssued != _session) await _player!.stop();
    return true;
  }

  /// Stop playback and unload the current media WITHOUT disposing the player, so
  /// the next [open] reuses the same warm decoder. Safe to call when nothing is
  /// playing. Bumps the ownership generation — killing any in-flight [open]
  /// from before this stop — and returns it: capturing the return value IS how
  /// a screen claims the player before opening on it.
  Future<int> stop() async {
    _mediaLive = false;
    final s = ++_session;
    await _player?.stop();
    return s;
  }
}
