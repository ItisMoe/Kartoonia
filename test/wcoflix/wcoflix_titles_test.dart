import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/services/wcoflix/wcoflix_quality.dart';
import 'package:kartoonia/services/wcoflix/wcoflix_titles.dart';

void main() {
  group('WcoQuality.best (default 720p)', () {
    test('want 720 present -> 720', () {
      expect(
          WcoQuality.best(WcoQuality.p720,
              [WcoQuality.p576, WcoQuality.p720, WcoQuality.p1080]),
          WcoQuality.p720);
    });
    test('want 720 absent, has 1080 -> 1080', () {
      expect(
          WcoQuality.best(WcoQuality.p720, [WcoQuality.p576, WcoQuality.p1080]),
          WcoQuality.p1080);
    });
    test('want 720, only 576 -> 576', () {
      expect(WcoQuality.best(WcoQuality.p720, [WcoQuality.p576]),
          WcoQuality.p576);
    });
    test('tags, tokens, resolutions', () {
      expect(WcoQuality.p720.tag, '720p');
      expect(WcoQuality.p1080.token, 'fhd');
      expect(WcoQuality.p576.resolution, 576);
    });
  });

  group('parseTitleMeta', () {
    test('dubbed episode', () {
      final m = parseTitleMeta('Black Torch Episode 1 English Dubbed');
      expect(m.cleanTitle, 'Black Torch');
      expect(m.isDub, isTrue);
      expect(m.isSub, isFalse);
      expect(m.episode, 1);
    });
    test('subbed flagged', () {
      final m = parseTitleMeta('Detective Conan Episode 900 English Subbed');
      expect(m.isSub, isTrue);
      expect(m.isDub, isFalse);
      expect(m.episode, 900);
    });
    test('season + episode', () {
      final m = parseTitleMeta(
          'Ascendance of a Bookworm Season 4 Episode 10 English Dubbed');
      expect(m.cleanTitle, 'Ascendance of a Bookworm');
      expect(m.season, 4);
      expect(m.episode, 10);
    });
    test('movie (no episode)', () {
      final m = parseTitleMeta('Animal Farm 2025');
      expect(m.episode, isNull);
      expect(m.cleanTitle, 'Animal Farm 2025');
    });
  });
}
