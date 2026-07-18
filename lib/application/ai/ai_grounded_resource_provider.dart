// Dart imports:
import 'dart:convert';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Project imports:
import 'package:varnamala/data/course_database.dart' as db;
import 'package:varnamala/data/course_repository.dart';
import 'package:varnamala/di/injection.dart';

/// Loads existing course resources so the AI can be grounded to reuse them.
///
/// Mirrors the resource-pool grounding used by tool-gui's design panel.
class AiGroundedResourceProvider extends ChangeNotifier {
  AiGroundedResourceProvider({CourseRepository? repository})
      : _repository = repository ?? CourseRepository(getIt<db.CourseDatabase>());

  final CourseRepository _repository;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  List<Map<String, dynamic>> _words = [];
  List<Map<String, dynamic>> _expressions = [];
  List<Map<String, dynamic>> _grammarPoints = [];

  List<Map<String, dynamic>> get words {
    return List.unmodifiable(_words);
  }

  List<Map<String, dynamic>> get expressions {
    return List.unmodifiable(_expressions);
  }

  List<Map<String, dynamic>> get grammarPoints {
    return List.unmodifiable(_grammarPoints);
  }

  bool get hasResources =>
      _words.isNotEmpty || _expressions.isNotEmpty || _grammarPoints.isNotEmpty;

  /// Loads resources from the DB. Safe to call multiple times; it will refresh
  /// the cached snapshot.
  Future<void> load({List<String>? scope}) async {
    final requestedScope = scope ?? const ['words', 'expressions', 'grammarPoints'];
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      if (requestedScope.contains('words')) {
        final rows = await _repository.vocabulary();
        _words = [
          for (final w in rows)
            {
              'id': w.id,
              'term': w.term,
              'translation': w.translation,
              if (w.pronunciation != null) 'pronunciation': w.pronunciation,
              if (w.tags.isNotEmpty) 'tags': w.tags,
            },
        ];
      } else {
        _words = [];
      }

      if (requestedScope.contains('expressions')) {
        final rows = await _repository.expressions();
        _expressions = [
          for (final e in rows)
            {
              'id': e.id,
              'term': e.term,
              'translation': e.translation,
              if (e.pronunciation != null) 'pronunciation': e.pronunciation,
              if (e.tags.isNotEmpty) 'tags': e.tags,
            },
        ];
      } else {
        _expressions = [];
      }

      if (requestedScope.contains('grammarPoints')) {
        final rows = await _repository.grammarPoints();
        _grammarPoints = [
          for (final g in rows)
            {
              'id': g.id,
              'title': g.title,
              'explanation': g.explanation,
              if (g.exampleExpressionIds.isNotEmpty)
                'exampleExpressionIds': g.exampleExpressionIds,
              if (g.exampleSentenceIds.isNotEmpty)
                'exampleSentenceIds': g.exampleSentenceIds,
            },
        ];
      } else {
        _grammarPoints = [];
      }
    } catch (e) {
      _error = e.toString();
      _words = [];
      _expressions = [];
      _grammarPoints = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Formats the loaded resources as a JSON snippet suitable for appending to
  /// an AI prompt. Empty resources produce an empty string.
  String formatContext({int? maxResources}) {
    if (!hasResources) return '';
    final cap = maxResources ?? 200;
    final payload = <String, dynamic>{};
    if (_words.isNotEmpty) {
      payload['words'] = _words.take(cap).toList();
    }
    if (_expressions.isNotEmpty) {
      payload['expressions'] = _expressions.take(cap).toList();
    }
    if (_grammarPoints.isNotEmpty) {
      payload['grammarPoints'] = _grammarPoints.take(cap).toList();
    }
    return jsonEncode(payload);
  }

  /// Returns the IDs of all loaded resources. Useful for lesson-helper prompts
  /// that need to constrain references without sending full resource bodies.
  Set<String> get allResourceIds => {
    for (final w in _words) w['id']?.toString() ?? '',
    for (final e in _expressions) e['id']?.toString() ?? '',
    for (final g in _grammarPoints) g['id']?.toString() ?? '',
  }..remove('');
}
