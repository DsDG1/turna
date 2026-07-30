/// Textbook-type presets for the textbook-import extraction pipeline.
///
/// Mirrors `tool/gui/src/backend/textbook_presets.py`. Distinct from AI
/// *provider* presets (DeepSeek/OpenAI): a [TextbookPreset] models the
/// *content type* of the source material.
class TextbookPreset {
  const TextbookPreset({
    required this.name,
    required this.label,
    required this.description,
    this.temperature = 0.3,
    this.strategy = 'standard',
    this.maxTokens,
    this.maxChapterChars = 8000,
    this.windowChars = 8000,
    this.overlapChars = 500,
    this.lessonTemplate = 'intro',
  });

  final String name;
  final String label;
  final String description;

  /// LLM sampling temperature for extraction.
  final double temperature;

  /// `standard` (words + expressions + grammar) or `vocab_only`.
  final String strategy;

  final int? maxTokens;
  final int maxChapterChars;
  final int windowChars;
  final int overlapChars;
  final String lessonTemplate;

  bool get isVocabOnly => strategy == 'vocab_only';
}

/// Built-in presets keyed by machine name (aligned with GUI).
const Map<String, TextbookPreset> builtinTextbookPresets = {
  'general': TextbookPreset(
    name: 'general',
    label: '通用教材',
    description: '词汇 + 表达 + 语法，均衡抽取。适合大多数课本。',
    temperature: 0.3,
    strategy: 'standard',
    maxChapterChars: 8000,
    lessonTemplate: 'intro',
  ),
  'grammar': TextbookPreset(
    name: 'grammar',
    label: '语法书',
    description: '低温抽取，侧重语法点与例句，规则更确定。',
    temperature: 0.15,
    strategy: 'standard',
    maxTokens: 4096,
    maxChapterChars: 8000,
    lessonTemplate: 'intro',
  ),
  'dialogue': TextbookPreset(
    name: 'dialogue',
    label: '对话书',
    description: '略高温抽取，侧重日常表达与口语词汇。',
    temperature: 0.5,
    strategy: 'standard',
    maxChapterChars: 8000,
    lessonTemplate: 'intro',
  ),
  'reading': TextbookPreset(
    name: 'reading',
    label: '阅读材料',
    description: '仅抽词汇，忽略隐式语法；适合长篇阅读导入。',
    temperature: 0.3,
    strategy: 'vocab_only',
    maxChapterChars: 10000,
    windowChars: 10000,
    lessonTemplate: 'intro',
  ),
};

/// Stable display order of preset machine names.
const List<String> textbookPresetNames = [
  'general',
  'grammar',
  'dialogue',
  'reading',
];

/// Return the preset for [name], falling back to `general`.
TextbookPreset presetFor(String name) =>
    builtinTextbookPresets[name] ?? builtinTextbookPresets['general']!;
