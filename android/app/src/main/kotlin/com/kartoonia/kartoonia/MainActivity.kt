package com.kartoonia.kartoonia

import android.Manifest
import android.app.UiModeManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.net.Uri
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
    private val voice by lazy { VoiceRecognizer(this) { emitVoice(it) } }
    // Locale to resume with once the RECORD_AUDIO prompt is answered, and whether
    // a start (not just a prepare) was waiting on that grant.
    private var pendingLocale: String? = null
    private var pendingStart = false

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
                    "isAvailable" -> result.success(voice.isAvailable())
                    // Warm the recognizer + request the mic permission ahead of the
                    // first tap, so listening starts instantly and is never blocked.
                    "prepare" -> {
                        if (!hasAudioPermission()) requestAudio()
                        voice.prepare()
                        result.success(true)
                    }
                    "start" -> {
                        pendingLocale = call.argument<String>("localeId")
                        if (hasAudioPermission()) {
                            voice.start(pendingLocale)
                        } else {
                            pendingStart = true
                            requestAudio()
                        }
                        result.success(true)
                    }
                    "stop" -> {
                        voice.stop()
                        result.success(true)
                    }
                    "cancel" -> {
                        voice.cancel()
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

    // ---- voice recognition (delegated to [VoiceRecognizer]) ----

    private fun hasAudioPermission(): Boolean =
        // minSdk is 30, so the Activity permission APIs (API 23+) are always
        // present — no androidx.core shim needed.
        checkSelfPermission(Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED

    private fun requestAudio() =
        requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), audioPermCode)

    /// RecognitionListener callbacks fire on the main thread, so the sink can be
    /// used directly.
    private fun emitVoice(event: Map<String, Any?>) {
        voiceEvents?.success(event)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        if (requestCode == audioPermCode) {
            val granted = grantResults.isNotEmpty() &&
                grantResults[0] == PackageManager.PERMISSION_GRANTED
            if (granted) {
                voice.prepare()
                if (pendingStart) voice.start(pendingLocale)
            } else if (pendingStart) {
                // 9 → Dart maps this to the muted mic-off state.
                emitVoice(mapOf("type" to "error", "code" to 9))
            }
            pendingStart = false
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onDestroy() {
        voice.destroy()
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
