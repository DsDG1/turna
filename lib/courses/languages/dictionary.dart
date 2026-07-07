// Project imports:
import 'package:words625/core/logger.dart';
import 'kannada_vocab.dart';

/// Look up the meaning of [word] in the Kannada vocabulary.
/// Single-language build: returns "--" if not found.
String getWordMeaning(String word) {
  logger.i("Dictionary lookup: $word");
  return kannadaVocabByTranslation[word.trim().toLowerCase()]?.translation ??
      "--";
}