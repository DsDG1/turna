// Dart imports:
import 'dart:async';
import 'dart:io';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/backup/backup_schema.dart';
import 'package:turna/application/game_provider.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/settings/commands/reset_account_command.dart';
import 'package:turna/application/settings/settings_destination.dart';
import 'package:turna/application/migration/turna_migration_import.dart';
import 'package:turna/application/settings/settings_operation_result.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/service/export_service.dart';
import 'package:turna/utils/validated_file_picker.dart';
import 'package:turna/views/settings/pages/settings_category_body.dart';
import 'package:turna/views/settings/widgets/settings_common.dart';
import 'package:turna/views/theme.dart';

/// Data & backup category page (formal route: `/settings/data-backup`).
///
/// Owns the local export / import flow. Import reports only what actually
/// happened: a validated+committed progress restore, an honest "legacy
/// course payload ignored" note for old v1 files, structured error codes
/// for rejections — never a blanket success for skipped work.
@RoutePage()
class DataBackupSettingsPage extends StatelessWidget {
  const DataBackupSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: SettingsDestination.dataAndBackup.title,
      body: SettingsCategoryBody(
        pageStorageKey: 'settings-data-backup',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
                  subtitle: AppStrings.settingsRemoteBackupSubtitle,
                  onTap: (context) =>
                      context.router.push(const RemoteBackupRoute()),
                ),
                settingsTileDivider(context),
                // Independent migration-package entry (plan 34 §R7-3): a
                // turna-migration-v1 zip from another platform (OHOS EOL
                // export) — deliberately separate from the JSON backup
                // import above. Legacy Anki rows land as pending
                // migration and never activate the old scheduler.
                SettingsActionTile(
                  icon: Icons.move_down_rounded,
                  title: '导入 Turna 迁移包',
                  subtitle: 'turna-migration-v1.zip（跨设备迁移）',
                  onTap: (context) => _importMigrationPackage(context),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SettingsSectionTitle(
              icon: Icons.history_rounded,
              title: AppStrings.settingsLearningRecordsTitle,
            ),
            const SizedBox(height: 8),
            SettingsCard(
              children: [
                SettingsActionTile(
                  icon: Icons.delete_sweep_rounded,
                  title: AppStrings.settingsClearMistakeLogTitle,
                  subtitle: AppStrings.settingsClearMistakeLogSubtitle,
                  iconColor: TurnaTheme.anatolianClay,
                  iconBackground:
                      TurnaTheme.anatolianClay.withValues(alpha: 0.10),
                  onTap: (context) => _confirmClearMistakes(context),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SettingsSectionTitle(
              icon: Icons.warning_amber_rounded,
              title: AppStrings.settingsDangerZoneTitle,
            ),
            const SizedBox(height: 8),
            SettingsCard(
              children: [
                SettingsActionTile(
                  icon: Icons.restart_alt_rounded,
                  title: AppStrings.settingsResetProgressTitle,
                  subtitle: AppStrings.settingsResetProgressSubtitle,
                  iconColor: TurnaTheme.error,
                  iconBackground: TurnaTheme.error.withValues(alpha: 0.09),
                  onTap: (context) => _confirmResetProgress(context),
                ),
                settingsTileDivider(context),
                SettingsActionTile(
                  icon: Icons.delete_forever_rounded,
                  title: AppStrings.accountResetTitle,
                  subtitle: AppStrings.accountResetSubtitle,
                  iconColor: TurnaTheme.error,
                  iconBackground: TurnaTheme.error.withValues(alpha: 0.09),
                  onTap: (context) => _confirmResetAccount(context),
                ),
              ],
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
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

  Future<void> _confirmResetAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => SettingsConfirmDialog(
        title: AppStrings.accountResetDialogTitle,
        message: AppStrings.accountResetDialogMessage,
        confirmText: AppStrings.accountResetConfirm,
      ),
    );
    if (confirmed != true || !context.mounted) return;

    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: const Center(child: CircularProgressIndicator()),
      ),
    ));

    final result = await getIt<ResetAccountCommand>().execute();
    if (!context.mounted) return;
    Navigator.of(context, rootNavigator: true).pop();
    switch (result) {
      case SettingsOperationSuccess():
        _showSnack(context, AppStrings.accountResetDone);
      case SettingsOperationFailure(:final userMessage):
        _showSnack(context, userMessage);
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

  /// turna-migration-v1 import (plan 34 §R7-3). Validation is fail-closed;
  /// the dialog reports exact outcomes, including ignored legacy imports.
  Future<void> _importMigrationPackage(BuildContext context) async {
    String? pickedPath;
    try {
      pickedPath = (await ValidatedFilePicker.pickFiles(
        allowedExtensions: const ['zip'],
      ))
          ?.files
          .single
          .path;
    } on ValidatedFilePickerInvalidExtension {
      if (context.mounted) {
        _showSnack(context, '仅支持导入 .zip 格式的迁移包。');
      }
      return;
    }
    if (pickedPath == null || !context.mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => SettingsConfirmDialog(
        title: '导入 Turna 迁移包',
        message: '将迁移包中的学习进度恢复到本机。旧版 Anki 牌组数据'
            '不再迁移（v1 链路已退役），学习记录与复习历史会照常恢复。',
        confirmText: '开始导入',
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      final importer = TurnaMigrationImporter(db: getIt<CourseDatabase>());
      final result = await importer.importFrom(File(pickedPath));
      if (!context.mounted) return;
      if (result.applied) {
        final ignored = result.legacyIgnoredImports.isEmpty
            ? ''
            : '\n已忽略旧版 Anki 牌组：${result.legacyIgnoredImports.length} 个'
                '（不再迁移）';
        _showSnack(
          context,
          '迁移完成：学习记录 ${result.restoredSrsStates} 条、复习历史 '
          '${result.restoredReviewEvents} 条$ignored',
        );
      } else {
        _showSnack(context, '迁移包被拒绝：${_rejectionText(result.rejection)}');
      }
    } catch (e) {
      if (context.mounted) {
        _showSnack(context, '迁移导入失败：$e');
      }
    }
  }

  String _rejectionText(TurnaMigrationImportRejection? rejection) {
    return switch (rejection) {
      TurnaMigrationImportRejection.notAZip => '文件不是有效的 zip 包',
      TurnaMigrationImportRejection.zipSlipEntry => '包内包含非法路径',
      TurnaMigrationImportRejection.missingManifest => '缺少清单文件',
      TurnaMigrationImportRejection.unknownFormat => '不是 Turna 迁移包',
      TurnaMigrationImportRejection.schemaTooNew => '迁移包来自更新的应用版本',
      TurnaMigrationImportRejection.missingSha256Sums => '缺少校验清单',
      TurnaMigrationImportRejection.checksumMismatch => '校验失败，文件可能损坏',
      TurnaMigrationImportRejection.missingRequiredEntry => '迁移包缺少必要文件',
      TurnaMigrationImportRejection.insufficientSpace => '存储空间不足',
      TurnaMigrationImportRejection.applyFailed => '数据应用失败，已回滚',
      null => '未知原因',
    };
  }

  Future<void> _importData(BuildContext context) async {    String? pickedPath;
    try {
      pickedPath = (await ValidatedFilePicker.pickFiles(
        allowedExtensions: const ['json'],
      ))
          ?.files
          .single
          .path;
    } on ValidatedFilePickerInvalidExtension {
      // Non-JSON selection is a user error worth explaining, not a silent
      // return that looks like the import did nothing.
      if (context.mounted) {
        _showSnack(context, '仅支持导入 .json 格式的备份文件。');
      }
      return;
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
      final outcome = await getIt<ExportService>().importFromFile(pickedPath);
      if (!context.mounted) return;
      if (outcome.progressRestored) {
        // Runtime providers were already refreshed through the
        // PostRestoreReloadRegistry; surface any step that still failed.
        if (outcome.reload.failures.isNotEmpty) {
          _showSnack(
            context,
            '${AppStrings.settingsProgressRestored}（部分运行时状态需重启后完全生效）',
          );
        } else {
          _showSnack(context, AppStrings.settingsProgressRestored);
        }
      } else if (outcome.legacyCoursePayloadIgnored) {
        _showSnack(
          context,
          '导入完成：该备份只包含内置课程内容副本，不含个人数据，无需恢复。',
        );
      } else {
        _showSnack(context, AppStrings.settingsNothingToImport);
      }
    } on BackupSchemaException catch (error) {
      if (context.mounted) {
        _showSnack(context, error.userMessage);
      }
    } on Object catch (error) {
      if (context.mounted) {
        _showSnack(context, AppStrings.settingsImportFailed(error));
      }
    }
  }
}

/// Export bottom sheet. The legacy "include course content" option is gone —
/// it only ever exported copies of bundled course assets (no user data) and
/// the import path could never honestly apply them. The sheet is wrapped in
/// SafeArea + SingleChildScrollView so it remains usable at 200% text scale
/// and in landscape with the keyboard open.
class _ExportSheet extends StatefulWidget {
  const _ExportSheet();

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  bool _exporting = false;

  Future<void> _export() async {
    setState(() => _exporting = true);
    try {
      final service = getIt<ExportService>();
      final file = await service.export();
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
    return SafeArea(
      child: SingleChildScrollView(
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
                Expanded(
                  child: Text(
                    AppStrings.settingsExportSheetTitle,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
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
            const SizedBox(height: 12),
            Text(
              '包含：学习进度、复习与错题记录、成就与装扮、学习偏好设置。'
              '不包含：服务器密码与 AI API key。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: TurnaTheme.textHintColor(context),
                  ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _exporting ? null : _export,
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
      ),
    );
  }
}
