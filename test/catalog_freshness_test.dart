import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/services/catalog_loader.dart';

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  group('generatedAtFromCatalogBytes', () {
    test('extracts the timestamp from the head of a catalog', () {
      final b = _bytes(
          '{"source":"carateen","generated_at":1783862377,"tvshows":[]}');
      expect(generatedAtFromCatalogBytes(b), 1783862377);
    });
    test('returns null when absent (arabicToons/stardima schema)', () {
      expect(generatedAtFromCatalogBytes(_bytes('{"shows":[],"movies":[]}')),
          isNull);
    });
  });

  group('preferAssetOverCache', () {
    test('prefers the bundled asset when it is strictly newer', () {
      // Stale OTA cache (older) must NOT shadow a fresh APK's bundled catalog.
      expect(preferAssetOverCache(100, 200), isTrue);
    });
    test('keeps the cache when it is newer or equal (OTA still works)', () {
      expect(preferAssetOverCache(200, 100), isFalse);
      expect(preferAssetOverCache(100, 100), isFalse);
    });
    test('keeps cache-first when either side lacks a timestamp', () {
      expect(preferAssetOverCache(null, 200), isFalse);
      expect(preferAssetOverCache(100, null), isFalse);
      expect(preferAssetOverCache(null, null), isFalse);
    });
  });
}
