import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_lifecycle_models.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_maintenance.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_import_attempt_dao.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
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
    await tester.binding.setSurfaceSize(const Size(400, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
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
    OfficialAnkiSourceDao(db).upsertSource(
      sourceId: 'src-retiring',
      profileId: paths.profileId,
      sourceHash: 'hash-retiring',
      sourceSize: 1,
      displayName: 'Retiring Deck',
      state: 'retiring',
      backendCommit: 'test',
      nowMillis: 1,
    );
    OfficialAnkiSourceDao(db).upsertSource(
      sourceId: 'src-quarantine',
      profileId: paths.profileId,
      sourceHash: 'hash-quarantine',
      sourceSize: 1,
      displayName: 'Quarantine Deck',
      state: 'quarantined',
      backendCommit: 'test',
      nowMillis: 1,
    );
    OfficialAnkiMaintenanceJobDao(db).enqueue(
      profileId: paths.profileId,
      kind: OfficialAnkiMaintenanceKind.compactCatalog,
      nowMillis: 1,
    );

    final discarded = <String>[];
    final retried = <String>[];
    final quarantined = <String>[];
    final exported = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: OfficialAnkiRepairCenterPage(
          catalog: db,
          paths: paths,
          scanner: _EmptyScanner(),
          onDiscardImport: (id) async => discarded.add(id),
          onRetryCleanup: (id) async => retried.add(id),
          onDeleteQuarantine: (id) async => quarantined.add(id),
          onExportDiagnostics: (payload) async => exported.add(payload),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pending Deck'), findsOneWidget);
    expect(find.text('Cleanup Deck'), findsOneWidget);
    expect(find.text('Retiring Deck'), findsOneWidget);
    expect(find.text('Quarantine Deck'), findsOneWidget);
    expect(find.text(AppStrings.ankiRepairSourceState('pending_cleanup')),
        findsOneWidget);
    expect(find.text(AppStrings.ankiRepairSourceState('retiring')),
        findsOneWidget);
    expect(find.text(AppStrings.ankiRepairJobKind('compact_catalog')),
        findsOneWidget);
    expect(find.text('pending_cleanup'), findsNothing);
    expect(find.text('compact_catalog'), findsNothing);
    expect(find.byKey(const Key('repair-optimize')), findsNothing);
    expect(find.text(AppStrings.ankiRepairMaintenanceJobs), findsOneWidget);

    expect(find.text(AppStrings.ankiPendingContinue), findsNothing);
    expect(find.text(AppStrings.ankiPendingImportTitle), findsWidgets);

    await tester.tap(find.text(AppStrings.ankiPendingDiscard));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.commonOk));
    await tester.pumpAndSettle();
    expect(discarded, ['src-pending']);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('repair-cleanup-src-cleanup')),
        matching: find.text(AppStrings.ankiRepairRetryCleanup),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.commonOk));
    await tester.pumpAndSettle();
    expect(retried, ['src-cleanup']);

    await tester.tap(find.text(AppStrings.ankiRepairDeleteQuarantine));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.commonOk));
    await tester.pumpAndSettle();
    expect(quarantined, ['src-quarantine']);

    await tester.tap(find.byKey(const Key('repair-export')));
    await tester.pumpAndSettle();
    expect(exported, isNotEmpty);
    expect(exported.single.contains('maintenancePending'), isTrue);
  });
}
