/// The two catalog backends the app can render from. Everything (parsing, art,
/// categories, playback) branches off the *persisted* selection — nothing is
/// hardcoded to one source.
///
///  - [arabicToons]: the legacy `arabictoons_catalog.json`. Items carry a direct
///    (tokenized) video path; playback fetches fresh tokens from the page URL.
///  - [stardima]: `stardima_catalog.json`. Items only have a `play_url` that must
///    be resolved (hyperwatching → host embed → .m3u8) right before playback.
enum CatalogSource {
  arabicToons(
    id: 'arabicToons',
    assetPath: 'assets/arabictoons_catalog.json',
  ),
  stardima(
    id: 'stardima',
    assetPath: 'assets/stardima_catalog.json',
  );

  const CatalogSource({required this.id, required this.assetPath});

  /// Stable string used as the persistence key value.
  final String id;

  /// Bundled asset the catalog is loaded from.
  final String assetPath;

  static CatalogSource fromId(String? id) => CatalogSource.values.firstWhere(
        (s) => s.id == id,
        orElse: () => CatalogSource.arabicToons,
      );
}
