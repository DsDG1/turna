import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:turna/application/anki_official/anki_deck_manager.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_lifecycle_models.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_storage_audit.dart';
import 'package:turna/application/anki_official/official_anki_catalog_service.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_retire_service.dart';
import 'package:turna/application/maintenance/database_doctor_service.dart';
import 'package:turna/application/maintenance/storage_inventory_service.dart';
import 'package:turna/core/log_capture.dart';

import 'package:turna/core/logger.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/utils/share_origin.dart';
import 'package:turna/views/anki/import_wizard/official_pending_import_banner.dart';
import 'package:turna/views/settings/widgets/settings_common.dart';
import 'package:turna/views/widgets/turna_snack_bar.dart';
import 'package:turna/core/theme.dart';

/// Database Health & Repair Center:
/// Handles both core CourseDatabase health and Anki official collection repair,
/// pending cleanups, quarantined sources, maintenance job queues, and orphan files.
@RoutePage()
class OfficialAnkiRepairCenterPage extends StatefulWidget {
  const OfficialAnkiRepairCenterPage({
    super.key,
    this.catalog,
    this.paths,
    this.scanner,
    this.engine,
    this.doctor,
    this.onContinueImport,
    this.onDiscardImport,
    this.onRetryCleanup,
    this.onDeleteQuarantine,
    this.onExportDiagnostics,
  });

  final OfficialAnkiDatabase? catalog;
  final OfficialAnkiPaths? paths;
  final StorageInventoryService? scanner;
  final OfficialAnkiEngine? engine;
  final DatabaseDoctorService? doctor;
  final Future<void> Function(String sourceId)? onContinueImport;
  final Future<void> Function(String sourceId)? onDiscardImport;
  final Future<void> Function(String sourceId)? onRetryCleanup;
  final Future<void> Function(String sourceId)? onDeleteQuarantine;
  final Future<void> Function(String payload)? onExportDiagnostics;

  @override
  State<OfficialAnkiRepairCenterPage> createState() =>
      _OfficialAnkiRepairCenterPageState();
}

class _OfficialAnkiRepairCenterPageState
    extends State<OfficialAnkiRepairCenterPage> {
  bool _busy = false;
  Future<StorageInventoryReport?>? _orphanScan;

  DatabaseDoctorReport? _doctorReport;
  bool _inspecting = false;

  List<OfficialAnkiPendingImport> _pending = const [];
  List<OfficialAnkiSourceRow> _sources = const [];
  List<Map<String, Object?>> _jobs = const [];
  List<Map<String, Object?>> _failedJobs = const [];

  DatabaseDoctorService get _doctor =>
      widget.doctor ?? const DatabaseDoctorService();

  OfficialAnkiDatabase? get _catalog =>
      widget.catalog ?? OfficialAnkiCompositionRoot.readOnlyCatalog;

  OfficialAnkiPaths? get _paths =>
      widget.paths ?? OfficialAnkiCompositionRoot.locatorPaths;

  OfficialAnkiEngine? get _engine =>
      widget.engine ?? OfficialAnkiCompositionRoot.engine;

  @override
  void initState() {
    super.initState();
    _orphanScan = _loadOrphans();
    _reloadCatalogSnapshot();
    _loadDoctorReport();
  }

  void _reloadCatalogSnapshot() {
    final snapshot = const OfficialAnkiCatalogService().repairSnapshot(
      catalog: _catalog,
      profileId: _paths?.profileId,
    );
    _pending = snapshot.pendingImports;
    _sources = snapshot.sources;
    _jobs = snapshot.pendingJobs;
    _failedJobs = snapshot.failedJobs;
  }

  Future<void> _loadDoctorReport() async {
    setState(() => _inspecting = true);
    try {
      final report = await _doctor.inspectHealth(
        catalog: _catalog,
        paths: _paths,
        scanner: widget.scanner,
      );
      if (mounted) {
        setState(() {
          _doctorReport = report;
          _inspecting = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _inspecting = false);
    }
  }

  void _reloadAndSetState() {
    setState(() {
      _reloadCatalogSnapshot();
      _orphanScan = _loadOrphans();
    });
    _loadDoctorReport();
  }

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: AppStrings.databaseDoctorTitle,
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final catalog = _catalog;
    if (catalog == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: TurnaTheme.surfaceColor(context),
              borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
              border: Border.all(color: TurnaTheme.dividerBg(context)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.info_outline_rounded,
                    color: TurnaTheme.textSecondaryColor(context)),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppStrings.ankiRepairCenterEmptyCatalog,
                    style: TextStyle(
                      color: TurnaTheme.textSecondaryColor(context),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildHealthOverviewCard(context, orphans: const []),
          const SizedBox(height: 16),
          _buildAdvancedTools(context),
        ],
      );
    }

    final pending = _pending;
    final pendingCleanup = _sources
        .where((s) => s.state == 'pending_cleanup' || s.state == 'retiring')
        .toList();
    final quarantined =
        _sources.where((s) => s.state == 'quarantined').toList();
    final jobs = _jobs;
    final failed = _failedJobs;

    return FutureBuilder<StorageInventoryReport?>(
      future: _orphanScan,
      builder: (context, snap) {
        final orphans = snap.data?.orphans ?? const <StorageArtifactReport>[];
        final empty = pending.isEmpty &&
            pendingCleanup.isEmpty &&
            quarantined.isEmpty &&
            jobs.isEmpty &&
            failed.isEmpty &&
            orphans.isEmpty;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (_busy || _inspecting) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            _buildHealthOverviewCard(context, orphans: orphans),
            const SizedBox(height: 16),
            if (empty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    AppStrings.ankiRepairCenterEmpty,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: TurnaTheme.textSecondaryColor(context),
                    ),
                  ),
                ),
              ),
            if (orphans.isNotEmpty) ...[
              _buildSectionHeader(
                title: AppStrings.ankiRepairOrphans,
                trailing: orphans.length > 1
                    ? TextButton.icon(
                        onPressed:
                            _busy ? null : () => _cleanAllOrphans(orphans),
                        icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                        label: Text(AppStrings.databaseDoctorCleanAllOrphans),
                      )
                    : null,
              ),
              for (final orphan in orphans)
                _tile(
                  key: Key('repair-orphan-${orphan.ownerId}'),
                  title: orphan.label,
                  subtitle:
                      '${_categoryName(orphan.category)} · ${_formatBytes(orphan.physicalBytes)}',
                  actions: [
                    TextButton(
                      onPressed: _busy ? null : () => _cleanOrphan(orphan),
                      child: Text(AppStrings.ankiRepairCleanAction),
                    ),
                  ],
                ),
            ],
            if (pending.isNotEmpty) ...[
              _buildSectionHeader(title: AppStrings.ankiPendingImportsTitle),
              for (final item in pending) ...[
                OfficialInterruptedImportCard(
                  key: Key('repair-pending-${item.sourceId}'),
                  displayName: item.displayName,
                  onDiscard: _busy ? null : () => _discardImport(item.sourceId),
                ),
                const SizedBox(height: 12),
              ],
            ],
            if (pendingCleanup.isNotEmpty) ...[
              _buildSectionHeader(title: AppStrings.ankiRepairPendingCleanup),
              for (final source in pendingCleanup)
                _tile(
                  key: Key('repair-cleanup-${source.sourceId}'),
                  title: source.displayName,
                  subtitle: AppStrings.ankiRepairSourceState(source.state),
                  actions: [
                    TextButton(
                      onPressed:
                          _busy ? null : () => _retryCleanup(source.sourceId),
                      child: Text(AppStrings.ankiRepairRetryCleanup),
                    ),
                  ],
                ),
            ],
            if (quarantined.isNotEmpty) ...[
              _buildSectionHeader(title: AppStrings.ankiRepairQuarantined),
              for (final source in quarantined)
                _tile(
                  key: Key('repair-quarantine-${source.sourceId}'),
                  title: source.displayName,
                  subtitle: AppStrings.ankiRepairSourceState(source.state),
                  actions: [
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _deleteQuarantine(source.sourceId),
                      child: Text(AppStrings.ankiRepairDeleteQuarantine),
                    ),
                  ],
                ),
            ],
            if (jobs.isNotEmpty) ...[
              _buildSectionHeader(
                title: AppStrings.ankiRepairMaintenanceJobs,
                trailing: TextButton(
                  onPressed: _busy ? null : _retryAllJobs,
                  child: Text(AppStrings.databaseDoctorRetryAllJobs),
                ),
              ),
              for (final job in jobs)
                _tile(
                  key: Key('repair-job-${job['job_id']}'),
                  title: AppStrings.ankiRepairJobKind('${job['kind']}'),
                  subtitle: AppStrings.ankiRepairJobState('${job['state']}'),
                  actions: [
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _retryJob(job['job_id'] as String),
                      child: Text(AppStrings.ankiRepairJobRun),
                    ),
                  ],
                ),
            ],
            if (failed.isNotEmpty) ...[
              _buildSectionHeader(
                title: AppStrings.ankiRepairFailedJobs,
                trailing: TextButton(
                  onPressed: _busy ? null : _clearFailedJobs,
                  child: Text(AppStrings.databaseDoctorClearFailedJobs),
                ),
              ),
              for (final job in failed)
                _tile(
                  key: Key('repair-failed-${job['job_id']}'),
                  title: AppStrings.ankiRepairJobKind('${job['kind']}'),
                  subtitle: AppStrings.ankiRepairJobErrorExplanation(
                      job['last_error_code'] as String?),
                  actions: [
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _retryJob(job['job_id'] as String),
                      child: Text(AppStrings.commonRetry),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _deleteJob(job['job_id'] as String),
                      child: Text(AppStrings.ankiRepairJobClear),
                    ),
                  ],
                ),
            ],
            const SizedBox(height: 16),
            _buildAdvancedTools(context),
          ],
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // UI Widgets
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildHealthOverviewCard(
    BuildContext context, {
    required List<StorageArtifactReport> orphans,
  }) {
    final report = _doctorReport;
    final isHealthy = report != null && report.isAllHealthy;
    final color = isHealthy ? Colors.green : Colors.orange;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        side: BorderSide(
          color: color.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      color: color.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  isHealthy
                      ? Icons.verified_rounded
                      : Icons.warning_amber_rounded,
                  color: color,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isHealthy
                            ? AppStrings.databaseDoctorHealthy
                            : (report?.courseDb.integrityOk == false
                                ? AppStrings.databaseDoctorError
                                : AppStrings.databaseDoctorWarning),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: TurnaTheme.textPrimaryColor(context),
                        ),
                      ),
                      if (report != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          isHealthy
                              ? AppStrings.ankiRepairHealthyDetail
                              : AppStrings.ankiRepairIssuesCount(
                                  report.totalIssuesCount),
                          style: TextStyle(
                            fontSize: 12,
                            color: TurnaTheme.textSecondaryColor(context),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: TurnaTheme.surfaceColor(context),
                borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
              ),
              child: Column(
                children: [
                  _statusRow(
                    context,
                    icon: Icons.menu_book_rounded,
                    title: AppStrings.databaseDoctorCourseDbTitle,
                    status: report?.courseDb.integrityOk == true
                        ? AppStrings.databaseDoctorCourseDbOk
                        : AppStrings.ankiRepairDbAbnormal,
                    statusColor: report?.courseDb.integrityOk == true
                        ? Colors.green
                        : Colors.red,
                    detail: report != null
                        ? AppStrings.ankiRepairCourseDbDetail(
                            report.courseDb.lessonCount,
                            report.courseDb.wordCount,
                            report.courseDb.srsCount,
                          )
                        : null,
                  ),
                  const Divider(height: 12),
                  _statusRow(
                    context,
                    icon: Icons.collections_bookmark_outlined,
                    title: AppStrings.databaseDoctorAnkiDbTitle,
                    status: report?.ankiDb.isConfigured == true
                        ? (report!.ankiDb.failedJobsCount > 0
                            ? AppStrings.ankiRepairHasFailedJobs
                            : AppStrings.databaseDoctorAnkiDbOk)
                        : AppStrings.databaseDoctorAnkiDbNotConfigured,
                    statusColor: report?.ankiDb.isConfigured == true
                        ? (report!.ankiDb.failedJobsCount > 0
                            ? Colors.orange
                            : Colors.green)
                        : TurnaTheme.textSecondaryColor(context),
                    detail: report?.ankiDb.isConfigured == true
                        ? AppStrings.ankiRepairDeckCount(
                            report!.ankiDb.sourceCount)
                        : null,
                  ),
                  const Divider(height: 12),
                  _statusRow(
                    context,
                    icon: Icons.folder_open_outlined,
                    title: AppStrings.databaseDoctorStorageTitle,
                    status: orphans.isEmpty
                        ? AppStrings.databaseDoctorStorageNoOrphans
                        : AppStrings.ankiRepairOrphanCount(orphans.length),
                    statusColor: orphans.isEmpty ? Colors.green : Colors.orange,
                    detail: orphans.isNotEmpty
                        ? _formatBytes(orphans.fold<int>(
                            0, (sum, a) => sum + a.physicalBytes))
                        : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  key: const Key('repair-doctor-optimize'),
                  onPressed: _busy ? null : _oneClickOptimize,
                  icon: const Icon(Icons.speed_rounded, size: 18),
                  label: Text(AppStrings.databaseDoctorOneClickOptimize),
                ),
                if (!isHealthy &&
                    (orphans.isNotEmpty ||
                        _failedJobs.isNotEmpty ||
                        _sources.any((s) => s.state == 'pending_cleanup')))
                  FilledButton.tonalIcon(
                    key: const Key('repair-doctor-fix-all'),
                    onPressed: _busy ? null : () => _oneClickRepair(orphans),
                    icon: const Icon(Icons.build_circle_outlined, size: 18),
                    label: Text(AppStrings.databaseDoctorOneClickRepair),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String status,
    required Color statusColor,
    String? detail,
  }) {
    return Row(
      children: [
        Icon(icon, size: 16, color: TurnaTheme.textSecondaryColor(context)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style:
                    const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              if (detail != null)
                Text(
                  detail,
                  style: TextStyle(
                    fontSize: 11,
                    color: TurnaTheme.textSecondaryColor(context),
                  ),
                ),
            ],
          ),
        ),
        Text(
          status,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: statusColor,
          ),
        ),
      ],
    );
  }

  Widget _buildAdvancedTools(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSectionHeader(title: AppStrings.databaseDoctorAdvancedTools),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _busy ? null : _checkIntegrity,
              icon: const Icon(Icons.check_circle_outline, size: 16),
              label: Text(AppStrings.databaseDoctorCheckIntegrity),
            ),
            OutlinedButton.icon(
              onPressed: _busy ? null : _rebuildIndexes,
              icon: const Icon(Icons.sync_alt_rounded, size: 16),
              label: Text(AppStrings.databaseDoctorRebuildIndexes),
            ),
            if (_catalog != null)
              OutlinedButton.icon(
                onPressed: _busy ? null : _checkCollection,
                icon: const Icon(Icons.health_and_safety_outlined, size: 16),
                label: Text(AppStrings.databaseDoctorCheckCollection),
              ),
            OutlinedButton.icon(
              key: const Key('repair-export'),
              onPressed: _busy ? null : _export,
              icon: const Icon(Icons.ios_share_outlined, size: 16),
              label: Text(AppStrings.ankiRepairExportDiagnostics),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSectionHeader({required String title, Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  Widget _tile({
    required Key key,
    required String title,
    required String subtitle,
    List<Widget> actions = const [],
  }) {
    return ListTile(
      key: key,
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(subtitle),
      trailing: actions.isEmpty
          ? null
          : Row(mainAxisSize: MainAxisSize.min, children: actions),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Actions
  // ─────────────────────────────────────────────────────────────────────────

  Future<StorageInventoryReport?> _loadOrphans() async {
    try {
      return await (widget.scanner ?? const StorageInventoryService()).scan();
    } catch (_) {
      return null;
    }
  }

  Future<void> _oneClickOptimize() async {
    setState(() => _busy = true);
    try {
      final res = await _doctor.optimizeAll(
        catalog: _catalog,
        paths: _paths,
        engine: _engine,
      );
      if (mounted) {
        _snack(AppStrings.databaseDoctorOptimizeDoneMessage(
          reclaimedBytes: res.courseDbReclaimedBytes,
          ankiJobs: res.ankiJobsCompleted,
        ));
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _reloadAndSetState();
      }
    }
  }

  Future<void> _oneClickRepair(List<StorageArtifactReport> orphans) async {
    final confirmed = await _confirm(
      title: AppStrings.ankiRepairOneClickTitle,
      body: AppStrings.ankiRepairOneClickBody,
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      // 1. Clean orphans
      if (orphans.isNotEmpty) {
        await _doctor.cleanOrphans(targets: orphans, scanner: widget.scanner);
      }
      // 2. Retry failed jobs
      await _doctor.retryFailedJobs(
        catalog: _catalog,
        paths: _paths,
        engine: _engine,
      );
      // 3. Retry pending cleanups
      final pendingCleanups = _sources
          .where((s) => s.state == 'pending_cleanup' || s.state == 'retiring')
          .toList();
      for (final s in pendingCleanups) {
        try {
          if (_catalog != null && _paths != null) {
            await OfficialAnkiV2RetireService(
              catalog: _catalog!,
              paths: _paths!,
              course: null,
              engine: _engine,
            ).runRetireJob(sourceId: s.sourceId);
          }
        } catch (e, st) {
          // One-click repair must still finish the remaining steps, but a
          // swallowed step failure would report success falsely.
          logger.w('RepairCenter: one-click repair step failed',
              error: e, stackTrace: st);
        }
      }
      if (mounted) {
        _snack(AppStrings.ankiRepairOneClickDone);
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _reloadAndSetState();
      }
    }
  }

  Future<void> _cleanOrphan(StorageArtifactReport orphan) async {
    final confirmed = await _confirm(
      title: AppStrings.databaseDoctorCleanOrphanConfirmTitle,
      body: AppStrings.databaseDoctorCleanOrphanConfirmBody,
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      if (getIt.isRegistered<AnkiDeckManager>()) {
        await getIt<AnkiDeckManager>().uninstall(orphan.ownerId);
      }
      if (mounted) _snack(AppStrings.ankiRepairOrphanCleaned);
    } catch (_) {
      if (mounted) _snack(AppStrings.ankiRepairActionUnavailable);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _reloadAndSetState();
      }
    }
  }

  Future<void> _cleanAllOrphans(List<StorageArtifactReport> orphans) async {
    final confirmed = await _confirm(
      title: AppStrings.databaseDoctorCleanOrphanConfirmTitle,
      body: AppStrings.databaseDoctorCleanOrphanConfirmBody,
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    try {
      final cleaned = await _doctor.cleanOrphans(targets: orphans);
      if (mounted) _snack(AppStrings.ankiRepairOrphansCleaned(cleaned));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _reloadAndSetState();
      }
    }
  }

  Future<void> _retryJob(String jobId) async {
    final catalog = _catalog;
    final paths = _paths;
    if (catalog == null || paths == null) return;
    setState(() => _busy = true);
    try {
      await const OfficialAnkiCatalogService().retryAndRunMaintenanceJob(
        jobId,
        catalog: catalog,
        paths: paths,
        engine: _engine,
      );
      if (mounted) _snack(AppStrings.ankiRepairJobDone);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _reloadAndSetState();
      }
    }
  }

  Future<void> _retryAllJobs() async {
    setState(() => _busy = true);
    try {
      final completed = await _doctor.retryFailedJobs(
        catalog: _catalog,
        paths: _paths,
        engine: _engine,
      );
      if (mounted) _snack(AppStrings.ankiRepairJobsDone(completed));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _reloadAndSetState();
      }
    }
  }

  Future<void> _deleteJob(String jobId) async {
    const OfficialAnkiCatalogService()
        .deleteMaintenanceJob(jobId, catalog: _catalog);
    _reloadAndSetState();
  }

  Future<void> _clearFailedJobs() async {
    final catalog = _catalog;
    final profileId = _paths?.profileId;
    if (catalog == null || profileId == null) return;
    final count = const OfficialAnkiCatalogService()
        .clearFailedMaintenanceJobs(profileId, catalog: catalog);
    _snack(AppStrings.ankiRepairFailedJobsCleared(count));
    _reloadAndSetState();
  }

  Future<void> _checkIntegrity() async {
    setState(() => _busy = true);
    try {
      final courseRes = await _doctor.checkCourseIntegrity();
      final ankiRes = const OfficialAnkiCatalogService()
              .catalogIntegrityCheck(catalog: _catalog) ??
          AppStrings.ankiRepairCatalogNotEnabled;
      if (mounted) {
        unawaited(showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(AppStrings.ankiRepairIntegrityTitle),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(AppStrings.ankiRepairCourseDbResult(courseRes)),
                const SizedBox(height: 8),
                Text(AppStrings.ankiRepairAnkiDbResult(ankiRes)),
              ],
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: Text(AppStrings.commonGotIt),
              ),
            ],
          ),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _rebuildIndexes() async {
    setState(() => _busy = true);
    try {
      await _doctor.rebuildCourseIndexes();
      if (mounted) _snack(AppStrings.ankiRepairIndexesRebuilt);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkCollection() async {
    setState(() => _busy = true);
    try {
      final ok = await _doctor.checkAnkiCollection(engine: _engine);
      if (mounted) {
        _snack(ok
            ? AppStrings.ankiRepairIntegrityPassed
            : AppStrings.ankiRepairIntegrityInterrupted);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _discardImport(String sourceId) async {
    final confirmed = await _confirm(
      title: AppStrings.ankiRepairDiscardConfirmTitle,
      body: AppStrings.ankiRepairDiscardConfirmBody,
    );
    if (confirmed != true) return;
    final injected = widget.onDiscardImport;
    if (injected != null) {
      await injected(sourceId);
      if (mounted) _reloadAndSetState();
      return;
    }
    final catalog = _catalog;
    final paths = _paths;
    if (catalog == null || paths == null) {
      _snack(AppStrings.ankiRepairActionUnavailable);
      return;
    }
    setState(() => _busy = true);
    try {
      await const OfficialAnkiCatalogService().discardPendingImport(
        sourceId,
        catalog: catalog,
        paths: paths,
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _reloadAndSetState();
      }
    }
  }

  Future<void> _retryCleanup(String sourceId) async {
    final confirmed = await _confirm(
      title: AppStrings.ankiRepairRetryCleanupConfirmTitle,
      body: AppStrings.ankiRepairRetryCleanupConfirmBody,
    );
    if (confirmed != true) return;
    final injected = widget.onRetryCleanup;
    if (injected != null) {
      await injected(sourceId);
      if (mounted) _reloadAndSetState();
      return;
    }
    final catalog = _catalog;
    final paths = _paths;
    if (catalog == null || paths == null) {
      _snack(AppStrings.ankiRepairActionUnavailable);
      return;
    }
    setState(() => _busy = true);
    try {
      await OfficialAnkiV2RetireService(
        catalog: catalog,
        paths: paths,
        engine: _engine,
      ).runRetireJob(sourceId: sourceId);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _reloadAndSetState();
      }
    }
  }

  Future<void> _deleteQuarantine(String sourceId) async {
    final confirmed = await _confirm(
      title: AppStrings.ankiRepairDeleteQuarantineConfirmTitle,
      body: AppStrings.ankiRepairDeleteQuarantineConfirmBody,
    );
    if (confirmed != true) return;
    final injected = widget.onDeleteQuarantine;
    if (injected != null) {
      await injected(sourceId);
      if (mounted) _reloadAndSetState();
      return;
    }
    setState(() => _busy = true);
    try {
      await getIt<AnkiDeckManager>().uninstall(sourceId);
    } catch (_) {
      _snack(AppStrings.ankiRepairActionUnavailable);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _reloadAndSetState();
      }
    }
  }

  Future<void> _export() async {
    final catalog = _catalog;
    if (catalog == null) {
      _snack(AppStrings.ankiRepairActionUnavailable);
      return;
    }
    final payload = const OfficialAnkiStorageAudit().encode(
      const OfficialAnkiStorageAudit().snapshot(
        catalog: catalog,
        paths: _paths,
        profileId: _paths?.profileId,
      ),
    );
    final withLogs = _appendRecentLogs(payload);
    final injected = widget.onExportDiagnostics;
    if (injected != null) {
      await injected(withLogs);
      return;
    }
    // Capture the iPad share anchor before the async clipboard write leaves
    // the context across a gap.
    final shareOrigin = context.mounted ? shareOriginFor(context) : null;
    await Clipboard.setData(ClipboardData(text: withLogs));
    try {
      await Share.share(
        withLogs,
        subject: AppStrings.ankiRepairCenterTitle,
        sharePositionOrigin: shareOrigin,
      );
    } catch (_) {
      // Best-effort secondary channel: the clipboard copy above already
      // succeeded and the snack below tells the user so.
    }
    if (mounted) _snack(AppStrings.ankiRepairExportCopied);
  }

  String _appendRecentLogs(String payload, {int limit = 120}) {
    try {
      final entries = LogCapture.instance.entries.value;
      if (entries.isEmpty) return payload;
      final buffer = StringBuffer(payload)
        ..write('\n--- recent file log (${entries.length} kept, '
            'showing up to $limit, newest first) ---\n');
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
    } catch (_) {
      return payload;
    }
  }

  String _categoryName(StorageArtifactCategory category) {
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

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Future<bool?> _confirm({required String title, required String body}) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(AppStrings.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(AppStrings.commonOk),
          ),
        ],
      ),
    );
  }

  void _snack(String message) => TurnaSnackBar.show(context, message);
}
