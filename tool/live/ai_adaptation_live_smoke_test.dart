// 一次性真实端点冒烟（不属于默认测试集，不在 test/ 下，CI 不会跑）。
//
// 目的：验证 `AiCardAdaptationService` + JSON Schema 信封 + 本地校验在真实
// 模型上到底能不能产出一份可用方案。凭据从仓库外的本地文件读取，**只在
// 运行时读一次**：不写进源码、不打印、不落盘到日志。
//
// 运行：
//   flutter test tool/live/ai_adaptation_live_smoke_test.dart
//
// 结果摘要写到 `build/live_adaptation_smoke.log`（build/ 不入库），因为测试
// 里禁止 print/debugPrint。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/ai/ai_json_schemas.dart';
import 'package:turna/application/ai/engine/ai_cache.dart';
import 'package:turna/application/ai/engine/ai_engine.dart';
import 'package:turna/application/ai/engine/ai_engine_config.dart';
import 'package:turna/application/ai/engine/ai_engine_result.dart';
import 'package:turna/application/ai/engine/ai_http_client.dart';
import 'package:turna/application/ai/engine/ai_provider_preset.dart';
import 'package:turna/application/anki_import/adaptation/adaptation_plan_validator.dart';
import 'package:turna/application/anki_import/adaptation/ai_card_adaptation_service.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';

// 凭据路径从环境变量读：仓库里不放任何个人路径，也不放凭据本身。
const String _credentialsEnv = 'TURNA_LIVE_CREDENTIALS';
const String _logPath = 'build/live_adaptation_smoke.log';

class _Credentials {
  const _Credentials({
    required this.baseUrl,
    required this.model,
    required this.apiKey,
  });

  final String baseUrl;
  final String model;
  final String apiKey;

  bool get isComplete =>
      baseUrl.isNotEmpty && model.isNotEmpty && apiKey.isNotEmpty;
}

/// 文件内容不是严格的 env 格式，逐行认三类：BASE_URL=、model="..."、裸 key。
_Credentials _readCredentials(String raw) {
  var baseUrl = '';
  var model = '';
  var apiKey = '';
  for (final line in raw.split(RegExp(r'\r?\n'))) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) continue;
    if (trimmed.startsWith('OPENAI_BASE_URL=')) {
      baseUrl = trimmed.substring('OPENAI_BASE_URL='.length).trim();
    } else if (trimmed.startsWith('model=')) {
      model = trimmed
          .substring('model='.length)
          .trim()
          .replaceAll('"', '')
          .replaceAll(',', '');
    } else if (trimmed.startsWith('sk-')) {
      apiKey = trimmed.replaceAll(RegExp(r'[",]'), '');
    }
  }
  return _Credentials(baseUrl: baseUrl, model: model, apiKey: apiKey);
}

void _append(String line) {
  final file = File(_logPath);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync('$line\n', mode: FileMode.append, flush: true);
}

void main() {
  final credentialsPath = Platform.environment[_credentialsEnv] ?? '';
  final credentialsFile = File(credentialsPath);
  if (credentialsPath.isEmpty || !credentialsFile.existsSync()) {
    test(
      'live smoke skipped: credentials path not provided',
      () {},
      skip: 'set TURNA_LIVE_CREDENTIALS to a local file with the endpoint config',
    );
    return;
  }
  final credentials = _readCredentials(credentialsFile.readAsStringSync());
  if (!credentials.isComplete) {
    test('live smoke skipped: credentials incomplete', () {}, skip: true);
    return;
  }
  File(_logPath).writeAsStringSync('', flush: true);

  const schema = OfficialAnkiProjectionSchema(
    notetypeId: 7,
    name: 'Turkish Basics',
    kind: 'normal',
    fieldNames: ['Expression', 'Meaning', 'Audio', 'Image'],
    templateNames: ['Card 1'],
    schemaFingerprint: 'live-fp',
    samples: [
      OfficialAnkiProjectionSample(
        noteId: 1,
        fields: ['merhaba', 'hello', '[sound:merhaba.mp3]', ''],
      ),
      OfficialAnkiProjectionSample(
        noteId: 2,
        fields: ['teşekkürler', 'thanks', '[sound:tesekkurler.mp3]', ''],
      ),
      OfficialAnkiProjectionSample(
        noteId: 3,
        fields: ['güle güle', 'goodbye', '', '<img src="wave.png">'],
      ),
    ],
    templateFacts: OfficialAnkiTemplateFacts(
      hash: 'live-template-hash',
      templates: [
        OfficialAnkiTemplateFact(
          ord: 0,
          name: 'Card 1',
          frontFields: [0, 2],
          backFields: [1, 3],
        ),
      ],
    ),
  );

  const facts = AdaptationFacts(
    sourceId: 'live-src',
    notetypeId: 7,
    fieldCount: 4,
    templateOrdinals: [0],
    frontFieldOrds: {0, 2},
    backFieldOrds: {1, 3},
  );

  test(
    'live: one adaptation call against the configured endpoint',
    () async {
      final config = AiEngineConfig(
        preset: kCustomPreset,
        apiKey: credentials.apiKey,
        modelChat: credentials.model,
        modelJson: credentials.model,
        customBaseUrl: credentials.baseUrl,
      );
      final engine = AiEngine(AiHttpClient(), AiCache());

      // 探针：先直接打一次最小请求，把真实错误抓出来。服务层刻意只记异常
      // 类型，这里需要看到消息本身才能判断是配额、schema 还是参数问题。
      String sanitize(Object? value) => '$value'.replaceAll(
            credentials.apiKey,
            '***',
          );
      try {
        final probe = await engine.requestJson(
          config: config,
          messages: const [
            {
              'role': 'user',
              'content': 'Reply with exactly {"planId":"probe"} and nothing else.',
            },
          ],
          jsonSchema: AiJsonSchemas.cardAdaptation,
          maxTokens: 600,
          timeout: const Duration(seconds: 90),
        );
        _append('probe=ok chars=${probe.content.length}');
        _append('probe_finish=${probe.finishReason ?? "none"}');
      } catch (error) {
        _append('probe=threw');
        _append('probe_type=${error.runtimeType}');
        final message = sanitize(error);
        _append(
          'probe_message=${message.length > 300 ? message.substring(0, 300) : message}',
        );
      }

      AiEngineResult? lastReply;
      final stopwatch = Stopwatch()..start();
      final service = AiCardAdaptationService(
        call: ({
          required List<Map<String, dynamic>> messages,
          Map<String, dynamic>? jsonSchema,
        }) async {
          final reply = await engine.requestJson(
            config: config,
            messages: messages,
            jsonSchema: jsonSchema ?? AiJsonSchemas.cardAdaptation,
            temperature: 0.2,
            // 推理型模型先花输出预算想事情；1200 在 M3.1-Flash 上直接把 content
            // 挤成空串（finish_reason=length）。给足预算再看链路。
            maxTokens: 4000,
            timeout: const Duration(seconds: 120),
          );
          lastReply = reply;
          return AdaptationRawReply(
            content: reply.content,
            truncated: reply.isTruncated,
          );
        },
      );

      final result = await service.generate(schema: schema, facts: facts);
      stopwatch.stop();

      _append('elapsed_ms=${stopwatch.elapsedMilliseconds}');
      final reply = lastReply;
      _append('call_happened=${reply != null}');
      if (reply != null) {
        _append('content_chars=${reply.content.length}');
        final head = sanitize(reply.content);
        _append('content_head=${head.length > 400 ? head.substring(0, 400) : head}');
        _append('reasoning_chars=${reply.reasoningText?.length ?? 0}');
        _append('cache_hit=${reply.cacheHit}');
        _append('finish_reason=${reply.finishReason ?? "none"}');
        _append('usage_keys=${reply.usage?.keys.join(",") ?? "none"}');
        _append('truncated=${reply.isTruncated}');
      }
      switch (result) {
        case CardAdaptationAccepted():
          _append('outcome=accepted');
          _append('plan_id=${result.plan.planId}');
          _append('revision=${result.plan.revision}');
          _append('default_exercise=${result.plan.defaultExercise}');
          _append(
            'blocks=front:${result.plan.front.length}'
            ',back:${result.plan.back.length}',
          );
          _append('bindings=${result.plan.bindings}');
          _append('repaired=${result.repaired}');
          _append('input_chars=${result.input.characterCount}');
          _append('input_samples=${result.input.sampleCount}');
          final revalidation = AdaptationPlanValidator.validate(
            result.plan,
            facts: facts,
          );
          _append('revalidation_ok=${revalidation.ok}');
          _append('revalidation_issues=${revalidation.issues}');
        case CardAdaptationRejected():
          _append('outcome=rejected');
          _append('code=${result.code}');
          _append('issues=${result.issues}');
        case CardAdaptationUnavailable():
          _append('outcome=unavailable');
          _append('reason=${result.reason}');
      }

      // 这条测试只证明「端点答了、链路通」：模型输出是否合规由上面记录的
      // outcome 说明，不把模型的一次发挥当断言。
      expect(reply, isNotNull, reason: '请求根本没发出去');
      expect(reply!.content, isNotEmpty, reason: '端点返回空内容');
      expect(
        result,
        isNot(isA<CardAdaptationUnavailable>()),
        reason: '不可用说明链路没打通（配置/传输），见 $_logPath',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
