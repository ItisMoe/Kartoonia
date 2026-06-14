import 'dart:convert';
import 'package:http/http.dart' as http;

/// Stardima on-demand resolver — ported from `stardima_resolver.py`.
///
/// Given a show's Arabic title (+ season/episode) it resolves EXTRA streaming
/// servers from Stardima, live. The "all-in-one" hyperwatching iframe is never
/// surfaced — only the individual host embeds. Each embed is then reduced to a
/// direct stream (Approach A) where possible; callers fall back to embedding it
/// (Approach B) when [resolveDirect] returns null.
///
/// Runs ONLY when the player opens an item — never as a catalog-wide sweep.

const _star = 'https://www.stardima.com';
const _hw = 'https://hyperwatching.com';
const _ua =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';

/// Cooperative cancellation — flipped when the player closes / changes episode.
class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

class StardimaException implements Exception {
  final String message;
  StardimaException(this.message);
  @override
  String toString() => 'StardimaException: $message';
}

/// A resolved Stardima host entry. [directUrl]/[headers] are filled lazily by
/// [resolveDirect]; until then only [embedUrl] is known.
class StardimaServer {
  final String name;
  final String embedUrl;
  String? directUrl;
  Map<String, String>? headers;
  bool isHls = false;

  /// NAME / language of the Arabic alternative-audio rendition in the HLS
  /// master, when present (so a capable player can force Arabic audio).
  String? arabicAudio;

  bool triedDirect = false;

  StardimaServer({required this.name, required this.embedUrl});
}

class StardimaService {
  final http.Client _client = http.Client();

  /// Stardima series index (title -> show url), loaded from the bundled asset.
  /// Title matching uses this first (the site /search is too broad); seasons,
  /// episodes and servers are always resolved live.
  List<Map<String, dynamic>> _index = const [];
  bool get hasIndex => _index.isNotEmpty;

  void setIndex(String json) {
    try {
      _index = ((jsonDecode(json) as List?) ?? const [])
          .map((e) => (e as Map).cast<String, dynamic>())
          .toList();
    } catch (_) {
      _index = const [];
    }
  }

  Map<String, String> get _baseHeaders =>
      {'User-Agent': _ua, 'Accept-Language': 'ar,en;q=0.9'};

  void _check(CancelToken? c) {
    if (c?.isCancelled ?? false) throw StardimaException('cancelled');
  }

  // ---- title matching (Dice bigram coefficient ≈ difflib ratio) ----
  String _norm(String s) =>
      s.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();

  double _similarity(String a, String b) {
    a = _norm(a);
    b = _norm(b);
    if (a == b) return 1;
    if (a.length < 2 || b.length < 2) return 0;
    Map<String, int> bigrams(String s) {
      final m = <String, int>{};
      for (var i = 0; i < s.length - 1; i++) {
        final g = s.substring(i, i + 2);
        m[g] = (m[g] ?? 0) + 1;
      }
      return m;
    }

    final ma = bigrams(a), mb = bigrams(b);
    var inter = 0;
    ma.forEach((g, n) {
      final o = mb[g];
      if (o != null) inter += n < o ? n : o;
    });
    final total = (a.length - 1) + (b.length - 1);
    return total == 0 ? 0 : (2.0 * inter) / total;
  }

  // ---- Stardima chain ----
  Future<List<dynamic>> _search(String title, CancelToken? c) async {
    final r = await _client.get(
      Uri.parse('$_star/search?q=${Uri.encodeQueryComponent(title)}'),
      headers: {..._baseHeaders, 'X-Requested-With': 'XMLHttpRequest'},
    );
    _check(c);
    if (r.statusCode != 200) return const [];
    return (jsonDecode(r.body)['videos'] as List?) ?? const [];
  }

  Future<String?> _playUrl(String showUrl, CancelToken? c) async {
    final r = await _client.get(Uri.parse(showUrl), headers: _baseHeaders);
    _check(c);
    final m = RegExp(r'og:video"\s+content="([^"]+)"').firstMatch(r.body);
    return m?.group(1);
  }

  Future<List<({String id, String number})>> _seasons(
      String showUrl, CancelToken? c) async {
    final play = await _playUrl(showUrl, c);
    if (play == null) return const [];
    final r = await _client
        .get(Uri.parse(play), headers: {..._baseHeaders, 'Referer': showUrl});
    _check(c);
    return RegExp(r'data-season-id="(\d+)"\s+data-season-number="([^"]*)"')
        .allMatches(r.body)
        .map((m) => (id: m.group(1)!, number: m.group(2)!))
        .toList();
  }

  Future<List<dynamic>> _episodes(String seasonId, CancelToken? c) async {
    final r = await _client.get(
      Uri.parse('$_star/series/season/$seasonId'),
      headers: {..._baseHeaders, 'X-Requested-With': 'XMLHttpRequest'},
    );
    _check(c);
    if (r.statusCode != 200) return const [];
    return (jsonDecode(r.body)['episodes'] as List?) ?? const [];
  }

  Future<List<StardimaServer>> _servers(String watchUrl, CancelToken? c) async {
    final code =
        RegExp(r'/iframe/([^/?#]+)').firstMatch(watchUrl)?.group(1);
    if (code == null) return const [];
    final iframe = '$_hw/iframe/$code';
    final r =
        await _client.get(Uri.parse(iframe), headers: {..._baseHeaders, 'Referer': '$_star/'});
    _check(c);
    final csrf = RegExp(r'csrf:\s*"([^"]+)"').firstMatch(r.body)?.group(1);
    if (csrf == null) return const [];
    final srv = RegExp(r'id:\s*"(\d+)",\s*name:\s*"([^"]+)"')
        .allMatches(r.body)
        .map((m) => (id: m.group(1)!, name: m.group(2)!))
        .toList();
    final out = <StardimaServer>[];
    for (final s in srv) {
      _check(c);
      try {
        final pr = await _client.post(
          Uri.parse('$_hw/api/videos/$code/link'),
          headers: {
            'Content-Type': 'application/json',
            'X-CSRF-TOKEN': csrf,
            'X-Requested-With': 'XMLHttpRequest',
            'Referer': iframe,
            'Origin': _hw,
            'User-Agent': _ua,
          },
          body: jsonEncode({'server_link_id': s.id}),
        );
        final wu = jsonDecode(pr.body)['watch_url'] as String?;
        if (wu != null && wu.isNotEmpty) {
          out.add(StardimaServer(name: s.name, embedUrl: wu));
        }
      } catch (_) {
        // skip a failed host
      }
    }
    return out;
  }

  /// Full chain: Arabic [title] -> best Stardima show -> season -> episode ->
  /// host server embeds (the all-in-one player is never included).
  ({Map<String, dynamic>? show, double conf}) _matchIndex(String title) {
    Map<String, dynamic>? best;
    var bestScore = 0.0;
    for (final v in _index) {
      final score = _similarity(title, (v['title'] ?? '').toString());
      if (score > bestScore) {
        bestScore = score;
        best = v;
      }
    }
    return (show: best, conf: bestScore);
  }

  Future<List<StardimaServer>> resolveServers(
    String title, {
    int? season,
    int episode = 1,
    CancelToken? cancel,
  }) async {
    // 1) match the bundled index (accurate); 2) fall back to live site search.
    var (show: best, conf: bestScore) = _matchIndex(title);
    if (best == null || bestScore < 0.6) {
      final vids = await _search(title, cancel);
      for (final v in vids) {
        final score = _similarity(title, (v['title'] ?? '').toString());
        if (score > bestScore) {
          bestScore = score;
          best = (v as Map).cast<String, dynamic>();
        }
      }
    }
    if (best == null || bestScore < 0.5) return const [];
    final showUrl = best['url']?.toString();
    if (showUrl == null) return const [];

    final ssn = await _seasons(showUrl, cancel);
    String? seasonId;
    if (ssn.isNotEmpty) {
      if (season != null) {
        for (final s in ssn) {
          if (s.number.contains('$season')) {
            seasonId = s.id;
            break;
          }
        }
      }
      seasonId ??= ssn.first.id;
    }
    if (seasonId == null) return const [];

    final eps = await _episodes(seasonId, cancel);
    if (eps.isEmpty) return const [];
    Map? ep;
    for (final e in eps) {
      if ((e['episode_number'] as num?)?.toInt() == episode) {
        ep = e as Map;
        break;
      }
    }
    ep ??= eps.first as Map;
    final watchUrl = ep['watch_url']?.toString() ?? '';
    return _servers(watchUrl, cancel);
  }

  // ---- Approach A: reduce a host embed to a direct stream ----
  // .m3u8 / .mp4 anywhere in text (handles escaped \/ slashes too).
  static final RegExp _urlRe = RegExp(
      r'''https?:\\?/\\?/[^\s"'\\)\]]+?\.(?:m3u8|mp4)[^\s"'\\)\]]*''');

  /// Scrapes the host embed page and reduces it to a direct stream
  /// (master.m3u8 / .mp4), incl. packer-hidden URLs — ported from
  /// `stardima_player.extract_stream`. Returns true if [server] now has a
  /// [directUrl]; false => caller falls back to the embed (Approach B).
  Future<bool> resolveDirect(StardimaServer server, {CancelToken? cancel}) async {
    if (server.triedDirect) return server.directUrl != null;
    server.triedDirect = true;
    try {
      // strema.top wrapper carries the real host url in its `id` query param.
      var target = server.embedUrl;
      var fetchReferer = '$_hw/';
      final em = Uri.tryParse(server.embedUrl);
      if (em != null && em.host.contains('strema')) {
        final inner = em.queryParameters['id'];
        if (inner != null && inner.startsWith('http')) {
          fetchReferer = '${em.scheme}://${em.host}/';
          target = inner;
        }
      }
      final pageOrigin = _origin(target);
      final r = await _client.get(Uri.parse(target), headers: {
        ..._baseHeaders,
        'Referer': fetchReferer,
        'Accept': '*/*',
      });
      _check(cancel);

      // search the raw page AND any unpacked packer blocks
      final found = <String>[];
      void collect(String hay) {
        for (final m in _urlRe.allMatches(hay)) {
          found.add(m.group(0)!.replaceAll(r'\/', '/'));
        }
      }

      collect(r.body);
      final unpacked = _unpack(r.body);
      if (unpacked != null) collect(unpacked);
      if (found.isEmpty) return false;

      // prefer a master HLS playlist, then any HLS, then mp4
      final uniq = found.toSet().toList();
      int rank(String u) {
        final lu = u.toLowerCase();
        if (lu.contains('master.m3u8')) return 0;
        if (lu.contains('.m3u8')) return 1;
        return 2;
      }

      uniq.sort((a, b) => rank(a).compareTo(rank(b)));
      final stream = uniq.first;

      server.directUrl = stream;
      server.isHls = stream.toLowerCase().contains('.m3u8');
      // Headers the CDN expects: Referer/Origin = the embed host (NOT the CDN).
      server.headers = {
        'User-Agent': _ua,
        'Referer': pageOrigin,
        'Origin': pageOrigin.replaceAll(RegExp(r'/$'), ''),
      };
      // Locate the Arabic alternative-audio rendition (if any) so a capable
      // player can force it (ported from `stardima_player.audio_tracks`).
      if (server.isHls) {
        server.arabicAudio =
            await _findArabicAudio(stream, pageOrigin, cancel);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  String _origin(String url) {
    final u = Uri.tryParse(url);
    if (u == null || u.scheme.isEmpty || u.host.isEmpty) return '$_hw/';
    return '${u.scheme}://${u.host}/';
  }

  Map<String, String> _parseMediaAttrs(String line) {
    final out = <String, String>{};
    final re = RegExp(r'([A-Z0-9-]+)=("[^"]*"|[^,]*)');
    for (final m in re.allMatches(line)) {
      out[m.group(1)!] = m.group(2)!.replaceAll('"', '');
    }
    return out;
  }

  Future<String?> _findArabicAudio(
      String masterUrl, String referer, CancelToken? cancel) async {
    try {
      final r = await _client.get(Uri.parse(masterUrl),
          headers: {..._baseHeaders, 'Referer': referer});
      _check(cancel);
      for (final line in r.body.split('\n')) {
        if (line.startsWith('#EXT-X-MEDIA') && line.contains('TYPE=AUDIO')) {
          final a = _parseMediaAttrs(line);
          final name = a['NAME'] ?? '';
          final lang = (a['LANGUAGE'] ?? '').toLowerCase();
          final isAr = lang == 'ar' ||
              lang == 'ara' ||
              lang == 'arabic' ||
              name.contains('عرب') ||
              name.contains('العربية');
          if (isAr) return name.isNotEmpty ? name : lang;
        }
      }
    } catch (_) {}
    return null;
  }

  // ---- Dean Edwards p,a,c,k,e,d unpacker (single-pass, all blocks) ----
  String? _unpack(String src) {
    const digits =
        '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final re = RegExp(
      r"\}\('(.*?)',(\d+),(\d+),'(.*?)'\.split\('\|'\)",
      dotAll: true,
    );
    final blocks = <String>[];
    for (final m in re.allMatches(src)) {
      final payload = m.group(1)!;
      final base = int.parse(m.group(2)!);
      final count = int.parse(m.group(3)!);
      final words = m.group(4)!.split('|');

      String enc(int n) {
        if (n == 0) return '0';
        var s = '';
        var x = n;
        while (x > 0) {
          s = digits[x % base] + s;
          x ~/= base;
        }
        return s;
      }

      final table = <String, String>{};
      for (var i = 0; i < count; i++) {
        final k = enc(i);
        table[k] = (i < words.length && words[i].isNotEmpty) ? words[i] : k;
      }
      blocks.add(payload.replaceAllMapped(
          RegExp(r'\b\w+\b'), (mo) => table[mo.group(0)!] ?? mo.group(0)!));
    }
    return blocks.isEmpty ? null : blocks.join('\n');
  }

  void dispose() => _client.close();
}
