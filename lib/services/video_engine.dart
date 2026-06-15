import 'dart:async';

import 'package:video_player/video_player.dart';

/// App-wide coordinator that serializes ExoPlayer decoder *release → acquire*.
///
/// ## Why this exists
///
/// Android (especially TV boxes) exposes only a handful of hardware video
/// decoders. `video_player` releases a controller's decoder **asynchronously**
/// on the platform thread, but Flutter's `State.dispose()` is **synchronous** —
/// it kicks off `controller.dispose()` and returns immediately, unable to await
/// the native release.
///
/// So when one player screen is torn down and another is opened (episode →
/// episode, trailer → episode, back → replay …), the previous ExoPlayer's
/// decoder is frequently *still being freed* at the moment the next controller
/// calls `initialize()`. That next `initialize()` then intermittently fails to
/// acquire a decoder — the video "doesn't play" even though the exact same
/// content played seconds ago. The earlier single-controller fix only covered
/// disposal **within** one screen; this covers the gap **between** screens.
///
/// ## How it works
///
/// Every decoder teardown is chained onto one global queue ([_teardown]). A
/// screen about to build a controller first awaits [ready] (or awaits the
/// future returned by [release]), guaranteeing no new ExoPlayer is created until
/// every pending one has fully released its decoder. Exactly one acquire or
/// release is ever in flight, so the decoder pool can't be transiently
/// over-subscribed by a release that hasn't landed yet.
class VideoEngine {
  /// Public so tests can use an isolated instance; production code uses
  /// [instance].
  VideoEngine();

  static final VideoEngine instance = VideoEngine();

  /// Tail of the serialized teardown queue. Starts already-completed so the very
  /// first acquire pays no cost.
  Future<void> _teardown = Future<void>.value();

  /// Run an async teardown [task] strictly after every previously-queued task.
  /// Returns a future for *this* task's slot in the queue (i.e. it completes
  /// once this task and all before it have finished).
  ///
  /// A throwing/timing-out task is swallowed so one bad release can never wedge
  /// the queue and block all future video.
  Future<void> runSerialized(Future<void> Function() task) {
    final next = _teardown.then((_) async {
      try {
        await task();
      } catch (_) {
        // Already gone / platform hiccup — keep the queue moving.
      }
    });
    _teardown = next;
    return next;
  }

  /// Release [controller]'s native decoder, serialized behind any pending
  /// teardown. Pass `null` to simply wait for the queue to drain without
  /// releasing anything. Await the result before creating a new controller.
  Future<void> release(VideoPlayerController? controller) {
    if (controller == null) return _teardown;
    return runSerialized(
      () => controller.dispose().timeout(const Duration(seconds: 5)),
    );
  }

  /// Completes once all pending decoder releases have finished. Call this
  /// immediately before constructing + initializing a new controller.
  Future<void> ready() => _teardown;
}
