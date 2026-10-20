// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:turna/application/ai/engine/ai_engine_config.dart';
import 'package:turna/application/ai/engine/ai_provider_preset.dart';

void main() {
  group('AiEngineConfig defaults', () {
    test('defaults to the DeepSeek preset with an empty key', () {
      const c = AiEngineConfig(apiKey: '');
      expect(c.preset.id, AiProvider.deepseek);
      expect(c.baseUrl, 'https://api.deepseek.com');
      expect(c.modelChat, 'deepseek-v4.1-flash');
      expect(c.modelJson, 'deepseek-v4.1-flash');
      expect(c.apiKey, '');
      expect(c.isComplete, isFalse); // empty key
    });

    test('reasoning is opt-in: off by default, on only via override', () {
      // No override → off, even though DeepSeek's preset advertises support.
      const implicit = AiEngineConfig(apiKey: 'k');
      expect(implicit.reasoningEnabled, isFalse);
      const on = AiEngineConfig(
        apiKey: 'k',
        supportsReasoningOverride: true,
      );
      expect(on.reasoningEnabled, isTrue);
      const off = AiEngineConfig(
        apiKey: 'k',
        supportsReasoningOverride: false,
      );
      expect(off.reasoningEnabled, isFalse);
    });

    test('selectModel routes chat vs json', () {
      const c = AiEngineConfig(
        preset: kMimoPreset,
        apiKey: 'k',
        modelChat: 'mimo-v2.6',
        modelJson: 'mimo-v2.6-pro',
      );
      expect(c.selectModel('chat'), 'mimo-v2.6');
      expect(c.selectModel('json'), 'mimo-v2.6-pro');
      // 未知类型回落到会话模型（`config.py:select_model` 的 `self.model`）。
      expect(c.selectModel('other'), 'mimo-v2.6');
    });

    // 回归：`custom` 预设没有默认模型，JSON 模型留空时旧实现回落到
    // `preset.defaultModel` 的空串，请求带着 `model: ""` 上路，服务端只回
    // `invalid params, unknown model ''` —— 表现是「AI 对话能用，学习诊断 /
    // 定制复习 / 生成课程全挂」。
    test('a blank JSON model inherits the chat model', () {
      const c = AiEngineConfig(
        preset: kCustomPreset,
        apiKey: 'k',
        customBaseUrl: 'https://api.minimax.cn/v1',
        modelChat: 'MiniMax-M3.1-Flash',
        modelJson: '',
      );
      expect(c.selectModel('chat'), 'MiniMax-M3.1-Flash');
      expect(c.selectModel('json'), 'MiniMax-M3.1-Flash');
      expect(c.isComplete, isTrue);
    });

    test('an explicit JSON model still wins over the chat model', () {
      const c = AiEngineConfig(
        preset: kCustomPreset,
        apiKey: 'k',
        modelChat: 'cheap-chat',
        modelJson: 'strong-json',
      );
      expect(c.selectModel('chat'), 'cheap-chat');
      expect(c.selectModel('json'), 'strong-json');
    });

    test('whitespace-only models count as blank, not as a model id', () {
      const c = AiEngineConfig(
        preset: kCustomPreset,
        apiKey: 'k',
        customBaseUrl: 'https://api.minimax.cn/v1',
        modelChat: '  MiniMax-M3.1-Flash  ',
        modelJson: '   ',
      );
      expect(c.selectModel('chat'), 'MiniMax-M3.1-Flash');
      expect(c.selectModel('json'), 'MiniMax-M3.1-Flash');
    });

    test('a custom config with no model at all is incomplete', () {
      const c = AiEngineConfig(
        preset: kCustomPreset,
        apiKey: 'k',
        customBaseUrl: 'https://api.minimax.cn/v1',
      );
      expect(c.selectModel('json'), isEmpty);
      expect(c.isComplete, isFalse);
    });

    test('custom preset uses customBaseUrl', () {
      const c = AiEngineConfig(
        preset: kCustomPreset,
        apiKey: 'k',
        customBaseUrl: 'https://my-proxy.example.com/v1',
        modelChat: 'my-model',
      );
      expect(c.baseUrl, 'https://my-proxy.example.com/v1');
      expect(c.chatCompletionsUrl,
          'https://my-proxy.example.com/v1/chat/completions');
      expect(c.modelChat, 'my-model');
      expect(c.isComplete, isTrue);
    });

    test('copyWith preserves raw model fields so a preset switch resets them',
        () {
      const c = AiEngineConfig(
        preset: kMimoPreset,
        apiKey: 'k',
        modelChat: 'mimo-v2.6',
      );
      // Switch preset without specifying models: should fall back to the new
      // preset's default (deepseek-v4.1-flash), not freeze 'mimo-v2.6'.
      final switched = c.copyWith(preset: kDeepseekPreset);
      expect(switched.preset.id, AiProvider.deepseek);
      expect(switched.modelChat, 'deepseek-v4.1-flash');
    });
  });

  group('serialization', () {
    test('toJson/fromJson round-trips a complete named-preset config', () {
      const c = AiEngineConfig(
        preset: kMimoPreset,
        apiKey: 'sk-secret',
        modelChat: 'mimo-v2.6',
        modelJson: 'mimo-v2.6-pro',
        strictSchema: StrictSchemaMode.on,
        cacheEnabled: false,
        supportsReasoningOverride: true,
      );
      // includeApiKey: the legacy-inclusive form is only for reading back
      // pre-migration blobs (the key now lives in the secure store).
      final restored = AiEngineConfig.fromJson(c.toJson(includeApiKey: true));
      expect(restored.preset.id, AiProvider.mimo);
      expect(restored.apiKey, 'sk-secret');
      expect(restored.modelChat, 'mimo-v2.6');
      expect(restored.modelJson, 'mimo-v2.6-pro');
      expect(restored.strictSchema, StrictSchemaMode.on);
      expect(restored.cacheEnabled, isFalse);
      expect(restored.supportsReasoningOverride, isTrue);
      expect(restored.baseUrl, 'https://api.xiaomimimo.com/v1');
    });

    test('toJson stamps the current schema version', () {
      const c = AiEngineConfig(apiKey: 'k');
      expect(c.toJson()['schemaVersion'], AiEngineConfig.schemaVersion);
    });

    test('toJson/fromJson round-trips a custom preset with customBaseUrl', () {
      const c = AiEngineConfig(
        preset: kCustomPreset,
        apiKey: 'k',
        customBaseUrl: 'https://my-proxy.example.com/v1',
        modelChat: 'my-model',
      );
      final restored = AiEngineConfig.fromJson(c.toJson(includeApiKey: true));
      expect(restored.preset.id, AiProvider.custom);
      expect(restored.baseUrl, 'https://my-proxy.example.com/v1');
      expect(restored.modelChat, 'my-model');
      expect(restored.apiKey, 'k');
    });

    test('fromJson degrades gracefully on missing fields', () {
      final restored = AiEngineConfig.fromJson({'apiKey': 'only-key'});
      expect(restored.preset.id, AiProvider.deepseek);
      expect(restored.apiKey, 'only-key');
      expect(restored.modelChat, 'deepseek-v4.1-flash'); // preset default
      expect(restored.cacheEnabled, isTrue); // constructor default
      expect(restored.strictSchema, StrictSchemaMode.auto); // default
    });

    test('fromJson falls back to DeepSeek on an unknown preset id', () {
      final restored =
          AiEngineConfig.fromJson({'presetId': 'no-such-provider'});
      expect(restored.preset.id, AiProvider.deepseek);
    });
  });

  // 2026-10-20 服务商收敛：Kimi / Qwen 从产品移除，DeepSeek 与 MiMo 换模型 id。
  // 这组 case 守的是「老配置不许静默变成必失败的组合」——枚举兜底成 DeepSeek
  // 会拼出 deepseek 地址 + kimi 模型 id，用户只会看到连接失败。
  group('retired preset / model migration', () {
    test('a retired kimi config becomes custom with the old base URL', () {
      final restored = AiEngineConfig.fromJson({
        'presetId': 'kimi',
        'modelChat': 'kimi-k2.7-code',
        'modelJson': 'kimi-k3',
        'apiKey': 'sk-old',
      });
      expect(restored.preset.id, AiProvider.custom);
      expect(restored.baseUrl, 'https://api.moonshot.cn/v1');
      expect(restored.modelChat, 'kimi-k2.7-code');
      expect(restored.modelJson, 'kimi-k3');
      expect(restored.apiKey, 'sk-old');
      expect(restored.isComplete, isTrue);
    });

    test('a retired qwen config keeps its model, or gets the old default', () {
      final withModel = AiEngineConfig.fromJson({
        'presetId': 'qwen',
        'modelChat': 'qwen3.7-flash',
      });
      expect(withModel.preset.id, AiProvider.custom);
      expect(withModel.baseUrl,
          'https://dashscope.aliyuncs.com/compatible-mode/v1');
      expect(withModel.modelChat, 'qwen3.7-flash');

      // 老配置里 modelChat 可能是 null（从未手填），此时用原预设的默认模型，
      // 而不是让 custom 的空默认值把配置判成「未完成」。
      final withoutModel = AiEngineConfig.fromJson({'presetId': 'qwen'});
      expect(withoutModel.modelChat, 'qwen3.8-max');
      expect(withoutModel.modelJson, 'qwen3.8-max');
    });

    test('retired model ids are rewritten to current ones', () {
      final restored = AiEngineConfig.fromJson({
        'presetId': 'deepseek',
        'modelChat': 'deepseek-v4-flash',
        'modelJson': 'deepseek-v4-pro',
      });
      expect(restored.modelChat, 'deepseek-v4.1-flash');
      expect(restored.modelJson, 'deepseek-v4.1-pro');

      final mimo = AiEngineConfig.fromJson({
        'presetId': 'mimo',
        'modelChat': 'mimo-v2.5-pro',
        'modelJson': 'mimo-v2.5',
      });
      expect(mimo.modelChat, 'mimo-v2.6-pro');
      expect(mimo.modelJson, 'mimo-v2.6');
    });

    test('unknown custom model ids are left untouched', () {
      final restored = AiEngineConfig.fromJson({
        'presetId': 'custom',
        'customBaseUrl': 'https://proxy.example.com/v1',
        'modelChat': 'my-own-alias',
      });
      expect(restored.modelChat, 'my-own-alias');
    });

    // 旧设置页把空的 JSON 输入框原样存成 ''。迁移到 custom 之后它既不是 null
    // （拿不到 retired 的默认值）也不是有效 id，只能算「没填」。
    test('a blank stored model is unset, never an empty model id', () {
      final retiredKimi = AiEngineConfig.fromJson({
        'presetId': 'kimi',
        'modelChat': 'kimi-k3',
        'modelJson': '',
      });
      expect(retiredKimi.preset.id, AiProvider.custom);
      expect(retiredKimi.modelJson, 'kimi-k3');
      expect(retiredKimi.selectModel('json'), 'kimi-k3');

      final custom = AiEngineConfig.fromJson({
        'presetId': 'custom',
        'customBaseUrl': 'https://api.minimax.cn/v1',
        'modelChat': 'MiniMax-M3.1-Flash',
        'modelJson': '',
      });
      expect(custom.modelJson, isEmpty); // 界面仍显示「留空」
      expect(custom.selectModel('json'), 'MiniMax-M3.1-Flash');
    });
  });
}
