import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/services/wcoflix/wcoflix_quality.dart';
import 'package:kartoonia/services/wcoflix/wcoflix_resolver.dart';

/// Fake I/O that serves canned bodies by URL substring, records POSTs, and
/// makes sleep instant — so the full getvid handshake is exercised offline.
class _FakeHttp implements WcoHttp {
  final Map<String, String> routes;
  final posts = <String>[];
  final gets = <String>[];
  /// Optional per-key dynamic responder (call index -> body) for retry tests.
  final Map<String, String Function(int)> dynamicRoutes;
  final _hits = <String, int>{};
  _FakeHttp(this.routes, {this.dynamicRoutes = const {}});
  @override
  Future<String> get(String url, {Map<String, String>? headers}) async {
    gets.add(url);
    for (final e in dynamicRoutes.entries) {
      if (url.contains(e.key)) {
        final n = _hits[e.key] = (_hits[e.key] ?? 0);
        _hits[e.key] = n + 1;
        return e.value(n);
      }
    }
    for (final e in routes.entries) {
      if (url.contains(e.key)) return e.value;
    }
    return '';
  }
  @override
  Future<void> post(String url, String body, {Map<String, String>? headers}) async {
    posts.add('$url|$body');
  }
  @override
  Future<void> sleep(Duration d) async {}
}

const _episode =
    '<iframe rel="nofollow" id="cizgi-js-0" '
    'src="https://embed.wcostream.com/inc/embed/index.php?file=x.flv&fullhd=1&pid=1012000&h=abc&t=1&embed=neptun"></iframe>';

const _player = 'stuff getvid?evid stuff getRedirectedUrl(videoUrl) '
    r'$.getJSON("/inc/embed/getvidlink.php?v=neptun/x.mp4&embed=neptun&fullhd=1", function(){})';

const _getvidJson =
    '{"enc":"E576","server":"https://neptun.wcostream.com","cdn":"https://cdn.x","hd":"H720","fhd":"F1080"}';

const _adWall =
    '<!DOCTYPE html><html><head><title>Announcement</title></head>'
    '<body><div id="announcement"><a>Get PREMIUM Now!</a></div></body></html>';

void main() {
  test('full getvid flow: handshake -> 720p-first mp4 streams', () async {
    final io = _FakeHttp({
      'black-torch': _episode,
      'video-js.php': _player,
      'getvidlink.php': _getvidJson,
      'advertisement.js': '',
    });
    final streams = await resolveWcoflix(
      'https://www.wcoflix.tv/black-torch-episode-1-english-dubbed',
      http: io,
    );
    // ad-verify was POSTed with a clear nonce for the right pid.
    expect(io.posts.single, contains('/ad-verify'));
    expect(io.posts.single, contains('"status":"clear"'));
    expect(io.posts.single, contains('"id":"1012000"'));
    // Uses the current player endpoint, never the retired ad-walled one.
    expect(io.gets.any((u) => u.contains('video-js.php')), isTrue);
    expect(io.gets.any((u) => u.contains('video-js-old.php')), isFalse);
    // 720p default is first; all three qualities present.
    expect(streams.first.quality, WcoQuality.p720);
    expect(streams.first.type, 'mp4');
    expect(streams.map((s) => s.quality).toSet(),
        {WcoQuality.p576, WcoQuality.p720, WcoQuality.p1080});
    expect(streams.first.url, 'https://neptun.wcostream.com/getvid?evid=H720');
    expect(streams.first.headers['Referer'], 'https://embed.wcostream.com/');
  });

  test('retries the anti-adblock wall until the real player loads', () async {
    // First two player fetches return the ad wall; the third is the player.
    final io = _FakeHttp(
      {
        'black-torch': _episode,
        'getvidlink.php': _getvidJson,
        'advertisement.js': '',
      },
      dynamicRoutes: {
        'video-js.php': (n) => n < 2 ? _adWall : _player,
      },
    );
    final streams = await resolveWcoflix(
      'https://www.wcoflix.tv/black-torch-episode-1-english-dubbed',
      http: io,
      dwell: Duration.zero,
      retryBackoff: Duration.zero,
    );
    expect(streams.first.url, 'https://neptun.wcostream.com/getvid?evid=H720');
    // One ad handshake per attempt (3 total).
    expect(io.posts.where((p) => p.contains('/ad-verify')).length, 3);
  });

  test('throws when every attempt hits the ad wall', () async {
    final io = _FakeHttp({
      'black-torch': _episode,
      'video-js.php': _adWall,
      'advertisement.js': '',
    });
    expect(
      () => resolveWcoflix(
        'https://www.wcoflix.tv/black-torch-episode-1-english-dubbed',
        http: io,
        dwell: Duration.zero,
        retryBackoff: Duration.zero,
      ),
      throwsA(isA<WcoflixResolveException>()),
    );
  });

  test('HLS embed path yields a single adaptive stream', () async {
    final io = _FakeHttp({
      '/ep': '<iframe id="anime-js-1" src="https://h.example/frame"></iframe>',
      'frame': '<source src="https://h.example/vid/master.m3u8">',
    });
    final streams = await resolveWcoflix('https://x/ep', http: io);
    expect(streams.single.type, 'hls');
    expect(streams.single.url, 'https://h.example/vid/master.m3u8');
  });
}
