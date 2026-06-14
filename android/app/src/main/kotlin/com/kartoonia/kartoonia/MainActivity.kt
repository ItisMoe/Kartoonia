package com.kartoonia.kartoonia

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "kartoonia/reco"
    private var methodChannel: MethodChannel? = null
    private var pendingDeepLink: String? = null

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
        // capture the deep link the app may have been launched with
        pendingDeepLink = linkFrom(intent)
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
