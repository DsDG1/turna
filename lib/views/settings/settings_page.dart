// Flutter imports:
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/achievements/achievement_service.dart';
import 'package:turna/application/anki/anki_deck_manager.dart';
import 'package:turna/application/audio_controller.dart';
import 'package:turna/application/game_provider.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/settings/settings_destination.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/service/export_service.dart';
import 'package:turna/service/local_reminder_service.dart';
import 'package:turna/views/settings/widgets/settings_about_section.dart';
import 'package:turna/views/settings/widgets/settings_accessibility_section.dart';
import 'package:turna/views/settings/widgets/settings_account_section.dart';
import 'package:turna/views/settings/widgets/settings_advanced_section.dart';
import 'package:turna/views/settings/widgets/settings_appearance_section.dart';
import 'package:turna/views/settings/widgets/settings_common.dart';
import 'package:turna/views/settings/widgets/settings_fun_section.dart';
import 'package:turna/views/settings/widgets/settings_learning_section.dart';
import 'package:turna/views/settings/widgets/settings_reminder_section.dart';
import 'package:turna/views/settings/widgets/settings_sound_section.dart';
import 'package:turna/utils/ohos_file_picker.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/theme.dart';

/// Settings landing page + typed in-page sub-page navigator (Plan 2 §5).
///
/// Because [SettingsPage] lives inside the Home `IndexedStack` (not a routed
/// page) and is switched to via `TabRouter`, sub-page navigation stays
/// in-page. Category identity is the strongly-typed [SettingsDestination] —
/// never an integer index — so inserting/removing tiles cannot shift another
/// category's identity. External callers (AI not-configured banners, storage
/// warnings) deep-link via [openSettings], which switches the Home tab and
/// delivers a [SettingsNavRequest] through [SettingsNavController].
///
/// Visited sub-pages stay mounted in an [IndexedStack] so scroll positions and
/// local state (e.g. slider drags) survive navigating back and forth.
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  /// null = landing category list; otherwise the open sub-page.
  SettingsDestination? _destination;

  /// Second-level anchor inside the Advanced destination.
  SettingsAdvancedAnchor? _advancedAnchor;

  /// Bumped when learning defaults are reset so Anki slider local state rebuilds.
  int _learningSectionEpoch = 0;

  /// Destinations the user has opened at least once. Kept mounted in the
  /// IndexedStack (slot 0 = landing) to preserve scroll/state per page.
  final Set<SettingsDestination> _visited = <SettingsDestination>{};

  SettingsNavController? _navController;

  @override
  void initState() {
    super.initState();
    if (getIt.isRegistered<SettingsNavController>()) {
      _navController = getIt<SettingsNavController>();
      _navController!.addListener(_onExternalNavRequest);
    }
  }

  @override
  void dispose() {
    _navController?.removeListener(_onExternalNavRequest);
    super.dispose();
  }

  void _onExternalNavRequest() {
    final controller = _navController;
    if (controller == null) return;
    final request = controller.consumePending();
    if (request == null) return;
    if (!mounted) return;
    _openDestination(request.destination, anchor: request.anchor);
  }

  void _openDestination(
    SettingsDestination destination, {
    SettingsAdvancedAnchor? anchor,
  }) {
    setState(() {
      _destination = destination;
      _visited.add(destination);
      // Anchors that map to routed pages push immediately; the compatibility
      // anchor is an in-page sub-page of Advanced.
      _advancedAnchor =
          destination == SettingsDestination.advanced ? anchor : null;
    });
    _maybePushAnchorRoute(anchor);
  }

  void _maybePushAnchorRoute(SettingsAdvancedAnchor? anchor) {
    switch (anchor) {
      case SettingsAdvancedAnchor.aiConnection:
        context.router.push(const AiApiConfigRoute());
      case SettingsAdvancedAnchor.storagePerformance:
        context.router.push(StorageDiagnosticsRoute());
      case SettingsAdvancedAnchor.systemHealth:
        context.router.push(const SystemHealthRoute());
      case SettingsAdvancedAnchor.legacyCompatibility:
      case null:
        break;
    }
  }

  void _backToLanding() {
    // Two-level back inside Advanced: the legacy-compatibility page returns
    // to the advanced hub first; the hub then returns to the landing list.
    if (_destination == SettingsDestination.advanced &&
        _advancedAnchor == SettingsAdvancedAnchor.legacyCompatibility) {
      setState(() => _advancedAnchor = null);
      return;
    }
    setState(() {
      _destination = null;
      _advancedAnchor = null;
    });
  }

  // ─── Category metadata ──────────────────────────────────────────────────

  String _titleFor(SettingsDestination destination) {
    switch (destination) {
      case SettingsDestination.account:
        return AppStrings.settingsCategoryAccount;
      case SettingsDestination.learning:
        return AppStrings.settingsCategoryLearning;
      case SettingsDestination.appearanceAndSound:
        return AppStrings.settingsCategoryAppearanceSound;
      case SettingsDestination.accessibility:
        return AppStrings.settingsCategoryAccessibility;
      case SettingsDestination.dataAndBackup:
        return AppStrings.settingsCategoryDataBackup;
      case SettingsDestination.advanced:
        return _advancedAnchor == SettingsAdvancedAnchor.legacyCompatibility
            ? AppStrings.settingsAdvancedLegacyTitle
            : AppStrings.settingsCategoryAdvanced;
      case SettingsDestination.about:
        return AppStrings.settingsCategoryAbout;
      case SettingsDestination.developer:
        return AppStrings.settingsCategoryFunLab;
    }
  }

  IconData _iconFor(SettingsDestination destination) {
    switch (destination) {
      case SettingsDestination.account:
        return Icons.person_rounded;
      case SettingsDestination.learning:
        return Icons.menu_book_rounded;
      case SettingsDestination.appearanceAndSound:
        return Icons.palette_rounded;
      case SettingsDestination.accessibility:
        return Icons.accessibility_new_rounded;
      case SettingsDestination.dataAndBackup:
        return Icons.storage_rounded;
      case SettingsDestination.advanced:
        return Icons.build_rounded;
      case SettingsDestination.about:
        return Icons.info_rounded;
      case SettingsDestination.developer:
        return Icons.science_rounded;
    }
  }

  String _subtitleFor(SettingsDestination destination) {
    switch (destination) {
      case SettingsDestination.account:
        return AppStrings.settingsCategoryAccountSubtitle;
      case SettingsDestination.learning:
        return AppStrings.settingsCategoryLearningSubtitle;
      case SettingsDestination.appearanceAndSound:
        return AppStrings.settingsCategoryAppearanceSoundSubtitle;
      case SettingsDestination.accessibility:
        return AppStrings.settingsCategoryAccessibilitySubtitle;
      case SettingsDestination.dataAndBackup:
        return AppStrings.settingsCategoryDataBackupSubtitle;
      case SettingsDestination.advanced:
        return AppStrings.settingsCategoryAdvancedSubtitle;
      case SettingsDestination.about:
        return AppStrings.settingsCategoryAboutSubtitle;
      case SettingsDestination.developer:
        return AppStrings.settingsCategoryFunLabSubtitle;
    }
  }

  /// Landing groups (Plan 2 §5.2): person / learning experience / data &
  /// system / product. The developer lab is debug-only and never present in
  /// release/profile builds (Plan 2 §4.4).
  List<(String, List<SettingsDestination>)> get _groups {
    return [
      (
        AppStrings.settingsGroupPersonal,
        [SettingsDestination.account],
      ),
      (
        AppStrings.settingsGroupLearning,
        [
          SettingsDestination.learning,
          SettingsDestination.appearanceAndSound,
          SettingsDestination.accessibility,
        ],
      ),
      (
        AppStrings.settingsGroupDataSystem,
        [SettingsDestination.dataAndBackup, SettingsDestination.advanced],
      ),
      (
        AppStrings.settingsGroupProduct,
        [SettingsDestination.about],
      ),
      if (kDebugMode)
        (
          AppStrings.settingsCategoryFunLab,
          [SettingsDestination.developer],
        ),
    ];
  }

  // ─── Build ───────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isList = _destination == null;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final titleIcon = isList
        ? Icons.settings_rounded
        : _iconFor(_destination!);
    final titleText =
        isList ? AppStrings.settingsTitle : _titleFor(_destination!);

    return PopScope(
      // When a sub-page is open, the system back button returns to the
      // category list instead of leaving the Settings tab.
      canPop: isList,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _destination != null) {
          _backToLanding();
        }
      },
      child: Scaffold(
        backgroundColor: TurnaTheme.surfaceColor(context),
        appBar: AppBar(
          backgroundColor: TurnaTheme.surfaceColor(context),
          elevation: 0,
          centerTitle: true,
          leading: isList
              ? null
              : IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  tooltip: AppStrings.settingsBack,
                  onPressed: _backToLanding,
                ),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                titleIcon,
                color: TurnaTheme.brandTeal,
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
          duration:
              reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
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
          child: isList ? _buildCategoryList() : _buildSubPage(_destination!),
        ),
      ),
    );
  }

  Widget _buildCategoryList() {
    return SingleChildScrollView(
      key: const ValueKey('settings-list'),
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        0,
        0,
        0,
        16 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (groupTitle, destinations) in _groups) ...[
            SettingsSectionTitle(
              icon: _iconFor(destinations.first),
              title: groupTitle,
            ),
            const SizedBox(height: 8),
            _categoryCard(destinations),
            const SizedBox(height: 20),
          ],
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  Widget _categoryCard(List<SettingsDestination> destinations) {
    return SettingsCard(
      children: [
        for (int i = 0; i < destinations.length; i++) ...[
          if (i > 0) settingsTileDivider(context),
          Builder(
            builder: (context) {
              final destination = destinations[i];
              return SettingsNavigationTile(
                key: ValueKey(destination.name),
                icon: _iconFor(destination),
                title: _titleFor(destination),
                subtitle: _subtitleFor(destination),
                onTap: (_) => _openDestination(destination),
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildSubPage(SettingsDestination destination) {
    // Keep every visited sub-page mounted (hidden ones are offstage by the
    // AnimatedSwitcher's Stack) so their scroll positions and local state
    // survive navigating between them and the landing list.
    return Stack(
      children: [
        for (final visited in SettingsDestination.values)
          if (_visited.contains(visited))
            Offstage(
              offstage: visited != destination,
              child: _subPageContent(visited),
            ),
      ],
    );
  }

  Widget _subPageContent(SettingsDestination destination) {
    return SingleChildScrollView(
      key: ValueKey('settings-${destination.name}'),
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.fromLTRB(
        0,
        0,
        0,
        16 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _sectionChildren(destination),
      ),
    );
  }

  List<Widget> _sectionChildren(SettingsDestination destination) {
    switch (destination) {
      case SettingsDestination.account:
        return [
          SettingsAccountSection(
            key: const ValueKey('account-section'),
            onNavigateToData: () => _openDestination(
              SettingsDestination.dataAndBackup,
            ),
          ),
          const SizedBox(height: 24),
        ];
      case SettingsDestination.learning:
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
      case SettingsDestination.appearanceAndSound:
        // "我喜欢怎样显示/播放" — themes and feedback channels (Plan 2 §4.2).
        return [
          SettingsSectionTitle(
            icon: Icons.palette_rounded,
            title: AppStrings.settingsAppearanceSectionTitle,
          ),
          const SizedBox(height: 8),
          const SettingsThemeSelector(),
          const SizedBox(height: 8),
          SettingsCard(
            children: [
              SettingsToggleTile(
                icon: Icons.screen_rotation_rounded,
                title: AppStrings.settingsAutoRotateTitle,
                subtitle: AppStrings.settingsAutoRotateSubtitle,
                valueSelector: (p) => p.autoRotateEnabled,
                onChanged: (p, value) => p.setAutoRotateEnabled(value),
              ),
            ],
          ),
          const SizedBox(height: 20),
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
      case SettingsDestination.accessibility:
        // "我需要怎样访问内容" — reading, motion, contrast, focus (Plan 2 §4.2).
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
          const SizedBox(height: 24),
        ];
      case SettingsDestination.dataAndBackup:
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
                icon: Icons.cloud_upload_outlined,
                title: AppStrings.settingsRemoteBackupTitle,
                subtitle: defaultTargetPlatform.name == 'ohos'
                    ? AppStrings.settingsRemoteBackupUnsupported
                    : AppStrings.settingsRemoteBackupSubtitle,
                enabled: defaultTargetPlatform.name != 'ohos',
                onTap: (context) =>
                    context.router.push(const RemoteBackupRoute()),
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
      case SettingsDestination.advanced:
        return [
          SettingsAdvancedSection(
            showLegacy:
                _advancedAnchor == SettingsAdvancedAnchor.legacyCompatibility,
            onOpenLegacy: () => setState(
              () => _advancedAnchor = SettingsAdvancedAnchor.legacyCompatibility,
            ),
          ),
          const SizedBox(height: 24),
        ];
      case SettingsDestination.about:
        return const [SettingsAboutSection(), SizedBox(height: 24)];
      case SettingsDestination.developer:
        return const [
          SettingsFunSection(),
          _DeveloperLabSection(),
          SizedBox(height: 24),
        ];
    }
  }

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

  Future<void> _openExportSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: TurnaTheme.cardBg(context),
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
      ))
          ?.files
          .single
          .path;
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
      if (import.progressRestored) {
        // Reload the in-memory achievement caches so the restored v2 state /
        // projection are visible without waiting for a restart.
        unawaited(
          getIt<AchievementService>().reloadFromPrefs().catchError((Object e) {
            debugPrint('Achievement reload after import failed: $e');
          }),
        );
      }
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

/// Debug-only engine diagnostics that used to live on the formal Advanced
/// page (Plan 2 §4.6): the Official-Anki internal import. Kept reachable only
/// through the developer lab so release builds never expose a second import
/// path that competes with the unified import flow.
class _DeveloperLabSection extends StatelessWidget {
  const _DeveloperLabSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        SettingsSectionTitle(
          icon: Icons.bug_report_rounded,
          title: 'Engine 诊断',
        ),
        const SizedBox(height: 8),
        SettingsCard(
          children: [
            SettingsNavigationTile(
              icon: Icons.inventory_2_outlined,
              title: 'Official Anki 内部导入',
              subtitle: '内部构建：官方导入与正式复习（仅开发环境）',
              onTap: (ctx) =>
                  ctx.router.push(const OfficialAnkiInternalRoute()),
            ),
          ],
        ),
      ],
    );
  }
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
                  color: TurnaTheme.textHintColor(context),
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
                        color: TurnaTheme.textOnPrimary,
                      ),
                    )
                  : const Icon(Icons.ios_share_rounded),
              label: Text(_exporting
                  ? AppStrings.settingsExporting
                  : AppStrings.settingsExportButton),
            ),
          ),
        ],
      ),
    );
  }
}
