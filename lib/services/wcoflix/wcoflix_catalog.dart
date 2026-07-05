import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'wcoflix_config.dart';
import 'wcoflix_parsers.dart';

typedef WcoFetch = Future<String> Function(String url,
    {Map<String, String>? post});

/// Live WCOFlix catalog access with a **bundled snapshot fallback**. Home/browse
/// rows read [snapshot] instantly (so Everything mode always shows titles, even
/// when the live site is slow, blocked by a Cloudflare challenge, or offline),
/// then swap to fresh data once a background [fetchLive] completes. Search and
/// series detail are live-only (with the same soft-fail behavior).
///
/// The [fetch] hook is injectable so tests run against fixtures with no network.
class WcoflixCatalog {
  WcoflixCatalog({WcoFetch? fetch, Future<String> Function(String)? loadAsset})
      : _fetch = fetch ?? _defaultFetch,
        _loadAsset = loadAsset ?? rootBundle.loadString;

  final WcoFetch _fetch;
  final Future<String> Function(String) _loadAsset;

  /// Successful, non-empty live results this session, keyed by category.
  final _live = <String, List<WcoLink>>{};
  final _inflight = <String, Future<void>>{};
  final _seriesCache = <String, WcoSeries>{};
  final _searchCache = <String, List<WcoLink>>{};
  Map<String, List<WcoLink>>? _snap;

  static final http.Client _client = http.Client();
  static Future<String> _defaultFetch(String url,
      {Map<String, String>? post}) async {
    final headers = {
      'User-Agent': kWcoflixUserAgent,
      'Referer': '${wcoflixBaseUrls.first}/',
      'Accept-Language': 'en-US,en;q=0.9',
    };
    final res = await (post == null
            ? _client.get(Uri.parse(url), headers: headers)
            : _client.post(Uri.parse(url), headers: headers, body: post))
        .timeout(const Duration(seconds: 15));
    return res.body;
  }

  // ---- category routing (path + parser) ----
  (String, List<WcoLink> Function(String)) _route(String key) {
    switch (key) {
      case 'latest':
        return ('/last-50-recent-release', parseRecentReleases);
      case 'cartoons':
        return ('/cartoon-list', parseDdmccList);
      case 'dubbed':
        return ('/dubbed-anime-list', parseDdmccList);
      case 'movies':
        return ('/movie-list', parseDdmccList);
      case 'ova':
        return ('/ova-list', parseDdmccList);
      case 'popular':
      default:
        return ('/', parseSidebarTitles);
    }
  }

  // ---- snapshot (bundled) ----
  Future<Map<String, List<WcoLink>>> _loadSnapshot() async {
    try {
      final raw = await _loadAsset('assets/wcoflix_snapshot.json');
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return m.map((k, v) => MapEntry(k, [
            for (final e in (v as List))
              WcoLink((e as Map)['u'] as String, e['t'] as String,
                  thumb: e['th'] as String?),
          ]));
    } catch (_) {
      return {};
    }
  }

  /// The bundled snapshot list for [key] (empty if the asset is missing/bad).
  Future<List<WcoLink>> snapshot(String key) async {
    _snap ??= await _loadSnapshot();
    return _snap![key] ?? const [];
  }

  /// The fresh live result for [key], or null until a live fetch has succeeded.
  List<WcoLink>? live(String key) => _live[key];

  /// A Cloudflare/interstitial CHALLENGE page instead of the real catalog HTML.
  /// (Note: the `/cdn-cgi/challenge-platform` script tag is present on every
  /// Cloudflare-fronted page even when serving real content, so it is NOT a
  /// reliable challenge marker — only these titles/markers are.)
  static bool _blocked(String html) =>
      html.contains('Just a moment') ||
      html.contains('cf-browser-verification') ||
      html.contains('Attention Required');

  /// Fetch a category live (deduped); stores it in [live] on success. Never
  /// throws — failures leave the snapshot in place.
  Future<void> fetchLive(String key) {
    if (_live.containsKey(key)) return Future.value();
    return _inflight.putIfAbsent(key, () async {
      try {
        final (path, parse) = _route(key);
        final html = await _fetch('${wcoflixBaseUrls.first}$path');
        if (!_blocked(html)) {
          final list = parse(html);
          if (list.isNotEmpty) _live[key] = list;
        }
      } catch (_) {
        // keep the snapshot
      } finally {
        _inflight.remove(key);
      }
    });
  }

  // ---- live-only (search + detail), soft-fail ----
  Future<List<WcoLink>> search(String q, {String type = 'series'}) async {
    final key = '$type:$q';
    final hit = _searchCache[key];
    if (hit != null) return hit;
    try {
      final html = await _fetch('${wcoflixBaseUrls.first}/search',
          post: {'catara': q, 'konuara': type});
      if (_blocked(html)) return const [];
      final list = parseSearchResults(html);
      _searchCache[key] = list;
      return list;
    } catch (_) {
      return const [];
    }
  }

  Future<WcoSeries> seriesDetail(String url) async {
    final hit = _seriesCache[url];
    if (hit != null) return hit;
    final s = parseSeriesPage(await _fetch(url), seriesSlugFromUrl(url));
    _seriesCache[url] = s;
    return s;
  }
}
