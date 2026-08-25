import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_dao.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_state.dart';
import 'package:turna/application/anki_official/migration/official_anki_source_reconciler.dart';
import 'package:turna/application/anki_official/migration/official_anki_startup_census.dart';
import 'package:turna/application/anki_official/migration/official_legacy_migration_coordinator.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/utils/validated_file_picker.dart';

/// Production W8 entry. Startup census remains read-only; only a per-source
/// button with an explicit scheduling acknowledgement can begin/resume.
@RoutePage()
class OfficialAnkiMigrationCenterPage extends StatefulWidget {
  const OfficialAnkiMigrationCenterPage({super.key});

  @override
  State<OfficialAnkiMigrationCenterPage> createState() =>
      _OfficialAnkiMigrationCenterPageState();
}

class _OfficialAnkiMigrationCenterPageState
    extends State<OfficialAnkiMigrationCenterPage> {
  OfficialAnkiSourceCensusReport? _report;
  List<LegacyAnkiMigrationRow> _journals = const [];
  final _policies = <String, LegacyAnkiSchedulingPolicy>{};
  final _confirmed = <String, bool>{};
  String? _busyImportId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _error = null);
    try {
      await OfficialAnkiCompositionRoot.initializeReadOnlyLocator();
      final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
      final paths = OfficialAnkiCompositionRoot.locatorPaths;
      if (catalog == null || paths == null) {
        throw StateError('Official Anki catalog is unavailable');
      }
      final report = await const OfficialAnkiStartupCensus().collect(
        course: getIt<CourseDatabase>(),
        catalog: catalog,
        profileId: paths.profileId,
      );
      final journals = OfficialAnkiMigrationDao(catalog).listMigrations(
        profileId: paths.profileId,
      );
      if (!mounted) return;
      setState(() {
        _report = report;
        _journals = journals;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  LegacyAnkiMigrationRow? _journalFor(String importId) {
    for (final journal in _journals) {
      if (journal.legacyImportId == importId) return journal;
    }
    return null;
  }

  Future<OfficialLegacyMigrationCoordinator> _buildCoordinator({
    bool requireRuntime = true,
  }) async {
    var importer = OfficialAnkiCompositionRoot.session;
    var engine = OfficialAnkiCompositionRoot.projectionEngineFromSession();
    final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
    final paths = OfficialAnkiCompositionRoot.locatorPaths;
    if (catalog == null || paths == null) {
      throw StateError('Official Anki catalog is unavailable');
    }
    if (requireRuntime) {
      importer = await OfficialAnkiCompositionRoot.requireImporter();
      engine = OfficialAnkiCompositionRoot.projectionEngineFromSession();
    }
    if (requireRuntime && engine == null) {
      throw StateError('Official Anki runtime is unavailable');
    }
    return OfficialLegacyMigrationCoordinator(
      course: getIt<CourseDatabase>(),
      catalog: catalog,
      paths: paths,
      importer: importer,
      engine: engine,
    );
  }

  Future<void> _run(OfficialAnkiSourceCensusRow row) async {
    final importId = row.evidence.importId ?? '';
    if (_confirmed[importId] != true) return;
    final policy = _policies[importId] ??
        _journalFor(importId)?.schedulingPolicy ??
        LegacyAnkiSchedulingPolicy.preservePackageScheduling;
    try {
      File package;
      if (policy.abandonsOfficialCutover) {
        // The read-only policy never reads a package or opens Collection.
        package = File('');
      } else {
        final picked = await ValidatedFilePicker.pickFiles(
          allowedExtensions: const ['apkg'],
          dialogTitle: 'Select the original Anki package',
        );
        final path = picked?.files.single.path;
        if (path == null || !mounted) return;
        package = File(path);
      }
      if (!mounted) return;
      setState(() {
        _busyImportId = importId;
        _error = null;
      });
      final coordinator = await _buildCoordinator(
        requireRuntime: !policy.abandonsOfficialCutover,
      );
      final result = await coordinator.run(
        censusRow: row,
        package: package,
        policy: policy,
        policyConfirmedByUser: true,
      );
      if (!mounted) return;
      if (result.outcome == OfficialLegacyMigrationOutcome.awaitingMapping) {
        final engine =
            OfficialAnkiCompositionRoot.projectionEngineFromSession();
        final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
        final paths = OfficialAnkiCompositionRoot.locatorPaths;
        if (engine != null && catalog != null && paths != null) {
          await context.router.push(
            OfficialAnkiSourceManagementRoute(
              engine: engine,
              catalog: catalog,
              course: getIt<CourseDatabase>(),
              profileId: paths.profileId,
              flags: OfficialAnkiFeatureFlags.current,
              courseProvider: context.read<CourseProvider>(),
            ),
          );
        }
      }
      await _refresh();
    } on ValidatedFilePickerInvalidExtension {
      if (mounted) setState(() => _error = 'Only .apkg files are accepted.');
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busyImportId = null);
    }
  }

  Future<void> _rollback(LegacyAnkiMigrationRow journal) async {
    setState(() {
      _busyImportId = journal.legacyImportId;
      _error = null;
    });
    try {
      await (await _buildCoordinator(requireRuntime: false))
          .rollbackBeforeOwnerCommit(journal.migrationId);
      await _refresh();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busyImportId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Scaffold(
      appBar: AppBar(title: const Text('Legacy Anki migration')),
      body: report == null
          ? Center(
              child: _error == null
                  ? const CircularProgressIndicator()
                  : _ErrorPanel(error: _error!, onRetry: _refresh),
            )
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Migrate one source at a time. Turna review progress '
                    'cannot currently be transferred losslessly; choose and '
                    'acknowledge a scheduling policy before continuing.',
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    _ErrorPanel(error: _error!, onRetry: _refresh),
                  ],
                  const SizedBox(height: 12),
                  if (report.rows.isEmpty)
                    const ListTile(
                      leading: Icon(Icons.check_circle_outline),
                      title: Text('No Legacy Anki sources detected'),
                    ),
                  for (final row in report.rows) _sourceCard(row),
                ],
              ),
            ),
    );
  }

  Widget _sourceCard(OfficialAnkiSourceCensusRow row) {
    final importId = row.evidence.importId ?? '(unknown)';
    final cleanLegacy =
        row.decision.state == OfficialAnkiSourceReconcileState.cleanLegacy;
    final journal = _journalFor(importId);
    final policy = _policies[importId] ??
        journal?.schedulingPolicy ??
        LegacyAnkiSchedulingPolicy.preservePackageScheduling;
    final busy = _busyImportId == importId;
    final canRollback = journal != null &&
        journal.state != LegacyAnkiMigrationState.cutover &&
        journal.state != LegacyAnkiMigrationState.observing &&
        journal.state != LegacyAnkiMigrationState.completed &&
        journal.state != LegacyAnkiMigrationState.rolledBackLegacy;
    return Card(
      key: ValueKey('official-migration-$importId'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(importId, style: Theme.of(context).textTheme.titleMedium),
            Text(
              '${row.evidence.legacyCardCount} cards · '
              '${row.decision.state.name}'
              '${journal == null ? '' : ' · ${journal.state.name}'}',
            ),
            if (cleanLegacy || journal != null) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<LegacyAnkiSchedulingPolicy>(
                initialValue: policy,
                decoration: const InputDecoration(
                  labelText: 'Scheduling policy',
                ),
                items: [
                  for (final value in LegacyAnkiSchedulingPolicy.values)
                    DropdownMenuItem(
                      value: value,
                      child: Text(value.userVisibleLabel),
                    ),
                ],
                onChanged: journal == null
                    ? (value) {
                        if (value == null) return;
                        setState(() {
                          _policies[importId] = value;
                          _confirmed[importId] = false;
                        });
                      }
                    : null,
              ),
              const SizedBox(height: 6),
              Text(policy.userVisibleDescription),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _confirmed[importId] ?? false,
                title: const Text(
                  'I understand this scheduling choice and have a backup.',
                ),
                onChanged: busy
                    ? null
                    : (value) => setState(
                          () => _confirmed[importId] = value ?? false,
                        ),
              ),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: busy || _confirmed[importId] != true
                          ? null
                          : () => _run(row),
                      icon: busy
                          ? const SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.sync),
                      label: Text(journal == null ? 'Begin' : 'Resume'),
                    ),
                  ),
                  if (canRollback) ...[
                    const SizedBox(width: 8),
                    OutlinedButton(
                      onPressed: busy ? null : () => _rollback(journal),
                      child: const Text('Roll back'),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.error, required this.onRetry});

  final String error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: ListTile(
        title: Text(error),
        trailing: IconButton(
          onPressed: onRetry,
          icon: const Icon(Icons.refresh),
        ),
      ),
    );
  }
}
