// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:http/http.dart' as http;

// Project imports:
import 'package:varnamala/application/ai/ai_api_config.dart';
import 'package:varnamala/application/ai/ai_course_provider.dart';
import 'package:varnamala/application/ai/ai_course_service.dart';
import 'package:varnamala/application/ai/textbook/knowledge_merger.dart';
import 'package:varnamala/application/ai/textbook/knowledge_prompt.dart';
import 'package:varnamala/application/ai/textbook/knowledge_schema.dart';
import 'package:varnamala/application/ai/textbook/markdown_chopper.dart';
import 'package:varnamala/application/ai/textbook/textbook_to_course.dart';
import 'package:varnamala/core/logger.dart';
import 'package:varnamala/data/course_database.dart' as db;
import 'package:varnamala/data/course_repository.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/utils/ohos_file_picker.dart';

/// Steps in the textbook import flow.
enum TextbookImportStep { pick, parse, chapters, extract, review, importDone }

/// Orchestrates the textbook import pipeline. Mirrors
/// `tool/gui/src/dialogs/textbook_import_controller.py`.
class TextbookImportProvider extends ChangeNotifier {
  TextbookImportProvider({
    http.Client? client,
    AiCourseService? service,
    CourseRepository? repository,
  })  : _service = service ?? AiCourseService(client: client),
        _repository = repository ?? CourseRepository(getIt<db.CourseDatabase>()),
        _chopper = const MarkdownChopper(),
        _merger = const KnowledgeMerger(),
        _builder = const TextbookToCourse();

  final AiCourseService _service;
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

  void updateSettings({
    String? language,
    String? sourceLanguage,
    String? level,
    ImportStrategy? strategy,
  }) {
    if (language != null) _language = language;
    if (sourceLanguage != null) _sourceLanguage = sourceLanguage;
    if (level != null) _level = level;
    if (strategy != null) _strategy = strategy;
    notifyListeners();
  }

  void reset() {
    _step = TextbookImportStep.pick;
    _filePath = null;
    _fileName = '';
    _error = null;
    _results = [];
    _isBusy = false;
    notifyListeners();
  }

  /// Picks a file and parses it into chapters.
  Future<void> pickFile() async {
    _error = null;
    final result = await OhosFilePicker.pickFiles(
      allowedExtensions: const ['md', 'txt'],
    );
    if (result == null || result.files.isEmpty) return;

    final path = result.files.single.path;
    if (path == null) {
      _error = 'Could not read file path';
      notifyListeners();
      return;
    }

    _filePath = path;
    _fileName = result.files.single.name;
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
  Future<void> extractAll(AiApiConfig config) async {
    _error = null;
    _isBusy = true;
    _step = TextbookImportStep.extract;
    notifyListeners();

    try {
      for (var i = 0; i < _results.length; i++) {
        final result = _results[i];
        if (!result.keep) continue;
        try {
          final knowledge = await _extractChapter(config, result.chapter);
          result.knowledge = knowledge;
          result.error = null;
        } catch (e) {
          result.error = e.toString();
          result.knowledge = null;
        }
        notifyListeners();
      }
      _step = TextbookImportStep.review;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }

  Future<KnowledgePoints> _extractChapter(
    AiApiConfig config,
    TextbookChapter chapter,
  ) async {
    final messages = KnowledgePrompt.buildExtractionMessages(
      language: _language,
      sourceLanguage: _sourceLanguage,
      chapterTitle: chapter.title,
      chapterMarkdown: chapter.markdown,
    );
    final raw = await _service.requestKnowledgeExtraction(
      config: config,
      messages: messages,
    );
    return coerceKnowledgePoints(raw);
  }

  /// Builds course sections from extracted knowledge and writes them to the DB.
  Future<void> importSections(AiCourseProvider courseProvider) async {
    _error = null;
    _isBusy = true;
    notifyListeners();

    if (_repository == null) {
      _error = 'CourseDatabase unavailable on this platform';
      _isBusy = false;
      notifyListeners();
      return;
    }

    try {
      final existingWords = (await _repository!.vocabulary()).map((w) => w.id).toSet();
      final existingExpressions =
          (await _repository!.expressions()).map((e) => e.id).toSet();
      final existingGrammar =
          (await _repository!.grammarPoints()).map((g) => g.id).toSet();

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

      for (final sectionJson in sections) {
        await courseProvider.saveSectionJson(sectionJson);
      }
      _step = TextbookImportStep.importDone;
    } catch (e, st) {
      logger.e('TextbookImportProvider.importSections failed', error: e, stackTrace: st);
      _error = e.toString();
    } finally {
      _isBusy = false;
      notifyListeners();
    }
  }
}
