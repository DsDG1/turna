// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/audio_controller.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/language_provider.dart';
import 'package:turna/application/language_registry.dart';
import 'package:turna/application/settings/commands/apply_fsrs_parameters_command.dart';
import 'package:turna/application/settings/settings_operation_result.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/application/streak_provider.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/course_scope.dart';
import 'package:turna/domain/course/language_codes.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/settings/widgets/settings_common.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/views/widgets/turna_snack_bar.dart';

/// Learning-language picker. Switches the *course scope* (the same action
/// as tapping a course in course management) so the course tree, SRS /
/// mistake / stats filters and the persisted selection all move together —
/// flipping only [LanguageProvider] used to leave practice on the old
/// course and silently revert on the next scope restore. Lists every
/// installed builtin-scope language, imported `.turnapack` courses
/// included; falls back to the packed manifest while the catalog has not
/// loaded yet.
class SettingsLanguageSelectorTile extends StatelessWidget {
  const SettingsLanguageSelectorTile({super.key});

  @override
  Widget build(BuildContext context) {
    final courseProvider = context.watch<CourseProvider>();
    final entries = courseProvider.catalogEntries
        .where((e) => e.isBuiltin)
        .toList(growable: false);
    final fromCatalog = entries.isNotEmpty;
    final activeScope = courseProvider.courseScope;
    final languageProvider = context.watch<LanguageProvider>();
    final fallbackCurrent = languageProvider.selectedLanguageCode;

    return PopupMenuButton<String>(
      initialValue: fromCatalog ? activeScope : fallbackCurrent,
      onSelected: (value) => _switchCourse(context, value),
      itemBuilder: (context) => fromCatalog
          ? [
              for (final entry in entries)
                _menuItem(
                  (entry.scope as BuiltinCourseScope).languageCode,
                  entry.displayName,
                  entry.wireKey == activeScope,
                ),
            ]
          : [
              for (final lang in LanguageRegistry.instance.languages)
                _menuItem(
                  lang.code,
                  lang.displayName,
                  lang.code == fallbackCurrent,
                ),
            ],
      child: SettingsTile(
        icon: Icons.language_rounded,
        title: AppStrings.settingsLearningLanguageTitle,
        subtitle: AppStrings.settingsLearningLanguageSubtitle,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              languageProvider.displayName,
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

  PopupMenuItem<String> _menuItem(String code, String label, bool selected) =>
      PopupMenuItem(
        value: code,
        child: Row(
          children: [
            Icon(
              Icons.language_rounded,
              size: 18,
              color: selected ? TurnaTheme.brandTeal : TurnaTheme.textHint,
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ],
        ),
      );

  Future<void> _switchCourse(BuildContext context, String code) async {
    // Same sequence as course management's _selectCourse: flip the language
    // immediately for TTS/display feedback, then let setScope own the full
    // cascade (course tree reload, SRS/mistakes/stats filters, persistence).
    final languageProvider = context.read<LanguageProvider>();
    languageProvider.setLanguageCode(code);
    // Persistence failure must not become an unhandled async error —
    // catch it and surface once instead.
    unawaited(
      languageProvider.cacheLanguage().catchError((Object error) {
        if (kDebugMode) {
          logger.w('Language persist failed: $error');
        }
      }),
    );
    try {
      await context.read<CourseProvider>().setScope(
            BuiltinCourseScope(LanguageCodes.canonicalize(code)),
          );
    } catch (error) {
      if (context.mounted) {
        TurnaSnackBar.show(
            context, AppStrings.settingsLanguageSwitchFailed(error));
      }
    }
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
      title: AppStrings.settingsStreakVoucherAutoUseTitle,
      subtitle: AppStrings.settingsStreakVoucherAutoUseSubtitle,
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
                      : () async {
                          final result =
                              await getIt<ApplyFsrsParametersCommand>()
                                  .execute(null, reviewCount: 0);
                          if (!context.mounted) return;
                          if (result case SettingsOperationFailure failure) {
                            TurnaSnackBar.show(context, failure.userMessage);
                          }
                        },
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
    // The CPU-heavy fit runs on a background isolate inside the command;
    // this widget only reports the structured outcome.
    final outcome =
        await getIt<ApplyFsrsParametersCommand>().optimizeInBackground();
    if (!context.mounted) return;
    switch (outcome) {
      case FsrsOptimizeNeedMoreReviews():
        TurnaSnackBar.showVia(
            messenger, context, AppStrings.settingsSrsOptimizeNeedMore);
      case FsrsOptimizeAccepted():
        TurnaSnackBar.showVia(
            messenger, context, AppStrings.settingsSrsOptimizeAccepted);
      case FsrsOptimizeRejected():
        TurnaSnackBar.showVia(
            messenger, context, AppStrings.settingsSrsOptimizeRejected);
      case FsrsOptimizeFailed(:final userMessage):
        TurnaSnackBar.showVia(messenger, context, userMessage);
    }
    setState(() => _busy = false);
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
///
/// 湿地雾光 R16 / ADR 0066：Anki 每日上限设置已迁往记忆卡域，本域的
/// `SettingsAnkiNewLimitTile` / `SettingsAnkiReviewLimitTile` /
/// `SettingsDailyChallengeAnkiTile` 随之从设置页摘除（承接待记忆卡中枢集成）。

class SettingsReviewBatchTile extends StatelessWidget {
  const SettingsReviewBatchTile({super.key});

  @override
  Widget build(BuildContext context) {
    final value = context.select<SettingsProvider, int>(
      (p) => p.reviewBatchSize,
    );
    return SettingsTile(
      icon: Icons.layers_rounded,
      title: AppStrings.settingsReviewBatchTitle,
      subtitle: AppStrings.settingsReviewBatchSubtitle,
      trailing: DropdownButton<int>(
        value: {20, 25, 30}.contains(value) ? value : 25,
        underline: const SizedBox.shrink(),
        items: const [
          DropdownMenuItem(value: 20, child: Text('20')),
          DropdownMenuItem(value: 25, child: Text('25')),
          DropdownMenuItem(value: 30, child: Text('30')),
        ],
        onChanged: (next) {
          if (next == null) return;
          context.read<SettingsProvider>().setReviewBatchSize(next);
        },
      ),
    );
  }
}
