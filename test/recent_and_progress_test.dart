import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:kartoonia/services/storage_service.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('removeProgressForItem clears all episodes of a show', () async {
    final s = await StorageService.create();
    await s.saveProgress(const ProgressEntry(
        itemId: 'show1',
        episodeUrl: 'u1',
        episodeNumber: 1,
        currentTime: 10,
        duration: 100,
        updatedAt: 1));
    await s.saveProgress(const ProgressEntry(
        itemId: 'show1',
        episodeUrl: 'u2',
        episodeNumber: 2,
        currentTime: 10,
        duration: 100,
        updatedAt: 2));
    await s.saveProgress(const ProgressEntry(
        itemId: 'other',
        episodeUrl: 'u3',
        episodeNumber: 1,
        currentTime: 10,
        duration: 100,
        updatedAt: 3));

    await s.removeProgressForItem('show1');
    expect(s.getProgress('u1'), isNull);
    expect(s.getProgress('u2'), isNull);
    expect(s.getProgress('u3'), isNotNull);

    await s.removeProgress('u3');
    expect(s.getProgress('u3'), isNull);
  });

  test('getContinueWatching shows one entry per title (latest episode)',
      () async {
    final s = await StorageService.create();
    // Two in-progress episodes of the same show + one of another show.
    await s.saveProgress(const ProgressEntry(
        itemId: 'show1',
        episodeUrl: 'e11',
        episodeNumber: 11,
        currentTime: 10,
        duration: 100,
        updatedAt: 5));
    await s.saveProgress(const ProgressEntry(
        itemId: 'show1',
        episodeUrl: 'e15',
        episodeNumber: 15,
        currentTime: 10,
        duration: 100,
        updatedAt: 9)); // more recent
    await s.saveProgress(const ProgressEntry(
        itemId: 'show2',
        episodeUrl: 'e1',
        episodeNumber: 1,
        currentTime: 10,
        duration: 100,
        updatedAt: 7));

    final cw = s.getContinueWatching();
    // One card per title, not one per episode.
    expect(cw.map((e) => e.itemId).toList(), ['show1', 'show2']);
    // The show1 card carries its MOST-RECENT episode (15, not 11).
    expect(cw.first.episodeNumber, 15);
  });
}
