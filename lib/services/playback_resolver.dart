import '../models/catalog_source.dart';
import 'stardima_resolver.dart';
import 'token_service.dart';

/// One playable server option for the player: a ready-to-open URL plus the
/// headers the CDN requires, with a small label/number for the server picker.
class PlayableServer {
  final int number;
  final String label;
  final String url;
  final Map<String, String> headers;

  const PlayableServer({
    required this.number,
    required this.label,
    required this.url,
    required this.headers,
  });
}

/// Resolve playable servers for an item, branching on its catalog source so the
/// player stays source-agnostic:
///
///  - [CatalogSource.arabicToons]: scrape FRESH IP/time-bound tokens from the
///    page URL (never cached) and play the tokenized URL directly.
///  - [CatalogSource.stardima]: run the hyperwatching → host-embed → `.m3u8`
///    resolver pipeline; each host becomes a numbered server with its own
///    Referer/UA headers.
Future<List<PlayableServer>> resolvePlayback(
  CatalogSource source,
  String pageOrPlayUrl,
) async {
  switch (source) {
    case CatalogSource.arabicToons:
      final servers = await fetchFreshTokens(pageOrPlayUrl);
      return [
        for (final s in servers)
          PlayableServer(
            number: s.serverNumber,
            label: 'Server ${s.serverNumber}',
            url: s.rawUrl,
            headers: kStreamHeaders,
          ),
      ];
    case CatalogSource.stardima:
      final streams = await resolveStardima(pageOrPlayUrl);
      return [
        for (var i = 0; i < streams.length; i++)
          PlayableServer(
            number: i + 1,
            label: streams[i].server,
            url: streams[i].streamUrl,
            headers: streams[i].headers,
          ),
      ];
  }
}
