package com.kartoonia.kartoonia

import android.Manifest
import android.app.UiModeManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.net.Uri
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "kartoonia/reco"
    private val voiceChannelName = "kartoonia/voice"
    private val voiceEventsName = "kartoonia/voice_events"
    private val audioPermCode = 0x5641 // 'VA'
    private var methodChannel: MethodChannel? = null
    private var pendingDeepLink: String? = null

    // ---- voice search (in-app SpeechRecognizer, YouTube-style) ----
    private var voiceEvents: EventChannel.EventSink? = null
    private var speech: SpeechRecognizer? = null
    // Locale to resume with once the RECORD_AUDIO prompt is answered.
    private var pendingLocale: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger, channelName
        )
        methodChannel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "publish" -> {
                    try {
                        @Suppress("UNCHECKED_CAST")
                        val items = (call.argument<List<Map<String, String>>>("items"))
                            ?: emptyList()
                        Recommendations.publish(this, items)
                        result.success(true)
                    } catch (e: Throwable) {
                        result.success(false)
                    }
                }
                "getInitialDeepLink" -> {
                    result.success(pendingDeepLink)
                    pendingDeepLink = null
                }
                // Whether this device is an Android TV / Google TV (leanback) box,
                // as opposed to a touch phone/tablet. Drives the UI fork in main():
                // TVs get the D-pad 1920×1080 canvas, phones get the portrait UI.
                "isTelevision" -> result.success(isTelevision())
                else -> result.notImplemented()
            }
        }

        // Voice search bridged as an in-app SpeechRecognizer session. The app
        // owns the microphone and renders its own listening overlay (from the
        // events on voiceEventsName) instead of launching the system speech
        // dialog — that dialog is a different component on every device, which is
        // why the old approach worked on some TVs and not others. This path is
        // consistent everywhere, the same way the YouTube TV app does it.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, voiceChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAvailable" ->
                        result.success(SpeechRecognizer.isRecognitionAvailable(this))
                    "start" -> {
                        startVoice(call.argument<String>("localeId"))
                        result.success(true)
                    }
                    "stop" -> {
                        speech?.stopListening()
                        result.success(true)
                    }
                    "cancel" -> {
                        destroySpeech()
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, voiceEventsName)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    voiceEvents = sink
                }

                override fun onCancel(args: Any?) {
                    voiceEvents = null
                }
            })

        // capture the deep link the app may have been launched with
        pendingDeepLink = linkFrom(intent)
    }

    /// True on leanback devices (Android TV / Google TV). Falls back to false
    /// (touch UI) if the system service is somehow unavailable.
    private fun isTelevision(): Boolean {
        return try {
            val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
            uiModeManager.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION
        } catch (e: Throwable) {
            false
        }
    }

    // ---- voice recognition ----

    /// Begin a session, requesting RECORD_AUDIO first if it isn't granted yet.
    /// Results/errors are streamed back over [voiceEvents]; nothing is returned
    /// synchronously beyond acknowledging the call.
    private fun startVoice(localeId: String?) {
        pendingLocale = localeId
        // minSdk is 30, so the Activity permission APIs (API 23+) are always
        // present — no androidx.core shim needed.
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO)
            == PackageManager.PERMISSION_GRANTED
        ) {
            beginListening(localeId)
        } else {
            requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), audioPermCode)
        }
    }

    private fun beginListening(localeId: String?) {
        if (!SpeechRecognizer.isRecognitionAvailable(this)) {
            // 9 = ERROR_INSUFFICIENT_PERMISSIONS; reused here as "no recognizer",
            // which the Dart side maps to the unavailable (muted) state.
            emit(mapOf("type" to "error", "code" to 9))
            return
        }
        destroySpeech()
        val recognizer = SpeechRecognizer.createSpeechRecognizer(this)
        recognizer.setRecognitionListener(voiceListener)
        val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
            )
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            // Some recognizers refuse to start without the calling package.
            putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, packageName)
            if (!localeId.isNullOrEmpty()) {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, localeId)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, localeId)
            }
        }
        speech = recognizer
        recognizer.startListening(intent)
    }

    private val voiceListener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) =
            emit(mapOf("type" to "status", "value" to "ready"))

        override fun onBeginningOfSpeech() =
            emit(mapOf("type" to "status", "value" to "speech"))

        override fun onRmsChanged(rmsdB: Float) {
            // rmsdB is roughly -2..10 dB; normalize to 0..1 for the mic rings.
            val level = ((rmsdB + 2f) / 12f).coerceIn(0f, 1f)
            emit(mapOf("type" to "rms", "level" to level.toDouble()))
        }

        override fun onBufferReceived(buffer: ByteArray?) {}

        override fun onEndOfSpeech() =
            emit(mapOf("type" to "status", "value" to "end"))

        override fun onError(error: Int) {
            emit(mapOf("type" to "error", "code" to error))
            destroySpeech()
        }

        override fun onResults(results: Bundle?) {
            val text = results
                ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                ?.firstOrNull { it.isNotBlank() }
            emit(mapOf("type" to "final", "text" to (text ?: "")))
            destroySpeech()
        }

        override fun onPartialResults(partialResults: Bundle?) {
            val text = partialResults
                ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                ?.firstOrNull { it.isNotBlank() }
            if (!text.isNullOrBlank()) {
                emit(mapOf("type" to "partial", "text" to text))
            }
        }

        override fun onEvent(eventType: Int, params: Bundle?) {}
    }

    private fun emit(event: Map<String, Any?>) {
        // RecognitionListener callbacks fire on the main thread, so the sink can
        // be used directly.
        voiceEvents?.success(event)
    }

    private fun destroySpeech() {
        speech?.let {
            try {
                it.cancel()
                it.destroy()
            } catch (_: Throwable) {
            }
        }
        speech = null
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        if (requestCode == audioPermCode) {
            if (grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            ) {
                beginListening(pendingLocale)
            } else {
                emit(mapOf("type" to "error", "code" to 9))
            }
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onDestroy() {
        destroySpeech()
        super.onDestroy()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val link = linkFrom(intent)
        if (link != null) {
            methodChannel?.invokeMethod("deepLink", link)
        }
    }

    private fun linkFrom(intent: Intent?): String? {
        val data: Uri? = intent?.data
        return if (data != null && data.scheme == "kartoonia") data.toString() else null
    }
}
