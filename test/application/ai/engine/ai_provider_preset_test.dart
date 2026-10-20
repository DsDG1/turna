// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:turna/application/ai/engine/ai_provider_preset.dart';

void main() {
  group('kBuiltinPresets', () {
    test('contains every provider', () {
      expect(kBuiltinPresets.keys, containsAll(AiProvider.values));
    });

    test('every preset has a non-empty label except custom defaults', () {
      for (final p in kBuiltinPresets.values) {
        expect(p.id, isNotNull);
      }
      expect(kBuiltinPresets[AiProvider.deepseek]!.baseUrl,
          'https://api.deepseek.com');
      expect(kBuiltinPresets[AiProvider.mimo]!.baseUrl,
          'https://api.xiaomimimo.com/v1');
      expect(kBuiltinPresets[AiProvider.custom]!.baseUrl, '');
    });

    test('DeepSeek ships 4.1 models and defaults to Flash', () {
      expect(kDeepseekPreset.defaultModel, 'deepseek-v4.1-flash');
      expect(kDeepseekPreset.supportedModels,
          containsAll(<String>['deepseek-v4.1-flash', 'deepseek-v4.1-pro']));
    });

    test('MiMo ships 2.6 models and defaults to Pro', () {
      expect(kMimoPreset.defaultModel, 'mimo-v2.6-pro');
      expect(kMimoPreset.supportedModels,
          containsAll(<String>['mimo-v2.6-pro', 'mimo-v2.6']));
    });

    test('no retired model ids remain in any preset quick-pick', () {
      for (final p in kBuiltinPresets.values) {
        for (final m in p.supportedModels) {
          expect(kRetiredModelAliases.containsKey(m), isFalse,
              reason: '${p.label} still offers retired model $m');
        }
      }
    });

    test('all named presets except custom advertise reasoning support', () {
      for (final p in const [
        AiProvider.deepseek,
        AiProvider.mimo,
      ]) {
        expect(kBuiltinPresets[p]!.supportsReasoning, isTrue);
      }
      expect(kBuiltinPresets[AiProvider.custom]!.supportsReasoning, isFalse);
    });

    test('retired providers are not part of the enum any more', () {
      // 它们只作为 `presetId` 字符串存在于历史配置里，迁移表负责翻译。
      final names = AiProvider.values.map((p) => p.name).toList();
      expect(names, isNot(contains('kimi')));
      expect(names, isNot(contains('qwen')));
      expect(kRetiredPresets.keys, containsAll(<String>['kimi', 'qwen']));
    });
  });

  group('applyPreset', () {
    test('a named preset fills baseUrl / model / reasoning', () {
      final r = applyPreset(
        provider: AiProvider.mimo,
        baseUrl: 'https://old.example.com',
        model: 'old-model',
        supportsReasoning: false,
      );
      expect(r.baseUrl, 'https://api.xiaomimimo.com/v1');
      expect(r.model, 'mimo-v2.6-pro');
      expect(r.supportsReasoning, isTrue);
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
        AiProvider.mimo,
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
        AiProvider.mimo,
        AiProvider.custom,
      ]);
    });
  });
}
