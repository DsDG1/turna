import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki/anki_study_session_host.dart';
import 'package:turna/application/anki/card_introduction_store.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/anki/card_introduction_state.dart';
import 'package:turna/domain/anki/card_presentation.dart';
import 'package:turna/domain/anki/study_models.dart';
import 'package:turna/domain/review/recall_outcome.dart';

void main() {
  const profile = 'profile-default-01';
  const sourceId = 'src-course';
  const courseId = 'official-anki-src-course';
  const lessonId = 'official-anki-src-course-l1-p0';

  CanonicalCardKey officialKey(int id) => CanonicalCardKey(
        backend: AnkiBackendKind.official,
        profileId: profile,
        sourceId: sourceId,
        cardId: id,
      );

  FlipCardPresentation flip(CanonicalCardKey key) => FlipCardPresentation(
        cardKey: key,
        frontText: 'front',
        backText: 'back',
        sourceFingerprint: 'lesson',
      );

  group('Official course practice + introduction', () {
    test('itemForCourse uses practice / none ledger / marksIntroduced', () {
      final item = AnkiStudySessionHost.itemForCourse(
        key: officialKey(7),
        presentation: flip(officialKey(7)),
        courseId: courseId,
        placementId: lessonId,
      );
      expect(item.mode, StudyMode.practice);
      expect(item.ledgerOwner, StudyLedgerOwner.none);
      expect(item.capabilities.writesLedger, isFalse);
      expect(item.capabilities.marksIntroduced, isTrue);
    });

    test('course practice does not mutate Official scheduler ledger', () async {
      final official = _CountingLedger(owner: StudyLedgerOwner.officialAnki);
      final turna = _CountingLedger(owner: StudyLedgerOwner.turnaFsrs);
      final intro = _InMemoryIntroductionRepository();
      final host = AnkiStudySessionHost(
        resolver: StudyLedgerResolver(official: official, turna: turna),
        introductionRepository: intro,
      );
      final key = officialKey(3);
      final controller = await host.driveFlip(
        item: AnkiStudySessionHost.itemForCourse(
          key: key,
          presentation: flip(key),
          courseId: courseId,
          placementId: lessonId,
        ),
        outcome: RecallOutcome.remembered,
      );

      expect(official.commits, 0);
      expect(turna.commits, 0);
      expect(controller.lastReceipt?.ledgerOwner, StudyLedgerOwner.none);
      expect(controller.phase, StudyCardPhase.readyForNext);
      expect((await intro.stateFor(courseId, key)).isIntroduced, isTrue);
    });

    test('introduction is exactly-once across repeat course submits', () async {
      final store = CardIntroductionStore();
      CardIntroductionStore.debugOverride = store;
      addTearDown(() {
        CardIntroductionStore.debugOverride = null;
      });

      final intro = _InMemoryIntroductionRepository();
      final host = AnkiStudySessionHost(
        resolver: const StudyLedgerResolver(),
        introductionRepository: intro,
      );
      final key = officialKey(5);
      final item = AnkiStudySessionHost.itemForCourse(
        key: key,
        presentation: flip(key),
        courseId: courseId,
        placementId: lessonId,
      );

      await host.driveFlip(item: item, outcome: RecallOutcome.forgotten);
      await store.markFromLesson(
        wordId: 'official-anki-$sourceId-c5',
        lessonId: lessonId,
      );
      expect(store.introducedCountForSource(sourceId), 1);
      expect((await intro.stateFor(courseId, key)).isIntroduced, isTrue);

      // Second successful course pass must not inflate introduced count.
      await host.driveFlip(item: item, outcome: RecallOutcome.remembered);
      await store.markFromLesson(
        wordId: 'official-anki-$sourceId-c5',
        lessonId: lessonId,
      );
      expect(store.introducedCountForSource(sourceId), 1);
    });

    test('legacy course cards degrade to practice (no Turna ledger write)',
        () {
      final legacy = CanonicalCardKey(
        backend: AnkiBackendKind.legacyTurna,
        profileId: profile,
        sourceId: 'legacy-pack',
        cardId: 9,
      );
      final item = AnkiStudySessionHost.itemForCourse(
        key: legacy,
        presentation: flip(legacy),
        courseId: 'anki-legacy-pack',
      );
      // Doc 35 L2: the Turna-FSRS writer for Anki cards is retired —
      // legacy imports study like official ones (practice, flip-through,
      // introduction only).
      expect(item.mode, StudyMode.practice);
      expect(item.ledgerOwner, StudyLedgerOwner.none);
      expect(item.capabilities.writesLedger, isFalse);
      expect(item.capabilities.marksIntroduced, isTrue);
    });
  });
}

class _InMemoryIntroductionRepository implements CardIntroductionRepository {
  final Map<String, CardIntroductionState> _states = {};

  String _key(String courseId, CanonicalCardKey key) =>
      '$courseId:${key.sourceId}:c${key.cardId}:${key.backend.name}';

  @override
  Future<CardIntroductionState> stateFor(
    String courseId,
    CanonicalCardKey key,
  ) async {
    return _states[_key(courseId, key)] ??
        CardIntroductionState(
          courseId: courseId,
          cardKey: key,
          status: CardIntroductionStatus.unintroduced,
        );
  }

  @override
  Future<Set<CanonicalCardKey>> introducedKeys(String courseId) async {
    return {
      for (final state in _states.values)
        if (state.courseId == courseId && state.isIntroduced) state.cardKey,
    };
  }

  @override
  Future<void> markIntroduced(
    String courseId,
    CanonicalCardKey key, {
    required CardIntroducedBy by,
    required String lessonId,
  }) async {
    _states[_key(courseId, key)] = CardIntroductionState(
      courseId: courseId,
      cardKey: key,
      status: CardIntroductionStatus.introduced,
      introducedBy: by,
      introducedAt: DateTime.now(),
      firstLessonId: lessonId,
    );
  }

  @override
  Future<void> retire(String courseId, CanonicalCardKey key) async {
    _states[_key(courseId, key)] = (await stateFor(courseId, key))
        .copyWith(status: CardIntroductionStatus.retired);
  }
}

class _CountingLedger implements StudyLedger {
  _CountingLedger({required this.owner});

  final StudyLedgerOwner owner;
  int commits = 0;

  @override
  Future<DueSnapshot> dueSnapshot(StudyScope scope) async {
    return const DueSnapshot(dueCardKeys: {});
  }

  @override
  Future<SchedulePreview> preview(
    CanonicalCardKey key,
    RecallOutcome outcome,
  ) async {
    return const SchedulePreview(intervalLabel: '1d');
  }

  @override
  Future<StudyEventReceipt> commit(
    CanonicalCardKey key,
    RecallOutcome outcome, {
    required String idempotencyKey,
  }) async {
    commits++;
    return StudyEventReceipt(
      eventId: 'e-$commits',
      idempotencyKey: idempotencyKey,
      cardKey: key,
      ledgerOwner: owner,
      outcome: outcome,
      reviewedAt: DateTime.now(),
    );
  }

  @override
  Future<bool> undo(StudyEventReceipt receipt) async => false;

  @override
  Future<bool> redo(StudyEventReceipt receipt) async => false;

  @override
  Future<bool> bury(CanonicalCardKey key) async => false;

  @override
  Future<bool> suspend(CanonicalCardKey key) async => false;
}
