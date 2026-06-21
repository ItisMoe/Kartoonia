import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/catalog_source.dart';

/// Persistence for watchlist, watch progress (continue watching) and prefs.
/// Backed by SharedPreferences. Ported from the RN `storageService.ts`.

class ProgressEntry {
  final String itemId;
  final String episodeUrl; // PAGE url (token-fetch url), the storage key
  final int episodeNumber;
  final double currentTime;
  final double duration;
  final int updatedAt;

  const ProgressEntry({
    required this.itemId,
    required this.episodeUrl,
    required this.episodeNumber,
    required this.currentTime,
    required this.duration,
    required this.updatedAt,
  });

  double get fraction => duration > 0 ? currentTime / duration : 0;

  Map<String, dynamic> toJson() => {
        'itemId': itemId,
        'episodeUrl': episodeUrl,
        'episodeNumber': episodeNumber,
        'currentTime': currentTime,
        'duration': duration,
        'updatedAt': updatedAt,
      };

  factory ProgressEntry.fromJson(Map<String, dynamic> j) => ProgressEntry(
        itemId: j['itemId'] as String,
        episodeUrl: j['episodeUrl'] as String,
        episodeNumber: (j['episodeNumber'] as num?)?.toInt() ?? 0,
        currentTime: (j['currentTime'] as num?)?.toDouble() ?? 0,
        duration: (j['duration'] as num?)?.toDouble() ?? 0,
        updatedAt: (j['updatedAt'] as num?)?.toInt() ?? 0,
      );
}

class StorageService {
  static const _kWatchlist = 'kt/watchlist';
  static const _kProgress = 'kt/progress';
  static const _kPreferredServer = 'kt/preferredServer';
  static const _kLang = 'kt/lang';
  static const _kPrefs = 'kt/prefs'; // motion/autoplay
  static const _kYtKey = 'kt/ytKey'; // user-set YouTube Data API key override
  static const _kCatalogSource = 'kt/catalogSource'; // arabicToons | stardima
  static const _kShaaratBoosts = 'kt/shaaratBoosts';
  static const _kShaaratVideoIds = 'kt/shaaratVideoIds';
  static const _kSkippedUpdate = 'kt/skippedUpdate'; // release the user dismissed

  final SharedPreferences _prefs;
  StorageService(this._prefs);

  static Future<StorageService> create() async =>
      StorageService(await SharedPreferences.getInstance());

  // ---- Watchlist ----
  List<String> getWatchlistIds() =>
      _prefs.getStringList(_kWatchlist) ?? const [];

  bool isInWatchlist(String itemId) => getWatchlistIds().contains(itemId);

  Future<bool> toggleWatchlist(String itemId) async {
    final ids = [...getWatchlistIds()];
    final present = ids.contains(itemId);
    if (present) {
      ids.remove(itemId);
    } else {
      ids.insert(0, itemId);
    }
    await _prefs.setStringList(_kWatchlist, ids);
    return !present;
  }

  // ---- Progress / continue watching ----
  Map<String, ProgressEntry> _readProgress() {
    final raw = _prefs.getString(_kProgress);
    if (raw == null) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map((k, v) =>
          MapEntry(k, ProgressEntry.fromJson(v as Map<String, dynamic>)));
    } catch (_) {
      return {};
    }
  }

  Future<void> saveProgress(ProgressEntry entry) async {
    final map = _readProgress();
    map[entry.episodeUrl] = entry;
    await _prefs.setString(
        _kProgress, jsonEncode(map.map((k, v) => MapEntry(k, v.toJson()))));
  }

  ProgressEntry? getProgress(String episodeUrl) => _readProgress()[episodeUrl];

  /// All in-progress entries (<95% watched), most-recent first.
  List<ProgressEntry> getContinueWatching() {
    final list = _readProgress()
        .values
        .where((e) => e.duration > 0 && e.fraction < 0.95)
        .toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  /// Best progress fraction for an item across its episodes (for cards).
  double progressForItem(String itemId) {
    double best = 0;
    for (final e in _readProgress().values) {
      if (e.itemId == itemId && e.fraction > best) best = e.fraction;
    }
    return best;
  }

  /// Drop a single episode's progress (keyed by its page/episode url).
  Future<void> removeProgress(String episodeUrl) async {
    final map = _readProgress()..remove(episodeUrl);
    await _prefs.setString(
        _kProgress, jsonEncode(map.map((k, v) => MapEntry(k, v.toJson()))));
  }

  /// Drop all progress for a show/movie (clears the whole title from the
  /// Continue Watching row).
  Future<void> removeProgressForItem(String itemId) async {
    final map = _readProgress()..removeWhere((_, v) => v.itemId == itemId);
    await _prefs.setString(
        _kProgress, jsonEncode(map.map((k, v) => MapEntry(k, v.toJson()))));
  }

  // ---- شارات engagement boost (implicit; orders the reel feed) ----
  // showId -> accumulated boost points. Earned from dwell/completion/entering a
  // show's reel (graduated), it raises the show's weight in `shaaratQueue`.
  Map<String, double> getShaaratBoosts() {
    final raw = _prefs.getString(_kShaaratBoosts);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map)
          .map((k, v) => MapEntry('$k', (v as num).toDouble()));
    } catch (_) {
      return {};
    }
  }

  /// Add [points] to a show's accumulated boost score.
  Future<void> addShaaratBoost(String showId, double points) async {
    final m = getShaaratBoosts();
    m[showId] = (m[showId] ?? 0) + points;
    await _prefs.setString(_kShaaratBoosts, jsonEncode(m));
  }

  // ---- شارات videoId cache ----
  // showId -> videoId, or '' as the "searched, none found" sentinel. Permanent:
  // each show costs at most one YouTube API search ever.
  Map<String, String> _readShaaratVideoIds() {
    final raw = _prefs.getString(_kShaaratVideoIds);
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map).map((k, v) => MapEntry('$k', '$v'));
    } catch (_) {
      return {};
    }
  }

  /// null = never searched, '' = searched/none, non-empty = the cached videoId.
  String? getShaaratVideoId(String showId) => _readShaaratVideoIds()[showId];

  Future<void> setShaaratVideoId(String showId, String videoIdOrEmpty) async {
    final m = _readShaaratVideoIds()..[showId] = videoIdOrEmpty;
    await _prefs.setString(_kShaaratVideoIds, jsonEncode(m));
  }

  // ---- Preferences ----
  int getPreferredServer() => _prefs.getInt(_kPreferredServer) ?? 1;
  Future<void> setPreferredServer(int n) =>
      _prefs.setInt(_kPreferredServer, n);

  // First launch defaults to English; persisted once the user picks a language.
  String getLang() => _prefs.getString(_kLang) ?? 'en';
  Future<void> setLang(String l) => _prefs.setString(_kLang, l);

  // Catalog source — which backend the catalog renders from. Defaults to
  // Arabic Toons (the legacy source) on first launch.
  CatalogSource getCatalogSource() =>
      CatalogSource.fromId(_prefs.getString(_kCatalogSource));
  Future<void> setCatalogSource(CatalogSource s) =>
      _prefs.setString(_kCatalogSource, s.id);

  // YouTube Data API key override. Empty => use the bundled default key.
  String getYoutubeKey() => _prefs.getString(_kYtKey) ?? '';
  Future<void> setYoutubeKey(String k) => _prefs.setString(_kYtKey, k.trim());
  Future<void> clearYoutubeKey() => _prefs.remove(_kYtKey);

  Map<String, String> getPrefs() {
    final raw = _prefs.getString(_kPrefs);
    final defaults = {'motion': 'off', 'autoplay': 'on', 'shaarat': 'video'};
    if (raw == null) return defaults;
    try {
      final m = (jsonDecode(raw) as Map).cast<String, dynamic>();
      return {...defaults, ...m.map((k, v) => MapEntry(k, v.toString()))};
    } catch (_) {
      return defaults;
    }
  }

  Future<void> setPref(String key, String value) async {
    final p = getPrefs()..[key] = value;
    await _prefs.setString(_kPrefs, jsonEncode(p));
  }

  // ---- App update ----
  /// The release version the user chose to skip (e.g. "1.22.0"), or '' if none.
  /// The update prompt is suppressed for exactly this version; a newer release
  /// still prompts.
  String getSkippedUpdate() => _prefs.getString(_kSkippedUpdate) ?? '';
  Future<void> setSkippedUpdate(String version) =>
      _prefs.setString(_kSkippedUpdate, version);
}
