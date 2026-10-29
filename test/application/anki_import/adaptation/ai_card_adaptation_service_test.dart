import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_import/adaptation/adaptation_plan_validator.dart';
import 'package:turna/application/anki_import/adaptation/ai_card_adaptation_service.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';

/// P5 orchestration gate: one call per group, one bounded repair attempt, and
/// every failure is a value — never an exception into the import flow.
void main() {
  const facts = AdaptationFacts(
    sourceId: 'src-1',
    notetypeId: 7,
    fieldCount: 2,
    templateOrdinals: [0],
    frontFieldOrds: {0},
    backFieldOrds: {1},
  );

  const schema = OfficialAnkiProjectionSchema(
    notetypeId: 7,
    name: 'Basic',
    kind: 'normal',
    fieldNames: ['Expression', 'Meaning'],
    templateNames: ['Card 1'],
    schemaFingerprint: 'fp',
  );

  String planReply({
    String sourceId = 'src-1',
    int answerFieldInFront = -1,
  }) {
    return jsonEncode(<String, Object?>{
      'schemaVersion': 1,
      'planId': 'plan-1',
      'revision': 1,
      'scope': <String, Object?>{
        'sourceId': sourceId,
        'notetypeId': 7,
        'templateOrdinal': 0,
      },
      'bindings': <String, Object?>{'prompt': 0, 'answer': 1},
      'front': <Object?>[
        <String, Object?>{'kind': 'text', 'fieldIndex': 0},
        if (answerFieldInFront >= 0)
          <String, Object?>{'kind': 'text', 'fieldIndex': answerFieldInFront},
      ],
      'back': <Object?>[
        <String, Object?>{'kind': 'text', 'fieldIndex': 1},
      ],
      'fallback': 'original',
    });
  }

  test('a valid reply is accepted and the schema rides along', () async {
    final calls = <List<Map<String, dynamic>>>[];
    Map<String, dynamic>? seenSchema;
    final service = AiCardAdaptationService(
      call: ({
        required List<Map<String, dynamic>> messages,
        Map<String, dynamic>? jsonSchema,
      }) async {
        calls.add(messages);
        seenSchema = jsonSchema;
        return AdaptationRawReply(content: planReply());
      },
    );

    final result = await service.generate(schema: schema, facts: facts);

    expect(result, isA<CardAdaptationAccepted>());
    final accepted = result as CardAdaptationAccepted;
    expect(accepted.repaired, isFalse);
    expect(accepted.plan.scope.sourceId, 'src-1');
    expect(calls, hasLength(1));
    expect(seenSchema, isNotNull, reason: '必须传 json_schema 信封');
  });

  test('a model-supplied source is overwritten by the app scope', () async {
    final service = AiCardAdaptationService(
      call: ({
        required List<Map<String, dynamic>> messages,
        Map<String, dynamic>? jsonSchema,
      }) async =>
          AdaptationRawReply(content: planReply(sourceId: 'someone-else')),
    );

    final result = await service.generate(schema: schema, facts: facts);

    expect(result, isA<CardAdaptationAccepted>());
    expect(
      (result as CardAdaptationAccepted).plan.scope.sourceId,
      'src-1',
      reason: 'AI 不能自己指定 source',
    );
  });

  test('one invalid reply gets exactly one repair attempt', () async {
    final calls = <List<Map<String, dynamic>>>[];
    final service = AiCardAdaptationService(
      call: ({
        required List<Map<String, dynamic>> messages,
        Map<String, dynamic>? jsonSchema,
      }) async {
        calls.add(messages);
        return AdaptationRawReply(
          content: calls.length == 1
              ? planReply(answerFieldInFront: 1)
              : planReply(),
        );
      },
    );

    final result = await service.generate(schema: schema, facts: facts);

    expect(result, isA<CardAdaptationAccepted>());
    expect((result as CardAdaptationAccepted).repaired, isTrue);
    expect(calls, hasLength(2));
    expect(
      calls.last.map((m) => m['role']),
      containsAllInOrder(['system', 'user', 'assistant', 'user']),
      reason: '修复轮要带上被拒的原回复',
    );
  });

  test('a second invalid reply is rejected, not retried forever', () async {
    var calls = 0;
    final service = AiCardAdaptationService(
      call: ({
        required List<Map<String, dynamic>> messages,
        Map<String, dynamic>? jsonSchema,
      }) async {
        calls++;
        return AdaptationRawReply(content: planReply(answerFieldInFront: 1));
      },
    );

    final result = await service.generate(schema: schema, facts: facts);

    expect(result, isA<CardAdaptationRejected>());
    final rejected = result as CardAdaptationRejected;
    expect(rejected.code, 'invalid_plan');
    expect(rejected.issues, contains(AdaptationIssue.answerOnFront));
    expect(calls, 2, reason: '默认每组最多一次修复尝试');
  });

  test('non-JSON replies end as not_json', () async {
    final service = AiCardAdaptationService(
      call: ({
        required List<Map<String, dynamic>> messages,
        Map<String, dynamic>? jsonSchema,
      }) async =>
          AdaptationRawReply(content: 'Sure! Here is your plan:'),
    );

    final result = await service.generate(schema: schema, facts: facts);

    expect(result, isA<CardAdaptationRejected>());
    expect((result as CardAdaptationRejected).code, 'not_json');
  });

  test('a fenced reply is still parsed (no wasted repair)', () async {
    final service = AiCardAdaptationService(
      call: ({
        required List<Map<String, dynamic>> messages,
        Map<String, dynamic>? jsonSchema,
      }) async =>
          AdaptationRawReply(content: '```json\n${planReply()}\n```'),
    );

    final result = await service.generate(schema: schema, facts: facts);

    expect(result, isA<CardAdaptationAccepted>());
  });

  test('a reply without scope is accepted: scope is app-owned', () async {
    // 真实端点（MiniMax）按协议省略了 scope，旧解析把它误判成 not_json。
    // 协议让模型别管 scope，解析就不能因为它缺席而失败。
    final reply = jsonEncode(<String, Object?>{
      'planId': 'turkish-basics-template-0-r1',
      'revision': 1,
      'fallback': 'original',
      'bindings': <String, Object?>{'prompt': 0, 'answer': 1},
      'front': <Object?>[
        <String, Object?>{'kind': 'text', 'fieldIndex': 0},
      ],
      'back': <Object?>[
        <String, Object?>{'kind': 'text', 'fieldIndex': 1},
      ],
    });
    var calls = 0;
    final service = AiCardAdaptationService(
      call: ({
        required List<Map<String, dynamic>> messages,
        Map<String, dynamic>? jsonSchema,
      }) async {
        calls++;
        return AdaptationRawReply(content: reply);
      },
    );

    final result = await service.generate(schema: schema, facts: facts);

    expect(result, isA<CardAdaptationAccepted>(), reason: 'scope 缺席不是格式错误');
    final accepted = result as CardAdaptationAccepted;
    expect(calls, 1, reason: '不该为这件事浪费一次修复');
    expect(accepted.plan.scope.sourceId, 'src-1');
    expect(accepted.plan.scope.notetypeId, 7);
    expect(accepted.plan.scope.templateOrdinal, 0);
    expect(accepted.plan.defaultExercise, 'flip');
  });

  test('a truncated reply is terminal, not repairable', () async {
    var calls = 0;
    final service = AiCardAdaptationService(
      call: ({
        required List<Map<String, dynamic>> messages,
        Map<String, dynamic>? jsonSchema,
      }) async {
        calls++;
        return const AdaptationRawReply(content: '{"planId":"p"', truncated: true);
      },
    );

    final result = await service.generate(schema: schema, facts: facts);

    expect(result, isA<CardAdaptationRejected>());
    expect((result as CardAdaptationRejected).code, 'truncated');
    expect(calls, 1);
  });

  test('a transport failure is unavailable, not fatal', () async {
    final service = AiCardAdaptationService(
      call: ({
        required List<Map<String, dynamic>> messages,
        Map<String, dynamic>? jsonSchema,
      }) async =>
          throw Exception('connection reset https://example.invalid/v1'),
    );

    final result = await service.generate(schema: schema, facts: facts);

    expect(result, isA<CardAdaptationUnavailable>());
    expect((result as CardAdaptationUnavailable).reason, 'transport');
  });

  test('AI disabled makes no call at all', () async {
    var calls = 0;
    final service = AiCardAdaptationService(
      aiEnabled: false,
      call: ({
        required List<Map<String, dynamic>> messages,
        Map<String, dynamic>? jsonSchema,
      }) async {
        calls++;
        return AdaptationRawReply(content: planReply());
      },
    );

    final result = await service.generate(schema: schema, facts: facts);

    expect(result, isA<CardAdaptationUnavailable>());
    expect((result as CardAdaptationUnavailable).reason, 'ai_unavailable');
    expect(calls, 0);
  });
}
