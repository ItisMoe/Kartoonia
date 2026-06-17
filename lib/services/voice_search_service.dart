import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Maps the active keyboard script to a BCP-47 locale tag for the system
/// speech recognizer. 'ar' → Arabic (Saudi), anything else → US English.
String voiceLocaleFor(String kbScript) => kbScript == 'ar' ? 'ar-SA' : 'en-US';

/// Voice search backed by the platform's system speech dialog (Android's
/// `RecognizerIntent`), bridged through the `kartoonia/voice` method channel.
///
/// On Android TV / Google TV this is the only reliable path. The continuous
/// `SpeechRecognizer` API the old `speech_to_text` plugin used gets no audio on
/// a Chromecast dongle — it has no built-in microphone, and the remote's mic is
/// reserved for the system Assistant — so it would report "listening" forever
/// without ever capturing a word. The system dialog instead uses the remote's
/// mic and returns a single final transcript, which also removes the
/// partial-result re-search lag the old approach caused.
class VoiceSearchService {
  static const _channel = MethodChannel('kartoonia/voice');

  /// Whether the device exposes a usable speech-recognition path.
  Future<bool> isAvailable() async {
    try {
      return await _channel.invokeMethod<bool>('isAvailable') ?? false;
    } on PlatformException catch (e) {
      debugPrint('VoiceSearch isAvailable failed: $e');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Launches the system voice dialog for [kbScript] and resolves with the
  /// recognized text, or null when the user cancelled, nothing was heard, or
  /// recognition is unavailable. [prompt] is shown in the system UI.
  Future<String?> recognize({required String kbScript, String? prompt}) async {
    try {
      final text = await _channel.invokeMethod<String>('recognize', {
        'localeId': voiceLocaleFor(kbScript),
        'prompt': prompt,
      });
      final trimmed = text?.trim();
      return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    } on PlatformException catch (e) {
      debugPrint('VoiceSearch recognize failed: $e');
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
