// Dart imports:
import 'dart:convert';

// Project imports:
import 'package:varnamala/application/ai/ai_api_config.dart';
import 'package:varnamala/application/ai/ai_course_service.dart';
import 'package:varnamala/application/ai/ai_resource_consistency.dart';
import 'package:varnamala/core/logger.dart';
import 'package:varnamala/domain/course/interaction.dart';
import 'package:varnamala/domain/course/lesson.dart';
import 'package:varnamala/domain/course/lesson_content.dart';
import 'package:varnamala/domain/course/stage.dart';

/// Result of an AI enhancement operation.
class EnhancementResult {
  /// The transformed interactions (may be different types from input)
  final List<Interaction> interactions;

  /// Whether the enhancement was successful
  final bool success;

  /// Error message if failed
  final String? error;

  const EnhancementResult({
    required this.interactions,
    required this.success,
    this.error,
  });
}

/// Enhances Anki cards using AI transformations.
///
/// Reuses [AiCourseService.requestLessonTransform] pipeline:
/// wraps AnkiCard list as a temporary Lesson JSON, sends to LLM with
/// user instruction, parses + autoFixResources for self-consistency.
///
/// Enhancement types:
/// - Generate distractors → AnkiCard → MultipleChoice
/// - Add example sentences → AnkiCard.hint field enrichment
/// - Cloze → FillBlank conversion
/// - Extract keywords → MatchWords generation
class AnkiCardEnhancer {
  final AiCourseService _service;

  AnkiCardEnhancer({AiCourseService? service})
      : _service = service ?? const AiCourseService();

  /// Enhance a batch of AnkiCard interactions using AI.
  ///
  /// [ankiCards] is the list of AnkiCard interactions to enhance.
  /// [instruction] is the user's natural language instruction
  ///   (e.g. "Generate 3 distractors for each card to make multiple-choice questions").
  /// [resourceIds] provides grounded resource IDs for consistency.
  Future<EnhancementResult> enhance({
    required AiApiConfig config,
    required List<Interaction> ankiCards,
    required String instruction,
    Set<String> resourceIds = const {},
  }) async {
    if (!config.isComplete) {
      return const EnhancementResult(
        interactions: [],
        success: false,
        error: 'AI config not complete',
      );
    }

    if (ankiCards.isEmpty) {
      return const EnhancementResult(interactions: [], success: true);
    }

    try {
      // Wrap cards as a temporary lesson for the transform pipeline
      final tempLesson = _wrapAsLesson(ankiCards);
      final lessonJson = jsonEncode(tempLesson.toJson());

      // Build the transform prompt
      final systemPrompt = _buildSystemPrompt(instruction, resourceIds);
      final userMessage = '''
Transform the following lesson JSON according to the instruction.
Return ONLY the transformed lesson JSON (no markdown fences).

Lesson JSON:
$lessonJson
''';

      final reply = await _service.requestTextReply(
        config: config,
        systemPrompt: systemPrompt,
        messages: [
          {'role': 'user', 'content': userMessage},
        ],
        temperature: 0.5,
        timeout: const Duration(seconds: 90),
      );

      // Parse the transformed lesson
      final transformed = _parseTransformedLesson(reply);
      if (transformed == null) {
        return EnhancementResult(
          interactions: ankiCards,
          success: false,
          error: 'Failed to parse AI response',
        );
      }

      // Extract interactions from transformed lesson
      final interactions = <Interaction>[];
      for (final stage in transformed.flattenedStages) {
        interactions.addAll(stage.items);
      }

      return EnhancementResult(
        interactions: interactions,
        success: true,
      );
    } catch (e) {
      logger.w('AnkiCardEnhancer failed: $e');
      return EnhancementResult(
        interactions: ankiCards,
        success: false,
        error: e.toString(),
      );
    }
  }

  /// Quick enhancement: generate distractors for AnkiCards → MultipleChoice.
  Future<EnhancementResult> generateDistractors({
    required AiApiConfig config,
    required List<Interaction> ankiCards,
  }) {
    return enhance(
      config: config,
      ankiCards: ankiCards,
      instruction:
          'For each flip card (AnkiCard), convert it to a MultipleChoice question. '
          'Use the front as the prompt, the back as the correct answer, '
          'and generate 3 plausible but incorrect distractors. '
          'Keep the same id for each interaction.',
    );
  }

  /// Quick enhancement: add example sentences to AnkiCard hints.
  Future<EnhancementResult> addExampleSentences({
    required AiApiConfig config,
    required List<Interaction> ankiCards,
  }) {
    return enhance(
      config: config,
      ankiCards: ankiCards,
      instruction:
          'For each flip card (AnkiCard), keep it as an AnkiCard but fill the '
          'hint field with a short example sentence using the front content. '
          'Do not change the front or back fields.',
    );
  }

  // ─── Private helpers ───────────────────────────────────────────────

  Lesson _wrapAsLesson(List<Interaction> cards) {
    final stages = <Stage>[];
    for (var i = 0; i < cards.length; i++) {
      stages.add(Stage(
        id: 'enhance-s$i',
        name: 'Card ${i + 1}',
        items: [cards[i]],
      ));
    }

    return Lesson(
      id: 'anki-enhance-temp',
      name: 'Anki Enhancement',
      type: LessonType.normal,
      template: LessonTemplate.legacy,
      content: LessonContent(stages: stages),
    );
  }

  String _buildSystemPrompt(String instruction, Set<String> resourceIds) {
    final buffer = StringBuffer();
    buffer.writeln('''
You are a Varnamala course content transformer. You receive a lesson JSON and
an instruction, and return the transformed lesson JSON.

Rules:
- Preserve the overall lesson structure (id, name, template)
- Transform only the interaction items as instructed
- Valid interaction runtimeTypes: ShowWord, MultipleChoice, MultiSelect, FillBlank,
  TranslateSentence, ListenAndPick, TypeTheWord, ListenOnly, ReorderSentence,
  ReadingMcq, ReadingTrueFalse, ReadingShortAnswer, AnkiCard
- Each interaction MUST have a "runtimeType" field and an "id" field
- MultipleChoice requires: prompt, options (list), correctIndex (int)
- FillBlank requires: sentence, answer
- AnkiCard requires: front, back
- Return ONLY valid JSON, no markdown fences or explanations

Instruction: $instruction
''');

    if (resourceIds.isNotEmpty) {
      buffer.writeln(
          '\nAvailable resource IDs (reuse these, do not invent new ones):');
      buffer.writeln(resourceIds.join(', '));
    }

    return buffer.toString();
  }

  Lesson? _parseTransformedLesson(String reply) {
    try {
      var cleaned = reply.trim();
      // Strip markdown fences if present
      if (cleaned.startsWith('```')) {
        cleaned = cleaned
            .replaceAll(RegExp(r'^```\w*\n?'), '')
            .replaceAll(RegExp(r'\n?```$'), '')
            .trim();
      }

      final json = jsonDecode(cleaned) as Map<String, dynamic>;

      // Run self-consistency checks
      normalizeResources(json);
      autoFixResources(json);

      return Lesson.fromJson(json);
    } catch (e) {
      logger.w('AnkiCardEnhancer parse error: $e');
      return null;
    }
  }
}
