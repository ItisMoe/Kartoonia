import '../models/content_item.dart';
import '../utils/youtube_query.dart';
import 'storage_service.dart';
import 'youtube_service.dart';

typedef SearchFn = Future<List<String>> Function(String query);

/// Resolves a show → its theme-song YouTube videoId, caching the result
/// permanently so each show costs at most one YouTube API search ever. The
/// stream URL itself is NOT cached here (it expires); callers re-extract it via
/// [YoutubeStreamResolver] which costs no API quota.
class ShaaratResolver {
  final StorageService storage;
  final SearchFn search;
  ShaaratResolver(this.storage, {SearchFn? search})
      : search = search ?? _defaultSearch;

  static Future<List<String>> _defaultSearch(String q) =>
      YoutubeService.searchVideoIds(q, max: 3);

  /// videoId for [show]'s theme, or null when none exists. Cache semantics:
  /// null = never searched, '' = searched/none found, non-empty = the id. A
  /// transient search failure (quota/network) returns null WITHOUT caching, so
  /// it is retried on a later open.
  Future<String?> videoIdFor(Show show) async {
    final cached = storage.getShaaratVideoId(show.id);
    if (cached != null) return cached.isEmpty ? null : cached;
    try {
      final ids = await search(youtubeSearchQuery(show));
      final id = ids.isNotEmpty ? ids.first : '';
      await storage.setShaaratVideoId(show.id, id);
      return id.isEmpty ? null : id;
    } catch (_) {
      return null;
    }
  }
}
