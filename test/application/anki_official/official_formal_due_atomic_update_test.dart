// Wave 1 red tests (maintainability plan §6.2-1): a formal-due refresh
// commits ONE complete snapshot (one generation bump, one listener
// notification), stale commits are rejected, mutations never lose
// suspended/buried sets, and introduction/retire changes publish a new
// complete snapshot instead of a getter-time bypass.

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki/card_introduction_store.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_repository.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_update.dart';

OfficialFormalDuePerSource _per(
  String importId, {
  Set<int> schedulerDue = const {},
  Set<int> placement = const {},
  Set<int> introduced = const {},
  Set<int> suspended = const {},
  Set<int> buried = const {},
  Set<int> retired = const {},
}) {
  return OfficialFormalDuePerSource(
    importId: importId,
    knowledge: FormalDueKnowledge.known,
    schedulerDueCardIds: schedulerDue,
    activePlacementCardIds: placement,
    introducedCardIds: introduced,
    suspendedCardIds: suspended,
    buriedCardIds: buried,
    retiredCardIds: retired,
  );
}

OfficialFormalDueUpdate _update({
  Map<String, OfficialFormalDuePerSource> bySource = const {},
  Map<String, int> rawDueBySource = const {},
}) {
  return OfficialFormalDueUpdate(
    bySource: bySource,
    rawDueBySource: rawDueBySource,
    turnaDue: 0,
    unintroducedNew: 0,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late OfficialFormalDueRepository repo;
  late CardIntroductionStore intro;

  setUp(() {
    OfficialFormalDueRepository.instance.resetForTest();
    repo = OfficialFormalDueRepository.instance;
    intro = CardIntroductionStore();
    CardIntroductionStore.debugOverride = intro;
    intro.resetForTest();
  });

  tearDown(() {
    CardIntroductionStore.debugOverride = null;
    OfficialFormalDueRepository.instance.resetForTest();
  });

  test('one logical refresh commits exactly one generation + one notification',
      () {
    repo.commit(
      _update(bySource: {
        'a': _per('a', schedulerDue: {1}, placement: {1}, introduced: {1}),
      }),
      basedOnGeneration: repo.generation,
    );
    final before = repo.generation;

    var notifications = 0;
    OfficialFormalDueSnapshot? lastSeen;
    void listener() {
      notifications++;
      lastSeen = repo.snapshot;
    }

    repo.addListener(listener);
    repo.commit(
      _update(
        bySource: {
          'a': _per('a', schedulerDue: {1, 2}, placement: {1, 2},
              introduced: {1, 2}),
        },
        rawDueBySource: {'a': 2},
      ),
      basedOnGeneration: before,
    );
    repo.removeListener(listener);

    expect(notifications, 1,
        reason: 'a full refresh is one atomic commit — consumers must never '
            'observe a partially updated snapshot');
    expect(repo.generation, before + 1);
    expect(lastSeen!.rawDueByImport['a'], 2,
        reason: 'the single observed snapshot carries every collection');
    expect(lastSeen!.byImport['a']!.schedulerDueCardIds, {1, 2});
  });

  test('a stale commit is rejected instead of overwriting newer state', () {
    repo.commit(
      _update(bySource: {
        'a': _per('a', schedulerDue: {1}, placement: {1}, introduced: {1}),
      }),
      basedOnGeneration: repo.generation,
    );
    final staleBase = repo.generation;
    repo.commit(
      _update(bySource: {
        'a': _per('a', schedulerDue: {9}, placement: {9}, introduced: {9}),
      }),
      basedOnGeneration: repo.generation,
    );

    final result = repo.commit(
      _update(bySource: {
        'a': _per('a', schedulerDue: {1, 2}, placement: {1, 2},
            introduced: {1, 2}),
      }),
      basedOnGeneration: staleBase,
    );

    expect(result, OfficialFormalDueCommitResult.stale);
    expect(repo.snapshot.byImport['a']!.schedulerDueCardIds, {9},
        reason: 'the late result must be dropped, not overwrite newer data');
  });

  test('mutation during a refresh window never loses suspended/buried', () {
    repo.commit(
      _update(bySource: {
        'a': _per('a',
            schedulerDue: {1, 2},
            placement: {1, 2},
            introduced: {1, 2},
            suspended: {2}),
      }),
      basedOnGeneration: repo.generation,
    );

    // A late refresh collected BEFORE the suspend but committing AFTER the
    // mutation must not resurrect the suspended card.
    final staleBase = repo.generation;
    final mutationResult = repo.mutateSource(
      'a',
      transform: (current) => OfficialFormalDuePerSource(
        importId: current.importId,
        knowledge: current.knowledge,
        schedulerDueCardIds: current.schedulerDueCardIds,
        activePlacementCardIds: current.activePlacementCardIds,
        introducedCardIds: current.introducedCardIds,
        suspendedCardIds: current.suspendedCardIds,
        buriedCardIds: {...current.buriedCardIds, 1},
        retiredCardIds: current.retiredCardIds,
      ),
    );
    expect(mutationResult, OfficialFormalDueCommitResult.committed);

    final lateResult = repo.commit(
      _update(bySource: {
        'a': _per('a', schedulerDue: {1, 2}, placement: {1, 2},
            introduced: {1, 2}, suspended: {2}),
      }),
      basedOnGeneration: staleBase,
    );
    expect(lateResult, OfficialFormalDueCommitResult.stale);

    final per = repo.snapshot.byImport['a']!;
    expect(per.suspendedCardIds, {2});
    expect(per.buriedCardIds, {1},
        reason: 'the mutation survived the racing refresh');
    expect(repo.formalDueCountForImport('a'), 0);
  });

  test('introduction mutation publishes a fresh complete snapshot', () async {
    repo.commit(
      _update(bySource: {
        'a': _per('a', schedulerDue: {1, 2}, placement: {1, 2}),
      }),
      basedOnGeneration: repo.generation,
    );
    expect(repo.formalDueCountForImport('a'), 0,
        reason: 'nothing introduced yet — due must be empty, not guessed');

    await intro.markFromLesson(
      wordId: 'anki-a-c1',
      lessonId: 'official-anki-a-l000000000001-p1',
    );

    expect(repo.formalDueCountForImport('a'), 1,
        reason: 'the introduction event must land in the committed snapshot '
            'immediately (no getter-time bypass)');
    expect(
      repo.snapshot.byImport['a']!.introducedCardIds,
      {1},
      reason: 'the introduced set itself lives in the snapshot now',
    );
  });

  test('snapshot collections are immutable from the outside', () {
    repo.commit(
      _update(bySource: {
        'a': _per('a', schedulerDue: {1}, placement: {1}, introduced: {1}),
      }),
      basedOnGeneration: repo.generation,
    );

    final per = repo.snapshot.byImport['a']!;
    expect(
      () => per.schedulerDueCardIds.add(99),
      throwsUnsupportedError,
      reason: 'sets must be frozen at the snapshot boundary',
    );
    expect(
      () => repo.snapshot.byImport['a']!.suspendedCardIds.add(99),
      throwsUnsupportedError,
    );
  });

  test('failed refresh keeps the last complete snapshot (markUnavailable)', () {
    repo.commit(
      _update(bySource: {
        'a': _per('a', schedulerDue: {1}, placement: {1}, introduced: {1}),
      }),
      basedOnGeneration: repo.generation,
    );
    final before = repo.snapshot;

    repo.markUnavailable(StateError('engine closed'));

    expect(repo.snapshot.unavailable, isTrue);
    expect(repo.snapshot.byImport, before.byImport,
        reason: 'stale-but-complete data stays visible');
    expect(repo.snapshot.generation, greaterThan(before.generation));
    expect(repo.formalDueCountForImport('a'), 1);
  });
}
