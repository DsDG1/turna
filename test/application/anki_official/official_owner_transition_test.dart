// Owner transition authority tests (plan 34 R4 / OS-18): the CourseDatabase
// v21 tables are the single production owner fact source. Covers phase CAS,
// the in-flight unique index, write-fence legal moves, the atomic owner
// commit (no dual-active window), rollback-only-before-commit, and the
// course-scope repair journal.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/data/anki_owner_authority_dao.dart';
import 'package:turna/data/course_database.dart';

import '../../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  late CourseDatabase db;
  late AnkiOwnerAuthorityDao dao;

  Future<AnkiCourseSourceAuthorityRow> seedSource({
    String courseId = 'course-a',
    String sourceId = 'src-abc123',
    String backendKind = 'legacyTurna',
    AnkiSourceVisibility state = AnkiSourceVisibility.active,
    String displayName = 'Deck',
  }) async {
    await dao.upsertSource(
      courseId: courseId,
      profileId: 'default',
      sourceId: sourceId,
      backendKind: backendKind,
      displayName: '$displayName $sourceId',
      sourceHash: 'hash-$sourceId',
      sourceFingerprint: 'fp-$sourceId',
      state: state,
    );
    return (await dao.findByCourseId(courseId))!;
  }

  setUp(() async {
    db = CourseDatabase(NativeDatabase.memory());
    await db.customSelect('SELECT 1').get();
    dao = AnkiOwnerAuthorityDao(db);
  });

  tearDown(() async {
    await db.close();
  });

  group('course source catalog', () {
    test('upsert is idempotent on course_id and keeps one row per source',
        () async {
      await seedSource();
      await seedSource(displayName: 'Deck renamed');
      final rows = await dao.listSources('default');
      expect(rows, hasLength(1));
      expect(rows.single.displayName, 'Deck renamed src-abc123');
      expect(rows.single.writeFence, AnkiWriteFence.open);
      expect(rows.single.ownerGeneration, 0);
    });

    test('visibility commit only works on an existing source row', () async {
      await expectLater(
        dao.commitVisibility(
          courseId: 'missing',
          state: AnkiSourceVisibility.active,
        ),
        throwsA(isA<OwnerAuthorityConflict>()),
      );
    });

    test('visibility commit persists state and projection generation',
        () async {
      await seedSource(state: AnkiSourceVisibility.staging);
      await dao.commitVisibility(
        courseId: 'course-a',
        state: AnkiSourceVisibility.active,
        activeProjectionGeneration: 'gen-1',
      );
      final row = await dao.findByCourseId('course-a');
      expect(row!.state, AnkiSourceVisibility.active);
      expect(row.activeProjectionGeneration, 'gen-1');
    });

    test('activeOnly listing filters staging rows', () async {
      await seedSource(courseId: 'course-a', sourceId: 'src-a');
      await seedSource(
        courseId: 'course-b',
        sourceId: 'src-b',
        state: AnkiSourceVisibility.staging,
      );
      final active = await dao.listSources('default', activeOnly: true);
      expect(active.map((r) => r.sourceId), ['src-a']);
    });
  });

  group('write fence', () {
    test('open → frozen → officialOnly is legal; officialOnly never regresses',
        () async {
      await seedSource();
      await dao.compareAndSetWriteFence(
        courseId: 'course-a',
        expected: AnkiWriteFence.open,
        next: AnkiWriteFence.frozen,
      );
      await dao.compareAndSetWriteFence(
        courseId: 'course-a',
        expected: AnkiWriteFence.frozen,
        next: AnkiWriteFence.officialOnly,
      );
      expect(
        (await dao.findByCourseId('course-a'))!.writeFence,
        AnkiWriteFence.officialOnly,
      );
      // Forbidden move (plan 34 §6.2): re-enabling the Legacy writer after
      // the Official engine owns mutations.
      await expectLater(
        dao.compareAndSetWriteFence(
          courseId: 'course-a',
          expected: AnkiWriteFence.officialOnly,
          next: AnkiWriteFence.open,
        ),
        throwsA(isA<OwnerAuthorityConflict>()),
      );
    });

    test('frozen → open is the rollback receipt move', () async {
      await seedSource();
      await dao.compareAndSetWriteFence(
        courseId: 'course-a',
        expected: AnkiWriteFence.open,
        next: AnkiWriteFence.frozen,
      );
      await dao.compareAndSetWriteFence(
        courseId: 'course-a',
        expected: AnkiWriteFence.frozen,
        next: AnkiWriteFence.open,
      );
      expect(
        (await dao.findByCourseId('course-a'))!.writeFence,
        AnkiWriteFence.open,
      );
    });

    test('CAS fails when the fence already moved', () async {
      await seedSource();
      await dao.compareAndSetWriteFence(
        courseId: 'course-a',
        expected: AnkiWriteFence.open,
        next: AnkiWriteFence.frozen,
      );
      await expectLater(
        dao.compareAndSetWriteFence(
          courseId: 'course-a',
          expected: AnkiWriteFence.open,
          next: AnkiWriteFence.frozen,
        ),
        throwsA(isA<OwnerAuthorityConflict>()),
      );
    });
  });

  group('owner transitions', () {
    test('full happy path advances phase-by-phase with CAS', () async {
      await seedSource();
      final transition = await dao.beginTransition(
        transitionId: 'tr-1',
        profileId: 'default',
        legacyImportId: 'legacy-a',
        officialSourceId: 'src-abc123',
        courseId: 'course-a',
        fromBackend: 'legacyTurna',
        toBackend: 'official',
        policy: 'resetSchedule',
      );
      expect(transition.phase, OwnerTransitionPhase.discovered);

      const path = [
        (
          OwnerTransitionPhase.discovered,
          OwnerTransitionPhase.awaitingUserPolicy
        ),
        (
          OwnerTransitionPhase.awaitingUserPolicy,
          OwnerTransitionPhase.backingUp
        ),
        (
          OwnerTransitionPhase.backingUp,
          OwnerTransitionPhase.importingOfficial
        ),
        (
          OwnerTransitionPhase.importingOfficial,
          OwnerTransitionPhase.verifyingIdentity
        ),
        (
          OwnerTransitionPhase.verifyingIdentity,
          OwnerTransitionPhase.projectionStaging
        ),
        (
          OwnerTransitionPhase.projectionStaging,
          OwnerTransitionPhase.cutoverReady
        ),
        (OwnerTransitionPhase.cutoverReady, OwnerTransitionPhase.frozen),
        (OwnerTransitionPhase.frozen, OwnerTransitionPhase.committing),
      ];
      for (final (from, to) in path) {
        await dao.advancePhase(transitionId: 'tr-1', from: from, to: to);
      }
      expect(
        (await dao.transitionById('tr-1'))!.phase,
        OwnerTransitionPhase.committing,
      );

      // Freeze is a real behavior: the fence must be frozen before commit.
      await dao.compareAndSetWriteFence(
        courseId: 'course-a',
        expected: AnkiWriteFence.open,
        next: AnkiWriteFence.frozen,
      );
      await dao.commitOwnership(transitionId: 'tr-1', courseId: 'course-a');

      final source = await dao.findByCourseId('course-a');
      expect(source!.backendKind, 'official');
      expect(source.ownerGeneration, 1);
      expect(source.writeFence, AnkiWriteFence.officialOnly);
      expect(source.lastTransitionId, 'tr-1');
      final after = await dao.transitionById('tr-1');
      expect(after!.phase, OwnerTransitionPhase.observing);
      expect(after.generation, 1);
    });

    test('phase CAS rejects stale advances (crash-resume discipline)',
        () async {
      await seedSource();
      await dao.beginTransition(
        transitionId: 'tr-2',
        profileId: 'default',
        officialSourceId: 'src-abc123',
        courseId: 'course-a',
        fromBackend: 'legacyTurna',
        toBackend: 'official',
        policy: 'resetSchedule',
      );
      // A replayed/stale advance must fail loudly instead of double-moving.
      await expectLater(
        dao.advancePhase(
          transitionId: 'tr-2',
          from: OwnerTransitionPhase.frozen,
          to: OwnerTransitionPhase.committing,
        ),
        throwsA(isA<OwnerAuthorityConflict>()),
      );
    });

    test('only one in-flight transition per course', () async {
      await seedSource();
      await dao.beginTransition(
        transitionId: 'tr-a',
        profileId: 'default',
        officialSourceId: 'src-abc123',
        courseId: 'course-a',
        fromBackend: 'legacyTurna',
        toBackend: 'official',
        policy: 'resetSchedule',
      );
      await expectLater(
        dao.beginTransition(
          transitionId: 'tr-b',
          profileId: 'default',
          officialSourceId: 'src-abc123',
          courseId: 'course-a',
          fromBackend: 'legacyTurna',
          toBackend: 'official',
          policy: 'resetSchedule',
        ),
        throwsA(anything),
      );
      // A second course may still start its own transition.
      await seedSource(courseId: 'course-b', sourceId: 'src-other');
      await dao.beginTransition(
        transitionId: 'tr-c',
        profileId: 'default',
        officialSourceId: 'src-other',
        courseId: 'course-b',
        fromBackend: 'legacyTurna',
        toBackend: 'official',
        policy: 'resetSchedule',
      );
    });

    test('a new transition may start after the previous one completed',
        () async {
      await seedSource();
      final first = await dao.beginTransition(
        transitionId: 'tr-done',
        profileId: 'default',
        officialSourceId: 'src-abc123',
        courseId: 'course-a',
        fromBackend: 'legacyTurna',
        toBackend: 'official',
        policy: 'resetSchedule',
      );
      await dao.advancePhase(
        transitionId: 'tr-done',
        from: first.phase,
        to: OwnerTransitionPhase.complete,
      );
      await dao.beginTransition(
        transitionId: 'tr-next',
        profileId: 'default',
        officialSourceId: 'src-abc123',
        courseId: 'course-a',
        fromBackend: 'official',
        toBackend: 'official',
        policy: 'rebuildProjection',
      );
    });

    test('owner commit refuses a transition not in committing phase', () async {
      await seedSource();
      await dao.beginTransition(
        transitionId: 'tr-early',
        profileId: 'default',
        officialSourceId: 'src-abc123',
        courseId: 'course-a',
        fromBackend: 'legacyTurna',
        toBackend: 'official',
        policy: 'resetSchedule',
      );
      await expectLater(
        dao.commitOwnership(transitionId: 'tr-early', courseId: 'course-a'),
        throwsA(isA<OwnerAuthorityConflict>()),
      );
      // Nothing moved: no dual-active window was opened.
      final source = await dao.findByCourseId('course-a');
      expect(source!.backendKind, 'legacyTurna');
      expect(source.writeFence, AnkiWriteFence.open);
    });

    test('owner commit is atomic: a missing source row changes nothing',
        () async {
      await seedSource();
      final transition = await dao.beginTransition(
        transitionId: 'tr-x',
        profileId: 'default',
        officialSourceId: 'src-abc123',
        courseId: 'course-a',
        fromBackend: 'legacyTurna',
        toBackend: 'official',
        policy: 'resetSchedule',
      );
      OwnerTransitionPhase phase = transition.phase;
      for (final next in [
        OwnerTransitionPhase.awaitingUserPolicy,
        OwnerTransitionPhase.backingUp,
        OwnerTransitionPhase.importingOfficial,
        OwnerTransitionPhase.verifyingIdentity,
        OwnerTransitionPhase.projectionStaging,
        OwnerTransitionPhase.cutoverReady,
        OwnerTransitionPhase.frozen,
        OwnerTransitionPhase.committing,
      ]) {
        await dao.advancePhase(transitionId: 'tr-x', from: phase, to: next);
        phase = next;
      }
      // Commit against the wrong course id must fail...
      await expectLater(
        dao.commitOwnership(transitionId: 'tr-x', courseId: 'wrong'),
        throwsA(isA<OwnerAuthorityConflict>()),
      );
      // ...and leave both the transition and the source untouched.
      expect(
        (await dao.transitionById('tr-x'))!.phase,
        OwnerTransitionPhase.committing,
      );
      final source = await dao.findByCourseId('course-a');
      expect(source!.backendKind, 'legacyTurna');
    });

    test('rollback restores legacy before commit and refuses after commit',
        () async {
      await seedSource();
      final transition = await dao.beginTransition(
        transitionId: 'tr-rb',
        profileId: 'default',
        officialSourceId: 'src-abc123',
        courseId: 'course-a',
        fromBackend: 'legacyTurna',
        toBackend: 'official',
        policy: 'resetSchedule',
      );
      await dao.compareAndSetWriteFence(
        courseId: 'course-a',
        expected: AnkiWriteFence.open,
        next: AnkiWriteFence.frozen,
      );
      await dao.advancePhase(
        transitionId: 'tr-rb',
        from: transition.phase,
        to: OwnerTransitionPhase.rollbackPending,
      );
      await dao.rollbackToLegacy(
        transitionId: 'tr-rb',
        courseId: 'course-a',
      );
      final rolledBack = await dao.findByCourseId('course-a');
      expect(rolledBack!.backendKind, 'legacyTurna');
      expect(rolledBack.writeFence, AnkiWriteFence.open);
      expect(
        (await dao.transitionById('tr-rb'))!.phase,
        OwnerTransitionPhase.rolledBackLegacy,
      );

      // After a successful owner commit, rollback must be refused.
      final second = await dao.beginTransition(
        transitionId: 'tr-commit',
        profileId: 'default',
        officialSourceId: 'src-abc123',
        courseId: 'course-a',
        fromBackend: 'legacyTurna',
        toBackend: 'official',
        policy: 'resetSchedule',
      );
      OwnerTransitionPhase phase = second.phase;
      for (final next in [
        OwnerTransitionPhase.awaitingUserPolicy,
        OwnerTransitionPhase.backingUp,
        OwnerTransitionPhase.importingOfficial,
        OwnerTransitionPhase.verifyingIdentity,
        OwnerTransitionPhase.projectionStaging,
        OwnerTransitionPhase.cutoverReady,
        OwnerTransitionPhase.frozen,
        OwnerTransitionPhase.committing,
      ]) {
        await dao.advancePhase(
            transitionId: 'tr-commit', from: phase, to: next);
        phase = next;
      }
      await dao.commitOwnership(
          transitionId: 'tr-commit', courseId: 'course-a');
      await expectLater(
        dao.rollbackToLegacy(transitionId: 'tr-commit', courseId: 'course-a'),
        throwsA(isA<OwnerAuthorityConflict>()),
      );
      // Ownership survived the illegal rollback attempt.
      expect((await dao.findByCourseId('course-a'))!.backendKind, 'official');
    });

    test('inFlightTransition finds the live transition only', () async {
      await seedSource();
      final transition = await dao.beginTransition(
        transitionId: 'tr-live',
        profileId: 'default',
        officialSourceId: 'src-abc123',
        courseId: 'course-a',
        fromBackend: 'legacyTurna',
        toBackend: 'official',
        policy: 'resetSchedule',
      );
      expect(
        (await dao.inFlightTransition('course-a'))!.transitionId,
        'tr-live',
      );
      await dao.advancePhase(
        transitionId: 'tr-live',
        from: transition.phase,
        to: OwnerTransitionPhase.complete,
      );
      expect(await dao.inFlightTransition('course-a'), isNull);
    });

    test('error codes are journaled on the transition row', () async {
      await seedSource();
      final transition = await dao.beginTransition(
        transitionId: 'tr-err',
        profileId: 'default',
        officialSourceId: 'src-abc123',
        courseId: 'course-a',
        fromBackend: 'legacyTurna',
        toBackend: 'official',
        policy: 'resetSchedule',
      );
      await dao.advancePhase(
        transitionId: 'tr-err',
        from: transition.phase,
        to: OwnerTransitionPhase.backingUp,
        errorCode: 'backup-io-14',
      );
      expect(
        (await dao.transitionById('tr-err'))!.lastErrorCode,
        'backup-io-14',
      );
    });
  });

  group('course scope repair journal', () {
    test('records repairs and codec version round-trips', () async {
      await dao.recordScopeRepair(
        oldCourseScope: 'anki:src',
        newCourseScope: 'course-scope:v1:official:default:src-abc123',
        oldCourseOrder: '["anki:src"]',
        newCourseOrder: '["course-scope:v1:official:default:src-abc123"]',
        reason: 'truncated-legacy-preference',
      );
      final rows = await db
          .customSelect('SELECT * FROM course_scope_repair_journal')
          .get();
      expect(rows, hasLength(1));
      expect(rows.single.read<String>('reason'), 'truncated-legacy-preference');

      expect(await dao.scopeCodecVersion(), isNull);
      await dao.setScopeCodecVersion(1);
      expect(await dao.scopeCodecVersion(), 1);
      await dao.setScopeCodecVersion(1); // idempotent
      expect(await dao.scopeCodecVersion(), 1);
    });
  });
}
