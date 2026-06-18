import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../models/content_item.dart';
import 'image_urls.dart';

/// Warm the image cache for [items]' posters so they decode before the user
/// scrolls them into view — smoother row reveals on low-power TV dongles.
/// Best-effort: errors are swallowed, and the count is capped so a launch
/// doesn't fire a burst of hundreds of requests.
void prefetchPosters(BuildContext context, Iterable<ContentItem> items,
    {int limit = 24}) {
  final seen = <String>{};
  for (final item in items) {
    if (seen.length >= limit) break;
    final url = item.posterUrl;
    if (url.isEmpty || !seen.add(url)) continue;
    final provider = CachedNetworkImageProvider(
      url,
      headers: needsReferer(url) ? kImageHeaders : null,
    );
    precacheImage(provider, context, onError: (_, _) {});
  }
}
