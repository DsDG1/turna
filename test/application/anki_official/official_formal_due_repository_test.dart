// OfficialFormalDueRepository tests (plan 34 R3 / OS-15 + maintainability
// plan Wave 1): the six-set formula, fail-closed unknowns (never a guessed
// zero), generation-based staleness with CAS commits, and per-source
// isolation.

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_repository.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_update.dart';

OfficialFormalDuePerSource _per(
  String importId, {
  bool known = true,
  Set<int> schedulerDue = const {},
  Set<int> placement = const {},
  Set<int> introduced = const {},
  Set<int> suspended = const {},
  Set<int> buried = const {},
  Set<int> retired = const {},
}) {
  return OfficialFormalDuePerSource(
    importId: importId,
    knowledge: known ? FormalDueKnowledge.known : FormalDueKnowledge.unknown,
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

  setUp(() {
    OfficialFormalDueRepository.instance.resetForTest();
  });

  tearDown(() {
    OfficialFormalDueRepository.instance.resetForTest();
  });

  test(
      'six-set formula: due ∩ placement ∩ introduced − suspended − buried '
      '− retired', () {
    final per = _per(
      'src-a',
      schedulerDue: {1, 2, 3, 4, 5, 6},
      placement: {1, 2, 3, 4, 5},
      introduced: {1, 2, 3, 4},
      suspended: {2},
      buried: {3},
      retired: {4},
    );
    expect(per.formalDueCardKeys.map((k) => k.cardId).toSet(), {1});
    expect(per.formalDueCount, 1);
  });

  test(
      'unknown sources report null — never a guessed zero, never a '
      'schedulerDue fallback', () {
    final per = _per(
      'src-never-synced',
      known: false,
      schedulerDue: {9, 10},
      placement: {9, 10},
    );
    expect(per.formalDueCount, isNull,
        reason: 'the count is unknown; 0 would be a guess (plan 34 R3-1)');
    expect(per.formalDueCardKeys, isEmpty);
    expect(per.knowledge, FormalDueKnowledge.unknown);
  });

  test('commit bumps the generation and isStale detects late results', () {
    final repo = OfficialFormalDueRepository.instance;
    repo.commit(
      _update(bySource: {'a': _per('a')}),
      basedOnGeneration: repo.generation,
    );
    final observed = repo.generation;
    repo.commit(
      _update(bySource: {'a': _per('a')}),
      basedOnGeneration: repo.generation,
    );
    expect(repo.isStale(observed), isTrue,
        reason: 'a late async result from the older generation must be '
            'dropped, not overwrite the newer snapshot');
    expect(repo.isStale(repo.generation), isFalse);
  });

  test('a stale commit is rejected and keeps the newer snapshot', () {
    final repo = OfficialFormalDueRepository.instance;
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
    expect(repo.schedulerDueCardIdsFor('a'), {9});
  });

  test('mutateSource commits a full snapshot for one source', () {
    final repo = OfficialFormalDueRepository.instance;
    repo.commit(
      _update(bySource: {
        'a': _per('a', schedulerDue: {1}, placement: {1}, introduced: {1}),
        'b': _per('b', schedulerDue: {5}, placement: {5}, introduced: {5}),
      }),
      basedOnGeneration: repo.generation,
    );

    final result = repo.mutateSource(
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

    expect(result, OfficialFormalDueCommitResult.committed);
    expect(repo.formalDueCountForImport('a'), 0,
        reason: 'the only due card is now buried');
    expect(repo.formalDueCountForImport('b'), 1,
        reason: 'the other source keeps its complete sets');
  });

  test('markUnavailable keeps the last good sets visible', () {
    final repo = OfficialFormalDueRepository.instance;
    repo.commit(
      _update(bySource: {
        'a': _per('a', schedulerDue: {1}, placement: {1}, introduced: {1}),
      }),
      basedOnGeneration: repo.generation,
    );
    repo.markUnavailable(StateError('engine closed'));

    expect(repo.snapshot.unavailable, isTrue);
    expect(repo.snapshot.byImport, isNotEmpty,
        reason: 'a failed refresh keeps the stale sets instead of zeroing');
    expect(repo.formalDueCountForImport('a'), 1);
  });

  test('per-source isolation: two sources never share sets', () {
    final repo = OfficialFormalDueRepository.instance;
    repo.commit(
      _update(bySource: {
        'src-a': _per('src-a',
            schedulerDue: {1, 2}, placement: {1, 2}, introduced: {1, 2}),
        'src-b': _per('src-b',
            schedulerDue: {1, 2},
            placement: {1},
            introduced: {1},
            suspended: {1}),
      }),
      basedOnGeneration: repo.generation,
    );
    expect(repo.formalDueCountForImport('src-a'), 2);
    expect(repo.formalDueCountForImport('src-b'), 0,
        reason: 'src-b suspended its only introduced card');
    expect(repo.officialImportIds, {'src-a', 'src-b'});
  });

  test('snapshot totals distinguish unknown sources (isPartial)', () {
    final repo = OfficialFormalDueRepository.instance;
    repo.commit(
      _update(
        bySource: {
          'src-known': _per('src-known',
              schedulerDue: {1}, placement: {1}, introduced: {1}),
          'src-unknown': _per('src-unknown', known: false),
        },
        rawDueBySource: {'src-known': 5, 'src-unknown': 7},
      ),
      basedOnGeneration: repo.generation,
    );
    final snap = repo.snapshot;
    expect(snap.introducedOfficialDue, 1);
    expect(snap.isPartial, isTrue);
    expect(snap.unintroducedOfficialDue, 11);
  });
}
