import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/anki/anki_models.dart';
import 'package:turna/application/anki/anki_review_assembler.dart';
import 'package:turna/application/anki/anki_srs_migrator.dart';
import 'package:turna/application/anki/card_introduction_eligibility.dart';
import 'package:turna/application/anki/card_introduction_store.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_repository.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_snapshot_builder.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_update.dart';
import 'package:turna/application/anki_official/engine/official_anki_review_session.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/lesson_link_store.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/domain/anki/card_introduction_state.dart';
import 'package:turna/domain/course/srs_word.dart';
import 'package:turna/service/locator.dart';

import '../../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const eligibility = CardIntroductionEligibility();

  setUp(() {
    CardIntroductionStore.debugOverride = CardIntroductionStore();
    OfficialFormalDueRepository.instance.resetForTest();
  });

  tearDown(() {
    CardIntroductionStore.debugOverride = null;
  });

  group('pure eligibility', () {
    test('unlearned new cards are not formally eligible', () {
      expect(
        eligibility.isFormallyEligible(stored: null, reps: 0),
        isFalse,
      );
      expect(
        eligibility.isFormallyEligible(
          stored: CardIntroductionStatus.unintroduced,
          reps: 0,
        ),
        isFalse,
      );
    });

    test('imported history and course introduction are eligible', () {
      expect(
        eligibility.isFormallyEligible(stored: null, reps: 3),
        isTrue,
      );
      expect(
        eligibility.isFormallyEligible(
          stored: CardIntroductionStatus.introduced,
          reps: 0,
        ),
        isTrue,
      );
      expect(
        eligibility.isFormallyEligible(
          stored: CardIntroductionStatus.retired,
          reps: 9,
        ),
        isFalse,
      );
    });

    test('formal due is 0 when nothing is introduced', () {
      expect(
        eligibility.formalDueCount(schedulerDue: 20, introducedCount: 0),
        0,
      );
      expect(
        eligibility.formalDueCount(schedulerDue: 20, introducedCount: 3),
        3,
      );
      expect(
        eligibility.formalDueCount(schedulerDue: 2, introducedCount: 8),
        2,
      );
    });
  });

  group('legacy review assembler', () {
    late AppPrefs prefs;
    late SrsProvider srs;
    late CourseProvider courseProvider;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final sp = await StreamingSharedPreferences.instance;
      prefs = AppPrefs(sp);
      await prefs.setString(PrefsConstants.courseScope, '');
      await prefs.preferences.setString(LocalStateKeys.srsState, '{}');
      srs = SrsProvider(prefs, LessonLinkStore(prefs), emptySrsStateDao());
      courseProvider = CourseProvider(prefs);
    });

    test('20 unlearned due cards produce formal due 0', () {
      for (var i = 1; i <= 20; i++) {
        srs.registerWord('anki-pack-c$i');
      }
      final assembler = AnkiReviewAssembler(srs, courseProvider);
      expect(assembler.totalAnkiDueCount, 0);
      expect(assembler.unintroducedDueCount(), 20);
      expect(assembler.collectDue(), isEmpty);
    });

    test('learning 3 cards then exiting exposes at most those 3', () async {
      for (var i = 1; i <= 20; i++) {
        srs.registerWord('anki-pack-c$i');
      }
      final store = CardIntroductionStore.debugOverride!;
      await store.markFromLesson(
        wordId: 'anki-pack-c1',
        lessonId: 'anki-pack-u-l0',
      );
      await store.markFromLesson(
        wordId: 'anki-pack-c2',
        lessonId: 'anki-pack-u-l0',
      );
      await store.markFromLesson(
        wordId: 'anki-pack-c3',
        lessonId: 'anki-pack-u-l0',
      );
      final assembler = AnkiReviewAssembler(srs, courseProvider);
      expect(assembler.totalAnkiDueCount, 3);
      expect(
        assembler.collectDue().map((w) => w.wordId).toSet(),
        {'anki-pack-c1', 'anki-pack-c2', 'anki-pack-c3'},
      );
      expect(assembler.unintroducedDueCount(), 17);
    });

    test('imported history (reps>0) is introduced without a course submit',
        () async {
      await srs.bulkImportStates({
        'anki-hist-c8': SrsWord(
          wordId: 'anki-hist-c8',
          dueAt: DateTime.now().subtract(const Duration(minutes: 1)),
          intervalDays: 1,
          ease: 2.5,
          reps: 4,
          lapses: 0,
        ),
      });
      final assembler = AnkiReviewAssembler(srs, courseProvider);
      expect(assembler.totalAnkiDueCount, 1);
      expect(assembler.collectDue().single.wordId, 'anki-hist-c8');
    });
  });

  group('legacy import seed', () {
    test('migrator marks reps>0 introduced and new cards unintroduced',
        () async {
      SharedPreferences.setMockInitialValues({});
      final sp = await StreamingSharedPreferences.instance;
      final prefs = AppPrefs(sp);
      await prefs.preferences.setString(LocalStateKeys.srsState, '{}');
      final srs = SrsProvider(prefs, LessonLinkStore(prefs), emptySrsStateDao());
      await AnkiSrsMigrator().migrate(
        cards: const [
          AnkiCardData(id: 1, nid: 1, did: 1, queue: 0, reps: 0),
          AnkiCardData(id: 2, nid: 2, did: 1, queue: 2, reps: 6, ivl: 3),
        ],
        importId: 'imp',
        srsProvider: srs,
        importScheduling: true,
      );
      final store = CardIntroductionStore.debugOverride!;
      expect(store.isIntroducedCard(sourceId: 'imp', cardId: 1), isFalse);
      expect(store.isIntroducedCard(sourceId: 'imp', cardId: 2), isTrue);
      expect(
        store.isFormallyEligibleWord(srs.state['anki-imp-c1']!),
        isFalse,
      );
      expect(
        store.isFormallyEligibleWord(srs.state['anki-imp-c2']!),
        isTrue,
      );
    });
  });

  group('official session filter', () {
    const flags = OfficialAnkiFeatureFlags(
      engine: true,
      import: true,
      catalogReady: true,
      runtimeCapable: true,
      platformReady: true,
      renderer: true,
      scheduler: true,
    );

    test('empty allowed set means no unintroduced new cards are shown',
        () async {
      final fake = FakeOfficialAnkiEngine();
      fake.seedPackage(packagePath: 'x.apkg', notes: 2, cards: 2);
      final session = OfficialReviewSession(
        engine: fake,
        flags: flags,
        allowedCardIds: const {},
      );
      await session.openDeck(1);
      expect(session.current, isNull);
      expect(session.phase, OfficialReviewPhase.completed);
    });
  });

  group('official home due display', () {
    test('scheduler due of 20 with 0 introduced displays 0', () {
      _commitSource(
        'src',
        schedulerDue: {for (var i = 1; i <= 20; i++) i},
        rawDue: 20,
      );
      final repo = OfficialFormalDueRepository.instance;
      expect(repo.formalOfficialDueForImport('src'), 0);
      expect(repo.snapshot.introducedOfficialDue, 0);
      expect(repo.snapshot.unintroducedOfficialDue, 20);
    });

    test('scheduler due of 20 with 3 introduced displays 3', () async {
      final store = CardIntroductionStore.debugOverride!;
      await store.markFromLesson(
        wordId: 'official-anki-src-c1',
        lessonId: 'official-anki-src-l0123456789ab-p1',
      );
      await store.markFromLesson(
        wordId: 'official-anki-src-c2',
        lessonId: 'official-anki-src-l0123456789ab-p1',
      );
      await store.markFromLesson(
        wordId: 'official-anki-src-c3',
        lessonId: 'official-anki-src-l0123456789ab-p1',
      );
      _commitSource(
        'src',
        schedulerDue: {for (var i = 1; i <= 20; i++) i},
        placement: {for (var i = 1; i <= 20; i++) i},
        rawDue: 20,
      );
      final repo = OfficialFormalDueRepository.instance;
      expect(repo.formalOfficialDueForImport('src'), 3);
      expect(repo.snapshot.unintroducedOfficialDue, 17);
    });
  });
}


void _commitSource(
  String importId, {
  required Set<int> schedulerDue,
  Set<int> placement = const {},
  int rawDue = 0,
}) {
  OfficialFormalDueRepository.instance.commit(
    OfficialFormalDueUpdate(
      bySource: {
        importId: buildFormalDuePerSource(
          importId: importId,
          schedulerDueCardIds: schedulerDue,
          schedulerDueSynced: true,
          activePlacementCardIds: placement,
          suspendedCardIds: const {},
          buriedCardIds: const {},
          retiredCardIds: const {},
        ),
      },
      rawDueBySource: {importId: rawDue},
      turnaDue: 0,
      unintroducedNew: 0,
    ),
    basedOnGeneration: OfficialFormalDueRepository.instance.generation,
  );
}
