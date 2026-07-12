/// A single carateen.tv `/music` theme song (a nostalgia-album track). The mp3
/// + cover are served straight from carateen.tv; playback is a plain audio open
/// (no resolve/decrypt needed — unlike the video sources).
class CarateenTrack {
  final int track;
  final String title;
  final String artist;
  final String album;
  final int duration; // seconds
  final String url; // .mp3
  final String cover; // .jpg

  const CarateenTrack({
    required this.track,
    required this.title,
    required this.artist,
    required this.album,
    required this.duration,
    required this.url,
    required this.cover,
  });

  factory CarateenTrack.fromJson(Map<String, dynamic> j) => CarateenTrack(
        track: (j['track'] as num?)?.toInt() ?? 0,
        title: j['title'] as String? ?? '',
        artist: j['artist'] as String? ?? '',
        album: j['album'] as String? ?? '',
        duration: (j['duration'] as num?)?.toInt() ?? 0,
        url: j['url'] as String? ?? '',
        cover: j['cover'] as String? ?? '',
      );

  /// Headers the carateen CDN wants for its static assets (Referer + UA). media
  /// _kit forwards these to libmpv for the audio request.
  static const Map<String, String> headers = {
    'User-Agent':
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
    'Referer': 'https://carateen.tv/',
  };
}

/// Parse the `carateen_music.json` document (`{albums:[{tracks:[…]}]}`) into a
/// flat, track-ordered list.
List<CarateenTrack> parseCarateenMusic(Map<String, dynamic> data) {
  final out = <CarateenTrack>[];
  for (final a in (data['albums'] as List?) ?? const []) {
    final am = (a as Map).cast<String, dynamic>();
    for (final t in (am['tracks'] as List?) ?? const []) {
      out.add(CarateenTrack.fromJson((t as Map).cast<String, dynamic>()));
    }
  }
  out.sort((a, b) => a.track.compareTo(b.track));
  return out;
}
