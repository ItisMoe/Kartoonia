import 'package:media_kit/media_kit.dart';

/// One entry in the player's quality picker. [height] is the video height in
/// pixels (e.g. 720), or null for the adaptive "Auto" option. [label] is the
/// display string — the resolution rows are "<height>p"; the Auto row uses the
/// localized label passed into [buildQualityOptions].
class QualityOption {
  final int? height;
  final String label;
  const QualityOption({required this.height, required this.label});
}

/// Collect the distinct, usable heights (h present and > 0) from [tracks].
Set<int> _distinctHeights(List<VideoTrack> tracks) {
  final heights = <int>{};
  for (final tr in tracks) {
    final h = tr.h;
    if (h != null && h > 0) heights.add(h);
  }
  return heights;
}

/// Build the picker: Auto first (height null, [autoLabel]), then one row per
/// distinct real height, sorted high -> low and labelled "<height>p". Tracks
/// without a usable height (null/zero — e.g. synthetic auto/no tracks) are
/// dropped, and equal heights are deduped.
List<QualityOption> buildQualityOptions(
  List<VideoTrack> tracks, {
  required String autoLabel,
}) {
  final sorted = _distinctHeights(tracks).toList()
    ..sort((a, b) => b.compareTo(a));
  return [
    QualityOption(height: null, label: autoLabel),
    for (final h in sorted) QualityOption(height: h, label: '${h}p'),
  ];
}

/// The [VideoTrack] whose height is closest to [height]; null when no track has
/// a usable height.
VideoTrack? nearestTrackForHeight(List<VideoTrack> tracks, int height) {
  VideoTrack? best;
  int? bestDelta;
  for (final tr in tracks) {
    final h = tr.h;
    if (h == null || h <= 0) continue;
    final delta = (h - height).abs();
    if (bestDelta == null || delta < bestDelta) {
      best = tr;
      bestDelta = delta;
    }
  }
  return best;
}

/// Whether there is a real choice to offer: at least two distinct heights.
/// Drives the Quality button's enabled state — single-quality streams (a lone
/// .mp4 or single-variant HLS) have nothing to pick.
bool hasSelectableQualities(List<VideoTrack> tracks) =>
    _distinctHeights(tracks).length >= 2;
