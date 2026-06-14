import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../theme/theme.dart';
import '../utils/image_urls.dart';

/// Network image for catalog art. arabic-toons CDN images get the required
/// Referer header; TMDB images load directly. If the primary URL fails (e.g. a
/// broken/missing TMDB poster) it falls back to [fallbackUrl] (the catalog
/// thumbnail) before showing the branded placeholder — so a usable catalog
/// thumbnail is never replaced by an empty box.
class CatalogImage extends StatelessWidget {
  final String url;
  final String? fallbackUrl;
  final BoxFit fit;
  const CatalogImage({
    super.key,
    required this.url,
    this.fallbackUrl,
    this.fit = BoxFit.cover,
  });

  static Widget _placeholder() => const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [AppColors.bg2, AppColors.bg3],
          ),
        ),
        child: Center(
          child: Icon(Icons.movie_outlined, color: AppColors.inkMute, size: 44),
        ),
      );

  Widget _image(String u, {Widget Function()? onError}) => CachedNetworkImage(
        imageUrl: u,
        fit: fit,
        httpHeaders: needsReferer(u) ? kImageHeaders : null,
        fadeInDuration: const Duration(milliseconds: 200),
        placeholder: (_, _) => _placeholder(),
        errorWidget: (_, _, _) => (onError ?? _placeholder)(),
      );

  @override
  Widget build(BuildContext context) {
    if (url.isEmpty) {
      final f = fallbackUrl;
      return (f != null && f.isNotEmpty) ? _image(f) : _placeholder();
    }
    final f = fallbackUrl;
    final hasFallback = f != null && f.isNotEmpty && f != url;
    return _image(
      url,
      onError: hasFallback ? () => _image(f) : null,
    );
  }
}
