import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Picks the best speech-recognition locale id for the given keyboard script.
///
/// Pure and testable: given the recognizer's [available] locale ids and the
/// device [systemLocaleId], it prefers an available locale whose language
/// matches the requested script ('ar' or 'en'). Crucially, it NEVER falls back
/// to a locale in a different language than the one the user asked for — when
/// the user picks Arabic, the result is always an Arabic locale (the system
/// locale only counts if it too is Arabic), otherwise the hardcoded `ar-SA`.
/// A recognizer with the Arabic language pack installed honors `ar-SA` even
/// when it didn't advertise an `ar` locale, so this keeps voice search in the
/// chosen language instead of silently reverting to the device's English.
/// Locale ids may use either `_` or `-` as separator.
String pickSpeechLocaleId(
  String kbScript, {
  required List<String> available,
  required String systemLocaleId,
}) {
  final prefix = kbScript == 'ar' ? 'ar' : 'en';

  String langOf(String id) =>
      id.toLowerCase().replaceAll('-', '_').split('_').first;

  // 1. A recognizer locale advertised in the requested language.
  for (final id in available) {
    if (langOf(id) == prefix) return id;
  }
  // 2. The system locale, but ONLY when it is the requested language — never
  //    switch to (e.g.) English just because that's the device default.
  if (systemLocaleId.isNotEmpty && langOf(systemLocaleId) == prefix) {
    return systemLocaleId;
  }
  // 3. A sensible hardcoded default for the requested language.
  return prefix == 'ar' ? 'ar-SA' : 'en-US';
}

/// Thin wrapper around [SpeechToText] for the search screen. Owns one-time
/// initialization (which also triggers the microphone permission prompt),
/// locale selection, and start/stop of a listening session.
class VoiceSearchService {
  final SpeechToText _speech = SpeechToText();
  bool _initialized = false;
  bool _available = false;
  List<String> _localeIds = const [];
  String _systemLocaleId = '';

  /// End-of-session callback for the active listening session, if any.
  VoidCallback? _onDone;

  bool get isListening => _speech.isListening;

  /// Initializes the recognizer once. Returns whether speech is available
  /// (the device has a recognizer and the mic permission was granted).
  Future<bool> ensureInitialized() async {
    if (_initialized) return _available;
    try {
      _available = await _speech.initialize(
        onError: (e) => debugPrint('VoiceSearch error: ${e.errorMsg}'),
        onStatus: (s) {
          debugPrint('VoiceSearch status: $s');
          // Surface end-of-session even when stopped without a final result.
          if (s == SpeechToText.doneStatus ||
              s == SpeechToText.notListeningStatus) {
            final cb = _onDone;
            _onDone = null;
            cb?.call();
          }
        },
      );
      if (_available) {
        final locales = await _speech.locales();
        _localeIds = locales.map((l) => l.localeId).toList();
        final sys = await _speech.systemLocale();
        _systemLocaleId = sys?.localeId ?? '';
      }
    } catch (e) {
      debugPrint('VoiceSearch init failed: $e');
      _available = false;
    }
    _initialized = true;
    return _available;
  }

  /// Starts a listening session for the language implied by [kbScript].
  ///
  /// [onText] is called with partial transcripts as the user speaks and once
  /// more with the final transcript. [onDone] fires when the session ends
  /// (final result, timeout, or stop).
  Future<bool> start({
    required String kbScript,
    required void Function(String text, bool isFinal) onText,
    required VoidCallback onDone,
  }) async {
    final ok = await ensureInitialized();
    if (!ok) return false;

    final localeId = pickSpeechLocaleId(
      kbScript,
      available: _localeIds,
      systemLocaleId: _systemLocaleId,
    );

    _onDone = onDone;
    await _speech.listen(
      onResult: (r) => onText(r.recognizedWords, r.finalResult),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.search,
        localeId: localeId,
        listenFor: const Duration(seconds: 20),
        pauseFor: const Duration(seconds: 4),
      ),
    );
    return true;
  }

  Future<void> stop() async {
    if (_speech.isListening) await _speech.stop();
  }
}
