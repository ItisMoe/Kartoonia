import '../models/catalog_source.dart';
import '../models/content_item.dart';
import 'storage_service.dart';

/// The source a detail screen preselects for a title, shared by the TV and
/// phone detail screens so the policy can't drift between them.
///
/// Default to whichever twin has stored progress (so Resume works), preferring
/// [base] when it (also) has progress. A fresh SHOW defaults to its Carateen
/// twin when one exists — Carateen streams HLS with real resolution variants,
/// so it plays noticeably better than the single-file sources.
CatalogSource defaultSourceFor(
    StorageService storage, ContentItem base, List<ContentItem> alts) {
  if (storage.progressForItem(base.id) > 0) return base.source;
  for (final a in alts) {
    if (storage.progressForItem(a.id) > 0) return a.source;
  }
  if (base is Show &&
      (base.source == CatalogSource.carateen ||
          alts.any((a) => a.source == CatalogSource.carateen))) {
    return CatalogSource.carateen;
  }
  return base.source;
}
