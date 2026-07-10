// Project imports:
import 'package:varnamala/core/logger.dart';
import 'swahili_vocab.dart';

/// Look up the meaning of [word] in the Swahili vocabulary.
/// Single-language build: returns "--" if not found.
String getWordMeaning(String word) {
  logger.i("Dictionary lookup: $word");
  return swahiliVocabByTranslation[word.trim().toLowerCase()]?.translation ??
      "--";
}