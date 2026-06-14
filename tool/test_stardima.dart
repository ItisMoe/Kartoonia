// Live check of the Dart Stardima port + extraction. Run:
//   dart run tool/test_stardima.dart
import 'dart:io';
import 'package:kartoonia/services/stardima_service.dart';

Future<void> main() async {
  final svc = StardimaService();
  svc.setIndex(await File('assets/stardima_index.json').readAsString());
  for (final title in ['المحقق كونان', 'سبونج بوب']) {
    print('\n=== $title ===');
    try {
      final servers = await svc
          .resolveServers(title, season: 1, episode: 1)
          .timeout(const Duration(seconds: 30));
      print('servers: ${servers.length}');
      for (final s in servers) {
        final ok = await svc.resolveDirect(s);
        if (ok) {
          print('  ${s.name.padRight(12)} -> ${s.isHls ? "HLS" : "MP4"}'
              '  arabicAudio=${s.arabicAudio ?? "-"}');
          print('      ${s.directUrl!.substring(0, s.directUrl!.length.clamp(0, 90))}');
        } else {
          print('  ${s.name.padRight(12)} -> EMBED (no direct) ${s.embedUrl}');
        }
      }
    } catch (e) {
      print('error: $e');
    }
  }
  svc.dispose();
}
