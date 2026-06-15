import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/services/video_engine.dart';

void main() {
  group('VideoEngine.runSerialized', () {
    test('never overlaps tasks — a task waits for the previous to finish',
        () async {
      final engine = VideoEngine();
      final log = <String>[];
      final gateA = Completer<void>();

      final a = engine.runSerialized(() async {
        log.add('a-start');
        await gateA.future;
        log.add('a-end');
      });
      final b = engine.runSerialized(() async {
        log.add('b-start');
      });

      // Let microtasks drain: B must NOT have started while A is still running.
      await Future<void>.delayed(Duration.zero);
      expect(log, ['a-start'], reason: 'B must not start until A completes');

      gateA.complete();
      await Future.wait([a, b]);
      expect(log, ['a-start', 'a-end', 'b-start']);
    });

    test('ready() completes only after all queued teardowns finish', () async {
      final engine = VideoEngine();
      var done = false;
      final gate = Completer<void>();

      engine.runSerialized(() async {
        await gate.future;
        done = true;
      });

      var readyResolved = false;
      final readyFuture = engine.ready().then((_) => readyResolved = true);

      await Future<void>.delayed(Duration.zero);
      expect(readyResolved, isFalse,
          reason: 'ready() must not resolve while a teardown is pending');

      gate.complete();
      await readyFuture;
      expect(done, isTrue);
      expect(readyResolved, isTrue);
    });

    test('a failing teardown does not wedge the queue', () async {
      final engine = VideoEngine();
      final log = <String>[];

      final a = engine.runSerialized(() async {
        log.add('a');
        throw Exception('dispose blew up');
      });
      final b = engine.runSerialized(() async {
        log.add('b');
      });

      await Future.wait([a, b]);
      expect(log, ['a', 'b'],
          reason: 'B must still run after A throws — one bad release can never '
              'block every future video');
    });
  });
}
