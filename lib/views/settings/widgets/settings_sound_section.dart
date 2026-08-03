// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/audio_controller.dart';
import 'package:turna/application/language_provider.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/service/tts_availability_checker.dart';
import 'package:turna/views/settings/widgets/settings_common.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/theme.dart';

class SettingsToggleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool Function(SettingsProvider) valueSelector;
  final void Function(SettingsProvider, bool) onChanged;

  const SettingsToggleTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.valueSelector,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final value = context.select<SettingsProvider, bool>(
      (settings) => valueSelector(settings),
    );

    return SettingsTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: settingsAdaptiveSwitch(
        value: value,
        onChanged: (newValue) =>
            onChanged(context.read<SettingsProvider>(), newValue),
      ),
    );
  }
}

class SettingsTtsEngineTile extends StatefulWidget {
  const SettingsTtsEngineTile({super.key});

  @override
  State<SettingsTtsEngineTile> createState() => _SettingsTtsEngineTileState();
}

class _SettingsTtsEngineTileState extends State<SettingsTtsEngineTile> {
  TtsDiagnostics? _diagnostics;
  bool _loading = true;
  bool _previewing = false;

  @override
  void initState() {
    super.initState();
    _refreshDiagnostics();
  }

  Future<void> _refreshDiagnostics() async {
    final checker = getIt<TtsAvailabilityChecker>();
    final lang = getIt<LanguageProvider>().ttsLanguageCode;
    final diag = await checker.diagnose(lang);
    if (!mounted) return;
    setState(() {
      _diagnostics = diag;
      _loading = false;
    });
  }

  String _subtitle() {
    if (_loading || _diagnostics == null) {
      return AppStrings.settingsTtsChecking;
    }
    final d = _diagnostics!;
    switch (d.preferredStatus) {
      case TtsPreferredStatus.ready:
        final locale = d.resolvedLocale ?? 'tr';
        return AppStrings.settingsTtsReady(locale);
      case TtsPreferredStatus.turkishVoiceMissing:
        if (d.hasGoogleEngine) {
          return AppStrings.settingsTtsGoogleInstalledMissingVoice;
        }
        return AppStrings.settingsTtsTurkishVoiceMissing;
      case TtsPreferredStatus.googleMissing:
        final oem = d.engines.isEmpty ? 'none listed' : d.engines.join(', ');
        return AppStrings.settingsTtsGoogleMissing(oem);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      icon: Icons.record_voice_over_rounded,
      title: AppStrings.settingsVoiceSourceTitle,
      subtitle: _subtitle(),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_previewing)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Text(
              AppStrings.settingsSystemTts,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: TurnaTheme.peacockTeal,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          const SizedBox(width: 4),
          const Icon(
            Icons.chevron_right_rounded,
            color: TurnaTheme.textHint,
          ),
        ],
      ),
      onTap: _previewing ? null : () => _showTtsMenu(),
    );
  }

  Future<void> _showTtsMenu() async {
    final selected = await showDialog<Object>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(AppStrings.settingsVoiceSourceDialogTitle),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop('preview'),
            child: Text(AppStrings.settingsPlaySample),
          ),
          SimpleDialogOption(
            onPressed: () async {
              Navigator.of(context).pop();
              await getIt<TtsAvailabilityChecker>().openSystemTtsSettings();
              await _refreshDiagnostics();
            },
            child: Text(AppStrings.settingsOpenSystemTts),
          ),
          SimpleDialogOption(
            onPressed: () async {
              Navigator.of(context).pop();
              await getIt<TtsAvailabilityChecker>().openGoogleTtsInstallPage();
              await _refreshDiagnostics();
            },
            child: Text(AppStrings.settingsInstallGoogleTts),
          ),
        ],
      ),
    );

    if (!mounted || selected == null) return;

    if (selected == 'preview') {
      await _playSample();
    }
  }

  Future<void> _playSample() async {
    setState(() => _previewing = true);
    try {
      final audio = getIt<AudioController>();
      final result = await audio.speakWithResult('Merhaba');
      if (!mounted) return;

      String message;
      if (result.source == TtsSpeakSource.failed) {
        message = result.error != null
            ? AppStrings.settingsTtsNoVoicePlayed(result.error!)
            : AppStrings.settingsTtsNoVoicePlayedFallback;
      } else {
        message = AppStrings.settingsTtsPlaying(result.userLabel);
      }
      _showMessage(message.trim());
    } finally {
      if (mounted) {
        setState(() => _previewing = false);
      }
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
