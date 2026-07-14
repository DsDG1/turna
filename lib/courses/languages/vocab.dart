// Project imports:
import 'package:varnamala/courses/course_loader.dart';
import 'package:varnamala/domain/course/word_entry.dart';

/// Curated target-language vocabulary for the SRS word pool.
///
/// Words are bundled in `assets/courses/turkish/vocab.json` and loaded
/// asynchronously at app start by [CourseLoader.load]. The synchronous
/// lookups [vocabById] / [vocabByTranslation] are populated
/// as a side-effect of the first call to [loadVocabulary] and
/// remain valid for the rest of the session — renderers can use them
/// without awaiting any future. [vocabByTerm] is also populated for
/// target-language term lookups.
Future<List<WordEntry>> loadVocabulary() async {
  final course = await CourseLoader.load();
  // Backfill the synchronous lookups on first call. Subsequent calls
  // are cheap (the map is already populated) but always refresh the
  // values to keep the lazy map and the in-memory list in sync.
  _populateLookups(course);
  return course.vocabulary;
}

void _populateLookups(CourseLoader course) {
  vocabById
    ..clear()
    ..addAll(course.vocabularyById);
  vocabByTerm
    ..clear()
    ..addAll(course.vocabularyByTerm);
  vocabByTranslation
    ..clear()
    ..addAll(course.vocabularyByTranslation);
}

/// Synchronous lookup-by-id map, populated on first
/// [loadVocabulary] call. Read by renderers that don't have
/// access to an async context (e.g. inside `build()`).
final Map<String, WordEntry> vocabById = <String, WordEntry>{};

/// Synchronous lookup-by-term map, case-insensitive. Populated
/// on first [loadVocabulary] call.
final Map<String, WordEntry> vocabByTerm = <String, WordEntry>{};

/// Synchronous lookup-by-translation map, case-insensitive. Populated
/// on first [loadVocabulary] call.
final Map<String, WordEntry> vocabByTranslation =
    <String, WordEntry>{};