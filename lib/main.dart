import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'app.dart';
import 'services/catalog_service.dart';
import 'services/storage_service.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize libmpv once for the process (required before any Player is built).
  MediaKit.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Detect the form factor up front so the right UI (TV D-pad canvas vs. the
  // portrait touch phone UI) and the right orientation lock are chosen before
  // the first frame. Defaults to phone if the native check is unavailable.
  final isTv = await _detectTv();
  await SystemChrome.setPreferredOrientations(
    isTv
        ? const [
            DeviceOrientation.landscapeLeft,
            DeviceOrientation.landscapeRight,
          ]
        // Phones browse in portrait (Netflix-style); the player flips to
        // landscape on its own while it is open.
        : const [DeviceOrientation.portraitUp],
  );

  // Load services before the first frame; the branded splash covers it.
  final storage = await StorageService.create();
  final catalog = await CatalogService.load(storage.getCatalogSource());

  runApp(
    ProviderScope(
      overrides: [
        isTvProvider.overrideWithValue(isTv),
        storageProvider.overrideWithValue(storage),
        catalogProvider.overrideWithValue(catalog),
      ],
      child: const KartooniaApp(),
    ),
  );
}

/// Ask the host whether this is a leanback (TV) device. Reuses the existing
/// recommendations channel. Any failure → treat as a phone (touch UI).
Future<bool> _detectTv() async {
  try {
    const channel = MethodChannel('kartoonia/reco');
    return await channel.invokeMethod<bool>('isTelevision') ?? false;
  } catch (_) {
    return false;
  }
}
