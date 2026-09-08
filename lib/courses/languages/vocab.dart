export 'package:turna/courses/languages/language_content_store.dart'
    show vocabById, vocabByTerm, vocabByTranslation;

import 'package:turna/courses/languages/language_content_store.dart';
import 'package:turna/domain/course/word_entry.dart';

/// Curated target-language vocabulary for the SRS word pool.
///
/// Words are bundled in `assets/courses/turkish/vocab.json` and loaded
/// asynchronously at app start by [CourseLoader.load]. The synchronous
/// lookups [vocabById] / [vocabByTranslation] are populated
/// as a side-effect of the first call to [loadVocabulary] and
/// remain valid for the rest of the session — renderers can use them
/// without awaiting any future. [vocabByTerm] is also populated for
/// target-language term lookups.
Future<List<WordEntry>> loadVocabulary([String? languageCode]) async {
  final store = languageCode == null
      ? await LanguageContentStore.activateDefault()
      : await LanguageContentStore.activate(languageCode);
  return store.vocabulary;
}