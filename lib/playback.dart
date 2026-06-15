import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models/content_item.dart';
import 'navigation.dart';
import 'screens/player_screen.dart';
import 'state/app_state.dart';

/// Resolves what to play for an item and opens the player.
/// Movies play directly; shows resume the in-progress episode or start the
/// first, and pass the full flattened episode list for prev/next.
void playItem(BuildContext context, WidgetRef ref, ContentItem item,
    {Episode? episode}) {
  final t = ref.read(stringsProvider);
  if (item is Movie) {
    AppNav.player(
      context,
      PlayerArgs(
        itemId: item.id,
        pageUrl: item.pageUrl,
        title: item.title,
        episodeLabel: t['movie']!,
        episodeNumber: 0,
        source: item.source,
      ),
    );
    return;
  }

  final show = item as Show;
  if (show.episodes.isEmpty) return;
  Episode target = episode ?? show.episodes.first;
  if (episode == null) {
    // resume the most recently watched, still-unfinished episode if any
    final storage = ref.read(storageProvider);
    final cw = storage
        .getContinueWatching()
        .where((e) => e.itemId == show.id)
        .toList();
    if (cw.isNotEmpty) {
      final match = show.episodes.firstWhere(
        (ep) => ep.episodeUrl == cw.first.episodeUrl,
        orElse: () => show.episodes.first,
      );
      target = match;
    }
  }

  AppNav.player(
    context,
    PlayerArgs(
      itemId: show.id,
      pageUrl: target.episodeUrl,
      title: show.title,
      episodeLabel: '${t['epShort']}${target.episodeNumber}',
      episodeNumber: target.episodeNumber,
      episodes: show.episodes,
      source: show.source,
    ),
  );
}
