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

/// Phased section generator (outline → per-lesson fill → validate → polish).
///
/// Network calls go through [AiEngine]; shape/normalization rules live in
/// [AiPracticePipeline] / `AiPracticeNormalizer`. Borrows the core reliability
/// patterns from `tool/gui`:
///   * deterministic pre-validation normalization (fixes template/item slips);
///   * FormatException-tolerant repair loop with temperature decay;
///   * automatic compact retry when a lesson hits output token truncation;
///   * per-lesson checkpoint callbacks for resumable multi-unit courses;
///   * optional second-pass glossary fill for `auto-fix` stubs.
@lazySingleton
class AiPracticeGenerator {
  AiPracticeGenerator(
    this._engine,
    this._grounded,
  );

  final AiEngine _engine;
  final AiGroundedResourceProvider _grounded;

  /// Repair calls allowed per outline or lesson before failing.
  static const int _maxRepairs = 2;

  /// Temperature schedule across initial attempt + repair passes (mirrors
  /// `tool/gui/src/backend/ai/validate_loop.py` temperature decay).
  static double _temperatureForAttempt(double base, int attempt) {
    final decayed = base - attempt * 0.18;
    return decayed < 0.05 ? 0.05 : decayed;
  }

  /// Phase A standalone entry: generate, normalize, and validate an outline
  /// JSON object for the two-step "先审大纲再填课" workflow.
  Future<Map<String, dynamic>> generateOutline({
    required AiEngineConfig config,
    required AiPracticeRequest request,
    required AiCancelToken cancelToken,
  }) async {
    final spec = request.spec;
    final systemPrompt = AiPromptCatalog.courseGeneration(
      override: AiPromptOverridesStore.overrideFor(
        AiPromptFeature.courseGeneration,
      ),
    );
    final grounded = await _loadGrounded(spec);
    final messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
      {
        'role': 'user',
        'content': AiPracticePrompts.outlinePrompt(
          request,
          groundedContext: grounded,
        ),
      },
    ];

    var lastErrors = const <String>[];
    for (var attempt = 0; attempt <= _maxRepairs; attempt++) {
      final raw = await _jsonCall(
        config: config,
        messages: messages,
        cancelToken: cancelToken,
        temperature: _temperatureForAttempt(0.3, attempt),
        timeout: const Duration(seconds: 90),
        jsonSchema: AiJsonSchemas.courseOutline,
      );
      Map<String, dynamic> decoded;
      try {
        decoded = AiPracticePipeline.decodeObject(raw);
      } on FormatException catch (e) {
        lastErrors = ['Invalid JSON: ${e.message}'];
        logger.w('practice outline JSON parse failed (attempt ${attempt + 1}): '
            '${e.message}');
        if (attempt >= _maxRepairs) break;
        messages
          ..add({'role': 'assistant', 'content': raw})
          ..add({
            'role': 'user',
            'content': AiPracticePrompts.jsonSyntaxRepairPrompt(e.message),
          });
        continue;
      }

      final normalized = AiPracticePipeline.normalizeOutline(
        decoded,
        fallbackSectionId: request.id,
        fallbackTitle: request.title,
        requestedTemplate: spec.template,
      );
      final errors = AiPracticePipeline.validateOutline(
        normalized,
        expectedUnits: spec.unitCount,
        expectedLessonsPerUnit: spec.lessonsPerUnit,
      );
      if (errors.isEmpty) return normalized;

      lastErrors = errors;
      logger.w('practice outline invalid (attempt ${attempt + 1}): $errors');
      if (attempt >= _maxRepairs) break;
      messages
        ..add({'role': 'assistant', 'content': raw})
        ..add({
          'role': 'user',
          'content': AiPracticePrompts.outlineRepairPrompt(errors),
        });
    }

    throw AiPracticeGenerationException(
      '大纲校验失败，请重试。',
      lastErrors,
    );
  }

  Future<AiPracticeGenerationResult> generate({
    required AiEngineConfig config,
    required AiPracticeRequest request,
    required AiCancelToken cancelToken,
    required void Function(AiPracticeProgress) onProgress,
    Map<String, dynamic>? approvedOutline,
    Map<String, dynamic>? resumeSection,
    Set<String> completedLessonIds = const <String>{},
    void Function(
            Map<String, dynamic> partialSection, Set<String> completedIds)?
        onCheckpoint,
  }) async {
    final spec = request.spec;
    final systemPrompt = AiPromptCatalog.courseGeneration(
      override: AiPromptOverridesStore.overrideFor(
        AiPromptFeature.courseGeneration,
      ),
    );

    final Map<String, dynamic> outline;
    final Map<String, dynamic> section;
    final completed = Set<String>.from(completedLessonIds);

    if (resumeSection != null && completed.isNotEmpty) {
      section = Map<String, dynamic>.from(resumeSection);
      outline = approvedOutline ?? request.approvedOutline ?? section;
    } else if (approvedOutline != null || request.approvedOutline != null) {
      final rawApproved = approvedOutline ?? request.approvedOutline!;
      outline = AiPracticePipeline.normalizeOutline(
        rawApproved,
        fallbackSectionId: request.id,
        fallbackTitle: request.title,
        requestedTemplate: spec.template,
      );
      final outlineErrors = AiPracticePipeline.validateOutline(
        outline,
        expectedUnits: 0,
        expectedLessonsPerUnit: 0,
      );
      if (outlineErrors.isNotEmpty) {
        throw AiPracticeGenerationException('大纲校验失败，请检查后重试。', outlineErrors);
      }
      section = AiPracticePipeline.sectionShell(
        outline,
        sectionId: request.id,
        sectionName: outline['name']?.toString().trim().isNotEmpty == true
            ? outline['name'].toString().trim()
            : request.title,
        description: outline['description']?.toString() ?? spec.topic,
      );
    } else {
      onProgress(const AiPracticeProgress(
        phase: AiPracticePhase.outline,
        message: '正在生成大纲…',
      ));
      outline = await generateOutline(
        config: config,
        request: request,
        cancelToken: cancelToken,
      );
      section = AiPracticePipeline.sectionShell(
        outline,
        sectionId: request.id,
        sectionName: request.title,
        description: outline['description']?.toString().isNotEmpty == true
            ? outline['description'].toString()
            : spec.topic,
      );
    }

    final lessons = AiPracticePipeline.iterLessons(outline);
    if (lessons.isEmpty) {
      throw const AiPracticeGenerationException('大纲没有生成任何课时。');
    }

    final wordById = _wordMapOf(outline);
    final total = lessons.length;
    var done = lessons
        .where((e) => completed.contains(e.lesson['id'].toString()))
        .length;

    onProgress(AiPracticeProgress(
      phase: AiPracticePhase.lessons,
      done: done,
      total: total,
      message: done >= total ? '正在做最终校验…' : '正在生成第 ${done + 1}/$total 课…',
    ));

    // Persist initial shell so even a crash on lesson 1 preserves the outline.
    onCheckpoint?.call(section, completed);

    for (final entry in lessons) {
      final lessonId = entry.lesson['id'].toString();
      if (completed.contains(lessonId)) continue;

      final lesson = await _fillSingleLesson(
        config: config,
        systemPrompt: systemPrompt,
        request: request,
        outline: outline,
        unitId: entry.unitId,
        lessonOutline: entry.lesson,
        wordById: wordById,
        cancelToken: cancelToken,
      );

      AiPracticePipeline.spliceLesson(section, lessonId, lesson);
      completed.add(lessonId);
      done++;
      onCheckpoint?.call(section, completed);
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

    // Best-effort second-pass glossary fill for any auto-fixed stubs.
    await _fillNeedsReviewResources(
      config: config,
      section: section,
      spec: spec,
      cancelToken: cancelToken,
    );

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

  /// Regenerate one specific lesson inside an existing [currentSection] without
  /// touching any other lesson.
  Future<({Map<String, dynamic> section, String qualityJson})>
      regenerateLesson({
    required AiEngineConfig config,
    required AiPracticeRequest request,
    required Map<String, dynamic> currentSection,
    required String lessonId,
    required AiCancelToken cancelToken,
  }) async {
    final section = Map<String, dynamic>.from(currentSection);
    final lessons = AiPracticePipeline.iterLessons(section);
    final match = lessons.where((e) => e.lesson['id'].toString() == lessonId);
    if (match.isEmpty) {
      throw AiPracticeGenerationException('找不到课时 $lessonId，无法重生成。');
    }
    final target = match.first;
    final systemPrompt = AiPromptCatalog.courseGeneration(
      override: AiPromptOverridesStore.overrideFor(
        AiPromptFeature.courseGeneration,
      ),
    );
    final freshLesson = await _fillSingleLesson(
      config: config,
      systemPrompt: systemPrompt,
      request: request,
      outline: section,
      unitId: target.unitId,
      lessonOutline: target.lesson,
      wordById: _wordMapOf(section),
      cancelToken: cancelToken,
    );
    AiPracticePipeline.spliceLesson(section, lessonId, freshLesson);
    final sectionErrors = AiPracticePipeline.validateSectionJson(section);
    if (sectionErrors.isNotEmpty) {
      throw AiPracticeGenerationException('重生成课时校验失败，请重试。', sectionErrors);
    }
    final quality = AiPracticeQualityChecker.check(section);
    if (!quality.passed) {
      throw AiPracticeGenerationException(
        '重生成课时内容校验未通过，请重试。',
        quality.blockingMessages,
      );
    }
    return (section: section, qualityJson: quality.toJsonString());
  }

  /// Apply a whole-section instruction to an existing generated draft.
  ///
  /// Ids/templates are preserved by the prompt and re-checked by
  /// [AiPracticePipeline.validateSectionJson]; up to [_maxRepairs] repair calls
  /// are allowed (including JSON syntax recovery).
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

    var lastErrors = const <String>[];
    for (var attempt = 0; attempt <= _maxRepairs; attempt++) {
      final raw = await _jsonCall(
        config: config,
        messages: messages,
        cancelToken: cancelToken,
        temperature: _temperatureForAttempt(0.3, attempt),
        timeout: const Duration(seconds: 120),
        jsonSchema: AiJsonSchemas.courseSection,
      );
      Map<String, dynamic> parsed;
      try {
        parsed = AiPracticePipeline.normalizeSectionJson(
          AiPracticePipeline.decodeObject(raw),
        );
      } on FormatException catch (e) {
        lastErrors = ['Invalid JSON: ${e.message}'];
        if (attempt >= _maxRepairs) break;
        messages
          ..add({'role': 'assistant', 'content': raw})
          ..add({
            'role': 'user',
            'content': AiPracticePrompts.jsonSyntaxRepairPrompt(e.message),
          });
        continue;
      }

      // Keep the original identity even if the model rewrote it.
      parsed['id'] = current['id'];
      var errors = AiPracticePipeline.validateSectionJson(parsed);
      if (errors.isEmpty) {
        errors = AiPracticeQualityChecker.check(parsed).blockingMessages;
      }
      if (errors.isEmpty) return parsed;

      lastErrors = errors;
      if (attempt >= _maxRepairs) break;
      messages
        ..add({'role': 'assistant', 'content': raw})
        ..add({
          'role': 'user',
          'content': AiPracticePrompts.repairPrompt(errors),
        });
    }

    throw AiPracticeGenerationException('调整结果校验失败，请重试。', lastErrors);
  }

  Future<Map<String, dynamic>> _fillSingleLesson({
    required AiEngineConfig config,
    required String systemPrompt,
    required AiPracticeRequest request,
    required Map<String, dynamic> outline,
    required String unitId,
    required Map<String, dynamic> lessonOutline,
    required Map<String, Map<String, dynamic>> wordById,
    required AiCancelToken cancelToken,
  }) async {
    final lessonId = lessonOutline['id'].toString();
    final template = lessonOutline['template'].toString();

    var messages = <Map<String, dynamic>>[
      {'role': 'system', 'content': systemPrompt},
      {
        'role': 'user',
        'content': AiPracticePrompts.lessonPrompt(
          request: request,
          outline: outline,
          lessonOutline: lessonOutline,
          unitId: unitId,
        ),
      },
    ];

    var lastErrors = const <String>[];
    var compactRetried = false;

    for (var attempt = 0; attempt <= _maxRepairs; attempt++) {
      final result = await _jsonCallRaw(
        config: config,
        messages: messages,
        cancelToken: cancelToken,
        temperature: _temperatureForAttempt(0.4, attempt),
        timeout: const Duration(seconds: 120),
        jsonSchema: AiJsonSchemas.lessonBody,
      );

      if (result.isTruncated) {
        logger
            .w('practice lesson $lessonId truncated on attempt ${attempt + 1}');
        if (!compactRetried && attempt < _maxRepairs) {
          compactRetried = true;
          // Restart cleanly with a compact item budget so the next call fits.
          messages = <Map<String, dynamic>>[
            {'role': 'system', 'content': systemPrompt},
            {
              'role': 'user',
              'content': AiPracticePrompts.lessonPrompt(
                request: request,
                outline: outline,
                lessonOutline: lessonOutline,
                unitId: unitId,
                compactForTruncation: true,
              ),
            },
          ];
          continue;
        }
        throw const AiPracticeGenerationException(
          '模型输出达到长度上限被截断。请减少每课题量或课时数量后重试。',
        );
      }

      final raw = result.content.trim();
      if (raw.isEmpty) {
        lastErrors = const ['AI 返回了空内容。'];
        if (attempt >= _maxRepairs) break;
        continue;
      }

      Map<String, dynamic> decoded;
      try {
        decoded = AiPracticePipeline.decodeObject(raw);
      } on FormatException catch (e) {
        lastErrors = ['Invalid JSON: ${e.message}'];
        logger.w('practice lesson $lessonId JSON parse failed '
            '(attempt ${attempt + 1}): ${e.message}');
        if (attempt >= _maxRepairs) break;
        messages
          ..add({'role': 'assistant', 'content': raw})
          ..add({
            'role': 'user',
            'content': AiPracticePrompts.jsonSyntaxRepairPrompt(e.message),
          });
        continue;
      }

      final lesson = AiPracticePipeline.normalizeLessonJson(
        decoded,
        lessonId: lessonId,
        template: template,
        outlineWordById: wordById,
      );
      final errors = _lessonErrors(outline, unitId, lesson);
      if (errors.isEmpty) return lesson;

      lastErrors = errors;
      logger.w('practice lesson $lessonId invalid (attempt ${attempt + 1}), '
          'errors: $errors');
      if (attempt >= _maxRepairs) break;
      messages
        ..add({'role': 'assistant', 'content': raw})
        ..add({
          'role': 'user',
          'content': AiPracticePrompts.repairPrompt(errors),
        });
    }

    throw AiPracticeGenerationException(
      '第 $lessonId 课校验失败，请重试。',
      lastErrors,
    );
  }

  /// Ported from `tool/gui/src/backend/ai/section_ops.py:fill_needs_review_resources`.
  /// Best-effort single cheap JSON call that replaces `auto-fix` / empty
  /// translations; failures are logged and ignored so valid sections are never
  /// rejected over polish.
  Future<void> _fillNeedsReviewResources({
    required AiEngineConfig config,
    required Map<String, dynamic> section,
    required AiCourseSpec spec,
    required AiCancelToken cancelToken,
  }) async {
    final targets = <({String bucket, Map<String, dynamic> entry})>[];
    for (final bucket in const ['words', 'expressions']) {
      final list = section[bucket];
      if (list is! List) continue;
      for (final raw in list) {
        if (raw is! Map<String, dynamic>) continue;
        final tags = {
          for (final t in (raw['tags'] as List? ?? const []))
            t.toString().toLowerCase(),
        };
        final trans = (raw['translation']?.toString() ?? '').trim();
        if (tags.contains('auto-fix') ||
            tags.contains('needs-review') ||
            trans.isEmpty ||
            trans == '[待补]') {
          targets.add((bucket: bucket, entry: raw));
        }
      }
    }
    if (targets.isEmpty) return;

    final payload = [
      for (final t in targets.take(25))
        {
          'bucket': t.bucket,
          'id': t.entry['id'] ?? '',
          'term': t.entry['term'] ?? '',
          'translation': t.entry['translation'] ?? '',
        },
    ];
    try {
      final raw = await _jsonCall(
        config: config,
        messages: [
          {
            'role': 'system',
            'content': 'You complete language-course glossary entries. '
                'Output ONLY valid JSON, no prose, no markdown fences.',
          },
          {
            'role': 'user',
            'content': AiPracticePrompts.fillNeedsReviewPrompt(
              language: spec.language,
              sourceLanguage: spec.sourceLanguage,
              entries: payload,
            ),
          },
        ],
        cancelToken: cancelToken,
        temperature: 0.2,
        timeout: const Duration(seconds: 60),
      );
      final parsed = AiPracticePipeline.decodeObject(raw);
      final updates = parsed['entries'];
      if (updates is! List) return;
      final byId = <String, Map<String, dynamic>>{
        for (final u in updates)
          if (u is Map && u['id'] != null)
            u['id'].toString(): Map<String, dynamic>.from(u),
      };
      for (final t in targets) {
        final id = t.entry['id']?.toString() ?? '';
        final patch = byId[id];
        if (patch == null) continue;
        final trans = (patch['translation']?.toString() ?? '').trim();
        final term = (patch['term']?.toString() ?? '').trim();
        if (trans.isNotEmpty && trans != '[待补]') {
          if (term.isNotEmpty) t.entry['term'] = term;
          t.entry['translation'] = trans;
          t.entry['tags'] = [
            for (final tag in (t.entry['tags'] as List? ?? const []))
              if (tag.toString().toLowerCase() != 'auto-fix' &&
                  tag.toString().toLowerCase() != 'needs-review')
                tag,
          ];
        }
      }
    } on AiCancelled {
      rethrow;
    } catch (e) {
      logger.w('practice needs-review glossary fill skipped: $e');
    }
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

  Future<({String content, bool isTruncated})> _jsonCallRaw({
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
    return (content: result.content, isTruncated: result.isTruncated);
  }

  Future<String> _jsonCall({
    required AiEngineConfig config,
    required List<Map<String, dynamic>> messages,
    required AiCancelToken cancelToken,
    required double temperature,
    required Duration timeout,
    Map<String, dynamic>? jsonSchema,
  }) async {
    final result = await _jsonCallRaw(
      config: config,
      messages: messages,
      cancelToken: cancelToken,
      temperature: temperature,
      timeout: timeout,
      jsonSchema: jsonSchema,
    );
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

  static Map<String, Map<String, dynamic>> _wordMapOf(
      Map<String, dynamic> outline) {
    return <String, Map<String, dynamic>>{
      for (final w in (outline['words'] as List? ?? const []))
        if (w is Map && w['id'] != null)
          w['id'].toString(): Map<String, dynamic>.from(w),
    };
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
      'words': [
        for (final w in (outline['words'] as List? ?? const []))
          if (w is Map) Map<String, dynamic>.from(w),
      ],
      'expressions': [
        for (final e in (outline['expressions'] as List? ?? const []))
          if (e is Map) Map<String, dynamic>.from(e),
      ],
      'grammarPoints': [
        for (final g in (outline['grammarPoints'] as List? ?? const []))
          if (g is Map) Map<String, dynamic>.from(g),
      ],
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
