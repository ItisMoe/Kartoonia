import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kartoonia/models/content_item.dart';
import 'package:kartoonia/services/storage_service.dart';
import 'package:kartoonia/services/shaarat_resolver.dart';

Show _show(String id) => Show(
    id: id,
    title: id,
    thumbnailUrl: '',
    description: '',
    totalEpisodes: 1,
    seasonCount: 1,
    seasons: const [],
    episodes: const []);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('cache miss → searches once and caches the top id', () async {
    final s = await StorageService.create();
    var calls = 0;
    final r = ShaaratResolver(s, search: (q) async {
      calls++;
      return ['vid1'];
    });
    expect(await r.videoIdFor(_show('a')), 'vid1');
    expect(await r.videoIdFor(_show('a')), 'vid1'); // served from cache
    expect(calls, 1);
  });

  test('empty search result caches the negative sentinel (no re-search)',
      () async {
    final s = await StorageService.create();
    var calls = 0;
    final r = ShaaratResolver(s, search: (q) async {
      calls++;
      return [];
    });
    expect(await r.videoIdFor(_show('a')), isNull);
    expect(await r.videoIdFor(_show('a')), isNull);
    expect(calls, 1);
  });

  test('search throwing returns null without caching', () async {
    final s = await StorageService.create();
    final r = ShaaratResolver(s, search: (q) async => throw Exception('quota'));
    expect(await r.videoIdFor(_show('a')), isNull);
    expect(s.getShaaratVideoId('a'), isNull); // not cached → retried next time
  });
}
