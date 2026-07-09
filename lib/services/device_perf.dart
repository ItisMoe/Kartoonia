/// Device performance class, detected once in main() (total RAM via the
/// `kartoonia/reco` channel) and read wherever behavior scales down on weak
/// hardware: HLS quality cap (PlayerService), hero autoplay cadence
/// (HeroCarousel), image-cache sizing (main).
///
/// A plain static — not a provider — so non-widget code (PlayerService) can
/// read it without plumbing a Ref. Defaults to false (full quality) in tests
/// and whenever detection fails.
class DevicePerf {
  DevicePerf._();

  /// True on boxes with < ~1.6 GB RAM (the cheap TV-stick class).
  static bool lowSpec = false;
}
