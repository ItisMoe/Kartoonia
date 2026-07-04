package com.kartoonia.kartoonia

import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import androidx.tvprovider.media.tv.PreviewChannel
import androidx.tvprovider.media.tv.PreviewChannelHelper
import androidx.tvprovider.media.tv.PreviewProgram
import androidx.tvprovider.media.tv.TvContractCompat
import androidx.tvprovider.media.tv.WatchNextProgram

/**
 * Publishes a Kartoonia "recommended" preview channel + programs on the
 * Google TV / Android TV home screen (the Netflix/Crunchyroll-style row), and
 * keeps the launcher's WATCH NEXT row in sync with in-progress episodes.
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

            // The stored id can go stale (launcher data cleared, channel removed
            // by the user). Verify it still exists before trusting it.
            if (channelId != -1L) {
                val exists = try { helper.getPreviewChannel(channelId) != null }
                    catch (_: Throwable) { false }
                if (!exists) channelId = -1L
            }
            // A channel may survive from a previous install while our prefs were
            // wiped — reuse it instead of creating a duplicate row.
            if (channelId == -1L) {
                channelId = try {
                    helper.allChannels.firstOrNull()?.id ?: -1L
                } catch (_: Throwable) { -1L }
                if (channelId != -1L) prefs.edit().putLong(KEY_CHANNEL, channelId).apply()
            }

            if (channelId == -1L) {
                // The logo is MANDATORY: PreviewChannelHelper.publishChannel
                // deletes the channel and throws IOException when no logo can be
                // stored. Publishing without one is why the channel historically
                // never appeared on any launcher.
                val logo = BitmapFactory.decodeResource(
                    context.resources, R.drawable.tv_channel_logo
                )
                val channel = PreviewChannel.Builder()
                    .setDisplayName("Kartoonia")
                    .setAppLinkIntentUri(Uri.parse("kartoonia://home"))
                    .setLogo(logo)
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

    // ---- Watch Next (the launcher's "Continue Watching" row) ----
    // Works on BOTH launcher generations: classic Android TV and Google TV
    // (which hides third-party preview channels but always shows Watch Next).
    // One program per catalog item, keyed "wn/<itemId>" -> programId in prefs.

    fun upsertWatchNext(context: Context, args: Map<String, Any?>) {
        try {
            val id = args["id"] as? String ?: return
            val title = args["title"] as? String ?: return
            val poster = args["poster"] as? String ?: return
            if (poster.isBlank()) return
            val positionMs = (args["positionMs"] as? Number)?.toInt() ?: 0
            val durationMs = (args["durationMs"] as? Number)?.toInt() ?: 0
            val isMovie = args["isMovie"] as? Boolean ?: false
            // true = "up next" (episode finished, next one queued);
            // false = plain continue-watching with a progress bar.
            val isNext = args["next"] as? Boolean ?: false

            val builder = WatchNextProgram.Builder()
                .setType(
                    if (isMovie) TvContractCompat.WatchNextPrograms.TYPE_MOVIE
                    else TvContractCompat.WatchNextPrograms.TYPE_TV_SERIES
                )
                .setWatchNextType(
                    if (isNext) TvContractCompat.WatchNextPrograms.WATCH_NEXT_TYPE_NEXT
                    else TvContractCompat.WatchNextPrograms.WATCH_NEXT_TYPE_CONTINUE
                )
                .setLastEngagementTimeUtcMillis(System.currentTimeMillis())
                .setTitle(title)
                .setPosterArtUri(Uri.parse(poster))
                .setPosterArtAspectRatio(
                    TvContractCompat.PreviewPrograms.ASPECT_RATIO_2_3
                )
                .setIntentUri(Uri.parse("kartoonia://item/$id"))
                .setInternalProviderId(id)
            if (durationMs > 0) {
                builder.setLastPlaybackPositionMillis(positionMs)
                builder.setDurationMillis(durationMs)
            }

            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val key = "wn/$id"
            val helper = PreviewChannelHelper(context)
            val existing = prefs.getLong(key, -1L)
            if (existing != -1L) {
                // The user may have dismissed the card from the launcher, which
                // deletes the row — fall through to a fresh insert then.
                try {
                    helper.updateWatchNextProgram(builder.build(), existing)
                    return
                } catch (_: Throwable) {
                }
            }
            val pid = helper.publishWatchNextProgram(builder.build())
            prefs.edit().putLong(key, pid).apply()
        } catch (_: Throwable) {
            // No TV provider on this device (phone) or launcher quirk — ignore.
        }
    }

    fun removeWatchNext(context: Context, id: String) {
        try {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val key = "wn/$id"
            val pid = prefs.getLong(key, -1L)
            if (pid == -1L) return
            context.contentResolver.delete(
                TvContractCompat.buildWatchNextProgramUri(pid), null, null
            )
            prefs.edit().remove(key).apply()
        } catch (_: Throwable) {
        }
    }
}
