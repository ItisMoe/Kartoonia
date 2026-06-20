import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Maps the active keyboard script to a BCP-47 locale tag for the system
/// speech recognizer. 'ar' → Arabic (Saudi), anything else → US English.
String voiceLocaleFor(String kbScript) => kbScript == 'ar' ? 'ar-SA' : 'en-US';

/// In-app voice search backed by Android's `SpeechRecognizer` service — the same
/// approach the YouTube TV app uses, and the reason it behaves identically on
/// every TV. We DO NOT launch the system `RecognizerIntent` dialog: that dialog
/// is provided by a different component on each device (a Google voice panel on
/// some, an on-screen keyboard on others, nothing at all on a few), which is
/// exactly why the old implementation "worked on some TVs and not others".
///
/// Instead the app owns the whole session: it binds the device's recognition
/// service, drives the remote/built-in microphone itself, and renders its own
/// listening overlay from the streamed events below. One consistent experience
/// everywhere.
///
/// Events are delivered on the [events] broadcast stream as maps:
///   {type: 'status', value: 'ready'|'speech'|'end'}
///   {type: 'rms',    level: double 0..1}   // mic loudness, for the animation
///   {type: 'partial', text: String}        // live (non-final) transcript
///   {type: 'final',   text: String}        // the committed transcript
///   {type: 'error',   code: int}           // recognizer error (see Android docs)
class VoiceSearchService {
  static const _method = MethodChannel('kartoonia/voice');
  static const _events = EventChannel('kartoonia/voice_events');

  /// Whether the device exposes a usable on-device recognition service.
  Future<bool> isAvailable() async {
    try {
      return await _method.invokeMethod<bool>('isAvailable') ?? false;
    } on PlatformException catch (e) {
      debugPrint('VoiceSearch isAvailable failed: $e');
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// Warm the native recognizer (create it + bind the RecognitionService, and
  /// request the mic permission) ahead of the first [start], so listening begins
  /// instantly instead of paying the cold-bind latency on tap. Best-effort.
  Future<void> prepare() async {
    try {
      await _method.invokeMethod('prepare');
    } on PlatformException catch (e) {
      debugPrint('VoiceSearch prepare failed: $e');
    } on MissingPluginException {
      // older host without the prepare method — start() still works.
    }
  }

  /// The single broadcast stream of recognition events for the active session.
  Stream<dynamic> events() => _events.receiveBroadcastStream();

  /// Begin a listening session in [localeId]. Events flow on [events]; finish by
  /// waiting for a `final`/`error` event, or call [stop]/[cancel].
  Future<void> start(String localeId) async {
    await _method.invokeMethod('start', {'localeId': localeId});
  }

  /// Stop capturing and let the recognizer finalize what it already heard (a
  /// `final` event follows). Mirrors releasing the mic button.
  Future<void> stop() async {
    try {
      await _method.invokeMethod('stop');
    } on PlatformException catch (e) {
      debugPrint('VoiceSearch stop failed: $e');
    }
  }

  /// Abort the session immediately with no result (user dismissed the overlay).
  Future<void> cancel() async {
    try {
      await _method.invokeMethod('cancel');
    } on PlatformException catch (e) {
      debugPrint('VoiceSearch cancel failed: $e');
    }
  }
}
