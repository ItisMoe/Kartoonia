import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kartoonia/services/storage_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('shaarat boost: absent show reads 0', () async {
    final s = await StorageService.create();
    expect(s.getShaaratBoosts()['show1'] ?? 0, 0);
  });

  test('shaarat boost: points accumulate and persist', () async {
    final s = await StorageService.create();
    await s.addShaaratBoost('show1', 1);
    await s.addShaaratBoost('show1', 2);
    expect(s.getShaaratBoosts()['show1'], 3);

    // A fresh instance reads the same persisted store.
    final s2 = await StorageService.create();
    expect(s2.getShaaratBoosts()['show1'], 3);
  });

  test('shaarat boost: tracks shows independently', () async {
    final s = await StorageService.create();
    await s.addShaaratBoost('a', 4);
    await s.addShaaratBoost('b', 1);
    expect(s.getShaaratBoosts(), {'a': 4, 'b': 1});
  });

  test('shaarat videoId cache: null until set, empty sentinel, real id', () async {
    final s = await StorageService.create();
    expect(s.getShaaratVideoId('show1'), isNull);
    await s.setShaaratVideoId('show1', '');
    expect(s.getShaaratVideoId('show1'), '');
    await s.setShaaratVideoId('show2', 'abc123');
    expect(s.getShaaratVideoId('show2'), 'abc123');
  });

  test('prefs default shaarat mode is video', () async {
    final s = await StorageService.create();
    expect(s.getPrefs()['shaarat'], 'video');
  });
}
