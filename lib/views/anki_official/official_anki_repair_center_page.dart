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
import 'package:turna/core/logger.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/anki_official/components/repair_center_sections.dart';
import 'package:turna/views/settings/components/settings_common.dart';
import 'package:turna/views/widgets/turna_snack_bar.dart';

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
  StorageInventoryReport? _orphanReport;
  String? _orphansError;
  bool _scanningOrphans = false;

  DatabaseDoctorReport? _doctorReport;
  String? _doctorError;
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
    _reloadCatalogSnapshot();
    _inspecting = true;
    unawaited(_loadDoctorReport(fromInit: true));
    if (_catalog != null) {
      _scanningOrphans = true;
      unawaited(_loadOrphans(fromInit: true));
    }
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

  Future<void> _loadDoctorReport({bool fromInit = false}) async {
    if (!fromInit && mounted) {
      setState(() {
        _inspecting = true;
        _doctorError = null;
      });
    }
    try {
      final report = await _doctor.inspectHealth(
        catalog: _catalog,
        paths: _paths,
        scanner: widget.scanner,
      );
      if (mounted) {
        setState(() {
          _doctorReport = report;
          _doctorError = null;
          _inspecting = false;
        });
      }
    } catch (e, st) {
      logger.w(
        'RepairCenter: doctor inspection failed',
        error: e,
        stackTrace: st,
      );
      if (mounted) {
        setState(() {
          _doctorError = AppStrings.repairDiagnosticsLoadFailed;
          _inspecting = false;
        });
      }
    }
  }

  Future<void> _loadOrphans({bool fromInit = false}) async {
    if (_catalog == null) return;
    if (!fromInit && mounted) {
      setState(() {
        _scanningOrphans = true;
        _orphansError = null;
      });
    }
    try {
      final report =
          await (widget.scanner ?? const StorageInventoryService()).scan();
      if (mounted) {
        setState(() {
          _orphanReport = report;
          _orphansError = null;
          _scanningOrphans = false;
        });
      }
    } catch (e, st) {
      logger.w('RepairCenter: orphan scan failed', error: e, stackTrace: st);
      if (mounted) {
        setState(() {
          _orphansError = AppStrings.repairDiagnosticsLoadFailed;
          _scanningOrphans = false;
        });
      }
    }
  }

  void _reloadAndSetState() {
    setState(_reloadCatalogSnapshot);
    unawaited(_loadDoctorReport());
    if (_catalog != null) {
      unawaited(_loadOrphans());
    }
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
          if (_busy || _inspecting) const LinearProgressIndicator(),
          const SizedBox(height: 8),
          const RepairEmptyCatalogCard(),
          const SizedBox(height: 16),
          RepairHealthOverviewCard(
            report: _doctorReport,
            doctorError: _doctorError,
            orphans: const [],
            orphansError: null,
            busy: _busy,
            canRepairAll: false,
            onRetryDoctor: () => unawaited(_loadDoctorReport()),
            onOneClickOptimize: () => unawaited(_oneClickOptimize()),
            onOneClickRepair: () => unawaited(_oneClickRepair(const [])),
          ),
          const SizedBox(height: 16),
          RepairAdvancedToolsSection(
            busy: _busy,
            hasCatalog: false,
            onCheckIntegrity: () => unawaited(_checkIntegrity()),
            onRebuildIndexes: () => unawaited(_rebuildIndexes()),
            onCheckCollection: () => unawaited(_checkCollection()),
            onExport: () => unawaited(_export()),
          ),
        ],
      );
    }

    final pendingCleanup = _sources
        .where((s) => s.state == 'pending_cleanup' || s.state == 'retiring')
        .toList();
    final quarantined =
        _sources.where((s) => s.state == 'quarantined').toList();
    final orphans = _orphanReport?.orphans ?? const <StorageArtifactReport>[];
    final empty = _orphansError == null &&
        _pending.isEmpty &&
        pendingCleanup.isEmpty &&
        quarantined.isEmpty &&
        _jobs.isEmpty &&
        _failedJobs.isEmpty &&
        orphans.isEmpty;
    final canRepairAll = orphans.isNotEmpty ||
        _failedJobs.isNotEmpty ||
        pendingCleanup.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        if (_busy || _inspecting || _scanningOrphans)
          const LinearProgressIndicator(),
        const SizedBox(height: 8),
        RepairHealthOverviewCard(
          report: _doctorReport,
          doctorError: _doctorError,
          orphans: orphans,
          orphansError: _orphansError,
          busy: _busy,
          canRepairAll: canRepairAll,
          onRetryDoctor: () => unawaited(_loadDoctorReport()),
          onOneClickOptimize: () => unawaited(_oneClickOptimize()),
          onOneClickRepair: () => unawaited(_oneClickRepair(orphans)),
        ),
        const SizedBox(height: 16),
        if (empty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                AppStrings.ankiRepairCenterEmpty,
                textAlign: TextAlign.center,
                style: TextStyle(color: TurnaTheme.textSecondaryColor(context)),
              ),
            ),
          ),
        RepairOrphansSection(
          orphans: orphans,
          orphansError: _orphansError,
          busy: _busy,
          onRetryScan: () => unawaited(_loadOrphans()),
          onCleanOrphan: (orphan) => unawaited(_cleanOrphan(orphan)),
          onCleanAllOrphans: () => unawaited(_cleanAllOrphans(orphans)),
        ),
        RepairPendingImportsSection(
          pending: _pending,
          busy: _busy,
          onDiscard: (id) => unawaited(_discardImport(id)),
        ),
        RepairPendingCleanupSection(
          sources: pendingCleanup,
          busy: _busy,
          onRetryCleanup: (id) => unawaited(_retryCleanup(id)),
        ),
        RepairQuarantinedSection(
          sources: quarantined,
          busy: _busy,
          onDeleteQuarantine: (id) => unawaited(_deleteQuarantine(id)),
        ),
        RepairMaintenanceJobsSection(
          jobs: _jobs,
          busy: _busy,
          onRetryAll: () => unawaited(_retryAllJobs()),
          onRetryJob: (id) => unawaited(_retryJob(id)),
        ),
        RepairFailedJobsSection(
          jobs: _failedJobs,
          busy: _busy,
          onClearAll: () => unawaited(_clearFailedJobs()),
          onRetryJob: (id) => unawaited(_retryJob(id)),
          onDeleteJob: (id) => unawaited(_deleteJob(id)),
        ),
        const SizedBox(height: 16),
        RepairAdvancedToolsSection(
          busy: _busy,
          hasCatalog: true,
          onCheckIntegrity: () => unawaited(_checkIntegrity()),
          onRebuildIndexes: () => unawaited(_rebuildIndexes()),
          onCheckCollection: () => unawaited(_checkCollection()),
          onExport: () => unawaited(_export()),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Actions
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _runBusyAction(
    String label,
    Future<void> Function() action, {
    bool reload = true,
  }) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (e, st) {
      logger.w('RepairCenter: $label failed', error: e, stackTrace: st);
      if (mounted) _snack(AppStrings.ankiRepairActionUnavailable);
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (reload) _reloadAndSetState();
      }
    }
  }

  Future<void> _runConfirmedAction({
    required String label,
    required String title,
    required String body,
    required Future<void> Function() action,
    Future<void> Function()? injected,
  }) async {
    final confirmed =
        await confirmRepairAction(context, title: title, body: body);
    if (!confirmed || !mounted) return;
    await _runBusyAction(label, injected ?? action);
  }

  Future<void> _oneClickOptimize() => _runBusyAction('optimize', () async {
        final res = await _doctor.optimizeAll(
          catalog: _catalog,
          paths: _paths,
          engine: _engine,
        );
        if (!mounted) return;
        _snack(res.ok || res.ankiJobsCompleted > 0
            ? AppStrings.databaseDoctorOptimizeDoneMessage(
                reclaimedBytes: res.courseDbReclaimedBytes,
                ankiJobs: res.ankiJobsCompleted,
              )
            : AppStrings.ankiRepairActionUnavailable);
      });

  Future<void> _oneClickRepair(List<StorageArtifactReport> orphans) =>
      _runConfirmedAction(
        label: 'one-click repair',
        title: AppStrings.ankiRepairOneClickTitle,
        body: AppStrings.ankiRepairOneClickBody,
        action: () async {
          if (orphans.isNotEmpty) {
            await _doctor.cleanOrphans(
                targets: orphans, scanner: widget.scanner);
          }
          await _doctor.retryFailedJobs(
              catalog: _catalog, paths: _paths, engine: _engine);
          var anyStepFailed = false;
          final pendingCleanups = _sources
              .where(
                  (s) => s.state == 'pending_cleanup' || s.state == 'retiring')
              .toList();
          for (final s in pendingCleanups) {
            try {
              if (_catalog != null && _paths != null) {
                await OfficialAnkiV2RetireService(
                  catalog: _catalog!,
                  paths: _paths!,
                  engine: _engine,
                ).runRetireJob(sourceId: s.sourceId);
              }
            } catch (e, st) {
              anyStepFailed = true;
              // One-click repair must still finish remaining steps, while
              // surfacing partial failure instead of pretending success.
              logger.w('RepairCenter: one-click repair step failed',
                  error: e, stackTrace: st);
            }
          }
          if (mounted) {
            _snack(anyStepFailed
                ? AppStrings.ankiRepairActionUnavailable
                : AppStrings.ankiRepairOneClickDone);
          }
        },
      );

  Future<void> _cleanOrphan(StorageArtifactReport orphan) =>
      _runConfirmedAction(
        label: 'clean orphan',
        title: AppStrings.databaseDoctorCleanOrphanConfirmTitle,
        body: AppStrings.databaseDoctorCleanOrphanConfirmBody,
        action: () async {
          if (!getIt.isRegistered<AnkiDeckManager>()) {
            if (mounted) _snack(AppStrings.ankiRepairActionUnavailable);
            return;
          }
          final ok = await getIt<AnkiDeckManager>().uninstall(orphan.ownerId);
          if (mounted) {
            _snack(ok
                ? AppStrings.ankiRepairOrphanCleaned
                : AppStrings.ankiRepairActionUnavailable);
          }
        },
      );

  Future<void> _cleanAllOrphans(List<StorageArtifactReport> orphans) =>
      _runConfirmedAction(
        label: 'clean all orphans',
        title: AppStrings.databaseDoctorCleanOrphanConfirmTitle,
        body: AppStrings.databaseDoctorCleanOrphanConfirmBody,
        action: () async {
          final cleaned = await _doctor.cleanOrphans(
              targets: orphans, scanner: widget.scanner);
          if (mounted) {
            _snack(cleaned > 0
                ? AppStrings.ankiRepairOrphansCleaned(cleaned)
                : AppStrings.ankiRepairActionUnavailable);
          }
        },
      );

  Future<void> _retryJob(String jobId) async {
    final catalog = _catalog;
    final paths = _paths;
    if (catalog == null || paths == null) {
      _snack(AppStrings.ankiRepairActionUnavailable);
      return;
    }
    await _runBusyAction('retry job', () async {
      final ok =
          await const OfficialAnkiCatalogService().retryAndRunMaintenanceJob(
        jobId,
        catalog: catalog,
        paths: paths,
        engine: _engine,
      );
      if (mounted) {
        _snack(ok
            ? AppStrings.ankiRepairJobDone
            : AppStrings.ankiRepairActionUnavailable);
      }
    });
  }

  Future<void> _retryAllJobs() => _runBusyAction('retry all jobs', () async {
        final completed = await _doctor.retryFailedJobs(
          catalog: _catalog,
          paths: _paths,
          engine: _engine,
        );
        if (mounted) _snack(AppStrings.ankiRepairJobsDone(completed));
      });

  Future<void> _deleteJob(String jobId) async {
    try {
      const OfficialAnkiCatalogService()
          .deleteMaintenanceJob(jobId, catalog: _catalog);
    } catch (e, st) {
      logger.w('RepairCenter: delete job failed', error: e, stackTrace: st);
      if (mounted) _snack(AppStrings.ankiRepairActionUnavailable);
    } finally {
      if (mounted) _reloadAndSetState();
    }
  }

  Future<void> _clearFailedJobs() async {
    final catalog = _catalog;
    final profileId = _paths?.profileId;
    if (catalog == null || profileId == null) {
      _snack(AppStrings.ankiRepairActionUnavailable);
      return;
    }
    try {
      final count = const OfficialAnkiCatalogService()
          .clearFailedMaintenanceJobs(profileId, catalog: catalog);
      if (mounted) _snack(AppStrings.ankiRepairFailedJobsCleared(count));
    } catch (e, st) {
      logger.w('RepairCenter: clear failed jobs failed',
          error: e, stackTrace: st);
      if (mounted) _snack(AppStrings.ankiRepairActionUnavailable);
    } finally {
      if (mounted) _reloadAndSetState();
    }
  }

  Future<void> _checkIntegrity() => _runBusyAction(
        'integrity check',
        () async {
          final courseRes = await _doctor.checkCourseIntegrity();
          final ankiRes = const OfficialAnkiCatalogService()
                  .catalogIntegrityCheck(catalog: _catalog) ??
              AppStrings.ankiRepairCatalogNotEnabled;
          if (mounted) {
            unawaited(showRepairIntegrityDialog(
              context,
              courseResult: courseRes,
              ankiResult: ankiRes,
            ));
          }
        },
        reload: false,
      );

  Future<void> _rebuildIndexes() => _runBusyAction(
        'rebuild indexes',
        () async {
          await _doctor.rebuildCourseIndexes();
          if (mounted) _snack(AppStrings.ankiRepairIndexesRebuilt);
        },
        reload: false,
      );

  Future<void> _checkCollection() => _runBusyAction(
        'check collection',
        () async {
          final ok = await _doctor.checkAnkiCollection(engine: _engine);
          if (mounted) {
            _snack(ok
                ? AppStrings.ankiRepairIntegrityPassed
                : AppStrings.ankiRepairIntegrityInterrupted);
          }
        },
        reload: false,
      );

  Future<void> _discardImport(String sourceId) {
    final injected = widget.onDiscardImport;
    if (injected == null && (_catalog == null || _paths == null)) {
      return _confirmAndUnavailable(
        title: AppStrings.ankiRepairDiscardConfirmTitle,
        body: AppStrings.ankiRepairDiscardConfirmBody,
      );
    }
    return _runConfirmedAction(
      label: 'discard import',
      title: AppStrings.ankiRepairDiscardConfirmTitle,
      body: AppStrings.ankiRepairDiscardConfirmBody,
      injected: injected == null ? null : () => injected(sourceId),
      action: () => const OfficialAnkiCatalogService().discardPendingImport(
        sourceId,
        catalog: _catalog!,
        paths: _paths!,
      ),
    );
  }

  Future<void> _retryCleanup(String sourceId) {
    final injected = widget.onRetryCleanup;
    if (injected == null && (_catalog == null || _paths == null)) {
      return _confirmAndUnavailable(
        title: AppStrings.ankiRepairRetryCleanupConfirmTitle,
        body: AppStrings.ankiRepairRetryCleanupConfirmBody,
      );
    }
    return _runConfirmedAction(
      label: 'retry cleanup',
      title: AppStrings.ankiRepairRetryCleanupConfirmTitle,
      body: AppStrings.ankiRepairRetryCleanupConfirmBody,
      injected: injected == null ? null : () => injected(sourceId),
      action: () => OfficialAnkiV2RetireService(
        catalog: _catalog!,
        paths: _paths!,
        engine: _engine,
      ).runRetireJob(sourceId: sourceId),
    );
  }

  Future<void> _deleteQuarantine(String sourceId) {
    final injected = widget.onDeleteQuarantine;
    return _runConfirmedAction(
      label: 'delete quarantine',
      title: AppStrings.ankiRepairDeleteQuarantineConfirmTitle,
      body: AppStrings.ankiRepairDeleteQuarantineConfirmBody,
      injected: injected == null ? null : () => injected(sourceId),
      action: () async {
        if (!getIt.isRegistered<AnkiDeckManager>()) {
          if (mounted) _snack(AppStrings.ankiRepairActionUnavailable);
          return;
        }
        final ok = await getIt<AnkiDeckManager>().uninstall(sourceId);
        if (mounted && !ok) _snack(AppStrings.ankiRepairActionUnavailable);
      },
    );
  }

  Future<void> _confirmAndUnavailable({
    required String title,
    required String body,
  }) async {
    final confirmed =
        await confirmRepairAction(context, title: title, body: body);
    if (confirmed && mounted) _snack(AppStrings.ankiRepairActionUnavailable);
  }

  Future<void> _export() async {
    final catalog = _catalog;
    if (catalog == null) {
      _snack(AppStrings.ankiRepairActionUnavailable);
      return;
    }
    try {
      final payload = const OfficialAnkiStorageAudit().encode(
        const OfficialAnkiStorageAudit().snapshot(
          catalog: catalog,
          paths: _paths,
          profileId: _paths?.profileId,
        ),
      );
      final withLogs = appendRepairRecentLogs(payload);
      final injected = widget.onExportDiagnostics;
      if (injected != null) {
        await injected(withLogs);
        return;
      }
      await Clipboard.setData(ClipboardData(text: withLogs));
      try {
        await Share.share(withLogs, subject: AppStrings.ankiRepairCenterTitle);
      } catch (e, st) {
        // Best-effort secondary channel: the clipboard copy above already
        // succeeded and the snack below tells the user so.
        logger.w('RepairCenter: share diagnostics failed',
            error: e, stackTrace: st);
      }
      if (mounted) _snack(AppStrings.ankiRepairExportCopied);
    } catch (e, st) {
      logger.w('RepairCenter: export diagnostics failed',
          error: e, stackTrace: st);
      if (mounted) _snack(AppStrings.ankiRepairActionUnavailable);
    }
  }

  void _snack(String message) => TurnaSnackBar.show(context, message);
}
