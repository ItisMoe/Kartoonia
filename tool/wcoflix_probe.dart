// Live probe: fetch each WCOFlix catalog page exactly like the app does and
// run the app's own parsers, printing item counts and challenge markers.
// Run: dart run tool/wcoflix_probe.dart
import 'dart:io';
import 'package:http/http.dart' as http;
import '../lib/services/wcoflix/wcoflix_config.dart';
import '../lib/services/wcoflix/wcoflix_parsers.dart';

Future<void> main() async {
  final client = http.Client();
  final headers = {
    'User-Agent': kWcoflixUserAgent,
    'Referer': '${wcoflixBaseUrls.first}/',
    'Accept-Language': 'en-US,en;q=0.9',
  };

  Future<String> fetch(String url) async {
    final res = await client
        .get(Uri.parse(url), headers: headers)
        .timeout(const Duration(seconds: 15));
    stdout.writeln('  HTTP ${res.statusCode}  final=${res.request?.url}  len=${res.body.length}');
    return res.body;
  }

  bool blocked(String html) =>
      html.contains('Just a moment') ||
      html.contains('cf-browser-verification') ||
      html.contains('Attention Required');

  final routes = <String, (String, List<WcoLink> Function(String))>{
    'popular': ('/', parseSidebarTitles),
    'latest': ('/last-50-recent-release', parseRecentReleases),
    'cartoons': ('/cartoon-list', parseDdmccList),
    'dubbed': ('/dubbed-anime-list', parseDdmccList),
    'movies': ('/movie-list', parseDdmccList),
    'ova': ('/ova-list', parseDdmccList),
  };

  for (final base in wcoflixBaseUrls) {
    stdout.writeln('=== base: $base ===');
    try {
      final html = await fetch('$base/');
      stdout.writeln('  blocked=${blocked(html)}');
      if (blocked(html)) continue;
      for (final e in routes.entries) {
        try {
          final page = e.key == 'popular' ? html : await fetch('$base${e.value.$1}');
          final list = e.value.$2(page);
          stdout.writeln('  ${e.key}: ${list.length} items'
              '${list.isNotEmpty ? '  first="${list.first.title}" url=${list.first.url}' : '  blocked=${blocked(page)}'}');
        } catch (err) {
          stdout.writeln('  ${e.key}: ERROR $err');
        }
      }
      break; // first working base is what the app would use
    } catch (err) {
      stdout.writeln('  ERROR $err');
    }
  }
  client.close();
  exit(0);
}
