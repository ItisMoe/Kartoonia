import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';
import '../services/youtube_service.dart';
import '../state/app_state.dart';
import '../theme/theme.dart';
import '../widgets/focusable.dart';

/// In-app trailer / theme-song player. Searches YouTube for [query] and plays
/// the first result in a TV-friendly WebView. Separate from the main streaming
/// player. Disposes cleanly on close (no audio continues).
class YoutubeScreen extends ConsumerStatefulWidget {
  final String query;
  final String title;
  const YoutubeScreen({super.key, required this.query, required this.title});
  @override
  ConsumerState<YoutubeScreen> createState() => _YoutubeScreenState();
}

class _YoutubeScreenState extends ConsumerState<YoutubeScreen> {
  WebViewController? _wc;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _search();
  }

  Future<void> _search() async {
    try {
      final userKey = ref.read(storageProvider).getYoutubeKey();
      final id = await YoutubeService.firstVideoId(widget.query, apiKey: userKey);
      if (!mounted) return;
      if (id == null) {
        setState(() {
          _loading = false;
          _failed = true;
        });
        return;
      }
      final controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.black);
      // allow autoplay without a user gesture (Android) — must be set BEFORE
      // the page loads, otherwise the first playback attempt is still gated.
      if (controller.platform is AndroidWebViewController) {
        (controller.platform as AndroidWebViewController)
            .setMediaPlaybackRequiresUserGesture(false);
      }
      // Load the player as an <iframe> inside a page whose base URL is a valid
      // YouTube origin. Loading the /embed URL directly as the top-level
      // document leaves the referrer empty, so YouTube refuses playback with
      // error 150/153 ("Video unavailable"). A youtube.com base URL gives the
      // embed a referrer it can verify, which is what lets the video play.
      await controller.loadHtmlString(_playerHtml(id),
          baseUrl: 'https://www.youtube.com');
      setState(() {
        _wc = controller;
        _loading = false;
      });
    } catch (e) {
      debugPrint('YouTube trailer failed: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  /// Full-bleed HTML host for the YouTube IFrame embed. Kept minimal so the
  /// player fills the TV screen with no scrollbars or chrome.
  String _playerHtml(String id) => '''
<!DOCTYPE html>
<html>
  <head>
    <meta name="viewport" content="width=device-width, initial-scale=1.0, user-scalable=no">
    <style>
      html, body { margin: 0; padding: 0; height: 100%; background: #000; overflow: hidden; }
      iframe { position: fixed; top: 0; left: 0; width: 100%; height: 100%; border: 0; }
    </style>
  </head>
  <body>
    <iframe
      src="https://www.youtube.com/embed/$id?autoplay=1&playsinline=1&rel=0&modestbranding=1&fs=1"
      allow="autoplay; encrypted-media; fullscreen"
      allowfullscreen>
    </iframe>
  </body>
</html>
''';

  @override
  void dispose() {
    _wc = null; // WebViewWidget removal disposes the platform webview
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(children: [
        if (_wc != null) Positioned.fill(child: WebViewWidget(controller: _wc!)),
        if (_loading)
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const CircularProgressIndicator(color: AppColors.primary),
              const SizedBox(height: 20),
              Text(t['yt_searching']!,
                  style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink)),
            ]),
          ),
        if (_failed)
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.error_outline,
                  size: 56, color: AppColors.inkMute),
              const SizedBox(height: 16),
              Text(t['yt_none']!,
                  style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppColors.inkSoft)),
              const SizedBox(height: 24),
              Focusable(
                autofocus: true,
                onPressed: () => Navigator.maybePop(context),
                builder: (context, focused) => Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
                  decoration: BoxDecoration(
                      color: focused ? Colors.white : AppColors.bg2,
                      borderRadius: BorderRadius.circular(999)),
                  child: Text(t['back']!,
                      style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          color:
                              focused ? AppColors.onFocus : AppColors.ink)),
                ),
              ),
            ]),
          ),
        // back button
        Positioned(
          top: 36,
          left: 36,
          child: Focusable(
            autofocus: !_failed,
            onPressed: () => Navigator.maybePop(context),
            builder: (context, focused) => AnimatedScale(
              scale: focused ? 1.06 : 1,
              duration: const Duration(milliseconds: 150),
              child: Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: focused
                        ? Colors.white
                        : Colors.black.withValues(alpha: 0.5)),
                child: Icon(Icons.arrow_back,
                    color: focused ? AppColors.onFocus : Colors.white,
                    size: 30),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}
