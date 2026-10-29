import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/v2/adaptation_promotion_flow.dart';
import 'package:turna/application/anki_official/v2/official_anki_adaptation_promoter.dart';
import 'package:turna/application/anki_official/v2/official_anki_adaptation_store.dart';
import 'package:turna/domain/anki/adaptation/card_adaptation_plan.dart';

/// P6c/P8 gate: the commit-time promotion is best-effort and never invents a
/// template ordinal. Everything here runs without a device (ADR 0057 §6).
void main() {
  const sourceId = 'src-flow';

  CardAdaptationPlan plan({int templateOrdinal = 0}) {
    return CardAdaptationPlan(
      planId: 'plan-1',
      revision: 1,
      scope: AdaptationScope(
        sourceId: sourceId,
        notetypeId: 1,
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

  OfficialAnkiProjectionSchema schema({
    bool withTemplateFacts = true,
    int ordinal = 0,
  }) {
    return OfficialAnkiProjectionSchema(
      notetypeId: 1,
      name: 'Basic',
      kind: 'normal',
      fieldNames: const ['Front', 'Back'],
      templateNames: const ['Card 1'],
      schemaFingerprint: 'fp',
      templateFacts: withTemplateFacts
          ? OfficialAnkiTemplateFacts(
              hash: 'h',
              templates: [
                OfficialAnkiTemplateFact(
                  ord: ordinal,
                  name: 'Card 1',
                  frontFields: const [0],
                  backFields: const [1],
                ),
              ],
            )
          : null,
    );
  }

  test('no live engine is a no-op, not a crash', () async {
    final report = await promoteAdaptationDrafts(
      live: null,
      sourceId: sourceId,
      plans: {adaptationScopeKey(1, 0): plan()},
    );
    expect(report.promoted, 0);
  });

  test('no drafts means no engine call at all', () async {
    final engine = FakeOfficialAnkiEngine();
    final report = await promoteAdaptationDrafts(
      live: engine,
      sourceId: sourceId,
      plans: const {},
    );

    expect(report.promoted, 0);
    expect(engine.getConfigCalls, 0);
  });

  test('a schema read failure is swallowed: import already succeeded',
      () async {
    final engine = _ThrowingSchemaEngine();
    final report = await promoteAdaptationDrafts(
      live: engine,
      sourceId: sourceId,
      plans: {adaptationScopeKey(1, 0): plan()},
    );

    expect(report.promoted, 0);
    expect(report.skipped, isEmpty);
  });

  test('a schema without template facts cannot prove the ordinal', () async {
    final engine = _SchemaEngine(schema(withTemplateFacts: false));
    final report = await promoteAdaptationDrafts(
      live: engine,
      sourceId: sourceId,
      plans: {adaptationScopeKey(1, 0): plan()},
    );

    expect(report.promoted, 0);
    expect(
      report.skipped[adaptationScopeKey(1, 0)],
      AdaptationSkipReason.missingTemplate,
    );
    expect(
      engine.configStore.keys.where((key) => key.startsWith('turna.adapt.')),
      isEmpty,
    );
  });

  test('a proven ordinal promotes and becomes active on live', () async {
    final engine = _SchemaEngine(schema());
    final report = await promoteAdaptationDrafts(
      live: engine,
      sourceId: sourceId,
      plans: {adaptationScopeKey(1, 0): plan()},
    );

    expect(report.promoted, 1);
    final store = OfficialAnkiAdaptationStore(engine);
    expect(
      await store.lookup(
        sourceId: sourceId,
        notetypeId: 1,
        templateOrdinal: 0,
        cardId: 7,
      ),
      isA<AdaptationPlanFound>(),
    );
  });
}

class _SchemaEngine extends FakeOfficialAnkiEngine {
  _SchemaEngine(this.schema);

  final OfficialAnkiProjectionSchema schema;

  @override
  Future<List<OfficialAnkiProjectionSchema>> getProjectionSchemas({
    List<int> notetypeIds = const <int>[],
    bool includeSamples = false,
    int sampleLimit = 3,
  }) async =>
      [schema];
}

class _ThrowingSchemaEngine extends FakeOfficialAnkiEngine {
  @override
  Future<List<OfficialAnkiProjectionSchema>> getProjectionSchemas({
    List<int> notetypeIds = const <int>[],
    bool includeSamples = false,
    int sampleLimit = 3,
  }) async =>
      throw StateError('projection unavailable');
}
