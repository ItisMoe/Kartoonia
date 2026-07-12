import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart';
import 'package:flutter_test/flutter_test.dart';
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
