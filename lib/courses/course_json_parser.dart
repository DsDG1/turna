import 'dart:convert';

import 'package:turna/domain/course/expression.dart';
import 'package:turna/domain/course/grammar_point.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/domain/course/word_entry.dart';

/// Parses a section for database seeding and downloaded-content validation.
Section parseSection(String raw) => Section.fromJson(
    _normalizeSection(jsonDecode(raw) as Map<String, dynamic>));

// Supports the flat-lesson authoring shape by turning content.questions into
// one default stage. All downstream readers see the same normalized model.
Map<String, dynamic> _normalizeSection(Map<String, dynamic> section) {
  final units = section['units'] as List<dynamic>?;
  if (units == null) return section;
  section['units'] = [
    for (final u in units) _normalizeUnit(u as Map<String, dynamic>),
  ];
  return section;
}

Map<String, dynamic> _normalizeUnit(Map<String, dynamic> unit) {
  final lessons = unit['lessons'] as List<dynamic>?;
  if (lessons == null) return unit;
  unit['lessons'] = [
    for (final l in lessons) _normalizeLesson(l as Map<String, dynamic>),
  ];
  return unit;
}

Map<String, dynamic> _normalizeLesson(Map<String, dynamic> lesson) {
  final content = lesson['content'] as Map<String, dynamic>?;
  if (content == null) return lesson;
  final hasStages = content.containsKey('stages');
  final hasQuestions = content.containsKey('questions');
  if (!hasQuestions) return lesson;
  if (hasStages) {
    throw FormatException(
      'Lesson ${lesson['id']} declares both "stages" and "questions" in its '
      'content; use exactly one.',
    );
  }
  // Flat shape: wrap the questions in one default stage. The lesson's own
  // name becomes the stage name; the synthetic stage id is stable.
  final questions = content['questions'] as List<dynamic>;
  final lessonName = (lesson['name'] as String?) ?? 'Practice';
  content['stages'] = [
    {
      'id': 'stage-default',
      'name': lessonName,
      'items': questions,
    },
  ];
  content.remove('questions');
  return lesson;
}

/// Parses vocabulary from course JSON.
List<WordEntry> parseVocabulary(String raw) => _parseVocabulary(raw);

List<WordEntry> _parseVocabulary(String raw) {
  final json = jsonDecode(raw) as Map<String, dynamic>;
  final words = json['words'] as List<dynamic>;
  return words
      .map((e) => WordEntry.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);
}

/// Parses grammar points from course JSON.
List<GrammarPoint> parseGrammarPoints(String raw) {
  final json = jsonDecode(raw) as Map<String, dynamic>;
  final points = json['grammarPoints'] as List<dynamic>;
  return points
      .map((e) => GrammarPoint.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);
}

/// Parses expressions from course JSON.
List<Expression> parseExpressions(String raw) {
  final json = jsonDecode(raw) as Map<String, dynamic>;
  final expressions = (json['expressions'] as List<dynamic>?) ?? [];
  return expressions
      .map((e) => Expression.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);
}
