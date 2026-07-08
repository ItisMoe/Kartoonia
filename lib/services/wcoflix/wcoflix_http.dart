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
/// On Android it routes through the native `kartoonia/net` channel, which pins
/// the handshake to **TLS 1.2** — the WCOFlix mirrors sit behind a Cloudflare
/// managed challenge that 403s a default TLS-1.3 client (which is what Dart's
/// `dart:io` HttpClient negotiates, with no way to change it). Forcing TLS 1.2
/// reproduces the fingerprint the WatchNixtoons2 Kodi addon uses to get through.
///
/// Everywhere else (tests, desktop tooling) it transparently falls back to the
/// plain `http` package so the same call sites work with no native side.
class WcoflixHttp {
  WcoflixHttp._();
  static final WcoflixHttp instance = WcoflixHttp._();

  static const _channel = MethodChannel('kartoonia/net');
  final http.Client _fallback = http.Client();

  /// Whether the native TLS-1.2 channel is available (Android only). Cached
  /// after the first probe; a MissingPluginException flips it off for good.
  bool _nativeOk = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<WcoResponse> get(String url, {Map<String, String>? headers}) =>
      _send('get', url, headers: headers);

  Future<WcoResponse> post(String url,
          {Map<String, String>? headers, String? body}) =>
      _send('post', url, headers: headers, body: body);

  Future<WcoResponse> _send(String method, String url,
      {Map<String, String>? headers, String? body}) async {
    if (_nativeOk) {
      try {
        final res = await _channel.invokeMapMethod<String, dynamic>(method, {
          'url': url,
          'headers': headers ?? const <String, String>{},
          if (body != null) 'body': body,
          'timeoutMs': 15000,
        });
        if (res != null) {
          return WcoResponse((res['status'] as int?) ?? 0,
              (res['body'] as String?) ?? '');
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
