// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/audio_controller.dart';
import 'package:varnamala/application/language_provider.dart';
import 'package:varnamala/application/settings_provider.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/service/piper_swahili_tts.dart';
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
    final settings = context.watch<SettingsProvider>();
    final value = valueSelector(settings);

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
        onChanged: (newValue) => onChanged(settings, newValue),
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

  String _label(TtsEngine engine) {
    switch (engine) {
      case TtsEngine.system:
        return 'System TTS';
      case TtsEngine.offline:
        return 'Offline Piper';
    }
  }

  String _piperStatusLabel() {
    if (!getIt.isRegistered<PiperSwahiliTts>()) {
      return 'not registered';
    }
    final piper = getIt<PiperSwahiliTts>();
    switch (piper.status) {
      case PiperTtsStatus.ready:
        return 'ready';
      case PiperTtsStatus.loading:
        return 'loading…';
      case PiperTtsStatus.failed:
        return 'init failed — use Retry';
      case PiperTtsStatus.idle:
        return 'not loaded yet';
    }
  }

  String _subtitle(TtsEngine engine) {
    switch (engine) {
      case TtsEngine.system:
        if (_loading || _diagnostics == null) {
          return 'Checking device TTS engines…';
        }
        final d = _diagnostics!;
        switch (d.preferredStatus) {
          case TtsPreferredStatus.ready:
            final locale = d.resolvedLocale ?? 'sw';
            return 'Google TTS ready ($locale) — recommended for learning';
          case TtsPreferredStatus.swahiliDataMissing:
            if (d.hasGoogleEngine) {
              return 'Google installed — download Swahili voice data in system TTS settings';
            }
            return 'Swahili voice not ready — open system TTS settings';
          case TtsPreferredStatus.googleMissing:
            final oem = d.engines.isEmpty ? 'none listed' : d.engines.join(', ');
            return 'Google TTS not detected (engines: $oem)';
        }
      case TtsEngine.offline:
        return 'Bundled neural voice (sw_CD) · ${_piperStatusLabel()}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return SettingsTile(
      icon: Icons.record_voice_over_rounded,
      title: 'Voice source',
      subtitle: _subtitle(settings.ttsEngine),
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
              _label(settings.ttsEngine),
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
      onTap: _previewing ? null : () => _showEnginePicker(context, settings),
    );
  }

  Future<void> _showEnginePicker(
    BuildContext context,
    SettingsProvider settings,
  ) async {
    final selected = await showDialog<Object>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Voice source'),
        children: [
          ...TtsEngine.values.map((engine) {
            return SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(engine),
              child: Row(
                children: [
                  Icon(
                    engine == settings.ttsEngine
                        ? Icons.check_circle_rounded
                        : Icons.circle_outlined,
                    color: engine == settings.ttsEngine
                        ? VarnamalaTheme.peacockTeal
                        : VarnamalaTheme.textHint,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _label(engine),
                          style: TextStyle(
                            fontWeight: engine == settings.ttsEngine
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                        Text(
                          _subtitle(engine),
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color:
                                        VarnamalaTheme.textHintColor(context),
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }),
          const Divider(),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop('preview'),
            child: const Text('Play sample (Habari) with current source…'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(context).pop('retry_piper'),
            child: const Text('Retry offline Piper init…'),
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

    if (selected == 'retry_piper') {
      await _retryPiper(context);
      return;
    }

    if (selected == 'preview') {
      await _playSample(context, settings);
      return;
    }

    if (selected is TtsEngine) {
      if (selected != settings.ttsEngine) {
        await settings.setTtsEngine(selected);
      }
      final audio = getIt<AudioController>();
      if (selected == TtsEngine.system) {
        await audio.rebindSystemTts();
        await _refreshDiagnostics();
      } else if (selected == TtsEngine.offline) {
        // Ensure a sticky init failure can recover when user picks offline.
        if (getIt.isRegistered<PiperSwahiliTts>()) {
          final piper = getIt<PiperSwahiliTts>();
          if (piper.initFailed) piper.resetFailure();
        }
      }
      if (!mounted) return;
      await _playSample(context, settings);
    }
  }

  Future<void> _retryPiper(BuildContext context) async {
    if (!getIt.isRegistered<PiperSwahiliTts>()) {
      _showMessage(context, 'Offline Piper is not available on this build.');
      return;
    }
    final piper = getIt<PiperSwahiliTts>();
    piper.resetFailure();
    setState(() => _previewing = true);
    try {
      await piper.prewarm();
      if (!mounted) return;
      if (piper.isReady) {
        _showMessage(context, 'Offline Piper ready.');
      } else {
        _showMessage(
          context,
          'Offline Piper still not ready'
          '${piper.lastError != null ? ": ${piper.lastError}" : "."}',
        );
      }
    } finally {
      if (mounted) setState(() => _previewing = false);
    }
  }

  Future<void> _playSample(
    BuildContext context,
    SettingsProvider settings,
  ) async {
    setState(() => _previewing = true);
    try {
      final audio = getIt<AudioController>();
      final result = await audio.speakWithResult('Habari');
      if (!mounted) return;

      final engine = settings.ttsEngine;
      String message;
      if (result.source == TtsSpeakSource.failed) {
        message =
            'No voice played. ${result.error ?? "Check logcat for TTS errors."}';
      } else if (engine == TtsEngine.offline &&
          result.source == TtsSpeakSource.system &&
          result.usedFallback) {
        message =
            'Wanted Offline Piper, but it failed — played Google/system instead.\n'
            'Use “Retry offline Piper init”. '
            '${result.error ?? ""}';
      } else if (engine == TtsEngine.system &&
          result.source == TtsSpeakSource.piper &&
          result.usedFallback) {
        message =
            'Wanted System TTS, but it failed — played Offline Piper instead.';
      } else {
        message = 'Playing: ${result.userLabel}';
      }
      _showMessage(context, message.trim());
    } finally {
      if (mounted) {
        setState(() => _previewing = false);
      }
    }
  }

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
