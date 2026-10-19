// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:

// Project imports:
import 'package:turna/application/audio_controller.dart';
import 'package:turna/application/language_provider.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/core/ohos_target.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/service/tts_availability_checker.dart';
import 'package:turna/views/settings/widgets/settings_common.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/views/widgets/turna_snack_bar.dart';

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
    this.enabled = true,
  });

  /// See [ProviderBoundToggleTile.enabled].
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return ProviderBoundToggleTile<SettingsProvider>(
      icon: icon,
      title: title,
      subtitle: subtitle,
      valueSelector: valueSelector,
      onChanged: onChanged,
      enabled: enabled,
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

  /// Voice tags the device's own engine can speak. Empty everywhere except the
  /// companion build, and empty there too when the engine never started, so
  /// [AppStrings.voiceListLabel] has to absorb both cases.
  List<String> _deviceVoices = const <String>[];

  @override
  void initState() {
    super.initState();
    _refreshDiagnostics();
  }

  Future<void> _refreshDiagnostics() async {
    final checker = getIt<TtsAvailabilityChecker>();
    final lang = getIt<LanguageProvider>().ttsLanguageCode;
    final diag = await checker.diagnose(lang);
    // Fetched after `diagnose` so the voice list can never delay the
    // diagnostics themselves, and fetched even when `diag` threw nothing —
    // an empty list is a legitimate state, not an error to swallow.
    final voices = await checker.listVoiceLanguages();
    if (!mounted) return;
    setState(() {
      _diagnostics = diag;
      _deviceVoices = voices;
      _loading = false;
    });
  }

  String _subtitle() {
    if (_loading || _diagnostics == null) {
      return AppStrings.settingsTtsChecking;
    }
    final d = _diagnostics!;
    final language = getIt<LanguageProvider>();
    if (isHarmonyOsTarget) {
      // The companion build has no preferred engine and no store, so the only
      // honest thing to report is which voices the device actually has.
      final voices = AppStrings.voiceListLabel(_deviceVoices);
      return switch (d.preferredStatus) {
        TtsPreferredStatus.ready => AppStrings.settingsOhosTtsReady(
            d.resolvedLocale ?? language.ttsLanguageCode,
          ),
        TtsPreferredStatus.voiceMissing =>
          AppStrings.settingsOhosTtsVoiceMissing(
            language.displayName,
            voices,
          ),
        TtsPreferredStatus.googleMissing =>
          AppStrings.settingsOhosTtsNoVoice(voices),
      };
    }
    switch (d.preferredStatus) {
      case TtsPreferredStatus.ready:
        final locale =
            d.resolvedLocale ?? getIt<LanguageProvider>().ttsLanguageCode;
        return AppStrings.settingsTtsReady(locale);
      case TtsPreferredStatus.voiceMissing:
        if (d.hasGoogleEngine) {
          return AppStrings.settingsTtsGoogleInstalledMissingVoice;
        }
        return AppStrings.settingsTtsVoiceMissing(
          getIt<LanguageProvider>().displayName,
        );
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
                    color: TurnaTheme.brandTeal,
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
          // Both of the remaining actions are Android-only affordances: one
          // launches a store listing, the other an Android `Intent`. Both fail
          // silently on the companion build, so they are omitted there instead
          // of being shown as buttons that do nothing.
          if (!isHarmonyOsTarget) ...[
            SimpleDialogOption(
              onPressed: () async {
                Navigator.of(context).pop();
                await getIt<TtsAvailabilityChecker>()
                    .openGoogleTtsInstallPage();
                await _refreshDiagnostics();
              },
              child: Text(AppStrings.settingsInstallGoogleTts),
            ),
          ],
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
      // The word comes from the same constant the menu entry renders, so the
      // preview cannot promise one word and speak another — which is what the
      // leftover OHOS diagnostic sample did: the entry said "Merhaba" and every
      // platform, Android included, heard a hardcoded Chinese phrase. No
      // `languageCode` override either: the spoken language is the course's.
      final result = await audio.speakWithResult(
        AppStrings.settingsPlaySampleWord,
      );
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
    TurnaSnackBar.show(
      context,
      message,
      duration: const Duration(seconds: 4),
    );
  }
}
