import 'dart:async';

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

/// True while the full-screen player is mounted — suppresses the screensaver so
/// it never covers playback.
final playerActiveProvider = StateProvider<bool>((ref) => false);

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

/// Liked شارات show ids (boost the reel feed ordering). Seeded from storage;
/// toggled by the reel heart.
final shaaratLikesProvider = StateProvider<Set<String>>(
    (ref) => ref.read(storageProvider).getShaaratLikes().toSet());

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
/// idle: not listening. listening: capturing speech. processing: speech ended,
/// recognizer is finalizing. error: a session failed to recognize anything
/// (e.g. no match) — the overlay shows a brief "didn't catch that". unavailable:
/// no recognizer / mic permission denied (button shows the muted icon).
enum VoicePhase { idle, listening, processing, error, unavailable }

/// Live state of the in-app voice session, consumed by the listening overlay.
class VoiceState {
  final VoicePhase phase;

  /// Latest non-final transcript, shown live in the overlay (NOT in the search
  /// box — see [VoiceNotifier.start]).
  final String partial;

  /// Microphone loudness 0..1, drives the overlay's reactive mic rings.
  final double level;

  const VoiceState({
    this.phase = VoicePhase.idle,
    this.partial = '',
    this.level = 0,
  });

  bool get listening => phase == VoicePhase.listening;
  bool get processing => phase == VoicePhase.processing;
  bool get errored => phase == VoicePhase.error;
  bool get unavailable => phase == VoicePhase.unavailable;

  VoiceState copyWith({VoicePhase? phase, String? partial, double? level}) =>
      VoiceState(
        phase: phase ?? this.phase,
        partial: partial ?? this.partial,
        level: level ?? this.level,
      );
}

/// Single recognizer wrapper for the app's lifetime.
final voiceServiceProvider =
    Provider<VoiceSearchService>((ref) => VoiceSearchService());

class VoiceNotifier extends Notifier<VoiceState> {
  StreamSubscription? _sub;
  Completer<String?>? _completer;
  bool _prepared = false;

  @override
  VoiceState build() {
    _checkAvailability();
    ref.onDispose(() => _sub?.cancel());
    return const VoiceState();
  }

  /// Warm the native recognizer + request the mic permission once, ahead of the
  /// first tap, so listening starts instantly. Safe to call repeatedly (e.g. on
  /// every search-screen build) — it only reaches the platform once.
  Future<void> prepare() async {
    if (_prepared) return;
    _prepared = true;
    await ref.read(voiceServiceProvider).prepare();
  }

  /// Reflects "no recognizer" as the muted mic-off icon, without permanently
  /// blocking the button — a later press still attempts a session.
  Future<void> _checkAvailability() async {
    final ok = await ref.read(voiceServiceProvider).isAvailable();
    if (!ok && state.phase == VoicePhase.idle) {
      state = state.copyWith(phase: VoicePhase.unavailable);
    }
  }

  /// Begin a listening session. Completes with the final transcript, or null if
  /// the user cancelled / nothing was recognized / recognition failed.
  ///
  /// Live partial results drive the overlay ONLY — they are deliberately NOT
  /// pushed into the search box. Re-running the O(N) catalog search and
  /// rebuilding the grid on every partial transcript was the lag the previous
  /// continuous-recognition approach suffered; only the final transcript is
  /// committed (by the caller).
  Future<String?> start() async {
    if (state.phase == VoicePhase.listening) return null;

    final svc = ref.read(voiceServiceProvider);
    final localeId = voiceLocaleFor(ref.read(searchProvider).kbScript);
    final completer = Completer<String?>();
    _completer = completer;
    state = const VoiceState(phase: VoicePhase.listening);

    _sub?.cancel();
    _sub = svc.events().listen(
      (e) {
        if (e is! Map) return;
        final map = e.cast<String, dynamic>();
        switch (map['type']) {
          case 'rms':
            state = state.copyWith(
                level: ((map['level'] as num?)?.toDouble() ?? 0).clamp(0, 1));
            break;
          case 'partial':
            final txt = (map['text'] as String?)?.trim() ?? '';
            if (txt.isNotEmpty) state = state.copyWith(partial: txt);
            break;
          case 'status':
            // End-of-speech: keep the overlay up in a "processing" state while
            // the recognizer finalizes (a final/error event follows).
            if (map['value'] == 'end' && state.phase == VoicePhase.listening) {
              state = state.copyWith(phase: VoicePhase.processing);
            }
            break;
          case 'final':
            final txt = (map['text'] as String?)?.trim();
            // An empty final = nothing recognized → surface as an error so the
            // overlay can say "didn't catch that" instead of silently closing.
            _finish(txt == null || txt.isEmpty ? null : txt,
                errored: txt == null || txt.isEmpty);
            break;
          case 'error':
            // 9 = ERROR_INSUFFICIENT_PERMISSIONS → mic denied / no recognizer.
            // Any other code = recognition failed (e.g. no match): surface it.
            final code = map['code'] as int?;
            _finish(null, unavailable: code == 9, errored: code != 9);
            break;
        }
      },
      onError: (_) => _finish(null),
    );

    try {
      await svc.start(localeId);
    } catch (_) {
      _finish(null);
    }
    return completer.future;
  }

  /// Stop capturing and let the recognizer finalize; a `final` event follows.
  Future<void> stop() async {
    if (state.phase != VoicePhase.listening) return;
    await ref.read(voiceServiceProvider).stop();
  }

  /// User dismissed the overlay — abort the native session with no result.
  Future<void> cancel() async {
    if (state.phase != VoicePhase.listening) return;
    await ref.read(voiceServiceProvider).cancel();
    _finish(null);
  }

  void _finish(String? result, {bool unavailable = false, bool errored = false}) {
    _sub?.cancel();
    _sub = null;
    final c = _completer;
    _completer = null;
    state = VoiceState(
        phase: unavailable
            ? VoicePhase.unavailable
            : errored
                ? VoicePhase.error
                : VoicePhase.idle);
    if (c != null && !c.isCompleted) c.complete(result);
  }
}

final voiceProvider =
    NotifierProvider<VoiceNotifier, VoiceState>(VoiceNotifier.new);
