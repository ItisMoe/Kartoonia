import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config.dart';

/// Why a YouTube search failed, so the UI can show a meaningful message instead
/// of a single catch-all "no video found".
enum YoutubeErrorKind {
  /// 403/429 — the (shared) API key hit its daily quota or was rate-limited.
  /// The user can set their own key in Settings to bypass it.
  quota,

  /// Any other non-200 HTTP status from the API.
  http,

  /// Transport failure (no connectivity, DNS, TLS, timeout).
  network,
}

class YoutubeException implements Exception {
  final YoutubeErrorKind kind;
  final String message;
  YoutubeException(this.kind, this.message);
  @override
  String toString() => 'YoutubeException($kind): $message';
}

/// Pure, testable: extract the video ids from a `search.list` JSON response
/// body, in result order, skipping any malformed entries.
List<String> parseSearchResultIds(String responseBody) {
  final items = (jsonDecode(responseBody)['items'] as List?) ?? const [];
  final ids = <String>[];
  for (final item in items) {
    final id = item is Map ? item['id'] : null;
    final videoId = id is Map ? id['videoId'] : null;
    if (videoId is String && videoId.isNotEmpty) ids.add(videoId);
  }
  return ids;
}

/// Thin wrapper over the YouTube Data API v3 `search.list`. Called only when the
/// user triggers the trailer / theme-song action — one request per open.
class YoutubeService {
  /// Returns up to [max] matching video ids for [query], in relevance order.
  /// The caller tries them one by one so a single unplayable top result (age /
  /// geo restricted, no muxed stream) doesn't sink the whole open.
  ///
  /// [apiKey] is the user-set key (Settings) when non-empty, else the bundled
  /// default. Throws [YoutubeException] (kind-tagged) on quota / HTTP / network
  /// errors so the caller can explain what went wrong.
  static Future<List<String>> searchVideoIds(
    String query, {
    String apiKey = '',
    int max = 5,
  }) async {
    final key = apiKey.trim().isNotEmpty ? apiKey.trim() : kYoutubeApiKey;
    final uri = Uri.parse('https://www.googleapis.com/youtube/v3/search')
        .replace(queryParameters: {
      'part': 'snippet',
      'type': 'video',
      'maxResults': '$max',
      'q': query,
      'key': key,
    });
    final http.Response r;
    try {
      r = await http.get(uri);
    } catch (e) {
      throw YoutubeException(YoutubeErrorKind.network, '$e');
    }
    if (r.statusCode == 403 || r.statusCode == 429) {
      // Quota exceeded / rate limited / disabled-or-invalid key.
      throw YoutubeException(YoutubeErrorKind.quota, 'YouTube API ${r.statusCode}');
    }
    if (r.statusCode != 200) {
      throw YoutubeException(YoutubeErrorKind.http, 'YouTube API ${r.statusCode}');
    }
    return parseSearchResultIds(r.body);
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
