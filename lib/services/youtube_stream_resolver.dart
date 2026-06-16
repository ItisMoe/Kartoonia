import 'package:youtube_explode_dart/youtube_explode_dart.dart';

/// A muxed (single-file video+audio) stream candidate, reduced to just the
/// fields the selection logic needs. Keeps [pickMuxedUrl] testable without the
/// network or constructing library types.
class MuxedOption {
  final int height;
  final String url;
  const MuxedOption({required this.height, required this.url});
}

/// Picks the best muxed stream URL for trailer playback:
/// the highest resolution at or below 720p; if every stream is above 720p,
/// the lowest available; null when there are no muxed streams.
///
/// In practice YouTube caps muxed (progressive) streams at 360p — the same
/// "best single file" the Python `yt-dlp` prototype played with format `b`.
/// The <=720p ceiling simply future-proofs the choice without ever picking an
/// oversized stream.
String? pickMuxedUrl(List<MuxedOption> options) {
  if (options.isEmpty) return null;
  final atOrBelow = options.where((o) => o.height <= 720).toList();
  if (atOrBelow.isNotEmpty) {
    atOrBelow.sort((a, b) => b.height.compareTo(a.height));
    return atOrBelow.first.url;
  }
  final all = [...options]..sort((a, b) => a.height.compareTo(b.height));
  return all.first.url;
}

/// Network-free view of one video-only stream, for [selectVideoOptions].
class VideoStreamCandidate {
  final int height;
  final String url;
  final bool isMp4; // mp4/H.264 preferred for Android-TV hardware decode
  const VideoStreamCandidate(
      {required this.height, required this.url, required this.isMp4});
}

/// Network-free view of one audio-only stream, for [pickBestAudioUrl].
class AudioStreamCandidate {
  final int bitrate;
  final String url;
  final bool isMp4; // m4a/AAC preferred on a tie
  const AudioStreamCandidate(
      {required this.bitrate, required this.url, required this.isMp4});
}

/// A playable video option for the trailer picker. [muxed] true means the URL
/// already carries audio (no external audio track should be attached).
class YtVideoOption {
  final int height;
  final String url;
  final bool muxed;
  const YtVideoOption(
      {required this.height, required this.url, this.muxed = false});
}

/// Everything the trailer player needs: video options (paired with [audioUrl])
/// plus a muxed URL for the failure path.
class YoutubePlayback {
  final List<YtVideoOption> videos; // mp4-preferred, deduped, <=cap, high->low
  final String? audioUrl;
  final String? muxedFallbackUrl;
  const YoutubePlayback(
      {required this.videos,
      required this.audioUrl,
      required this.muxedFallbackUrl});
}

/// Best audio-only URL: highest bitrate; on a tie prefer mp4/m4a. Null if empty.
String? pickBestAudioUrl(List<AudioStreamCandidate> options) {
  if (options.isEmpty) return null;
  final sorted = [...options]..sort((a, b) {
      final byBitrate = b.bitrate.compareTo(a.bitrate);
      if (byBitrate != 0) return byBitrate;
      if (a.isMp4 == b.isMp4) return 0;
      return a.isMp4 ? -1 : 1; // mp4 first on tie
    });
  return sorted.first.url;
}

/// Video-only options at or below [maxHeight], one per distinct height (mp4
/// preferred when a height offers both), sorted high -> low.
List<YtVideoOption> selectVideoOptions(List<VideoStreamCandidate> options,
    {int maxHeight = 720}) {
  final byHeight = <int, VideoStreamCandidate>{};
  for (final o in options) {
    if (o.height <= 0 || o.height > maxHeight) continue;
    final existing = byHeight[o.height];
    if (existing == null || (!existing.isMp4 && o.isMp4)) {
      byHeight[o.height] = o;
    }
  }
  final heights = byHeight.keys.toList()..sort((a, b) => b.compareTo(a));
  return [
    for (final h in heights)
      YtVideoOption(height: h, url: byHeight[h]!.url, muxed: false),
  ];
}

/// Turns a YouTube videoId into a directly-playable muxed stream URL, the way
/// `yt-dlp` does in the Python prototype. Isolates `youtube_explode_dart` so the
/// rest of the app only ever deals with a plain URL string.
class YoutubeStreamResolver {
  /// Returns a playable muxed URL for [videoId], or null if none is available
  /// (no muxed streams, geo-block, or a YouTube cipher change the package
  /// hasn't caught up to yet). Throws on transport errors (caller handles).
  static Future<String?> resolve(String videoId) async {
    final yt = YoutubeExplode();
    try {
      final manifest = await yt.videos.streamsClient.getManifest(videoId);
      final options = manifest.muxed
          .map((s) => MuxedOption(
                height: s.videoResolution.height,
                url: s.url.toString(),
              ))
          .toList();
      return pickMuxedUrl(options);
    } finally {
      yt.close();
    }
  }
}
