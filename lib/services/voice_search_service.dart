import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart';

/// Picks the best speech-recognition locale id for the given keyboard script.
///
/// Pure and testable: given the recognizer's [available] locale ids and the
/// device [systemLocaleId], it prefers an available locale whose language
/// matches the script ('ar' or 'en'), then the system locale, then a sensible
/// hardcoded default. Locale ids may use either `_` or `-` as separator.
String pickSpeechLocaleId(
  String kbScript, {
  required List<String> available,
  required String systemLocaleId,
}) {
  final prefix = kbScript == 'ar' ? 'ar' : 'en';

  bool matchesScript(String id) {
    final lang = id.toLowerCase().replaceAll('-', '_').split('_').first;
    return lang == prefix;
  }

  for (final id in available) {
    if (matchesScript(id)) return id;
  }
  if (systemLocaleId.isNotEmpty) return systemLocaleId;
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
