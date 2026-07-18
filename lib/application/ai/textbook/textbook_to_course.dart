// Project imports:
import 'package:varnamala/application/ai/textbook/knowledge_schema.dart';

/// Builds a Varnamala section dict from extracted textbook knowledge.
/// Mirrors `tool/gui/src/backend/textbook_to_course.py`.
class TextbookToCourse {
  const TextbookToCourse();

  /// Builds one section per chapter. Each section contains a single unit with
  /// a single intro lesson that teaches the extracted words/expressions.
  List<Map<String, dynamic>> buildSections(
    List<ChapterResult> results, {
    required String language,
    required String sourceLanguage,
    required String level,
  }) {
    final sections = <Map<String, dynamic>>[];
    for (var i = 0; i < results.length; i++) {
      final result = results[i];
      if (!result.keep || result.knowledge == null || result.knowledge!.isEmpty) {
        continue;
      }
      sections.add(
        _buildSection(
          result: result,
          index: i,
          language: language,
          sourceLanguage: sourceLanguage,
          level: level,
        ),
      );
    }
    return sections;
  }

  Map<String, dynamic> _buildSection({
    required ChapterResult result,
    required int index,
    required String language,
    required String sourceLanguage,
    required String level,
  }) {
    final chapter = result.chapter;
    final k = result.knowledge!;
    final sectionId = 'tb-${chapter.slug}';
    final unitId = '$sectionId-u1';
    final lessonId = '$unitId-l1';

    final items = <Map<String, dynamic>>[
      for (final w in k.words)
        {
          'runtimeType': 'showWord',
          'id': '$lessonId-sw-${w['id']}',
          'wordId': w['id'],
          'context': null,
        },
      for (final e in k.expressions)
        {
          'runtimeType': 'translateSentence',
          'id': '$lessonId-tr-${e['id']}',
          'source': e['translation'],
          'expected': e['term'],
          'hints': [],
        },
      if (k.words.isNotEmpty)
        {
          'runtimeType': 'multipleChoice',
          'id': '$lessonId-mc-1',
          'prompt': 'Choose the correct $language word:',
          'options': [
            for (final w in k.words.take(4)) w['term'],
          ],
          'correctIndex': 0,
        },
    ];

    return {
      'id': sectionId,
      'name': chapter.title,
      'description': 'Imported from textbook: ${chapter.title}',
      'level': level,
      'prerequisiteSectionIds': [],
      'words': k.words,
      'expressions': k.expressions,
      'grammarPoints': k.grammarPoints,
      'units': [
        {
          'id': unitId,
          'name': chapter.title,
          'description': '',
          'prerequisiteUnitIds': [],
          'lessons': [
            {
              'id': lessonId,
              'name': chapter.title,
              'description': '',
              'type': 'normal',
              'template': 'intro',
              'prerequisiteLessonIds': [],
              'content': {
                'subLessons': [
                  {
                    'id': '$lessonId-sl1',
                    'name': 'New knowledge',
                    'stages': [
                      {
                        'id': '$lessonId-sl1-st1',
                        'name': 'Learn',
                        'items': items,
                      }
                    ],
                  }
                ],
              },
            }
          ],
        }
      ],
    };
  }
}
