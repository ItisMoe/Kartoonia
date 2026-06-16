/// Decide how to react to an error reported by libmpv *during* playback.
///
/// `media_kit`'s `Player.stream.error` surfaces libmpv error-*level* log
/// events, and libmpv logs at error level for many **transient, self-recovering**
/// conditions — a single failed/retried segment or HTTP range request, a
/// momentary TLS/connection reset, a cache underrun — not just fatal ones.
///
/// Treating every such event as a dead server is what made the
/// "All servers failed" overlay appear on a stream that was still playing
/// fine: over a long session the chance of at least one transient error log
/// approaches certainty. So a mid-playback error is only a *suspicion*. After a
/// short confirmation window we look at the player state and decide:
///
///  - position advanced, or playback completed  → healthy/ended, ignore.
///  - position frozen but the player is paused/idle (user paused) → ignore.
///  - position frozen while the player is still trying to play (playing or
///    buffering) → a genuine stall, fail over to another server.
bool shouldFailOverAfterError({
  required Duration positionBefore,
  required Duration positionNow,
  required bool playing,
  required bool buffering,
  required bool completed,
}) {
  // Playback moved forward, or the file ended cleanly: the error was transient.
  if (positionNow > positionBefore || completed) return false;
  // Position is frozen. Only treat it as a failure if the player still intends
  // to play (so a deliberate user pause is never mistaken for a dead stream).
  return playing || buffering;
}
