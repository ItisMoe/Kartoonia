import 'wcoflix_config.dart';
import 'wcoflix_quality.dart';

/// Pure stream-source parsers for the WCOFlix player, mirroring the current
/// WatchNixtoons2 (kodi19 v0.25) resolver — all pure HTTP, no browser. The
/// episode page holds a `*-js-N` player iframe (usually the wcostream
/// `index.php` ad-gate embed); the resolver swaps it to `video-js-old.php` (see
/// wcoflix_resolver.dart) and the resulting player HTML yields either a getvid
/// `$.getJSON` link (enc/hd/fhd tokens) or a plain HLS `<source>`.

/// The player iframe `src` on an episode page. Two generations of markup:
///  - legacy: `<iframe id="xxx-js-N" src=...>` (cizgi-js-0 / anime-js-0);
///  - 2026-07: the id no longer follows `*-js-N` (e.g.
///    `frameNewcizgifilmuploads0`), so fall back to ANY iframe whose src is the
///    wco embed player (`.../inc/embed/...`). The src match is what actually
///    identifies the player — other iframes on the page (login checker, ads)
///    never point there. Null when no player frame exists.
final _reJsIframe = RegExp(
  r'<iframe\s*(?:rel="nofollow")?\s*id="[a-zA-Z]+-js-[0-9]+"\s*src="([^"]+)"',
  dotAll: true,
);
final _reEmbedSrcIframe = RegExp(
  r'<iframe[^>]*\ssrc="([^"]*/inc/embed/[^"]+)"',
  dotAll: true,
);
String? pickEmbedIframe(String episodeHtml) =>
    _reJsIframe.firstMatch(episodeHtml)?.group(1) ??
    _reEmbedSrcIframe.firstMatch(episodeHtml)?.group(1);

/// From the `video-js-old.php` player HTML, the absolute getvidlink JSON URL to
/// call (with the `X-Requested-With` header). Handles both the current
/// `getRedirectedUrl(videoUrl)` shape (`$.getJSON("<path>")` + `&json`) and the
/// legacy inline `/inc/embed/getvidlink...` shape. Null when neither is present.
String? getvidLinkUrl(String playerHtml) {
  if (playerHtml.contains('getRedirectedUrl(videoUrl)')) {
    final m = RegExp(r'\$\.getJSON\("([^"]+)"').firstMatch(playerHtml);
    if (m != null) {
      final u = m.group(1)!;
      return '$kWcoflixEmbedHost/${u.startsWith('/') ? u.substring(1) : u}&json';
    }
  }
  final m = RegExp(r'"(/inc/embed/getvidlink[^"]+)').firstMatch(playerHtml);
  if (m != null) return '$kWcoflixEmbedHost${m.group(1)}';
  return null;
}

/// A plain HLS `<source src="...m3u8">` (or `getRedirectedUrl("...")`) in the
/// player HTML, for the non-getvid embeds. Null when the player is getvid-based.
String? hlsSourceUrl(String playerHtml) {
  final s = RegExp(r'<source\s*src="([^"]+\.m3u8[^"]*)"').firstMatch(playerHtml);
  if (s != null) return s.group(1);
  final g = RegExp(r'getRedirectedUrl\("([^"]+\.m3u8[^"]*)')
      .firstMatch(playerHtml);
  return g?.group(1);
}

/// One playable HLS variant + its (optional) separate English audio rendition.
class HlsVariant {
  final WcoQuality quality;
  final String url;
  final String? audioUrl;
  const HlsVariant(this.quality, this.url, this.audioUrl);
}

String _resolve(String ref, String base) {
  if (ref.startsWith('http')) return ref;
  final root = base.substring(0, base.lastIndexOf('/'));
  return '$root/$ref';
}

/// Parse an HLS master: one [HlsVariant] per `#EXT-X-STREAM-INF` whose
/// RESOLUTION height is 576/720/1080, attaching the English audio rendition
/// URI. URIs are resolved absolute against [masterUrl].
List<HlsVariant> parseHlsMaster(String masterText, String masterUrl) {
  final lines = masterText.split('\n').map((l) => l.trim()).toList();
  String? engAudio;
  for (final l in lines) {
    if (l.startsWith('#EXT-X-MEDIA:TYPE=AUDIO') && l.contains('LANGUAGE="eng')) {
      final u = RegExp(r'URI="([^"]+)"').firstMatch(l)?.group(1);
      if (u != null) engAudio = _resolve(u, masterUrl);
    }
  }
  final out = <HlsVariant>[];
  for (var i = 0; i < lines.length; i++) {
    if (!lines[i].startsWith('#EXT-X-STREAM-INF')) continue;
    for (final q in WcoQuality.values) {
      if (lines[i].contains('x${q.resolution}')) {
        final uri = (i + 1 < lines.length) ? lines[i + 1].trim() : '';
        if (uri.isNotEmpty && !uri.startsWith('#')) {
          out.add(HlsVariant(q, _resolve(uri, masterUrl), engAudio));
        }
      }
    }
  }
  return out;
}

/// Build the per-quality getvid URLs from a getvidlink JSON response
/// (`{server, enc, hd, fhd, cdn}`): `server/getvid?evid=<token>`.
Map<WcoQuality, String> parseGetvidJson(Map<String, dynamic> json) {
  final server = (json['server'] as String?)?.trimRight() ?? '';
  final out = <WcoQuality, String>{};
  for (final q in WcoQuality.values) {
    final token = json[q.token] as String?;
    if (server.isNotEmpty && token != null && token.isNotEmpty) {
      out[q] = '$server/getvid?evid=$token';
    }
  }
  return out;
}
