// Legacy write-fence matrix tests (plan 34 R4-1 / OS-17): after a freeze,
// EVERY ordinary Legacy mutator is rejected; cleanup tokens and rollback
// state are the only escape hatches, and they are scoped and one-shot.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/data/anki_legacy_write_fence.dart';
import 'package:turna/data/anki_note_dao.dart';
import 'package:turna/data/anki_owner_authority_dao.dart';
import 'package:turna/data/course_database.dart';

import '../../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  late CourseDatabase db;
  late AnkiOwnerAuthorityDao dao;
  late AnkiNoteDao noteDao;

  const courseId = 'course-src-a';
  const srcA = 'src-4f8b2c9d1e';

  setUp(() async {
    db = CourseDatabase(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();
    dao = AnkiOwnerAuthorityDao(db);
    noteDao = AnkiNoteDao(db);
    await dao.upsertSource(
      courseId: courseId,
      profileId: 'profile-default-01',
      sourceId: srcA,
      backendKind: 'legacyTurna',
      displayName: 'Deck A',
      sourceHash: 'hash-a',
      sourceFingerprint: 'fp-a',
      state: AnkiSourceVisibility.active,
    );
    LegacyWriteFence.instance.debugReset();
    await LegacyWriteFence.instance.loadFrom(db);
  });

  tearDown(() async {
    LegacyWriteFence.instance.debugReset();
    await db.close();
  });

  Future<void> freeze() async {
    await dao.compareAndSetWriteFence(
      courseId: courseId,
      expected: AnkiWriteFence.open,
      next: AnkiWriteFence.frozen,
    );
  }

  // Doc 38 P1-B: the writer matrix shrank to the surviving mutators
  // (setCardState / deleteByImport); rows are seeded with raw SQL.
  Future<void> seedCard(String importId, int cardId) =>
      db.customStatement(
        'INSERT INTO anki_cards_meta (import_id, card_id, note_id, word_id) '
        "VALUES (?, ?, 1, 'anki-$importId-c$cardId')",
        [importId, cardId],
      );

  test('open fence allows every ordinary mutator', () async {
    await seedCard(srcA, 1);
    await noteDao.setCardState(srcA, 1, suspended: true);
    await noteDao.deleteByImport(srcA);
  });

  test('frozen rejects every ordinary Legacy mutator (the full matrix)',
      () async {
    await seedCard(srcA, 1);
    await noteDao.setCardState(srcA, 1, buriedUntil: 10);
    await freeze();

    Future<void> expectDenied(Future<void> Function() op, String name) async {
      try {
        await op();
        fail('$name must be denied while frozen');
      } on LegacyWriteDenied {
        // expected
      }
    }

    await expectDenied(
      () => noteDao.setCardState(srcA, 1, suspended: true),
      'setCardState',
    );
    await expectDenied(
      () => noteDao.deleteByImport(srcA),
      'deleteByImport',
    );
  });

  test('unfenced sources keep writing while a sibling is frozen', () async {
    await dao.upsertSource(
      courseId: 'course-src-b',
      profileId: 'profile-default-01',
      sourceId: 'src-b',
      backendKind: 'legacyTurna',
      displayName: 'Deck B',
      sourceHash: 'hash-b',
      sourceFingerprint: 'fp-b',
      state: AnkiSourceVisibility.active,
    );
    await freeze();

    // Source B is untouched by A's freeze.
    await db.customStatement(
      "INSERT INTO anki_imports (import_id, source_path, source_hash, "
      "imported_at) VALUES ('src-b', '/tmp/b.apkg', 'hash-b2', 1700000000)",
    );
    await db.customStatement(
      'INSERT INTO anki_cards_meta (import_id, card_id, note_id, word_id) '
      "VALUES ('src-b', 1, 1, 'anki-src-b-c1')",
    );
    await noteDao.setCardState('src-b', 1, suspended: true);
  });

  test('migration cleanup requires a live, matching, unconsumed token',
      () async {
    await freeze();
    final fence = LegacyWriteFence.instance;

    // No token → denied.
    expect(
      () => fence.assertAllowed(
        importId: srcA,
        operation: 'deleteByImport',
        intent: LegacyWriteIntent.migrationCleanup,
        courseId: courseId,
      ),
      throwsA(isA<LegacyWriteDenied>()),
    );

    // Wrong course → denied.
    final other = fence.issueCleanupToken('course-other');
    expect(
      () => fence.assertAllowed(
        importId: srcA,
        operation: 'deleteByImport',
        intent: LegacyWriteIntent.migrationCleanup,
        cleanupToken: other,
        courseId: courseId,
      ),
      throwsA(isA<LegacyWriteDenied>()),
    );

    // Right token → allowed, once.
    final token = fence.issueCleanupToken(courseId);
    fence.assertAllowed(
      importId: srcA,
      operation: 'deleteByImport',
      intent: LegacyWriteIntent.migrationCleanup,
      cleanupToken: token,
      courseId: courseId,
    );
    token.consumed = true;
    expect(
      () => fence.assertAllowed(
        importId: srcA,
        operation: 'deleteByImport',
        intent: LegacyWriteIntent.migrationCleanup,
        cleanupToken: token,
        courseId: courseId,
      ),
      throwsA(isA<LegacyWriteDenied>()),
    );
  });

  test('rollbackRestore works only while rollback is pending', () async {
    await freeze();
    final fence = LegacyWriteFence.instance;

    expect(
      () => fence.assertAllowed(
        importId: srcA,
        operation: 'rollbackRestore',
        intent: LegacyWriteIntent.rollbackRestore,
        courseId: courseId,
      ),
      throwsA(isA<LegacyWriteDenied>()),
      reason: 'rollback restore before beginRollback must be denied',
    );

    fence.beginRollback(courseId);
    fence.assertAllowed(
      importId: srcA,
      operation: 'rollbackRestore',
      intent: LegacyWriteIntent.rollbackRestore,
      courseId: courseId,
    );
    fence.endRollback(courseId);

    expect(
      () => fence.assertAllowed(
        importId: srcA,
        operation: 'rollbackRestore',
        intent: LegacyWriteIntent.rollbackRestore,
        courseId: courseId,
      ),
      throwsA(isA<LegacyWriteDenied>()),
    );
  });

  test('migrationRead declared on a mutation is always an error', () {
    expect(
      () => LegacyWriteFence.instance.assertAllowed(
        importId: srcA,
        operation: 'anything',
        intent: LegacyWriteIntent.migrationRead,
      ),
      throwsA(isA<StateError>()),
    );
  });

  test(
      'authority transitions update the registry and fence linked legacy '
      'import ids', () async {
    await dao.upsertSource(
      courseId: 'anki-legacy-imp-9',
      profileId: 'profile-default-01',
      sourceId: 'legacy-imp-9',
      backendKind: 'legacyTurna',
      displayName: 'Legacy deck',
      sourceHash: 'hash-legacy',
      sourceFingerprint: 'fp-legacy',
      state: AnkiSourceVisibility.active,
    );
    // A transition linking a legacy import id to the official source.
    await dao.beginTransition(
      transitionId: 'tr-1',
      profileId: 'profile-default-01',
      legacyImportId: 'legacy-imp-9',
      officialSourceId: srcA,
      courseId: courseId,
      fromBackend: 'legacyTurna',
      toBackend: 'official',
      policy: 'resetSchedule',
    );
    await freeze();

    // The LEGACY id is fenced through its link.
    expect(
      () => LegacyWriteFence.instance.assertAllowed(
        importId: 'legacy-imp-9',
        operation: 'answer',
      ),
      throwsA(isA<LegacyWriteDenied>()),
    );
    // Owner commit flips the fence to officialOnly — still fenced.
    await dao.advancePhase(
      transitionId: 'tr-1',
      from: OwnerTransitionPhase.discovered,
      to: OwnerTransitionPhase.committing,
    );
    await dao.commitOwnership(
      transitionId: 'tr-1',
      courseId: courseId,
      legacyCourseId: 'anki-legacy-imp-9',
    );
    expect(
        LegacyWriteFence.instance.fenceFor(srcA), AnkiWriteFence.officialOnly);
    expect(
      () => LegacyWriteFence.instance.assertAllowed(
        importId: srcA,
        operation: 'answer',
      ),
      throwsA(isA<LegacyWriteDenied>()),
    );
    expect(
      (await dao.findByCourseId('anki-legacy-imp-9'))?.state,
      AnkiSourceVisibility.retired,
    );
  });
}
