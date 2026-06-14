import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app.dart';
import 'services/catalog_service.dart';
import 'services/storage_service.dart';
import 'state/app_state.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  // Load services before the first frame; the branded splash covers it.
  final storage = await StorageService.create();
  final catalog = await CatalogService.load();

  runApp(
    ProviderScope(
      overrides: [
        storageProvider.overrideWithValue(storage),
        catalogProvider.overrideWithValue(catalog),
      ],
      child: const KartooniaApp(),
    ),
  );
}
