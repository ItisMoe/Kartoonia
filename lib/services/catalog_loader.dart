import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

import '../models/carateen_adapter.dart';
import '../models/carateen_music.dart';
import '../models/catalog_source.dart';
import '../models/content_item.dart';
import '../models/stardima_adapter.dart';
import 'catalog_updater.dart';

/// Typed result of parsing one catalog source.
class ParsedCatalog {
  final List<Show> shows;
  final List<Movie> movies;
  const ParsedCatalog(this.shows, this.movies);
}

/// Loads and parses a bundled/cached catalog into typed models entirely OFF
/// the UI isolate.
///
/// The catalogs are 15–30 MB of JSON; decoding them plus building thousands of
/// [Show]/[Movie] objects takes multiple seconds of pure CPU on a low-end TV
/// box. Doing that on the UI isolate froze the app for the whole duration
/// (startup used to block the first frame on it). Here the main isolate only
/// gathers the inputs that *require* it — the asset bytes via [rootBundle] and
/// the cache path via path_provider — and everything expensive (file read,
/// UTF-8 decode, jsonDecode, model construction) happens in [Isolate.run].
/// The models come back via `Isolate.exit`, which transfers the object graph
/// without copying.
///
/// Source-selection semantics mirror [CatalogUpdater.loadJson]: a valid cached
/// GitHub download wins, the bundled asset is the always-working fallback.
Future<ParsedCatalog> loadCatalogModels(CatalogSource src) async {
  // Cache path (path_provider needs the platform channel → main isolate).
  // Unavailable in unit tests / on cache errors — the asset covers those.
  String? cachePath;
  try {
    final dir = await getApplicationSupportDirectory();
    cachePath = '${dir.path}/catalogs/${src.assetPath.split('/').last}';
  } catch (_) {}

  // Raw asset bytes only — no UTF-8/JSON decode on the UI isolate.
  final data = await rootBundle.load(src.assetPath);
  final assetBytes =
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

  return Isolate.run(() => _parseCatalog(src, cachePath, assetBytes));
}

/// Load the bundled carateen theme-song album (`carateen_music.json`). Tiny
/// (~30 KB), so it decodes inline — no isolate needed. Returns an empty list if
/// the asset is missing (older builds) so callers can no-op gracefully.
Future<List<CarateenTrack>> loadCarateenMusic() async {
  try {
    final raw = await rootBundle.loadString('assets/carateen_music.json');
    return parseCarateenMusic(json.decode(raw) as Map<String, dynamic>);
  } catch (_) {
    return const [];
  }
}

ParsedCatalog _parseCatalog(
    CatalogSource src, String? cachePath, Uint8List assetBytes) {
  final json = _decodeCacheOrAsset(cachePath, assetBytes);
  switch (src) {
    case CatalogSource.arabicToons:
      final shows = ((json['shows'] as List?) ?? const [])
          .map((e) => Show.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
      final movies = ((json['movies'] as List?) ?? const [])
          .map((e) => Movie.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
      return ParsedCatalog(shows, movies);
    case CatalogSource.stardima:
      final (shows, movies) = StardimaAdapter.parse(json);
      return ParsedCatalog(shows, movies);
    case CatalogSource.carateen:
      final (shows, movies) = CarateenAdapter.parse(json);
      return ParsedCatalog(shows, movies);
    case CatalogSource.wcoflix:
      return const ParsedCatalog([], []); // live-scraped, no bundled asset
  }
}

/// The `generated_at` unix timestamp from the head of a catalog, or null when
/// the schema doesn't carry one (arabicToons/stardima). Scans only the first
/// bytes — the field sits in the opening object, so we never decode the whole
/// 30 MB payload just to read it.
int? generatedAtFromCatalogBytes(Uint8List bytes) {
  final n = bytes.length < 512 ? bytes.length : 512;
  // The prefix holds only ASCII keys + digits (Arabic content comes later),
  // so a latin1 view is safe for the scan.
  final head = String.fromCharCodes(bytes, 0, n);
  final m = RegExp(r'"generated_at"\s*:\s*(\d+)').firstMatch(head);
  return m == null ? null : int.tryParse(m.group(1)!);
}

/// True when the bundled asset should win over a cached OTA download — i.e. the
/// asset is STRICTLY newer. This stops a stale OTA cache from shadowing the
/// fresher catalog an APK upgrade ships. When either side lacks a timestamp we
/// keep the historical cache-first behavior (returns false).
bool preferAssetOverCache(int? cacheGen, int? assetGen) =>
    cacheGen != null && assetGen != null && assetGen > cacheGen;

/// Decoded catalog JSON: the FRESHER of the cached download and the bundled
/// asset (by `generated_at`), else cache-first. Any cache problem
/// (missing/corrupt file) silently falls back to the bundle.
Map<String, dynamic> _decodeCacheOrAsset(
    String? cachePath, Uint8List assetBytes) {
  if (cachePath != null) {
    try {
      final f = File(cachePath);
      if (f.existsSync()) {
        final cacheBytes = f.readAsBytesSync();
        // An APK upgrade keeps the app's old OTA cache; when the bundled asset
        // is newer, use it instead of the stale cache.
        if (!preferAssetOverCache(generatedAtFromCatalogBytes(cacheBytes),
            generatedAtFromCatalogBytes(assetBytes))) {
          final decoded = _decodeJsonBytes(cacheBytes);
          if (decoded is Map<String, dynamic> &&
              CatalogUpdater.looksLikeCatalog(decoded)) {
            return decoded;
          }
        }
      }
    } catch (_) {}
  }
  return _decodeJsonBytes(assetBytes) as Map<String, dynamic>;
}

/// Fused UTF-8 + JSON decode — skips materialising the intermediate 30 MB
/// string that `jsonDecode(utf8.decode(bytes))` would allocate.
Object? _decodeJsonBytes(Uint8List bytes) =>
    utf8.decoder.fuse(json.decoder).convert(bytes);
