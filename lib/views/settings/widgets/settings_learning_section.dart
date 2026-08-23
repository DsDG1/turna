// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/anki/anki_deck_manager.dart';
import 'package:turna/application/audio_controller.dart';
import 'package:turna/application/language_provider.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/application/streak_provider.dart';
import 'package:turna/core/enums.dart';
import 'package:turna/core/extensions.dart';
import 'package:turna/core/fsrs_optimizer.dart';
import 'package:turna/data/review_history_dao.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/settings/widgets/settings_common.dart';
import 'package:turna/views/theme.dart';

class SettingsLanguageSelectorTile extends StatelessWidget {
  const SettingsLanguageSelectorTile({super.key});

  @override
  Widget build(BuildContext context) {
    final current = context.select<LanguageProvider, TargetLanguage>(
      (p) => p.selectedLanguage,
    );

    return PopupMenuButton<TargetLanguage>(
      initialValue: current,
      onSelected: (value) {
        final languageProvider = context.read<LanguageProvider>();
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
                        ? TurnaTheme.brandTeal
                        : TurnaTheme.textHint,
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
        title: AppStrings.settingsLearningLanguageTitle,
        subtitle: AppStrings.settingsLearningLanguageSubtitle,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              current.name.toTitleCase,
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
      ),
    );
  }
}

class SettingsStreakVoucherAutoUseTile extends StatefulWidget {
  const SettingsStreakVoucherAutoUseTile({super.key});

  @override
  State<SettingsStreakVoucherAutoUseTile> createState() =>
      _SettingsStreakVoucherAutoUseTileState();
}

class _SettingsStreakVoucherAutoUseTileState
    extends State<SettingsStreakVoucherAutoUseTile> {
  late final StreakProvider _streak = getIt<StreakProvider>();

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      icon: Icons.shield_outlined,
      title: '自动使用连续学习保护券',
      subtitle: '默认关闭；只保护连续天数，不会生成学习记录',
      trailing: settingsAdaptiveSwitch(
        value: _streak.autoUseVoucher,
        onChanged: (value) async {
          await _streak.setAutoUseVoucher(value);
          if (mounted) setState(() {});
        },
      ),
    );
  }
}

/// TTS speed slider. Uses local state while dragging so we do not write
/// SharedPreferences or call [SettingsProvider.notifyListeners] on every frame.
class SettingsTtsSpeedTile extends StatefulWidget {
  const SettingsTtsSpeedTile({super.key});

  @override
  State<SettingsTtsSpeedTile> createState() => _SettingsTtsSpeedTileState();
}

class _SettingsTtsSpeedTileState extends State<SettingsTtsSpeedTile> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final persisted =
        context.select<SettingsProvider, double>((p) => p.ttsSpeed);
    final value = _dragValue ?? persisted;

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
                  color: TurnaTheme.brandTeal.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
                ),
                child: const Icon(
                  Icons.record_voice_over_rounded,
                  color: TurnaTheme.brandTeal,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.settingsTtsSpeedTitle,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    Text(
                      AppStrings.settingsTtsSpeedSubtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: TurnaTheme.textHintColor(context),
                          ),
                    ),
                  ],
                ),
              ),
              Text(
                AppStrings.settingsTtsSpeedValue(value.toStringAsFixed(1)),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: TurnaTheme.brandTeal,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 52),
            child: Slider.adaptive(
              value: value,
              min: 0.5,
              max: 2.0,
              divisions: 15,
              activeColor: TurnaTheme.brandTeal,
              inactiveColor: TurnaTheme.dividerBg(context),
              onChanged: (v) {
                setState(() => _dragValue = v);
                // Preview immediately without prefs write / provider notify.
                getIt<AudioController>().setTtsSpeed(v);
              },
              onChangeEnd: (v) async {
                await context.read<SettingsProvider>().setTtsSpeed(v);
                if (mounted) setState(() => _dragValue = null);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Local FSRS weight fit + reset (ADR 0029). Binary scoring only.
class SettingsSrsWeightsTile extends StatefulWidget {
  const SettingsSrsWeightsTile({super.key});

  @override
  State<SettingsSrsWeightsTile> createState() => _SettingsSrsWeightsTileState();
}

class _SettingsSrsWeightsTileState extends State<SettingsSrsWeightsTile> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final custom = settings.hasCustomFsrsWeights;
    final subtitle = custom
        ? AppStrings.settingsSrsWeightsCustom(settings.fsrsOptimizedReviews)
        : AppStrings.settingsSrsWeightsDefault;

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
                  color: TurnaTheme.brandTeal.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
                ),
                child: const Icon(
                  Icons.auto_graph_rounded,
                  color: TurnaTheme.brandTeal,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppStrings.settingsSrsWeightsTitle,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: TurnaTheme.textHintColor(context),
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
            child: Text(
              AppStrings.settingsSrsOptimizeHint,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: TurnaTheme.textHintColor(context),
                  ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: _busy ? null : () => _optimize(context),
                  child: Text(
                    _busy
                        ? AppStrings.settingsSrsOptimizing
                        : AppStrings.settingsSrsOptimize,
                  ),
                ),
              ),
              if (custom) ...[
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => context
                          .read<SettingsProvider>()
                          .clearFsrsParameters(),
                  child: Text(AppStrings.settingsSrsResetWeights),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _optimize(BuildContext context) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dao = getIt<ReviewHistoryDao>();
      final events = await dao.allEvents();
      final result = await Future<FsrsOptimizeResult>(() {
        return FsrsLiteOptimizer().optimize(events);
      });
      if (!context.mounted) return;
      if (result.message == 'need_more_reviews') {
        messenger.showSnackBar(
          SnackBar(content: Text(AppStrings.settingsSrsOptimizeNeedMore)),
        );
      } else if (result.accepted) {
        await context.read<SettingsProvider>().applyFsrsParameters(
              result.parameters,
              reviewCount: result.reviewCount,
            );
        if (!context.mounted) return;
        messenger.showSnackBar(
          SnackBar(content: Text(AppStrings.settingsSrsOptimizeAccepted)),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(content: Text(AppStrings.settingsSrsOptimizeRejected)),
        );
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

/// FSRS target retention (binary scoring only — not a four-grade UI).
class SettingsSrsRetentionTile extends StatefulWidget {
  const SettingsSrsRetentionTile({super.key});

  @override
  State<SettingsSrsRetentionTile> createState() =>
      _SettingsSrsRetentionTileState();
}

class _SettingsSrsRetentionTileState extends State<SettingsSrsRetentionTile> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final stored = context.select<SettingsProvider, double>(
      (p) => p.srsDesiredRetention,
    );
    final value = _dragValue ?? stored;
    final percent = (value * 100).round();

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
                  color: TurnaTheme.brandTeal.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
                ),
                child: const Icon(
                  Icons.psychology_rounded,
                  color: TurnaTheme.brandTeal,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  AppStrings.settingsSrsRetentionTitle,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              Text(
                AppStrings.settingsSrsRetentionValue(percent),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: TurnaTheme.brandTeal,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 52),
            child: Slider.adaptive(
              value: value,
              min: 0.80,
              max: 0.95,
              divisions: 15,
              activeColor: TurnaTheme.brandTeal,
              inactiveColor: TurnaTheme.dividerBg(context),
              onChanged: (v) => setState(() => _dragValue = v),
              onChangeEnd: (v) async {
                await context
                    .read<SettingsProvider>()
                    .setSrsDesiredRetention(v);
                if (mounted) setState(() => _dragValue = null);
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
  late final AnkiDeckManager _manager = getIt<AnkiDeckManager>();

  @override
  Widget build(BuildContext context) {
    return _AnkiLimitSlider(
      manager: _manager,
      icon: Icons.add_card_outlined,
      title: AppStrings.settingsAnkiNewCardsTitle,
      subtitle: AppStrings.settingsAnkiNewCardsSubtitle,
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

class _SettingsAnkiReviewLimitTileState
    extends State<SettingsAnkiReviewLimitTile> {
  late final AnkiDeckManager _manager = getIt<AnkiDeckManager>();

  @override
  Widget build(BuildContext context) {
    return _AnkiLimitSlider(
      manager: _manager,
      icon: Icons.refresh_rounded,
      title: AppStrings.settingsAnkiReviewCardsTitle,
      subtitle: AppStrings.settingsAnkiReviewCardsSubtitle,
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
                  color: TurnaTheme.brandTeal.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
                ),
                child: Icon(
                  widget.icon,
                  color: TurnaTheme.brandTeal,
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
                            color: TurnaTheme.textHintColor(context),
                          ),
                    ),
                  ],
                ),
              ),
              Text(
                '$_value',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: TurnaTheme.brandTeal,
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
              activeColor: TurnaTheme.brandTeal,
              inactiveColor: TurnaTheme.dividerBg(context),
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
  late final AnkiDeckManager _manager = getIt<AnkiDeckManager>();
  late bool _value = _manager.dailyChallengeIncludesAnki;

  @override
  Widget build(BuildContext context) {
    return SettingsTile(
      icon: Icons.emoji_events_outlined,
      title: AppStrings.settingsAnkiDailyChallengeTitle,
      subtitle: AppStrings.settingsAnkiDailyChallengeSubtitle,
      trailing: settingsAdaptiveSwitch(
        value: _value,
        onChanged: (newValue) {
          setState(() => _value = newValue);
          _manager.setDailyChallengeIncludesAnki(newValue);
        },
      ),
    );
  }
}
