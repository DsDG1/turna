// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/audio_controller.dart';
import 'package:varnamala/application/language_provider.dart';
import 'package:varnamala/application/settings_provider.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/service/tts_availability_checker.dart';
import 'package:varnamala/views/settings/widgets/settings_common.dart';
import 'package:varnamala/views/theme.dart';

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
      trailing: Switch.adaptive(
        value: value,
        activeTrackColor: VarnamalaTheme.peacockTeal,
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return VarnamalaTheme.peacockTeal;
          }
          return null;
        }),
        onChanged: (newValue) => onChanged(context.read<SettingsProvider>(), newValue),
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
      return 'Checking device TTS engines…';
    }
    final d = _diagnostics!;
    switch (d.preferredStatus) {
      case TtsPreferredStatus.ready:
        final locale = d.resolvedLocale ?? 'tr';
        return 'Google TTS ready ($locale) — recommended for learning';
      case TtsPreferredStatus.turkishVoiceMissing:
        if (d.hasGoogleEngine) {
          return 'Google installed — download Turkish voice data in system TTS settings';
        }
        return 'Turkish voice not ready — open system TTS settings';
      case TtsPreferredStatus.googleMissing:
        final oem = d.engines.isEmpty ? 'none listed' : d.engines.join(', ');
        return 'Google TTS not detected (engines: $oem)';
    }
  }

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      icon: Icons.record_voice_over_rounded,
      title: 'Voice source',
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
              'System TTS',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: VarnamalaTheme.peacockTeal,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          const SizedBox(width: 4),
          const Icon(
            Icons.chevron_right_rounded,
            color: VarnamalaTheme.textHint,
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
        title: const Text('Voice source'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop('preview'),
            child: const Text('Play sample (Merhaba)…'),
          ),
          SimpleDialogOption(
            onPressed: () async {
              Navigator.of(context).pop();
              await getIt<TtsAvailabilityChecker>().openSystemTtsSettings();
              await _refreshDiagnostics();
            },
            child: const Text('Open system TTS settings…'),
          ),
          SimpleDialogOption(
            onPressed: () async {
              Navigator.of(context).pop();
              await getIt<TtsAvailabilityChecker>().openGoogleTtsInstallPage();
              await _refreshDiagnostics();
            },
            child: const Text('Install / open Google TTS…'),
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
        message =
            'No voice played. ${result.error ?? "Check logcat for TTS errors."}';
      } else {
        message = 'Playing: ${result.userLabel}';
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