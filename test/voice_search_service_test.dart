import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/services/voice_search_service.dart';

void main() {
  group('pickSpeechLocaleId', () {
    test('maps "ar" to an available Arabic locale (underscore form)', () {
      final id = pickSpeechLocaleId(
        'ar',
        available: const ['en_US', 'ar_SA', 'fr_FR'],
        systemLocaleId: 'en_US',
      );
      expect(id, 'ar_SA');
    });

    test('maps "en" to an available English locale (dash form)', () {
      final id = pickSpeechLocaleId(
        'en',
        available: const ['ar-SA', 'en-GB', 'en-US'],
        systemLocaleId: 'ar-SA',
      );
      expect(id, 'en-GB');
    });

    test('matches the script regardless of region casing', () {
      final id = pickSpeechLocaleId(
        'ar',
        available: const ['AR_EG'],
        systemLocaleId: 'en_US',
      );
      expect(id, 'AR_EG');
    });

    test('falls back to system locale when script is unavailable', () {
      final id = pickSpeechLocaleId(
        'ar',
        available: const ['en_US', 'fr_FR'],
        systemLocaleId: 'en_US',
      );
      expect(id, 'en_US');
    });

    test('falls back to a sensible default when nothing matches', () {
      final id = pickSpeechLocaleId(
        'ar',
        available: const [],
        systemLocaleId: '',
      );
      expect(id, 'ar-SA');
    });

    test('English default fallback', () {
      final id = pickSpeechLocaleId(
        'en',
        available: const [],
        systemLocaleId: '',
      );
      expect(id, 'en-US');
    });
  });
}
