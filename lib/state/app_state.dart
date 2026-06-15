import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/catalog_source.dart';
import '../services/storage_service.dart';
import '../services/catalog_service.dart';
import '../services/voice_search_service.dart';
import '../i18n/strings.dart';

/// Injected in main() via ProviderScope overrides after async init.
final storageProvider = Provider<StorageService>(
    (ref) => throw UnimplementedError('storageProvider must be overridden'));
final catalogProvider = Provider<CatalogService>(
    (ref) => throw UnimplementedError('catalogProvider must be overridden'));

/// Bumped after an import or a source switch so dependent UI rebuilds (the
/// catalog mutates in place).
final catalogRevProvider = StateProvider<int>((ref) => 0);

// ---------------- Catalog source (Arabic Toons | Stardima) ----------------
/// True while a source switch is loading/parsing the new catalog asset.
final catalogSwitchingProvider = StateProvider<bool>((ref) => false);

/// The active catalog source, persisted across restarts. Changing it reloads the
/// catalog in place and bumps [catalogRevProvider] so the whole UI re-renders
/// from the newly selected source.
class CatalogSourceNotifier extends Notifier<CatalogSource> {
  @override
  CatalogSource build() => ref.read(storageProvider).getCatalogSource();

  Future<void> setSource(CatalogSource next) async {
    if (next == state) return;
    ref.read(catalogSwitchingProvider.notifier).state = true;
    try {
      await ref.read(storageProvider).setCatalogSource(next);
      await ref.read(catalogProvider).switchTo(next);
      state = next;
      // Reset transient browse/search filters that may not exist in the new
      // source, then force every catalog-bound screen to rebuild.
      ref.read(browseProvider.notifier).reset();
      ref.read(searchProvider.notifier).clear();
      ref.read(catalogRevProvider.notifier).state++;
    } finally {
      ref.read(catalogSwitchingProvider.notifier).state = false;
    }
  }
}

final catalogSourceProvider =
    NotifierProvider<CatalogSourceNotifier, CatalogSource>(
        CatalogSourceNotifier.new);

// ---------------- Settings (language + playback prefs) ----------------
class SettingsState {
  final String lang; // 'ar' | 'en'
  final Map<String, String> prefs; // motion / autoplay / subtitles
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
}

final searchProvider =
    NotifierProvider<SearchNotifier, SearchState>(SearchNotifier.new);

// ---------------- Voice search ----------------
/// idle: not listening. listening: actively transcribing into the search box.
/// unavailable: no recognizer / mic permission denied (button hides itself).
enum VoiceStatus { idle, listening, unavailable }

/// Single recognizer instance for the app's lifetime.
final voiceServiceProvider = Provider<VoiceSearchService>((ref) {
  final svc = VoiceSearchService();
  ref.onDispose(svc.stop);
  return svc;
});

class VoiceNotifier extends Notifier<VoiceStatus> {
  @override
  VoiceStatus build() => VoiceStatus.idle;

  /// Toggles a listening session. Reads the active keyboard script to pick the
  /// recognition language and streams the transcript into [searchProvider].
  Future<void> toggle() async {
    final svc = ref.read(voiceServiceProvider);
    if (state == VoiceStatus.listening) {
      await svc.stop();
      state = VoiceStatus.idle;
      return;
    }

    final search = ref.read(searchProvider.notifier);
    final kbScript = ref.read(searchProvider).kbScript;
    state = VoiceStatus.listening;
    try {
      final ok = await svc.start(
        kbScript: kbScript,
        onText: (text, _) => search.setQuery(text),
        onDone: () {
          if (state == VoiceStatus.listening) state = VoiceStatus.idle;
        },
      );
      if (!ok) state = VoiceStatus.unavailable;
    } catch (_) {
      state = VoiceStatus.unavailable;
    }
  }
}

final voiceProvider =
    NotifierProvider<VoiceNotifier, VoiceStatus>(VoiceNotifier.new);
