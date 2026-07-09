// Project imports:
import 'package:words625/core/logger.dart';
import 'kannada_vocab.dart';

/// Look up the meaning of [word] in the Swahili vocabulary.
/// Single-language build: returns "--" if not found.
///
/// NOTE: The underlying lookup map currently holds Kannada vocabulary
/// while the Swahili word list is being prepared.
String getWordMeaning(String word) {
  logger.i("Dictionary lookup: $word");
  return swahiliVocabByTranslation[word.trim().toLowerCase()]?.translation ??
      "--";
}