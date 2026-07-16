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
    label: 'New Words',
    primaryKey: 'subLessons',
    description:
        'Introduce new words via word display, translation, and fill-in-the-blank.',
    suggestedTypes: ['showWord', 'translateSentence', 'fillBlank'],
  ),
  '[practice]': GenreMeta(
    tag: '[practice]',
    template: 'practice',
    label: 'Practice',
    primaryKey: 'subLessons',
    description:
        'Reinforce vocabulary and sentence patterns through multiple interactions.',
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
    label: 'Review',
    primaryKey: 'subLessons',
    description: 'Review learned content; may mix subLessons and stages.',
    suggestedTypes: ['multipleChoice', 'fillBlank', 'translateSentence'],
  ),
  '[listening]': GenreMeta(
    tag: '[listening]',
    template: 'listening',
    label: 'Listening',
    primaryKey: 'listeningPhases',
    description: 'Train listening comprehension through listening phases.',
    suggestedTypes: ['listenAndPick', 'typeTheWord', 'listenOnly'],
  ),
  '[reading]': GenreMeta(
    tag: '[reading]',
    template: 'reading',
    label: 'Reading',
    primaryKey: 'readingPassage',
    description: 'Provide a reading passage with comprehension questions.',
    suggestedTypes: ['readingMcq', 'readingTrueFalse', 'readingShortAnswer'],
  ),
  '[mastery]': GenreMeta(
    tag: '[mastery]',
    template: 'mastery',
    label: 'Quiz',
    primaryKey: 'stages',
    description: 'End-of-unit quiz covering multiple question types.',
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
    label: 'Mixed',
    primaryKey: '',
    description:
        'Combine multiple templates in one section for comprehensive courses.',
    suggestedTypes: [],
  ),
};

const Map<String, String> templateLabels = {
  'intro': 'New Words',
  'practice': 'Practice',
  'review': 'Review',
  'listening': 'Listening',
  'reading': 'Reading',
  'mastery': 'Quiz',
  'mixed': 'Mixed',
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
  final lines = <String>[
    'Available genre tags (the user may insert these in the topic or extra '
        'instructions to specify a template):',
  ];
  for (final entry in genreTemplates.entries) {
    final meta = entry.value;
    lines.add(
      '${entry.key} → ${meta.label} (template=${meta.template}, '
      'primaryKey=${meta.primaryKey.isEmpty ? "mixed" : meta.primaryKey}): '
      '${meta.description}',
    );
  }
  lines.add(
    'Rule: if the user inserts a genre tag in the topic or extra '
        'instructions, generate the corresponding template structure for the '
        'matching unit or lesson; untagged parts fall back to the default '
        'template.',
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