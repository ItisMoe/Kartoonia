import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/models/content_item.dart';
import 'package:kartoonia/services/resume.dart';
import 'package:kartoonia/services/storage_service.dart';

Episode _ep(int n) => Episode(
      episodeNumber: n,
      episodeTitle: 'E$n',
      episodeUrl: 'u$n',
      servers: const [],
      seasonNumber: 1,
    );

ProgressEntry _p(String url, int n, double frac,
        {int updatedAt = 0, double duration = 100}) =>
    ProgressEntry(
      itemId: 'show',
      episodeUrl: url,
      episodeNumber: n,
      currentTime: frac * duration,
      duration: duration,
      updatedAt: updatedAt,
    );

void main() {
  final episodes = [for (var i = 1; i <= 5; i++) _ep(i)];

  ProgressEntry? Function(String) lookup(Map<String, ProgressEntry> m) =>
      (url) => m[url];

  group('episodeWatchState', () {
    test('null / zero-duration progress is unwatched', () {
      expect(episodeWatchState(null), EpisodeWatchState.unwatched);
      expect(episodeWatchState(_p('u1', 1, 0)), EpisodeWatchState.unwatched);
    });
    test('partial is inProgress, >=95% is watched', () {
      expect(episodeWatchState(_p('u1', 1, 0.4)), EpisodeWatchState.inProgress);
      expect(episodeWatchState(_p('u1', 1, 0.96)), EpisodeWatchState.watched);
      expect(episodeWatchState(_p('u1', 1, 0.95)), EpisodeWatchState.watched);
    });
  });

  group('resumeTarget', () {
    test('no progress → first episode', () {
      expect(resumeTarget(episodes, lookup({})).episodeNumber, 1);
    });

    test('an in-progress episode wins, most-recent if several', () {
      final m = {
        'u2': _p('u2', 2, 0.3, updatedAt: 10),
        'u4': _p('u4', 4, 0.5, updatedAt: 20), // newer
      };
      expect(resumeTarget(episodes, lookup(m)).episodeNumber, 4);
    });

    test('all finished up to N → next unwatched episode', () {
      final m = {
        'u1': _p('u1', 1, 1.0, updatedAt: 1),
        'u2': _p('u2', 2, 0.97, updatedAt: 2),
        'u3': _p('u3', 3, 1.0, updatedAt: 3),
      };
      expect(resumeTarget(episodes, lookup(m)).episodeNumber, 4);
    });

    test('in-progress takes priority over a later finished episode', () {
      final m = {
        'u2': _p('u2', 2, 0.4, updatedAt: 5), // in progress
        'u3': _p('u3', 3, 1.0, updatedAt: 9), // finished later
      };
      expect(resumeTarget(episodes, lookup(m)).episodeNumber, 2);
    });

    test('everything watched → restart from first', () {
      final m = {
        for (var i = 1; i <= 5; i++) 'u$i': _p('u$i', i, 1.0, updatedAt: i),
      };
      expect(resumeTarget(episodes, lookup(m)).episodeNumber, 1);
    });
  });

  group('hasAnyProgress', () {
    test('false when nothing started, true once one is started', () {
      expect(hasAnyProgress(episodes, lookup({})), isFalse);
      expect(
          hasAnyProgress(episodes, lookup({'u3': _p('u3', 3, 0.1)})), isTrue);
    });
  });
}
