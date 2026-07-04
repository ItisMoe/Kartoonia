import 'package:flutter/services.dart';
import '../models/content_item.dart';

/// Bridge to the native Google TV / Android TV home-screen recommendation
/// channel (see android `Recommendations.kt`). All calls are best-effort.
class Recommendations {
  static const _ch = MethodChannel('kartoonia/reco');

  /// Publish/refresh the recommended channel from a popular pool. Uses TMDB
  /// poster art (public, no Referer needed) so the launcher can load it.
  static Future<void> publish(List<ContentItem> items) async {
    try {
      await _ch.invokeMethod('publish', {
        'items': [
          for (final i in items)
            {'id': i.id, 'title': i.title, 'poster': i.posterUrl},
        ],
      });
    } catch (_) {
      // launcher without preview-channel support — ignore
    }
  }

  /// Upsert this item into the launcher's WATCH NEXT ("Continue Watching")
  /// row. [next] true publishes an "up next" card (episode finished, next one
  /// queued) instead of a progress-bar continue card. Pass TMDB art only —
  /// the launcher can't send the Referer the catalog CDN requires.
  static Future<void> updateWatchNext({
    required String id,
    required String title,
    required String poster,
    required int positionMs,
    required int durationMs,
    required bool isMovie,
    bool next = false,
  }) async {
    try {
      await _ch.invokeMethod('watchNext', {
        'id': id,
        'title': title,
        'poster': poster,
        'positionMs': positionMs,
        'durationMs': durationMs,
        'isMovie': isMovie,
        'next': next,
      });
    } catch (_) {}
  }

  /// Drop the item's WATCH NEXT card (finished, or removed by the user).
  static Future<void> removeWatchNext(String id) async {
    try {
      await _ch.invokeMethod('watchNextRemove', {'id': id});
    } catch (_) {}
  }

  /// The deep link the app was cold-launched with (if any).
  static Future<String?> initialDeepLink() async {
    try {
      return await _ch.invokeMethod<String>('getInitialDeepLink');
    } catch (_) {
      return null;
    }
  }

  /// Subsequent deep links while the app is running.
  static void onDeepLink(void Function(String link) handler) {
    _ch.setMethodCallHandler((call) async {
      if (call.method == 'deepLink' && call.arguments is String) {
        handler(call.arguments as String);
      }
      return null;
    });
  }
}
