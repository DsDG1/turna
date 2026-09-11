// Dart imports:
import 'dart:async';
import 'dart:math' as math;

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
import 'package:turna/courses/course_loader.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/course_scope.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/utils/validated_file_picker.dart';
import 'package:turna/views/anki/import_wizard/official_pending_import_banner.dart';
import 'package:turna/views/theme.dart';

/// Course management page — opened from the course switcher in the Learn
/// tab. Lists the built-in course plus every Anki course (one entry per
/// source), lets the user switch the active course (tap), reorder courses
/// (drag), delete imported courses with an exact-source confirmation (the
/// built-in course can never be deleted), and reach the add-course entry
/// points.
///
/// [highlightWire] briefly highlights one catalog entry (v1 scope wire key)
/// — used by the import wizard's "view decks" action (plan 34 R1-4).
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
      body: _CourseManagementBody(highlightWire: highlightWire),
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
            onReorderItem: (oldIndex, newIndex) =>
                _onReorder(context, entries, oldIndex, newIndex),
            children: [
              for (var i = 0; i < entries.length; i++)
                _CourseCard(
                  key: ValueKey(entries[i].wireKey),
                  entry: entries[i],
                  index: i,
                  isActive: entries[i].wireKey == activeScope,
                  isHighlighted: entries[i].wireKey == _highlightWire,
                  ttsFeatureEnabled: ttsFeatureEnabled,
                  onTap: () => _selectCourse(context, entries[i]),
                  onSettings: () => _showTtsSettings(
                    context,
                    entries[i].wireKey,
                    entries[i].displayName,
                  ),
                  onDelete: entries[i].isBuiltin &&
                          entries.where((e) => e.isBuiltin).length < 2
                      ? null
                      : () => _confirmDelete(context, entries[i]),
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
                  _AddCourseCard(
                    onTap: () => context.router.push(const AnkiImportRoute()),
                  ),
                  const SizedBox(height: 8),
                  _AddCourseCard(
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
                      _RestoreLanguageCard(
                        key: ValueKey('course-restore-${language.code}'),
                        displayName: language.displayName,
                        onRestore: () =>
                            _restoreLanguage(context, language.code),
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
        throw const CoursePackImportException(['课程数据库尚未就绪']);
      }
      if (!context.mounted) return;
      final phase = ValueNotifier<CoursePackImportPhase>(
        CoursePackImportPhase.decoding,
      );
      showDialog<void>(
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
      );
      progressShown = true;
      final courseProvider = context.read<CourseProvider>();
      final result = await CoursePackImporter(
        db,
        onImportingActiveCode: courseProvider.switchAwayIfActive,
        onPhase: (p) => phase.value = p,
      ).importFromFile(path);
      await courseProvider.reloadCourse();
      if (!context.mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.courseManagementImportPackSuccess(
              result.displayName,
              result.sectionCount,
              result.wordCount,
            ),
          ),
        ),
      );
    } on ValidatedFilePickerInvalidExtension {
      if (!context.mounted) return;
      _showPackErrors(context, ['文件类型不受支持']);
    } on CoursePackImportException catch (e) {
      if (!context.mounted) return;
      if (progressShown) {
        Navigator.of(context, rootNavigator: true).maybePop();
      }
      _showPackErrors(context, e.errors);
    } catch (e) {
      if (!context.mounted) return;
      if (progressShown) {
        Navigator.of(context, rootNavigator: true).maybePop();
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

  void _showPackErrors(BuildContext context, List<String> errors) {
    final shown = errors.take(5).join('\n');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.courseManagementImportPackFailedTitle),
        content: Text('$shown\n\n${AppStrings.courseManagementImportPackLogHint}'),
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
    await courseProvider.setScope(entry.scope);
    if (context.mounted) {
      await context.router.maybePop();
    }
  }

  Future<void> _confirmDelete(
    BuildContext context,
    CourseCatalogEntry entry,
  ) async {
    // Exact-source confirmation (plan 34 R1-7): display name, short source
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

    final courseProvider = context.read<CourseProvider>();
    var uninstallCompleted = false;
    if (entry.isBuiltin) {
      final code = (entry.scope as BuiltinCourseScope).languageCode;
      try {
        await courseProvider.uninstallBuiltinLanguage(code);
        uninstallCompleted = true;
      } catch (e) {
        debugPrint('[CourseManagement] builtin uninstall failed for $code: $e');
      }
    } else {
      // Uninstall with the COMPLETE source identity — never a truncated id.
      final deletionId = entry.officialSourceId ?? entry.legacyImportId!;
      try {
        uninstallCompleted = await getIt<AnkiDeckManager>().uninstall(deletionId);
      } catch (e) {
        debugPrint('[CourseManagement] uninstall failed for $deletionId: $e');
      }
      if (!context.mounted) return;
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
    if (!context.mounted) return;
    // v2 删除序列里用户可见的移除在账本 COMMIT 即生效；false（locator
    // 未就绪）与抛错（提交前失败）都意味着本次什么都没删掉 → 「未完成，
    // 请重试」此时才与课程列表状态一致。
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          uninstallCompleted
              ? AppStrings.ankiDeckRemoved
              : AppStrings.ankiDeckRemovalFailed,
        ),
      ),
    );
  }

  /// Restore an uninstalled builtin language (marker cleared + assets
  /// reseeded). Content comes back; learning progress stays deleted.
  Future<void> _restoreLanguage(BuildContext context, String code) async {
    final courseProvider = context.read<CourseProvider>();
    var restored = false;
    var message = AppStrings.courseManagementRestoreFailed;
    try {
      await courseProvider.reinstallBuiltinLanguage(code);
      restored = true;
    } on CoursePackMissingException {
      message = AppStrings.courseManagementRestorePackMissing;
    } catch (e) {
      debugPrint('[CourseManagement] reinstall failed for $code: $e');
    }
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          restored
              ? AppStrings.courseManagementRestored(
                  ImportedLanguageRegistry.instance.displayNameOrNull(code) ??
                      LanguageRegistry.instance.displayName(code),
                )
              : message,
        ),
      ),
    );
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
      builder: (_) => _CourseTtsSettingsSheet(
        scope: scope,
        name: name,
        settings: context.read<SettingsProvider>(),
      ),
    );
  }
}

class _CourseCard extends StatelessWidget {
  final CourseCatalogEntry entry;
  final int index;
  final bool isActive;
  final bool isHighlighted;
  final bool ttsFeatureEnabled;
  final VoidCallback onTap;
  final VoidCallback onSettings;
  final VoidCallback? onDelete;

  const _CourseCard({
    super.key,
    required this.entry,
    required this.index,
    required this.isActive,
    this.isHighlighted = false,
    required this.ttsFeatureEnabled,
    required this.onTap,
    required this.onSettings,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final accent = isActive
        ? TurnaTheme.brandTeal
        : TurnaTheme.textSecondaryColor(context);
    final hasMenuActions = ttsFeatureEnabled || onDelete != null;
    final radius = BorderRadius.circular(TurnaTheme.radiusLarge);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: TurnaTheme.cardBg(context),
        borderRadius: radius,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(
                color: isActive || isHighlighted
                    ? TurnaTheme.brandTeal
                    : TurnaTheme.brandTeal.withValues(alpha: 0.12),
                width: isActive || isHighlighted ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: isActive
                        ? const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [TurnaTheme.brandTeal, TurnaTheme.brandSky],
                          )
                        : null,
                    color: isActive
                        ? null
                        : accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    entry.isBuiltin
                        ? Icons.language_rounded
                        : Icons.style_rounded,
                    color: isActive ? Colors.white : accent,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              entry.displayName,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (isActive) ...[
                            const SizedBox(width: 8),
                            _Badge(
                              label: AppStrings.courseManagementCurrentBadge,
                              color: TurnaTheme.brandTeal,
                            ),
                          ],
                          if (entry.isBuiltin) ...[
                            const SizedBox(width: 8),
                            _Badge(
                              label: AppStrings.courseManagementDefaultBadge,
                              color: TurnaTheme.textSecondaryColor(context),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entry.isBuiltin
                            ? AppStrings.courseManagementBuiltinSubtitle
                            : AppStrings.courseManagementCardCount(
                                entry.cardCount,
                              ),
                        style: TextStyle(
                          fontSize: 13,
                          color: TurnaTheme.textSecondaryColor(context),
                        ),
                      ),
                      if (entry.scope is BuiltinCourseScope) ...[
                        Builder(
                          builder: (context) {
                            final code =
                                (entry.scope as BuiltinCourseScope).languageCode;
                            final attribution = ImportedLanguageRegistry
                                .instance
                                .licenseAttributionOrNull(code);
                            if (attribution == null) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                attribution,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: TurnaTheme.textSecondaryColor(context),
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ],
                  ),
                ),
                if (isActive)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.check_circle_rounded,
                      color: TurnaTheme.brandTeal,
                      size: 22,
                    ),
                  ),
                // Card actions collapse into one overflow menu: TTS settings
                // (gated by the opt-in master switch) + remove. The built-in
                // course with read-aloud off renders no menu at all.
                if (hasMenuActions)
                  PopupMenuButton<String>(
                    tooltip: AppStrings.commonMoreActions,
                    icon: Icon(
                      Icons.more_vert_rounded,
                      color: TurnaTheme.textSecondaryColor(context),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    onSelected: (value) {
                      if (value == 'tts') {
                        onSettings();
                      } else if (value == 'delete') {
                        onDelete?.call();
                      }
                    },
                    itemBuilder: (_) => [
                      if (ttsFeatureEnabled)
                        PopupMenuItem(
                          value: 'tts',
                          child: Row(
                            children: [
                              const Icon(
                                Icons.record_voice_over_rounded,
                                size: 20,
                                color: TurnaTheme.brandTeal,
                              ),
                              const SizedBox(width: 10),
                              Text(AppStrings.courseTtsSettingsTitle),
                            ],
                          ),
                        ),
                      if (onDelete != null)
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              const Icon(
                                Icons.delete_outline_rounded,
                                size: 20,
                                color: TurnaTheme.error,
                              ),
                              const SizedBox(width: 10),
                              Text(AppStrings.courseManagementRemoveCourse),
                            ],
                          ),
                        ),
                    ],
                  ),
                ReorderableDragStartListener(
                  index: index,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 10,
                    ),
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      color: TurnaTheme.textHintColor(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;

  const _Badge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

/// Hero entry card for adding a course — dashed teal outline so it reads as
/// "create/import here" instead of another course in the list.
class _AddCourseCard extends StatelessWidget {
  final VoidCallback onTap;
  final String? title;
  final String? subtitle;

  const _AddCourseCard({
    super.key,
    required this.onTap,
    this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(TurnaTheme.radiusLarge);
    return Material(
      color: Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: CustomPaint(
          foregroundPainter: _DashedBorderPainter(
            color: TurnaTheme.brandTeal.withValues(alpha: 0.45),
            radius: TurnaTheme.radiusLarge,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.add_circle_outline_rounded,
                  size: 28,
                  color: TurnaTheme.brandTeal,
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title ?? AppStrings.courseManagementImportTitle,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: TurnaTheme.brandTeal,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle ?? AppStrings.homeFromAnkiSubtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: TurnaTheme.textSecondaryColor(context),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One row per uninstalled builtin language in the restore list.
class _RestoreLanguageCard extends StatelessWidget {
  final String displayName;
  final VoidCallback onRestore;

  const _RestoreLanguageCard({
    super.key,
    required this.displayName,
    required this.onRestore,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(TurnaTheme.radiusLarge);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: TurnaTheme.cardBg(context),
        borderRadius: radius,
        child: InkWell(
          onTap: onRestore,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: TurnaTheme.brandTeal.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.language_rounded,
                    size: 20,
                    color: TurnaTheme.brandTeal,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    displayName,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton.icon(
                  onPressed: onRestore,
                  icon: const Icon(
                    Icons.restore_rounded,
                    size: 18,
                    color: TurnaTheme.brandTeal,
                  ),
                  label: Text(AppStrings.courseManagementRestore(displayName)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Dashed rounded-rect border, drawn once per paint pass — no packages.
class _DashedBorderPainter extends CustomPainter {
  static const double _dashWidth = 6;
  static const double _dashGap = 5;
  static const double _strokeWidth = 1.6;

  final Color color;
  final double radius;

  const _DashedBorderPainter({required this.color, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(radius),
        ),
      );
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = _strokeWidth;
    final metric = path.computeMetrics().first;
    var distance = 0.0;
    while (distance < metric.length) {
      final next = math.min(distance + _dashWidth, metric.length);
      canvas.drawPath(metric.extractPath(distance, next), paint);
      distance = next + _dashGap;
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter oldDelegate) =>
      color != oldDelegate.color || radius != oldDelegate.radius;
}

/// Bottom sheet for a single course's smart-TTS settings: the auto-read
/// toggle and the translation/native language used as the Latin-text fallback.
class _CourseTtsSettingsSheet extends StatefulWidget {
  final String scope;
  final String name;
  final SettingsProvider settings;

  const _CourseTtsSettingsSheet({
    required this.scope,
    required this.name,
    required this.settings,
  });

  @override
  State<_CourseTtsSettingsSheet> createState() =>
      _CourseTtsSettingsSheetState();
}

class _CourseTtsSettingsSheetState extends State<_CourseTtsSettingsSheet> {
  static const _nativeLangOptions = <({String code, String label})>[
    (code: 'en', label: '英语'),
    (code: 'zh', label: '中文'),
    (code: 'tr', label: '土耳其语'),
    (code: 'ru', label: '俄语'),
    (code: 'ar', label: '阿拉伯语'),
    (code: 'es', label: '西班牙语'),
    (code: 'fr', label: '法语'),
    (code: 'de', label: '德语'),
    (code: 'ja', label: '日语'),
    (code: 'ko', label: '韩语'),
    (code: 'pt', label: '葡萄牙语'),
    (code: 'it', label: '意大利语'),
    (code: 'vi', label: '越南语'),
    (code: 'id', label: '印尼语'),
  ];

  late bool _autoRead;
  late String _nativeLang;

  @override
  void initState() {
    super.initState();
    _autoRead = widget.settings.autoReadOnTapFor(widget.scope);
    _nativeLang = widget.settings.nativeLanguageCodeFor(widget.scope);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '${AppStrings.courseTtsSettingsTitle} · ${widget.name}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 16),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(AppStrings.courseTtsAutoReadTitle),
              subtitle: Text(
                AppStrings.courseTtsAutoReadSubtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: TurnaTheme.textSecondaryColor(context),
                ),
              ),
              value: _autoRead,
              onChanged: (value) async {
                setState(() => _autoRead = value);
                await widget.settings.setAutoReadOnTapFor(widget.scope, value);
              },
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.courseTtsNativeLangTitle,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            Text(
              AppStrings.courseTtsNativeLangSubtitle,
              style: TextStyle(
                fontSize: 12,
                color: TurnaTheme.textSecondaryColor(context),
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _nativeLang,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final opt in _nativeLangOptions)
                  DropdownMenuItem(
                    value: opt.code,
                    child: Text(opt.label),
                  ),
              ],
              onChanged: (value) async {
                if (value == null) return;
                setState(() => _nativeLang = value);
                await widget.settings
                    .setNativeLanguageCodeFor(widget.scope, value);
              },
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(AppStrings.dialogClose),
            ),
          ],
        ),
      ),
    );
  }
}
