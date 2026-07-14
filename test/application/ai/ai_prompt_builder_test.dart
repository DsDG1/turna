// Project imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/application/ai/ai_course_spec.dart';
import 'package:varnamala/application/ai/ai_prompt_builder.dart';

void main() {
  group('ai_prompt_builder', () {
    final spec = AiCourseSpec(
      language: 'Turkish',
      sourceLanguage: 'Chinese',
      topic: 'Travel',
      level: 'A1',
      unitCount: 1,
      lessonsPerUnit: 3,
      template: 'intro',
    );

    test('buildPrompt contains template schema, resource schema, id rules', () {
      final p = buildPrompt(spec);
      expect(p.contains('可用课模板'), isTrue);
      expect(p.contains('showWord'), isTrue);
      expect(p.contains('顶层资源数组'), isTrue);
      expect(p.contains('ID 规则'), isTrue);
      expect(p.contains('Target language: Turkish'), isTrue);
      expect(p.contains('Template for all lessons: intro'), isTrue);
    });

    test('buildPrompt includes genre batch block when enabled', () {
      final p = buildPrompt(spec.copyWith(useGenreBatch: true));
      expect(p.contains('genre 标签'), isTrue);
      expect(p.contains('multi-template batch mode'), isTrue);
    });

    test('buildPrompt picks listening example for listening template', () {
      final p = buildPrompt(spec.copyWith(template: 'listening'));
      expect(p.contains('listeningPhases'), isTrue);
      expect(p.contains('"template": "listening"'), isTrue);
    });

    test('buildPrompt picks reading example for reading template', () {
      final p = buildPrompt(spec.copyWith(template: 'reading'));
      expect(p.contains('readingPassage'), isTrue);
    });

    test('buildAlignmentPrompt does not request JSON output', () {
      final p = buildAlignmentPrompt(spec);
      expect(p.contains('ALIGN'), isTrue);
      expect(p.contains('Do NOT output the final course JSON'), isTrue);
      expect(p.contains('json_object'), isFalse);
    });

    test('buildAlignmentPrompt mentions topic when empty', () {
      final p = buildAlignmentPrompt(spec.copyWith(topic: ''));
      expect(p.contains('(not specified yet'), isTrue);
    });
  });
}