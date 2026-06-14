import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

/// Thin wrapper over the YouTube Data API v3 `search.list`. Called only when the
/// user triggers the trailer / theme-song action — one request per open.
class YoutubeService {
  /// Returns the first matching video id for [query], or null if none.
  /// [apiKey] is the user-set key (Settings) when non-empty, else the bundled
  /// default. Throws on transport/quota/HTTP errors (caller shows a message).
  static Future<String?> firstVideoId(String query, {String apiKey = ''}) async {
    final key = apiKey.trim().isNotEmpty ? apiKey.trim() : kYoutubeApiKey;
    final uri = Uri.parse('https://www.googleapis.com/youtube/v3/search')
        .replace(queryParameters: {
      'part': 'snippet',
      'type': 'video',
      'maxResults': '1',
      'q': query,
      'key': key,
    });
    final r = await http.get(uri);
    if (r.statusCode != 200) {
      throw Exception('YouTube API ${r.statusCode}');
    }
    final items = (jsonDecode(r.body)['items'] as List?) ?? const [];
    if (items.isEmpty) return null;
    final id = items.first['id'];
    return id is Map ? id['videoId'] as String? : null;
  }

  /// Lightweight validation used by Settings: true if the key returns 200.
  static Future<bool> validateKey(String apiKey) async {
    final key = apiKey.trim();
    if (key.isEmpty) return false;
    final uri = Uri.parse('https://www.googleapis.com/youtube/v3/search')
        .replace(queryParameters: {
      'part': 'snippet',
      'type': 'video',
      'maxResults': '1',
      'q': 'test',
      'key': key,
    });
    try {
      final r = await http.get(uri);
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
