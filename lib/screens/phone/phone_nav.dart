import 'package:flutter/material.dart';
import '../../models/content_item.dart';
import 'phone_detail_screen.dart';
import 'phone_settings_screen.dart';

/// Navigation helpers for the phone UI. Detail and Settings use phone-specific
/// (portrait) screens; the player is shared with the TV build (it flips to
/// landscape on its own).
Route<T> phoneFade<T>(Widget page) => PageRouteBuilder<T>(
      pageBuilder: (_, _, _) => page,
      transitionsBuilder: (_, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 160),
    );

void openPhoneDetail(BuildContext context, ContentItem item) =>
    Navigator.push(context, phoneFade(PhoneDetailScreen(itemId: item.id)));

void openPhoneSettings(BuildContext context) =>
    Navigator.push(context, phoneFade(const PhoneSettingsScreen()));
