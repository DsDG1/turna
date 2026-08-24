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

  test('open fence allows every ordinary mutator', () async {
    await noteDao.replaceImportIssues(srcA, const []);
    await noteDao.replaceDeckIndex(srcA, const []);
    await noteDao.replacePracticeProjections(srcA, const []);
  });

  test('frozen rejects every ordinary Legacy mutator (the full matrix)',
      () async {
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
      () => noteDao.replaceDeckIndex(srcA, const []),
      'replaceDeckIndex',
    );
    await expectDenied(
      () => noteDao.replaceImportIssues(srcA, const []),
      'replaceImportIssues',
    );
    await expectDenied(
      () => noteDao.replacePracticeProjections(srcA, const []),
      'replacePracticeProjections',
    );
    await expectDenied(
      () => noteDao.upsertNotetype(
        AnkiNotetypeRecord(importId: srcA, mid: 1),
      ),
      'upsertNotetype',
    );
    await expectDenied(
      () => noteDao.upsertNote(
        AnkiNoteRecord(importId: srcA, noteId: 1, mid: 1, fields: const []),
      ),
      'upsertNote',
    );
    await expectDenied(
      () => noteDao.deleteByImport(srcA),
      'deleteByImport',
    );
    await expectDenied(
      () => noteDao.upsertNotetypeBatch(
        [AnkiNotetypeRecord(importId: srcA, mid: 2)],
      ),
      'upsertNotetypeBatch',
    );
    await expectDenied(
      () => noteDao.upsertNoteBatch(
        [AnkiNoteRecord(importId: srcA, noteId: 2, mid: 1, fields: const [])],
      ),
      'upsertNoteBatch',
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
    await noteDao.replaceImportIssues('src-b', const []);
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
    LegacyWriteFence.instance.debugReset();
    await LegacyWriteFence.instance.loadFrom(db);

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
    await dao.commitOwnership(transitionId: 'tr-1', courseId: courseId);
    expect(
        LegacyWriteFence.instance.fenceFor(srcA), AnkiWriteFence.officialOnly);
    expect(
      () => LegacyWriteFence.instance.assertAllowed(
        importId: srcA,
        operation: 'answer',
      ),
      throwsA(isA<LegacyWriteDenied>()),
    );
  });
}
