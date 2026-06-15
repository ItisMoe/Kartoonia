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
}
