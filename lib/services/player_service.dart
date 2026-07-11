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

  /// The shared player. Only valid after [ensureCreated] (called for you by
  /// [open]); screens call [ensureCreated] in `initState` before wiring streams.
  Player get player => _player!;

  /// The shared render controller passed to the `Video` widget.
  VideoController get controller => _controller!;

  bool get isCreated => _player != null;

  /// Lazily build the single player + controller. No-op after the first call.
  void ensureCreated() {
    if (_player != null) return;
    final p = Player();
    _player = p;
    _controller = VideoController(p);
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

  /// media_kit's own Android default (AndroidVideoController.getDefaultHwdec on
  /// a real device): hardware decode via MediaCodec. Restored on every open that
  /// doesn't force software decoding.
  static const _defaultHwdec = 'auto-safe';

  /// Select the decoder for the NEXT open. libmpv picks the decoder when the
  /// file loads, so this must run before [Player.open].
  ///
  /// Why non-default modes exist at all: on some TV boxes the hardware H.264
  /// decoder hands mpv's GPU path garbage frames for the WCOFlix (Everything
  /// mode) 720p/1080p mp4s — the screen shows only shifting solid colors while
  /// audio plays fine. The streams themselves are plain H.264 yuv420p (probed),
  /// and the exact same content garbled the same way in the desktop VLC tool
  /// until hardware decode was disabled there too (commit 15c25fb). v2.2.6
  /// forced software decode (`no`) for wcoflix opens, but at least one box
  /// still garbles even then, so the mode is now user-selectable per device:
  /// `no` (software), `auto-safe` (the Android default: direct mediacodec),
  /// or `mediacodec-copy` (hardware decode, frames copied back to system
  /// memory — a different render upload path than direct mediacodec).
  Future<void> _applyHwdec(String mode) async {
    final platform = _player!.platform;
    if (platform is NativePlayer) {
      await platform.setProperty('hwdec', mode);
    }
  }

  /// Point the shared player at [url] and start playback. Reuses the existing
  /// decoder — does NOT create a new player. [headers] are forwarded to libmpv
  /// for the manifest and every segment (Referer/UA/Origin for the CDN).
  /// [hwdec] selects the decode mode for THIS media only (see [_applyHwdec]);
  /// null keeps media_kit's Android hardware default, and the next plain open
  /// restores it.
  Future<void> open(
    String url, {
    Map<String, String> headers = const {},
    String? hwdec,
  }) async {
    ensureCreated();
    await _applyHwdec(hwdec ?? _defaultHwdec);
    await _player!.open(Media(url, httpHeaders: headers));
  }

  /// Open a video-only [videoUrl] and attach [audioUrl] as an external audio
  /// track (how YouTube 720p+ is played: separate video + audio files). libmpv
  /// timestamp-syncs the two. When [audioUrl] is null this behaves like [open].
  Future<void> openWithAudio(
    String videoUrl, {
    String? audioUrl,
    Map<String, String> headers = const {},
  }) async {
    ensureCreated();
    await _applyHwdec(_defaultHwdec);
    // Open WITHOUT auto-playing, attach the external audio, THEN play — so the
    // full graph exists before playback starts. Opening with play:true lets the
    // video run for ~1-2s and then attaching the audio track forces libmpv to
    // rebuild and re-seek the video to 0 (audio starts from its own 0), which
    // looked like the video "replaying from the start" while audio kept going.
    await _player!.open(Media(videoUrl, httpHeaders: headers), play: false);
    if (audioUrl != null) {
      await _player!.setAudioTrack(AudioTrack.uri(audioUrl));
    }
    await _player!.play();
  }

  /// Stop playback and unload the current media WITHOUT disposing the player, so
  /// the next [open] reuses the same warm decoder. Safe to call when nothing is
  /// playing.
  Future<void> stop() async {
    await _player?.stop();
  }
}
