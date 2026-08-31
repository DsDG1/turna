import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:turna/application/anki_official/import/official_anki_import_saga.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_maintenance.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_pending_imports.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_storage_audit.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_uninstall_saga.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_import_attempt_dao.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/maintenance/official_storage_optimize_service.dart';
import 'package:turna/application/maintenance/storage_inventory_service.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/settings/widgets/settings_common.dart';
import 'package:turna/views/theme.dart';

/// Product repair surface (doc 41 §13.3): pending imports, pending cleanup,
/// quarantine, maintenance jobs, and ledger-less leftovers. Not a
/// diagnostics-guarded page.
@RoutePage()
class OfficialAnkiRepairCenterPage extends StatefulWidget {
  const OfficialAnkiRepairCenterPage({
    super.key,
    this.catalog,
    this.paths,
    this.scanner,
    this.optimizeDatabases,
    this.onContinueImport,
    this.onDiscardImport,
    this.onRetryCleanup,
    this.onExportDiagnostics,
  });

  final OfficialAnkiDatabase? catalog;
  final OfficialAnkiPaths? paths;
  final StorageInventoryService? scanner;
  final Future<OfficialStorageOptimizeResult> Function({required bool force})?
      optimizeDatabases;
  final Future<void> Function(String sourceId)? onContinueImport;
  final Future<void> Function(String sourceId)? onDiscardImport;
  final Future<void> Function(String sourceId)? onRetryCleanup;
  final Future<void> Function(String payload)? onExportDiagnostics;

  @override
  State<OfficialAnkiRepairCenterPage> createState() =>
      _OfficialAnkiRepairCenterPageState();
}

class _OfficialAnkiRepairCenterPageState
    extends State<OfficialAnkiRepairCenterPage> {
  bool _busy = false;
  late final Future<StorageInventoryReport?> _orphanScan;

  @override
  void initState() {
    super.initState();
    _orphanScan = _loadOrphans();
  }

  OfficialAnkiDatabase? get _catalog =>
      widget.catalog ?? OfficialAnkiCompositionRoot.readOnlyCatalog;

  OfficialAnkiPaths? get _paths =>
      widget.paths ?? OfficialAnkiCompositionRoot.locatorPaths;

  @override
  Widget build(BuildContext context) {
    return SettingsScaffold(
      title: AppStrings.ankiRepairCenterTitle,
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final catalog = _catalog;
    if (catalog == null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          AppStrings.ankiRepairCenterEmptyCatalog,
          style: TextStyle(color: TurnaTheme.textSecondaryColor(context)),
        ),
      );
    }
    final profileId = _paths?.profileId;
    final pending = const OfficialAnkiPendingImportStore().list(catalog);
    final sources = profileId == null
        ? const <OfficialAnkiSourceRow>[]
        : OfficialAnkiSourceDao(catalog).listSources(profileId);
    final pendingCleanup = sources
        .where((s) => s.state == 'pending_cleanup')
        .toList();
    final quarantined =
        sources.where((s) => s.state == 'quarantined').toList();
    final jobs = profileId == null
        ? const <Map<String, Object?>>[]
        : OfficialAnkiMaintenanceJobDao(catalog).pending(profileId: profileId);
    final failed = profileId == null
        ? const <Map<String, Object?>>[]
        : OfficialAnkiMaintenanceJobDao(catalog)
            .recentFailed(profileId: profileId);
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
            if (_busy) const LinearProgressIndicator(),
            if (empty)
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Text(
                  AppStrings.ankiRepairCenterEmpty,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: TurnaTheme.textSecondaryColor(context),
                  ),
                ),
              ),
            if (pending.isNotEmpty) ...[
              _section(AppStrings.ankiPendingImportsTitle),
              for (final item in pending)
                _tile(
                  key: Key('repair-pending-${item.sourceId}'),
                  title: item.displayName,
                  subtitle: AppStrings.ankiPendingImportPhase(item.phase),
                  actions: [
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _continueImport(item.sourceId),
                      child: Text(AppStrings.ankiPendingContinue),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _discardImport(item.sourceId),
                      child: Text(AppStrings.ankiPendingDiscard),
                    ),
                  ],
                ),
            ],
            if (pendingCleanup.isNotEmpty) ...[
              _section(AppStrings.ankiRepairPendingCleanup),
              for (final source in pendingCleanup)
                _tile(
                  key: Key('repair-cleanup-${source.sourceId}'),
                  title: source.displayName,
                  subtitle: source.state,
                  actions: [
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () => _retryCleanup(source.sourceId),
                      child: Text(AppStrings.ankiRepairRetryCleanup),
                    ),
                  ],
                ),
            ],
            if (quarantined.isNotEmpty) ...[
              _section(AppStrings.ankiRepairQuarantined),
              for (final source in quarantined)
                _tile(
                  key: Key('repair-quarantine-${source.sourceId}'),
                  title: source.displayName,
                  subtitle: source.state,
                ),
            ],
            if (jobs.isNotEmpty) ...[
              _section(AppStrings.ankiRepairMaintenanceJobs),
              for (final job in jobs)
                _tile(
                  key: Key('repair-job-${job['job_id']}'),
                  title: '${job['kind']}',
                  subtitle: '${job['state']}',
                ),
            ],
            if (failed.isNotEmpty) ...[
              _section(AppStrings.ankiRepairFailedJobs),
              for (final job in failed)
                _tile(
                  key: Key('repair-failed-${job['job_id']}'),
                  title: '${job['kind']}',
                  subtitle: '${job['last_error_code'] ?? job['state']}',
                ),
            ],
            if (orphans.isNotEmpty) ...[
              _section(AppStrings.ankiRepairOrphans),
              for (final orphan in orphans)
                _tile(
                  key: Key('repair-orphan-${orphan.ownerId}'),
                  title: orphan.label,
                  subtitle: orphan.category.name,
                ),
            ],
            const SizedBox(height: 16),
            OutlinedButton.icon(
              key: const Key('repair-optimize'),
              onPressed: _busy ? null : _optimize,
              icon: const Icon(Icons.compress_outlined, size: 18),
              label: Text(AppStrings.storageOptimizeDatabase),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('repair-export'),
              onPressed: _busy ? null : _export,
              icon: const Icon(Icons.ios_share_outlined, size: 18),
              label: Text(AppStrings.ankiRepairExportDiagnostics),
            ),
          ],
        );
      },
    );
  }

  Future<StorageInventoryReport?> _loadOrphans() async {
    try {
      return await (widget.scanner ?? const StorageInventoryService()).scan();
    } catch (_) {
      return null;
    }
  }

  Widget _section(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 8),
      child: Text(
        title,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
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

  Future<void> _continueImport(String sourceId) async {
    final injected = widget.onContinueImport;
    if (injected != null) {
      await injected(sourceId);
      return;
    }
    if (!mounted) return;
    await context.router.push(const AnkiImportRoute());
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
      setState(() {});
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
      await OfficialAnkiImportSaga(
        sources: OfficialAnkiSourceDao(catalog),
        attempts: OfficialAnkiImportAttemptDao(catalog),
        paths: paths,
      ).cancelSource(sourceId);
    } finally {
      if (mounted) setState(() => _busy = false);
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
      setState(() {});
      return;
    }
    final catalog = _catalog;
    final engine = OfficialAnkiCompositionRoot.engine;
    if (catalog == null || engine == null) {
      _snack(AppStrings.ankiRepairActionUnavailable);
      return;
    }
    setState(() => _busy = true);
    try {
      await OfficialAnkiUninstallSaga(
        catalog: catalog,
        engine: engine,
        paths: _paths,
      ).run(sourceId);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _optimize() async {
    final confirmed = await _confirm(
      title: AppStrings.storageOptimizeConfirmTitle,
      body: AppStrings.storageOptimizeConfirmBody,
    );
    if (confirmed != true) return;
    setState(() => _busy = true);
    OfficialStorageOptimizeResult result;
    try {
      final injected = widget.optimizeDatabases;
      result = injected != null
          ? await injected(force: true)
          : await const OfficialStorageOptimizeService().runForceCompact(
              catalog: _catalog,
              paths: _paths,
            );
    } catch (_) {
      result = const OfficialStorageOptimizeResult(
        ok: false,
        errorCode: 'optimize_failed',
      );
    }
    if (!mounted) return;
    setState(() => _busy = false);
    _snack(
      !result.ok
          ? (result.errorCode == 'capability_missing'
              ? AppStrings.storageOptimizeUnavailable
              : AppStrings.storageOptimizeFailed)
          : AppStrings.storageOptimizeDone(result.completedJobs),
    );
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
    final injected = widget.onExportDiagnostics;
    if (injected != null) {
      await injected(payload);
      return;
    }
    await Clipboard.setData(ClipboardData(text: payload));
    try {
      await Share.share(payload, subject: AppStrings.ankiRepairCenterTitle);
    } catch (_) {}
    if (mounted) _snack(AppStrings.ankiRepairExportCopied);
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

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}
