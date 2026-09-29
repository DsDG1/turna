import 'package:turna/domain/course/section.dart';

/// CEFR tag to persist when the section file itself has no level.
///
/// Index shells carry A1/A2 for the builtin courses. An explicit body level,
/// including a non-empty author value, wins. An empty body falls back to the
/// index shell so a reseed stores the tag.
String sectionLevelForSeed({String? bodyLevel, Object? indexLevel}) {
  final body = (bodyLevel ?? '').trim();
  if (body.isNotEmpty) return body;
  return '${indexLevel ?? ''}'.trim();
}

/// Non-empty `sections[].level` values from an `index.json` object, by id.
Map<String, String> sectionLevelsFromIndex(Map<String, dynamic> index) {
  final levels = <String, String>{};
  final sections = index['sections'];
  if (sections is! List) return levels;
  for (final entry in sections) {
    if (entry is! Map) continue;
    final id = '${entry['id'] ?? ''}'.trim();
    final level = '${entry['level'] ?? ''}'.trim();
    if (id.isEmpty || level.isEmpty) continue;
    levels[id] = level;
  }
  return levels;
}

/// Use [levels] when [section] has no stored level.
///
/// A non-empty stored level, including the Anki marker, is left as written.
Section overlaySectionLevel(Section section, Map<String, String> levels) {
  final current = section.level?.trim() ?? '';
  if (current.isNotEmpty) return section;
  final level = levels[section.id];
  if (level == null || level.isEmpty) return section;
  return section.copyWith(level: level);
}
