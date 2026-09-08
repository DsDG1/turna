import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show AssetBundle;

import 'package:turna/courses/language_manifest.dart';
import 'package:turna/domain/course/language_codes.dart';

/// Process-wide packed-language registry. The live source of display names
/// and TTS locales (it replaced the old single-language TargetLanguage
/// enum).
class LanguageRegistry {
  LanguageRegistry._();

  static LanguageRegistry instance = LanguageRegistry._();

  List<LanguageDescriptor> _languages = LanguageManifest.packedFallback;
  bool _loaded = false;

  List<LanguageDescriptor> get languages => List.unmodifiable(_languages);

  String get defaultCode =>
      _languages.isEmpty ? LanguageCodes.turkish : _languages.first.code;

  LanguageDescriptor get defaultLanguage => byCode(defaultCode);

  bool get isLoaded => _loaded;

  LanguageDescriptor byCode(String code) {
    final canonical = LanguageCodes.canonicalize(code);
    for (final language in _languages) {
      if (language.code == canonical) return language;
    }
    return LanguageDescriptor(
      code: canonical,
      displayName: canonical,
      ttsLocale: canonical,
      dir: LanguageCodes.packedDirs[canonical] ?? canonical,
    );
  }

  String displayName(String code) => byCode(code).displayName;

  /// The language's own name for itself ("Türkçe öğren"); falls back to
  /// [displayName] for synthesized descriptors.
  String nativeLabel(String code) => byCode(code).displayNativeLabel;

  String ttsLocale(String code) => byCode(code).ttsLocale;

  String ttsLanguageCode(String code) => byCode(code).ttsLanguageCode;

  String assetDir(String code) => byCode(code).dir;

  Future<void> load({AssetBundle? bundle}) async {
    _languages = await LanguageManifest.load(bundle: bundle);
    _loaded = true;
  }

  @visibleForTesting
  void replaceForTest(List<LanguageDescriptor> languages) {
    _languages = List.of(languages);
    _loaded = true;
  }

  @visibleForTesting
  void resetForTest() {
    _languages = LanguageManifest.packedFallback;
    _loaded = false;
  }
}
