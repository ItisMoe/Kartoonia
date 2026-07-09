import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'app.dart';
import 'services/catalog_service.dart';
import 'services/catalog_updater.dart';
import 'services/device_perf.dart';
import 'services/storage_service.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize libmpv once for the process (required before any Player is built).
  MediaKit.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // A TV catalog scrolls past many posters/backdrops; lift the image cache
  // above the 100 MB / 1000-object default so freshly scrolled-away rows aren't
  // evicted and re-fetched the instant the user scrolls back — but size it to
  // the box. On a ~1 GB TV stick a 192 MB bitmap cache is a large slice of the
  // app's allowable footprint: it drives GC churn and invites the low-memory
  // killer, both of which read as "the whole app is laggy". Such boxes get a
  // smaller cache (an occasional re-decode beats memory pressure).
  final lowRam = await _isLowRamDevice();
  DevicePerf.lowSpec = lowRam;
  PaintingBinding.instance.imageCache
    ..maximumSizeBytes = (lowRam ? 96 : 192) << 20
    ..maximumSize = lowRam ? 800 : 1500;

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

  // Storage is quick (SharedPreferences); await it before the first frame.
  final storage = await StorageService.create();

  // The catalogs are NOT awaited: 45 MB of JSON takes many seconds to parse on
  // a low-end TV box, and the app used to sit on a dead native splash for all
  // of it. Instead the UI boots instantly against an empty catalog, the parse
  // runs in background isolates (see CatalogService.loadMergedInPlace), and
  // the branded splash waits on [catalogReadyProvider] before routing to Home.
  final catalog = CatalogService.empty();
  final catalogReady = Completer<void>();

  final container = ProviderContainer(
    overrides: [
      isTvProvider.overrideWithValue(isTv),
      storageProvider.overrideWithValue(storage),
      catalogProvider.overrideWithValue(catalog),
      catalogReadyProvider.overrideWithValue(catalogReady.future),
    ],
  );

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: const KartooniaApp(),
    ),
  );

  unawaited(() async {
    try {
      await catalog.loadMergedInPlace();
    } catch (_) {
      // Even a failed load must release the splash — Home renders what exists.
    } finally {
      catalogReady.complete();
      // Anything already built against the empty catalog rebuilds.
      container.read(catalogRevProvider.notifier).state++;
    }

    // Background-refresh the catalogs from GitHub (ETag-cheap when unchanged).
    // A fresh download is served by the NEXT launch — see CatalogUpdater.
    // Deferred well past launch so the (up to 45 MB) download never competes
    // with first-run browsing for CPU/network on a weak box.
    await Future<void>.delayed(const Duration(seconds: 45));
    unawaited(CatalogUpdater.refreshAll());
  }());
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

/// True on boxes with less than ~1.6 GB of RAM (the cheap TV-stick class the
/// app must stay smooth on). Any failure → assume enough memory.
Future<bool> _isLowRamDevice() async {
  try {
    const channel = MethodChannel('kartoonia/reco');
    final total = await channel.invokeMethod<int>('totalMemBytes') ?? -1;
    return total > 0 && total < 1600 * 1024 * 1024;
  } catch (_) {
    return false;
  }
}
