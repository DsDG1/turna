// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/anki_official/anki_deck_manager.dart';
import 'package:turna/application/course_catalog.dart';
import 'package:turna/application/course_pack/course_pack.dart';
import 'package:turna/application/course_pack/course_pack_importer.dart';
import 'package:turna/application/course_pack/imported_languages.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/language_provider.dart';
import 'package:turna/application/language_registry.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/course_scope.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/utils/validated_file_picker.dart';
import 'package:turna/views/anki/import_wizard/official_pending_import_banner.dart';
import 'package:turna/views/anki_official/components/adaptation_restore_sheet.dart';
import 'package:turna/views/courses/components/course_management_cards.dart';
import 'package:turna/views/courses/components/course_tts_settings_sheet.dart';
import 'package:turna/views/widgets/turna_page_content.dart';
import 'package:turna/views/widgets/turna_snack_bar.dart';

/// Course management page — opened from the course switcher in the Learn
/// tab. Lists the built-in courses plus every imported memory-card deck
/// (one entry per source): switch the active course (tap), reorder courses
/// (drag), delete imported courses with an exact-source confirmation (the
/// built-in course can never be deleted), and reach the add-course entry
/// points (memory-card import + language pack import).
///
/// [highlightWire] briefly highlights one catalog entry (v1 scope wire key)
/// — used by the import wizard's "view decks" action (ADR 0043).
@RoutePage()
class CourseManagementPage extends StatelessWidget {
  const CourseManagementPage({super.key, this.highlightWire});

  final String? highlightWire;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TurnaTheme.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: TurnaTheme.surfaceColor(context),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.router.maybePop(),
        ),
        title: Text(
          AppStrings.courseManagementTitle,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: TurnaTheme.textPrimaryColor(context),
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            key: const Key('course-open-repair-center'),
            tooltip: AppStrings.databaseDoctorTitle,
            icon: const Icon(Icons.healing_outlined),
            onPressed: () =>
                context.router.push(OfficialAnkiRepairCenterRoute()),
          ),
        ],
      ),
      body: TurnaPageContent(
        maxWidth: 840,
        child: _CourseManagementBody(highlightWire: highlightWire),
      ),
    );
  }
}

class _CourseManagementBody extends StatefulWidget {
  const _CourseManagementBody({this.highlightWire});

  final String? highlightWire;

  @override
  State<_CourseManagementBody> createState() => _CourseManagementBodyState();
}

class _CourseManagementBodyState extends State<_CourseManagementBody> {
  String? _highlightWire;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _highlightWire = widget.highlightWire;
    if (_highlightWire != null) {
      // The highlight is a brief affordance, not a permanent state.
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) setState(() => _highlightWire = null);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final courseProvider = context.watch<CourseProvider>();
    final entries = courseProvider.catalogEntries;
    final restorable = courseProvider.restorableBuiltinLanguages;
    final activeScope = courseProvider.courseScope;
    // The read-aloud per-course entry is opt-in: it only appears once the
    // master switch in Settings > Learning is on.
    final ttsFeatureEnabled = context.select<SettingsProvider, bool>(
      (p) => p.ttsFeatureEnabled,
    );

    return Column(
      children: [
        if (_busy) const LinearProgressIndicator(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              AppStrings.courseManagementMyCourses,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: TurnaTheme.textSecondaryColor(context),
              ),
            ),
          ),
        ),
        Expanded(
          child: ReorderableListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            buildDefaultDragHandles: false,
            onReorderItem: (oldIndex, newIndex) => _onReorder(
              context,
              entries,
              oldIndex,
              newIndex,
            ),
            children: [
              for (var i = 0; i < entries.length; i++)
                CourseManagementCard(
                  key: ValueKey(entries[i].wireKey),
                  entry: entries[i],
                  index: i,
                  isActive: entries[i].wireKey == activeScope,
                  isHighlighted: entries[i].wireKey == _highlightWire,
                  ttsFeatureEnabled: ttsFeatureEnabled,
                  onTap:
                      _busy ? () {} : () => _selectCourse(context, entries[i]),
                  onSettings: () => _showTtsSettings(
                    context,
                    entries[i].wireKey,
                    entries[i].displayName,
                  ),
                  onDelete: _busy ||
                          (entries[i].isBuiltin &&
                              entries.where((e) => e.isBuiltin).length < 2)
                      ? null
                      : () => _confirmDelete(context, entries[i]),
                  // 只有官方来源才有适配方案可恢复（ADR 0057 §6）。
                  onAdaptation: _busy || entries[i].officialSourceId == null
                      ? null
                      : () => showAdaptationRestoreSheet(
                            context,
                            sourceId: entries[i].officialSourceId!,
                          ),
                ),
            ],
          ),
        ),
        const Divider(height: 1),
        // 底部「添加课程」区:内层 Column 必须用 MainAxisSize.min,
        // 否则它会吃掉外层 Column 的全部剩余高度,把 Expanded(ReorderableListView)
        // 挤成 0 高度,渲染出大面积红色溢出条。SingleChildScrollView 兜底,
        // 小屏 / 大字体下也能滚出来。
        SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    AppStrings.courseManagementAddTitle,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: TurnaTheme.textSecondaryColor(context),
                    ),
                  ),
                  const SizedBox(height: 8),
                  OfficialPendingImportBanner(
                    onChanged: () => setState(() {}),
                  ),
                  AddCourseCard(
                    title: AppStrings.courseManagementImportTitle,
                    onTap: () => context.router.push(const AnkiImportRoute()),
                  ),
                  const SizedBox(height: 8),
                  AddCourseCard(
                    key: const Key('course-import-pack'),
                    title: AppStrings.courseManagementImportPackTitle,
                    subtitle: AppStrings.courseManagementImportPackSubtitle,
                    onTap: () => _importCoursePack(context),
                  ),
                  if (restorable.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Text(
                      AppStrings.courseManagementRestoreTitle,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: TurnaTheme.textSecondaryColor(context),
                      ),
                    ),
                    const SizedBox(height: 8),
                    for (final language in restorable)
                      RestoreLanguageCard(
                        key: ValueKey('course-restore-${language.code}'),
                        displayName: language.displayName,
                        onRestore: _busy
                            ? () {}
                            : () => _restoreLanguage(context, language.code),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _importCoursePack(BuildContext context) async {
    // True only while the progress dialog is on the root navigator; the
    // error handlers must not pop when the failure preceded the dialog
    // (e.g. "database not ready" — popping then would close this page).
    var progressShown = false;
    try {
      final picked = await ValidatedFilePicker.pickFiles(
        allowedExtensions: const ['turnapack', 'json'],
        dialogTitle: AppStrings.courseManagementImportPackTitle,
      );
      if (picked == null || picked.files.isEmpty) return;
      final path = picked.files.first.path;
      if (path == null) return;
      final db = CourseLoader.databaseOrNull();
      if (db == null) {
        throw CoursePackImportException([AppStrings.coursePackDbNotReady]);
      }
      if (!context.mounted) return;
      final phase = ValueNotifier<CoursePackImportPhase>(
        CoursePackImportPhase.decoding,
      );
      unawaited(showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => ValueListenableBuilder<CoursePackImportPhase>(
          valueListenable: phase,
          builder: (ctx, value, _) => AlertDialog(
            content: Row(
              children: [
                const CircularProgressIndicator(),
                const SizedBox(width: 16),
                Expanded(child: Text(_importPhaseLabel(value))),
              ],
            ),
          ),
        ),
      ));
      progressShown = true;
      final courseProvider = context.read<CourseProvider>();
      final result = await CoursePackImporter(
        db,
        onImportingActiveCode: courseProvider.switchAwayIfActive,
        onPhase: (p) => phase.value = p,
        confirmReplaceExisting: (code, existingName) =>
            _confirmReplace(context, existingName),
      ).importFromFile(path);
      await courseProvider.reloadCourse();
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      TurnaSnackBar.show(
        context,
        AppStrings.courseManagementImportPackSuccess(
          result.displayName,
          result.sectionCount,
          result.wordCount,
        ),
      );
    } on ValidatedFilePickerInvalidExtension {
      if (!context.mounted) return;
      _showPackErrors(context, [AppStrings.coursePackInvalidFileType]);
    } on CoursePackImportException catch (e) {
      if (!context.mounted) return;
      if (progressShown) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      _showPackErrors(context, e.errors);
    } on CoursePackImportCancelled {
      // Quiet exit — the user just declined the replace confirmation, no
      // error dialog on top of it.
      if (!context.mounted) return;
      if (progressShown) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      TurnaSnackBar.show(context, AppStrings.coursePackImportCancelled);
    } catch (e) {
      if (!context.mounted) return;
      if (progressShown) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      _showPackErrors(context, [e.toString()]);
    }
  }

  static String _importPhaseLabel(CoursePackImportPhase phase) =>
      switch (phase) {
        CoursePackImportPhase.decoding =>
          AppStrings.courseManagementImportPackDecoding,
        CoursePackImportPhase.validating =>
          AppStrings.courseManagementImportPackValidating,
        CoursePackImportPhase.writing =>
          AppStrings.courseManagementImportPackWriting,
      };

  /// "Replace the course already installed for this language?"
  /// (pack importer's confirmReplaceExisting callback). Stacks on top of
  /// the progress dialog; same shape as [_confirmDelete].
  Future<bool> _confirmReplace(BuildContext context, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppStrings.coursePackReplaceConfirmTitle),
        content: Text(AppStrings.coursePackReplaceConfirmBody(name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppStrings.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(AppStrings.coursePackReplaceConfirmAction),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  void _showPackErrors(BuildContext context, List<String> errors) {
    final shown = errors.take(5).join('\n');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.courseManagementImportPackFailedTitle),
        content:
            Text('$shown\n\n${AppStrings.courseManagementImportPackLogHint}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppStrings.commonOk),
          ),
        ],
      ),
    );
  }

  Future<void> _onReorder(
    BuildContext context,
    List<CourseCatalogEntry> entries,
    int oldIndex,
    int newIndex,
  ) async {
    final wires = [for (final e in entries) e.wireKey];
    final wire = wires.removeAt(oldIndex);
    wires.insert(newIndex, wire);
    await context.read<CourseProvider>().persistCourseOrder(wires);
  }

  /// Tap a course = make it the active course, then return to the Learn tab.
  Future<void> _selectCourse(
    BuildContext context,
    CourseCatalogEntry entry,
  ) async {
    final courseProvider = context.read<CourseProvider>();
    if (entry.isBuiltin) {
      final languageProvider = context.read<LanguageProvider>();
      final code = (entry.scope as BuiltinCourseScope).languageCode;
      languageProvider.setLanguageCode(code);
      unawaited(languageProvider.cacheLanguage());
    }
    try {
      await courseProvider.setScope(entry.scope);
    } on CourseScopeSwitchException catch (error) {
      // The provider rolled everything back to the previous language; the
      // premature TTS flip above is included in that rollback.
      if (context.mounted) {
        TurnaSnackBar.show(
            context, AppStrings.settingsLanguageSwitchFailed(error.cause));
      }
      return;
    }
    if (context.mounted) {
      await context.router.maybePop();
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    CourseCatalogEntry entry,
  ) async {
    // Exact-source confirmation (ADR 0043): display name, short source
    // id and card count, so deleting one source can never be confused with
    // a sibling sharing the `src-` prefix.
    final bool isBuiltin = entry.isBuiltin;
    final String content;
    final String title;
    final String actionLabel;
    if (isBuiltin) {
      title = AppStrings.courseUninstallConfirmTitle;
      content = AppStrings.courseUninstallConfirmBody(
        entry.displayName,
        entry.cardCount,
      );
      actionLabel = AppStrings.courseUninstallAction;
    } else {
      final idDetail = entry.shortId.isEmpty
          ? ''
          : '\n${entry.shortId} · ${entry.cardCount} cards';
      title = AppStrings.ankiUninstallConfirmTitle;
      content =
          '${entry.displayName}$idDetail\n\n${AppStrings.ankiUninstallConfirmBody}';
      actionLabel = AppStrings.ankiUninstallDeck;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppStrings.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: TurnaTheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    if (_busy) return;
    setState(() => _busy = true);

    final courseProvider = context.read<CourseProvider>();
    var uninstallCompleted = false;
    if (entry.isBuiltin) {
      final code = (entry.scope as BuiltinCourseScope).languageCode;
      try {
        await courseProvider.uninstallBuiltinLanguage(code);
        uninstallCompleted = true;
      } catch (e) {
        logger.w('[CourseManagement] builtin uninstall failed for $code: $e');
      }
    } else {
      // Uninstall with the COMPLETE source identity — never a truncated id.
      final deletionId = entry.officialSourceId!;
      try {
        uninstallCompleted =
            await getIt<AnkiDeckManager>().uninstall(deletionId);
      } catch (e) {
        logger.w('[CourseManagement] uninstall failed for $deletionId: $e');
      }
      if (!context.mounted) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      if (courseProvider.scope == entry.scope) {
        await courseProvider.setScope(
          CourseCatalog.fallbackBuiltin(courseProvider.catalogEntries),
        );
      } else {
        await courseProvider.reloadCourse();
      }
    }
    // Drop the removed course from the persisted order.
    await courseProvider.persistCourseOrder(
      [for (final e in courseProvider.catalogEntries) e.wireKey],
    );
    if (!context.mounted) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    // v2 删除序列里用户可见的移除在账本 COMMIT 即生效；false（locator
    // 未就绪）与抛错（提交前失败）都意味着本次什么都没删掉 → 「未完成，
    // 请重试」此时才与课程列表状态一致。
    TurnaSnackBar.show(
      context,
      uninstallCompleted
          ? AppStrings.ankiDeckRemoved
          : AppStrings.ankiDeckRemovalFailed,
    );
    if (mounted) setState(() => _busy = false);
  }

  /// Restore an uninstalled builtin language (marker cleared + assets
  /// reseeded). Content comes back; learning progress stays deleted.
  Future<void> _restoreLanguage(BuildContext context, String code) async {
    if (_busy) return;
    setState(() => _busy = true);
    final courseProvider = context.read<CourseProvider>();
    var restored = false;
    var message = AppStrings.courseManagementRestoreFailed;
    try {
      await courseProvider.reinstallBuiltinLanguage(code);
      restored = true;
    } on CoursePackMissingException {
      message = AppStrings.courseManagementRestorePackMissing;
    } catch (e) {
      logger.w('[CourseManagement] reinstall failed for $code: $e');
    }
    if (!context.mounted) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    TurnaSnackBar.show(
      context,
      restored
          ? AppStrings.courseManagementRestored(
              ImportedLanguageRegistry.instance.displayNameOrNull(code) ??
                  LanguageRegistry.instance.displayName(code),
            )
          : message,
    );
    if (mounted) setState(() => _busy = false);
  }

  /// Per-course TTS settings (auto-read toggle + translation/native language).
  void _showTtsSettings(BuildContext context, String scope, String name) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: TurnaTheme.cardBg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(TurnaTheme.radiusLarge),
        ),
      ),
      builder: (_) => CourseTtsSettingsSheet(
        scope: scope,
        name: name,
        settings: context.read<SettingsProvider>(),
      ),
    );
  }
}
