import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/introduction/card_introduction_eligibility.dart';
import 'package:turna/application/anki_official/introduction/card_introduction_store.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_repository.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_snapshot_builder.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_update.dart';
import 'package:turna/application/anki_official/engine/official_anki_review_session.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/domain/anki/card_introduction_state.dart';


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
    test('scheduler due outside every placement is not formal due', () {
      // Transitional collect: the scheduler still reports cards that no
      // active placement owns (e.g. pre-reconcile) — placement scopes them
      // out of formal due while rawDue keeps the hint.
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

    test('a locked source reports no scheduler due at all', () {
      // P1: unintroduced cards are scheduler-suspended, so the collected
      // schedulerDue set is empty — that is why the badge reads 0, not a
      // Dart-side introduced subtraction. rawDue would equally be 0; the
      // value here models a not-yet-reconciled transitional collect.
      _commitSource(
        'src',
        schedulerDue: const {},
        placement: {for (var i = 1; i <= 20; i++) i},
        rawDue: 0,
      );
      final repo = OfficialFormalDueRepository.instance;
      expect(repo.formalOfficialDueForImport('src'), 0);
      expect(repo.snapshot.introducedOfficialDue, 0);
      expect(repo.snapshot.unintroducedOfficialDue, 0);
    });

    test('post-lock scheduler due displays verbatim', () {
      // Three cards unlocked by lesson completion: the scheduler reports
      // exactly those as due, and the snapshot shows them without any
      // introduced-set arithmetic.
      _commitSource(
        'src',
        schedulerDue: const {1, 2, 3},
        placement: {for (var i = 1; i <= 20; i++) i},
        rawDue: 3,
      );
      final repo = OfficialFormalDueRepository.instance;
      expect(repo.formalOfficialDueForImport('src'), 3);
      expect(repo.snapshot.unintroducedOfficialDue, 0);
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
