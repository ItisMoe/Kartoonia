import 'dart:math';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models/content_item.dart';
import 'navigation.dart';
import 'screens/player_screen.dart';
import 'services/resume.dart';
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
  // When no explicit episode is given, smart-resume: continue the in-progress
  // episode, else jump to the next unwatched one (see [resumeTarget]).
  final storage = ref.read(storageProvider);
  final Episode target = episode ??
      resumeTarget(show.episodes, (url) => storage.getProgress(url));

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

final _rng = Random();

/// "Surprise me": play a random well-known cartoon straight away. Picks from the
/// curated famous pool (animation/family, deduped) for quality, falling back to
/// the full catalog. Shows smart-resume to their in-progress/next episode.
void playRandom(BuildContext context, WidgetRef ref) {
  final catalog = ref.read(catalogProvider);
  final pool = catalog.popularPool();
  final items = pool.isNotEmpty ? pool : catalog.all;
  if (items.isEmpty) return;
  playItem(context, ref, items[_rng.nextInt(items.length)]);
}
