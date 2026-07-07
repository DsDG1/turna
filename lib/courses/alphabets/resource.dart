// Project imports:
import 'package:words625/core/enums.dart';
import 'package:words625/courses/alphabets/alphabets.dart';

/// Kannada-only: helpers directly return the kannada map. The [TargetLanguage]
/// parameter is retained as a no-op so existing call sites continue to compile.
Map<String, String> getLanguageSounds(TargetLanguage _) => kannadaSounds;
Map<String, String> getLanguageVowels(TargetLanguage _) => kannadaVowels;
Map<String, String> getLanguageConsonants(TargetLanguage _) => kannadaConsonants;