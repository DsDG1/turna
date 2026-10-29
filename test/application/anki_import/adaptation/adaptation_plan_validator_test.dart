import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_import/adaptation/adaptation_plan_validator.dart';
import 'package:turna/domain/anki/adaptation/card_adaptation_plan.dart';

/// P5 local gate: a plan is activated only when it is structurally and
/// semantically safe. Nothing here trusts the model (ADR 0057 §7).
void main() {
  Map<String, Object?> block(int fieldIndex, {String kind = 'text'}) =>
      <String, Object?>{'kind': kind, 'fieldIndex': fieldIndex};

  Map<String, Object?> planJson({
    Map<String, Object?> scope = const {
      'sourceId': 'src-1',
      'notetypeId': 7,
      'templateOrdinal': 0,
    },
    Map<String, Object?>? bindings,
    List<Map<String, Object?>>? front,
    List<Map<String, Object?>>? back,
    List<String>? exercises,
    String fallback = 'original',
    Object? schemaVersion = 1,
  }) {
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'planId': 'plan-1',
      'revision': 1,
      'scope': scope,
      'bindings': bindings ?? <String, Object?>{'prompt': 0, 'answer': 1},
      'front': front ?? [block(0)],
      'back': back ?? [block(1)],
      'optionalExercises': exercises ?? const <String>[],
      'fallback': fallback,
    };
  }

  const facts = AdaptationFacts(
    sourceId: 'src-1',
    notetypeId: 7,
    fieldCount: 3,
    templateOrdinals: [0, 1],
    frontFieldOrds: {0, 2},
    backFieldOrds: {1},
  );

  AdaptationValidation validate(
    Map<String, Object?> json, {
    AdaptationFacts against = facts,
  }) =>
      AdaptationPlanValidator.validate(
        CardAdaptationPlan.fromJson(json),
        facts: against,
      );

  test('a well-formed plan passes', () {
    expect(validate(planJson()).ok, isTrue);
  });

  test('the answer field on the question face is rejected', () {
    final result = validate(
      planJson(front: [block(1)], bindings: {'prompt': 0, 'answer': 1}),
    );
    expect(result.ok, isFalse);
    expect(result.issues, contains(AdaptationIssue.answerOnFront));
  });

  test('a back-only field on the question face is rejected', () {
    final result = validate(planJson(front: [block(1)]));
    expect(result.issues, contains(AdaptationIssue.backOnlyFieldOnFront));
  });

  test('an unknown block kind is rejected', () {
    final result = validate(
      planJson(front: [block(0, kind: 'executeScript')]),
    );
    expect(result.issues, contains(AdaptationIssue.unknownBlockKind));
  });

  test('an out-of-range field index is rejected', () {
    final result = validate(planJson(front: [block(9)]));
    expect(result.issues, contains(AdaptationIssue.fieldOutOfRange));
  });

  test('an unknown exercise is rejected', () {
    final result = validate(planJson(exercises: ['runShell']));
    expect(result.issues, contains(AdaptationIssue.unknownExercise));
  });

  test('a scope from another source or notetype is rejected', () {
    final otherSource = validate(
      planJson(scope: const {
        'sourceId': 'src-2',
        'notetypeId': 7,
        'templateOrdinal': 0,
      }),
    );
    expect(otherSource.issues, contains(AdaptationIssue.scopeSource));

    final otherNotetype = validate(
      planJson(scope: const {
        'sourceId': 'src-1',
        'notetypeId': 99,
        'templateOrdinal': 0,
      }),
    );
    expect(otherNotetype.issues, contains(AdaptationIssue.scopeNotetype));

    final otherTemplate = validate(
      planJson(scope: const {
        'sourceId': 'src-1',
        'notetypeId': 7,
        'templateOrdinal': 5,
      }),
    );
    expect(otherTemplate.issues, contains(AdaptationIssue.scopeTemplate));
  });

  test('an empty front face is rejected', () {
    final result = validate(planJson(front: const []));
    expect(result.issues, contains(AdaptationIssue.emptyFront));
  });

  test('a fallback other than original is rejected', () {
    final result = validate(planJson(fallback: 'skipCard'));
    expect(result.issues, contains(AdaptationIssue.unknownFallback));
  });

  test('an unknown binding role or schema version is rejected', () {
    expect(
      validate(planJson(bindings: {'prompt': 0, 'answer': 1, 'script': 2}))
          .issues,
      contains(AdaptationIssue.unknownBindingRole),
    );
    expect(
      validate(planJson(schemaVersion: 99)).issues,
      contains(AdaptationIssue.schemaVersion),
    );
  });

  test('a plan without an envelope is a format error, not a plan', () {
    expect(
      () => CardAdaptationPlan.fromJson(const {'revision': 1}),
      throwsA(
        isA<AdaptationPlanFormatException>()
            .having((e) => e.code, 'code', 'plan_id'),
      ),
    );
    expect(
      () => CardAdaptationPlan.fromJson(const {
        'planId': 'p',
        'revision': 1,
        'front': <Object?>[],
      }),
      throwsA(isA<AdaptationPlanFormatException>()),
    );
  });

  test('encode/decode round-trips blocks, bindings and scope', () {
    final plan = CardAdaptationPlan.fromJson(planJson(
      exercises: ['dictation'],
      bindings: {'prompt': 0, 'answer': 1, 'image': 2},
      front: [block(0), block(2, kind: 'imageGroup')],
      back: [block(1)],
    ));
    final decoded = CardAdaptationPlan.fromJson(plan.toJson());

    expect(decoded.bindings, plan.bindings);
    expect(decoded.front.map((b) => b.kind), ['text', 'imageGroup']);
    expect(decoded.front.last.fieldIndex, 2);
    expect(decoded.optionalExercises, ['dictation']);
    expect(decoded.scope.templateOrdinal, 0);
    expect(decoded.fallback, 'original');
  });
}
