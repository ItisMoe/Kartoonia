package com.kartoonia.kartoonia

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "kartoonia/reco"
    private val voiceChannelName = "kartoonia/voice"
    private val voiceRequestCode = 0x5643 // 'VC'
    private var methodChannel: MethodChannel? = null
    private var pendingDeepLink: String? = null
    // The Flutter call awaiting the system voice dialog's result, if any.
    private var pendingVoiceResult: MethodChannel.Result? = null

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
                else -> result.notImplemented()
            }
        }

        // Voice search via the system speech dialog (RecognizerIntent). This is
        // the reliable path on Android TV / Google TV: it uses the remote's
        // microphone (the Chromecast dongle has no built-in mic and the
        // continuous SpeechRecognizer API gets no audio there) and returns one
        // final transcript.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, voiceChannelName)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAvailable" -> result.success(voiceRecognitionAvailable())
                    "recognize" -> startVoiceRecognition(
                        call.argument<String>("localeId"),
                        call.argument<String>("prompt"),
                        result
                    )
                    else -> result.notImplemented()
                }
            }

        // capture the deep link the app may have been launched with
        pendingDeepLink = linkFrom(intent)
    }

    private fun voiceRecognitionAvailable(): Boolean {
        return try {
            if (SpeechRecognizer.isRecognitionAvailable(this)) return true
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
            intent.resolveActivity(packageManager) != null
        } catch (e: Throwable) {
            false
        }
    }

    private fun startVoiceRecognition(
        localeId: String?,
        prompt: String?,
        result: MethodChannel.Result
    ) {
        // Only one dialog at a time; resolve a second request as "no input".
        if (pendingVoiceResult != null) {
            result.success(null)
            return
        }
        try {
            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(
                    RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                    RecognizerIntent.LANGUAGE_MODEL_FREE_FORM
                )
                putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
                if (!localeId.isNullOrEmpty()) {
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE, localeId)
                    putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, localeId)
                }
                if (!prompt.isNullOrEmpty()) {
                    putExtra(RecognizerIntent.EXTRA_PROMPT, prompt)
                }
            }
            if (intent.resolveActivity(packageManager) == null) {
                result.success(null)
                return
            }
            pendingVoiceResult = result
            startActivityForResult(intent, voiceRequestCode)
        } catch (e: Throwable) {
            pendingVoiceResult = null
            result.success(null)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == voiceRequestCode) {
            val cb = pendingVoiceResult
            pendingVoiceResult = null
            val text = if (resultCode == Activity.RESULT_OK && data != null) {
                data.getStringArrayListExtra(RecognizerIntent.EXTRA_RESULTS)
                    ?.firstOrNull { it.isNotBlank() }
            } else {
                null
            }
            cb?.success(text)
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
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
