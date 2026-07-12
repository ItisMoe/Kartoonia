# Library Modes · Carateen SpaceToon · Spotlight Hero — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add every carateen.tv SpaceToon title to the app, replace the binary "Everything" toggle with five explicit library modes that scope Home + Browse only, and turn the Home hero into a backdrop-sized spotlight-card carousel.

**Architecture:** Three cohesive parts on one branch. Part 1 (SpaceToon) is standalone — a new sp branch in the Carateen scraper (Python) and resolver (Dart), regenerating the bundled catalog. Part 2 (modes) introduces a `LibraryMode` enum persisted in storage, makes `CatalogService` compute mode-scoped *views* (leaving the global merged library for Search/Detail untouched), and rewires Settings/Browse/Home. Part 3 (hero) is an internal redesign of `HeroCarousel`.

**Tech Stack:** Flutter/Dart (Riverpod, `http`, `encrypt`, `flutter_test` + `MockClient`), Python 3 (`pycryptodome`) for the scraper.

## Global Constraints

- **Version bump before tag:** bump `pubspec.yaml` `version:` to the release `X.Y.Z` BEFORE tagging `vX.Y.Z` (in-app updater loops otherwise). Current: `3.2.0+29`. This release: `3.3.0+30`.
- **No new dependencies.** Use only what's already in `pubspec.yaml`.
- **AES envelope:** carateen key is the literal UTF-8 string `7annaba3l_loves_crypto_safe_key!`, AES-256-CBC / PKCS7, `iv`=hex, `encryptedData`=hex. Reuse existing helpers; never re-derive.
- **Carateen media headers:** every CDN request needs `User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36` + `Referer: https://carateen.tv/`. Use `kCarateenMediaHeaders`.
- **Mode scope:** modes affect **Home and Browse ONLY**. My List, Continue Watching, Search, Detail, and playback stay global/mode-independent.
- **Windows asset lock:** the Dart analysis server locks `assets/*.json`; overwrite in place (don't `os.replace`) — the scraper already writes in place.
- **Run tests with:** `flutter test test/<file>.dart` from repo root.

---

## Part 1 — Carateen SpaceToon catalog

### Task 1: sp resolver branch

**Files:**
- Modify: `lib/services/carateen_resolver.dart`
- Test: `test/carateen_test.dart` (extend)

**Interfaces:**
- Produces: `parseCarateenPlayUrl(String) -> ({String showId, String episodeId, bool isSp})?` (adds `isSp`). `resolveCarateen(String playUrl, {http.Client? client})` unchanged signature; now POSTs `/api/sp/episode/link` when `isSp`.

- [ ] **Step 1: Write the failing tests**

Add to `test/carateen_test.dart` inside `main()`:

```dart
group('parseCarateenPlayUrl sp form', () {
  test('flags an sp watch URL and extracts ids', () {
    final r = parseCarateenPlayUrl('https://carateen.tv/watch/sp/175/12896');
    expect(r, isNotNull);
    expect(r!.showId, '175');
    expect(r.episodeId, '12896');
    expect(r.isSp, isTrue);
  });
  test('non-sp watch URL is not flagged sp', () {
    final r = parseCarateenPlayUrl('https://carateen.tv/watch/91/740');
    expect(r!.isSp, isFalse);
    expect(r.showId, '91');
    expect(r.episodeId, '740');
  });
});

group('resolveCarateen sp', () {
  Map<String, String> envelope(String plainJson) {
    final key = Key.fromUtf8('7annaba3l_loves_crypto_safe_key!');
    final iv = IV(Uint8List.fromList(
        List<int>.generate(16, (i) => (i * 13 + 1) & 0xff)));
    final enc = Encrypter(AES(key, mode: AESMode.cbc, padding: 'PKCS7'));
    return {'iv': iv.base16, 'encryptedData': enc.encrypt(plainJson, iv: iv).base16};
  }

  test('POSTs /api/sp/episode/link with episodeId and expands the master',
      () async {
    const masterUrl = 'https://pegasus.example/api/sp/hls/abc/playlist.m3u8';
    final client = MockClient((req) async {
      if (req.url.path == '/api/sp/episode/link') {
        expect(req.method, 'POST');
        expect(jsonDecode(req.body)['episodeId'], '12896');
        return http.Response(
            jsonEncode(envelope('{"success":true,"link":"$masterUrl"}')), 200);
      }
      expect(req.url.toString(), masterUrl);
      expect(req.headers['Referer'], 'https://carateen.tv/');
      return http.Response(
          '#EXTM3U\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=5000000,RESOLUTION=1920x1080,NAME="1080p"\n'
          '1080p/playlist.m3u8\n'
          '#EXT-X-STREAM-INF:BANDWIDTH=2800000,RESOLUTION=1280x720,NAME="720p"\n'
          '720p/playlist.m3u8\n',
          200);
    });
    final streams = await resolveCarateen(
        'https://carateen.tv/watch/sp/175/12896', client: client);
    expect(streams.map((s) => s.server).toList(), ['720p', '1080p']);
    expect(streams.first.headers['Referer'], 'https://carateen.tv/');
  });
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `flutter test test/carateen_test.dart`
Expected: FAIL — `isSp` not defined; sp POST path not handled.

- [ ] **Step 3: Implement the sp branch**

In `lib/services/carateen_resolver.dart`, change `parseCarateenPlayUrl` to detect the `sp` marker and add `isSp` to the record:

```dart
/// Parse ids out of a `.../watch/<show>/<episode>` OR `.../watch/sp/<show>/<episode>`
/// play_url. `isSp` marks the SpaceToon-Go catalog, which resolves via a
/// different endpoint (POST /api/sp/episode/link). Returns null when not a watch link.
({String showId, String episodeId, bool isSp})? parseCarateenPlayUrl(String playUrl) {
  final u = Uri.tryParse(playUrl);
  if (u == null) return null;
  final segs = u.pathSegments.where((s) => s.isNotEmpty).toList();
  final i = segs.indexOf('watch');
  if (i < 0) return null;
  // sp form: watch / sp / <show> / <episode>
  if (segs.length >= i + 4 && segs[i + 1] == 'sp') {
    return (showId: segs[i + 2], episodeId: segs[i + 3], isSp: true);
  }
  // tg form: watch / <show> / <episode>
  if (segs.length >= i + 3) {
    return (showId: segs[i + 1], episodeId: segs[i + 2], isSp: false);
  }
  return null;
}
```

Then in `resolveCarateen`, replace the single `/api/episode` fetch block with a branch that fetches the sp link when `ids.isSp`, keeping everything after `streamUrl` (the master-expansion + fallback) identical:

```dart
Future<List<CarateenStream>> resolveCarateen(String playUrl,
    {http.Client? client}) async {
  final ids = parseCarateenPlayUrl(playUrl);
  if (ids == null) {
    throw CarateenResolveException('not a carateen watch url: $playUrl');
  }
  final own = client == null;
  final c = client ?? http.Client();
  try {
    final String streamUrl;
    if (ids.isSp) {
      // SpaceToon-Go: POST the episodeId, decrypt, read `link` (a master .m3u8).
      final resp = await c.post(
        Uri.parse('$_kBase/api/sp/episode/link'),
        headers: const {
          'User-Agent': _kUserAgent,
          'X-Cartoony-Client': 'web-frontend-v1',
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          'Referer': '$_kBase/',
        },
        body: jsonEncode({'episodeId': ids.episodeId}),
      );
      if (resp.statusCode != 200) {
        throw CarateenResolveException(
            'HTTP ${resp.statusCode} for /api/sp/episode/link');
      }
      final data = decryptCarateen(jsonDecode(utf8.decode(resp.bodyBytes)));
      final link = data is Map ? data['link'] : null;
      if (link is! String || link.isEmpty) {
        throw const CarateenResolveException('no link in /api/sp/episode/link');
      }
      streamUrl = link;
    } else {
      final uri = Uri.parse(
          '$_kBase/api/episode?episodeId=${ids.episodeId}&showId=${ids.showId}');
      final resp = await c.get(uri, headers: const {
        'User-Agent': _kUserAgent,
        'X-Cartoony-Client': 'web-frontend-v1',
        'Accept': 'application/json',
        'Referer': '$_kBase/',
      });
      if (resp.statusCode != 200) {
        throw CarateenResolveException('HTTP ${resp.statusCode} for /api/episode');
      }
      final data = decryptCarateen(jsonDecode(utf8.decode(resp.bodyBytes)));
      final s = data is Map ? data['streamUrl'] : null;
      if (s is! String || s.isEmpty) {
        throw const CarateenResolveException('no streamUrl in /api/episode');
      }
      streamUrl = s;
    }

    // --- master-playlist expansion (unchanged) ---
    try {
      final master =
          await c.get(Uri.parse(streamUrl), headers: kCarateenMediaHeaders);
      if (master.statusCode == 200) {
        final variants = orderCarateenVariants(parseHlsMasterVariants(
            utf8.decode(master.bodyBytes), Uri.parse(streamUrl)));
        if (variants.length > 1) {
          return [
            for (final v in variants)
              CarateenStream(
                  server: v.name, streamUrl: v.url, headers: kCarateenMediaHeaders),
          ];
        }
      }
    } catch (_) {/* fall through */}
    return [
      CarateenStream(
          server: 'Carateen', streamUrl: streamUrl, headers: kCarateenMediaHeaders),
    ];
  } finally {
    if (own) c.close();
  }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/carateen_test.dart`
Expected: PASS (all groups, including the pre-existing tg tests).

- [ ] **Step 5: Commit**

```bash
git add lib/services/carateen_resolver.dart test/carateen_test.dart
git commit -m "feat(carateen): resolve SpaceToon (sp) episodes via /api/sp/episode/link"
```

---

### Task 2: Scraper — pull the sp catalog

**Files:**
- Modify: `tool/carateen_scrape.py`

**Interfaces:**
- Produces: `assets/carateen_catalog.json` now contains sp shows/movies with `play_url` of the form `https://carateen.tv/watch/sp/<showId>/<episodeId>`, ids namespaced `sp_<id>`, seasons grouped by the episode `season` field. Same top-level schema (`source, generated_at, tvshows, movies, music`).

- [ ] **Step 1: Add sp fetch + normalization functions**

In `tool/carateen_scrape.py`, add after the existing `build_item` function:

```python
# ------------------------------------------------------------- SpaceToon (sp)
SP_BASE_WATCH = BASE + "/watch/sp"


def _sp_episode(show_id, e):
    eid = e.get("id")
    return {
        "number": (e.get("number") or 0),
        "title": e.get("title") or f"الحلقة {e.get('number') or ''}".strip(),
        # sp episodes resolve via POST /api/sp/episode/link {episodeId}; the app's
        # carateen_resolver keys on the `/watch/sp/` marker in this URL.
        "play_url": f"{SP_BASE_WATCH}/{show_id}/{eid}",
        "video_id": str(e.get("video_id") or ""),
        "thumbnail": e.get("cover_full_path") or "",
        "season": (e.get("season") or 1),
        "hls": True,
    }


def build_sp_item(show, episodes):
    """Normalize an sp show to the SAME schema build_item emits. Groups episodes
    by their `season` field so multi-season titles (e.g. أبطال الكرة) render
    their seasons. Returns (kind, dict)."""
    sid = show["id"]
    eps = sorted(episodes, key=lambda x: (x.get("season") or 1, x.get("number") or 0))
    base = {
        "id": f"sp_{sid}",
        "title": show.get("name") or "",
        "poster_url": show.get("cover_full_path") or "",
        "description": _clean(show.get("pref")),
        "category": show.get("planet_name") or "",
        "year": _year({"release_year": show.get("release_year")}),
        "views": show.get("views"),
        "rating": show.get("rating"),
        "total_votes": show.get("total_votes"),
        "quality": "",
    }
    is_movie = bool(show.get("is_movie")) or len(eps) <= 1
    built = [_sp_episode(sid, e) for e in eps]
    if is_movie and built:
        base["play_url"] = built[0]["play_url"]
        return "movie", base
    # group into seasons[]
    seasons = {}
    for ep in built:
        seasons.setdefault(ep["season"], []).append(ep)
    base["seasons"] = [
        {"number": n, "title": "", "episodes": seasons[n]}
        for n in sorted(seasons)
    ]
    return "show", base


def scrape_sp(progress, log, stop, workers):
    """Fetch /api/sp/tvshows + /api/sp/episodes. Returns (tvshows, movies)."""
    log("fetching sp show list  /api/sp/tvshows …")
    shows = api("/api/sp/tvshows")
    total = len(shows)
    log(f"sp: {total} shows")
    results = [None] * total
    idx = {s["id"]: i for i, s in enumerate(shows)}
    done = 0

    def fetch(show):
        if stop():
            return show["id"], None
        eps = api(f"/api/sp/episodes?id={show['id']}")
        return show["id"], build_sp_item(show, eps if isinstance(eps, list) else [])

    with ThreadPoolExecutor(max_workers=workers) as ex:
        futs = [ex.submit(fetch, s) for s in shows]
        for fut in as_completed(futs):
            if stop():
                break
            sid, built = fut.result()
            if built is not None:
                results[idx[sid]] = built
            done += 1
            if done % 10 == 0 or done == total:
                progress(done, total, "sp")
                log(f"sp [{done}/{total}]")

    tv = [r[1] for r in results if r and r[0] == "show"]
    mv = [r[1] for r in results if r and r[0] == "movie"]
    log(f"sp catalog: {len(tv)} shows / {len(mv)} movies")
    return tv, mv
```

- [ ] **Step 2: Merge sp results into `run()`**

In `run()`, after the existing `movies = [...]` / `n_eps` block and before `music = scrape_music(log)`, add:

```python
    sp_tv, sp_mv = scrape_sp(progress, log, stop, workers)
    tvshows = tvshows + sp_tv
    movies = movies + sp_mv
    log(f"combined: {len(tvshows)} shows / {len(movies)} movies (tg + sp)")
```

- [ ] **Step 3: Run the scraper headless and verify أبطال الكرة is present**

Run:
```bash
python tool/carateen_scrape.py --headless
python -X utf8 -c "import json;d=json.load(open('assets/carateen_catalog.json',encoding='utf-8'));print('shows',len(d['tvshows']),'movies',len(d['movies']));print([s['id'] for s in d['tvshows'] if 'أبطال الكرة' in s['title']])"
```
Expected: show count jumps (~288 → ~600+); the second line prints sp ids including `sp_175`. A title with `seasons` length > 1 exists for the multi-season كرة entries.

- [ ] **Step 4: Commit**

```bash
git add tool/carateen_scrape.py assets/carateen_catalog.json
git commit -m "feat(carateen): scrape SpaceToon /api/sp catalog (adds أبطال الكرة +sp titles)"
```

---

### Task 3: Adapter — sp id + season passthrough test

**Files:**
- Modify: `lib/models/carateen_adapter.dart` (only if needed — verify first)
- Test: `test/carateen_test.dart` (extend)

**Interfaces:**
- Consumes: catalog JSON with sp items (`id` already `sp_<n>`, absolute `poster_url`, multi-season `seasons[]`).
- Produces: `Show` with `id` `c_sp_<n>`, `seasonCount == seasons.length`, episodes carrying the `/watch/sp/...` url.

- [ ] **Step 1: Write the failing test**

Add to `test/carateen_test.dart`:

```dart
test('parses an sp show with multiple seasons and sp play_urls', () {
  final (shows, _) = CarateenAdapter.parse({
    'tvshows': [
      {
        'id': 'sp_175',
        'title': 'أبطال الكرة',
        'poster_url': 'https://cdn.spacetoongo.com/x.jpg',
        'category': 'رياضة',
        'seasons': [
          {'number': 1, 'episodes': [
            {'number': 1, 'title': 'ح1', 'play_url': 'https://carateen.tv/watch/sp/175/12896'},
          ]},
          {'number': 2, 'episodes': [
            {'number': 1, 'title': 'ح1', 'play_url': 'https://carateen.tv/watch/sp/175/13001'},
          ]},
        ],
      }
    ],
    'movies': const [],
  });
  final s = shows.single;
  expect(s.id, 'c_sp_175');
  expect(s.source, CatalogSource.carateen);
  expect(s.seasonCount, 2);
  expect(s.episodes.first.episodeUrl, 'https://carateen.tv/watch/sp/175/12896');
});
```

- [ ] **Step 2: Run to verify it passes as-is**

Run: `flutter test test/carateen_test.dart -p vm --plain-name 'sp show with multiple seasons'`
Expected: PASS with **no adapter change** — the existing `_show` season loop already handles this. (If it fails, the only permitted fix is generalizing `_show` to read `seasons[].number`; do not special-case sp.)

- [ ] **Step 3: Commit**

```bash
git add test/carateen_test.dart lib/models/carateen_adapter.dart
git commit -m "test(carateen): lock sp multi-season adapter parsing"
```

---

## Part 2 — Library Modes

### Task 4: `LibraryMode` enum + storage + migration

**Files:**
- Create: `lib/models/library_mode.dart`
- Modify: `lib/services/storage_service.dart:52-55,208-213`
- Test: `test/library_mode_test.dart`

**Interfaces:**
- Produces: `enum LibraryMode { dubbed, carateen, arabic, wcoflix, everything }` with `String id`, `Set<CatalogSource> bundled`, `bool wcoflix`, getters `bool get showsArabic => bundled.isNotEmpty;` `bool get showsWcoflix => wcoflix;` `bool get isWcoflixOnly => wcoflix && bundled.isEmpty;`, and `static LibraryMode fromId(String?)`.
- Produces: `StorageService.getLibraryMode() -> LibraryMode`, `setLibraryMode(LibraryMode)`.

- [ ] **Step 1: Write the failing tests**

Create `test/library_mode_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/models/catalog_source.dart';
import 'package:kartoonia/models/library_mode.dart';

void main() {
  test('mode → bundled sources + wcoflix flags', () {
    expect(LibraryMode.dubbed.bundled,
        {CatalogSource.arabicToons, CatalogSource.stardima});
    expect(LibraryMode.carateen.bundled, {CatalogSource.carateen});
    expect(LibraryMode.arabic.bundled, {
      CatalogSource.arabicToons,
      CatalogSource.stardima,
      CatalogSource.carateen
    });
    expect(LibraryMode.wcoflix.showsArabic, isFalse);
    expect(LibraryMode.wcoflix.isWcoflixOnly, isTrue);
    expect(LibraryMode.everything.showsWcoflix, isTrue);
    expect(LibraryMode.everything.showsArabic, isTrue);
    expect(LibraryMode.everything.isWcoflixOnly, isFalse);
  });

  test('fromId round-trips and defaults to arabic', () {
    for (final m in LibraryMode.values) {
      expect(LibraryMode.fromId(m.id), m);
    }
    expect(LibraryMode.fromId('nonsense'), LibraryMode.arabic);
    expect(LibraryMode.fromId(null), LibraryMode.arabic);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/library_mode_test.dart`
Expected: FAIL — `library_mode.dart` missing.

- [ ] **Step 3: Create the enum**

Create `lib/models/library_mode.dart`:

```dart
import 'catalog_source.dart';

/// The five catalog modes the user picks in Settings. A mode scopes **Home and
/// Browse only** — My List, Search, Detail and playback are mode-independent.
///
///  - [dubbed]      Arabic Toons + Stardima (the dubbed-anime library).
///  - [carateen]    Carateen only (its own catalog, incl. SpaceToon-Go).
///  - [arabic]      All three bundled Arabic sources merged (the app default).
///  - [wcoflix]     The WCOFlix universe only.
///  - [everything]  Arabic (all three) AND WCOFlix, shown un-merged together.
enum LibraryMode {
  dubbed(
    id: 'dubbed',
    bundled: {CatalogSource.arabicToons, CatalogSource.stardima},
    wcoflix: false,
  ),
  carateen(
    id: 'carateen',
    bundled: {CatalogSource.carateen},
    wcoflix: false,
  ),
  arabic(
    id: 'arabic',
    bundled: {
      CatalogSource.arabicToons,
      CatalogSource.stardima,
      CatalogSource.carateen
    },
    wcoflix: false,
  ),
  wcoflix(
    id: 'wcoflix',
    bundled: {},
    wcoflix: true,
  ),
  everything(
    id: 'everything',
    bundled: {
      CatalogSource.arabicToons,
      CatalogSource.stardima,
      CatalogSource.carateen
    },
    wcoflix: true,
  );

  const LibraryMode(
      {required this.id, required this.bundled, required this.wcoflix});

  /// Stable persistence key value.
  final String id;

  /// Bundled Arabic catalogs this mode shows (empty for WCOFlix-only).
  final Set<CatalogSource> bundled;

  /// Whether the WCOFlix universe is shown.
  final bool wcoflix;

  bool get showsArabic => bundled.isNotEmpty;
  bool get showsWcoflix => wcoflix;
  bool get isWcoflixOnly => wcoflix && bundled.isEmpty;

  static LibraryMode fromId(String? id) => LibraryMode.values.firstWhere(
        (m) => m.id == id,
        orElse: () => LibraryMode.arabic,
      );
}
```

- [ ] **Step 4: Add storage accessors + migration**

In `lib/services/storage_service.dart`, add the import at the top with the other model imports:

```dart
import '../models/library_mode.dart';
```

Add the key next to `_kEverythingMode` (line ~54):

```dart
  static const _kLibraryMode = 'kt/libraryMode'; // dubbed|carateen|arabic|wcoflix|everything
```

Replace the `getEverythingMode`/`setEverythingMode` block (lines ~208-212) with:

```dart
  // Library mode scopes Home + Browse. Migrates the legacy everythingMode bool:
  // a one-time read maps true→wcoflix, false→arabic when libraryMode is unset.
  LibraryMode getLibraryMode() {
    final id = _prefs.getString(_kLibraryMode);
    if (id != null) return LibraryMode.fromId(id);
    final legacy = _prefs.getBool(_kEverythingMode);
    return legacy == true ? LibraryMode.wcoflix : LibraryMode.arabic;
  }

  Future<void> setLibraryMode(LibraryMode m) =>
      _prefs.setString(_kLibraryMode, m.id);
```

(Keep `_kEverythingMode` const for the migration read; nothing writes it anymore.)

- [ ] **Step 5: Run tests to verify they pass**

Run: `flutter test test/library_mode_test.dart`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/models/library_mode.dart lib/services/storage_service.dart test/library_mode_test.dart
git commit -m "feat(modes): add LibraryMode enum + storage migration from everythingMode"
```

---

### Task 5: Mode-scoped views in `CatalogService`

**Files:**
- Modify: `lib/services/catalog_service.dart`
- Test: `test/merged_catalog_test.dart` (extend)

**Interfaces:**
- Consumes: `LibraryMode` (Task 4), existing `all`, `_byId`, `availableOn`, `famousPool`, `genreRowsFor`.
- Produces: `LibraryMode activeMode` (default `arabic`), `void setMode(LibraryMode)`, `List<ContentItem> viewItems()`, `List<Show> viewShows()`, `List<Movie> viewMovies()`. **`shows`/`movies`/`all`/`search` stay global (mode-independent).** Home pool getters (`popularPool`, `popularShows`, `popularMovies`, `getFeaturedPool`, `genreRows`, `browse`) now derive from `viewItems()` and are invalidated on `setMode`.

- [ ] **Step 1: Write the failing tests**

Add to `test/merged_catalog_test.dart` (mirror its existing merged-catalog construction; it already builds a `CatalogService` from fixtures — reuse that helper). Add:

```dart
test('carateen mode view is pure carateen items', () async {
  final svc = await buildMergedFixtureService(); // existing test helper
  svc.setMode(LibraryMode.carateen);
  expect(svc.viewItems(), isNotEmpty);
  expect(svc.viewItems().every((i) => i.source == CatalogSource.carateen),
      isTrue);
});

test('dubbed mode excludes carateen-only titles', () async {
  final svc = await buildMergedFixtureService();
  svc.setMode(LibraryMode.dubbed);
  expect(
      svc.viewItems().any((i) =>
          svc.availableOn(i, CatalogSource.arabicToons) ||
          svc.availableOn(i, CatalogSource.stardima)),
      isTrue);
  expect(
      svc.viewItems().every((i) =>
          svc.availableOn(i, CatalogSource.arabicToons) ||
          svc.availableOn(i, CatalogSource.stardima)),
      isTrue);
});

test('wcoflix mode has an empty bundled view', () async {
  final svc = await buildMergedFixtureService();
  svc.setMode(LibraryMode.wcoflix);
  expect(svc.viewItems(), isEmpty);
});

test('setMode invalidates the featured pool', () async {
  final svc = await buildMergedFixtureService();
  svc.setMode(LibraryMode.arabic);
  final arabicFeatured = svc.getFeaturedPool().length;
  svc.setMode(LibraryMode.carateen);
  final carFeatured = svc.getFeaturedPool().length;
  expect(carFeatured, isNot(arabicFeatured)); // recomputed for the new mode
});
```

> If `buildMergedFixtureService()` does not already exist in the test file, add a small helper there that constructs the merged service the same way the file's existing tests do, and ensure the fixtures include at least one carateen-only title and one arabicToons title. Keep the helper in the test file.

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/merged_catalog_test.dart`
Expected: FAIL — `setMode`/`viewItems` undefined.

- [ ] **Step 3: Add mode-scoped views**

In `lib/services/catalog_service.dart`, add the import:

```dart
import '../models/library_mode.dart';
```

Add a field near `source` and a memo field near the other memos:

```dart
  /// Active Home/Browse mode. Does NOT affect [all]/[shows]/[movies]/[search].
  LibraryMode activeMode = LibraryMode.arabic;

  List<ContentItem>? _viewAll;
```

In `_invalidateDerived()`, add `_viewAll = null;`.

Add these methods (e.g. after `browse`):

```dart
  /// Switch the Home/Browse mode and drop mode-scoped caches.
  void setMode(LibraryMode mode) {
    if (mode == activeMode) return;
    activeMode = mode;
    _invalidateDerived();
  }

  /// The mode-scoped display pool. Memoized per active mode.
  List<ContentItem> viewItems() {
    if (_viewAll != null) return _viewAll!;
    final b = activeMode.bundled;
    if (b.isEmpty) return _viewAll = const [];
    if (b.length == 1) {
      final s = b.first;
      // Pure single source — include twins that global merge collapsed away.
      return _viewAll = [
        for (final i in _byId.values) if (i.source == s) i
      ];
    }
    // Multi-source: the merged library filtered to titles available on any
    // allowed source (collapsed primaries; 'arabic' keeps everything).
    return _viewAll = [
      for (final i in all)
        if (b.any((s) => availableOn(i, s))) i
    ];
  }

  List<Show> viewShows() => viewItems().whereType<Show>().toList();
  List<Movie> viewMovies() => viewItems().whereType<Movie>().toList();
```

Now point the Home/Browse-facing getters at `viewItems()` (leave Search on `all`). Change:

```dart
  List<ContentItem> popularPool() => _popularPool ??= famousPool(viewItems());
  List<Show> popularShows() => _popularShows ??= famousPool(viewShows());
  List<Movie> popularMovies() => _popularMovies ??= famousPool(viewMovies());
```

Change `getFeaturedPool()` to draw from `popularPool()` (already does) — no edit needed since it calls `popularPool()`. Change `_fameSortedGenreRows` and `getAllGenres`/`byGenre` used by Home to `viewItems()`:

```dart
  List<MapEntry<String, List<ContentItem>>> _fameSortedGenreRows(
          {required int min, required int cap}) =>
      [
        for (final e in genreRowsFor(viewItems(), min: min, cap: cap))
          MapEntry(e.key,
              e.value..sort((a, b) => b.fameScore.compareTo(a.fameScore))),
      ];
```

Change `browse(kind)` to use the view:

```dart
  List<ContentItem> browse(String kind) {
    switch (kind) {
      case 'movies':
        return viewMovies();
      case 'tv':
        return viewShows();
      default:
        return viewItems();
    }
  }
```

Leave `getRecentShows`/`getRecentMovies` as-is if Home uses them, but point them at views too:

```dart
  List<Show> getRecentShows({int count = 20}) => viewShows().take(count).toList();
  List<Movie> getRecentMovies({int count = 20}) => viewMovies().take(count).toList();
```

> `search()`, `getAllGenres()` for Search, `getById`, `alternatesFor`, `primaryFor` stay on the global index — do not change them.

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test test/merged_catalog_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/services/catalog_service.dart test/merged_catalog_test.dart
git commit -m "feat(modes): mode-scoped Home/Browse views in CatalogService"
```

---

### Task 6: Replace `everythingModeProvider` with `libraryModeProvider`

**Files:**
- Modify: `lib/state/wcoflix_providers.dart:14-29`
- Modify: `lib/state/app_state.dart` (remove `sourceFilter` from `BrowseState`; add mode plumbing if the catalog service is held there)
- Test: none (wiring; covered by screen tasks)

**Interfaces:**
- Produces: `libraryModeProvider` (`NotifierProvider<LibraryModeNotifier, LibraryMode>`) with `set(LibraryMode)` persisting via `storageProvider`. On set, also calls `catalogService.setMode(...)` so views refresh.
- Removes: `everythingModeProvider`, `EverythingModeNotifier`, `BrowseState.sourceFilter` + `setSourceFilter`.

- [ ] **Step 1: Add the mode notifier**

In `lib/state/wcoflix_providers.dart`, replace the `EverythingModeNotifier` class + `everythingModeProvider` (lines ~14-29) with:

```dart
/// Persisted library mode. Drives which sources Home + Browse show. Writing it
/// also flips the in-memory CatalogService view so Home/Browse rebuild scoped.
class LibraryModeNotifier extends Notifier<LibraryMode> {
  @override
  LibraryMode build() {
    final m = ref.read(storageProvider).getLibraryMode();
    ref.read(catalogServiceProvider).setMode(m);
    return m;
  }

  Future<void> set(LibraryMode m) async {
    if (m == state) return;
    ref.read(catalogServiceProvider).setMode(m);
    state = m;
    await ref.read(storageProvider).setLibraryMode(m);
  }
}

final libraryModeProvider =
    NotifierProvider<LibraryModeNotifier, LibraryMode>(LibraryModeNotifier.new);
```

Add the import `import '../models/library_mode.dart';` and confirm `catalogServiceProvider` is imported/defined (it lives in `app_state.dart`; add the import if needed). If `catalogServiceProvider` exposes the `CatalogService` singleton, `.setMode` is synchronous and safe here.

- [ ] **Step 2: Remove `sourceFilter` from `BrowseState`**

In `lib/state/app_state.dart`, delete the `sourceFilter` field (line ~134), its ctor param, the `copy` param + branch (lines ~149-157), and the `setSourceFilter` method (lines ~175-177). Leave `reset()` clearing the remaining transient filters.

- [ ] **Step 3: Update remaining references**

Search and replace usages so the app compiles:

Run: `grep -rn "everythingModeProvider\|EverythingModeNotifier\|sourceFilter\|setSourceFilter\|getEverythingMode\|setEverythingMode" lib/`

Every hit is addressed in Tasks 7–9 (screens) except any stray one — replace a boolean `everythingMode` read with `ref.watch(libraryModeProvider).showsWcoflix` (or `.isWcoflixOnly` where the intent was "WCOFlix-only home"). Do NOT leave `everythingModeProvider` referenced anywhere.

- [ ] **Step 4: Verify it compiles**

Run: `flutter analyze lib/state/`
Expected: no errors in `state/` (screen files still referenced in later tasks may error until Tasks 7-9 — that's expected; do not fix screens here beyond what's needed to keep `state/` clean).

- [ ] **Step 5: Commit**

```bash
git add lib/state/wcoflix_providers.dart lib/state/app_state.dart
git commit -m "feat(modes): libraryModeProvider replaces everythingMode; drop sourceFilter state"
```

---

### Task 7: Settings — 5-way mode picker

**Files:**
- Modify: `lib/screens/settings_screen.dart:126-160`
- Modify: `lib/screens/phone/phone_settings_screen.dart` (mirror, if it has the Everything toggle)
- Modify: `lib/i18n/strings.dart` (add mode labels)

**Interfaces:**
- Consumes: `libraryModeProvider`, `LibraryMode`.

- [ ] **Step 1: Add i18n labels**

In `lib/i18n/strings.dart`, add these keys to the Arabic (and any English) maps:

```dart
  'mode_title': 'وضع المكتبة',
  'mode_dubbed': 'ستارديما + عرب تونز',
  'mode_carateen': 'كراتين',
  'mode_arabic': 'كل العربية',
  'mode_wcoflix': 'WCOFlix',
  'mode_everything': 'كل شيء',
```

- [ ] **Step 2: Replace the On/Off block with a mode list**

In `lib/screens/settings_screen.dart`, replace the Everything On/Off `opt(...)` block (lines ~130-156) with a single-select list over `LibraryMode.values`, reusing the existing `opt(...)` row builder:

```dart
// Library mode — scopes Home + Browse (My List/Search stay global).
final mode = ref.watch(libraryModeProvider);
String label(LibraryMode m) => {
      LibraryMode.dubbed: t['mode_dubbed']!,
      LibraryMode.carateen: t['mode_carateen']!,
      LibraryMode.arabic: t['mode_arabic']!,
      LibraryMode.wcoflix: t['mode_wcoflix']!,
      LibraryMode.everything: t['mode_everything']!,
    }[m]!;
// ...inside the settings section titled t['mode_title']:
for (final m in LibraryMode.values)
  opt(label(m), mode == m,
      () => ref.read(libraryModeProvider.notifier).set(m)),
```

Match the surrounding section's widget structure (the `opt` helper and its container) exactly — only the option set changes.

- [ ] **Step 3: Mirror on phone settings (if present)**

If `phone_settings_screen.dart` renders the Everything toggle, apply the same replacement there.

- [ ] **Step 4: Verify**

Run: `flutter analyze lib/screens/settings_screen.dart lib/screens/phone/phone_settings_screen.dart`
Expected: no errors.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/settings_screen.dart lib/screens/phone/phone_settings_screen.dart lib/i18n/strings.dart
git commit -m "feat(modes): 5-way library-mode picker in Settings"
```

---

### Task 8: Browse — scope by mode, remove the source filter

**Files:**
- Modify: `lib/screens/browse_screen.dart`
- Modify: `lib/screens/phone/phone_browse_screen.dart`

**Interfaces:**
- Consumes: `libraryModeProvider`, `catalog.browse(kind)` (already mode-scoped), existing `wcoflixTvBrowseProvider`/movies providers.

- [ ] **Step 1: Remove the per-source filter UI + logic**

In `lib/screens/browse_screen.dart`:
- Delete the source-filter chips/dialog (the block around lines ~360-440 that builds `CatalogSource` options and calls `setSourceFilter`).
- Delete `final srcFilter = browse.sourceFilter;` and the `.availableOn(i, srcFilter)` filtering (lines ~40-71). The grid now comes straight from `catalog.browse(kind)` for Arabic universes.
- Replace `final everything = ref.watch(everythingModeProvider);` with `final mode = ref.watch(libraryModeProvider);`.

- [ ] **Step 2: Choose the grid source by mode**

Replace the `wco`/grid-selection logic (lines ~39-71) with:

```dart
final mode = ref.watch(libraryModeProvider);
// My List ignores mode. Otherwise: WCOFlix-only mode → wco grid; Arabic modes →
// the mode-scoped local grid; Everything → a universe toggle (Step 3).
final useWco = !isMyList && mode.isWcoflixOnly;
```

For `isMyList`, keep the existing global My List path untouched. For Arabic grids, use `catalog.browse(kind)` directly (no `availableOn` filter).

- [ ] **Step 3: Everything universe toggle**

When `!isMyList && mode == LibraryMode.everything`, render a top segmented control **[العربية | WCOFlix]** (local `useState`/`StateProvider`, default العربية) that swaps between `catalog.browse(kind)` and the `wcoflix*BrowseProvider` grid. Reuse the existing pill/segmented widget used elsewhere in the screen. Add i18n keys `'universe_arabic': 'العربية'` (reuse `mode_wcoflix` for the WCOFlix label).

- [ ] **Step 4: Mirror on phone browse**

Apply the same three edits to `phone_browse_screen.dart` (remove the phone source-filter rail, scope by mode, add the Everything universe toggle at phone scale).

- [ ] **Step 5: Verify**

Run: `flutter analyze lib/screens/browse_screen.dart lib/screens/phone/phone_browse_screen.dart`
Expected: no errors; no remaining `sourceFilter`/`everythingModeProvider` references.

- [ ] **Step 6: Commit**

```bash
git add lib/screens/browse_screen.dart lib/screens/phone/phone_browse_screen.dart lib/i18n/strings.dart
git commit -m "feat(modes): Browse grids scoped by mode; remove source filter; Everything universe toggle"
```

---

### Task 9: Home — scope by mode, Everything = Arabic + WCOFlix rows

**Files:**
- Modify: `lib/screens/home_screen.dart`
- Modify: `lib/screens/phone/phone_home_screen.dart`

**Interfaces:**
- Consumes: `libraryModeProvider`, mode-scoped `catalog` pools (Task 5), `wco*` providers.

- [ ] **Step 1: Branch Home on mode instead of the bool**

In `lib/screens/home_screen.dart`, replace the `everythingMode` branch (where it currently picks the WCOFlix home vs the Arabic home) with:

```dart
final mode = ref.watch(libraryModeProvider);
// WCOFlix-only → the WCOFlix home. Any Arabic mode → the mode-scoped Arabic home
// (pools already scoped by CatalogService.viewItems). Everything → Arabic home
// PLUS a WCOFlix section appended (Step 2).
if (mode.isWcoflixOnly) {
  return _buildWcoflixHome(...);   // existing WCOFlix home body
}
// else Arabic home — the existing Arabic body, unchanged (pools are scoped).
```

Since `CatalogService` pools are already mode-scoped, the Arabic home body needs **no per-row edits** — `getFeaturedPool`, `mostPopular`, `genreRows`, recent rows all narrow automatically to the active mode.

- [ ] **Step 2: Everything mode — append WCOFlix rows**

When `mode == LibraryMode.everything`, after the Arabic rows, append a labelled WCOFlix section built from the same `wco*` row providers the WCOFlix home uses (Top-10, cartoons, dubbed, movies), under a section header (reuse `mode_wcoflix` as the label). Do not merge them into the Arabic rows.

- [ ] **Step 3: Mirror on phone home**

Apply the same mode branch to `phone_home_screen.dart`.

- [ ] **Step 4: Verify the app builds + smoke test**

Run: `flutter analyze lib/` then `flutter test`
Expected: analyze clean; all tests pass. Then manual smoke per Task-11 verification.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/home_screen.dart lib/screens/phone/phone_home_screen.dart
git commit -m "feat(modes): Home scoped by mode; Everything shows Arabic + WCOFlix rows"
```

---

## Part 3 — Spotlight hero

### Task 10: `HeroCarousel` spotlight-card layout

**Files:**
- Modify: `lib/widgets/hero_carousel.dart`
- Test: `test/hero_carousel_test.dart`

**Interfaces:**
- Consumes: unchanged public API (`items`, `t`, `isRtl`, `autoplay`, `onPlay`, `onMoreInfo`, `onToggleList`, `isInList`, `onBackdrop`).
- Produces: the same widget, rendered as a centered 16:9 backdrop **card** with dimmed peek slivers of the prev/next titles, title + meta + three pills **below** the card, dots below the pills. Auto-advance slides between titles; low-spec falls back to cross-fade. Focus/D-pad behavior preserved (pills focusable, Watch autofocus, dots navigate).

- [ ] **Step 1: Write the failing widget test**

Create `test/hero_carousel_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/models/catalog_source.dart';
import 'package:kartoonia/models/content_item.dart';
import 'package:kartoonia/widgets/hero_carousel.dart';

Show _show(String id, String title) => Show(
      id: id, title: title, thumbnailUrl: 'https://x/$id.jpg',
      description: 'd', tmdb: TmdbData(backdropUrl: 'https://x/$id-bd.jpg'),
      totalEpisodes: 1, seasonCount: 1, seasons: const [], episodes: const [],
      source: CatalogSource.carateen);

void main() {
  testWidgets('renders the current title, three action pills, and dots',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: HeroCarousel(
          items: [_show('1', 'أبطال الكرة'), _show('2', 'كونان')],
          t: const {
            'featured': 'مميز', 'watchNow': 'شاهد', 'moreInfo': 'معلومات',
            'myList': 'قائمتي', 'inList': 'في قائمتي', 'season': 'موسم',
            'movie': 'فيلم',
          },
          isRtl: true, autoplay: false,
          onPlay: (_) {}, onMoreInfo: (_) {}, onToggleList: (_) {},
          isInList: (_) => false,
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('أبطال الكرة'), findsOneWidget);
    expect(find.text('شاهد'), findsOneWidget);
    expect(find.text('معلومات'), findsOneWidget);
    expect(find.text('قائمتي'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run to verify it fails or passes**

Run: `flutter test test/hero_carousel_test.dart`
Expected: PASS on the current widget too (the pills/title already exist). This test is the **regression guard** for the redesign — keep it green through Step 3.

- [ ] **Step 3: Restructure `build()` into the spotlight layout**

Rework `hero_carousel.dart`'s `build()` so the hero band is a `Column`:
1. A fixed-height row containing: a dimmed non-focusable peek of `items[(index-1)%n]` (RTL: on the right), the **centered 16:9 card** (`AspectRatio(aspectRatio: 16/9)` inside the band height, rounded `ClipRRect`, `CatalogImage(url: s.backdropUrl, fallbackUrl: s.thumbnailUrl)` with the existing 1.06 overscan), and a dimmed peek of `items[(index+1)%n]` (RTL: on the left). Peeks are ~12% band width, `Opacity(0.45)`.
2. The title (existing `Fonts.display` style, smaller — `fontSize: 48`), meta line (`_metaLine`), and the three pills row (**unchanged** pill widgets/order/callbacks) — all below the card, aligned per `isRtl`.
3. The dots row (unchanged), below the pills.

Keep:
- The `AnimatedSwitcher` cross-fade keyed on `s.id` for the card image; on non-low-spec use a horizontal `SlideTransition` (slide the card) — implement via `AnimatedSwitcher` with a `transitionBuilder` returning a `SlideTransition` for `!DevicePerf.lowSpec`, else the fade.
- `_emitBackdrop()`, `_start()` timer, `_focusInside` pause, index clamp — all unchanged.
- The blurred `_HeroBackdropFill` is painted by the shell behind the band (in `home_screen.dart`) — leave that call site as-is.

Preserve the `Dims.heroH` band height. The card width is derived from the band height (`heroH * 16/9`) and centered; peeks fill the remaining width.

- [ ] **Step 4: Run the regression test + analyze**

Run: `flutter test test/hero_carousel_test.dart && flutter analyze lib/widgets/hero_carousel.dart`
Expected: PASS + no analyzer errors.

- [ ] **Step 5: Commit**

```bash
git add lib/widgets/hero_carousel.dart test/hero_carousel_test.dart
git commit -m "feat(hero): backdrop-sized spotlight card carousel (layout A)"
```

---

### Task 11: Release verification + version bump

**Files:**
- Modify: `pubspec.yaml` (version)

- [ ] **Step 1: Full test + analyze gate**

Run: `flutter analyze && flutter test`
Expected: analyze clean; every test passes.

- [ ] **Step 2: Manual smoke on a device/emulator**

Run: `flutter run` (or the project's `/run` skill). Verify, in order:
1. Settings shows the 5 modes; selecting each persists across a restart.
2. **Carateen mode** → Browse TV grid contains **أبطال الكرة**; open it → seasons show; play an episode → it streams (720p default).
3. **Dubbed mode** hides carateen-only titles; **Arabic mode** shows all three; **WCOFlix mode** shows the WCOFlix library; **Everything** shows Arabic rows + a WCOFlix section.
4. My List content is identical across every mode.
5. Home hero renders as a centered backdrop card with side peeks, title/pills below, dots; auto-advances; D-pad reaches the pills and dots.

- [ ] **Step 3: Bump version**

In `pubspec.yaml`: `version: 3.3.0+30`.

- [ ] **Step 4: Commit**

```bash
git add pubspec.yaml
git commit -m "chore(release): v3.3.0 — library modes, Carateen SpaceToon, spotlight hero"
```

---

## Self-Review

**Spec coverage:**
- Modes (5) → Tasks 4–9. ✓
- Home/Browse-only scope; My List/Search/Detail global → Task 5 (views leave `all`/`search` untouched) + Task 8/9. ✓
- Everything = Arabic-3 + WCOFlix un-merged → Task 8 (universe toggle) + Task 9 (appended rows). ✓
- Settings 5-way picker → Task 7. ✓
- Browse filter removed → Task 8. ✓
- Storage migration → Task 4. ✓
- Carateen sp catalog (scrape) → Task 2; resolver → Task 1; adapter → Task 3. ✓
- Spotlight hero (A) → Task 10. ✓
- Version bump rule → Task 11 + Global Constraints. ✓

**Placeholder scan:** No TBD/TODO. The two "if present / mirror" steps (phone screens, `buildMergedFixtureService`) are conditional-but-explicit (exact edit named), not placeholders.

**Type consistency:** `LibraryMode` fields (`id`, `bundled`, `wcoflix`, `showsArabic`, `showsWcoflix`, `isWcoflixOnly`, `fromId`) consistent across Tasks 4–9. `parseCarateenPlayUrl` `isSp` used consistently in Tasks 1 & 3. `viewItems`/`viewShows`/`viewMovies`/`setMode`/`activeMode` consistent Tasks 5–6. `libraryModeProvider`/`LibraryModeNotifier.set` consistent Tasks 6–9.
