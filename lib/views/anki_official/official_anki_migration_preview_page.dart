import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:turna/application/anki_official/engine/official_anki_operation_coordinator.dart';
import 'package:turna/application/anki_official/migration/official_anki_census.dart';
import 'package:turna/application/anki_official/migration/official_anki_dry_run_matcher.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_state.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';

/// Preview-only migration UI. Cutover stays disabled.
@RoutePage()
class OfficialAnkiMigrationPreviewPage extends StatefulWidget {
  const OfficialAnkiMigrationPreviewPage({
    super.key,
    required this.census,
    required this.dryRun,
    this.diskFreeBytes = 0,
    this.displayName = 'Legacy source',
    this.importId,
    this.sourceHash,
    this.flags = const OfficialAnkiFeatureFlags(),
    this.coordinator,
  });

  final LegacyAnkiCensusReport census;
  final LegacyAnkiDryRunResult dryRun;
  final int diskFreeBytes;
  final String displayName;
  final String? importId;
  final String? sourceHash;
  final OfficialAnkiFeatureFlags flags;
  final OfficialAnkiOperationCoordinator? coordinator;

  @override
  State<OfficialAnkiMigrationPreviewPage> createState() =>
      _OfficialAnkiMigrationPreviewPageState();
}

class _OfficialAnkiMigrationPreviewPageState
    extends State<OfficialAnkiMigrationPreviewPage> {
  var _policy = LegacyAnkiSchedulingPolicy.preservePackageScheduling;

  @override
  Widget build(BuildContext context) {
    final unmatched = widget.dryRun.rows
        .where((row) => row.matchState != LegacyAnkiMatchState.matched)
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Legacy migration preview')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(widget.displayName, key: const Key('official-migration-source')),
          Text(
            'cards=${widget.census.cardCount} notes=${widget.census.noteCount}',
            key: const Key('official-migration-counts'),
          ),
          Text(
            'diskFree=${widget.diskFreeBytes}',
            key: const Key('official-migration-disk'),
          ),
          DropdownButton<LegacyAnkiSchedulingPolicy>(
            key: const Key('official-migration-policy'),
            value: _policy,
            onChanged: (value) {
              if (value == null) return;
              setState(() => _policy = value);
            },
            items: [
              for (final policy in LegacyAnkiSchedulingPolicy.values)
                DropdownMenuItem(
                  value: policy,
                  child: Text(policy.userVisibleLabel),
                ),
            ],
          ),
          Text(
            'unmatched=${unmatched.length}',
            key: const Key('official-migration-unmatched'),
          ),
          for (final row in unmatched.take(20))
            Text('#${row.legacyCardId} ${row.matchState.name}'),
          const SizedBox(height: 8),
          const Text(
            'Cutover runs through the W8 census driver after a scheduling '
            'policy is confirmed — this preview cannot switch owner.',
            key: Key('official-migration-cutover-disabled'),
          ),
        ],
      ),
    );
  }
}
