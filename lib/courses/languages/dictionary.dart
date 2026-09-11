// Project imports:
import 'package:turna/core/logger.dart';
import 'package:turna/courses/languages/language_content_store.dart';
import 'package:turna/domain/course/language_codes.dart';

/// Look up the meaning of [word] in the target-language vocabulary.
///
/// Supports bidirectional lookup:
/// - Target-language term → English translation.
/// - English translation → target-language term.
///
/// Returns "--" if not found.
String getWordMeaning(String word) {
  final key = word.trim().toLowerCase();
  logger.i("Dictionary lookup: $word");
  if (key.isEmpty) return "--";

  // Term keys are folded with the language-aware rule used when the index
  // was built (Turkish İ/I handling); translation keys are plain lowercase.
  final termKey =
      LanguageCodes.lookupFoldKey(word, LanguageContentStore.activeCode);
  final byTerm = vocabByTerm[termKey];
  if (byTerm != null) return byTerm.translation;

  final byTranslation = vocabByTranslation[key];
  if (byTranslation != null) return byTranslation.term;

  return "--";
}