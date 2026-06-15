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
