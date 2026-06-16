import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:kartoonia/services/video_quality.dart';

VideoTrack _vt(String id, int? height) =>
    VideoTrack(id, null, null, h: height);

void main() {
  group('buildQualityOptions', () {
    test('Auto is always first and uses the supplied label', () {
      final opts = buildQualityOptions(const [], autoLabel: 'تلقائي');
      expect(opts.length, 1);
      expect(opts.first.height, isNull);
      expect(opts.first.label, 'تلقائي');
    });

    test('lists distinct heights high to low, labelled "<h>p"', () {
      final opts = buildQualityOptions(
        [_vt('1', 480), _vt('2', 1080), _vt('3', 720)],
        autoLabel: 'Auto',
      );
      expect(opts.map((o) => o.height).toList(), [null, 1080, 720, 480]);
      expect(opts.map((o) => o.label).toList(),
          ['Auto', '1080p', '720p', '480p']);
    });

    test('dedupes equal heights and ignores null/zero-height tracks', () {
      final opts = buildQualityOptions(
        [_vt('1', 720), _vt('2', 720), _vt('3', 0), _vt('4', null)],
        autoLabel: 'Auto',
      );
      expect(opts.map((o) => o.height).toList(), [null, 720]);
    });
  });

  group('nearestTrackForHeight', () {
    test('returns the exact match when present', () {
      final tracks = [_vt('a', 1080), _vt('b', 720), _vt('c', 480)];
      expect(nearestTrackForHeight(tracks, 720)?.id, 'b');
    });

    test('returns the closest height when no exact match', () {
      final tracks = [_vt('a', 720), _vt('b', 480)];
      expect(nearestTrackForHeight(tracks, 1080)?.id, 'a');
      expect(nearestTrackForHeight(tracks, 500)?.id, 'b');
    });

    test('returns null when no track has a usable height', () {
      expect(nearestTrackForHeight([_vt('a', null), _vt('b', 0)], 720), isNull);
    });
  });

  group('hasSelectableQualities', () {
    test('false for zero or one distinct height', () {
      expect(hasSelectableQualities(const []), isFalse);
      expect(hasSelectableQualities([_vt('a', 720), _vt('b', 720)]), isFalse);
    });

    test('true for two or more distinct heights', () {
      expect(hasSelectableQualities([_vt('a', 720), _vt('b', 480)]), isTrue);
    });
  });
}
