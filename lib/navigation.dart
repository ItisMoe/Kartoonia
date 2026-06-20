import 'package:flutter/material.dart';
import 'models/content_item.dart';
import 'screens/browse_screen.dart';
import 'screens/detail_screen.dart';
import 'screens/player_screen.dart';
import 'screens/search_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/shaarat_screen.dart';
import 'screens/youtube_screen.dart';

/// Global navigator key — lets deep links (home-screen recommendations) push
/// routes without a BuildContext.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

/// Observes route pushes/pops so the شارات reel feed can pause its playback
/// whenever a screen (detail / player) is pushed on top of it, and resume on
/// return. Registered on the [MaterialApp] in app.dart.
final RouteObserver<PageRoute<dynamic>> routeObserver =
    RouteObserver<PageRoute<dynamic>>();

/// Handle a `kartoonia://item/<id>` (or `kartoonia://home`) deep link.
void handleDeepLink(String link) {
  final uri = Uri.tryParse(link);
  final nav = appNavigatorKey.currentState;
  if (uri == null || nav == null) return;
  if (uri.host == 'item' && uri.pathSegments.isNotEmpty) {
    nav.push(_fade(DetailScreen(itemId: uri.pathSegments.first)));
  }
  // 'home' → already the base route; nothing to do.
}

Route<T> _fade<T>(Widget page) => PageRouteBuilder<T>(
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 160),
    );

/// Central navigation. Home is the base route; tab switches reset to it, while
/// Detail/Player/Settings/Import push on top (mirrors the design's stack model).
class AppNav {
  static void home(BuildContext c) =>
      Navigator.popUntil(c, (r) => r.isFirst);

  static void _tab(BuildContext c, Widget w) =>
      Navigator.pushAndRemoveUntil(c, _fade(w), (r) => r.isFirst);

  static void search(BuildContext c) => _tab(c, const SearchScreen());
  static void shaarat(BuildContext c) => _tab(c, const ShaaratScreen());
  static void browse(BuildContext c, String kind) =>
      _tab(c, BrowseScreen(kind: kind));

  static void settings(BuildContext c) =>
      Navigator.push(c, _fade(const SettingsScreen()));

  static void detail(BuildContext c, ContentItem item) =>
      Navigator.push(c, _fade(DetailScreen(itemId: item.id)));

  static void player(BuildContext c, PlayerArgs args) =>
      Navigator.push(c, _fade(PlayerScreen(args: args)));

  static void youtube(BuildContext c, String query, String title) =>
      Navigator.push(c, _fade(YoutubeScreen(query: query, title: title)));
}
