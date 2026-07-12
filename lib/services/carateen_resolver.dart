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
