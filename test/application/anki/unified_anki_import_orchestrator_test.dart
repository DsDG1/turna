import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki/card_introduction_eligibility.dart';
import 'package:turna/application/anki/unified_anki_import_orchestrator.dart';
import 'package:turna/data/anki_unification_dao.dart';
import 'package:turna/di/injection.dart';

import '../../helpers/in_memory_course_db.dart';

void main() {
  late UnifiedAnkiImportOrchestrator orchestrator;

  setUp(() {
    orchestrator = UnifiedAnkiImportOrchestrator.instance;
    orchestrator.reset();
  });

  tearDown(() => orchestrator.reset());

  group('UnifiedAnkiImportOrchestrator', () {
    test('Official-capable path writes no Turna SRS and reconciles 1:1',
        () async {
      final persisted = <UnifiedAnkiImportRequest>[];
      orchestrator.persistIdentity = (request) async {
        persisted.add(request);
      };
      final result = await orchestrator.importPackage(
        const UnifiedAnkiImportRequest(
          importId: 'imp-official',
          sourceHash: 'hash-a',
          canonicalCardIds: [10, 11, 12],
          persistedOwnerIsOfficial: true,
        ),
      );
      expect(result.wroteTurnaSrs, isFalse);
      expect(result.noOp, isFalse);
      expect(result.canonicalCardCount, 3);
      expect(result.placementCount, 3);
      expect(result.presentationCount, 3);
      expect(result.cardinalityOk, isTrue);
      expect(result.turnaSrsWordIds, isEmpty);
      expect(orchestrator.turnaSrsWordIds, isEmpty);
      expect(persisted, hasLength(1));
      expect(persisted.single.canonicalCardIds, [10, 11, 12]);
    });

    test('legacy path still registers Turna SRS ids 1:1', () async {
      // Real in-memory unification DAO: the placement/presentation counts are
      // now measured from the database, so cardinalityOk is a real 1:1 check
      // instead of echoing the request.
      final db = emptyInMemoryCourseDatabase();
      getIt.registerSingleton<AnkiUnificationDao>(AnkiUnificationDao(db));
      addTearDown(() async {
        await getIt.reset();
        await db.close();
      });

      final result = await orchestrator.importPackage(
        const UnifiedAnkiImportRequest(
          importId: 'imp-legacy',
          sourceHash: 'hash-legacy',
          canonicalCardIds: [1, 2],
          persistedOwnerIsOfficial: false,
        ),
      );
      expect(result.wroteTurnaSrs, isTrue);
      expect(result.turnaSrsWordIds, {
        'anki-imp-legacy-c1',
        'anki-imp-legacy-c2',
      });
      expect(result.cardinalityOk, isTrue);
      expect(orchestrator.placementCount('imp-legacy'), 2);
    });

    test('in-place reimport replaces projection identity but keeps history',
        () async {
      final db = emptyInMemoryCourseDatabase();
      addTearDown(db.close);
      final dao = AnkiUnificationDao(db);
      final local = UnifiedAnkiImportOrchestrator();
      const importId = 'imp-replace';
      final courseId =
          CardIntroductionEligibility.courseIdForLegacyImport(importId);
      const first = UnifiedAnkiImportRequest(
        importId: importId,
        sourceHash: 'hash-old',
        canonicalCardIds: [1, 2],
        persistedOwnerIsOfficial: false,
        reuseExistingIdentity: false,
      );
      await local.begin(first);
      await local.finalize(first, unificationDao: dao);
      await db.customStatement(
        '''
        INSERT INTO anki_card_introduction_states (
          course_id, source_id, card_id, status, version
        ) VALUES (?, ?, ?, 'introduced', 1)
        ''',
        [courseId, importId, 1],
      );

      await db.transaction(() async {
        await dao.deleteProjectionIdentityByCourseId(courseId);
        const replacement = UnifiedAnkiImportRequest(
          importId: importId,
          sourceHash: 'hash-new',
          canonicalCardIds: [2, 3],
          persistedOwnerIsOfficial: false,
          reuseExistingIdentity: false,
        );
        await local.begin(replacement);
        final written = await local.finalize(
          replacement,
          unificationDao: dao,
        );
        expect(written.placements, 2);
        expect(written.presentations, 2);
      });

      final placements = await db.customSelect(
        'SELECT card_id, source_fingerprint '
        'FROM anki_course_card_placements WHERE course_id = ? '
        'ORDER BY card_id',
        variables: [Variable.withString(courseId)],
      ).get();
      expect(placements.map((row) => row.read<int>('card_id')), [2, 3]);
      expect(
        placements.map((row) => row.read<String>('source_fingerprint')),
        everyElement('hash-new'),
      );
      final history = await db.customSelect(
        'SELECT COUNT(*) AS n FROM anki_card_introduction_states '
        "WHERE course_id = ? AND status = 'introduced'",
        variables: [Variable.withString(courseId)],
      ).getSingle();
      expect(history.read<int>('n'), 1);
    });

    test('same source hash second import is a no-op (persisted inventory)',
        () async {
      // The dedup authority is the persisted inventory: the seam below
      // simulates rows that survive across imports.
      final persistedHashes = <String>{};
      orchestrator.lookupByHash =
          (hash) async => persistedHashes.contains(hash);
      orchestrator.persistIdentity = (request) async {
        persistedHashes.add(request.sourceHash);
      };
      const request = UnifiedAnkiImportRequest(
        importId: 'imp-same',
        sourceHash: 'hash-same',
        canonicalCardIds: [21, 22, 23, 24],
        persistedOwnerIsOfficial: true,
      );
      final first = await orchestrator.importPackage(request);
      expect(first.noOp, isFalse);
      expect(first.canonicalCardCount, 4);

      final second = await orchestrator.importPackage(
        const UnifiedAnkiImportRequest(
          importId: 'imp-same',
          sourceHash: 'hash-same',
          canonicalCardIds: [21, 22, 23, 24, 99],
          persistedOwnerIsOfficial: true,
        ),
      );
      expect(second.noOp, isTrue);
      expect(second.wroteTurnaSrs, isFalse);
      expect(second.canonicalCardCount, 4);
      expect(second.placementCount, 4);
      expect(second.presentationCount, 4);
      expect(orchestrator.placementCount('imp-same'), 4);
    });

    test('delete then re-import in the same process recreates real data',
        () async {
      // Phase 0 regression: the persisted inventory is deleted and the
      // orchestrator memory is invalidated; the same process must be able to
      // import the identical package again instead of returning a fake
      // "already imported" summary.
      final persistedHashes = <String>{};
      orchestrator.lookupByHash =
          (hash) async => persistedHashes.contains(hash);
      final persisted = <UnifiedAnkiImportRequest>[];
      orchestrator.persistIdentity = (request) async {
        persisted.add(request);
        persistedHashes.add(request.sourceHash);
      };

      const request = UnifiedAnkiImportRequest(
        importId: 'imp-re',
        sourceHash: 'hash-re',
        canonicalCardIds: [7, 8, 9],
        persistedOwnerIsOfficial: false,
      );
      final first = await orchestrator.importPackage(request);
      expect(first.noOp, isFalse);
      expect(persisted, hasLength(1));

      // Duplicate submission while the complete import still exists: no-op.
      final dup = await orchestrator.importPackage(request);
      expect(dup.noOp, isTrue);
      expect(persisted, hasLength(1));

      // Uninstall: persisted rows gone, process caches invalidated.
      persistedHashes.remove(request.sourceHash);
      persisted.clear();
      orchestrator.invalidate(importId: request.importId);
      expect(orchestrator.turnaSrsWordIds, isEmpty);
      expect(orchestrator.placementCount('imp-re'), 0);

      final second = await orchestrator.importPackage(request);
      expect(second.noOp, isFalse, reason: 're-import after delete must run');
      expect(second.cardinalityOk, isTrue);
      expect(second.wroteTurnaSrs, isTrue,
          reason: 'legacy path re-registers Turna SRS ids');
      expect(persisted, hasLength(1));
      expect(orchestrator.turnaSrsWordIds, contains('anki-imp-re-c7'));
    });

    test('a failed import does not block retrying the same hash', () async {
      const request = UnifiedAnkiImportRequest(
        importId: 'imp-fail',
        sourceHash: 'hash-fail',
        canonicalCardIds: [1],
        persistedOwnerIsOfficial: true,
      );
      orchestrator.persistIdentity = (_) async {};
      final started = await orchestrator.begin(request);
      expect(started.noOp, isFalse);
      // The import task failed before finalize: invalidate releases the
      // in-flight key so a retry is accepted.
      orchestrator.invalidate(importId: request.importId);
      final retry = await orchestrator.begin(request);
      expect(retry.noOp, isFalse);
    });

    test('two concurrent begins for the same hash are rejected', () async {
      const request = UnifiedAnkiImportRequest(
        importId: 'imp-conc',
        sourceHash: 'hash-conc',
        canonicalCardIds: [1, 2],
        persistedOwnerIsOfficial: true,
      );
      final started = await orchestrator.begin(request);
      expect(started.noOp, isFalse);
      await expectLater(
        orchestrator.begin(request),
        throwsStateError,
        reason: 'double submission of one source must not double-write',
      );
      await orchestrator.finalize(request);
      // After the task ends the key is released; the persisted inventory
      // (absent here) decides the next begin.
      final again = await orchestrator.begin(request);
      expect(again.noOp, isFalse);
    });

    test('source key stays reserved until identity persistence finishes',
        () async {
      const request = UnifiedAnkiImportRequest(
        importId: 'imp-finalizing',
        sourceHash: 'hash-finalizing',
        canonicalCardIds: [1],
        persistedOwnerIsOfficial: true,
      );
      final persistStarted = Completer<void>();
      final releasePersist = Completer<void>();
      orchestrator.persistIdentity = (_) async {
        persistStarted.complete();
        await releasePersist.future;
      };
      await orchestrator.begin(request);
      final finalizing = orchestrator.finalize(request);
      await persistStarted.future;

      await expectLater(orchestrator.begin(request), throwsStateError);

      releasePersist.complete();
      await finalizing;
      expect((await orchestrator.begin(request)).noOp, isFalse);
    });

    test('lookupByHash same-hash begin skips persist', () async {
      orchestrator.lookupByHash = (hash) async => hash == 'disk-hash';
      var persisted = 0;
      orchestrator.persistIdentity = (_) async {
        persisted++;
      };
      final result = await orchestrator.begin(
        const UnifiedAnkiImportRequest(
          importId: 'imp-disk',
          sourceHash: 'disk-hash',
          canonicalCardIds: [1, 2, 3],
          persistedOwnerIsOfficial: true,
        ),
      );
      expect(result.noOp, isTrue);
      expect(result.wroteTurnaSrs, isFalse);
      expect(persisted, 0);
    });

  });
}
