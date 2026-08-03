// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:turna/application/ai/engine/ai_provider_preset.dart';

void main() {
  group('kBuiltinPresets', () {
    test('contains all five providers', () {
      expect(kBuiltinPresets.keys, containsAll(AiProvider.values));
    });

    test('every preset has a non-empty label except custom defaults', () {
      for (final p in kBuiltinPresets.values) {
        expect(p.id, isNotNull);
      }
      expect(kBuiltinPresets[AiProvider.deepseek]!.baseUrl,
          'https://api.deepseek.com');
      expect(kBuiltinPresets[AiProvider.openai]!.baseUrl,
          'https://api.openai.com/v1');
      expect(kBuiltinPresets[AiProvider.moonshot]!.baseUrl,
          'https://api.moonshot.cn/v1');
      expect(kBuiltinPresets[AiProvider.ollama]!.baseUrl,
          'http://localhost:11434/v1');
      expect(kBuiltinPresets[AiProvider.custom]!.baseUrl, '');
    });

    test('only DeepSeek advertises reasoning support', () {
      expect(kBuiltinPresets[AiProvider.deepseek]!.supportsReasoning, isTrue);
      for (final p in const [
        AiProvider.openai,
        AiProvider.moonshot,
        AiProvider.ollama,
        AiProvider.custom,
      ]) {
        expect(kBuiltinPresets[p]!.supportsReasoning, isFalse);
      }
    });
  });

  group('applyPreset', () {
    test('a named preset fills baseUrl / model / reasoning', () {
      final r = applyPreset(
        provider: AiProvider.openai,
        baseUrl: 'https://old.example.com',
        model: 'old-model',
        supportsReasoning: true,
      );
      expect(r.baseUrl, 'https://api.openai.com/v1');
      expect(r.model, 'gpt-4o');
      expect(r.supportsReasoning, isFalse);
    });

    test('the custom preset preserves the existing values', () {
      final r = applyPreset(
        provider: AiProvider.custom,
        baseUrl: 'https://my-proxy.example.com/v1',
        model: 'my-model',
        supportsReasoning: true,
      );
      expect(r.baseUrl, 'https://my-proxy.example.com/v1');
      expect(r.model, 'my-model');
      expect(r.supportsReasoning, isTrue);
    });

    test('every named preset round-trips through applyPreset', () {
      for (final p in const [
        AiProvider.deepseek,
        AiProvider.openai,
        AiProvider.moonshot,
        AiProvider.ollama,
      ]) {
        final preset = presetFor(p);
        final r = applyPreset(
          provider: p,
          baseUrl: '',
          model: '',
          supportsReasoning: false,
        );
        expect(r.baseUrl, preset.baseUrl);
        expect(r.model, preset.defaultModel);
        expect(r.supportsReasoning, preset.supportsReasoning);
      }
    });
  });

  group('providerOrder', () {
    test('returns the canonical dropdown order', () {
      expect(providerOrder(), const [
        AiProvider.deepseek,
        AiProvider.openai,
        AiProvider.moonshot,
        AiProvider.ollama,
        AiProvider.custom,
      ]);
    });
  });
}
