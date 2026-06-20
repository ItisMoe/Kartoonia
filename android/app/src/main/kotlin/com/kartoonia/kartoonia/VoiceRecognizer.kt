package com.kartoonia.kartoonia

import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer

/// Thin lifecycle wrapper around the native [SpeechRecognizer] that streams its
/// callbacks out as plain maps (consumed by the Flutter overlay).
///
/// Two behaviours fix the real-TV issues:
///  - **Pre-warm:** [prepare] creates the recognizer (and binds the device's
///    RecognitionService) ahead of time, so the first [start] has no cold-bind
///    latency — that was the "delay before it starts listening".
///  - **Prefer online:** the intent sets `EXTRA_PREFER_OFFLINE = false`. TV boxes
///    frequently ship without an on-device Arabic model, so the offline path
///    returned nothing — that was the "I speak but no result is written".
///
/// All methods must be called on the main thread (Flutter channel handlers and
/// the RecognitionListener callbacks already are).
class VoiceRecognizer(
    private val context: Context,
    private val emit: (Map<String, Any?>) -> Unit,
) {
    private var recognizer: SpeechRecognizer? = null
    private var listening = false

    fun isAvailable(): Boolean = SpeechRecognizer.isRecognitionAvailable(context)

    /// Create + bind the recognizer ahead of time so the first [start] is instant.
    /// Idempotent and cheap; no microphone is opened here.
    fun prepare() {
        if (recognizer != null || !isAvailable()) return
        recognizer = SpeechRecognizer.createSpeechRecognizer(context).apply {
            setRecognitionListener(listener)
        }
    }

    fun start(localeId: String?) {
        if (!isAvailable()) {
            // 9 = ERROR_INSUFFICIENT_PERMISSIONS, reused as "no recognizer".
            emit(mapOf("type" to "error", "code" to 9))
            return
        }
        prepare()
        val r = recognizer ?: return
        if (listening) r.cancel()
        listening = true
        r.startListening(buildIntent(localeId))
    }

    fun stop() {
        recognizer?.stopListening()
    }

    fun cancel() {
        listening = false
        recognizer?.cancel()
    }

    fun destroy() {
        listening = false
        recognizer?.let {
            try {
                it.cancel()
                it.destroy()
            } catch (_: Throwable) {
            }
        }
        recognizer = null
    }

    private fun buildIntent(localeId: String?): Intent =
        Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
            putExtra(
                RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
            )
            putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
            putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
            // Some recognizers refuse to start without the calling package.
            putExtra(RecognizerIntent.EXTRA_CALLING_PACKAGE, context.packageName)
            // Prefer the online (Google) recognizer — the on-device model on TV
            // boxes commonly lacks Arabic, which yields empty results offline.
            putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, false)
            if (!localeId.isNullOrEmpty()) {
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, localeId)
                putExtra(RecognizerIntent.EXTRA_LANGUAGE_PREFERENCE, localeId)
                putStringArrayListExtra(
                    RecognizerIntent.EXTRA_SUPPORTED_LANGUAGES,
                    arrayListOf(localeId, "en-US"),
                )
            }
        }

    private val listener = object : RecognitionListener {
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
            listening = false
            // Keep the recognizer instance alive so a retry is instant.
            emit(mapOf("type" to "error", "code" to error))
        }

        override fun onResults(results: Bundle?) {
            listening = false
            val text = results
                ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                ?.firstOrNull { it.isNotBlank() }
            emit(mapOf("type" to "final", "text" to (text ?: "")))
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
}
