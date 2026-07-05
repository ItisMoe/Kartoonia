import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/services/wcoflix/wcoflix_catalog.dart';
import 'package:kartoonia/services/wcoflix/wcoflix_adapter.dart';

/// Reproduction: exercise the REAL bundled snapshot the way Everything mode
/// does, and confirm each home row yields non-empty, titled cards.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled snapshot yields titled cards for every home row', () async {
    final cat = WcoflixCatalog();
    for (final key in ['popular', 'latest', 'cartoons', 'dubbed', 'movies']) {
      final links = await cat.snapshot(key);
      expect(links, isNotEmpty, reason: 'snapshot "$key" is empty');
      final cards = [for (final l in links) wcoflixShowStub(l)];
      expect(cards.every((c) => c.title.trim().isNotEmpty), isTrue,
          reason: 'row "$key" has a card with an empty title');
    }
  });
}
