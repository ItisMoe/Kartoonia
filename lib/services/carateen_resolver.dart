import 'dart:convert';
import 'dart:typed_data';
import 'package:encrypt/encrypt.dart';
import 'package:http/http.dart' as http;

/// Resolves a carateen.tv episode `play_url` into a playable HLS `.m3u8`.
///
/// carateen's API responses are AES-256-CBC encrypted (`{iv, encryptedData}`)
/// with a single static key baked into the site bundle. The per-play source
/// endpoint `GET /api/episode?episodeId=&showId=` returns `{streamUrl,…}`; the
/// `streamUrl` is a master HLS playlist on the CDN that plays anonymously with
/// just a Referer + User-Agent (no signing/token for guest playback). We do the
/// exact fetch+decrypt the site's axios interceptor does — no browser, no auth.
class CarateenStream {
  final String server;
  final String streamUrl;
  final Map<String, String> headers;
  const CarateenStream({
    required this.server,
    required this.streamUrl,
    required this.headers,
  });
}

class CarateenResolveException implements Exception {
  final String message;
  const CarateenResolveException(this.message);
  @override
  String toString() => 'CarateenResolveException: $message';
}

const String _kBase = 'https://carateen.tv';
const String _kUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

/// The AES-256 key is the literal UTF-8 string the bundle hard-codes. IV is the
/// hex-decoded `iv` field; ciphertext is the hex-decoded `encryptedData`.
final Key _kKey = Key.fromUtf8('7annaba3l_loves_crypto_safe_key!');
final Encrypter _kEnc =
    Encrypter(AES(_kKey, mode: AESMode.cbc, padding: 'PKCS7'));

/// Headers every carateen CDN request needs (the media manifest AND segments —
/// media_kit forwards these to libmpv for each request).
const Map<String, String> kCarateenMediaHeaders = {
  'User-Agent': _kUserAgent,
  'Referer': '$_kBase/',
};

List<int> _hexDecode(String hex) {
  final out = List<int>.filled(hex.length ~/ 2, 0);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// Decrypt a carateen `{iv, encryptedData}` envelope back to its JSON value.
/// Returns the already-plain body unchanged (defensive — some endpoints or a
/// future server change might stop encrypting).
Object? decryptCarateen(Object? body) {
  if (body is! Map) return body;
  final iv = body['iv'];
  final enc = body['encryptedData'];
  if (iv is! String || enc is! String) return body;
  final plain = _kEnc.decrypt(
    Encrypted.fromBase16(enc),
    iv: IV(Uint8List.fromList(_hexDecode(iv))),
  );
  return jsonDecode(plain);
}

/// One variant row of an HLS master playlist (`#EXT-X-STREAM-INF`).
class HlsVariant {
  final String name; // '720p'
  final int height;
  final int bandwidth;
  final String url; // absolute
  const HlsVariant({
    required this.name,
    required this.height,
    required this.bandwidth,
    required this.url,
  });
}

final RegExp _reStreamInf = RegExp(r'^#EXT-X-STREAM-INF:(.*)$');
final RegExp _reBandwidth = RegExp(r'BANDWIDTH=(\d+)');
final RegExp _reResolution = RegExp(r'RESOLUTION=\d+x(\d+)');
final RegExp _reName = RegExp(r'NAME="([^"]+)"');

/// Extract the variant entries of an HLS *master* playlist, resolving each
/// variant URI against [base]. Returns an empty list for media playlists
/// (no `#EXT-X-STREAM-INF` lines), which callers treat as "not a master".
List<HlsVariant> parseHlsMasterVariants(String playlist, Uri base) {
  final out = <HlsVariant>[];
  String? pendingAttrs;
  for (final raw in playlist.split('\n')) {
    final line = raw.trim();
    if (line.isEmpty) continue;
    final m = _reStreamInf.firstMatch(line);
    if (m != null) {
      pendingAttrs = m.group(1);
      continue;
    }
    if (line.startsWith('#') || pendingAttrs == null) continue;
    final attrs = pendingAttrs;
    pendingAttrs = null;
    final bandwidth =
        int.tryParse(_reBandwidth.firstMatch(attrs)?.group(1) ?? '') ?? 0;
    final height =
        int.tryParse(_reResolution.firstMatch(attrs)?.group(1) ?? '') ?? 0;
    final name = _reName.firstMatch(attrs)?.group(1) ??
        (height > 0 ? '${height}p' : '${bandwidth ~/ 1000}k');
    out.add(HlsVariant(
      name: name,
      height: height,
      bandwidth: bandwidth,
      url: base.resolve(line).toString(),
    ));
  }
  return out;
}

/// Order variants 720p-first, then the rest highest-first — the same rule the
/// WCOFlix resolver uses, so the player's server picker doubles as a
/// resolution picker and the DEFAULT pick is the bandwidth-safe 720p (the
/// carateen CDN can't reliably sustain its 5 Mbps 1080p variant).
List<HlsVariant> orderCarateenVariants(List<HlsVariant> variants) {
  if (variants.isEmpty) return variants;
  final atOrBelow = variants.where((v) => v.height <= 720).toList();
  final preferred = (atOrBelow.isEmpty ? variants.toList() : atOrBelow)
    ..sort((a, b) => b.height.compareTo(a.height));
  final want = preferred.first;
  final sorted = variants.toList()
    ..sort((a, b) {
      if (identical(a, want) && !identical(b, want)) return -1;
      if (identical(b, want) && !identical(a, want)) return 1;
      return b.height.compareTo(a.height);
    });
  return sorted;
}

/// Parse `showId`/`episodeId` out of a `.../watch/<show>/<episode>` play_url.
/// Returns null when the URL isn't a carateen watch link.
({String showId, String episodeId})? parseCarateenPlayUrl(String playUrl) {
  final u = Uri.tryParse(playUrl);
  if (u == null) return null;
  final segs = u.pathSegments.where((s) => s.isNotEmpty).toList();
  final i = segs.indexOf('watch');
  if (i >= 0 && segs.length >= i + 3) {
    return (showId: segs[i + 1], episodeId: segs[i + 2]);
  }
  return null;
}

/// Resolve one carateen episode `play_url` to its playable HLS stream.
Future<List<CarateenStream>> resolveCarateen(String playUrl,
    {http.Client? client}) async {
  final ids = parseCarateenPlayUrl(playUrl);
  if (ids == null) {
    throw CarateenResolveException('not a carateen watch url: $playUrl');
  }
  final own = client == null;
  final c = client ?? http.Client();
  try {
    final uri = Uri.parse(
        '$_kBase/api/episode?episodeId=${ids.episodeId}&showId=${ids.showId}');
    final resp = await c.get(uri, headers: {
      'User-Agent': _kUserAgent,
      'X-Cartoony-Client': 'web-frontend-v1',
      'Accept': 'application/json',
      'Referer': '$_kBase/',
    });
    if (resp.statusCode != 200) {
      throw CarateenResolveException('HTTP ${resp.statusCode} for /api/episode');
    }
    final data = decryptCarateen(jsonDecode(utf8.decode(resp.bodyBytes)));
    if (data is! Map) {
      throw const CarateenResolveException('unexpected /api/episode payload');
    }
    final streamUrl = data['streamUrl'];
    if (streamUrl is! String || streamUrl.isEmpty) {
      throw const CarateenResolveException('no streamUrl in /api/episode');
    }
    // Expand the master playlist into one stream per resolution variant.
    // libmpv can't switch HLS variants mid-play (and `hls-bitrate=max` pins
    // the 5 Mbps 1080p one, which the CDN delivers slower than realtime), so
    // each variant becomes its own picker entry, bandwidth-safe 720p first.
    // Any failure here (host down, playlist shape change, already a media
    // playlist) falls back to the old single master-URL behavior.
    try {
      final master =
          await c.get(Uri.parse(streamUrl), headers: kCarateenMediaHeaders);
      if (master.statusCode == 200) {
        final variants = orderCarateenVariants(parseHlsMasterVariants(
            utf8.decode(master.bodyBytes), Uri.parse(streamUrl)));
        if (variants.length > 1) {
          return [
            for (final v in variants)
              CarateenStream(
                server: v.name,
                streamUrl: v.url,
                headers: kCarateenMediaHeaders,
              ),
          ];
        }
      }
    } catch (_) {
      // fall through to the master URL
    }
    return [
      CarateenStream(
        server: 'Carateen',
        streamUrl: streamUrl,
        headers: kCarateenMediaHeaders,
      ),
    ];
  } finally {
    if (own) c.close();
  }
}
