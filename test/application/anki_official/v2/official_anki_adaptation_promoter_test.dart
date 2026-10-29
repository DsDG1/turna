import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/v2/official_anki_adaptation_promoter.dart';
import 'package:turna/application/anki_official/v2/official_anki_adaptation_store.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_config_keys.dart';
import 'package:turna/domain/anki/adaptation/card_adaptation_plan.dart';

/// P6b staging → live rebinding (ADR 0057 §6, plan §12.3).
void main() {
  const sourceId = 'src-promote';

  late FakeOfficialAnkiEngine staging;
  late FakeOfficialAnkiEngine live;
  late OfficialAnkiAdaptationStore stagingStore;
  const promoter = OfficialAnkiAdaptationPromoter();

  setUp(() {
    staging = FakeOfficialAnkiEngine();
    live = FakeOfficialAnkiEngine();
    stagingStore = OfficialAnkiAdaptationStore(staging);
  });

  CardAdaptationPlan plan({
    String planId = 'plan-1',
    int revision = 1,
    int templateOrdinal = 0,
  }) {
    return CardAdaptationPlan(
      planId: planId,
      revision: revision,
      scope: AdaptationScope(
        sourceId: sourceId,
        notetypeId: 7,
        templateOrdinal: templateOrdinal,
      ),
      bindings: const <String, int>{'prompt': 0, 'answer': 1},
      front: const <AdaptationBlock>[
        AdaptationBlock(kind: 'text', fieldIndex: 0),
      ],
      back: const <AdaptationBlock>[
        AdaptationBlock(kind: 'text', fieldIndex: 1),
      ],
    );
  }

  Map<int, Set<int>> liveFacts({Map<int, Set<int>>? override}) =>
      override ??
      const <int, Set<int>>{
        7: <int>{0, 1},
      };

  test('a valid scope moves to live and becomes active there', () async {
    await stagingStore.activate(
      sourceId: sourceId,
      scopeKey: adaptationScopeKey(7, 0),
      plan: plan(),
    );

    final report = await promoter.promote(
      staging: staging,
      live: live,
      sourceId: sourceId,
      liveTemplateOrdinals: liveFacts(),
    );

    expect(report.promoted, 1);
    expect(report.skipped, isEmpty);

    final liveStore = OfficialAnkiAdaptationStore(live);
    expect(await liveStore.readRevision('plan-1', 1), isNotNull);
    final found = await liveStore.lookup(
      sourceId: sourceId,
      notetypeId: 7,
      templateOrdinal: 0,
      cardId: 1,
    );
    expect(found, isA<AdaptationPlanFound>());
  });

  test('a template that no longer exists on live is skipped, not guessed',
      () async {
    await stagingStore.activate(
      sourceId: sourceId,
      scopeKey: adaptationScopeKey(7, 3),
      plan: plan(templateOrdinal: 3),
    );

    final report = await promoter.promote(
      staging: staging,
      live: live,
      sourceId: sourceId,
      liveTemplateOrdinals: liveFacts(),
    );

    expect(report.promoted, 0);
    expect(
      report.skipped[adaptationScopeKey(7, 3)],
      AdaptationSkipReason.missingTemplate,
    );
    expect(
      live.configStore.entries.where(
        (e) => e.key.startsWith('turna.adapt.'),
      ),
      isEmpty,
      reason: '被跳过的组不得在 live 留下半份状态',
    );
  });

  test('an unknown notetype fails closed', () async {
    await stagingStore.activate(
      sourceId: sourceId,
      scopeKey: adaptationScopeKey(7, 0),
      plan: plan(),
    );

    final report = await promoter.promote(
      staging: staging,
      live: live,
      sourceId: sourceId,
      liveTemplateOrdinals: const <int, Set<int>>{},
    );

    expect(report.promoted, 0);
    expect(
      report.skipped[adaptationScopeKey(7, 0)],
      AdaptationSkipReason.missingTemplate,
    );
  });

  test('a manifest whose body is gone is skipped', () async {
    await stagingStore.activate(
      sourceId: sourceId,
      scopeKey: adaptationScopeKey(7, 0),
      plan: plan(),
    );
    await staging.setConfig(
      OfficialAnkiAdaptationConfigKeys.plan('plan-1', 1),
      null,
    );

    final report = await promoter.promote(
      staging: staging,
      live: live,
      sourceId: sourceId,
      liveTemplateOrdinals: liveFacts(),
    );

    expect(report.promoted, 0);
    expect(
      report.skipped[adaptationScopeKey(7, 0)],
      AdaptationSkipReason.missingBody,
    );
  });

  test('a malformed scope key is skipped', () async {
    staging.configStore[OfficialAnkiAdaptationConfigKeys.manifest(sourceId)] = {
      'schema': 1,
      'entries': {
        'garbage': {'planId': 'plan-1', 'revision': 1},
      },
    };

    final report = await promoter.promote(
      staging: staging,
      live: live,
      sourceId: sourceId,
      liveTemplateOrdinals: liveFacts(),
    );

    expect(report.skipped['garbage'], AdaptationSkipReason.malformedScope);
  });

  test('a plan whose own scope disagrees with its key is skipped', () async {
    // Manifest claims template 0, the body says template 1.
    staging.configStore[OfficialAnkiAdaptationConfigKeys.manifest(sourceId)] = {
      'schema': 1,
      'entries': {
        adaptationScopeKey(7, 0): {'planId': 'plan-1', 'revision': 1},
      },
    };
    await stagingStore.writeRevision(
      sourceId: sourceId,
      plan: plan(templateOrdinal: 1),
    );

    final report = await promoter.promote(
      staging: staging,
      live: live,
      sourceId: sourceId,
      liveTemplateOrdinals: liveFacts(),
    );

    expect(
      report.skipped[adaptationScopeKey(7, 0)],
      AdaptationSkipReason.scopeMismatch,
    );
  });

  test('promotion merges with existing live scopes', () async {
    final liveStore = OfficialAnkiAdaptationStore(live);
    await liveStore.activate(
      sourceId: sourceId,
      scopeKey: adaptationScopeKey(9, 0),
      plan: CardAdaptationPlan(
        planId: 'old-plan',
        revision: 4,
        scope: const AdaptationScope(
          sourceId: sourceId,
          notetypeId: 9,
          templateOrdinal: 0,
        ),
        bindings: const <String, int>{'prompt': 0, 'answer': 1},
        front: const <AdaptationBlock>[
          AdaptationBlock(kind: 'text', fieldIndex: 0),
        ],
        back: const <AdaptationBlock>[
          AdaptationBlock(kind: 'text', fieldIndex: 1),
        ],
      ),
    );

    await stagingStore.activate(
      sourceId: sourceId,
      scopeKey: adaptationScopeKey(7, 0),
      plan: plan(),
    );

    await promoter.promote(
      staging: staging,
      live: live,
      sourceId: sourceId,
      liveTemplateOrdinals: const <int, Set<int>>{
        7: <int>{0},
        9: <int>{0},
      },
    );

    final manifest = await liveStore.readManifest(sourceId);
    expect(
      manifest.entries.keys,
      containsAll(<String>['7:0', '9:0']),
      reason: '老 scope 不得因为一次新导入被抹掉',
    );
  });

  test('per-card decisions travel with the group', () async {
    await stagingStore.activate(
      sourceId: sourceId,
      scopeKey: adaptationScopeKey(7, 0),
      plan: plan(),
    );
    await stagingStore.writeCardOverride(
      sourceId: sourceId,
      cardId: 42,
      override: const AdaptationCardOverride.original(),
    );

    final report = await promoter.promote(
      staging: staging,
      live: live,
      sourceId: sourceId,
      liveTemplateOrdinals: liveFacts(),
    );

    expect(report.cardsCopied, 1);
    final liveStore = OfficialAnkiAdaptationStore(live);
    expect(
      await liveStore.lookup(
        sourceId: sourceId,
        notetypeId: 7,
        templateOrdinal: 0,
        cardId: 42,
      ),
      isA<AdaptationExplicitlyOriginal>(),
    );
  });

  test('promotion is idempotent', () async {
    await stagingStore.activate(
      sourceId: sourceId,
      scopeKey: adaptationScopeKey(7, 0),
      plan: plan(),
    );

    final first = await promoter.promote(
      staging: staging,
      live: live,
      sourceId: sourceId,
      liveTemplateOrdinals: liveFacts(),
    );
    final second = await promoter.promote(
      staging: staging,
      live: live,
      sourceId: sourceId,
      liveTemplateOrdinals: liveFacts(),
    );

    expect(first.promoted, 1);
    expect(second.promoted, 1);
    expect(second.skipped, isEmpty);
  });

  test('nothing staged means no live writes at all', () async {
    final report = await promoter.promote(
      staging: staging,
      live: live,
      sourceId: sourceId,
      liveTemplateOrdinals: liveFacts(),
    );

    expect(report.promoted, 0);
    expect(live.configStore, isEmpty);
  });

  group('in-session plans (the import wizard path)', () {
    test('plans held in memory are written to live and activated', () async {
      final report = await promoter.promotePlans(
        live: live,
        sourceId: sourceId,
        plans: {adaptationScopeKey(7, 0): plan()},
        liveTemplateOrdinals: liveFacts(),
      );

      expect(report.promoted, 1);
      final liveStore = OfficialAnkiAdaptationStore(live);
      expect(await liveStore.readRevision('plan-1', 1), isNotNull);
      expect(
        await liveStore.lookup(
          sourceId: sourceId,
          notetypeId: 7,
          templateOrdinal: 0,
          cardId: 1,
        ),
        isA<AdaptationPlanFound>(),
      );
    });

    test('an in-session plan for a vanished template is skipped', () async {
      final report = await promoter.promotePlans(
        live: live,
        sourceId: sourceId,
        plans: {adaptationScopeKey(7, 5): plan(templateOrdinal: 5)},
        liveTemplateOrdinals: liveFacts(),
      );

      expect(report.promoted, 0);
      expect(
        report.skipped[adaptationScopeKey(7, 5)],
        AdaptationSkipReason.missingTemplate,
      );
      expect(live.configStore, isEmpty);
    });

    test('an empty plan map writes nothing', () async {
      final report = await promoter.promotePlans(
        live: live,
        sourceId: sourceId,
        plans: const {},
        liveTemplateOrdinals: liveFacts(),
      );

      expect(report.promoted, 0);
      expect(live.configStore, isEmpty);
    });

    test('a key that disagrees with the plan scope is skipped', () async {
      final report = await promoter.promotePlans(
        live: live,
        sourceId: sourceId,
        plans: {adaptationScopeKey(7, 0): plan(templateOrdinal: 1)},
        liveTemplateOrdinals: liveFacts(),
      );

      expect(report.promoted, 0);
      expect(
        report.skipped[adaptationScopeKey(7, 0)],
        AdaptationSkipReason.scopeMismatch,
      );
    });
  });
}
