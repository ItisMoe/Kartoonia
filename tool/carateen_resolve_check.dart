// Live check: resolve a carateen episode end-to-end through the app's resolver
// (fetch /api/episode -> AES-256-CBC decrypt -> streamUrl). Run:
//   dart run tool/carateen_resolve_check.dart
import '../lib/services/carateen_resolver.dart';

Future<void> main() async {
  const url = 'https://carateen.tv/watch/91/740';
  print('resolving $url');
  final streams = await resolveCarateen(url);
  for (final s in streams) {
    print('  server=${s.server}');
    print('  streamUrl=${s.streamUrl}');
    print('  headers=${s.headers}');
  }
  if (streams.isEmpty) print('  NO STREAMS');
}
