// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/anki/anki_deck_manager.dart';
import 'package:varnamala/application/audio_controller.dart';
import 'package:varnamala/application/language_provider.dart';
import 'package:varnamala/application/locale_provider.dart';
import 'package:varnamala/application/settings_provider.dart';
import 'package:varnamala/core/enums.dart';
import 'package:varnamala/core/extensions.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/l10n/app_localizations.dart';
import 'package:varnamala/service/locator.dart';
import 'package:varnamala/views/settings/widgets/settings_common.dart';
import 'package:varnamala/views/theme.dart';

class SettingsLanguageSelectorTile extends StatelessWidget {
  const SettingsLanguageSelectorTile({super.key});

  @override
  Widget build(BuildContext context) {
    final languageProvider = context.watch<LanguageProvider>();
    final current = languageProvider.selectedLanguage;
    final l10n = AppLocalizations.of(context)!;

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
        title: l10n.settingsLearningLanguageTitle,
        subtitle: l10n.settingsLearningLanguageSubtitle,
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

/// UI display language selector (app interface language). Independent of
/// [SettingsLanguageSelectorTile] which selects the *target* learning language.
class SettingsUiLocaleTile extends StatelessWidget {
  const SettingsUiLocaleTile({super.key});

  @override
  Widget build(BuildContext context) {
    final localeProvider = context.watch<LocaleProvider>();
    final l10n = AppLocalizations.of(context)!;

    // null = follow system; otherwise the chosen Locale.
    final current = localeProvider.locale;

    String label(BuildContext context, Locale? locale) {
      if (locale == null) return l10n.settingsUiLanguageSystem;
      switch (locale.languageCode) {
        case 'zh':
          return '中文';
        case 'en':
        default:
          return 'English';
      }
    }

    return PopupMenuButton<String>(
      initialValue: current?.languageCode ?? 'system',
      onSelected: (value) {
        final Locale? locale;
        switch (value) {
          case 'en':
            locale = const Locale('en');
            break;
          case 'zh':
            locale = const Locale('zh');
            break;
          case 'system':
          default:
            locale = null;
        }
        localeProvider.setLocale(locale);
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'system',
          child: Row(
            children: [
              Icon(
                Icons.settings_suggest_outlined,
                size: 18,
                color: current == null
                    ? VarnamalaTheme.peacockTeal
                    : VarnamalaTheme.textHint,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.settingsUiLanguageSystem,
                style: TextStyle(
                  fontWeight: current == null
                      ? FontWeight.w700
                      : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'en',
          child: Row(
            children: [
              Icon(
                Icons.language_rounded,
                size: 18,
                color: current?.languageCode == 'en'
                    ? VarnamalaTheme.peacockTeal
                    : VarnamalaTheme.textHint,
              ),
              const SizedBox(width: 8),
              Text(
                'English',
                style: TextStyle(
                  fontWeight: current?.languageCode == 'en'
                      ? FontWeight.w700
                      : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'zh',
          child: Row(
            children: [
              Icon(
                Icons.language_rounded,
                size: 18,
                color: current?.languageCode == 'zh'
                    ? VarnamalaTheme.peacockTeal
                    : VarnamalaTheme.textHint,
              ),
              const SizedBox(width: 8),
              Text(
                '中文',
                style: TextStyle(
                  fontWeight: current?.languageCode == 'zh'
                      ? FontWeight.w700
                      : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ],
      child: SettingsTile(
        icon: Icons.translate_rounded,
        title: l10n.settingsUiLanguageTitle,
        subtitle: l10n.settingsUiLanguageSubtitle,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label(context, current),
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
    final l10n = AppLocalizations.of(context)!;

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
                      l10n.settingsTtsSpeedTitle,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    Text(
                      l10n.settingsTtsSpeedSubtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: VarnamalaTheme.textHintColor(context),
                          ),
                    ),
                  ],
                ),
              ),
              Text(
                l10n.settingsTtsSpeedValue(
                    settings.ttsSpeed.toStringAsFixed(1)),
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

/// Slider tile configuring the Anki daily new-card limit.
///
/// Reads/writes `AnkiDeckManager` preferences (no provider rebuild needed —
/// the slider's own state drives the UI; prefs is authoritative).
class SettingsAnkiNewLimitTile extends StatefulWidget {
  const SettingsAnkiNewLimitTile({super.key});

  @override
  State<SettingsAnkiNewLimitTile> createState() =>
      _SettingsAnkiNewLimitTileState();
}

class _SettingsAnkiNewLimitTileState extends State<SettingsAnkiNewLimitTile> {
  late final AnkiDeckManager _manager = AnkiDeckManager(
    repo: getIt(),
    srsProvider: getIt(),
    importDao: getIt(),
    appPrefs: getIt<AppPrefs>(),
  );

  @override
  Widget build(BuildContext context) {
    return _AnkiLimitSlider(
      manager: _manager,
      icon: Icons.add_card_outlined,
      title: 'Anki: Daily new cards',
      subtitle: 'Max new Anki cards introduced per day',
      min: 0,
      max: 100,
      divisions: 20,
      getValue: (m) => m.dailyNewLimit,
      setValue: (m, v) => m.setDailyNewLimit(v),
    );
  }
}

/// Slider tile configuring the Anki daily review limit.
class SettingsAnkiReviewLimitTile extends StatefulWidget {
  const SettingsAnkiReviewLimitTile({super.key});

  @override
  State<SettingsAnkiReviewLimitTile> createState() =>
      _SettingsAnkiReviewLimitTileState();
}

class _SettingsAnkiReviewLimitTileState extends State<SettingsAnkiReviewLimitTile> {
  late final AnkiDeckManager _manager = AnkiDeckManager(
    repo: getIt(),
    srsProvider: getIt(),
    importDao: getIt(),
    appPrefs: getIt<AppPrefs>(),
  );

  @override
  Widget build(BuildContext context) {
    return _AnkiLimitSlider(
      manager: _manager,
      icon: Icons.refresh_rounded,
      title: 'Anki: Daily review cards',
      subtitle: 'Max Anki review cards per day',
      min: 0,
      max: 500,
      divisions: 50,
      getValue: (m) => m.dailyReviewLimit,
      setValue: (m, v) => m.setDailyReviewLimit(v),
    );
  }
}

class _AnkiLimitSlider extends StatefulWidget {
  final AnkiDeckManager manager;
  final IconData icon;
  final String title;
  final String subtitle;
  final int min;
  final int max;
  final int divisions;
  final int Function(AnkiDeckManager) getValue;
  final Future<void> Function(AnkiDeckManager, int) setValue;

  const _AnkiLimitSlider({
    required this.manager,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.min,
    required this.max,
    required this.divisions,
    required this.getValue,
    required this.setValue,
  });

  @override
  State<_AnkiLimitSlider> createState() => _AnkiLimitSliderState();
}

class _AnkiLimitSliderState extends State<_AnkiLimitSlider> {
  late int _value;

  @override
  void initState() {
    super.initState();
    _value = widget.getValue(widget.manager);
  }

  @override
  Widget build(BuildContext context) {
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
                child: Icon(
                  widget.icon,
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
                      widget.title,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    Text(
                      widget.subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: VarnamalaTheme.textHintColor(context),
                          ),
                    ),
                  ],
                ),
              ),
              Text(
                '$_value',
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
              value: _value.toDouble(),
              min: widget.min.toDouble(),
              max: widget.max.toDouble(),
              divisions: widget.divisions,
              activeColor: VarnamalaTheme.peacockTeal,
              inactiveColor: VarnamalaTheme.dividerBg(context),
              onChanged: (value) {
                setState(() => _value = value.round());
              },
              onChangeEnd: (value) {
                widget.setValue(widget.manager, value.round());
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Toggle controlling whether imported Anki cards appear in the daily
/// challenge. Reads/writes [AnkiDeckManager.dailyChallengeIncludesAnki].
class SettingsDailyChallengeAnkiTile extends StatefulWidget {
  const SettingsDailyChallengeAnkiTile({super.key});

  @override
  State<SettingsDailyChallengeAnkiTile> createState() =>
      _SettingsDailyChallengeAnkiTileState();
}

class _SettingsDailyChallengeAnkiTileState
    extends State<SettingsDailyChallengeAnkiTile> {
  late final AnkiDeckManager _manager = AnkiDeckManager(
    repo: getIt(),
    srsProvider: getIt(),
    importDao: getIt(),
    appPrefs: getIt<AppPrefs>(),
  );
  late bool _value = _manager.dailyChallengeIncludesAnki;

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      icon: Icons.emoji_events_outlined,
      title: 'Anki cards in Daily Challenge',
      subtitle: 'Include imported Anki cards in the daily challenge pool',
      trailing: Switch.adaptive(
        value: _value,
        activeTrackColor: VarnamalaTheme.peacockTeal,
        onChanged: (newValue) {
          setState(() => _value = newValue);
          _manager.setDailyChallengeIncludesAnki(newValue);
        },
      ),
    );
  }
}