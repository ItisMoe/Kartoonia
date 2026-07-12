import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:kartoonia/models/carateen_adapter.dart';
import 'package:kartoonia/models/carateen_music.dart';
import 'package:kartoonia/models/catalog_source.dart';
import 'package:kartoonia/models/content_item.dart';
import 'package:kartoonia/services/carateen_resolver.dart';
import 'package:kartoonia/services/shaarat_feed.dart';

void main() {
  group('parseCarateenPlayUrl', () {
    test('extracts showId + episodeId from a watch URL', () {
      final r = parseCarateenPlayUrl('https://carateen.tv/watch/91/740');
      expect(r, isNotNull);
      expect(r!.showId, '91');
      expect(r.episodeId, '740');
    });
    test('returns null for a non-watch URL', () {
      expect(parseCarateenPlayUrl('https://carateen.tv/music'), isNull);
      expect(parseCarateenPlayUrl('not a url at all /watch/'), isNull);
    });
  });

  group('decryptCarateen', () {
    test('round-trips an AES-256-CBC {iv, encryptedData} envelope', () {
      // Encrypt a payload with the SAME key/mode the site uses, then confirm the
      // resolver's decrypt recovers it — locks the cipher/key/padding choice.
      final key = Key.fromUtf8('7annaba3l_loves_crypto_safe_key!');
      final iv = IV(Uint8List.fromList(
          List<int>.generate(16, (i) => (i * 7 + 3) & 0xff)));
      final enc = Encrypter(AES(key, mode: AESMode.cbc, padding: 'PKCS7'));
      const plain = '{"streamUrl":"https://cdn/x.m3u8","hls_supported":true}';
      final ct = enc.encrypt(plain, iv: iv);
      final envelope = {'iv': iv.base16, 'encryptedData': ct.base16};

      final out = decryptCarateen(envelope);
      expect(out, isA<Map>());
      expect((out as Map)['streamUrl'], 'https://cdn/x.m3u8');
      expect(out['hls_supported'], true);
    });
    test('passes through an already-plain body', () {
      final plain = {'streamUrl': 'x'};
      expect(decryptCarateen(plain), same(plain));
    });
  });

  group('parseHlsMasterVariants', () {
    // Verbatim shape of pegasus.5387692.xyz masters (variants NOT in
    // resolution order, blank lines between entries).
    const master = '''
#EXTM3U
#EXT-X-VERSION:4

#EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080,NAME="1080p"
1080p/playlist.m3u8

#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=640x360,NAME="360p"
360p/playlist.m3u8

#EXT-X-STREAM-INF:BANDWIDTH=1400000,RESOLUTION=854x480,NAME="480p"
480p/playlist.m3u8

#EXT-X-STREAM-INF:BANDWIDTH=2800000,RESOLUTION=1280x720,NAME="720p"
720p/playlist.m3u8
''';
    final base =
        Uri.parse('https://pegasus.5387692.xyz/api/hls/2583/playlist.m3u8');

    test('extracts every variant with absolute URLs and heights', () {
      final v = parseHlsMasterVariants(master, base);
      expect(v, hasLength(4));
      final p1080 = v.firstWhere((e) => e.name == '1080p');
      expect(p1080.height, 1080);
      expect(p1080.bandwidth, 5000000);
      expect(p1080.url,
          'https://pegasus.5387692.xyz/api/hls/2583/1080p/playlist.m3u8');
    });

    test('orders 720p first, then the rest highest-first (WCOFlix rule)', () {
      final v = orderCarateenVariants(parseHlsMasterVariants(master, base));
      expect(v.map((e) => e.name).toList(), ['720p', '1080p', '480p', '360p']);
    });

    test('falls back to the resolution height when NAME is missing', () {
      const noName = '#EXTM3U\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=2800000,RESOLUTION=1280x720\n'
          'v0/playlist.m3u8\n';
      final v = parseHlsMasterVariants(noName, base);
      expect(v.single.name, '720p');
    });

    test('returns empty for a media (non-master) playlist', () {
      const media = '#EXTM3U\n#EXT-X-TARGETDURATION:11\n'
          '#EXTINF:9.6,\nsegment_000.jpg\n';
      expect(parseHlsMasterVariants(media, base), isEmpty);
    });
  });

  group('resolveCarateen variants', () {
    // Encrypt an /api/episode envelope exactly like the site does.
    Map<String, String> envelope(String plainJson) {
      final key = Key.fromUtf8('7annaba3l_loves_crypto_safe_key!');
      final iv = IV(Uint8List.fromList(
          List<int>.generate(16, (i) => (i * 11 + 5) & 0xff)));
      final enc = Encrypter(AES(key, mode: AESMode.cbc, padding: 'PKCS7'));
      return {
        'iv': iv.base16,
        'encryptedData': enc.encrypt(plainJson, iv: iv).base16,
      };
    }

    test('expands the master playlist into per-resolution servers, 720p first',
        () async {
      const masterUrl = 'https://cdn.example/api/hls/9/playlist.m3u8';
      final client = MockClient((req) async {
        if (req.url.path == '/api/episode') {
          return http.Response(
              jsonEncode(envelope('{"streamUrl":"$masterUrl"}')), 200);
        }
        expect(req.url.toString(), masterUrl);
        // Media headers must reach the CDN request too.
        expect(req.headers['Referer'], 'https://carateen.tv/');
        return http.Response(
            '#EXTM3U\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080,NAME="1080p"\n'
            '1080p/playlist.m3u8\n'
            '#EXT-X-STREAM-INF:BANDWIDTH=2800000,RESOLUTION=1280x720,NAME="720p"\n'
            '720p/playlist.m3u8\n',
            200);
      });
      final streams = await resolveCarateen('https://carateen.tv/watch/91/740',
          client: client);
      expect(streams.map((s) => s.server).toList(), ['720p', '1080p']);
      expect(streams.first.streamUrl,
          'https://cdn.example/api/hls/9/720p/playlist.m3u8');
      expect(streams.first.headers['Referer'], 'https://carateen.tv/');
    });

    test('falls back to the single master URL when the master fetch fails',
        () async {
      const masterUrl = 'https://cdn.example/api/hls/9/playlist.m3u8';
      final client = MockClient((req) async {
        if (req.url.path == '/api/episode') {
          return http.Response(
              jsonEncode(envelope('{"streamUrl":"$masterUrl"}')), 200);
        }
        return http.Response('nope', 403);
      });
      final streams = await resolveCarateen('https://carateen.tv/watch/91/740',
          client: client);
      expect(streams, hasLength(1));
      expect(streams.single.streamUrl, masterUrl);
      expect(streams.single.server, 'Carateen');
    });
  });

  group('CarateenAdapter', () {
    test('parses shows + movies with carateen source and play_urls', () {
      final (shows, movies) = CarateenAdapter.parse({
        'tvshows': [
          {
            'id': '91',
            'title': 'ساندي بل',
            'poster_url': 'https://carateen.tv/p.webp',
            'category': 'مسلسل مدبلج',
            'year': 1981,
            'seasons': [
              {
                'number': 1,
                'episodes': [
                  {
                    'number': 0,
                    'title': 'الحلقة 1',
                    'play_url': 'https://carateen.tv/watch/91/740',
                  }
                ]
              }
            ]
          }
        ],
        'movies': [
          {
            'id': '5',
            'title': 'فيلم',
            'poster_url': 'https://carateen.tv/m.webp',
            'play_url': 'https://carateen.tv/watch/5/52',
          }
        ],
      });
      expect(shows, hasLength(1));
      expect(movies, hasLength(1));
      final s = shows.first;
      expect(s.source, CatalogSource.carateen);
      expect(s.id, 'c_91');
      expect(s.episodes.single.episodeUrl, 'https://carateen.tv/watch/91/740');
      expect(s.year, 1981);
      expect(movies.first.pageUrl, 'https://carateen.tv/watch/5/52');
      expect(movies.first.source, CatalogSource.carateen);
    });
  });

  group('parseCarateenMusic', () {
    test('flattens album tracks in track order', () {
      final tracks = parseCarateenMusic({
        'albums': [
          {
            'id': 'nostalgia',
            'tracks': [
              {'track': 2, 'title': 'b', 'url': 'u2', 'duration': 10},
              {'track': 1, 'title': 'a', 'artist': 'x', 'url': 'u1'},
            ]
          }
        ]
      });
      expect(tracks.map((t) => t.track).toList(), [1, 2]);
      expect(tracks.first.title, 'a');
      expect(tracks.first.artist, 'x');
    });
  });

  group('shaaratItemQueue', () {
    // shaaratQueue only surfaces famous + animated shows, so give each a
    // qualifying TMDB (distinct id so they aren't deduped).
    Show show(String id) => Show(
          id: id,
          title: 'S$id',
          thumbnailUrl: '',
          description: '',
          tmdb: TmdbData(
            tmdbId: int.parse(id),
            voteCount: 100,
            tmdbGenres: const ['Animation'],
          ),
          totalEpisodes: 0,
          seasonCount: 0,
          seasons: const [],
          episodes: const [],
          source: CatalogSource.carateen,
        );
    CarateenTrack track(int n) => CarateenTrack(
        track: n,
        title: 'T$n',
        artist: 'a',
        album: 'x',
        duration: 1,
        url: 'u$n',
        cover: 'c$n');

    test('interleaves music through the show reels and drops nothing', () {
      final q = shaaratItemQueue(
        [show('1'), show('2'), show('3'), show('4'), show('5'), show('6')],
        const {},
        [track(1), track(2)],
        (_) => null,
        musicEvery: 3,
      );
      final music = q.where((e) => e.isMusic).toList();
      expect(music, hasLength(2)); // both tracks present
      // A music entry sits after every 3rd show, so index 3 is the first music.
      expect(q[3].isMusic, isTrue);
      // Unlinked tracks can't be entered.
      expect(music.every((e) => !e.canEnter), isTrue);
    });

    test('with no shows, the feed is just the music', () {
      final q = shaaratItemQueue(
          const [], const {}, [track(1), track(2)], (_) => null);
      expect(q, hasLength(2));
      expect(q.every((e) => e.isMusic), isTrue);
    });
  });
}
