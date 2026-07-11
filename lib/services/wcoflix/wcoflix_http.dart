import 'dart:async';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform, kIsWeb;
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// One HTTP response: status + decoded body text.
class WcoResponse {
  final int status;
  final String body;
  const WcoResponse(this.status, this.body);
  bool get ok => status >= 200 && status < 400;
}

/// HTTP for the WCOFlix live paths (catalog, search, playback resolve).
///
/// The WCOFlix mirrors sit behind a Cloudflare managed challenge. Which client
/// fingerprint Cloudflare trusts is NOT stable over time: it used to 403 the
/// default TLS-1.3 client and let a forced-TLS-1.2 one through (the reason for
/// the native `kartoonia/net` channel), but as of 2026-07 it has flipped — it
/// now challenges the forced-TLS-1.2 fingerprint while the plain Dart HTTP stack
/// passes on the live `wcofun.net` mirror.
///
/// So this tries BOTH transports and returns whichever actually clears the
/// challenge: the native TLS-1.2 channel first (Android), then the plain `http`
/// client whenever the native result is empty or a Cloudflare challenge page.
/// Non-Android (tests, desktop tooling) uses the plain client directly. This
/// makes playback robust to Cloudflare flipping its rules again.
///
/// EXCEPTION — the playback embed hosts (`embed.wcostream.com` and the
/// `*.wcostream.com` getvid edges) are NOT Cloudflare-challenged, but they DO
/// run the site's anti-bot/anti-adblock scoring, and a flagged ad-verify
/// handshake is punished with getvid tokens that stream a DECOY video: real
/// audio under deliberately scrambled video (shifting solid colors). That
/// matched the Everything-mode symptom on a real TV box exactly — the picture
/// stayed scrambled under software, hardware AND copy-back decoding, which
/// exonerates the decoder and means the received bitstream itself was garbage.
/// The same resolve flow through the PLAIN Dart client (the desktop probe)
/// produced tokens that played clean, so wcostream.com requests go through the
/// plain client FIRST (the fingerprint verified to pass), with the native
/// channel kept only as a fallback if that transport ever starts failing.
class WcoflixHttp {
  WcoflixHttp._();
  static final WcoflixHttp instance = WcoflixHttp._();

  static const _channel = MethodChannel('kartoonia/net');
  final http.Client _fallback = http.Client();

  /// Whether the native TLS-1.2 channel is available (Android only). Cached
  /// after the first probe; a MissingPluginException flips it off for good.
  bool _nativeOk = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// A Cloudflare/interstitial challenge instead of real content — the signal
  /// that this transport did NOT clear and the other should be tried.
  static bool _isChallenge(String body) =>
      body.contains('Just a moment') ||
      body.contains('cf-browser-verification') ||
      body.contains('Attention Required');

  Future<WcoResponse> get(String url, {Map<String, String>? headers}) =>
      _send('get', url, headers: headers);

  Future<WcoResponse> post(String url,
          {Map<String, String>? headers, String? body}) =>
      _send('post', url, headers: headers, body: body);

  /// Whether [url] targets the playback embed/CDN host family, where the
  /// anti-bot scoring (not Cloudflare) picks the transport order — see the
  /// class doc's decoy-stream note.
  static bool _isEmbedHost(String url) {
    final host = Uri.tryParse(url)?.host ?? '';
    return host == 'wcostream.com' || host.endsWith('.wcostream.com');
  }

  Future<WcoResponse> _send(String method, String url,
      {Map<String, String>? headers, String? body}) async {
    if (_isEmbedHost(url)) {
      final plain = await _fallbackSend(method, url, headers: headers, body: body);
      // 404 is a REAL answer here (e.g. probing a dead getvid variant) — only
      // a transport-level failure or a challenge page warrants the native retry.
      if (plain.status != 0 && !_isChallenge(plain.body)) return plain;
    }
    if (_nativeOk) {
      try {
        final res = await _channel.invokeMapMethod<String, dynamic>(method, {
          'url': url,
          'headers': headers ?? const <String, String>{},
          if (body != null) 'body': body,
          'timeoutMs': 15000,
        });
        if (res != null) {
          final native = WcoResponse((res['status'] as int?) ?? 0,
              (res['body'] as String?) ?? '');
          // Fall through to the plain client only when the native
          // (forced-TLS-1.2) result looks CHALLENGED or FAILED — a Cloudflare
          // interstitial, a challenge status, or a dead response. A normal
          // reply (incl. a legitimately empty 200 like `ad-verify`) is used as
          // is, so non-walled embed requests aren't needlessly sent twice.
          final challenged = _isChallenge(native.body) ||
              native.status == 0 ||
              native.status == 403 ||
              native.status == 503;
          if (!challenged) return native;
        }
      } on MissingPluginException {
        _nativeOk = false; // no native side (e.g. tests) — use fallback forever
      } catch (_) {
        // A transient native failure: fall through to the plain client once.
      }
    }
    return _fallbackSend(method, url, headers: headers, body: body);
  }

  Future<WcoResponse> _fallbackSend(String method, String url,
      {Map<String, String>? headers, String? body}) async {
    try {
      final uri = Uri.parse(url);
      final res = method == 'post'
          ? await _fallback
              .post(uri, headers: headers, body: body)
              .timeout(const Duration(seconds: 15))
          : await _fallback
              .get(uri, headers: headers)
              .timeout(const Duration(seconds: 15));
      return WcoResponse(res.statusCode, res.body);
    } catch (_) {
      return const WcoResponse(0, '');
    }
  }
}
