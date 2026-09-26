// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Package imports:

// Project imports:
import 'package:turna/application/audio_controller.dart';
import 'package:turna/application/language_provider.dart';
import 'package:turna/application/settings_provider.dart';
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
  });

  @override
  Widget build(BuildContext context) {
    return ProviderBoundToggleTile<SettingsProvider>(
      icon: icon,
      title: title,
      subtitle: subtitle,
      valueSelector: valueSelector,
      onChanged: onChanged,
    );
  }
}

class SettingsTtsEngineTile extends StatefulWidget {
  const SettingsTtsEngineTile({super.key});

  @override
  State<SettingsTtsEngineTile> createState() => _SettingsTtsEngineTileState();
}

class _SettingsTtsEngineTileState extends State<SettingsTtsEngineTile>
    with WidgetsBindingObserver {
  TtsDiagnostics? _diagnostics;
  bool _loading = true;
  bool _previewing = false;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshDiagnostics();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Returning from system settings (where the user may have just installed a
  // voice or switched engines) must re-run the diagnosis — the tile otherwise
  // keeps showing the stale "voice missing" state until the page is reopened.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshDiagnostics();
    }
  }

  Future<void> _refreshDiagnostics() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final checker = getIt<TtsAvailabilityChecker>();
      final lang = getIt<LanguageProvider>().ttsLanguageCode;
      final diag = await checker.diagnose(lang);
      if (!mounted) return;
      setState(() {
        _diagnostics = diag;
        _loading = false;
      });
    } finally {
      _refreshing = false;
    }
  }

  String _subtitle() {
    if (_loading || _diagnostics == null) {
      return AppStrings.settingsTtsChecking;
    }
    final d = _diagnostics!;
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    switch (d.preferredStatus) {
      case TtsPreferredStatus.ready:
        final locale =
            d.resolvedLocale ?? getIt<LanguageProvider>().ttsLanguageCode;
        return isAndroid
            ? AppStrings.settingsTtsReady(locale)
            : AppStrings.settingsTtsReadySystem(locale);
      case TtsPreferredStatus.voiceMissing:
        final name = getIt<LanguageProvider>().displayName;
        if (isAndroid) {
          return d.hasGoogleEngine
              ? AppStrings.settingsTtsGoogleInstalledMissingVoice
              : AppStrings.settingsTtsVoiceMissing(name);
        }
        return AppStrings.settingsTtsVoiceMissingSystem(name);
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
    // Engine selection and the Play Store are Android-only; on iOS the only
    // actionable path is downloading voices in system Settings.
    final isAndroid =
        !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    final isIos = !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
    final selected = await showDialog<Object>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(AppStrings.settingsVoiceSourceDialogTitle),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop('preview'),
            child: Text(AppStrings.settingsPlaySample),
          ),
          if (isAndroid) ...[
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
                await getIt<TtsAvailabilityChecker>()
                    .openGoogleTtsInstallPage();
                await _refreshDiagnostics();
              },
              child: Text(AppStrings.settingsInstallGoogleTts),
            ),
          ] else if (isIos)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop('voiceGuide'),
              child: Text(AppStrings.settingsVoiceGuideAction),
            ),
        ],
      ),
    );

    if (!mounted || selected == null) return;

    if (selected == 'preview') {
      await _playSample();
    } else if (selected == 'voiceGuide') {
      await _showVoiceDownloadGuide();
    }
  }

  Future<void> _showVoiceDownloadGuide() {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppStrings.settingsVoiceGuideIosTitle),
        content: Text(AppStrings.settingsVoiceGuideIosBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(AppStrings.commonGotIt),
          ),
        ],
      ),
    );
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
    TurnaSnackBar.show(
      context,
      message,
      duration: const Duration(seconds: 4),
    );
  }
}
