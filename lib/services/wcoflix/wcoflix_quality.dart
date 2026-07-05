/// WCOFlix stream qualities. `token` is the JSON key in the getvidlink response
/// (`enc`=576p, `hd`=720p, `fhd`=1080p); the getvid stream URL is built as
/// `server/getvid?evid=<token value>`. The HLS path matches on [resolution].
enum WcoQuality {
  p576(576, '576p', 'enc'),
  p720(720, '720p', 'hd'),
  p1080(1080, '1080p', 'fhd');

  const WcoQuality(this.resolution, this.tag, this.token);
  final int resolution;
  final String tag;
  final String token;

  /// 720p-default selection with graceful fallback (ports ZenDownloader
  /// `Quality.bestQuality`): prefer the wanted tier, else step toward it.
  static WcoQuality best(WcoQuality want, List<WcoQuality> have) {
    if (have.isEmpty) return p576;
    if (have.contains(want)) return want;
    switch (want) {
      case p1080:
        return have.contains(p720) ? p720 : p576;
      case p720:
        return have.contains(p1080) ? p1080 : p576;
      case p576:
        return have.contains(p720) ? p720 : p1080;
    }
  }
}
