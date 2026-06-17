import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/services/voice_search_service.dart';

void main() {
  group('voiceLocaleFor', () {
    test('maps "ar" to Arabic (Saudi)', () {
      expect(voiceLocaleFor('ar'), 'ar-SA');
    });

    test('maps "en" to US English', () {
      expect(voiceLocaleFor('en'), 'en-US');
    });

    test('defaults anything non-Arabic to US English', () {
      expect(voiceLocaleFor(''), 'en-US');
      expect(voiceLocaleFor('fr'), 'en-US');
    });
  });
}
