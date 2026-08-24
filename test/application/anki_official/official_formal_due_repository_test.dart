// OfficialFormalDueRepository tests (plan 34 R3 / OS-15): the six-set
// formula, fail-closed unknowns (never a guessed zero), generation-based
// staleness, rollback of the full six sets, and per-source isolation.

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_repository.dart';

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
    resolveIntroducedAtReadTime: false,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    OfficialFormalDueRepository.instance.reset();
  });

  tearDown(() {
    OfficialFormalDueRepository.instance.reset();
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

  test('apply bumps the generation and isStale detects late results', () {
    final repo = OfficialFormalDueRepository.instance;
    repo.apply(byImport: {'a': _per('a')});
    final observed = repo.generation;
    repo.apply(byImport: {'a': _per('a')});
    expect(repo.isStale(observed), isTrue,
        reason: 'a late async result from the older generation must be '
            'dropped, not overwrite the newer snapshot');
    expect(repo.isStale(repo.generation), isFalse);
  });

  test('rollback restores the complete previous six sets', () {
    final repo = OfficialFormalDueRepository.instance;
    repo.apply(byImport: {
      'a': _per('a', schedulerDue: {1}, placement: {1}, introduced: {1}),
    });
    repo.saveForRollback();
    repo.apply(byImport: {
      'a': _per('a',
          schedulerDue: {1, 2},
          placement: {1, 2},
          introduced: {1, 2},
          retired: {2}),
    });
    expect(repo.formalDueCardKeysForImport('a').map((k) => k.cardId), {1});

    repo.rollback();

    expect(
      repo.schedulerDueCardIdsFor('a'),
      {1},
      reason: 'the failed refresh must leave the last good six sets intact',
    );
    expect(repo.retiredCardIdsFor('a'), isEmpty);
    expect(repo.generation, greaterThan(0));
  });

  test('markUnavailable keeps the last good sets visible', () {
    final repo = OfficialFormalDueRepository.instance;
    repo.apply(byImport: {
      'a': _per('a', schedulerDue: {1}, placement: {1}, introduced: {1}),
    });
    repo.markUnavailable(StateError('engine closed'));

    expect(repo.snapshot.unavailable, isTrue);
    expect(repo.snapshot.byImport, isNotEmpty,
        reason: 'a failed refresh keeps the stale sets instead of zeroing');
    expect(repo.formalDueCountForImport('a'), 1);
  });

  test('per-source isolation: two sources never share sets', () {
    final repo = OfficialFormalDueRepository.instance;
    repo.apply(byImport: {
      'src-a': _per('src-a',
          schedulerDue: {1, 2}, placement: {1, 2}, introduced: {1, 2}),
      'src-b': _per('src-b',
          schedulerDue: {1, 2},
          placement: {1},
          introduced: {1},
          suspended: {1}),
    });
    expect(repo.formalDueCountForImport('src-a'), 2);
    expect(repo.formalDueCountForImport('src-b'), 0,
        reason: 'src-b suspended its only introduced card');
    expect(repo.officialImportIds, {'src-a', 'src-b'});
  });

  test('snapshot totals distinguish unknown sources (isPartial)', () {
    final repo = OfficialFormalDueRepository.instance;
    repo.apply(
      byImport: {
        'src-known': _per('src-known',
            schedulerDue: {1}, placement: {1}, introduced: {1}),
        'src-unknown': _per('src-unknown', known: false),
      },
      rawDueByImport: {'src-known': 5, 'src-unknown': 7},
    );
    final snap = repo.snapshot;
    expect(snap.introducedOfficialDue, 1);
    expect(snap.isPartial, isTrue);
    expect(snap.unintroducedOfficialDue, 11);
  });
}
