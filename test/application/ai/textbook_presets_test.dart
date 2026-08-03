import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/ai/textbook/textbook_presets.dart';

void main() {
  test('builtin presets match GUI names and fields', () {
    expect(textbookPresetNames, ['general', 'grammar', 'dialogue', 'reading']);
    for (final name in textbookPresetNames) {
      final p = presetFor(name);
      expect(p.name, name);
      expect(p.label, isNotEmpty);
      expect(p.description, isNotEmpty);
      expect(p.temperature, greaterThan(0));
      expect(p.maxChapterChars, greaterThan(0));
    }
  });

  test('presetFor falls back to general', () {
    expect(presetFor('unknown').name, 'general');
  });

  test('reading preset is vocab_only', () {
    expect(presetFor('reading').isVocabOnly, isTrue);
    expect(presetFor('general').isVocabOnly, isFalse);
  });

  test('grammar preset is cooler temperature', () {
    expect(presetFor('grammar').temperature,
        lessThan(presetFor('dialogue').temperature));
  });
}
