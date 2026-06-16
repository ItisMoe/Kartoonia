import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

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
      platform.setProperty('hls-bitrate', 'max');
    }
  }

  /// Point the shared player at [url] and start playback. Reuses the existing
  /// decoder — does NOT create a new player. [headers] are forwarded to libmpv
  /// for the manifest and every segment (Referer/UA/Origin for the CDN).
  Future<void> open(String url, {Map<String, String> headers = const {}}) async {
    ensureCreated();
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
    await _player!.open(Media(videoUrl, httpHeaders: headers));
    if (audioUrl != null) {
      await _player!.setAudioTrack(AudioTrack.uri(audioUrl));
    }
  }

  /// Stop playback and unload the current media WITHOUT disposing the player, so
  /// the next [open] reuses the same warm decoder. Safe to call when nothing is
  /// playing.
  Future<void> stop() async {
    await _player?.stop();
  }
}
