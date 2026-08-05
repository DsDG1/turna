// Structural gates for the non–AI-pipeline Turkish content enrichment.
// Asserts the shipped assets/courses/turkish tree: no placeholders, multi-
// lesson units, listening + reading per section, and material pool growth.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/section.dart';

List<Section> _loadAllSections() {
  final dir = Directory('assets/courses/turkish/sections');
  final files = dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.endsWith('.json'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  return files
      .map((f) => parseSection(f.readAsStringSync()))
      .toList(growable: false);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Section> sections;
  late Map<String, dynamic> index;
  late List<dynamic> words;
  late List<dynamic> expressions;
  late List<dynamic> grammarPoints;

  setUpAll(() {
    sections = _loadAllSections();
    index = jsonDecode(
        File('assets/courses/turkish/index.json').readAsStringSync())
        as Map<String, dynamic>;
    words = (jsonDecode(
            File('assets/courses/turkish/vocab.json').readAsStringSync())
        as Map<String, dynamic>)['words'] as List<dynamic>;
    expressions = (jsonDecode(File('assets/courses/turkish/expressions.json')
            .readAsStringSync()) as Map<String, dynamic>)['expressions']
        as List<dynamic>;
    grammarPoints = (jsonDecode(
            File('assets/courses/turkish/grammar_points.json')
                .readAsStringSync()) as Map<String, dynamic>)['grammarPoints']
        as List<dynamic>;
  });

  test('index keeps 8 sections A1→B2 with prerequisite chain', () {
    final shells = index['sections'] as List<dynamic>;
    expect(shells, hasLength(8));
    final levels = shells.map((s) => (s as Map)['level']).toList();
    expect(levels, ['A1', 'A1', 'A1', 'A2', 'B1', 'B1', 'B2', 'B2']);
    for (var i = 0; i < shells.length; i++) {
      final prereq =
          List<String>.from((shells[i] as Map)['prerequisiteSectionIds'] as List);
      if (i == 0) {
        expect(prereq, isEmpty);
      } else {
        expect(prereq, ['section$i']);
      }
    }
  });

  test('no placeholder lesson stubs remain', () {
    for (final s in sections) {
      for (final u in s.units) {
        for (final l in u.lessons) {
          expect(
            l.description.toLowerCase().contains('placeholder'),
            isFalse,
            reason: 'placeholder description on ${l.id}',
          );
        }
      }
    }
  });

  test('each section has multiple real lessons including listening and reading',
      () {
    expect(sections, hasLength(8));
    for (final s in sections) {
      final lessons = s.units.expand((u) => u.lessons).toList();
      expect(lessons.length, greaterThanOrEqualTo(4),
          reason: '${s.id} should not be a single legacy MCQ stand-in');
      final templates = lessons.map((l) => l.template).toSet();
      expect(templates.contains(LessonTemplate.listening), isTrue,
          reason: '${s.id} missing listening template');
      expect(templates.contains(LessonTemplate.reading), isTrue,
          reason: '${s.id} missing reading template');
      // Listening path has phases with transcript-capable summary/dialogue.
      final listeningLessons =
          lessons.where((l) => l.template == LessonTemplate.listening);
      expect(listeningLessons, isNotEmpty);
      for (final l in listeningLessons) {
        expect(l.content.listeningPhases, isNotEmpty,
            reason: '${l.id} listeningPhases empty');
        final hasTranscript = l.content.listeningPhases
            .any((p) => p.transcript.trim().isNotEmpty);
        expect(hasTranscript, isTrue,
            reason: '${l.id} needs TTS-ready transcript text');
      }
      final readingLessons =
          lessons.where((l) => l.template == LessonTemplate.reading);
      for (final l in readingLessons) {
        expect(l.content.readingPassage, isNotNull,
            reason: '${l.id} missing readingPassage');
        expect(l.content.readingPassage!.paragraphs, isNotEmpty);
        expect(l.flattenedStages, isNotEmpty,
            reason: '${l.id} missing comprehension items');
      }
    }
  });

  test('resource pool is materially larger than thin baseline', () {
    // Pre-goal baseline was ~30 words / 6 expressions / 0 grammar.
    expect(words.length, greaterThanOrEqualTo(100));
    expect(expressions.length, greaterThanOrEqualTo(12));
    expect(grammarPoints.length, greaterThanOrEqualTo(4));
  });

  test('parsed lessons expose playable flattened stages for intro items', () {
    final s1 = sections.firstWhere((s) => s.id == 'section1');
    final intro = s1.units
        .expand((u) => u.lessons)
        .firstWhere((l) => l.id == 's1-l2');
    expect(intro.template, LessonTemplate.intro);
    expect(intro.flattenedStages, isNotEmpty);
  });
}
