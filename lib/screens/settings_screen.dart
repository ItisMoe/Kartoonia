import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/catalog_source.dart';
import '../navigation.dart';
import '../services/wcoflix/wcoflix_config.dart';
import '../services/youtube_service.dart';
import '../state/app_state.dart';
import '../state/wcoflix_providers.dart';
import '../theme/theme.dart';
import '../widgets/focusable.dart';
import '../widgets/screen_shell.dart';
import '../widgets/selectable_chip.dart';
import '../widgets/update_check_row.dart';
import 'player_screen.dart';

/// A stable, public 1280x720 H.264 (High/yuv420p) sample. Playing this on the
/// device isolates its decode/render path: if THIS plays clean but Everything
/// mode garbles, the box handles 720p H.264 fine and the WCO problem is
/// stream/token-specific; if this garbles too, the device path itself is at
/// fault. No special headers required.
const String _kDiagReferenceUrl =
    'https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4';

void _playDirect(BuildContext context, String url, String title, String sub,
    {Map<String, String>? headers}) {
  AppNav.player(
    context,
    PlayerArgs(
      itemId: 'diag',
      pageUrl: url,
      title: title,
      episodeLabel: sub,
      episodeNumber: 0,
      source: CatalogSource.wcoflix,
      directUrl: url,
      directHeaders: headers,
    ),
  );
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = ref.watch(stringsProvider);
    final settings = ref.watch(settingsProvider);
    final sn = ref.read(settingsProvider.notifier);
    final ytKey = ref.watch(ytKeyProvider);

    Widget opt(String label, bool selected, VoidCallback onPressed,
            {bool autofocus = false}) =>
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: SelectableChip(
            label: label,
            selected: selected,
            autofocus: autofocus,
            padding: const EdgeInsets.symmetric(horizontal: 42, vertical: 18),
            radius: 16,
            fontSize: 25,
            minWidth: 150,
            onPressed: onPressed,
          ),
        );

    Widget group(String label, List<Widget> options) => Padding(
          padding: const EdgeInsets.only(bottom: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AppColors.inkSoft)),
              const SizedBox(height: 16),
              Row(children: options),
            ],
          ),
        );

    return ScreenShell(
      current: 'settings',
      background: AppColors.bg1,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Spacing.pad, 150, Spacing.pad, 80),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      gradient: const LinearGradient(
                          colors: AppColors.primaryGradient)),
                  child: const Icon(Icons.settings,
                      size: 40, color: AppColors.onPrimary),
                ),
                const SizedBox(width: 24),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t['settings']!,
                        style: const TextStyle(
                            fontFamily: Fonts.display,
                            fontFamilyFallback: Fonts.fallback,
                            fontWeight: FontWeight.w600,
                            fontSize: 54,
                            color: AppColors.ink)),
                    Text(t['set_hint']!,
                        style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                            color: AppColors.inkMute)),
                  ],
                ),
              ]),
              const SizedBox(height: 52),
              group(t['set_language']!, [
                opt('English', settings.lang == 'en', () => sn.setLang('en'),
                    autofocus: true),
                opt('العربية', settings.lang == 'ar', () => sn.setLang('ar')),
              ]),
              // Everything mode — reveal the full WCOFlix library.
              Padding(
                padding: const EdgeInsets.only(bottom: 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t['everything_mode']!,
                        style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: AppColors.inkSoft)),
                    const SizedBox(height: 6),
                    Text(t['everything_desc']!,
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            color: AppColors.inkMute)),
                    const SizedBox(height: 16),
                    Row(children: [
                      opt(t['on']!, ref.watch(everythingModeProvider),
                          () => ref
                              .read(everythingModeProvider.notifier)
                              .set(true)),
                      opt(t['off']!, !ref.watch(everythingModeProvider),
                          () => ref
                              .read(everythingModeProvider.notifier)
                              .set(false)),
                    ]),
                  ],
                ),
              ),
              group(t['set_autoplay']!, [
                opt(t['on']!, settings.prefs['autoplay'] != 'off',
                    () => sn.setPref('autoplay', 'on')),
                opt(t['off']!, settings.prefs['autoplay'] == 'off',
                    () => sn.setPref('autoplay', 'off')),
              ]),
              group(t['set_motion']!, [
                opt(t['on']!, settings.prefs['motion'] == 'on',
                    () => sn.setPref('motion', 'on')),
                opt(t['off']!, settings.prefs['motion'] != 'on',
                    () => sn.setPref('motion', 'off')),
              ]),
              group(t['shaarat_mode']!, [
                opt(t['shaarat_mode_video']!,
                    settings.prefs['shaarat'] != 'audio',
                    () => sn.setPref('shaarat', 'video')),
                opt(t['shaarat_mode_audio']!,
                    settings.prefs['shaarat'] == 'audio',
                    () => sn.setPref('shaarat', 'audio')),
              ]),
              // YouTube API key (override the bundled default)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t['set_ytkey']!,
                      style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: AppColors.inkSoft)),
                  const SizedBox(height: 16),
                  Row(children: [
                    opt(t['ytkey_edit']!, false,
                        () => _openYtKeyDialog(context, ref)),
                  ]),
                  const SizedBox(height: 12),
                  Text(ytKey.trim().isEmpty
                      ? t['ytkey_default']!
                      : '${t['ytkey_custom']!}  •  ${_mask(ytKey)}',
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.inkMute)),
                ],
              ),
              const SizedBox(height: 40),
              // Manual update check (the launch prompt also runs once per start).
              const UpdateCheckRow(),
              const SizedBox(height: 40),
              // Playback diagnostics — isolate the Everything-mode garbled-video
              // bug: a known-good 720p H.264 reference vs a URL verified clean
              // elsewhere. Both show the live decode-info line in the player.
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t['diag_section'] ?? 'Playback diagnostic',
                      style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: AppColors.inkSoft)),
                  const SizedBox(height: 16),
                  Row(children: [
                    opt(t['diag_reference'] ?? 'Play reference 720p', false,
                        () => _playDirect(context, _kDiagReferenceUrl,
                            'Diagnostic — reference 720p', 'H.264 sample')),
                    opt(t['diag_paste'] ?? 'Play pasted URL', false,
                        () => _openDiagUrlDialog(context, ref)),
                  ]),
                  const SizedBox(height: 12),
                  Text(
                      t['diag_hint'] ??
                          'If the reference plays clean but Everything mode does not, '
                              'the device decodes 720p H.264 fine — paste a URL verified '
                              'clean elsewhere to test the exact stream.',
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: AppColors.inkMute)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Shows a masked preview only — never the full key.
  static String _mask(String k) {
    final s = k.trim();
    if (s.length <= 8) return '••••';
    return '${s.substring(0, 4)}••••${s.substring(s.length - 4)}';
  }

  void _openDiagUrlDialog(BuildContext context, WidgetRef ref) {
    final t = ref.read(stringsProvider);
    showDialog<void>(
      context: context,
      builder: (_) => _DiagUrlDialog(
        t: t,
        onPlay: (url) {
          Navigator.of(context).pop();
          _playDirect(context, url, 'Diagnostic — pasted URL', 'verified stream',
              headers: kWcoflixMediaHeaders);
        },
      ),
    );
  }

  void _openYtKeyDialog(BuildContext context, WidgetRef ref) {
    final t = ref.read(stringsProvider);
    showDialog<void>(
      context: context,
      builder: (_) => _YtKeyDialog(
        t: t,
        initial: ref.read(storageProvider).getYoutubeKey(),
        onSave: (key) async {
          await ref.read(storageProvider).setYoutubeKey(key);
          ref.read(ytKeyProvider.notifier).state = key.trim();
        },
        onReset: () async {
          await ref.read(storageProvider).clearYoutubeKey();
          ref.read(ytKeyProvider.notifier).state = '';
        },
      ),
    );
  }
}

/// TV-friendly dialog to paste a direct stream URL for the playback diagnostic.
/// Also accepts the URL via the clipboard (Paste button) since typing a long
/// getvid URL on a remote is painful.
class _DiagUrlDialog extends StatefulWidget {
  final Map<String, String> t;
  final void Function(String url) onPlay;
  const _DiagUrlDialog({required this.t, required this.onPlay});
  @override
  State<_DiagUrlDialog> createState() => _DiagUrlDialogState();
}

class _DiagUrlDialogState extends State<_DiagUrlDialog> {
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) setState(() => _ctrl.text = data!.text!.trim());
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return AlertDialog(
      backgroundColor: AppColors.bg2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(t['diag_paste'] ?? 'Play pasted URL',
          style: const TextStyle(
              fontWeight: FontWeight.w900, color: AppColors.ink)),
      content: SizedBox(
        width: 720,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            maxLines: 3,
            style: const TextStyle(color: AppColors.ink, fontSize: 20),
            decoration: InputDecoration(
              hintText: 'https://…/getvid?evid=…',
              hintStyle: const TextStyle(color: AppColors.inkMute),
              enabledBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.inkMute)),
              focusedBorder: const OutlineInputBorder(
                  borderSide: BorderSide(color: AppColors.primary)),
            ),
          ),
          const SizedBox(height: 16),
          Row(children: [
            SelectableChip(
              label: t['diag_paste_btn'] ?? 'Paste',
              selected: false,
              onPressed: _paste,
              padding:
                  const EdgeInsets.symmetric(horizontal: 30, vertical: 14),
              radius: 14,
              fontSize: 22,
            ),
          ]),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t['cancel'] ?? 'Cancel',
                style: const TextStyle(color: AppColors.inkMute))),
        FilledButton(
          onPressed: () {
            final u = _ctrl.text.trim();
            if (u.startsWith('http')) widget.onPlay(u);
          },
          style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
          child: Text(t['diag_play'] ?? 'Play',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800)),
        ),
      ],
    );
  }
}

/// TV-friendly dialog to view/edit/reset/test the YouTube API key.
class _YtKeyDialog extends StatefulWidget {
  final Map<String, String> t;
  final String initial;
  final Future<void> Function(String key) onSave;
  final Future<void> Function() onReset;
  const _YtKeyDialog({
    required this.t,
    required this.initial,
    required this.onSave,
    required this.onReset,
  });
  @override
  State<_YtKeyDialog> createState() => _YtKeyDialogState();
}

class _YtKeyDialogState extends State<_YtKeyDialog> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.initial);
  String? _msg;
  Color _msgColor = AppColors.inkMute;
  bool _testing = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.t;
    return AlertDialog(
      backgroundColor: AppColors.bg2,
      title: Text(t['set_ytkey']!,
          style: const TextStyle(
              color: AppColors.ink, fontWeight: FontWeight.w800)),
      content: SizedBox(
        width: 640,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: _ctrl,
            autofocus: true,
            maxLines: 2,
            style: const TextStyle(color: AppColors.ink, fontSize: 20),
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
          if (_msg != null) ...[
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(_msg!,
                  style: TextStyle(
                      color: _msgColor, fontWeight: FontWeight.w700)),
            ),
          ],
        ]),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      actions: [
        _DialogBtn(
          label: t['ytkey_test']!,
          onPressed: _testing ? null : _test,
        ),
        _DialogBtn(
          label: t['ytkey_reset']!,
          onPressed: () async {
            await widget.onReset();
            if (context.mounted) Navigator.pop(context);
          },
        ),
        _DialogBtn(
          label: t['cancel']!,
          onPressed: () => Navigator.pop(context),
        ),
        _DialogBtn(
          label: t['ytkey_save']!,
          primary: true,
          onPressed: () async {
            final k = _ctrl.text.trim();
            if (k.isEmpty) {
              setState(() {
                _msg = t['ytkey_empty'];
                _msgColor = AppColors.primary;
              });
              return;
            }
            await widget.onSave(k);
            if (context.mounted) Navigator.pop(context);
          },
        ),
      ],
    );
  }

  Future<void> _test() async {
    final k = _ctrl.text.trim();
    if (k.isEmpty) {
      setState(() {
        _msg = widget.t['ytkey_empty'];
        _msgColor = AppColors.primary;
      });
      return;
    }
    setState(() {
      _testing = true;
      _msg = '…';
      _msgColor = AppColors.inkMute;
    });
    final ok = await YoutubeService.validateKey(k);
    if (!mounted) return;
    setState(() {
      _testing = false;
      _msg = ok ? widget.t['ytkey_ok'] : widget.t['ytkey_bad'];
      _msgColor = ok ? AppColors.accent : AppColors.primary;
    });
  }
}

class _DialogBtn extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool primary;
  const _DialogBtn(
      {required this.label, required this.onPressed, this.primary = false});
  @override
  Widget build(BuildContext context) {
    return Focusable(
      onPressed: onPressed,
      builder: (context, focused) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: focused
              ? Colors.white
              : (primary ? AppColors.primary : AppColors.bg3),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 19,
                fontWeight: FontWeight.w800,
                color: focused
                    ? AppColors.onFocus
                    : (primary ? AppColors.onPrimary : AppColors.ink))),
      ),
    );
  }
}
