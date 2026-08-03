// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/di/injection.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/xiaoyi_service.dart';
import 'package:turna/views/settings/widgets/settings_common.dart';
import 'package:turna/views/settings/widgets/settings_sound_section.dart';

/// A toggle that lets the learner hand practice-question explanations to
/// HarmonyOS 小艺 instead of the configured DeepSeek endpoint. Renders only
/// when the native XiaoyiPlugin is present (HarmonyOS); on Android/Web
/// [XiaoyiService.isSupported] is false so the tile is never shown, leaving
/// Android behavior untouched.
///
/// When visible, includes a **leading** divider so the parent card does not
/// leave a double divider when this tile collapses to [SizedBox.shrink].
class SettingsXiaoyiTile extends StatefulWidget {
  const SettingsXiaoyiTile({super.key});

  @override
  State<SettingsXiaoyiTile> createState() => _SettingsXiaoyiTileState();
}

class _SettingsXiaoyiTileState extends State<SettingsXiaoyiTile> {
  late final Future<bool> _supportedFuture;

  @override
  void initState() {
    super.initState();
    _supportedFuture = getIt<XiaoyiService>().isSupported;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _supportedFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        if (snapshot.data != true) return const SizedBox.shrink();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            settingsTileDivider(context),
            SettingsToggleTile(
              icon: Icons.auto_awesome_rounded,
              title: AppStrings.settingsXiaoyiTitle,
              subtitle: AppStrings.settingsXiaoyiSubtitle,
              valueSelector: (p) => p.useXiaoyiHint,
              onChanged: (p, value) => p.setUseXiaoyiHint(value),
            ),
          ],
        );
      },
    );
  }
}
