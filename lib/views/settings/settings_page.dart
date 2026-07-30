// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/ai/ai_course_provider.dart';
import 'package:varnamala/application/anki/anki_deck_manager.dart';
import 'package:varnamala/application/audio_controller.dart';
import 'package:varnamala/application/game_provider.dart';
import 'package:varnamala/application/mistake_provider.dart';
import 'package:varnamala/application/settings_provider.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/routing/routing.gr.dart';
import 'package:varnamala/service/export_service.dart';
import 'package:varnamala/service/local_reminder_service.dart';
import 'package:varnamala/views/settings/ai_api_config_sheet.dart';
import 'package:varnamala/views/settings/widgets/settings_about_section.dart';
import 'package:varnamala/views/settings/widgets/settings_accessibility_section.dart';
import 'package:varnamala/views/settings/widgets/settings_account_section.dart';
import 'package:varnamala/views/settings/widgets/settings_appearance_section.dart';
import 'package:varnamala/views/settings/widgets/settings_common.dart';
import 'package:varnamala/views/settings/widgets/settings_fun_section.dart';
import 'package:varnamala/views/settings/widgets/settings_learning_section.dart';
import 'package:varnamala/views/settings/widgets/settings_reminder_section.dart';
import 'package:varnamala/views/settings/widgets/settings_sound_section.dart';
import 'package:varnamala/views/settings/widgets/settings_xiaoyi_tile.dart';
import 'package:varnamala/utils/ohos_file_picker.dart';
import 'package:varnamala/l10n/app_strings.dart';
import 'package:varnamala/views/theme.dart';

/// Settings is organized as a category list that pushes a sub-page per
/// category (iOS Settings style). Because [SettingsPage] lives inside the
/// Home `IndexedStack` (not a routed page) and is switched to via `TabRouter`,
/// navigation is kept in-page with [_category] state rather than AutoRoute —
/// this preserves the "Go to settings" tab-switch and avoids touching routing.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  /// null = landing category list; 0..7 = the selected category sub-page.
  int? _category;

  /// Bumped when learning defaults are reset so Anki slider local state rebuilds.
  int _learningSectionEpoch = 0;

  static final _categories = <_SettingsCategory>[
    _SettingsCategory(
      index: 0,
      title: AppStrings.settingsCategoryAccount,
      subtitle: AppStrings.settingsCategoryAccountSubtitle,
      icon: Icons.person_rounded,
    ),
    _SettingsCategory(
      index: 1,
      title: AppStrings.settingsCategoryLearning,
      subtitle: AppStrings.settingsCategoryLearningSubtitle,
      icon: Icons.menu_book_rounded,
    ),
    _SettingsCategory(
      index: 2,
      title: AppStrings.settingsCategoryAudioHaptics,
      subtitle: AppStrings.settingsCategoryAudioHapticsSubtitle,
      icon: Icons.volume_up_rounded,
    ),
    _SettingsCategory(
      index: 3,
      title: AppStrings.settingsCategoryAccessibility,
      subtitle: AppStrings.settingsCategoryAccessibilitySubtitle,
      icon: Icons.accessibility_new_rounded,
    ),
    _SettingsCategory(
      index: 4,
      title: AppStrings.settingsCategoryAiTools,
      subtitle: AppStrings.settingsCategoryAiToolsSubtitle,
      icon: Icons.auto_awesome_rounded,
    ),
    _SettingsCategory(
      index: 5,
      title: AppStrings.settingsCategoryData,
      subtitle: AppStrings.settingsCategoryDataSubtitle,
      icon: Icons.storage_rounded,
    ),
    _SettingsCategory(
      index: 6,
      title: AppStrings.settingsCategoryAbout,
      subtitle: AppStrings.settingsCategoryAboutSubtitle,
      icon: Icons.info_rounded,
    ),
    _SettingsCategory(
      index: 7,
      title: AppStrings.settingsCategoryFunLab,
      subtitle: AppStrings.settingsCategoryFunLabSubtitle,
      icon: Icons.science_rounded,
    ),
  ];

  /// Main prefs (account → AI).
  static const _mainIndexes = [0, 1, 2, 3, 4];

  /// Data + About.
  static const _dataAboutIndexes = [5, 6];

  /// Fun lab (isolated group).
  static const _labIndexes = [7];

  @override
  Widget build(BuildContext context) {
    final isList = _category == null;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final titleIcon = isList
        ? Icons.settings_rounded
        : _categoryByIndex(_category!).icon;
    final titleText =
        isList ? AppStrings.settingsTitle : _categoryByIndex(_category!).title;

    return PopScope(
      // When a sub-page is open, the system back button returns to the
      // category list instead of leaving the Settings tab.
      canPop: isList,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _category != null) {
          setState(() => _category = null);
        }
      },
      child: Scaffold(
        backgroundColor: VarnamalaTheme.surfaceColor(context),
        appBar: AppBar(
          backgroundColor: VarnamalaTheme.surfaceColor(context),
          elevation: 0,
          centerTitle: true,
          leading: isList
              ? null
              : IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  tooltip: AppStrings.settingsBack,
                  onPressed: () => setState(() => _category = null),
                ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                titleIcon,
                color: VarnamalaTheme.peacockTeal,
                size: 22,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  titleText,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
        ),
        body: AnimatedSwitcher(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 220),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          // Top-align the cross-fade so short sub-pages don't jump after the
          // taller category list fades out.
          layoutBuilder: (currentChild, previousChildren) {
            return Stack(
              alignment: Alignment.topCenter,
              children: <Widget>[
                ...previousChildren,
                if (currentChild != null) currentChild,
              ],
            );
          },
          child: isList ? _buildCategoryList() : _buildSubPage(_category!),
        ),
      ),
    );
  }

  Widget _buildCategoryList() {
    return SingleChildScrollView(
      key: const ValueKey('settings-list'),
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsSectionTitle(
            icon: Icons.apps_rounded,
            title: AppStrings.settingsGroupMain,
          ),
          const SizedBox(height: 8),
          _categoryCard(_mainIndexes),
          const SizedBox(height: 20),
          SettingsSectionTitle(
            icon: Icons.folder_rounded,
            title: AppStrings.settingsGroupDataAbout,
          ),
          const SizedBox(height: 8),
          _categoryCard(_dataAboutIndexes),
          const SizedBox(height: 20),
          SettingsSectionTitle(
            icon: Icons.science_rounded,
            title: AppStrings.settingsGroupLab,
          ),
          const SizedBox(height: 8),
          _categoryCard(_labIndexes),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _categoryCard(List<int> indexes) {
    return SettingsCard(
      children: [
        for (int i = 0; i < indexes.length; i++) ...[
          if (i > 0) settingsTileDivider(context),
          Builder(
            builder: (context) {
              final cat = _categoryByIndex(indexes[i]);
              return SettingsNavigationTile(
                key: ValueKey(cat.title),
                icon: cat.icon,
                title: cat.title,
                subtitle: cat.subtitle,
                onTap: (_) => setState(() => _category = cat.index),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildSubPage(int category) {
    return SingleChildScrollView(
      key: ValueKey('settings-$category'),
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _sectionChildren(category),
      ),
    );
  }

  List<Widget> _sectionChildren(int category) {
    switch (category) {
      case 0:
        return [
          SettingsAccountSection(
            key: const ValueKey('account-section'),
            onNavigateToData: () => setState(() => _category = 5),
          ),
        ];
      case 1:
        // Match Account page rhythm: SectionTitle + SettingsCard groups.
        return [
          SettingsSectionTitle(
            icon: Icons.tune_rounded,
            title: AppStrings.settingsLearningPrefsTitle,
          ),
          const SizedBox(height: 8),
          SettingsCard(
            key: ValueKey('learning-prefs-$_learningSectionEpoch'),
            children: [
              const SettingsLanguageSelectorTile(),
              settingsTileDivider(context),
              const SettingsTtsSpeedTile(),
              settingsTileDivider(context),
              const SettingsSrsRetentionTile(),
              settingsTileDivider(context),
              const SettingsSrsWeightsTile(),
              settingsTileDivider(context),
              const SettingsDailyReminderTile(),
              // Xiaoyi renders its own leading divider only when supported
              // (avoids a double divider gap on non-HarmonyOS builds).
              const SettingsXiaoyiTile(),
            ],
          ),
          const SizedBox(height: 20),
          SettingsSectionTitle(
            icon: Icons.style_rounded,
            title: AppStrings.settingsAnkiSectionTitle,
          ),
          const SizedBox(height: 8),
          SettingsCard(
            key: ValueKey('anki-prefs-$_learningSectionEpoch'),
            children: [
              const SettingsAnkiNewLimitTile(),
              settingsTileDivider(context),
              const SettingsAnkiReviewLimitTile(),
              settingsTileDivider(context),
              const SettingsDailyChallengeAnkiTile(),
            ],
          ),
          const SizedBox(height: 12),
          SettingsCard(
            children: [
              SettingsActionTile(
                icon: Icons.restart_alt_rounded,
                title: AppStrings.settingsResetLearningDefaultsTitle,
                subtitle: AppStrings.settingsResetLearningDefaultsSubtitle,
                onTap: (context) => _confirmResetLearningDefaults(context),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ];
      case 2:
        return [
          SettingsSectionTitle(
            icon: Icons.volume_up_rounded,
            title: AppStrings.settingsAudioSectionTitle,
          ),
          const SizedBox(height: 8),
          SettingsCard(
            children: [
              SettingsToggleTile(
                icon: Icons.music_note_rounded,
                title: AppStrings.settingsSoundEffectsTitle,
                subtitle: AppStrings.settingsSoundEffectsSubtitle,
                valueSelector: (p) => p.soundEffectsEnabled,
                onChanged: (p, value) => p.setSoundEffects(value),
              ),
              settingsTileDivider(context),
              SettingsToggleTile(
                icon: Icons.vibration_rounded,
                title: AppStrings.settingsHapticFeedbackTitle,
                subtitle: AppStrings.settingsHapticFeedbackSubtitle,
                valueSelector: (p) => p.hapticFeedbackEnabled,
                onChanged: (p, value) => p.setHapticFeedback(value),
              ),
              settingsTileDivider(context),
              const SettingsTtsEngineTile(),
            ],
          ),
          const SizedBox(height: 24),
        ];
      case 3:
        return [
          SettingsSectionTitle(
            icon: Icons.accessibility_new_rounded,
            title: AppStrings.settingsA11ySectionTitle,
          ),
          const SizedBox(height: 8),
          SettingsCard(
            children: [
              const SettingsTextScaleTile(),
              settingsTileDivider(context),
              const SettingsReducedMotionTile(),
              settingsTileDivider(context),
              const SettingsHighContrastTile(),
              settingsTileDivider(context),
              const SettingsDyslexiaFontTile(),
              settingsTileDivider(context),
              const SettingsSensoryReduceTile(),
              settingsTileDivider(context),
              const SettingsFocusModeTile(),
            ],
          ),
          const SizedBox(height: 20),
          SettingsSectionTitle(
            icon: Icons.palette_rounded,
            title: AppStrings.settingsAppearanceSectionTitle,
          ),
          const SizedBox(height: 8),
          const SettingsThemeSelector(),
          const SizedBox(height: 24),
        ];
      case 4:
        return [
          SettingsSectionTitle(
            icon: Icons.auto_awesome_rounded,
            title: AppStrings.settingsAiSectionTitle,
          ),
          const SizedBox(height: 8),
          SettingsCard(
            children: [
              SettingsActionTile(
                icon: Icons.vpn_key_rounded,
                title: AppStrings.settingsAiApiConfigTitle,
                subtitle: AppStrings.settingsAiApiConfigSubtitle,
                onTap: (context) => _openAiApiConfigSheet(context),
              ),
              settingsTileDivider(context),
              SettingsActionTile(
                icon: Icons.auto_awesome_rounded,
                title: AppStrings.settingsDesignCourseAiTitle,
                subtitle: AppStrings.settingsDesignCourseAiSubtitle,
                onTap: (context) =>
                    context.router.push(const AiWishChatRoute()),
              ),
              settingsTileDivider(context),
              SettingsActionTile(
                icon: Icons.menu_book_rounded,
                title: AppStrings.settingsImportTextbookTitle,
                subtitle: AppStrings.settingsImportTextbookSubtitle,
                onTap: (context) =>
                    context.router.push(const TextbookImportRoute()),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ];
      case 5:
        return [
          SettingsSectionTitle(
            icon: Icons.storage_rounded,
            title: AppStrings.settingsDataSectionTitle,
          ),
          const SizedBox(height: 8),
          SettingsCard(
            children: [
              SettingsActionTile(
                icon: Icons.ios_share_rounded,
                title: AppStrings.settingsExportDataTitle,
                subtitle: AppStrings.settingsExportDataSubtitle,
                onTap: (context) => _openExportSheet(context),
              ),
              settingsTileDivider(context),
              SettingsActionTile(
                icon: Icons.file_upload_outlined,
                title: AppStrings.settingsImportDataTitle,
                subtitle: AppStrings.settingsImportDataSubtitle,
                onTap: (context) => _importData(context),
              ),
              settingsTileDivider(context),
              SettingsActionTile(
                icon: Icons.delete_sweep_rounded,
                title: AppStrings.settingsClearMistakeLogTitle,
                subtitle: AppStrings.settingsClearMistakeLogSubtitle,
                onTap: (context) => _confirmClearMistakes(context),
              ),
              settingsTileDivider(context),
              SettingsActionTile(
                icon: Icons.restart_alt_rounded,
                title: AppStrings.settingsResetProgressTitle,
                subtitle: AppStrings.settingsResetProgressSubtitle,
                onTap: (context) => _confirmResetProgress(context),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ];
      case 6:
        return const [SettingsAboutSection(), SizedBox(height: 24)];
      case 7:
        return const [SettingsFunSection(), SizedBox(height: 24)];
      default:
        return const [];
    }
  }

  _SettingsCategory _categoryByIndex(int category) =>
      _categories.firstWhere((c) => c.index == category);

  Future<void> _confirmClearMistakes(BuildContext context) async {
    final mistakeProvider = context.read<MistakeProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => SettingsConfirmDialog(
        title: AppStrings.settingsClearMistakeDialogTitle,
        message: AppStrings.settingsClearMistakeDialogMessage,
        confirmText: AppStrings.settingsClearMistakeConfirm,
      ),
    );
    if (confirmed == true) {
      await mistakeProvider.clear();
      if (context.mounted) {
        _showSnack(context, AppStrings.settingsMistakeLogCleared);
      }
    }
  }

  Future<void> _confirmResetProgress(BuildContext context) async {
    final gameProvider = context.read<GameProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => SettingsConfirmDialog(
        title: AppStrings.settingsResetProgressDialogTitle,
        message: AppStrings.settingsResetProgressDialogMessage,
        confirmText: AppStrings.settingsResetProgressConfirm,
      ),
    );
    if (confirmed == true) {
      await gameProvider.resetLessonProgress();
      if (context.mounted) {
        _showSnack(context, AppStrings.settingsProgressReset);
      }
    }
  }

  Future<void> _confirmResetLearningDefaults(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => SettingsConfirmDialog(
        title: AppStrings.settingsResetLearningDefaultsDialogTitle,
        message: AppStrings.settingsResetLearningDefaultsDialogMessage,
        confirmText: AppStrings.settingsResetLearningDefaultsConfirm,
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    final settings = context.read<SettingsProvider>();
    await settings.resetLearningDefaults();
    getIt<AudioController>().setTtsSpeed(settings.ttsSpeed);
    await getIt<LocalReminderService>().applyFromSettings(
      enabled: settings.dailyReminderEnabled,
      time: settings.dailyReminderTime,
    );

    await getIt<AnkiDeckManager>().resetLearningDefaults();

    if (!mounted) return;
    setState(() => _learningSectionEpoch++);
    if (context.mounted) {
      _showSnack(context, AppStrings.settingsResetLearningDefaultsDone);
    }
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _openAiApiConfigSheet(BuildContext context) async {
    final provider = context.read<AiCourseProvider>();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: VarnamalaTheme.cardBg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => AiApiConfigSheet(provider: provider),
    );
  }

  Future<void> _openExportSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: VarnamalaTheme.cardBg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _ExportSheet(),
    );
  }

  Future<void> _importData(BuildContext context) async {
    String? pickedPath;
    try {
      pickedPath = (await OhosFilePicker.pickFiles(
        allowedExtensions: const ['json'],
      ))?.files.single.path;
    } on OhosFilePickerInvalidExtension {
      return; // user picked a non-json file; ignore
    }
    if (pickedPath == null) return; // user cancelled
    if (!context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => SettingsConfirmDialog(
        title: AppStrings.settingsImportDataDialogTitle,
        message: AppStrings.settingsImportDataDialogMessage,
        confirmText: AppStrings.settingsImportDataConfirm,
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    try {
      final import = await getIt<ExportService>().importFromFile(pickedPath);
      if (!context.mounted) return;
      if (import.hasCoursePayload && !import.progressRestored) {
        _showSnack(context, AppStrings.settingsCourseSavedRestart);
      } else if (import.progressRestored) {
        _showSnack(context, AppStrings.settingsProgressRestoredRestart);
      } else {
        _showSnack(context, AppStrings.settingsNothingToImport);
      }
    } catch (e) {
      if (context.mounted) {
        _showSnack(context, AppStrings.settingsImportFailed(e));
      }
    }
  }
}

class _SettingsCategory {
  const _SettingsCategory({
    required this.index,
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final int index;
  final String title;
  final String subtitle;
  final IconData icon;
}

class _ExportSheet extends StatefulWidget {
  const _ExportSheet();

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  bool _includeProgress = true;
  bool _includeCourse = false;
  bool _exporting = false;

  bool get _canExport => _includeProgress || _includeCourse;

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final service = getIt<ExportService>();
      final file = await service.export(
        includeProgress: _includeProgress,
        includeCourse: _includeCourse,
      );
      await service.share(file);
      if (mounted) Navigator.of(context).maybePop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.settingsExportFailed(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                AppStrings.settingsExportSheetTitle,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close, size: 22),
                tooltip: AppStrings.commonClose,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            AppStrings.settingsExportSubtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: VarnamalaTheme.textHintColor(context),
                ),
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: _includeProgress,
            onChanged: _exporting
                ? null
                : (v) => setState(() => _includeProgress = v ?? false),
            title: Text(AppStrings.settingsExportProgressTitle),
            subtitle: Text(AppStrings.settingsExportProgressSubtitle),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          CheckboxListTile(
            value: _includeCourse,
            onChanged: _exporting
                ? null
                : (v) => setState(() => _includeCourse = v ?? false),
            title: Text(AppStrings.settingsExportCourseTitle),
            subtitle: Text(AppStrings.settingsExportCourseSubtitle),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: (_canExport && !_exporting) ? _export : null,
              icon: _exporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: VarnamalaTheme.textOnPrimary,
                      ),
                    )
                  : const Icon(Icons.ios_share_rounded),
              label: Text(_exporting ? AppStrings.settingsExporting : AppStrings.settingsExportButton),
            ),
          ),
        ],
      ),
    );
  }
}