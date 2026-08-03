// Project imports:
import 'package:turna/core/logger.dart';
import 'vocab.dart';

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

  final byTerm = vocabByTerm[key];
  if (byTerm != null) return byTerm.translation;

  final byTranslation = vocabByTranslation[key];
  if (byTranslation != null) return byTranslation.term;

  return "--";
}