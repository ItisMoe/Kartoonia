import 'dart:convert';
import 'dart:isolate';
import 'package:flutter/services.dart' show rootBundle;
import '../../models/content_item.dart';
import 'wcoflix_config.dart';
import 'wcoflix_domain.dart';
import 'wcoflix_http.dart';
import 'wcoflix_parsers.dart';

typedef WcoFetch = Future<String> Function(String url,
    {Map<String, String>? post});

/// Live WCOFlix catalog access with a **bundled snapshot fallback**. Home/browse
/// rows read [snapshot] instantly (so Everything mode always shows titles, even
/// when the live site is slow, blocked by a Cloudflare challenge, or offline),
/// then swap to fresh data once a background [fetchLive] completes. Search and
/// series detail are live-only (with the same soft-fail behavior).
///
/// One bundled catalog record used for local search / ranking.
class _WcoItem {
  final String path;
  final String title;
  final TmdbData tmdb;
  final String type; // 'tv' | 'movie' | ''

  /// Precomputed lowercase "title + English + original title" haystack.
  /// [WcoflixCatalog.searchLocal] runs per keystroke over 8k+ items; building
  /// this string 8k times per keypress was measurable jank on weak boxes.
  final String hay;
  const _WcoItem(this.path, this.title, this.tmdb, this.type, this.hay);
}

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

  /// Bundled TMDB art/popularity, keyed by series slug. Loaded once from
  /// `assets/wcoflix_catalog.json` (see tool/wcoflix_enrich.dart).
  Map<String, TmdbData>? _art;

  /// Every bundled item as a searchable record: (path, title, TMDB), ordered by
  /// fame. Powers the instant LOCAL search (the live POST /search is Cloudflare-
  /// walled, and this covers the whole enriched catalog anyway).
  List<_WcoItem>? _items;

  static Future<String> _defaultFetch(String url,
      {Map<String, String>? post}) async {
    // Rehome the request onto whichever mirror is actually serving content, then
    // go through the native TLS-1.2 client so Cloudflare doesn't 403 us.
    final base = await WcoflixDomain.activeBase(WcoflixDomain.defaultGet);
    final target = WcoflixDomain.rewrite(url, base);
    final headers = {
      'User-Agent': kWcoflixUserAgent,
      'Referer': '$base/',
      'Accept-Language': 'en-US,en;q=0.9',
    };
    final res = post == null
        ? await WcoflixHttp.instance.get(target, headers: headers)
        : await WcoflixHttp.instance.post(target,
            headers: {
              ...headers,
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: post.entries
                .map((e) =>
                    '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
                .join('&'));
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
  // The snapshot stores each item's URL as a bare, mirror-agnostic path (e.g.
  // `/anime/one-piece`); it is rehomed onto the live mirror by [_defaultFetch]
  // / the resolver at fetch time. Older absolute-URL snapshots also load fine
  // (rewrite leaves live-mirror URLs alone).
  Future<Map<String, List<WcoLink>>> _loadSnapshot() async {
    try {
      final raw = await _loadAsset('assets/wcoflix_snapshot.json');
      // Decode + build off the UI isolate (models come back via Isolate.exit).
      return await Isolate.run(() => _parseSnapshot(raw));
    } catch (_) {
      return {};
    }
  }

  static Map<String, List<WcoLink>> _parseSnapshot(String raw) {
    final m = jsonDecode(raw) as Map<String, dynamic>;
    return m.map((k, v) => MapEntry(k, [
          for (final e in (v as List))
            WcoLink((e as Map)['u'] as String, e['t'] as String,
                thumb: e['th'] as String?),
        ]));
  }

  /// The bundled snapshot list for [key] (empty if the asset is missing/bad).
  Future<List<WcoLink>> snapshot(String key) async {
    _snap ??= await _loadSnapshot();
    return _snap![key] ?? const [];
  }

  // ---- TMDB art / popularity (bundled) ----
  Future<void> _loadArt() async {
    if (_art != null) return;
    var art = const <String, TmdbData>{};
    var items = const <_WcoItem>[];
    try {
      final raw = await _loadAsset('assets/wcoflix_catalog.json');
      // 7+ MB of JSON → thousands of TmdbData objects: decoded and built OFF
      // the UI isolate (this runs while the Everything Home is on screen).
      (art, items) = await Isolate.run(() => _parseArt(raw));
    } catch (_) {
      // leave art empty — cards fall back to scraped thumbnails
    }
    _art = art;
    _items = items;
  }

  static (Map<String, TmdbData>, List<_WcoItem>) _parseArt(String raw) {
    final art = <String, TmdbData>{};
    final ranked = <(_WcoItem, int)>[]; // (item, voteCount)
    final items = (jsonDecode(raw) as Map<String, dynamic>)['items']
        as Map<String, dynamic>;
    items.forEach((path, v) {
      final tm = (v as Map)['tmdb'];
      if (tm is! Map) return;
      final j = tm.cast<String, dynamic>();
      // The enricher nests the plot under `en.overview`; TmdbData reads
      // `overview_en` — bridge it so detail plots populate.
      final en = j['en'];
      if (en is Map && en['overview'] != null) {
        j['overview_en'] = en['overview'];
      }
      final tmdb = TmdbData.fromJson(j);
      art[seriesSlugFromUrl(path)] = tmdb;
      final title = (tmdb.enTitle?.isNotEmpty == true)
          ? tmdb.enTitle!
          : (v['t'] as String? ?? '');
      final type = (j['type'] as String?) ?? '';
      final hay =
          '$title ${tmdb.enTitle ?? ''} ${tmdb.originalTitle ?? ''}'
              .toLowerCase();
      ranked.add((
        _WcoItem(path, title, tmdb, type, hay),
        (j['vote_count'] as num?)?.toInt() ?? 0
      ));
    });
    ranked.sort((a, b) => b.$2.compareTo(a.$2));
    return (art, [for (final r in ranked) r.$1]);
  }

  /// Instant LOCAL search over the bundled enriched catalog (title + English +
  /// original title). Fame-ordered because [_items] is. Case/space-insensitive
  /// substring match; a multi-word query matches when every word is present.
  /// This replaces the live POST /search, which is Cloudflare-walled.
  Future<List<WcoLink>> searchLocal(String query, {int limit = 120}) async {
    await ensureArt();
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return const [];
    final words = q.split(RegExp(r'\s+'));
    final out = <WcoLink>[];
    for (final it in _items ?? const <_WcoItem>[]) {
      final hay = it.hay; // precomputed at parse time — hot per-keystroke path
      if (words.every(hay.contains)) {
        out.add(WcoLink(it.path, it.title, thumb: it.tmdb.posterUrlW500));
        if (out.length >= limit) break;
      }
    }
    return out;
  }

  /// The bundled TMDB data for a series [url] (poster/backdrop/popularity), or
  /// null when the title wasn't matched. Call [ensureArt] first.
  TmdbData? artFor(String url) => _art?[seriesSlugFromUrl(url)];

  /// Load the bundled art map once (idempotent). Safe to await before building
  /// cards; a missing/bad asset just leaves art empty.
  Future<void> ensureArt() => _loadArt();

  /// Series links for the most TMDB-famous titles (vote_count desc), as
  /// `/anime/<slug>` paths — the pool the Everything Home ranks its rows/hero
  /// from. [withBackdrop] keeps only titles that have a backdrop (for the hero).
  Future<List<WcoLink>> famousPool(
      {int limit = 200, bool withBackdrop = false, String? type}) async {
    await ensureArt();
    final out = <WcoLink>[];
    // Dedupe by TMDB id AND by title so the same show mapped to two wco paths
    // (e.g. dub + sub, or a re-upload) never appears twice in a Home row.
    final seenId = <int>{};
    final seenTitle = <String>{};
    for (final it in _items ?? const <_WcoItem>[]) {
      final t = it.tmdb;
      if (type != null && it.type != type) continue;
      if (withBackdrop && (t.backdropUrl == null || t.backdropUrl!.isEmpty)) {
        continue;
      }
      final title = it.title;
      if (title.isEmpty) continue;
      final id = t.tmdbId;
      if (id != null && !seenId.add(id)) continue;
      if (!seenTitle.add(title.toLowerCase())) continue;
      // Preserve the ORIGINAL item path (movies live at root, series under
      // /anime/…) so detail/playback fetch the right page.
      out.add(WcoLink(it.path, title, thumb: t.posterUrlW500));
      if (out.length >= limit) break;
    }
    return out;
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
    final html = await _fetch(url);
    // A Cloudflare challenge (or an empty/redirect-stub body) has no episodes.
    // Do NOT cache it — otherwise a transient block poisons this session and the
    // show renders as a single episode with no seasons. Throw so the provider
    // shows a retryable error and the next visit re-fetches.
    if (html.isEmpty || _blocked(html)) {
      throw StateError('wcoflix series page blocked or empty: $url');
    }
    final s = parseSeriesPage(html, seriesSlugFromUrl(url));
    // A real page that parsed zero episodes is likewise not worth caching (the
    // slug may be wrong, or the markup changed) — let a later visit retry.
    if (s.episodes.isEmpty) return s;
    _seriesCache[url] = s;
    return s;
  }
}
