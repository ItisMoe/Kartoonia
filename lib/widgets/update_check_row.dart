import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../state/app_state.dart';
import '../theme/theme.dart';
import 'selectable_chip.dart';
import 'update_gate.dart';

/// Settings row: a "Check for updates" button with an inline status line.
/// Pressing it runs the same flow as the launch prompt ([UpdateFlow]) but
/// ignores a previously skipped version; when nothing newer exists it says so
/// instead of staying silent. Sized for the TV canvas by default; [phone]
/// shrinks it to the portrait settings list scale.
class UpdateCheckRow extends ConsumerStatefulWidget {
  final bool phone;
  const UpdateCheckRow({super.key, this.phone = false});

  @override
  ConsumerState<UpdateCheckRow> createState() => _UpdateCheckRowState();
}

class _UpdateCheckRowState extends ConsumerState<UpdateCheckRow> {
  bool _checking = false;
  bool _upToDate = false;
  // Installed build, shown next to the check button so users can read off
  // which version their device is ACTUALLY running (in-app updates can look
  // successful without installing anything).
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((i) {
      if (mounted) setState(() => _version = i.version);
    }, onError: (_) {});
  }

  Future<void> _check() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _upToDate = false;
    });
    final found = await UpdateFlow.checkAndPrompt(ref, manual: true);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _upToDate = !found;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = ref.watch(stringsProvider);
    final phone = widget.phone;
    final status = _checking
        ? t['update_checking']
        : _upToDate
            ? t['update_none']
            : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(t['update_section']!,
            style: TextStyle(
                fontSize: phone ? 17 : 26,
                fontWeight: FontWeight.w800,
                color: AppColors.inkSoft)),
        SizedBox(height: phone ? 12 : 16),
        Row(children: [
          SelectableChip(
            label: t['update_check']!,
            selected: false,
            onPressed: _check,
            padding: phone
                ? const EdgeInsets.symmetric(horizontal: 26, vertical: 12)
                : const EdgeInsets.symmetric(horizontal: 42, vertical: 18),
            radius: phone ? 12 : 16,
            fontSize: phone ? 15 : 25,
            minWidth: phone ? null : 150,
          ),
          if (_version.isNotEmpty) ...[
            SizedBox(width: phone ? 14 : 20),
            Text('${t['version'] ?? 'Version'} $_version',
                textDirection: TextDirection.ltr,
                style: TextStyle(
                    fontSize: phone ? 14 : 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.inkMute)),
          ],
        ]),
        if (status != null) ...[
          SizedBox(height: phone ? 10 : 12),
          Text(status,
              style: TextStyle(
                  fontSize: phone ? 13 : 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.inkMute)),
        ],
      ],
    );
  }
}
