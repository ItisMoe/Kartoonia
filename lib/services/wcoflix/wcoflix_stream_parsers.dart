import 'wcoflix_quality.dart';

/// Pure stream-source parsers for the WCOFlix player. Two embed shapes exist:
/// the ad-gated "getvid" player (a `$.getJSON` returning enc/hd/fhd tokens) and
/// a plain HLS embed (`anime-js-1`). These functions cover the parts that can
/// be tested without a browser; the ad-gate itself is Phase 2 (WebView).

/// The player iframe on an episode page, tried by id in the order ZenDownloader
/// uses (`anime-js-0` → `anime-js-1` → `cizgi-js-0`). Returns the frame `src`,
/// or null when no known player frame exists.
String? pickEmbedIframe(String episodeHtml) {
  for (final id in ['anime-js-0', 'anime-js-1', 'cizgi-js-0']) {
    final m = RegExp('id="$id"[^>]*\\ssrc="([^"]+)"').firstMatch(episodeHtml) ??
        RegExp('src="([^"]+)"[^>]*\\sid="$id"').firstMatch(episodeHtml);
    if (m != null) return m.group(1);
  }
  return null;
}

/// True when the active frame is `anime-js-1` (the pure-HTTP HLS embed) and the
/// getvid frame `anime-js-0` is absent — anime-js-0 wins when both are present.
bool isM3u8Embed(String episodeHtml) {
  final hasM3u8 = RegExp(r'id="anime-js-1"').hasMatch(episodeHtml);
  if (!hasM3u8) return false;
  return !RegExp(r'id="anime-js-0"').hasMatch(episodeHtml);
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
