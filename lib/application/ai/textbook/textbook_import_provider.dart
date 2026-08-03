// Dart imports:
import 'dart:convert';
import 'dart:io';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Project imports:
import 'package:turna/application/ai/ai_course_provider.dart';
import 'package:turna/application/ai/engine/ai_cancel_token.dart';
import 'package:turna/application/ai/engine/ai_engine.dart';
import 'package:turna/application/ai/engine/ai_engine_config.dart';
import 'package:turna/application/ai/engine/ai_recent_tasks_provider.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/application/ai/textbook/import_plan.dart';
import 'package:turna/application/ai/textbook/knowledge_merger.dart';
import 'package:turna/application/ai/textbook/knowledge_prompt.dart';
import 'package:turna/application/ai/textbook/knowledge_schema.dart';
import 'package:turna/application/ai/textbook/markdown_chopper.dart';
import 'package:turna/application/ai/textbook/textbook_presets.dart';
import 'package:turna/application/ai/textbook/textbook_to_course.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/data/course_database.dart' as db;
import 'package:turna/data/course_repository.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/utils/ohos_file_picker.dart';

/// Kind of a flattened knowledge row in the review table.
enum ResourceKind { word, expression, grammar }

/// Editable row for the review table.
class EditableResource {
  EditableResource({
    required this.kind,
    required this.chapterIndex,
    required this.itemIndex,
    required this.id,
    required this.primary,
    required this.secondary,
    this.kept = true,
  });

  final ResourceKind kind;
  final int chapterIndex;
  final int itemIndex;
  final String id;
  String primary;
  String secondary;
  bool kept;
}

/// Steps in the textbook import flow.
enum TextbookImportStep {
  pick,
  parse,
  chapters,
  extract,
  review,
  conflict,
  importDone,
}

/// Orchestrates the textbook import pipeline. Mirrors
/// `tool/gui/src/dialogs/textbook_import_controller.py`.
class TextbookImportProvider extends ChangeNotifier {
  TextbookImportProvider({
    AiEngine? engine,
    CourseRepository? repository,
  })  : _engine = engine ?? getIt<AiEngine>(),
        _repository = repository ?? CourseRepository(getIt<db.CourseDatabase>()),
        _chopper = const MarkdownChopper(),
        _merger = const KnowledgeMerger(),
        _builder = const TextbookToCourse();

  final AiEngine _engine;
  AiCancelToken? _cancelToken;
  final CourseRepository? _repository;
  final MarkdownChopper _chopper;
  final KnowledgeMerger _merger;
  final TextbookToCourse _builder;

  TextbookImportStep _step = TextbookImportStep.pick;
  TextbookImportStep get step => _step;

  String? _filePath;
  String? get filePath => _filePath;

  String _fileName = '';
  String get fileName => _fileName;

  String? _error;
  String? get error => _error;

  List<ChapterResult> _results = [];
  List<ChapterResult> get results => List.unmodifiable(_results);

  bool _isBusy = false;
  bool get isBusy => _isBusy;

  String _language = 'Turkish';
  String get language => _language;

  String _sourceLanguage = 'Chinese';
  String get sourceLanguage => _sourceLanguage;

  String _level = 'A1';
  String get level => _level;

  ImportStrategy _strategy = ImportStrategy.merge;
  ImportStrategy get strategy => _strategy;

  TextbookPreset _preset = presetFor('general');
  TextbookPreset get preset => _preset;

  CollisionReport? _collisionReport;
  CollisionReport? get collisionReport => _collisionReport;

  List<SectionImportPlan> _sectionPlans = [];
  List<SectionImportPlan> get sectionPlans => List.unmodifiable(_sectionPlans);

  String _reviewQuery = '';
  String get reviewQuery => _reviewQuery;

  void updateSettings({
    String? language,
    String? sourceLanguage,
    String? level,
    ImportStrategy? strategy,
    TextbookPreset? preset,
  }) {
    if (language != null) _language = language;
    if (sourceLanguage != null) _sourceLanguage = sourceLanguage;
    if (level != null) _level = level;
    if (strategy != null) _strategy = strategy;
    if (preset != null) _preset = preset;
    notifyListeners();
  }

  void setReviewQuery(String query) {
    _reviewQuery = query;
    notifyListeners();
  }

  void reset() {
    _cancelToken?.cancel();
    _step = TextbookImportStep.pick;
    _filePath = null;
    _fileName = '';
    _error = null;
    _results = [];
    _isBusy = false;
    _collisionReport = null;
    _sectionPlans = [];
    _reviewQuery = '';
    notifyListeners();
  }

  /// Cancel any in-flight extraction (cooperative; the next LLM chunk throws
  /// [AiCancelled], which [extractAll] turns into a return to the chapters step).
  void cancel() {
    _cancelToken?.cancel();
  }

  /// Picks a file and parses it into chapters.
  Future<void> pickFile() async {
    _error = null;
    String? path;
    String name = '';
    try {
      final result = await OhosFilePicker.pickFiles(
        allowedExtensions: const ['md', 'txt'],
      );
      if (result == null || result.files.isEmpty) return;
      path = result.files.single.path;
      name = result.files.single.name;
    } on OhosFilePickerInvalidExtension {
      return;
    }

    if (path == null) {
      _error = 'Could not read file path';
      notifyListeners();
      return;
    }

    _filePath = path;
    _fileName = name;
    _step = TextbookImportStep.parse;
    _isBusy = true;
    notifyListeners();

    try {
      final text = await File(path).readAsString();
      final chapters = _chopper.splitChapters(text);
      _results = [
        for (final c in chapters) ChapterResult(chapter: c),
      ];
      _step = TextbookImportStep.chapters;
    } catch (e) {
      _error = e.toString();
      _step = TextbookImportStep.pick;
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  void setChapterKept(int index, bool kept) {
    if (index < 0 || index >= _results.length) return;
    _results[index].keep = kept;
    notifyListeners();
  }

  /// Extracts knowledge from all kept chapters using the LLM.
  Future<void> extractAll(AiEngineConfig config) async {
    _cancelToken?.cancel();
    final token = AiCancelToken();
    _cancelToken = token;
    _error = null;
    _isBusy = true;
    _step = TextbookImportStep.extract;
    notifyListeners();

    var cancelled = false;
    try {
      for (var i = 0; i < _results.length; i++) {
        final result = _results[i];
        if (!result.keep) continue;
        try {
          final knowledge =
              await _extractChapter(config, result.chapter, token);
          result.knowledge = knowledge;
          result.error = null;
        } on AiCancelled {
          cancelled = true;
          break;
        } catch (e) {
          result.error = e.toString();
          result.knowledge = null;
        }
        notifyListeners();
      }
      _step =
          cancelled ? TextbookImportStep.chapters : TextbookImportStep.review;
    } catch (e) {
      _error = e.toString();
    } finally {
      if (identical(_cancelToken, token)) _cancelToken = null;
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<KnowledgePoints> _extractChapter(
    AiEngineConfig config,
    TextbookChapter chapter,
    AiCancelToken cancelToken,
  ) async {
    final messages = KnowledgePrompt.buildExtractionMessages(
      language: _language,
      sourceLanguage: _sourceLanguage,
      chapterTitle: chapter.title,
      chapterMarkdown: chapter.markdown,
      maxChars: _preset.maxChapterChars,
      extractionStrategy: _preset.strategy,
    );
    final result = await _engine.requestJson(
      config: config,
      messages: messages,
      temperature: _preset.temperature,
      timeout: const Duration(seconds: 120),
      cancelToken: cancelToken,
    );
    final cleaned = _stripCodeFences(result.content);
    final decoded = jsonDecode(cleaned) as Map<String, dynamic>;
    var points = coerceKnowledgePoints(decoded);
    if (_preset.isVocabOnly) {
      points = points.copyWith(
        expressions: const [],
        grammarPoints: const [],
      );
    }
    return points;
  }

  // ─── Review table API ───────────────────────────────────────────────

  List<EditableResource> flattenedResources(ResourceKind kind) {
    final out = <EditableResource>[];
    for (var ci = 0; ci < _results.length; ci++) {
      final r = _results[ci];
      if (!r.keep || r.knowledge == null) continue;
      final k = r.knowledge!;
      final list = switch (kind) {
        ResourceKind.word => k.words,
        ResourceKind.expression => k.expressions,
        ResourceKind.grammar => k.grammarPoints,
      };
      for (var ii = 0; ii < list.length; ii++) {
        final item = list[ii];
        final id = item['id']?.toString() ?? '';
        final primary = kind == ResourceKind.grammar
            ? (item['title']?.toString() ?? '')
            : (item['term']?.toString() ?? '');
        final secondary = kind == ResourceKind.grammar
            ? (item['explanation']?.toString() ?? '')
            : (item['translation']?.toString() ?? '');
        out.add(
          EditableResource(
            kind: kind,
            chapterIndex: ci,
            itemIndex: ii,
            id: id,
            primary: primary,
            secondary: secondary,
          ),
        );
      }
    }
    final q = _reviewQuery.trim().toLowerCase();
    if (q.isEmpty) return out;
    return out
        .where(
          (e) =>
              e.primary.toLowerCase().contains(q) ||
              e.secondary.toLowerCase().contains(q) ||
              e.id.toLowerCase().contains(q),
        )
        .toList();
  }

  int get totalWordCount => _countKind(ResourceKind.word);
  int get totalExpressionCount => _countKind(ResourceKind.expression);
  int get totalGrammarCount => _countKind(ResourceKind.grammar);

  int _countKind(ResourceKind kind) {
    var n = 0;
    for (final r in _results) {
      if (!r.keep || r.knowledge == null) continue;
      final k = r.knowledge!;
      n += switch (kind) {
        ResourceKind.word => k.words.length,
        ResourceKind.expression => k.expressions.length,
        ResourceKind.grammar => k.grammarPoints.length,
      };
    }
    return n;
  }

  void updateResource({
    required ResourceKind kind,
    required int chapterIndex,
    required int itemIndex,
    required String primary,
    required String secondary,
  }) {
    if (chapterIndex < 0 || chapterIndex >= _results.length) return;
    final r = _results[chapterIndex];
    final k = r.knowledge;
    if (k == null) return;
    final list = List<Map<String, dynamic>>.from(switch (kind) {
      ResourceKind.word => k.words,
      ResourceKind.expression => k.expressions,
      ResourceKind.grammar => k.grammarPoints,
    });
    if (itemIndex < 0 || itemIndex >= list.length) return;
    final item = Map<String, dynamic>.from(list[itemIndex]);
    if (kind == ResourceKind.grammar) {
      item['title'] = primary;
      item['explanation'] = secondary;
    } else {
      item['term'] = primary;
      item['translation'] = secondary;
    }
    list[itemIndex] = item;
    r.knowledge = switch (kind) {
      ResourceKind.word => k.copyWith(words: list),
      ResourceKind.expression => k.copyWith(expressions: list),
      ResourceKind.grammar => k.copyWith(grammarPoints: list),
    };
    notifyListeners();
  }

  void removeResource({
    required ResourceKind kind,
    required int chapterIndex,
    required int itemIndex,
  }) {
    if (chapterIndex < 0 || chapterIndex >= _results.length) return;
    final r = _results[chapterIndex];
    final k = r.knowledge;
    if (k == null) return;
    final list = List<Map<String, dynamic>>.from(switch (kind) {
      ResourceKind.word => k.words,
      ResourceKind.expression => k.expressions,
      ResourceKind.grammar => k.grammarPoints,
    });
    if (itemIndex < 0 || itemIndex >= list.length) return;
    list.removeAt(itemIndex);
    r.knowledge = switch (kind) {
      ResourceKind.word => k.copyWith(words: list),
      ResourceKind.expression => k.copyWith(expressions: list),
      ResourceKind.grammar => k.copyWith(grammarPoints: list),
    };
    notifyListeners();
  }

  // ─── Conflict preview ───────────────────────────────────────────────

  /// Build collision report + section plans and advance to conflict step.
  Future<void> prepareConflictPreview() async {
    _error = null;
    _isBusy = true;
    notifyListeners();

    try {
      final repo = _repository;
      final existingWords = repo == null
          ? <String>{}
          : (await repo.vocabulary()).map((w) => w.id).toSet();
      final existingExpressions = repo == null
          ? <String>{}
          : (await repo.expressions()).map((e) => e.id).toSet();
      final existingGrammar = repo == null
          ? <String>{}
          : (await repo.grammarPoints()).map((g) => g.id).toSet();
      final existingSections = repo == null
          ? <String>{}
          : (await repo.sectionShells()).map((s) => s.id).toSet();

      _collisionReport = _merger.analyze(
        _results,
        existingWordIds: existingWords,
        existingExpressionIds: existingExpressions,
        existingGrammarIds: existingGrammar,
      );

      final sections = _builder.buildSections(
        _results,
        language: _language,
        sourceLanguage: _sourceLanguage,
        level: _level,
      );
      final titles = [
        for (final r in _results)
          if (r.keep && r.knowledge != null && !r.knowledge!.isEmpty)
            r.chapter.title,
      ];

      _sectionPlans = planBulkImport(
        sections: sections,
        existingSectionIds: existingSections,
        strategy: _strategy,
        chapterTitles: titles,
      );
      _step = TextbookImportStep.conflict;
    } catch (e, st) {
      logger.e('prepareConflictPreview failed', error: e, stackTrace: st);
      _error = e.toString();
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  void backToReview() {
    if (_step == TextbookImportStep.conflict) {
      _step = TextbookImportStep.review;
      notifyListeners();
    }
  }

  /// Builds course sections from extracted knowledge and writes them to the DB.
  Future<void> importSections(AiCourseProvider courseProvider) async {
    _error = null;
    _isBusy = true;
    notifyListeners();

    final repo = _repository;
    if (repo == null) {
      _error = 'CourseDatabase unavailable on this platform';
      _isBusy = false;
      notifyListeners();
      return;
    }

    try {
      final existingWords =
          (await repo.vocabulary()).map((w) => w.id).toSet();
      final existingExpressions =
          (await repo.expressions()).map((e) => e.id).toSet();
      final existingGrammar =
          (await repo.grammarPoints()).map((g) => g.id).toSet();
      final existingSections =
          (await repo.sectionShells()).map((s) => s.id).toSet();

      // Resource-level strategy (skipExisting filters rows; appendAsNew rewrites ids).
      _merger.apply(
        _results,
        strategy: _strategy,
        existingWordIds: existingWords,
        existingExpressionIds: existingExpressions,
        existingGrammarIds: existingGrammar,
      );

      final sections = _builder.buildSections(
        _results,
        language: _language,
        sourceLanguage: _sourceLanguage,
        level: _level,
      );

      final plans = _sectionPlans.isNotEmpty
          ? _sectionPlans
          : planBulkImport(
              sections: sections,
              existingSectionIds: existingSections,
              strategy: _strategy,
            );

      // Align plan length with rebuilt sections when review edits changed counts.
      final plansToUse = plans.length == sections.length
          ? plans
          : planBulkImport(
              sections: sections,
              existingSectionIds: existingSections,
              strategy: _strategy,
            );

      for (var i = 0; i < sections.length; i++) {
        final plan = i < plansToUse.length
            ? plansToUse[i]
            : SectionImportPlan(
                index: i,
                sourceId: sections[i]['id']?.toString() ?? '',
                targetId: sections[i]['id']?.toString() ?? '',
                exists: false,
                action: ImportAction.append,
              );
        final payload = applyPlanToSection(sections[i], plan);
        if (payload == null) continue;
        await courseProvider.saveSectionJson(payload);
      }
      _step = TextbookImportStep.importDone;
      _recordRecent();
    } catch (e, st) {
      logger.e('TextbookImportProvider.importSections failed',
          error: e, stackTrace: st);
      _error = e.toString();
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  /// Strip a leading ```lang and trailing ``` so a fenced JSON blob decodes.
  String _stripCodeFences(String s) {
    if (s.startsWith('```')) {
      final firstNewline = s.indexOf('\n');
      if (firstNewline >= 0) s = s.substring(firstNewline + 1);
      if (s.endsWith('```')) {
        s = s.substring(0, s.length - 3);
      }
    }
    return s.trim();
  }

  /// Append a textbook-import task to the AI Hub's recent list.
  void _recordRecent() {
    try {
      getIt<AiRecentTasksProvider>().record(
            AiRecentTask(
              kind: AiTaskKind.textbook,
              summary: 'textbook',
              timestamp: DateTime.now(),
              route: TextbookImportRoute.name,
            ),
          );
    } catch (_) {
      // Advisory only.
    }
  }
}
