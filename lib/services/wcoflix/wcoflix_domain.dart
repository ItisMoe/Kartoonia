import 'package:http/http.dart' as http;
import 'wcoflix_config.dart';

/// Resolves which WCOFlix mirror is actually serving content and rewrites stale
/// links onto it.
///
/// WCOFlix renames domains often and fronts them with Cloudflare: the primary
/// `wcoflix.tv` currently answers every request with a `403 "Just a moment"`
/// challenge, while `wcofun.net` serves the real catalog. Bundled snapshot URLs
/// and links parsed from one mirror also embed whatever host was first in
/// [wcoflixBaseUrls] at scrape time, so before fetching ANY wcoflix page we
/// rewrite its origin to the mirror that currently works.
///
/// Playback embeds live on `embed.wcostream.com`, which is NOT a catalog mirror
/// — [rewrite] deliberately leaves non-mirror hosts untouched.
class WcoflixDomain {
  WcoflixDomain._();

  /// Every host that has served the WCOFlix catalog (current + historical), so
  /// links pointing at any of them can be rehomed onto the live mirror.
  static final Set<String> _mirrorHosts = {
    for (final b in wcoflixBaseUrls) Uri.parse(b).host,
    'wcoflix.tv',
    'www.wcoflix.tv',
    'wcofun.net',
    'www.wcofun.net',
    'wcofun.org',
    'www.wcofun.org',
  };

  static String? _active;
  static Future<String>? _probe;

  /// A challenge/interstitial page rather than real catalog HTML. Only these
  /// markers are reliable — the `/cdn-cgi/challenge-platform` script tag is on
  /// every Cloudflare-fronted page, including ones serving real content.
  static bool looksBlocked(String html) =>
      html.contains('Just a moment') ||
      html.contains('cf-browser-verification') ||
      html.contains('Attention Required');

  /// The origin (`https://host`) of the first base in [wcoflixBaseUrls] that
  /// returns real, non-challenge HTML. Cached for the session. If none pass
  /// (offline, all challenged), falls back to the first configured base so
  /// callers still produce absolute URLs.
  ///
  /// [get] is injectable so tests drive it without network.
  static Future<String> activeBase(
      Future<String> Function(String url) get) {
    if (_active != null) return Future.value(_active!);
    return _probe ??= _probeBases(get);
  }

  static Future<String> _probeBases(
      Future<String> Function(String url) get) async {
    for (final base in wcoflixBaseUrls) {
      try {
        final html = await get('$base/');
        if (html.isNotEmpty && !looksBlocked(html)) {
          _active = _origin(base);
          return _active!;
        }
      } catch (_) {
        // try the next mirror
      }
    }
    _active = _origin(wcoflixBaseUrls.first);
    _probe = null; // allow a later retry once connectivity returns
    return _active!;
  }

  /// Default network probe (real http), used by production callers.
  static final http.Client _client = http.Client();
  static Future<String> defaultGet(String url) async {
    final res = await _client.get(Uri.parse(url), headers: {
      'User-Agent': kWcoflixUserAgent,
      'Accept-Language': 'en-US,en;q=0.9',
    }).timeout(const Duration(seconds: 15));
    return res.body;
  }

  /// Rewrite [url]'s origin to [base] when its host is a known catalog mirror.
  /// Relative URLs are made absolute against [base]. Non-mirror hosts (e.g.
  /// `embed.wcostream.com`, CDN edges) pass through unchanged.
  static String rewrite(String url, String base) {
    final b = Uri.parse(base);
    if (url.startsWith('//')) url = '${b.scheme}:$url';
    final u = Uri.tryParse(url);
    if (u == null) return url;
    if (!u.hasScheme) {
      // relative path -> absolutize against the active base
      final path = url.startsWith('/') ? url : '/$url';
      return '${b.scheme}://${b.host}$path';
    }
    if (_mirrorHosts.contains(u.host) && u.host != b.host) {
      return u.replace(scheme: b.scheme, host: b.host, port: null).toString();
    }
    return url;
  }

  static String _origin(String base) {
    final u = Uri.parse(base);
    return '${u.scheme}://${u.host}';
  }

  /// Test seam: forget the cached mirror.
  static void resetForTest() {
    _active = null;
    _probe = null;
  }
}
