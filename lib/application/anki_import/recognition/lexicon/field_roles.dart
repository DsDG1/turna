import '../config.dart';

/// Bump when the lexicon data below changes.
const int lexiconVersion = 1;

/// Field roles across recognition, persisted mappings, and projection.
///
/// `prompt`/`response` replace the old `targetText`/`nativeText` naming
/// (which embedded language-learning assumptions); direction remains a
/// mapping option, not a role. `unitLabel`/`lessonLabel` survive because
/// the projector consumes them for tree placement.
enum FieldRole {
  prompt,
  response,
  options,
  audio,
  image,
  pronunciation,
  example,
  hint,
  extra,
  unitLabel,
  lessonLabel,
  ignored,
}

/// Legacy persisted names → current roles. Old `mapping_json` rows parse
/// through this map so user-confirmed mappings keep working untouched.
const Map<String, FieldRole> _legacyRoleNames = {
  'targetText': FieldRole.prompt,
  'nativeText': FieldRole.response,
  'optionPool': FieldRole.options,
  'exampleTarget': FieldRole.example,
  'exampleNative': FieldRole.example,
};

FieldRole fieldRoleFromName(String name) {
  if (_legacyRoleNames.containsKey(name)) return _legacyRoleNames[name]!;
  return FieldRole.values.firstWhere(
    (role) => role.name == name,
    orElse: () => FieldRole.ignored,
  );
}

/// Tie-break priority when a field name hits several roles with equal
/// weight. Earlier = stronger claim.
const List<FieldRole> _rolePriority = [
  FieldRole.prompt,
  FieldRole.response,
  FieldRole.audio,
  FieldRole.image,
  FieldRole.pronunciation,
  FieldRole.options,
  FieldRole.example,
  FieldRole.unitLabel,
  FieldRole.lessonLabel,
  FieldRole.hint,
  FieldRole.extra,
];

int fieldRolePriority(FieldRole role) {
  final index = _rolePriority.indexOf(role);
  return index < 0 ? _rolePriority.length : index;
}

/// Structural synonyms only (doc 37 iron law): never a topic word, never a
/// subject name. Exact hits score [lexiconExactWeight]; substring hits on
/// the contains-lists score [lexiconContainsWeight].
///
/// Direction-ambiguous tokens like `word`/`单词`/`term` deliberately stay
/// OUT of the exact lists: in a listening deck the Word field is the back,
/// and structure (template faces) + position resolve them more honestly
/// than a lexicon that guesses a direction.
const Map<FieldRole, List<String>> _exactTerms = {
  FieldRole.prompt: [
    'front', 'question', 'q', 'expression', 'prompt', 'stem',
    '正面', '题目', '题干', '题面', '问题', '句',
  ],
  FieldRole.response: [
    'back', 'answer', 'meaning', 'translation', 'gloss', 'definition',
    '背面', '反面', '答案', '释义', '翻译', '后面', '解词',
  ],
  FieldRole.options: ['options', 'option', 'choice', 'choices', '选项', '备选'],
  FieldRole.audio: ['audio', 'sound', '音频', '声音', '发音'],
  FieldRole.image: [
    'image', 'picture', 'img', 'photo', 'mask', 'occlusion',
    '图片', '插图', '相片', '遮图', '遮挡',
  ],
  FieldRole.pronunciation: [
    'pronunciation', 'ipa', 'phonetic', 'pinyin', 'reading',
    '音标', '拼音', '注音', '读音',
  ],
  FieldRole.example: ['example', 'sentence', 'context', '例句', '语境'],
  FieldRole.hint: ['hint', '提示', '线索'],
  FieldRole.extra: ['extra', 'note', '补充', '备注'],
  FieldRole.unitLabel: ['unit', 'chapter', '单元', '章'],
  FieldRole.lessonLabel: ['lesson', 'topic', '课', '节'],
};

const Map<FieldRole, List<String>> _containsTerms = {
  FieldRole.prompt: ['front', 'question', 'prompt', 'stem', '正面', '题干'],
  FieldRole.response: [
    'back', 'answer', 'meaning', 'translation', 'gloss',
    '背面', '反面', '释义', '翻译', '答案',
  ],
  FieldRole.options: ['option', 'choice', '选项', '备选'],
  FieldRole.audio: ['audio', 'sound', '音频', '发音', '声音'],
  FieldRole.image: [
    'image', 'picture', 'photo', 'occlusion', '遮图', '图片', '插图',
  ],
  FieldRole.pronunciation: ['pronun', 'ipa', 'phonetic', '音标', '拼音', '读音'],
  FieldRole.example: ['example', '例句'],
  FieldRole.hint: ['hint', '提示'],
  FieldRole.extra: ['extra', '补充'],
  FieldRole.unitLabel: ['unit', 'chapter', '单元'],
  FieldRole.lessonLabel: ['lesson', 'topic', '课时'],
};

/// Normalize a field name for lexicon matching: lowercase and drop the
/// `_`/`-`/space separators composite names are built from.
String normalizeFieldName(String name) {
  return name.toLowerCase().replaceAll(RegExp(r'[_\-\s]+'), '').trim();
}

/// Exact lexicon lookup on the normalized name.
FieldRole? exactRoleFor(String fieldName) {
  final normalized = normalizeFieldName(fieldName);
  if (normalized.isEmpty) return null;
  for (final entry in _exactTerms.entries) {
    if (entry.value.contains(normalized)) return entry.key;
  }
  return null;
}

/// All roles whose contains-list hits the normalized name, ordered by role
/// priority (caller applies the fixed contains weight).
List<FieldRole> containsRolesFor(String fieldName) {
  final normalized = normalizeFieldName(fieldName);
  if (normalized.isEmpty) return const <FieldRole>[];
  final hits = <FieldRole>[];
  for (final entry in _containsTerms.entries) {
    for (final term in entry.value) {
      if (normalized.contains(term)) {
        hits.add(entry.key);
        break;
      }
    }
  }
  hits.sort((a, b) => fieldRolePriority(a).compareTo(fieldRolePriority(b)));
  return hits;
}
