import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/services/youtube_service.dart';

void main() {
  group('parseSearchResultIds', () {
    test('extracts video ids in result order', () {
      final body = jsonEncode({
        'items': [
          {
            'id': {'kind': 'youtube#video', 'videoId': 'aaa'}
          },
          {
            'id': {'kind': 'youtube#video', 'videoId': 'bbb'}
          },
        ]
      });
      expect(parseSearchResultIds(body), ['aaa', 'bbb']);
    });

    test('skips malformed / non-video entries', () {
      final body = jsonEncode({
        'items': [
          {
            'id': {'kind': 'youtube#channel', 'channelId': 'ccc'}
          },
          {'id': 'not-a-map'},
          {
            'id': {'videoId': ''}
          },
          {
            'id': {'videoId': 'good'}
          },
        ]
      });
      expect(parseSearchResultIds(body), ['good']);
    });

    test('returns empty when there are no items', () {
      expect(parseSearchResultIds(jsonEncode({'items': []})), isEmpty);
      expect(parseSearchResultIds(jsonEncode({})), isEmpty);
    });
  });
}
