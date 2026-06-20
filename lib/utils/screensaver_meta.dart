import '../models/content_item.dart';
import 'genre_translations.dart';

/// One-line metadata for the screensaver info card: year · type · genres.
/// Deliberately excludes any TMDB rating (never displayed app-wide).
String screensaverMeta(ContentItem item, Map<String, String> t) {
  final parts = <String>[];
  if (item.year != null) parts.add('${item.year}');
  if (item is Show) {
    parts.add('${item.seasonCount} ${t['seasons'] ?? ''}'.trim());
  } else {
    final movie = t['movie'];
    if (movie != null && movie.isNotEmpty) parts.add(movie);
  }
  parts.addAll(item.genres.map(translateGenre));
  return parts.where((p) => p.isNotEmpty).join(' · ');
}
