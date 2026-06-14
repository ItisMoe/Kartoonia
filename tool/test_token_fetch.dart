// Live token-extraction check. Run:
//   dart run tool/test_token_fetch.dart "https://www.arabic-toons.com/<page>.html"
// Prints the extracted server URLs (with fresh tokens). Confirms the parser
// works against a live page BEFORE wiring the player UI.
import 'package:kartoonia/services/token_service.dart';

Future<void> main(List<String> args) async {
  final url = args.isNotEmpty
      ? args.first
      : 'https://www.arabic-toons.com/abraj-mylwry-aljz-1-1732261698-42816.html';
  print('Fetching fresh tokens for:\n  $url\n');
  try {
    final servers = await fetchFreshTokens(url);
    if (servers.isEmpty) {
      print('NO SERVERS FOUND — inspect the page HTML / adjust the regex.');
      return;
    }
    for (final s in servers) {
      print('Server ${s.serverNumber}');
      print('  clean: ${s.cleanUrl}');
      print('  raw  : ${s.rawUrl}\n');
    }
    print('OK — extracted ${servers.length} server(s).');
  } catch (e) {
    print('ERROR: $e');
  }
}
