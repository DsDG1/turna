// Project imports:
import 'package:turna/core/enums.dart';
import 'package:turna/courses/alphabets/alphabets.dart';

/// Single-language build: helpers return the alphabet map. The
/// [TargetLanguage] parameter is retained as a no-op so existing call sites
/// continue to compile.
Map<String, String> getLanguageSounds(TargetLanguage _) => alphabetSounds;
Map<String, String> getLanguageVowels(TargetLanguage _) => alphabetVowels;
Map<String, String> getLanguageConsonants(TargetLanguage _) => alphabetConsonants;