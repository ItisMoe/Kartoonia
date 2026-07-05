import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/services/wcoflix/wcoflix_match.dart';
import 'package:kartoonia/services/wcoflix/wcoflix_parsers.dart';

void main() {
  group('titleMatchScore', () {
    test('exact after normalization = 1', () {
      expect(titleMatchScore('Detective Conan', 'detective conan!'), 1.0);
      expect(titleMatchScore('Hunter x Hunter (2011)', 'Hunter x Hunter'), 1.0);
    });
    test('format/noise words ignored', () {
      expect(titleMatchScore('Naruto English Dubbed', 'Naruto'), 1.0);
      expect(titleMatchScore('Bleach Season 1', 'Bleach'), 1.0);
    });
    test('one shared word only -> below gate', () {
      expect(titleMatchScore('Naruto', 'Naruto Shippuden'), lessThan(0.6));
    });
    test('unrelated -> low', () {
      expect(titleMatchScore('One Piece', 'Bleach'), 0);
    });
  });

  test('bestWcoflixMatch gates on min score', () {
    final links = [
      const WcoLink('/anime/naruto-shippuden', 'Naruto Shippuden'),
      const WcoLink('/anime/detective-conan', 'Detective Conan English Dubbed'),
    ];
    expect(bestWcoflixMatch('Detective Conan', links)!.url,
        '/anime/detective-conan');
    // "Naruto" alone shouldn't match "Naruto Shippuden".
    expect(bestWcoflixMatch('Naruto', links), isNull);
  });
}
