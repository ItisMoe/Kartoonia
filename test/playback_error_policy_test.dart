import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/services/playback_error_policy.dart';

void main() {
  group('shouldFailOverAfterError', () {
    test('ignores a transient error while playback keeps advancing', () {
      // The bug: a single libmpv error log during healthy long playback used to
      // trigger "All servers failed". Position advanced, so it must be ignored.
      expect(
        shouldFailOverAfterError(
          positionBefore: const Duration(minutes: 42),
          positionNow: const Duration(minutes: 42, seconds: 6),
          playing: true,
          buffering: false,
          completed: false,
        ),
        isFalse,
      );
    });

    test('ignores an error that fires right as the file completes', () {
      expect(
        shouldFailOverAfterError(
          positionBefore: const Duration(minutes: 42),
          positionNow: const Duration(minutes: 42),
          playing: false,
          buffering: false,
          completed: true,
        ),
        isFalse,
      );
    });

    test('ignores an error while the user has the video paused', () {
      // Paused => position frozen and not playing/buffering. Not a stream death.
      expect(
        shouldFailOverAfterError(
          positionBefore: const Duration(minutes: 10),
          positionNow: const Duration(minutes: 10),
          playing: false,
          buffering: false,
          completed: false,
        ),
        isFalse,
      );
    });

    test('fails over when playback is frozen but still trying to play', () {
      expect(
        shouldFailOverAfterError(
          positionBefore: const Duration(minutes: 10),
          positionNow: const Duration(minutes: 10),
          playing: true,
          buffering: true,
          completed: false,
        ),
        isTrue,
      );
    });

    test('fails over when stalled and stuck buffering even if not playing', () {
      expect(
        shouldFailOverAfterError(
          positionBefore: const Duration(minutes: 10),
          positionNow: const Duration(minutes: 10),
          playing: false,
          buffering: true,
          completed: false,
        ),
        isTrue,
      );
    });
  });
}
