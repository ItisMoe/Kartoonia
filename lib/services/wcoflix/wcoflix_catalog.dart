import 'package:http/http.dart' as http;
import 'wcoflix_config.dart';
import 'wcoflix_parsers.dart';

typedef WcoFetch = Future<String> Function(String url,
    {Map<String, String>? post});

class _Cached {
  final DateTime at;
  final List<WcoLink> data;
  _Cached(this.at, this.data);
}

/// Live WCOFlix catalog access with a simple TTL memory cache. All parsing is
/// delegated to the pure fns in `wcoflix_parsers.dart`; this class only does
/// I/O + caching, so it stays thin and the logic stays testable. The [fetch]
/// hook is injectable so tests run against fixtures with no network.
class WcoflixCatalog {
  WcoflixCatalog({WcoFetch? fetch}) : _fetch = fetch ?? _defaultFetch;
  final WcoFetch _fetch;
  final _cache = <String, _Cached>{};
  final _seriesCache = <String, WcoSeries>{};

  static final http.Client _client = http.Client();
  static Future<String> _defaultFetch(String url,
      {Map<String, String>? post}) async {
    final headers = {
      'User-Agent': kWcoflixUserAgent,
      'Referer': '${wcoflixBaseUrls.first}/',
    };
    final res = post == null
        ? await _client.get(Uri.parse(url), headers: headers)
        : await _client.post(Uri.parse(url), headers: headers, body: post);
    return res.body;
  }

  Future<List<WcoLink>> _listed(
    String key,
    String path,
    List<WcoLink> Function(String) parse, {
    Duration ttl = const Duration(hours: 6),
    Map<String, String>? post,
  }) async {
    final hit = _cache[key];
    if (hit != null && DateTime.now().difference(hit.at) < ttl) return hit.data;
    final url = path.startsWith('http') ? path : '${wcoflixBaseUrls.first}$path';
    final data = parse(await _fetch(url, post: post));
    _cache[key] = _Cached(DateTime.now(), data);
    return data;
  }

  Future<List<WcoLink>> popular() =>
      _listed('popular', '/', parseSidebarTitles);
  Future<List<WcoLink>> latest() => _listed(
        'latest',
        '/last-50-recent-release',
        parseRecentReleases,
        ttl: const Duration(minutes: 30),
      );
  Future<List<WcoLink>> cartoons() =>
      _listed('cartoons', '/cartoon-list', parseDdmccList);
  Future<List<WcoLink>> dubbedAnime() =>
      _listed('dubbed', '/dubbed-anime-list', parseDdmccList);
  Future<List<WcoLink>> movies() =>
      _listed('movies', '/movie-list', parseDdmccList);
  Future<List<WcoLink>> ova() => _listed('ova', '/ova-list', parseDdmccList);
  Future<List<WcoLink>> genres() =>
      _listed('genres', '/search-by-genre', parseDdmccList);
  Future<List<WcoLink>> byGenre(String slug) =>
      _listed('genre:$slug', '/search-by-genre/$slug', parseDdmccList);

  Future<List<WcoLink>> search(String q, {String type = 'series'}) => _listed(
        'search:$type:$q',
        '${wcoflixBaseUrls.first}/search',
        parseSearchResults,
        ttl: const Duration(minutes: 10),
        post: {'catara': q, 'konuara': type},
      );

  Future<WcoSeries> seriesDetail(String url) async {
    final hit = _seriesCache[url];
    if (hit != null) return hit;
    final s = parseSeriesPage(await _fetch(url), seriesSlugFromUrl(url));
    _seriesCache[url] = s;
    return s;
  }
}
