import 'catalog_source.dart';

/// The five catalog modes the user picks in Settings. A mode scopes **Home and
/// Browse only** — My List, Search, Detail and playback are mode-independent.
///
///  - [dubbed]      Arabic Toons + Stardima (the dubbed-anime library).
///  - [carateen]    Carateen only (its own catalog, incl. SpaceToon-Go).
///  - [arabic]      All three bundled Arabic sources merged (the app default).
///  - [wcoflix]     The WCOFlix universe only.
///  - [everything]  Arabic (all three) AND WCOFlix, shown un-merged together.
enum LibraryMode {
  dubbed(
    id: 'dubbed',
    bundled: {CatalogSource.arabicToons, CatalogSource.stardima},
    hasWcoflix: false,
  ),
  carateen(
    id: 'carateen',
    bundled: {CatalogSource.carateen},
    hasWcoflix: false,
  ),
  arabic(
    id: 'arabic',
    bundled: {
      CatalogSource.arabicToons,
      CatalogSource.stardima,
      CatalogSource.carateen
    },
    hasWcoflix: false,
  ),
  wcoflix(
    id: 'wcoflix',
    bundled: {},
    hasWcoflix: true,
  ),
  everything(
    id: 'everything',
    bundled: {
      CatalogSource.arabicToons,
      CatalogSource.stardima,
      CatalogSource.carateen
    },
    hasWcoflix: true,
  );

  const LibraryMode(
      {required this.id, required this.bundled, required this.hasWcoflix});

  /// Stable persistence key value.
  final String id;

  /// Bundled Arabic catalogs this mode shows (empty for WCOFlix-only).
  final Set<CatalogSource> bundled;

  /// Whether the WCOFlix universe is shown.
  final bool hasWcoflix;

  bool get showsArabic => bundled.isNotEmpty;
  bool get showsWcoflix => hasWcoflix;
  bool get isWcoflixOnly => hasWcoflix && bundled.isEmpty;

  static LibraryMode fromId(String? id) => LibraryMode.values.firstWhere(
        (m) => m.id == id,
        orElse: () => LibraryMode.arabic,
      );
}
