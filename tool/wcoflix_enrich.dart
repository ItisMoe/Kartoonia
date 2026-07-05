// TMDB enrichment for the WCOFlix catalog.
//
// Reads assets/wcoflix_snapshot.json (the scraped ~13.7k-title catalog) and, for
// each unique title, matches it to TMDB to attach a poster, backdrop, and the
// internal popularity signals (vote_count / popularity) — the same `tmdb` block
// shape the Arabic catalog uses (see TmdbData.fromJson). Writes
// assets/wcoflix_catalog.json keyed by the item's bare path.
//
// Runs matches in PARALLEL (bounded pool) with rate-limit backoff, and
// CHECKPOINTS after every batch so a long run can resume where it left off.
//
//   TMDB_API_KEY=<v3 key>  dart run tool/wcoflix_enrich.dart
//
// Optional: pass a comma list of snapshot keys to limit scope, e.g.
//   dart run tool/wcoflix_enrich.dart popular,movies
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../lib/services/wcoflix/wcoflix_titles.dart';

const _out = 'assets/wcoflix_catalog.json';
const _progress = 'tool/enrich_progress.json'; // live status for the GUI viewer
const _poolSize = 16; // concurrent TMDB requests
const _matchGate = 0.5; // min normalized-title similarity to accept a match

// ---- title normalization (inlined so the tool has no Flutter deps) ----
final _reNonAlnum = RegExp(r'[^a-z0-9 ]');
final _reSpace = RegExp(r'\s+');
final _reOrdinal =
    RegExp(r'\b(season|part|episode|series|vol|volume|chapter)\s+\d+\b');
final _reYear = RegExp(r'\b(?:19|20)\d{2}\b');
final _reNoise = RegExp(
    r'\b(the|a|an|season|part|movie|film|special|ova|tv|series|english|dubbed|subbed|and)\b');

String _norm(String s) => s
    .toLowerCase()
    .replaceAll('&', ' and ')
    .replaceAll(_reNonAlnum, ' ')
    .replaceAll(_reOrdinal, ' ')
    .replaceAll(_reYear, ' ')
    .replaceAll(_reNoise, ' ')
    .replaceAll(_reSpace, ' ')
    .trim();

double _score(String a, String b) {
  final na = _norm(a), nb = _norm(b);
  if (na.isEmpty || nb.isEmpty) return 0;
  if (na == nb) return 1;
  final ta = na.split(' ').where((w) => w.isNotEmpty).toSet();
  final tb = nb.split(' ').where((w) => w.isNotEmpty).toSet();
  if (ta.isEmpty || tb.isEmpty) return 0;
  return ta.intersection(tb).length / ta.union(tb).length;
}

const _imgBase = 'https://image.tmdb.org/t/p';

Future<void> main(List<String> args) async {
  final key = Platform.environment['TMDB_API_KEY'];
  if (key == null || key.isEmpty) {
    stderr.writeln('Set TMDB_API_KEY (a TMDB v3 API key) and re-run.');
    exit(2);
  }

  // Collect unique titles from the snapshot (skip the episode-level "latest").
  final snap = jsonDecode(File('assets/wcoflix_snapshot.json').readAsStringSync())
      as Map<String, dynamic>;
  final onlyKeys = args.isEmpty ? null : args.first.split(',').toSet();
  final byTitle = <String, String>{}; // cleanTitle -> representative path
  for (final entry in snap.entries) {
    if (entry.key == 'latest') continue; // episode entries, not shows
    if (onlyKeys != null && !onlyKeys.contains(entry.key)) continue;
    for (final raw in (entry.value as List)) {
      final m = raw as Map;
      final clean = parseTitleMeta(m['t'] as String).cleanTitle;
      byTitle.putIfAbsent(clean, () => m['u'] as String);
    }
  }
  final target = byTitle.length;
  stdout.writeln('$target unique titles to enrich');

  // Resume: keep already-matched paths from a previous run.
  final result = <String, dynamic>{};
  final done = <String>{};
  final outFile = File(_out);
  if (outFile.existsSync()) {
    try {
      final prev = jsonDecode(outFile.readAsStringSync()) as Map<String, dynamic>;
      final items = prev['items'];
      if (items is Map) {
        result.addAll(items.cast<String, dynamic>());
        done.addAll(items.keys.map((k) => k.toString()));
      }
    } catch (_) {}
  }

  final client = http.Client();
  final work = byTitle.entries
      .where((e) => !done.contains(e.value))
      .toList(); // (cleanTitle, path)
  stdout.writeln('${work.length} remaining (${done.length} already done)');

  var processed = 0, matched = 0;
  final it = work.iterator;
  bool next(void Function(String title, String path) run) {
    if (!it.moveNext()) {
      return false;
    }
    run(it.current.key, it.current.value);
    return true;
  }

  Future<void> worker() async {
    while (true) {
      String? title, path;
      if (!next((t, p) {
        title = t;
        path = p;
      })) return;
      final block = await _enrich(client, key, title!);
      processed++;
      if (block != null) {
        matched++;
        result[path!] = {'t': title, 'tmdb': block};
      }
      if (processed % 100 == 0) {
        _writeCheckpoint(outFile, result);
        _writeProgress(target, done.length + processed, matched, running: true);
        stdout.writeln('  $processed/${work.length}  matched=$matched');
      }
    }
  }

  _writeProgress(target, done.length, done.length, running: true);
  await Future.wait(List.generate(_poolSize, (_) => worker()));
  _writeCheckpoint(outFile, result);
  _writeProgress(target, done.length + processed, result.length, running: false);
  client.close();
  stdout.writeln('DONE: ${result.length} enriched titles → $_out '
      '(${(outFile.lengthSync() / 1024).toStringAsFixed(0)} KB)');
  exit(0);
}

void _writeProgress(int target, int processed, int matched,
    {required bool running}) {
  File(_progress).writeAsStringSync(
      jsonEncode({
        'target': target,
        'processed': processed,
        'matched': matched,
        'running': running,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true);
}

void _writeCheckpoint(File f, Map<String, dynamic> items) {
  f.writeAsStringSync(
      jsonEncode({
        'generated_at': DateTime.now().toUtc().toIso8601String(),
        'source': 'wcoflix+tmdb',
        'total': items.length,
        'items': items,
      }),
      flush: true);
}

/// Query TMDB for [title]; return a `tmdb` block (matching TmdbData.fromJson) or
/// null when nothing clears the match gate. Retries once on HTTP 429.
Future<Map<String, dynamic>?> _enrich(
    http.Client c, String key, String title) async {
  for (var attempt = 0; attempt < 3; attempt++) {
    try {
      final uri = Uri.parse('https://api.themoviedb.org/3/search/multi'
          '?api_key=$key&include_adult=false&query=${Uri.encodeQueryComponent(title)}');
      final res = await c.get(uri).timeout(const Duration(seconds: 15));
      if (res.statusCode == 429) {
        await Future<void>.delayed(const Duration(seconds: 2));
        continue;
      }
      if (res.statusCode != 200) return null;
      final results = (jsonDecode(res.body) as Map)['results'] as List? ?? const [];

      Map? best;
      var bestScore = 0.0;
      for (final r in results) {
        final m = r as Map;
        final type = m['media_type'];
        if (type != 'tv' && type != 'movie') continue;
        final name = (m['name'] ?? m['title'] ?? '') as String;
        final orig = (m['original_name'] ?? m['original_title'] ?? '') as String;
        var s = _score(title, name);
        final so = _score(title, orig);
        if (so > s) s = so;
        // Nudge animation titles ahead on close calls (cartoon/anime catalog).
        final isAnim = (m['genre_ids'] as List?)?.contains(16) ?? false;
        if (isAnim) s += 0.02;
        if (s > bestScore) {
          bestScore = s;
          best = m;
        }
      }
      if (best == null || bestScore < _matchGate) return null;

      final type = best['media_type'] == 'movie' ? 'movie' : 'tv';
      final poster = best['poster_path'] as String?;
      final backdrop = best['backdrop_path'] as String?;
      final dateStr =
          (best['first_air_date'] ?? best['release_date'] ?? '') as String;
      final year =
          dateStr.length >= 4 ? int.tryParse(dateStr.substring(0, 4)) : null;
      return {
        'tmdb_id': best['id'],
        'type': type,
        'match_confidence': double.parse(bestScore.toStringAsFixed(3)),
        'poster_url': poster == null ? null : '$_imgBase/original$poster',
        'poster_url_w500': poster == null ? null : '$_imgBase/w500$poster',
        'backdrop_url': backdrop == null ? null : '$_imgBase/original$backdrop',
        'original_title':
            best['original_name'] ?? best['original_title'],
        'vote_average': best['vote_average'],
        'vote_count': best['vote_count'],
        'popularity': best['popularity'],
        'year': year,
        'en': {
          'title': best['name'] ?? best['title'],
          'overview': best['overview'],
          'genres': const <String>[], // genre_ids only from /search; names need a detail call
        },
      };
    } catch (_) {
      return null;
    }
  }
  return null;
}
