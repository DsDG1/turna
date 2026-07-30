// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:varnamala/application/ai/engine/ai_engine_config.dart';
import 'package:varnamala/application/ai/engine/ai_provider_preset.dart';

void main() {
  group('AiEngineConfig defaults', () {
    test('defaults to the DeepSeek preset with an empty key', () {
      const c = AiEngineConfig(apiKey: '');
      expect(c.preset.id, AiProvider.deepseek);
      expect(c.baseUrl, 'https://api.deepseek.com');
      expect(c.modelChat, 'deepseek-v4-pro');
      expect(c.modelJson, 'deepseek-v4-pro');
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
      // preset's default (deepseek-v4-pro), not freeze 'gpt-4o-mini'.
      final switched = c.copyWith(preset: kDeepseekPreset);
      expect(switched.preset.id, AiProvider.deepseek);
      expect(switched.modelChat, 'deepseek-v4-pro');
    });
  });
}
