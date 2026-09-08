export 'package:turna/courses/languages/language_content_store.dart'
    show grammarPointById;

import 'package:turna/courses/languages/language_content_store.dart';
import 'package:turna/domain/course/grammar_point.dart';

/// Grammar points for the grammar-review SRS queue.
///
/// Grammar points are bundled in `assets/courses/turkish/grammar_points.json`,
/// seeded into the local SQLite DB, and loaded asynchronously at app start by
/// [CourseLoader.load]. The synchronous lookup [grammarPointById] is
/// populated as a side-effect of the first call to [loadGrammarPoints]
/// and remains valid for the rest of the session — the grammar review screen
/// can use it without awaiting any future.
Future<List<GrammarPoint>> loadGrammarPoints([String? languageCode]) async {
  final store = languageCode == null
      ? LanguageContentStore.active
      : LanguageContentStore.of(languageCode);
  await store.ensureLoaded();
  if (languageCode == null ||
      languageCode == LanguageContentStore.activeCode) {
    store.publishGlobals();
  }
  return store.grammarPoints;
}