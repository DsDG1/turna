// Project imports:
import 'package:words625/core/enums.dart';
import 'package:words625/courses/alphabets/alphabets.dart';

/// Swahili-only: helpers directly return the kannada map. The [TargetLanguage]
/// parameter is retained as a no-op so existing call sites continue to compile.
///
/// NOTE: The returned alphabet maps currently contain Kannada script while
/// the Swahili alphabet assets are being prepared.
Map<String, String> getLanguageSounds(TargetLanguage _) => kannadaSounds;
Map<String, String> getLanguageVowels(TargetLanguage _) => kannadaVowels;
Map<String, String> getLanguageConsonants(TargetLanguage _) => kannadaConsonants;