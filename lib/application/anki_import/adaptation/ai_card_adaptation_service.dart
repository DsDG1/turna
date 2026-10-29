import 'dart:convert';

import 'package:turna/application/ai/ai_json_schemas.dart';
import 'package:turna/application/ai/engine/ai_engine.dart';
import 'package:turna/application/ai/engine/ai_engine_config.dart';
import 'package:turna/application/anki_import/adaptation/adaptation_input_builder.dart';
import 'package:turna/application/anki_import/adaptation/adaptation_plan_validator.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/core/ohos_target.dart';
import 'package:turna/domain/anki/adaptation/card_adaptation_plan.dart';

/// One raw reply, already stripped of transport details so the orchestration
/// here can be tested without a network or an engine instance.
class AdaptationRawReply {
  const AdaptationRawReply({required this.content, this.truncated = false});

  final String content;

  /// The provider hit its output-token limit. Retrying the same request can
  /// never succeed, so this is a terminal rejection, not a repair round.
  final bool truncated;
}

typedef AdaptationJsonCall = Future<AdaptationRawReply> Function({
  required List<Map<String, dynamic>> messages,
  Map<String, dynamic>? jsonSchema,
});

/// Outcome of one adaptation attempt. All three are non-throwing: AI failure
/// must never break an import (ADR 0057 §7).
sealed class CardAdaptationResult {
  const CardAdaptationResult();
}

final class CardAdaptationAccepted extends CardAdaptationResult {
  const CardAdaptationAccepted({
    required this.plan,
    required this.input,
    required this.repaired,
  });

  final CardAdaptationPlan plan;
  final AdaptationInput input;

  /// True when the first reply was rejected locally and a second attempt
  /// succeeded.
  final bool repaired;
}

final class CardAdaptationRejected extends CardAdaptationResult {
  const CardAdaptationRejected({
    required this.code,
    this.issues = const <AdaptationIssue>[],
  });

  /// `truncated` | `not_json` | `invalid_plan`.
  final String code;
  final List<AdaptationIssue> issues;
}

/// AI unavailable is a normal state: no configuration, a build without the AI
/// module (ADR 0056), a transport failure or a bad key. Callers continue with
/// the local result or the original card.
final class CardAdaptationUnavailable extends CardAdaptationResult {
  const CardAdaptationUnavailable(this.reason);

  /// `ai_unavailable` | `transport`.
  final String reason;
}

/// Turns a structural group into one constrained AI request, validates the
/// reply locally, and gives the model exactly one repair attempt.
///
/// Everything the plan needs is decided here or rejected here; nothing about
/// the reply is trusted, and nothing about a failure escapes as an exception.
class AiCardAdaptationService {
  const AiCardAdaptationService({
    required AdaptationJsonCall call,
    bool aiEnabled = true,
  })  : _call = call,
        _aiEnabled = aiEnabled;

  final AdaptationJsonCall _call;
  final bool _aiEnabled;

  /// Production binding: every real request still goes through
  /// `AiEngine.requestJson` (the app's single LLM exit), so cancellation,
  /// caching, usage accounting and the OHOS compliance gate keep applying.
  factory AiCardAdaptationService.viaEngine({
    required AiEngine engine,
    required AiEngineConfig config,
    bool aiEnabled = true,
    Duration timeout = const Duration(seconds: 90),
    // Reasoning models spend output tokens on hidden thinking before they emit
    // the plan (measured on MiniMax-M3.1-Flash: ~9k chars of reasoning). A small
    // budget truncates the JSON and turns into a terminal `truncated`.
    int maxTokens = 4000,
  }) {
    return AiCardAdaptationService(
      aiEnabled: aiEnabled,
      call: ({
        required List<Map<String, dynamic>> messages,
        Map<String, dynamic>? jsonSchema,
      }) async {
        final result = await engine.requestJson(
          config: config,
          messages: messages,
          jsonSchema: jsonSchema,
          // Low temperature: this is a structured extraction task, not prose.
          temperature: 0.2,
          maxTokens: maxTokens,
          timeout: timeout,
        );
        return AdaptationRawReply(
          content: result.content,
          truncated: result.isTruncated,
        );
      },
    );
  }

  static const int _maxAttempts = 2;

  Future<CardAdaptationResult> generate({
    required OfficialAnkiProjectionSchema schema,
    required AdaptationFacts facts,
    AdaptationInputBudget budget = const AdaptationInputBudget(),
  }) async {
    // Compliance gate (ADR 0056) + user preference. Both mean "continue
    // locally", never "fail the import".
    if (!_aiEnabled || isDegraded(OhosDegradation.aiGeneration)) {
      return const CardAdaptationUnavailable('ai_unavailable');
    }

    final input = AdaptationInputBuilder.build(schema: schema, budget: budget);
    var messages = input.messages;
    var issues = const <AdaptationIssue>[];
    var lastCode = 'not_json';

    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      AdaptationRawReply reply;
      try {
        reply = await _call(
          messages: messages,
          jsonSchema: AiJsonSchemas.cardAdaptation,
        );
      } catch (error) {
        // The error text may carry a URL or a provider message; log the class
        // only, per the "no content in diagnostics" rule (plan §11.3).
        logger.w('card adaptation call failed: ${error.runtimeType}');
        return const CardAdaptationUnavailable('transport');
      }

      if (reply.truncated) {
        return const CardAdaptationRejected(code: 'truncated');
      }

      final parsed = _parse(reply.content, facts);
      if (parsed == null) {
        lastCode = 'not_json';
        messages = _repairMessages(
          input.messages,
          reply.content,
          const ['not_json'],
        );
        continue;
      }

      // The app owns scope: a model-supplied source/notetype/template is
      // overwritten before validation, so it cannot widen its own blast radius.
      final plan = _withFactsScope(parsed, facts);
      final validation = AdaptationPlanValidator.validate(plan, facts: facts);
      if (validation.ok) {
        return CardAdaptationAccepted(
          plan: plan,
          input: input,
          repaired: attempt > 0,
        );
      }
      issues = validation.issues;
      lastCode = 'invalid_plan';
      logger.w(
        'card adaptation rejected locally: ${issues.map((i) => i.name).join(',')}',
      );
      messages = _repairMessages(
        input.messages,
        reply.content,
        issues.map((issue) => issue.name).toList(),
      );
    }

    return CardAdaptationRejected(code: lastCode, issues: issues);
  }

  static CardAdaptationPlan? _parse(
    String content,
    AdaptationFacts facts,
  ) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return null;
    try {
      final decoded = _decode(trimmed);
      if (decoded is! Map) return null;
      final map = Map<String, Object?>.from(decoded);
      // scope 由应用附加（协议明确不让模型决定 source/notetype），所以模型
      // 省略它是遵守协议，不是格式错误。这里用调用方给的事实补上，随后仍走
      // `_withFactsScope` 覆盖——少了这一步会把合规回复误判成 not_json。
      map['scope'] ??= <String, Object?>{
        'sourceId': facts.sourceId,
        'notetypeId': facts.notetypeId,
        'templateOrdinal': facts.templateOrdinals.isEmpty
            ? 0
            : facts.templateOrdinals.first,
      };
      return CardAdaptationPlan.fromJson(map);
    } on AdaptationPlanFormatException {
      return null;
    } catch (_) {
      return null;
    }
  }

  static Object? _decode(String content) {
    // Tolerate a fenced reply (` ```json ... ``` `) — providers add it even in
    // JSON mode, and a fence is not a reason to burn the repair attempt.
    var body = content.trim();
    if (body.startsWith('```')) {
      final firstBreak = body.indexOf('\n');
      if (firstBreak > 0) body = body.substring(firstBreak + 1);
      final closing = body.lastIndexOf('```');
      if (closing >= 0) body = body.substring(0, closing);
    }
    return _jsonDecoder.convert(body.trim());
  }

  static const _jsonDecoder = JsonDecoder();

  static CardAdaptationPlan _withFactsScope(
    CardAdaptationPlan plan,
    AdaptationFacts facts,
  ) {
    return CardAdaptationPlan(
      planId: plan.planId,
      revision: plan.revision,
      scope: AdaptationScope(
        sourceId: facts.sourceId,
        notetypeId: facts.notetypeId,
        templateOrdinal: plan.scope.templateOrdinal,
        clozeTarget: plan.scope.clozeTarget,
      ),
      bindings: plan.bindings,
      front: plan.front,
      back: plan.back,
      schemaVersion: plan.schemaVersion,
      optionalExercises: plan.optionalExercises,
      fallback: plan.fallback,
      origin: plan.origin,
      fingerprints: plan.fingerprints,
      provenance: plan.provenance,
    );
  }

  /// The repair turn keeps the original request plus the rejected reply, so the
  /// model has both the task and its own mistake in context.
  static List<Map<String, dynamic>> _repairMessages(
    List<Map<String, dynamic>> base,
    String previousReply,
    List<String> problems,
  ) {
    return <Map<String, dynamic>>[
      ...base,
      {'role': 'assistant', 'content': previousReply},
      {
        'role': 'user',
        'content': 'Your previous reply was rejected locally: '
            '${problems.join(', ')}. Return the complete corrected JSON object '
            'only. Do not explain.',
      },
    ];
  }
}
