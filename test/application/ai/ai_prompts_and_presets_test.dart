// Consolidated tests for AI genres, prompt builder, textbook presets, and note study tools.

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/ai/ai_course_spec.dart';
import 'package:turna/application/ai/ai_genre.dart';
import 'package:turna/application/ai/ai_prompt_builder.dart';
import 'package:turna/application/ai/ai_saved_explanations.dart';
import 'package:turna/application/ai/companion/ai_note_study_tools.dart';
import 'package:turna/application/ai/textbook/textbook_presets.dart';

void main() {
  group('ai_genre', () {
    test('genreToTemplate maps known tags', () {
      expect(genreToTemplate('[intro]'), 'intro');
      expect(genreToTemplate('[listening]'), 'listening');
      expect(genreToTemplate('[mastery]'), 'mastery');
      expect(genreToTemplate('intro'), 'intro');
      expect(genreToTemplate('[unknown]'), 'mixed');
    });

    test('templateLabel returns human-readable label', () {
      expect(templateLabel('intro'), 'New Words');
      expect(templateLabel('listening'), 'Listening');
      expect(templateLabel('unknown'), 'unknown');
    });

    test('parseGenreTag returns first recognized tag or null', () {
      expect(parseGenreTag('Travel [listening] vocab'), '[listening]');
      expect(parseGenreTag('no tags here'), isNull);
      expect(parseGenreTag('[unknown]'), isNull);
      expect(parseGenreTag(null), isNull);
      expect(parseGenreTag(''), isNull);
    });

    test('genreTagsInText returns all recognized tags in order', () {
      expect(
        genreTagsInText('[intro] then [listening] then [unknown]'),
        ['[intro]', '[listening]'],
      );
      expect(genreTagsInText('[intro] [intro]'), ['[intro]']);
      expect(genreTagsInText(''), isEmpty);
    });

    test('allGenreTags returns 7 tags', () {
      expect(allGenreTags().length, 7);
    });

    test('genrePromptBlock lists all tags', () {
      final block = genrePromptBlock();
      for (final tag in allGenreTags()) {
        expect(block.contains(tag), isTrue);
      }
    });
  });

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
      expect(p.contains('Available lesson templates'), isTrue);
      expect(p.contains('showWord'), isTrue);
      expect(p.contains('Top-level resource arrays'), isTrue);
      expect(p.contains('ID rules'), isTrue);
      expect(p.contains('Target language: Turkish'), isTrue);
      expect(p.contains('Template for all lessons: intro'), isTrue);
    });

    test('buildPrompt includes genre batch block when enabled', () {
      final p = buildPrompt(spec.copyWith(useGenreBatch: true));
      expect(p.contains('Available genre tags'), isTrue);
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

  group('textbook_presets', () {
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
      expect(
        presetFor('grammar').temperature,
        lessThan(presetFor('dialogue').temperature),
      );
    });
  });

  group('ai_note_study_tools', () {
    const tools = AiNoteStudyTools();

    SavedExplanation sampleNote({String body = '宾格用于特指的直接宾语。'}) =>
        SavedExplanation(
          id: 'note-1',
          title: '土耳其语宾格',
          body: body,
          source: 'hint',
          createdAt: DateTime.utc(2026),
        );

    test('verification creates two to three deterministic offline questions', () {
      expect(tools.verificationQuestions(sampleNote()), hasLength(2));
      final detailed = tools.verificationQuestions(
        sampleNote(body: List.filled(8, '宾格用于特指的直接宾语。').join()),
      );
      expect(detailed, hasLength(3));
      expect(detailed.first.prompt, contains('土耳其语宾格'));
    });

    test('Anki export is one TSV row even when note contains newlines', () {
      final draft = tools.ankiDraft(sampleNote(body: '第一行\n第二行\t补充'));
      expect(draft.asTsv, '土耳其语宾格\t第一行 第二行 补充');
    });
  });
}
