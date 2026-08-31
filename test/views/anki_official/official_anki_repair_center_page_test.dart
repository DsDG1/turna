import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_lifecycle_models.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_maintenance.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_import_attempt_dao.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/maintenance/official_storage_optimize_service.dart';
import 'package:turna/application/maintenance/storage_inventory_service.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/anki_official/official_anki_repair_center_page.dart';

import '../../helpers/in_memory_course_db.dart';

class _EmptyScanner implements StorageInventoryService {
  @override
  Future<StorageInventoryReport> scan() async => StorageInventoryReport(
        artifacts: const [],
        databaseWalBytes: 0,
        databaseShmBytes: 0,
        freelistBytes: 0,
        aiCacheEntries: 0,
        scannedAt: DateTime(2026, 8, 31),
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  testWidgets('missing catalog shows empty state', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: OfficialAnkiRepairCenterPage()),
    );
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.ankiRepairCenterEmptyCatalog), findsOneWidget);
  });

  testWidgets('whitelist actions fire after confirm', (tester) async {
    final db = OfficialAnkiDatabase.memory();
    addTearDown(db.close);
    final root = Directory.systemTemp.createTempSync('turna-repair-ui-');
    addTearDown(() => root.deleteSync(recursive: true));
    final paths = OfficialAnkiPaths(
      profileId: 'profile-repair-01',
      profileRoot: root,
    );
    OfficialAnkiSourceDao(db).upsertSource(
      sourceId: 'src-pending',
      profileId: paths.profileId,
      sourceHash: 'hash-pending',
      sourceSize: 1,
      displayName: 'Pending Deck',
      state: 'staging',
      backendCommit: 'test',
      nowMillis: 1,
    );
    OfficialAnkiImportAttemptDao(db).insert(
      attemptId: 'att-pending',
      sourceId: 'src-pending',
      requestId: 'req-pending',
      state: 'preview_ready',
      nowMillis: 1,
      phase: 'preview_ready',
    );
    OfficialAnkiSourceDao(db).upsertSource(
      sourceId: 'src-cleanup',
      profileId: paths.profileId,
      sourceHash: 'hash-cleanup',
      sourceSize: 1,
      displayName: 'Cleanup Deck',
      state: 'pending_cleanup',
      backendCommit: 'test',
      nowMillis: 1,
    );
    OfficialAnkiMaintenanceJobDao(db).enqueue(
      profileId: paths.profileId,
      kind: OfficialAnkiMaintenanceKind.compactCatalog,
      nowMillis: 1,
    );

    final continued = <String>[];
    final discarded = <String>[];
    final retried = <String>[];
    final exported = <String>[];
    var optimizeForce = false;

    await tester.pumpWidget(
      MaterialApp(
        home: OfficialAnkiRepairCenterPage(
          catalog: db,
          paths: paths,
          scanner: _EmptyScanner(),
          onContinueImport: (id) async => continued.add(id),
          onDiscardImport: (id) async => discarded.add(id),
          onRetryCleanup: (id) async => retried.add(id),
          onExportDiagnostics: (payload) async => exported.add(payload),
          optimizeDatabases: ({required bool force}) async {
            optimizeForce = force;
            return const OfficialStorageOptimizeResult(
              ok: true,
              completedJobs: 1,
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pending Deck'), findsOneWidget);
    expect(find.text('Cleanup Deck'), findsOneWidget);
    expect(find.text(AppStrings.ankiRepairMaintenanceJobs), findsOneWidget);

    await tester.tap(find.text(AppStrings.ankiPendingContinue));
    await tester.pumpAndSettle();
    expect(continued, ['src-pending']);

    await tester.tap(find.text(AppStrings.ankiPendingDiscard));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.commonOk));
    await tester.pumpAndSettle();
    expect(discarded, ['src-pending']);

    await tester.tap(find.text(AppStrings.ankiRepairRetryCleanup));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.commonOk));
    await tester.pumpAndSettle();
    expect(retried, ['src-cleanup']);

    await tester.tap(find.byKey(const Key('repair-optimize')));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.commonOk));
    await tester.pumpAndSettle();
    expect(optimizeForce, isTrue);

    await tester.tap(find.byKey(const Key('repair-export')));
    await tester.pumpAndSettle();
    expect(exported, isNotEmpty);
    expect(exported.single.contains('maintenancePending'), isTrue);
  });
}
