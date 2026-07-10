// Project imports:
import 'package:varnamala/courses/course_loader.dart';
import 'package:varnamala/domain/course/word_entry.dart';

/// Curated Swahili vocabulary for the SRS word pool.
///
/// Words are bundled in `assets/courses/swahili/vocab.json` and loaded
/// asynchronously at app start by [SwahiliCourse.load]. The synchronous
/// lookups [swahiliVocabById] / [swahiliVocabByTranslation] are populated
/// as a side-effect of the first call to [loadSwahiliVocabulary] and
/// remain valid for the rest of the session — renderers can use them
/// without awaiting any future.
Future<List<WordEntry>> loadSwahiliVocabulary() async {
  final course = await SwahiliCourse.load();
  // Backfill the synchronous lookups on first call. Subsequent calls
  // are cheap (the map is already populated) but always refresh the
  // values to keep the lazy map and the in-memory list in sync.
  _populateLookups(course);
  return course.vocabulary;
}

void _populateLookups(SwahiliCourse course) {
  swahiliVocabById
    ..clear()
    ..addAll(course.vocabularyById);
  swahiliVocabByTranslation
    ..clear()
    ..addAll(course.vocabularyByTranslation);
}

/// Synchronous lookup-by-id map, populated on first
/// [loadSwahiliVocabulary] call. Read by renderers that don't have
/// access to an async context (e.g. inside `build()`).
final Map<String, WordEntry> swahiliVocabById = <String, WordEntry>{};

/// Synchronous lookup-by-translation map, case-insensitive. Populated
/// on first [loadSwahiliVocabulary] call.
final Map<String, WordEntry> swahiliVocabByTranslation =
    <String, WordEntry>{};
