import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';

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
    case CatalogSource.wcoflix:
      return const ParsedCatalog([], []); // live-scraped, no bundled asset
  }
}

/// Decoded catalog JSON: valid cached download first, bundled asset otherwise.
/// Any cache problem (missing/corrupt file) silently falls back to the bundle,
/// matching [CatalogUpdater.loadJson].
Map<String, dynamic> _decodeCacheOrAsset(
    String? cachePath, Uint8List assetBytes) {
  if (cachePath != null) {
    try {
      final f = File(cachePath);
      if (f.existsSync()) {
        final decoded = _decodeJsonBytes(f.readAsBytesSync());
        if (decoded is Map<String, dynamic> &&
            CatalogUpdater.looksLikeCatalog(decoded)) {
          return decoded;
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
