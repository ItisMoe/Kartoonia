import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kartoonia/services/storage_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

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
