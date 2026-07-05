import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../models/catalog_source.dart';

/// Keeps the catalogs fresh WITHOUT shipping a new APK: the repo's catalog
/// JSONs (committed under `assets/` on GitHub) are re-downloaded on launch
/// into app storage, and [loadJson] serves cache-first with the bundled asset
/// as the always-working fallback.
///
/// Freshly downloaded data applies on the NEXT launch — deliberately. The
/// catalogs are 15–30 MB; re-parsing and re-merging them mid-session on the
/// UI isolate would jank whatever screen the user is on, for content they'll
/// see next open anyway. Downloads are ETag-conditional, so an unchanged
/// catalog costs one 304 round-trip, not 45 MB per launch.
class CatalogUpdater {
  static const _rawBase =
      'https://raw.githubusercontent.com/ItisMoe/Kartoonia/main';

  static Future<File> _cacheFile(CatalogSource src) async {
    final dir = await getApplicationSupportDirectory();
    final name = src.assetPath.split('/').last;
    return File('${dir.path}/catalogs/$name');
  }

  /// Decoded catalog JSON for [src]: valid cached download first, bundled
  /// asset otherwise. Any cache problem — missing file, corrupt JSON, no
  /// path_provider plugin (unit tests) — silently falls back to the bundle.
  static Future<Map<String, dynamic>> loadJson(CatalogSource src) async {
    try {
      final f = await _cacheFile(src);
      if (await f.exists()) {
        final decoded = jsonDecode(await f.readAsString());
        if (decoded is Map<String, dynamic> && _looksLikeCatalog(decoded)) {
          return decoded;
        }
      }
    } catch (_) {}
    return jsonDecode(await rootBundle.loadString(src.assetPath))
        as Map<String, dynamic>;
  }

  /// Refresh every catalog from GitHub. Fire-and-forget from startup; each
  /// source fails independently (offline / GitHub down just means the cached
  /// or bundled data keeps serving).
  static Future<void> refreshAll() async {
    for (final src in CatalogSource.values) {
      if (src.assetPath.isEmpty) continue; // live-scraped source, no asset
      try {
        await _refresh(src);
      } catch (_) {}
    }
  }

  static Future<void> _refresh(CatalogSource src) async {
    final f = await _cacheFile(src);
    final etagFile = File('${f.path}.etag');
    final headers = <String, String>{};
    if (await f.exists() && await etagFile.exists()) {
      headers['If-None-Match'] = await etagFile.readAsString();
    }
    final r = await http
        .get(Uri.parse('$_rawBase/${src.assetPath}'), headers: headers)
        .timeout(const Duration(minutes: 5));
    if (r.statusCode == 304) return; // unchanged since last download
    if (r.statusCode != 200 || r.body.isEmpty) return;

    // Validate OFF the UI isolate before committing: a truncated download or
    // an HTML error page must never replace a working cache.
    if (!await compute(_isValidCatalogBody, r.body)) return;

    await f.parent.create(recursive: true);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(r.body, flush: true);
    if (await f.exists()) await f.delete();
    await tmp.rename(f.path);
    final etag = r.headers['etag'];
    if (etag != null && etag.isNotEmpty) {
      await etagFile.writeAsString(etag, flush: true);
    }
  }

  static bool _looksLikeCatalog(Map<String, dynamic> d) =>
      // Arabic Toons uses `shows`, Stardima uses `tvshows`; both have `movies`.
      (d['shows'] is List || d['tvshows'] is List) && d['movies'] is List;

  static bool _isValidCatalogBody(String body) {
    try {
      final d = jsonDecode(body);
      return d is Map<String, dynamic> && _looksLikeCatalog(d);
    } catch (_) {
      return false;
    }
  }
}
