package com.kartoonia.kartoonia

import android.content.Context
import android.net.Uri
import androidx.tvprovider.media.tv.PreviewChannel
import androidx.tvprovider.media.tv.PreviewChannelHelper
import androidx.tvprovider.media.tv.PreviewProgram
import androidx.tvprovider.media.tv.TvContractCompat

/**
 * Publishes a Kartoonia "recommended" preview channel + programs on the
 * Google TV / Android TV home screen (the Netflix/Crunchyroll-style row).
 *
 * Each program deep-links back into the app via kartoonia://item/<id>.
 * Everything is wrapped in try/catch so a launcher that doesn't support preview
 * channels (or a denied permission) can never crash the app.
 */
object Recommendations {
    private const val PREFS = "kt_reco"
    private const val KEY_CHANNEL = "channelId"
    private const val KEY_PROGRAMS = "programIds"

    fun publish(context: Context, items: List<Map<String, String>>) {
        try {
            val helper = PreviewChannelHelper(context)
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            var channelId = prefs.getLong(KEY_CHANNEL, -1L)

            if (channelId == -1L) {
                val channel = PreviewChannel.Builder()
                    .setDisplayName("Kartoonia")
                    .setAppLinkIntentUri(Uri.parse("kartoonia://home"))
                    .build()
                channelId = helper.publishDefaultChannel(channel)
                prefs.edit().putLong(KEY_CHANNEL, channelId).apply()
                try {
                    TvContractCompat.requestChannelBrowsable(context, channelId)
                } catch (_: Throwable) {
                }
            }

            // remove previously-published programs (daily refresh)
            val old = prefs.getString(KEY_PROGRAMS, "") ?: ""
            for (token in old.split(",")) {
                val pid = token.toLongOrNull() ?: continue
                try {
                    helper.deletePreviewProgram(pid)
                } catch (_: Throwable) {
                }
            }

            val newIds = StringBuilder()
            for (item in items.take(20)) {
                val id = item["id"] ?: continue
                val title = item["title"] ?: continue
                val poster = item["poster"] ?: continue
                if (poster.isBlank()) continue
                try {
                    val program = PreviewProgram.Builder()
                        .setChannelId(channelId)
                        .setType(TvContractCompat.PreviewPrograms.TYPE_TV_SERIES)
                        .setTitle(title)
                        .setPosterArtUri(Uri.parse(poster))
                        .setPosterArtAspectRatio(
                            TvContractCompat.PreviewPrograms.ASPECT_RATIO_2_3
                        )
                        .setIntentUri(Uri.parse("kartoonia://item/$id"))
                        .setInternalProviderId(id)
                        .build()
                    val pid = helper.publishPreviewProgram(program)
                    if (newIds.isNotEmpty()) newIds.append(",")
                    newIds.append(pid)
                } catch (_: Throwable) {
                }
            }
            prefs.edit().putString(KEY_PROGRAMS, newIds.toString()).apply()
        } catch (_: Throwable) {
            // Launcher without preview-channel support, or permission denied —
            // ignore so playback/browse are unaffected.
        }
    }
}
