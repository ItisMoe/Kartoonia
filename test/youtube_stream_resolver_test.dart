import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/services/youtube_stream_resolver.dart';

void main() {
  group('pickMuxedUrl', () {
    test('returns null when there are no muxed streams', () {
      expect(pickMuxedUrl(const []), isNull);
    });

    test('picks the highest stream at or below 720p', () {
      final options = const [
        MuxedOption(height: 360, url: 'u360'),
        MuxedOption(height: 720, url: 'u720'),
        MuxedOption(height: 1080, url: 'u1080'),
      ];
      expect(pickMuxedUrl(options), 'u720');
    });

    test('ignores streams above 720p', () {
      final options = const [
        MuxedOption(height: 480, url: 'u480'),
        MuxedOption(height: 1080, url: 'u1080'),
      ];
      expect(pickMuxedUrl(options), 'u480');
    });

    test('falls back to the lowest stream when all exceed 720p', () {
      final options = const [
        MuxedOption(height: 1080, url: 'u1080'),
        MuxedOption(height: 1440, url: 'u1440'),
      ];
      expect(pickMuxedUrl(options), 'u1080');
    });
  });

  group('pickBestAudioUrl', () {
    test('returns null when empty', () {
      expect(pickBestAudioUrl(const []), isNull);
    });
    test('picks the highest bitrate', () {
      expect(
        pickBestAudioUrl(const [
          AudioStreamCandidate(bitrate: 128000, url: 'a', isMp4: true),
          AudioStreamCandidate(bitrate: 256000, url: 'b', isMp4: false),
        ]),
        'b',
      );
    });
    test('prefers mp4 on a bitrate tie', () {
      expect(
        pickBestAudioUrl(const [
          AudioStreamCandidate(bitrate: 128000, url: 'webm', isMp4: false),
          AudioStreamCandidate(bitrate: 128000, url: 'mp4', isMp4: true),
        ]),
        'mp4',
      );
    });
  });

  group('selectVideoOptions', () {
    test('caps at maxHeight and sorts high to low (all video-only)', () {
      final r = selectVideoOptions(const [
        VideoStreamCandidate(height: 360, url: '360', isMp4: true),
        VideoStreamCandidate(height: 1080, url: '1080', isMp4: true),
        VideoStreamCandidate(height: 720, url: '720', isMp4: true),
      ]);
      expect(r.map((o) => o.height).toList(), [720, 360]);
      expect(r.every((o) => o.muxed == false), isTrue);
    });
    test('prefers mp4 when a height has both mp4 and webm', () {
      final r = selectVideoOptions(const [
        VideoStreamCandidate(height: 720, url: '720webm', isMp4: false),
        VideoStreamCandidate(height: 720, url: '720mp4', isMp4: true),
      ]);
      expect(r.length, 1);
      expect(r.first.url, '720mp4');
    });
    test('keeps webm when a height has no mp4', () {
      final r = selectVideoOptions(const [
        VideoStreamCandidate(height: 480, url: '480webm', isMp4: false),
      ]);
      expect(r.single.url, '480webm');
    });
    test('empty when nothing is at or below the cap', () {
      expect(
        selectVideoOptions(const [
          VideoStreamCandidate(height: 1080, url: '1080', isMp4: true),
        ], maxHeight: 720),
        isEmpty,
      );
    });
  });
}
