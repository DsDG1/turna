import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:turna/application/language_registry.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/domain/course/expression.dart';
import 'package:turna/domain/course/grammar_point.dart';
import 'package:turna/domain/course/language_codes.dart';
import 'package:turna/domain/course/word_entry.dart';

/// Compatibility view of the active language (renderers read these maps).
final Map<String, WordEntry> vocabById = <String, WordEntry>{};
final Map<String, WordEntry> vocabByTerm = <String, WordEntry>{};
final Map<String, WordEntry> vocabByTranslation = <String, WordEntry>{};
final Map<String, GrammarPoint> grammarPointById = <String, GrammarPoint>{};
final Map<String, Expression> expressionsById = <String, Expression>{};

/// Per-language vocabulary / grammar / expression lookups.
///
/// Replaces the process-global maps as the source of truth. The global maps
/// remain a compatibility view of the [active] language so renderers that
/// read them synchronously stay correct after a scope switch.
class LanguageContentStore {
  LanguageContentStore(this.languageCode);

  final String languageCode;

  List<WordEntry> vocabulary = const [];
  Map<String, WordEntry> vocabularyById = const {};
  Map<String, WordEntry> vocabularyByTerm = const {};
  Map<String, WordEntry> vocabularyByTranslation = const {};
  List<GrammarPoint> grammarPoints = const [];
  Map<String, GrammarPoint> grammarIndex = const {};
  List<Expression> expressions = const [];
  Map<String, Expression> expressionIndex = const {};

  bool _loaded = false;
  Future<void>? _inFlight;

  bool get isLoaded => _loaded;

  static final Map<String, LanguageContentStore> _cache = {};
  static String _activeCode = LanguageCodes.turkish;

  static String get activeCode => _activeCode;

  static LanguageContentStore of(String languageCode) {
    final code = LanguageCodes.canonicalize(languageCode);
    return _cache.putIfAbsent(code, () => LanguageContentStore(code));
  }

  static LanguageContentStore get active => of(_activeCode);

  static Future<LanguageContentStore> activate(String languageCode) async {
    final code = LanguageCodes.canonicalize(languageCode);
    final store = of(code);
    // Load before switching _activeCode: on failure the active language (and
    // the published globals) keep pointing at the previous, working store.
    await store.ensureLoaded();
    _activeCode = code;
    store.publishGlobals();
    return store;
  }

  static Future<LanguageContentStore> activateDefault() {
    return activate(LanguageRegistry.instance.defaultCode);
  }

  static void drop(String languageCode) {
    final code = LanguageCodes.canonicalize(languageCode);
    _cache.remove(code);
    if (_activeCode == code) {
      vocabById.clear();
      vocabByTerm.clear();
      vocabByTranslation.clear();
      grammarPointById.clear();
      expressionsById.clear();
    }
  }

  @visibleForTesting
  static void resetForTest() {
    _cache.clear();
    _activeCode = LanguageCodes.turkish;
    vocabById.clear();
    vocabByTerm.clear();
    vocabByTranslation.clear();
    grammarPointById.clear();
    expressionsById.clear();
  }

  Future<void> ensureLoaded() {
    if (_loaded) return Future.value();
    // Clear the in-flight slot on completion (success OR failure) so a
    // failed load can be retried instead of caching the error forever.
    return _inFlight ??= _load().whenComplete(() => _inFlight = null);
  }

  Future<void> _load() async {
    final course = await CourseLoader.load(languageCode);
    vocabulary = course.vocabulary;
    vocabularyById = Map<String, WordEntry>.from(course.vocabularyById);
    vocabularyByTerm = Map<String, WordEntry>.from(course.vocabularyByTerm);
    vocabularyByTranslation =
        Map<String, WordEntry>.from(course.vocabularyByTranslation);
    grammarPoints = course.grammarPoints;
    grammarIndex = Map<String, GrammarPoint>.from(course.grammarPointsById);
    expressions = course.expressions;
    expressionIndex = Map<String, Expression>.from(course.expressionsById);
    _loaded = true;
  }

  /// Copy this store into the process-global lookup maps.
  void publishGlobals() {
    vocabById
      ..clear()
      ..addAll(vocabularyById);
    vocabByTerm
      ..clear()
      ..addAll(vocabularyByTerm);
    vocabByTranslation
      ..clear()
      ..addAll(vocabularyByTranslation);
    grammarPointById
      ..clear()
      ..addAll(grammarIndex);
    expressionsById
      ..clear()
      ..addAll(expressionIndex);
  }

  WordEntry? wordById(String id) => vocabularyById[id];

  GrammarPoint? grammarById(String id) => grammarIndex[id];

  Expression? expressionById(String id) => expressionIndex[id];
}
