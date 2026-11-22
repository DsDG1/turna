import 'package:flutter/material.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_lifecycle_models.dart';
import 'package:turna/application/anki_official/official_anki_catalog_service.dart';
import 'package:turna/application/maintenance/database_doctor_service.dart';
import 'package:turna/application/maintenance/storage_inventory_service.dart';
import 'package:turna/core/log_capture.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/core/turna_icon_id.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/anki/import_wizard/official_pending_import_banner.dart';
import 'package:turna/views/widgets/turna_icon.dart';
import 'package:turna/views/widgets/turna_sheet.dart';

/// Inline error card shown when a repair-center diagnostic probe fails.
class RepairDiagnosticsErrorBanner extends StatelessWidget {
  const RepairDiagnosticsErrorBanner({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: TurnaTheme.dangerSurface(context),
        borderRadius: TurnaTheme.borderRadius,
        border: Border.all(color: TurnaTheme.error.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const TurnaIcon(TurnaIconId.error, color: TurnaTheme.error, size: 18),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              message,
              style: AppTextStyles.captionSm(context)
                  .copyWith(color: TurnaTheme.textPrimaryColor(context)),
            ),
          ),
          TextButton(onPressed: onRetry, child: Text(AppStrings.commonRetry)),
        ],
      ),
    );
  }
}

/// Informational notice rendered when the official catalog database is absent.
class RepairEmptyCatalogCard extends StatelessWidget {
  const RepairEmptyCatalogCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: TurnaTheme.flatPaperDecoration(context),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TurnaIcon(
            TurnaIconId.info,
            size: 20,
            color: TurnaTheme.textSecondaryColor(context),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              AppStrings.ankiRepairCenterEmptyCatalog,
              style: AppTextStyles.captionSm(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// Summary card for CourseDB, Official catalog DB, and orphan storage checks.
class RepairHealthOverviewCard extends StatelessWidget {
  const RepairHealthOverviewCard({
    super.key,
    required this.report,
    required this.doctorError,
    required this.orphans,
    required this.orphansError,
    required this.busy,
    required this.canRepairAll,
    required this.onRetryDoctor,
    required this.onOneClickOptimize,
    required this.onOneClickRepair,
  });

  final DatabaseDoctorReport? report;
  final String? doctorError;
  final List<StorageArtifactReport> orphans;
  final String? orphansError;
  final bool busy;
  final bool canRepairAll;
  final VoidCallback onRetryDoctor;
  final VoidCallback onOneClickOptimize;
  final VoidCallback onOneClickRepair;

  @override
  Widget build(BuildContext context) {
    final hasError = doctorError != null || orphansError != null;
    final isHealthy =
        report != null && report!.isAllHealthy && !hasError && orphans.isEmpty;
    final color = isHealthy
        ? TurnaTheme.achievementEmerald
        : (doctorError != null ? TurnaTheme.error : TurnaTheme.warning);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: TurnaTheme.flatPaperDecoration(context).copyWith(
        color: color.withValues(alpha: 0.05),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: TurnaTheme.borderRadius,
                ),
                child: TurnaIcon(
                  isHealthy ? TurnaIconId.verified : TurnaIconId.warning,
                  color: color,
                  size: 22,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isHealthy
                          ? AppStrings.databaseDoctorHealthy
                          : (report?.courseDb.integrityOk == false ||
                                    doctorError != null
                                ? AppStrings.databaseDoctorError
                                : AppStrings.databaseDoctorWarning),
                      style: AppTextStyles.cardTitle(context)
                          .copyWith(fontWeight: FontWeight.w700),
                    ),
                    if (report != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        isHealthy
                            ? AppStrings.ankiRepairHealthyDetail
                            : AppStrings.ankiRepairIssuesCount(
                                report!.totalIssuesCount,
                              ),
                        style: AppTextStyles.captionSm(context),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (doctorError != null) ...[
            const SizedBox(height: AppSpacing.md),
            RepairDiagnosticsErrorBanner(
              message: doctorError!,
              onRetry: onRetryDoctor,
            ),
          ],
          if (report != null || doctorError == null) ...[
            const SizedBox(height: AppSpacing.lg),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: TurnaTheme.flatPaperDecoration(context),
              child: Column(
                children: [
                  _StatusRow(
                    icon: TurnaIconId.book,
                    title: AppStrings.databaseDoctorCourseDbTitle,
                    status: report?.courseDb.integrityOk == true
                        ? AppStrings.databaseDoctorCourseDbOk
                        : AppStrings.ankiRepairDbAbnormal,
                    statusColor: report?.courseDb.integrityOk == true
                        ? TurnaTheme.achievementEmerald
                        : TurnaTheme.error,
                    detail: report != null
                        ? AppStrings.ankiRepairCourseDbDetail(
                            report!.courseDb.lessonCount,
                            report!.courseDb.wordCount,
                            report!.courseDb.srsCount,
                          )
                        : null,
                  ),
                  const Divider(height: AppSpacing.md),
                  _StatusRow(
                    icon: TurnaIconId.cards,
                    title: AppStrings.databaseDoctorAnkiDbTitle,
                    status: report?.ankiDb.isConfigured == true
                        ? (report!.ankiDb.failedJobsCount > 0
                              ? AppStrings.ankiRepairHasFailedJobs
                              : AppStrings.databaseDoctorAnkiDbOk)
                        : AppStrings.databaseDoctorAnkiDbNotConfigured,
                    statusColor: report?.ankiDb.isConfigured == true
                        ? (report!.ankiDb.failedJobsCount > 0
                              ? TurnaTheme.warning
                              : TurnaTheme.achievementEmerald)
                        : TurnaTheme.textSecondaryColor(context),
                    detail: report?.ankiDb.isConfigured == true
                        ? AppStrings.ankiRepairDeckCount(
                            report!.ankiDb.sourceCount,
                          )
                        : null,
                  ),
                  const Divider(height: AppSpacing.md),
                  _StatusRow(
                    icon: TurnaIconId.folder,
                    title: AppStrings.databaseDoctorStorageTitle,
                    status: orphansError != null
                        ? AppStrings.ankiRepairDbAbnormal
                        : (orphans.isEmpty
                              ? AppStrings.databaseDoctorStorageNoOrphans
                              : AppStrings.ankiRepairOrphanCount(
                                  orphans.length,
                                )),
                    statusColor: orphansError != null
                        ? TurnaTheme.error
                        : (orphans.isEmpty
                              ? TurnaTheme.achievementEmerald
                              : TurnaTheme.warning),
                    detail: orphansError == null && orphans.isNotEmpty
                        ? formatRepairBytes(
                            orphans.fold<int>(
                              0,
                              (sum, a) => sum + a.physicalBytes,
                            ),
                          )
                        : null,
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton.icon(
                key: const Key('repair-doctor-optimize'),
                onPressed: busy ? null : onOneClickOptimize,
                icon: const TurnaIcon(
                  TurnaIconId.speed,
                  size: 18,
                  color: TurnaTheme.textOnPrimary,
                ),
                label: Text(AppStrings.databaseDoctorOneClickOptimize),
              ),
              if (!isHealthy && canRepairAll)
                FilledButton.tonalIcon(
                  key: const Key('repair-doctor-fix-all'),
                  onPressed: busy ? null : onOneClickRepair,
                  icon: const TurnaIcon(TurnaIconId.wrench, size: 18),
                  label: Text(AppStrings.databaseDoctorOneClickRepair),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.icon,
    required this.title,
    required this.status,
    required this.statusColor,
    this.detail,
  });

  final TurnaIconId icon;
  final String title;
  final String status;
  final Color statusColor;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        TurnaIcon(
          icon,
          size: 16,
          color: TurnaTheme.textSecondaryColor(context),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTextStyles.captionSm(context).copyWith(
                  fontWeight: FontWeight.w600,
                  color: TurnaTheme.textPrimaryColor(context),
                ),
              ),
              if (detail != null)
                Text(
                  detail!,
                  style: AppTextStyles.caption(context).copyWith(
                    letterSpacing: 0,
                    color: TurnaTheme.textSecondaryColor(context),
                  ),
                ),
            ],
          ),
        ),
        Text(
          status,
          style: AppTextStyles.captionSm(context)
              .copyWith(fontWeight: FontWeight.w600, color: statusColor),
        ),
      ],
    );
  }
}

/// Section header row with optional trailing bulk action.
class RepairSectionHeader extends StatelessWidget {
  const RepairSectionHeader({super.key, required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, AppSpacing.lg, 0, AppSpacing.sm),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: AppTextStyles.cardTitle(context)),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Structured 4px flat-paper row with trailing action buttons.
class RepairActionTile extends StatelessWidget {
  const RepairActionTile({
    super.key,
    required this.title,
    required this.subtitle,
    this.actions = const [],
  });

  final String title;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.md,
      ),
      decoration: TurnaTheme.flatPaperDecoration(context),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTextStyles.bodyText(context)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: AppTextStyles.captionSm(context)),
              ],
            ),
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(width: AppSpacing.sm),
            Row(mainAxisSize: MainAxisSize.min, children: actions),
          ],
        ],
      ),
    );
  }
}

/// Orphan storage artifacts section (including scan error + retry state).
class RepairOrphansSection extends StatelessWidget {
  const RepairOrphansSection({
    super.key,
    required this.orphans,
    required this.orphansError,
    required this.busy,
    required this.onRetryScan,
    required this.onCleanOrphan,
    required this.onCleanAllOrphans,
  });

  final List<StorageArtifactReport> orphans;
  final String? orphansError;
  final bool busy;
  final VoidCallback onRetryScan;
  final ValueChanged<StorageArtifactReport> onCleanOrphan;
  final VoidCallback onCleanAllOrphans;

  @override
  Widget build(BuildContext context) {
    if (orphansError == null && orphans.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RepairSectionHeader(
          title: AppStrings.ankiRepairOrphans,
          trailing: orphans.length > 1
              ? TextButton.icon(
                  onPressed: busy ? null : onCleanAllOrphans,
                  icon: const TurnaIcon(TurnaIconId.deleteSweep, size: 16),
                  label: Text(AppStrings.databaseDoctorCleanAllOrphans),
                )
              : null,
        ),
        if (orphansError != null)
          RepairDiagnosticsErrorBanner(
            message: orphansError!,
            onRetry: onRetryScan,
          ),
        for (final orphan in orphans)
          RepairActionTile(
            key: Key('repair-orphan-${orphan.ownerId}'),
            title: orphan.label,
            subtitle:
                '${repairCategoryName(orphan.category)} · '
                '${formatRepairBytes(orphan.physicalBytes)}',
            actions: [
              TextButton(
                onPressed: busy ? null : () => onCleanOrphan(orphan),
                child: Text(AppStrings.ankiRepairCleanAction),
              ),
            ],
          ),
      ],
    );
  }
}

/// Interrupted imports section.
class RepairPendingImportsSection extends StatelessWidget {
  const RepairPendingImportsSection({
    super.key,
    required this.pending,
    required this.busy,
    required this.onDiscard,
  });

  final List<OfficialAnkiPendingImport> pending;
  final bool busy;
  final ValueChanged<String> onDiscard;

  @override
  Widget build(BuildContext context) {
    if (pending.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RepairSectionHeader(title: AppStrings.ankiPendingImportsTitle),
        for (final item in pending) ...[
          OfficialInterruptedImportCard(
            key: Key('repair-pending-${item.sourceId}'),
            displayName: item.displayName,
            onDiscard: busy ? null : () => onDiscard(item.sourceId),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      ],
    );
  }
}

/// Sources waiting on cleanup / retirement.
class RepairPendingCleanupSection extends StatelessWidget {
  const RepairPendingCleanupSection({
    super.key,
    required this.sources,
    required this.busy,
    required this.onRetryCleanup,
  });

  final List<OfficialAnkiSourceRow> sources;
  final bool busy;
  final ValueChanged<String> onRetryCleanup;

  @override
  Widget build(BuildContext context) {
    if (sources.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RepairSectionHeader(title: AppStrings.ankiRepairPendingCleanup),
        for (final source in sources)
          RepairActionTile(
            key: Key('repair-cleanup-${source.sourceId}'),
            title: source.displayName,
            subtitle: AppStrings.ankiRepairSourceState(source.state),
            actions: [
              TextButton(
                onPressed: busy ? null : () => onRetryCleanup(source.sourceId),
                child: Text(AppStrings.ankiRepairRetryCleanup),
              ),
            ],
          ),
      ],
    );
  }
}

/// Quarantined sources section.
class RepairQuarantinedSection extends StatelessWidget {
  const RepairQuarantinedSection({
    super.key,
    required this.sources,
    required this.busy,
    required this.onDeleteQuarantine,
  });

  final List<OfficialAnkiSourceRow> sources;
  final bool busy;
  final ValueChanged<String> onDeleteQuarantine;

  @override
  Widget build(BuildContext context) {
    if (sources.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RepairSectionHeader(title: AppStrings.ankiRepairQuarantined),
        for (final source in sources)
          RepairActionTile(
            key: Key('repair-quarantine-${source.sourceId}'),
            title: source.displayName,
            subtitle: AppStrings.ankiRepairSourceState(source.state),
            actions: [
              TextButton(
                onPressed: busy
                    ? null
                    : () => onDeleteQuarantine(source.sourceId),
                child: Text(AppStrings.ankiRepairDeleteQuarantine),
              ),
            ],
          ),
      ],
    );
  }
}

/// Pending maintenance job queue section.
class RepairMaintenanceJobsSection extends StatelessWidget {
  const RepairMaintenanceJobsSection({
    super.key,
    required this.jobs,
    required this.busy,
    required this.onRetryAll,
    required this.onRetryJob,
  });

  final List<Map<String, Object?>> jobs;
  final bool busy;
  final VoidCallback onRetryAll;
  final ValueChanged<String> onRetryJob;

  @override
  Widget build(BuildContext context) {
    if (jobs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RepairSectionHeader(
          title: AppStrings.ankiRepairMaintenanceJobs,
          trailing: TextButton(
            onPressed: busy ? null : onRetryAll,
            child: Text(AppStrings.databaseDoctorRetryAllJobs),
          ),
        ),
        for (final job in jobs)
          RepairActionTile(
            key: Key('repair-job-${job['job_id']}'),
            title: AppStrings.ankiRepairJobKind('${job['kind']}'),
            subtitle: AppStrings.ankiRepairJobState('${job['state']}'),
            actions: [
              TextButton(
                onPressed: busy
                    ? null
                    : () => onRetryJob(job['job_id'] as String),
                child: Text(AppStrings.ankiRepairJobRun),
              ),
            ],
          ),
      ],
    );
  }
}

/// Failed maintenance jobs section.
class RepairFailedJobsSection extends StatelessWidget {
  const RepairFailedJobsSection({
    super.key,
    required this.jobs,
    required this.busy,
    required this.onClearAll,
    required this.onRetryJob,
    required this.onDeleteJob,
  });

  final List<Map<String, Object?>> jobs;
  final bool busy;
  final VoidCallback onClearAll;
  final ValueChanged<String> onRetryJob;
  final ValueChanged<String> onDeleteJob;

  @override
  Widget build(BuildContext context) {
    if (jobs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RepairSectionHeader(
          title: AppStrings.ankiRepairFailedJobs,
          trailing: TextButton(
            onPressed: busy ? null : onClearAll,
            child: Text(AppStrings.databaseDoctorClearFailedJobs),
          ),
        ),
        for (final job in jobs)
          RepairActionTile(
            key: Key('repair-failed-${job['job_id']}'),
            title: AppStrings.ankiRepairJobKind('${job['kind']}'),
            subtitle: AppStrings.ankiRepairJobErrorExplanation(
              job['last_error_code'] as String?,
            ),
            actions: [
              TextButton(
                onPressed: busy
                    ? null
                    : () => onRetryJob(job['job_id'] as String),
                child: Text(AppStrings.commonRetry),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => onDeleteJob(job['job_id'] as String),
                child: Text(AppStrings.ankiRepairJobClear),
              ),
            ],
          ),
      ],
    );
  }
}

/// Advanced diagnostic actions section.
class RepairAdvancedToolsSection extends StatelessWidget {
  const RepairAdvancedToolsSection({
    super.key,
    required this.busy,
    required this.hasCatalog,
    required this.onCheckIntegrity,
    required this.onRebuildIndexes,
    required this.onCheckCollection,
    required this.onExport,
  });

  final bool busy;
  final bool hasCatalog;
  final VoidCallback onCheckIntegrity;
  final VoidCallback onRebuildIndexes;
  final VoidCallback onCheckCollection;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RepairSectionHeader(title: AppStrings.databaseDoctorAdvancedTools),
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            OutlinedButton.icon(
              onPressed: busy ? null : onCheckIntegrity,
              icon: const TurnaIcon(TurnaIconId.checkCircle, size: 16),
              label: Text(AppStrings.databaseDoctorCheckIntegrity),
            ),
            OutlinedButton.icon(
              onPressed: busy ? null : onRebuildIndexes,
              icon: const TurnaIcon(TurnaIconId.swapArrows, size: 16),
              label: Text(AppStrings.databaseDoctorRebuildIndexes),
            ),
            if (hasCatalog)
              OutlinedButton.icon(
                onPressed: busy ? null : onCheckCollection,
                icon: const TurnaIcon(TurnaIconId.heartPulse, size: 16),
                label: Text(AppStrings.databaseDoctorCheckCollection),
              ),
            OutlinedButton.icon(
              key: const Key('repair-export'),
              onPressed: busy ? null : onExport,
              icon: const TurnaIcon(TurnaIconId.share, size: 16),
              label: Text(AppStrings.ankiRepairExportDiagnostics),
            ),
          ],
        ),
      ],
    );
  }
}

/// Localized display name for a storage artifact category.
String repairCategoryName(StorageArtifactCategory category) {
  switch (category) {
    case StorageArtifactCategory.mainDatabase:
      return AppStrings.ankiRepairCategoryMainDb;
    case StorageArtifactCategory.legacyAnki:
      return AppStrings.ankiRepairCategoryLegacyAnki;
    case StorageArtifactCategory.legacyAnkiMedia:
      return AppStrings.ankiRepairCategoryLegacyMedia;
    case StorageArtifactCategory.officialAnki:
      return AppStrings.ankiRepairCategoryOfficialAnki;
    case StorageArtifactCategory.regenerableCache:
      return AppStrings.ankiRepairCategoryRegenerable;
    case StorageArtifactCategory.logs:
      return AppStrings.ankiRepairCategoryLogs;
  }
}

/// Human-readable byte count formatting.
String formatRepairBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}

/// Confirmation dialog shared by destructive repair actions.
Future<bool> confirmRepairAction(
  BuildContext context, {
  required String title,
  required String body,
}) async {
  final confirmed = await showTurnaConfirmDialog(
    context: context,
    title: title,
    message: body,
    confirmLabel: AppStrings.commonOk,
  );
  return confirmed == true;
}

/// Integrity check results modal dialog.
Future<void> showRepairIntegrityDialog(
  BuildContext context, {
  required String courseResult,
  required String ankiResult,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => TurnaDialogPanel(
      title: AppStrings.ankiRepairIntegrityTitle,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.ankiRepairCourseDbResult(courseResult),
            style: AppTextStyles.bodyText(ctx)
                .copyWith(color: TurnaTheme.textSecondaryColor(ctx)),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            AppStrings.ankiRepairAnkiDbResult(ankiResult),
            style: AppTextStyles.bodyText(ctx)
                .copyWith(color: TurnaTheme.textSecondaryColor(ctx)),
          ),
        ],
      ),
      actions: [
        TurnaSheetAction(
          label: AppStrings.commonGotIt,
          primary: true,
          onPressed: () => Navigator.of(ctx).pop(),
        ),
      ],
    ),
  );
}

/// Appends recent redacted log entries to exported repair diagnostics.
String appendRepairRecentLogs(String payload, {int limit = 120}) {
  try {
    final entries = LogCapture.instance.entries.value;
    if (entries.isEmpty) return payload;
    final buffer = StringBuffer(payload)
      ..write(
        '\n--- recent file log (${entries.length} kept, '
        'showing up to $limit, newest first) ---\n',
      );
    var shown = 0;
    for (final entry in entries) {
      if (shown >= limit) break;
      buffer.writeln(
        '${entry.timestamp.toIso8601String()} '
        '[${entry.level.name}] ${entry.displayMessage}',
      );
      shown++;
    }
    return buffer.toString();
  } catch (e, st) {
    logger.w(
      'RepairCenter: append recent logs failed',
      error: e,
      stackTrace: st,
    );
    return payload;
  }
}
