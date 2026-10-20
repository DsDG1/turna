// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/ai/ai_course_explainer.dart';
import 'package:turna/application/ai/ai_course_spec.dart';
import 'package:turna/application/ai/ai_grounded_resource_provider.dart';
import 'package:turna/application/ai/ai_json_schemas.dart';
import 'package:turna/application/ai/ai_prompt_catalog.dart';
import 'package:turna/application/ai/ai_prompt_overrides.dart';
import 'package:turna/application/ai/engine/ai_cancel_token.dart';
import 'package:turna/application/ai/engine/ai_engine.dart';
import 'package:turna/application/ai/engine/ai_engine_config.dart';
import 'package:turna/application/ai/practice/ai_practice_models.dart';
import 'package:turna/application/ai/practice/ai_practice_pipeline.dart';
import 'package:turna/application/ai/practice/ai_practice_prompts.dart';
import 'package:turna/application/ai/practice/ai_practice_quality.dart';
import 'package:turna/core/logger.dart';

/// User-facing failure of one generation job. [message] is safe to persist and
/// show in the library card; [details] carries the validator errors for logs.
class AiPracticeGenerationException implements Exception {
  const AiPracticeGenerationException(this.message, [this.details = const []]);

  final String message;
  final List<String> details;

  @override
  String toString() =>
      'AiPracticeGenerationException($message${details.isEmpty ? '' : '; ${details.take(3).join(' | ')}'})';
}

/// Phased section generator (outline → per-lesson fill → validate).
///
/// Network calls go through [AiEngine]; the shape rules live in
/// [AiPracticePipeline]. The queue owns retries/lifecycle, so this class only
/// reports progress and throws on unrecoverable output.
@lazySingleton
class AiPracticeGenerator {
  AiPracticeGenerator(
    this._engine,
    this._grounded,
  );

  final AiEngine _engine;
  final AiGroundedResourceProvider _grounded;

  /// Repair calls allowed per lesson before the job fails. One was not enough:
  /// the first retry fixes shape (a flat `questions` array, a missing id) and
  /// the second is what rescues a lesson whose *answers* were broken.
  static const int _maxRepairs = 2;

  Future<AiPracticeGenerationResult> generate({
    required AiEngineConfig config,
    required AiPracticeRequest request,
    required AiCancelToken cancelToken,
    required void Function(AiPracticeProgress) onProgress,
  }) async {
    final spec = request.spec;
    final systemPrompt = AiPromptCatalog.courseGeneration(
      override: AiPromptOverridesStore.overrideFor(
        AiPromptFeature.courseGeneration,
      ),
    );

    onProgress(const AiPracticeProgress(
      phase: AiPracticePhase.outline,
      message: '正在生成大纲…',
    ));

    final grounded = await _loadGrounded(spec);
    final outlineMessages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
      {
        'role': 'user',
        'content': AiPracticePrompts.outlinePrompt(
          request,
          groundedContext: grounded,
        ),
      },
    ];

    var outlineText = await _jsonCall(
      config: config,
      messages: outlineMessages,
      cancelToken: cancelToken,
      temperature: 0.3,
      timeout: const Duration(seconds: 90),
      jsonSchema: AiJsonSchemas.courseOutline,
    );
    var outline = AiPracticePipeline.decodeObject(outlineText);
    var outlineErrors = AiPracticePipeline.validateOutline(
      outline,
      expectedUnits: spec.unitCount,
      expectedLessonsPerUnit: spec.lessonsPerUnit,
    );
    if (outlineErrors.isNotEmpty) {
      logger.w('practice outline invalid, repairing: $outlineErrors');
      outlineMessages
        ..add({'role': 'assistant', 'content': outlineText})
        ..add({
          'role': 'user',
          'content': AiPracticePrompts.outlineRepairPrompt(outlineErrors),
        });
      outlineText = await _jsonCall(
        config: config,
        messages: outlineMessages,
        cancelToken: cancelToken,
        temperature: 0.2,
        timeout: const Duration(seconds: 90),
        jsonSchema: AiJsonSchemas.courseOutline,
      );
      outline = AiPracticePipeline.decodeObject(outlineText);
      outlineErrors = AiPracticePipeline.validateOutline(
        outline,
        expectedUnits: spec.unitCount,
        expectedLessonsPerUnit: spec.lessonsPerUnit,
      );
      if (outlineErrors.isNotEmpty) {
        throw AiPracticeGenerationException(
          '大纲校验失败，请重试。',
          outlineErrors,
        );
      }
    }

    final section = AiPracticePipeline.sectionShell(
      outline,
      sectionId: request.id,
      sectionName: request.title,
      description: spec.topic,
    );
    final lessons = AiPracticePipeline.iterLessons(outline);
    if (lessons.isEmpty) {
      throw const AiPracticeGenerationException('大纲没有生成任何课时。');
    }

    final total = lessons.length;
    var done = 0;
    onProgress(AiPracticeProgress(
      phase: AiPracticePhase.lessons,
      done: done,
      total: total,
      message: '正在生成第 1/$total 课…',
    ));

    for (final entry in lessons) {
      final lessonId = entry.lesson['id'].toString();
      final template = entry.lesson['template'].toString();
      final messages = <Map<String, dynamic>>[
        {'role': 'system', 'content': systemPrompt},
        {
          'role': 'user',
          'content': AiPracticePrompts.lessonPrompt(
            request: request,
            outline: outline,
            lessonOutline: entry.lesson,
            unitId: entry.unitId,
          ),
        },
      ];

      var lessonText = await _jsonCall(
        config: config,
        messages: messages,
        cancelToken: cancelToken,
        temperature: 0.4,
        timeout: const Duration(seconds: 120),
        jsonSchema: AiJsonSchemas.lessonBody,
      );
      var lesson = AiPracticePipeline.normalizeLessonJson(
        AiPracticePipeline.decodeObject(lessonText),
        lessonId: lessonId,
        template: template,
      );
      var errors = _lessonErrors(outline, entry.unitId, lesson);
      // Two repairs, not one: the first retry usually fixes shape, the second
      // is what saves a lesson whose *content* was broken (out-of-range
      // correctIndex, duplicated options) rather than its JSON.
      for (var attempt = 0;
          errors.isNotEmpty && attempt < _maxRepairs;
          attempt++) {
        logger.w('practice lesson $lessonId invalid (repair ${attempt + 1}), '
            'errors: $errors');
        messages
          ..add({'role': 'assistant', 'content': lessonText})
          ..add({
            'role': 'user',
            'content': AiPracticePrompts.repairPrompt(errors),
          });
        lessonText = await _jsonCall(
          config: config,
          messages: messages,
          cancelToken: cancelToken,
          temperature: 0.2,
          timeout: const Duration(seconds: 120),
          jsonSchema: AiJsonSchemas.lessonBody,
        );
        lesson = AiPracticePipeline.normalizeLessonJson(
          AiPracticePipeline.decodeObject(lessonText),
          lessonId: lessonId,
          template: template,
        );
        errors = _lessonErrors(outline, entry.unitId, lesson);
      }
      if (errors.isNotEmpty) {
        throw AiPracticeGenerationException(
          '第 $lessonId 课校验失败，请重试。',
          errors,
        );
      }

      AiPracticePipeline.spliceLesson(section, lessonId, lesson);
      done++;
      onProgress(AiPracticeProgress(
        phase: AiPracticePhase.lessons,
        done: done,
        total: total,
        message: done >= total ? '正在做最终校验…' : '正在生成第 ${done + 1}/$total 课…',
      ));
    }

    onProgress(const AiPracticeProgress(
      phase: AiPracticePhase.validating,
      message: '正在校验…',
    ));
    final sectionErrors = AiPracticePipeline.validateSectionJson(section);
    if (sectionErrors.isNotEmpty) {
      logger.w('practice section invalid: $sectionErrors');
      throw AiPracticeGenerationException('整节校验失败，请重试。', sectionErrors);
    }
    // Whole-section content verification (answerable questions, vocabulary
    // coverage, non-empty stages). Advisory findings do not block: they ride
    // along in the stored report and are shown in the library detail page.
    final quality = AiPracticeQualityChecker.check(section);
    if (!quality.passed) {
      logger.w('practice section failed quality gate: '
          '${quality.blockingMessages}');
      throw AiPracticeGenerationException(
        '内容校验未通过，请重试。',
        quality.blockingMessages,
      );
    }

    String? explanation;
    if (request.explanationRequested) {
      try {
        explanation = await explainGeneratedCourse(
          engine: _engine,
          config: config,
          spec: spec,
          sectionJson: section,
          cancelToken: cancelToken,
        );
      } catch (e) {
        // Explanation is optional; the practice itself is already valid.
        logger.w('practice explanation failed: $e');
      }
    }

    return AiPracticeGenerationResult(
      section: section,
      explanation: explanation,
      qualityJson: quality.toJsonString(),
    );
  }

  /// Apply a whole-section instruction to an existing generated draft.
  ///
  /// Ids/templates are preserved by the prompt and re-checked by
  /// [AiPracticePipeline.validateSectionJson]; one repair call is allowed.
  Future<Map<String, dynamic>> adjust({
    required AiEngineConfig config,
    required AiPracticeRequest request,
    required Map<String, dynamic> current,
    required String instruction,
    required AiCancelToken cancelToken,
  }) async {
    final systemPrompt = AiPromptCatalog.courseGeneration(
      override: AiPromptOverridesStore.overrideFor(
        AiPromptFeature.courseGeneration,
      ),
    );
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
      {
        'role': 'user',
        'content': AiPracticePrompts.adjustPrompt(
          section: current,
          instruction: instruction,
        ),
      },
    ];

    var text = await _jsonCall(
      config: config,
      messages: messages,
      cancelToken: cancelToken,
      temperature: 0.3,
      timeout: const Duration(seconds: 120),
      jsonSchema: AiJsonSchemas.courseOutline,
    );
    var parsed = AiPracticePipeline.decodeObject(text);
    var errors = AiPracticePipeline.validateSectionJson(parsed);
    if (errors.isEmpty) {
      errors = AiPracticeQualityChecker.check(parsed).blockingMessages;
    }
    if (errors.isNotEmpty) {
      messages
        ..add({'role': 'assistant', 'content': text})
        ..add({
          'role': 'user',
          'content': AiPracticePrompts.repairPrompt(errors),
        });
      text = await _jsonCall(
        config: config,
        messages: messages,
        cancelToken: cancelToken,
        temperature: 0.2,
        timeout: const Duration(seconds: 120),
        jsonSchema: AiJsonSchemas.courseOutline,
      );
      parsed = AiPracticePipeline.decodeObject(text);
      errors = AiPracticePipeline.validateSectionJson(parsed);
      if (errors.isEmpty) {
        errors = AiPracticeQualityChecker.check(parsed).blockingMessages;
      }
      if (errors.isNotEmpty) {
        throw AiPracticeGenerationException('调整结果校验失败，请重试。', errors);
      }
    }
    // Keep the original identity even if the model rewrote it.
    parsed['id'] = current['id'];
    return parsed;
  }

  Future<String?> _loadGrounded(AiCourseSpec spec) async {
    if (!spec.groundedMode) return null;
    try {
      await _grounded.load(scope: spec.resourceScope);
      if (_grounded.error != null) return null;
      return _grounded.formatContext(maxResources: spec.maxGroundedResources);
    } catch (e) {
      logger.w('practice grounded load failed: $e');
      return null;
    }
  }

  Future<String> _jsonCall({
    required AiEngineConfig config,
    required List<Map<String, dynamic>> messages,
    required AiCancelToken cancelToken,
    required double temperature,
    required Duration timeout,
    Map<String, dynamic>? jsonSchema,
  }) async {
    final result = await _engine.requestJson(
      config: config,
      messages: messages,
      temperature: temperature,
      timeout: timeout,
      jsonSchema: jsonSchema,
      cancelToken: cancelToken,
    );
    // A reply cut off by the output-token limit is not a parse bug. Telling the
    // user "JSON 解析失败，请重试" for a `finish_reason == length` reply made
    // them retry an impossible request; the fix is to ask for less content.
    if (result.isTruncated) {
      throw const AiPracticeGenerationException(
        '模型输出达到长度上限被截断。请减少单元/课时数量后重试。',
      );
    }
    final content = result.content.trim();
    if (content.isEmpty) {
      throw const AiPracticeGenerationException('AI 返回了空内容。');
    }
    return content;
  }

  Map<String, dynamic> _wrapLesson(
    Map<String, dynamic> outline,
    String unitId,
    Map<String, dynamic> lesson,
  ) {
    return {
      'id': 'tmp-section',
      'name': 'tmp',
      'description': '',
      'words': outline['words'] ?? const [],
      'expressions': outline['expressions'] ?? const [],
      'grammarPoints': outline['grammarPoints'] ?? const [],
      'units': [
        {
          'id': unitId,
          'name': unitId,
          'lessons': [lesson],
        }
      ],
    };
  }

  /// Structural + content errors for one lesson, as repair-prompt lines.
  List<String> _lessonErrors(
    Map<String, dynamic> outline,
    String unitId,
    Map<String, dynamic> lesson,
  ) {
    final wrapped = _wrapLesson(outline, unitId, lesson);
    final quality = AiPracticeQualityChecker.check(
      wrapped,
      wordCoverage: false,
    );
    return [
      ...AiPracticePipeline.validateSectionJson(wrapped),
      ...quality.blockingMessages,
    ];
  }
}
