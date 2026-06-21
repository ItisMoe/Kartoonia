import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// A newer GitHub release than the one installed.
class AppRelease {
  /// Numeric version from the tag, e.g. "1.22.0" (the leading "v" is stripped).
  final String version;

  /// The raw tag, e.g. "v1.22.0".
  final String tag;

  /// Release notes (GitHub release body); may be empty.
  final String notes;

  /// Direct download URL of the attached `.apk` asset, when the release has one.
  /// Installing it over the current app (same signing key) updates in place and
  /// keeps all local data — watchlist, progress, prefs — intact.
  final String? apkUrl;

  /// The release web page — the fallback "Update" target when no APK is attached.
  final String pageUrl;

  const AppRelease({
    required this.version,
    required this.tag,
    required this.notes,
    required this.apkUrl,
    required this.pageUrl,
  });

  /// What "Update" opens: the APK asset if present, else the release page.
  String get downloadUrl => apkUrl ?? pageUrl;
}

/// Checks the project's GitHub Releases for a build newer than the installed
/// one. Read-only and best-effort: any network/parse failure (including the
/// common case of no *published* release yet — a bare git tag is not a release,
/// so the API 404s) resolves to `null` so the app never blocks or nags on error.
class UpdateService {
  static const _owner = 'ItisMoe';
  static const _repo = 'Kartoonia';
  static final Uri _latest =
      Uri.parse('https://api.github.com/repos/$_owner/$_repo/releases/latest');

  /// The latest release if it is newer than the running app, else `null`.
  Future<AppRelease?> checkForUpdate() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final resp = await http.get(
        _latest,
        headers: const {'Accept': 'application/vnd.github+json'},
      ).timeout(const Duration(seconds: 8));
      if (resp.statusCode != 200) return null;

      final j = jsonDecode(resp.body) as Map<String, dynamic>;
      if (j['draft'] == true || j['prerelease'] == true) return null;

      final tag = (j['tag_name'] as String?)?.trim() ?? '';
      final version = tag.replaceFirst(RegExp(r'^[vV]'), '');
      if (version.isEmpty || !_isNewer(version, info.version)) return null;

      String? apk;
      for (final a in (j['assets'] as List? ?? const [])) {
        final name = ((a as Map)['name'] as String? ?? '').toLowerCase();
        if (name.endsWith('.apk')) {
          apk = a['browser_download_url'] as String?;
          break;
        }
      }

      return AppRelease(
        version: version,
        tag: tag,
        notes: (j['body'] as String?)?.trim() ?? '',
        apkUrl: apk,
        pageUrl: (j['html_url'] as String?) ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  /// Dotted-numeric version compare: true when [remote] > [current]
  /// ("1.22.0" > "1.21.3"). Non-numeric/build-suffix parts are ignored; missing
  /// trailing parts count as 0, so "1.22" == "1.22.0".
  static bool _isNewer(String remote, String current) {
    final r = _parts(remote);
    final c = _parts(current);
    final n = r.length > c.length ? r.length : c.length;
    for (var i = 0; i < n; i++) {
      final a = i < r.length ? r[i] : 0;
      final b = i < c.length ? c[i] : 0;
      if (a != b) return a > b;
    }
    return false;
  }

  static List<int> _parts(String v) => v
      .split('+')
      .first
      .split('.')
      .map((p) => int.tryParse(RegExp(r'\d+').stringMatch(p) ?? '') ?? 0)
      .toList();
}
