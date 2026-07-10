// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/audio_controller.dart';
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
  bool? _hasGoogleTts;
  List<String> _engines = const [];

  @override
  void initState() {
    super.initState();
    _refreshGoogleStatus();
  }

  Future<void> _refreshGoogleStatus() async {
    final checker = getIt<TtsAvailabilityChecker>();
    final hasGoogle = await checker.hasGoogleTtsEngine();
    final engines = await checker.listEngineNames();
    if (!mounted) return;
    setState(() {
      _hasGoogleTts = hasGoogle;
      _engines = engines;
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

  String _subtitle(TtsEngine engine) {
    switch (engine) {
      case TtsEngine.system:
        if (_hasGoogleTts == true) {
          return 'Google TTS (preferred for Swahili)';
        }
        if (_hasGoogleTts == false) {
          final oem = _engines.isEmpty ? 'OEM' : _engines.join(', ');
          return 'Google TTS not installed — using $oem';
        }
        return 'Checking device TTS engines…';
      case TtsEngine.offline:
        return 'Bundled Piper Swahili voice (offline)';
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
      onTap: () => _showEnginePicker(context, settings),
    );
  }

  Future<void> _showEnginePicker(
    BuildContext context,
    SettingsProvider settings,
  ) async {
    final selected = await showDialog<TtsEngine>(
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
          if (_hasGoogleTts == false) ...[
            const Divider(),
            SimpleDialogOption(
              onPressed: () async {
                Navigator.of(context).pop();
                await getIt<TtsAvailabilityChecker>().openGoogleTtsInstallPage();
                await _refreshGoogleStatus();
              },
              child: const Text('Install Google TTS…'),
            ),
            SimpleDialogOption(
              onPressed: () async {
                Navigator.of(context).pop();
                await getIt<TtsAvailabilityChecker>().openSystemTtsSettings();
                await _refreshGoogleStatus();
              },
              child: const Text('Open system TTS settings…'),
            ),
          ],
        ],
      ),
    );

    if (selected != null && selected != settings.ttsEngine) {
      await settings.setTtsEngine(selected);
      final audio = getIt<AudioController>();
      if (selected == TtsEngine.system) {
        await audio.rebindSystemTts();
        await _refreshGoogleStatus();
      }
      // Short sample so the user (and logcat) confirm which path is active.
      await audio.speak('Habari');
    }
  }
}
