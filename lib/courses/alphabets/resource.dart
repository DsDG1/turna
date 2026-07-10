// Project imports:
import 'package:varnamala/core/enums.dart';
import 'package:varnamala/courses/alphabets/alphabets.dart';

/// Swahili-only: helpers return the Swahili alphabet map. The [TargetLanguage]
/// parameter is retained as a no-op so existing call sites continue to compile.
Map<String, String> getLanguageSounds(TargetLanguage _) => swahiliSounds;
Map<String, String> getLanguageVowels(TargetLanguage _) => swahiliVowels;
Map<String, String> getLanguageConsonants(TargetLanguage _) => swahiliConsonants;