import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/storage_service.dart';
import '../services/catalog_service.dart';
import '../services/voice_search_service.dart';
import '../i18n/strings.dart';

/// True on Android TV / Google TV (leanback). Detected once in main() via the
/// native channel and injected below; drives the UI fork (TV D-pad canvas vs.
/// the portrait touch phone UI).
final isTvProvider = Provider<bool>(
    (ref) => throw UnimplementedError('isTvProvider must be overridden'));

/// Injected in main() via ProviderScope overrides after async init.
final storageProvider = Provider<StorageService>(
    (ref) => throw UnimplementedError('storageProvider must be overridden'));
final catalogProvider = Provider<CatalogService>(
    (ref) => throw UnimplementedError('catalogProvider must be overridden'));

/// Bumped after an import or a source switch so dependent UI rebuilds (the
/// catalog mutates in place).
final catalogRevProvider = StateProvider<int>((ref) => 0);

/// Selected bottom-tab index for the phone shell (0=Home, 1=Browse, 2=Search,
/// 3=My List). A provider so screens can switch tabs programmatically (e.g. the
/// Home search affordance or an empty My-List CTA).
final phoneTabProvider = StateProvider<int>((ref) => 0);

// ---------------- Settings (language + playback prefs) ----------------
class SettingsState {
  final String lang; // 'ar' | 'en'
  final Map<String, String> prefs; // motion / autoplay
  const SettingsState(this.lang, this.prefs);
  bool get isRtl => lang == 'ar';
}

class SettingsNotifier extends Notifier<SettingsState> {
  @override
  SettingsState build() {
    final s = ref.read(storageProvider);
    return SettingsState(s.getLang(), s.getPrefs());
  }

  Future<void> setLang(String lang) async {
    if (lang == state.lang) return;
    await ref.read(storageProvider).setLang(lang);
    state = SettingsState(lang, state.prefs);
  }

  Future<void> setPref(String key, String value) async {
    await ref.read(storageProvider).setPref(key, value);
    state = SettingsState(state.lang, ref.read(storageProvider).getPrefs());
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, SettingsState>(SettingsNotifier.new);

/// Current string table + helper.
final stringsProvider = Provider<Map<String, String>>((ref) {
  final lang = ref.watch(settingsProvider).lang;
  return kStrings[lang] ?? kStrings['ar']!;
});

/// The user-set YouTube Data API key ('' => use the bundled default). Updated
/// from Settings; read by the trailer/theme-song player.
final ytKeyProvider = StateProvider<String>(
    (ref) => ref.read(storageProvider).getYoutubeKey());

// ---------------- User library (watchlist + continue watching) ----------------
class UserState {
  final Set<String> watchlistIds;
  final List<ProgressEntry> continueWatching;
  const UserState(this.watchlistIds, this.continueWatching);
}

class UserNotifier extends Notifier<UserState> {
  @override
  UserState build() => _read();

  UserState _read() {
    final s = ref.read(storageProvider);
    return UserState(
      s.getWatchlistIds().toSet(),
      s.getContinueWatching(),
    );
  }

  bool isInList(String id) => state.watchlistIds.contains(id);

  Future<bool> toggle(String id) async {
    final now = await ref.read(storageProvider).toggleWatchlist(id);
    state = _read();
    return now;
  }

  void refresh() => state = _read();
}

final userProvider =
    NotifierProvider<UserNotifier, UserState>(UserNotifier.new);

// ---------------- Browse + search transient UI state ----------------
class BrowseState {
  final String kind; // 'tv' | 'movies' | 'mylist'
  final String? letter;
  final String alphaScript; // 'en' | 'ar'
  final String? category; // Stardima category filter (null = all)
  const BrowseState(
      {this.kind = 'tv', this.letter, this.alphaScript = 'ar', this.category});
  BrowseState copy(
          {String? kind,
          String? letter,
          bool clearLetter = false,
          String? alphaScript,
          String? category,
          bool clearCategory = false}) =>
      BrowseState(
        kind: kind ?? this.kind,
        letter: clearLetter ? null : (letter ?? this.letter),
        alphaScript: alphaScript ?? this.alphaScript,
        category: clearCategory ? null : (category ?? this.category),
      );
}

class BrowseNotifier extends Notifier<BrowseState> {
  @override
  BrowseState build() => const BrowseState();
  void setKind(String k) =>
      state = state.copy(kind: k, clearLetter: true, clearCategory: true);
  void setLetter(String? l) => state =
      l == null ? state.copy(clearLetter: true) : state.copy(letter: l);
  void setScript(String s) =>
      state = state.copy(alphaScript: s, clearLetter: true);
  void setCategory(String? c) => state =
      c == null ? state.copy(clearCategory: true) : state.copy(category: c);

  /// Clear all transient filters (used when the catalog source changes).
  void reset() => state = const BrowseState();
}

final browseProvider =
    NotifierProvider<BrowseNotifier, BrowseState>(BrowseNotifier.new);

class SearchState {
  final String query;
  final String filter; // all | tv | movies
  final String kbScript; // en | ar
  const SearchState({this.query = '', this.filter = 'all', this.kbScript = 'ar'});
  SearchState copy({String? query, String? filter, String? kbScript}) =>
      SearchState(
        query: query ?? this.query,
        filter: filter ?? this.filter,
        kbScript: kbScript ?? this.kbScript,
      );
}

class SearchNotifier extends Notifier<SearchState> {
  @override
  SearchState build() => const SearchState();
  void type(String ch) => state = state.copy(query: state.query + ch);
  void backspace() => state = state.copy(
      query: state.query.isEmpty
          ? ''
          : state.query.substring(0, state.query.length - 1));
  void clear() => state = state.copy(query: '');
  void setFilter(String f) => state = state.copy(filter: f);
  void setScript(String s) => state = state.copy(kbScript: s);
  void setQuery(String q) => state = state.copy(query: q);

  /// Persist the current query as a recent search (called when the user opens a
  /// result), then refresh the recent list.
  Future<void> record() async {
    final q = state.query.trim();
    if (q.isEmpty) return;
    await ref.read(storageProvider).addRecentSearch(q);
    ref.read(recentSearchesProvider.notifier).state =
        ref.read(storageProvider).getRecentSearches();
  }

  Future<void> clearRecent() async {
    await ref.read(storageProvider).clearRecentSearches();
    ref.read(recentSearchesProvider.notifier).state = const [];
  }
}

final searchProvider =
    NotifierProvider<SearchNotifier, SearchState>(SearchNotifier.new);

/// Persisted recent search queries (most-recent first), surfaced on the empty
/// Search screen. Seeded from storage; updated when a search is "used".
final recentSearchesProvider = StateProvider<List<String>>(
    (ref) => ref.read(storageProvider).getRecentSearches());

// ---------------- Voice search ----------------
/// idle: not listening. listening: actively transcribing into the search box.
/// unavailable: no recognizer / mic permission denied (button hides itself).
enum VoiceStatus { idle, listening, unavailable }

/// Single recognizer wrapper for the app's lifetime.
final voiceServiceProvider =
    Provider<VoiceSearchService>((ref) => VoiceSearchService());

class VoiceNotifier extends Notifier<VoiceStatus> {
  @override
  VoiceStatus build() {
    _checkAvailability();
    return VoiceStatus.idle;
  }

  /// Reflects "no recognizer" as the muted mic-off icon, without blocking the
  /// button — a press still attempts recognition in case the check was wrong.
  Future<void> _checkAvailability() async {
    final ok = await ref.read(voiceServiceProvider).isAvailable();
    if (!ok && state == VoiceStatus.idle) state = VoiceStatus.unavailable;
  }

  /// Opens the system voice dialog, then drops the final transcript into the
  /// search box. The dialog owns the listening session, so there is nothing to
  /// stop — a press while already listening is ignored.
  Future<void> toggle() async {
    if (state == VoiceStatus.listening) return;

    final svc = ref.read(voiceServiceProvider);
    final search = ref.read(searchProvider.notifier);
    final kbScript = ref.read(searchProvider).kbScript;
    final prompt = ref.read(stringsProvider)['voiceSpeak'];

    state = VoiceStatus.listening;
    try {
      final text = await svc.recognize(kbScript: kbScript, prompt: prompt);
      if (text != null) search.setQuery(text);
    } catch (_) {
      // Swallow: an unavailable recognizer just yields no transcript.
    } finally {
      state = VoiceStatus.idle;
    }
  }
}

final voiceProvider =
    NotifierProvider<VoiceNotifier, VoiceStatus>(VoiceNotifier.new);
