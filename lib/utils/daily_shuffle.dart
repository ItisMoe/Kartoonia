import 'dart:math';

/// Deterministic once-per-day shuffle: the order is stable for a given calendar
/// day (doesn't reshuffle on every app open / navigation) and changes when the
/// day changes. [salt] varies the order per row so different rows aren't
/// permuted identically.
List<T> dailyShuffled<T>(List<T> items, {String salt = ''}) {
  if (items.length < 2) return List<T>.of(items);
  final now = DateTime.now();
  final key = '${now.year}-${now.month}-${now.day}-$salt';
  final rng = Random(key.hashCode);
  final out = List<T>.of(items);
  out.shuffle(rng);
  return out;
}
