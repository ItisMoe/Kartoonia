// Full WCOFlix catalog scraper → assets/wcoflix_snapshot.json.
//
// Scrapes all six catalog list pages IN PARALLEL from whichever mirror is live
// (the WatchNixtoons2 approach: pure HTML + the app's own parsers) and writes a
// DOMAIN-AGNOSTIC snapshot — each item's URL is stored as a bare path so the app
// can rehome it onto whatever mirror is up at run time. This is the whole
// library (~13k titles), not the capped sample the old snapshot held, so
// Everything mode shows everything instantly and offline.
//
// Run:  dart run tool/wcoflix_scrape.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../lib/services/wcoflix/wcoflix_config.dart';
import '../lib/services/wcoflix/wcoflix_domain.dart';
import '../lib/services/wcoflix/wcoflix_parsers.dart';

/// key -> (path, parser)
final _routes = <String, (String, List<WcoLink> Function(String))>{
  'popular': ('/', parseSidebarTitles),
  'latest': ('/last-50-recent-release', parseRecentReleases),
  'cartoons': ('/cartoon-list', parseDdmccList),
  'dubbed': ('/dubbed-anime-list', parseDdmccList),
  'movies': ('/movie-list', parseDdmccList),
  'ova': ('/ova-list', parseDdmccList),
};

/// Strip a parsed absolute URL down to a bare path(+query) so it is independent
/// of whichever mirror was live at scrape time.
String _toPath(String url) {
  final u = Uri.tryParse(url);
  if (u == null || !u.hasScheme) return url;
  return u.hasQuery ? '${u.path}?${u.query}' : u.path;
}

Future<void> main() async {
  final base = await WcoflixDomain.activeBase(WcoflixDomain.defaultGet);
  stdout.writeln('live mirror: $base');
  final client = http.Client();

  Future<String> fetch(String path) async {
    final res = await client.get(Uri.parse('$base$path'), headers: {
      'User-Agent': kWcoflixUserAgent,
      'Referer': '$base/',
      'Accept-Language': 'en-US,en;q=0.9',
    }).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw HttpException('HTTP ${res.statusCode} for $path');
    }
    return res.body;
  }

  // Scrape all six lists concurrently.
  final results = await Future.wait(_routes.entries.map((e) async {
    final (path, parse) = e.value;
    try {
      final links = parse(await fetch(path));
      // Dedup by path, drop empties, preserve order.
      final seen = <String>{};
      final items = <Map<String, String>>[];
      for (final l in links) {
        final p = _toPath(l.url);
        if (l.title.trim().isEmpty || !seen.add(p)) continue;
        items.add({
          'u': p,
          't': l.title.trim(),
          if (l.thumb != null && l.thumb!.isNotEmpty) 'th': l.thumb!,
        });
      }
      stdout.writeln('  ${e.key}: ${items.length} items');
      return MapEntry(e.key, items);
    } catch (err) {
      stdout.writeln('  ${e.key}: FAILED ($err)');
      return MapEntry(e.key, <Map<String, String>>[]);
    }
  }));

  final snapshot = <String, List<Map<String, String>>>{
    for (final r in results) r.key: r.value,
  };

  // Abort if the scrape came back mostly empty — never clobber a good asset
  // with a failed run.
  final total = snapshot.values.fold<int>(0, (n, v) => n + v.length);
  if (total < 1000) {
    stderr.writeln('ABORT: only $total items scraped — asset left unchanged.');
    client.close();
    exit(1);
  }

  // Write in place (Windows locks assets/*.json against os.replace/rename).
  final out = File('assets/wcoflix_snapshot.json');
  out.writeAsStringSync(jsonEncode(snapshot), flush: true);
  stdout.writeln('wrote ${out.path}: $total items, '
      '${(out.lengthSync() / 1024).toStringAsFixed(0)} KB');
  client.close();
  exit(0);
}
