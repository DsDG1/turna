// Dart imports:
import 'dart:convert';

/// Genre tag → lesson template metadata. Mirrors
/// `tool/gui/src/backend/ai_genre.py:GENRE_TEMPLATES`.
class GenreMeta {
  const GenreMeta({
    required this.tag,
    required this.template,
    required this.label,
    required this.primaryKey,
    required this.description,
    required this.suggestedTypes,
  });

  final String tag;
  final String template;
  final String label;
  final String primaryKey;
  final String description;
  final List<String> suggestedTypes;
}

const Map<String, GenreMeta> genreTemplates = {
  '[intro]': GenreMeta(
    tag: '[intro]',
    template: 'intro',
    label: '认识新词',
    primaryKey: 'subLessons',
    description: '通过展示新词、翻译句子和填空引导学生认识生词。',
    suggestedTypes: ['showWord', 'translateSentence', 'fillBlank'],
  ),
  '[practice]': GenreMeta(
    tag: '[practice]',
    template: 'practice',
    label: '巩固练习',
    primaryKey: 'subLessons',
    description: '通过多轮互动练习巩固词汇和句型。',
    suggestedTypes: [
      'multipleChoice',
      'translateSentence',
      'fillBlank',
      'reorderSentence',
    ],
  ),
  '[review]': GenreMeta(
    tag: '[review]',
    template: 'review',
    label: '复习',
    primaryKey: 'subLessons',
    description: '复习已学内容，可混合使用 subLessons 和 stages。',
    suggestedTypes: ['multipleChoice', 'fillBlank', 'translateSentence'],
  ),
  '[listening]': GenreMeta(
    tag: '[listening]',
    template: 'listening',
    label: '听力训练',
    primaryKey: 'listeningPhases',
    description: '通过听力阶段训练学生的听力理解。',
    suggestedTypes: ['listenAndPick', 'typeTheWord', 'listenOnly'],
  ),
  '[reading]': GenreMeta(
    tag: '[reading]',
    template: 'reading',
    label: '阅读理解',
    primaryKey: 'readingPassage',
    description: '提供阅读材料并配合阅读理解题目。',
    suggestedTypes: ['readingMcq', 'readingTrueFalse', 'readingShortAnswer'],
  ),
  '[mastery]': GenreMeta(
    tag: '[mastery]',
    template: 'mastery',
    label: '综合测验',
    primaryKey: 'stages',
    description: '单元末综合测验，覆盖多种题型。',
    suggestedTypes: [
      'multipleChoice',
      'translateSentence',
      'fillBlank',
      'multiSelect',
    ],
  ),
  '[mixed]': GenreMeta(
    tag: '[mixed]',
    template: 'mixed',
    label: '混合',
    primaryKey: '',
    description: '在一个 section 中混合使用多种模板，适合综合课程。',
    suggestedTypes: [],
  ),
};

const Map<String, String> templateLabels = {
  'intro': '认识新词',
  'practice': '巩固练习',
  'review': '复习',
  'listening': '听力训练',
  'reading': '阅读理解',
  'mastery': '综合测验',
  'mixed': '混合',
};

final RegExp _tagRe = RegExp(r'\[([a-zA-Z]+)\]');

/// Map a genre tag (with or without brackets) to a template name.
String genreToTemplate(String genre) {
  var key = genre.toLowerCase().trim();
  if (!key.startsWith('[')) key = '[$key]';
  final meta = genreTemplates[key];
  return meta?.template ?? 'mixed';
}

/// Return the human-readable label for a template.
String templateLabel(String template) => templateLabels[template] ?? template;

/// Return the first recognized genre tag from [text], or null.
String? parseGenreTag(String? text) {
  if (text == null || text.isEmpty) return null;
  for (final match in _tagRe.allMatches(text)) {
    final tag = '[${match.group(1)!.toLowerCase()}]';
    if (genreTemplates.containsKey(tag)) return tag;
  }
  return null;
}

/// Return all recognized genre tags found in [text], in order.
List<String> genreTagsInText(String? text) {
  final found = <String>[];
  if (text == null || text.isEmpty) return found;
  for (final match in _tagRe.allMatches(text)) {
    final tag = '[${match.group(1)!.toLowerCase()}]';
    if (genreTemplates.containsKey(tag) && !found.contains(tag)) {
      found.add(tag);
    }
  }
  return found;
}

/// All recognized genre tags including brackets.
List<String> allGenreTags() => genreTemplates.keys.toList();

/// Prompt block explaining available genre tags to the model.
String genrePromptBlock() {
  final lines = <String>['可用 genre 标签（用户可在主题或额外指令中插入这些标签来指定模板）：'];
  for (final entry in genreTemplates.entries) {
    final meta = entry.value;
    lines.add(
      '${entry.key} → ${meta.label}（template=${meta.template}，'
      '主键=${meta.primaryKey.isEmpty ? "混合" : meta.primaryKey}）：${meta.description}',
    );
  }
  lines.add(
    '规则：如果用户在主题或额外指令中插入了 genre 标签，'
    '请按标签为对应单元或课时生成相应模板结构；未标注的部分回退到默认模板。',
  );
  return lines.join('\n');
}

/// Detect first genre tag in spec topic or extra instructions.
String? detectGenreFromSpec({
  required String topic,
  required String extraInstructions,
}) {
  final combined = '$topic $extraInstructions';
  final tags = genreTagsInText(combined);
  return tags.isNotEmpty ? tags.first : null;
}

/// Encode a list of strings as a JSON array string (for DB tags column).
String encodeTags(List<dynamic> tags) => jsonEncode(tags);