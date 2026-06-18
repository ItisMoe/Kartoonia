import '../models/content_item.dart';
import 'storage_service.dart';

/// How far through an episode counts as "watched". Mirrors the Continue
/// Watching cutoff in [StorageService.getContinueWatching] so an episode that
/// has left the Keep-Watching row is also treated as finished here.
const double kWatchedThreshold = 0.95;

/// Watch state of a single episode, derived from its saved progress.
enum EpisodeWatchState { unwatched, inProgress, watched }

/// Watch state for a saved progress entry (or null when never opened).
EpisodeWatchState episodeWatchState(ProgressEntry? p) {
  if (p == null || p.duration <= 0 || p.fraction <= 0) {
    return EpisodeWatchState.unwatched;
  }
  return p.fraction >= kWatchedThreshold
      ? EpisodeWatchState.watched
      : EpisodeWatchState.inProgress;
}

/// True when any episode of the show has been started (so the UI shows
/// "Resume" rather than "Play", and surfaces unwatched markers).
bool hasAnyProgress(
    List<Episode> episodes, ProgressEntry? Function(String url) progressOf) {
  for (final ep in episodes) {
    if (episodeWatchState(progressOf(ep.episodeUrl)) !=
        EpisodeWatchState.unwatched) {
      return true;
    }
  }
  return false;
}

/// The episode to play when the user presses Resume/Play on a show:
///   1. the most-recently-updated still-unfinished (in-progress) episode, else
///   2. the first episode (in season/list order) that is unwatched — i.e. the
///      "next one to watch" after a run of finished episodes, else
///   3. the first episode (everything watched → start over).
///
/// [progressOf] looks an episode up by its [Episode.episodeUrl]. [episodes] is
/// assumed non-empty (callers guard empty shows before reaching here).
Episode resumeTarget(
    List<Episode> episodes, ProgressEntry? Function(String url) progressOf) {
  Episode? bestInProgress;
  ProgressEntry? bestEntry;
  for (final ep in episodes) {
    final p = progressOf(ep.episodeUrl);
    if (episodeWatchState(p) == EpisodeWatchState.inProgress) {
      if (bestEntry == null || p!.updatedAt > bestEntry.updatedAt) {
        bestEntry = p;
        bestInProgress = ep;
      }
    }
  }
  if (bestInProgress != null) return bestInProgress;

  for (final ep in episodes) {
    if (episodeWatchState(progressOf(ep.episodeUrl)) ==
        EpisodeWatchState.unwatched) {
      return ep;
    }
  }
  return episodes.first;
}
