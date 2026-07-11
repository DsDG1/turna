// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/audio_controller.dart';
import 'package:varnamala/application/language_provider.dart';
import 'package:varnamala/application/settings_provider.dart';
import 'package:varnamala/core/enums.dart';
import 'package:varnamala/core/extensions.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/views/settings/widgets/settings_common.dart';
import 'package:varnamala/views/theme.dart';

class SettingsLanguageSelectorTile extends StatelessWidget {
  const SettingsLanguageSelectorTile({super.key});

  @override
  Widget build(BuildContext context) {
    final languageProvider = context.watch<LanguageProvider>();
    final current = languageProvider.selectedLanguage;

    return PopupMenuButton<TargetLanguage>(
      initialValue: current,
      onSelected: (value) {
        languageProvider.setLanguage(value);
        unawaited(languageProvider.cacheLanguage());
      },
      itemBuilder: (context) => TargetLanguage.values
          .map(
            (lang) => PopupMenuItem(
              value: lang,
              child: Row(
                children: [
                  Icon(
                    Icons.language_rounded,
                    size: 18,
                    color: lang == current
                        ? VarnamalaTheme.peacockTeal
                        : VarnamalaTheme.textHint,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    lang.name.toTitleCase,
                    style: TextStyle(
                      fontWeight:
                          lang == current ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
      child: SettingsTile(
        icon: Icons.language_rounded,
        title: 'Learning Language',
        subtitle: 'Choose the language you are learning',
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              current.name.toTitleCase,
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
      ),
    );
  }
}

class SettingsTtsSpeedTile extends StatelessWidget {
  const SettingsTtsSpeedTile({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.08),
                  borderRadius:
                      BorderRadius.circular(VarnamalaTheme.radiusMedium),
                ),
                child: const Icon(
                  Icons.record_voice_over_rounded,
                  color: VarnamalaTheme.peacockTeal,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TTS Speed',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    Text(
                      'Adjust voice playback speed',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: VarnamalaTheme.textHintColor(context),
                          ),
                    ),
                  ],
                ),
              ),
              Text(
                '${settings.ttsSpeed.toStringAsFixed(1)}x',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: VarnamalaTheme.peacockTeal,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 52),
            child: Slider.adaptive(
              value: settings.ttsSpeed,
              min: 0.5,
              max: 2.0,
              divisions: 15,
              activeColor: VarnamalaTheme.peacockTeal,
              inactiveColor: VarnamalaTheme.dividerBg(context),
              onChanged: (value) {
                settings.setTtsSpeed(value);
                getIt<AudioController>().setTtsSpeed(value);
              },
            ),
          ),
        ],
      ),
    );
  }
}
