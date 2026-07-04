import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../navigation.dart';
import '../services/update_service.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';

/// Transparent wrapper that, once per app launch, checks GitHub Releases for a
/// newer build and (if found and not skipped) prompts the user to update. It
/// sits above the Navigator in [MaterialApp.builder] so it survives the splash →
/// home route swap; the dialog is shown via [appNavigatorKey] on the live route.
///
/// Updating installs the release APK over the current app (same signing key),
/// which Android upgrades in place — watchlist, progress and prefs are kept.
class UpdateGate extends ConsumerStatefulWidget {
  final Widget child;
  const UpdateGate({super.key, required this.child});

  @override
  ConsumerState<UpdateGate> createState() => _UpdateGateState();
}

class _UpdateGateState extends ConsumerState<UpdateGate> {
  // App-session guard: check at most once, even though the builder rebuilds.
  static bool _checked = false;

  @override
  void initState() {
    super.initState();
    if (_checked) return;
    _checked = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Let the splash route to the home shell first so the dialog lands on it.
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) await _maybePrompt();
    });
  }

  Future<void> _maybePrompt() async {
    final release = await ref.read(updateServiceProvider).checkForUpdate();
    if (release == null || !mounted) return;
    final storage = ref.read(storageProvider);
    if (storage.getSkippedUpdate() == release.version) return;

    final ctx = appNavigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    final t = ref.read(stringsProvider);

    await showDialog<void>(
      context: ctx,
      barrierDismissible: true,
      builder: (dctx) => _UpdateDialog(
        release: release,
        t: t,
        onUpdate: () {
          Navigator.of(dctx).pop();
          _downloadAndInstall(release);
        },
        onLater: () => Navigator.of(dctx).pop(),
        onSkip: () {
          storage.setSkippedUpdate(release.version);
          Navigator.of(dctx).pop();
        },
      ),
    );
  }

  static const _installChannel = MethodChannel('kartoonia/reco');

  /// Download the release APK in-app (progress dialog) and hand it to the
  /// system package installer. Any failure — no APK asset, network error,
  /// installer refused — falls back to opening the download URL in a browser
  /// (the old behavior, still right on phones).
  Future<void> _downloadAndInstall(AppRelease release) async {
    final apkUrl = release.apkUrl;
    final ctx = appNavigatorKey.currentContext;
    if (apkUrl == null || ctx == null || !ctx.mounted) {
      launchUrl(Uri.parse(release.downloadUrl),
          mode: LaunchMode.externalApplication);
      return;
    }

    final t = ref.read(stringsProvider);
    final progress = ValueNotifier<double?>(null);
    var dialogUp = true;
    showDialog<void>(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => _DownloadDialog(progress: progress, t: t),
    ).whenComplete(() => dialogUp = false);
    void closeDialog() {
      if (dialogUp) appNavigatorKey.currentState?.pop();
    }

    final client = http.Client();
    try {
      final resp =
          await client.send(http.Request('GET', Uri.parse(apkUrl)));
      if (resp.statusCode != 200) throw Exception('HTTP ${resp.statusCode}');
      final file = File(
          '${(await getTemporaryDirectory()).path}/kartoonia-update.apk');
      final sink = file.openWrite();
      final total = resp.contentLength ?? 0;
      var got = 0;
      try {
        await for (final chunk in resp.stream) {
          sink.add(chunk);
          got += chunk.length;
          if (total > 0) progress.value = got / total;
        }
      } finally {
        await sink.close();
      }
      closeDialog();
      final ok =
          await _installChannel.invokeMethod('installApk', {'path': file.path});
      if (ok != true) throw Exception('installer refused');
    } catch (_) {
      closeDialog();
      launchUrl(Uri.parse(release.downloadUrl),
          mode: LaunchMode.externalApplication);
    } finally {
      client.close();
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Modal download progress for the in-app update. Indeterminate until the
/// content length is known, then a percentage bar.
class _DownloadDialog extends StatelessWidget {
  final ValueNotifier<double?> progress;
  final Map<String, String> t;
  const _DownloadDialog({required this.progress, required this.t});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.bg2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: [
        const Icon(Icons.download, color: AppColors.primary2, size: 26),
        const SizedBox(width: 10),
        Expanded(
          child: Text(t['update_downloading'] ?? 'Downloading update…',
              style: const TextStyle(
                  fontWeight: FontWeight.w900, color: AppColors.ink)),
        ),
      ]),
      content: ValueListenableBuilder<double?>(
        valueListenable: progress,
        builder: (_, v, _) => Column(mainAxisSize: MainAxisSize.min, children: [
          LinearProgressIndicator(
            value: v,
            minHeight: 8,
            borderRadius: BorderRadius.circular(4),
            backgroundColor: const Color(0x33FFFFFF),
            valueColor: const AlwaysStoppedAnimation(AppColors.primary),
          ),
          if (v != null) ...[
            const SizedBox(height: 10),
            Text('${(v * 100).round()}%',
                style: const TextStyle(
                    fontWeight: FontWeight.w800, color: AppColors.inkSoft)),
          ],
        ]),
      ),
    );
  }
}

class _UpdateDialog extends StatelessWidget {
  final AppRelease release;
  final Map<String, String> t;
  final VoidCallback onUpdate;
  final VoidCallback onLater;
  final VoidCallback onSkip;
  const _UpdateDialog({
    required this.release,
    required this.t,
    required this.onUpdate,
    required this.onLater,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final notes = release.notes;
    return AlertDialog(
      backgroundColor: AppColors.bg2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: [
        const Icon(Icons.system_update, color: AppColors.primary2, size: 26),
        const SizedBox(width: 10),
        Expanded(
          child: Text(t['update_title'] ?? 'Update available',
              style: const TextStyle(
                  fontWeight: FontWeight.w900, color: AppColors.ink)),
        ),
      ]),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${t['update_message'] ?? 'A new version is ready'} — ${release.tag}',
            style: const TextStyle(
                fontWeight: FontWeight.w700, color: AppColors.inkSoft),
          ),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: SingleChildScrollView(
                child: Text(notes,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.inkMute)),
              ),
            ),
          ],
        ],
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
            onPressed: onSkip,
            child: Text(t['update_skip'] ?? 'Skip',
                style: const TextStyle(color: AppColors.inkMute))),
        Row(mainAxisSize: MainAxisSize.min, children: [
          TextButton(
              onPressed: onLater,
              child: Text(t['update_later'] ?? 'Later',
                  style: const TextStyle(color: AppColors.inkSoft))),
          const SizedBox(width: 6),
          FilledButton(
            onPressed: onUpdate,
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: Text(t['update_now'] ?? 'Update',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        ]),
      ],
    );
  }
}
