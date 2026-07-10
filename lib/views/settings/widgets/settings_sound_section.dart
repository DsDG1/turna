// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/audio_controller.dart';
import 'package:varnamala/application/settings_provider.dart';
import 'package:varnamala/di/injection.dart';
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

class SettingsTtsEngineTile extends StatelessWidget {
  const SettingsTtsEngineTile({super.key});

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
        return 'Device voice (Google TTS on Android)';
      case TtsEngine.offline:
        return 'Bundled Piper Swahili voice';
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
        children: TtsEngine.values.map((engine) {
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
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: VarnamalaTheme.textHintColor(context),
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );

    if (selected != null && selected != settings.ttsEngine) {
      await settings.setTtsEngine(selected);
      if (selected == TtsEngine.system) {
        await getIt<AudioController>().rebindSystemTts();
      }
    }
  }
}
