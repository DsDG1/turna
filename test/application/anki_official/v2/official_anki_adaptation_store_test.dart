import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/v2/official_anki_adaptation_store.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_config_keys.dart';
import 'package:turna/domain/anki/adaptation/card_adaptation_plan.dart';

/// P6 activation protocol (ADR 0057 §6): immutable revisions, one manifest
/// switch, card overrides, and a namespace that can be deleted completely.
void main() {
  const sourceId = 'src-adapt';

  late FakeOfficialAnkiEngine engine;
  late OfficialAnkiAdaptationStore store;
  setUp(() {
    engine = FakeOfficialAnkiEngine();
    store = OfficialAnkiAdaptationStore(engine);
  });

  CardAdaptationPlan plan({
    String planId = 'plan-1',
    int revision = 1,
    int templateOrdinal = 0,
    String? extra,
    Map<String, int>? bindings,
    List<AdaptationBlock>? front,
  }) {
    return CardAdaptationPlan(
      planId: planId,
      revision: revision,
      scope: AdaptationScope(
        sourceId: sourceId,
        notetypeId: 7,
        templateOrdinal: templateOrdinal,
      ),
      bindings: bindings ??
          <String, int>{
            'prompt': 0,
            'answer': 1,
            if (extra != null) 'image': 2,
          },
      front: front ??
          const <AdaptationBlock>[
            AdaptationBlock(kind: 'text', fieldIndex: 0),
          ],
      back: const <AdaptationBlock>[
        AdaptationBlock(kind: 'text', fieldIndex: 1),
      ],
    );
  }

  test('activation writes the body first and the manifest second', () async {
    final written = await store.activate(
      sourceId: sourceId,
      scopeKey: adaptationScopeKey(7, 0),
      plan: plan(),
    );

    expect(written, isTrue);
    expect(
      engine.configStore.keys,
      containsAll(<String>[
        OfficialAnkiAdaptationConfigKeys.plan('plan-1', 1),
        OfficialAnkiAdaptationConfigKeys.manifest(sourceId),
        OfficialAnkiAdaptationConfigKeys.index(sourceId),
      ]),
    );

    final found = await store.lookup(
      sourceId: sourceId,
      notetypeId: 7,
      templateOrdinal: 0,
      cardId: 100,
    );
    expect(found, isA<AdaptationPlanFound>());
    expect((found as AdaptationPlanFound).plan.planId, 'plan-1');
    expect(found.fromCardOverride, isFalse);
  });

  test('a revision is immutable: same key, different body is rejected',
      () async {
    await store.activate(
      sourceId: sourceId,
      scopeKey: adaptationScopeKey(7, 0),
      plan: plan(),
    );

    await expectLater(
      store.writeRevision(sourceId: sourceId, plan: plan(extra: 'x')),
      throwsA(
        isA<OfficialAnkiException>().having(
          (e) => e.debugDetails,
          'debugDetails',
          'adaptation_revision_not_immutable',
        ),
      ),
    );
  });

  test('replaying the same bytes is idempotent', () async {
    expect(
      await store.writeRevision(sourceId: sourceId, plan: plan()),
      isTrue,
    );
    expect(
      await store.writeRevision(sourceId: sourceId, plan: plan()),
      isTrue,
    );
  });

  test('a manifest that points at a deleted body is not silently ignored',
      () async {
    await store.activate(
      sourceId: sourceId,
      scopeKey: adaptationScopeKey(7, 0),
      plan: plan(),
    );
    await engine.setConfig(
      OfficialAnkiAdaptationConfigKeys.plan('plan-1', 1),
      null,
    );

    final found = await store.lookup(
      sourceId: sourceId,
      notetypeId: 7,
      templateOrdinal: 0,
      cardId: 100,
    );
    expect(found, isA<AdaptationPlanMissing>());
  });

  test('a corrupt revision body reads as missing', () async {
    engine.configStore[OfficialAnkiAdaptationConfigKeys.plan('plan-1', 1)] =
        'not-a-plan';
    expect(await store.readRevision('plan-1', 1), isNull);
  });

  test('a card override beats the template plan in both directions',
      () async {
    await store.activate(
      sourceId: sourceId,
      scopeKey: adaptationScopeKey(7, 0),
      plan: plan(),
    );
    await store.writeCardOverride(
      sourceId: sourceId,
      cardId: 100,
      override: const AdaptationCardOverride.original(),
    );

    expect(
      await store.lookup(
        sourceId: sourceId,
        notetypeId: 7,
        templateOrdinal: 0,
        cardId: 100,
      ),
      isA<AdaptationExplicitlyOriginal>(),
    );

    await store.writeCardOverride(
      sourceId: sourceId,
      cardId: 200,
      override: const AdaptationCardOverride.plan(planId: 'plan-1', revision: 1),
    );
    final pinned = await store.lookup(
      sourceId: sourceId,
      notetypeId: 7,
      templateOrdinal: 0,
      cardId: 200,
    );
    expect(pinned, isA<AdaptationPlanFound>());
    expect((pinned as AdaptationPlanFound).fromCardOverride, isTrue);

    await store.clearCardOverride(sourceId: sourceId, cardId: 100);
    expect(
      await store.lookup(
        sourceId: sourceId,
        notetypeId: 7,
        templateOrdinal: 0,
        cardId: 100,
      ),
      isA<AdaptationPlanFound>(),
    );
  });

  test('an exact cloze scope beats the template scope', () async {
    await store.activate(
      sourceId: sourceId,
      scopeKey: adaptationScopeKey(7, 0),
      plan: plan(planId: 'generic'),
    );
    await store.activate(
      sourceId: sourceId,
      scopeKey: adaptationScopeKey(7, 0, clozeTarget: 2),
      plan: plan(planId: 'cloze-2'),
    );

    final targeted = await store.lookup(
      sourceId: sourceId,
      notetypeId: 7,
      templateOrdinal: 0,
      cardId: 1,
      clozeTarget: 2,
    );
    expect((targeted as AdaptationPlanFound).plan.planId, 'cloze-2');

    final generic = await store.lookup(
      sourceId: sourceId,
      notetypeId: 7,
      templateOrdinal: 0,
      cardId: 1,
      clozeTarget: 3,
    );
    expect((generic as AdaptationPlanFound).plan.planId, 'generic');
  });

  test('deactivation hides the plan but keeps the body for a later switch',
      () async {
    await store.activate(
      sourceId: sourceId,
      scopeKey: adaptationScopeKey(7, 0),
      plan: plan(),
    );
    expect(
      await store.deactivate(sourceId: sourceId, scopeKey: adaptationScopeKey(7, 0)),
      isTrue,
    );

    expect(
      await store.lookup(
        sourceId: sourceId,
        notetypeId: 7,
        templateOrdinal: 0,
        cardId: 100,
      ),
      isA<AdaptationNoPlan>(),
    );
    expect(await store.readRevision('plan-1', 1), isNotNull);
  });

  test('no plan is the normal old-data path', () async {
    expect(
      await store.lookup(
        sourceId: sourceId,
        notetypeId: 7,
        templateOrdinal: 0,
        cardId: 100,
      ),
      isA<AdaptationNoPlan>(),
    );
  });

  test('a corrupt manifest reads as an empty manifest', () async {
    engine.configStore[OfficialAnkiAdaptationConfigKeys.manifest(sourceId)] =
        'garbage';
    expect(
      (await store.readManifest(sourceId)).entries,
      isEmpty,
    );
  });

  test('uninstalling a source removes the whole namespace', () async {
    await store.activate(
      sourceId: sourceId,
      scopeKey: adaptationScopeKey(7, 0),
      plan: plan(),
    );
    await store.writeCardOverride(
      sourceId: sourceId,
      cardId: 100,
      override: const AdaptationCardOverride.original(),
    );
    expect(engine.configStore, isNotEmpty);

    await store.deleteSourceNamespace(sourceId);

    expect(
      engine.configStore.keys.where((key) => key.startsWith('turna.adapt.')),
      isEmpty,
    );
  });

  test('scope keys separate cloze targets from template ordinals', () {
    expect(adaptationScopeKey(7, 0), '7:0');
    expect(adaptationScopeKey(7, 0, clozeTarget: 2), '7:0:c2');
    expect(
      adaptationScopeKey(7, 2),
      isNot(adaptationScopeKey(7, 0, clozeTarget: 2)),
      reason: '普通模板序号 2 与 cloze 目标 2 不是同一 scope',
    );
  });
}
