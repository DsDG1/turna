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
      expect(c.modelChat, 'deepseek-v4-flash');
      expect(c.modelJson, 'deepseek-v4-flash');
      expect(c.apiKey, '');
      expect(c.isComplete, isFalse); // empty key
    });

    test('selectModel routes chat vs json', () {
      const c = AiEngineConfig(
        preset: kOpenaiPreset,
        apiKey: 'k',
        modelChat: 'gpt-4o-mini',
        modelJson: 'gpt-4o',
      );
      expect(c.selectModel('chat'), 'gpt-4o-mini');
      expect(c.selectModel('json'), 'gpt-4o');
      expect(c.selectModel('other'), 'gpt-4o'); // falls back to preset default
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
        preset: kOpenaiPreset,
        apiKey: 'k',
        modelChat: 'gpt-4o-mini',
      );
      // Switch preset without specifying models: should fall back to the new
      // preset's default (deepseek-v4-flash), not freeze 'gpt-4o-mini'.
      final switched = c.copyWith(preset: kDeepseekPreset);
      expect(switched.preset.id, AiProvider.deepseek);
      expect(switched.modelChat, 'deepseek-v4-flash');
    });
  });

  group('serialization', () {
    test('toJson/fromJson round-trips a complete named-preset config', () {
      const c = AiEngineConfig(
        preset: kOpenaiPreset,
        apiKey: 'sk-secret',
        modelChat: 'gpt-4o-mini',
        modelJson: 'gpt-4o',
        strictSchema: StrictSchemaMode.on,
        cacheEnabled: false,
        supportsReasoningOverride: true,
      );
      // includeApiKey: the legacy-inclusive form is only for reading back
      // pre-migration blobs (the key now lives in the secure store).
      final restored =
          AiEngineConfig.fromJson(c.toJson(includeApiKey: true));
      expect(restored.preset.id, AiProvider.openai);
      expect(restored.apiKey, 'sk-secret');
      expect(restored.modelChat, 'gpt-4o-mini');
      expect(restored.modelJson, 'gpt-4o');
      expect(restored.strictSchema, StrictSchemaMode.on);
      expect(restored.cacheEnabled, isFalse);
      expect(restored.supportsReasoningOverride, isTrue);
      expect(restored.baseUrl, 'https://api.openai.com/v1');
    });

    test('toJson/fromJson round-trips a custom preset with customBaseUrl', () {
      const c = AiEngineConfig(
        preset: kCustomPreset,
        apiKey: 'k',
        customBaseUrl: 'https://my-proxy.example.com/v1',
        modelChat: 'my-model',
      );
      final restored =
          AiEngineConfig.fromJson(c.toJson(includeApiKey: true));
      expect(restored.preset.id, AiProvider.custom);
      expect(restored.baseUrl, 'https://my-proxy.example.com/v1');
      expect(restored.modelChat, 'my-model');
      expect(restored.apiKey, 'k');
    });

    test('fromJson degrades gracefully on missing fields', () {
      final restored = AiEngineConfig.fromJson({'apiKey': 'only-key'});
      expect(restored.preset.id, AiProvider.deepseek);
      expect(restored.apiKey, 'only-key');
      expect(restored.modelChat, 'deepseek-v4-flash'); // preset default
      expect(restored.cacheEnabled, isTrue); // constructor default
      expect(restored.strictSchema, StrictSchemaMode.auto); // default
    });

    test('fromJson falls back to DeepSeek on an unknown preset id', () {
      final restored =
          AiEngineConfig.fromJson({'presetId': 'no-such-provider'});
      expect(restored.preset.id, AiProvider.deepseek);
    });
  });
}
