import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../state/app_state.dart';
import '../../theme/theme.dart';

/// Portrait settings: the same options as the TV settings, laid out as a simple
/// scrollable touch list.
class PhoneSettingsScreen extends ConsumerWidget {
  const PhoneSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final settings = ref.watch(settingsProvider);
    final sn = ref.read(settingsProvider.notifier);
    final ytKey = ref.watch(ytKeyProvider);

    return Scaffold(
      backgroundColor: AppColors.bg1,
      appBar: AppBar(
        backgroundColor: AppColors.bg0,
        elevation: 0,
        title: Text(t['settings']!,
            style: const TextStyle(
                fontFamily: Fonts.display,
                fontFamilyFallback: Fonts.fallback,
                fontWeight: FontWeight.w600,
                color: AppColors.ink)),
        iconTheme: const IconThemeData(color: AppColors.ink),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          _Group(
            label: t['set_language']!,
            child: Row(children: [
              _Opt('English', settings.lang == 'en', () => sn.setLang('en')),
              const SizedBox(width: 12),
              _Opt('العربية', settings.lang == 'ar', () => sn.setLang('ar')),
            ]),
          ),
          _Group(
            label: t['set_autoplay']!,
            child: _OnOff(
                on: settings.prefs['autoplay'] != 'off',
                t: t,
                onChanged: (v) => sn.setPref('autoplay', v ? 'on' : 'off')),
          ),
          _Group(
            label: t['set_motion']!,
            child: _OnOff(
                on: settings.prefs['motion'] == 'on',
                t: t,
                onChanged: (v) => sn.setPref('motion', v ? 'on' : 'off')),
          ),
          _Group(
            label: t['shaarat_mode']!,
            child: Row(children: [
              _Opt(t['shaarat_mode_video']!, settings.prefs['shaarat'] != 'audio',
                  () => sn.setPref('shaarat', 'video')),
              const SizedBox(width: 12),
              _Opt(t['shaarat_mode_audio']!, settings.prefs['shaarat'] == 'audio',
                  () => sn.setPref('shaarat', 'audio')),
            ]),
          ),
          _Group(
            label: t['set_ytkey']!,
            hint: ytKey.trim().isEmpty
                ? t['ytkey_default']!
                : '${t['ytkey_custom']!}  •  ${_mask(ytKey)}',
            child: _Opt(t['ytkey_edit']!, false,
                () => _openYtKeyDialog(context, ref)),
          ),
        ],
      ),
    );
  }

  static String _mask(String k) {
    final s = k.trim();
    if (s.length <= 8) return '••••';
    return '${s.substring(0, 4)}••••${s.substring(s.length - 4)}';
  }

  void _openYtKeyDialog(BuildContext context, WidgetRef ref) {
    final t = ref.read(stringsProvider);
    final controller =
        TextEditingController(text: ref.read(storageProvider).getYoutubeKey());
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.bg2,
        title: Text(t['set_ytkey']!,
            style: const TextStyle(
                color: AppColors.ink, fontWeight: FontWeight.w800)),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 2,
          style: const TextStyle(color: AppColors.ink),
          decoration: InputDecoration(
            hintText: t['ytkey_hint'],
            hintStyle: const TextStyle(color: AppColors.inkMute),
            filled: true,
            fillColor: AppColors.bg3,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await ref.read(storageProvider).clearYoutubeKey();
              ref.read(ytKeyProvider.notifier).state = '';
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(t['ytkey_reset']!,
                style: const TextStyle(color: AppColors.inkSoft)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t['cancel']!,
                style: const TextStyle(color: AppColors.inkSoft)),
          ),
          TextButton(
            onPressed: () async {
              final k = controller.text.trim();
              if (k.isEmpty) return;
              await ref.read(storageProvider).setYoutubeKey(k);
              ref.read(ytKeyProvider.notifier).state = k;
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(t['ytkey_save']!,
                style: const TextStyle(
                    color: AppColors.primary2, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

class _Group extends StatelessWidget {
  final String label;
  final String? hint;
  final Widget child;
  const _Group({required this.label, this.hint, required this.child});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: AppColors.inkSoft)),
          const SizedBox(height: 12),
          child,
          if (hint != null) ...[
            const SizedBox(height: 10),
            Text(hint!,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.inkMute)),
          ],
        ],
      ),
    );
  }
}

class _OnOff extends StatelessWidget {
  final bool on;
  final Map<String, String> t;
  final ValueChanged<bool> onChanged;
  const _OnOff({required this.on, required this.t, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      _Opt(t['on']!, on, () => onChanged(true)),
      const SizedBox(width: 12),
      _Opt(t['off']!, !on, () => onChanged(false)),
    ]);
  }
}

class _Opt extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Opt(this.label, this.selected, this.onTap);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: selected
              ? const LinearGradient(colors: AppColors.primaryGradient)
              : null,
          color: selected ? null : AppColors.bg2,
          border: selected
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: selected ? AppColors.onPrimary : AppColors.inkSoft)),
      ),
    );
  }
}
