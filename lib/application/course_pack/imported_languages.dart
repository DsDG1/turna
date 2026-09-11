import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:turna/courses/language_manifest.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/domain/course/language_codes.dart';

/// Overlay for languages imported from `.turnapack` (plan §5.3).
///
/// Packed [LanguageRegistry] descriptors stay the builtin truth; imported
/// courses persist displayName / TTS / signatureChars in `courseMeta` under
/// [metaKeyFor].
class ImportedLanguageRegistry {
  ImportedLanguageRegistry._();

  static final ImportedLanguageRegistry instance = ImportedLanguageRegistry._();

  static const String metaPrefix = 'importedLang';

  static String metaKeyFor(String languageCode) =>
      '$metaPrefix:${LanguageCodes.canonicalize(languageCode)}';

  final Map<String, Map<String, dynamic>> _byCode = {};

  void resetForTest() => _byCode.clear();

  bool contains(String languageCode) =>
      _byCode.containsKey(LanguageCodes.canonicalize(languageCode));

  Future<void> hydrate(CourseDatabase db) async {
    const prefix = '$metaPrefix:';
    final rows = await (db.select(db.courseMeta)
          ..where((t) => t.key.like('$prefix%')))
        .get();
    _byCode.clear();
    for (final row in rows) {
      final code = row.key.substring(prefix.length);
      try {
        final decoded = jsonDecode(row.value);
        if (decoded is Map<String, dynamic>) {
          _byCode[LanguageCodes.canonicalize(code)] = decoded;
        }
      } catch (_) {
        // Corrupt overlay rows degrade to the registry fallback.
      }
    }
  }

  void remember(String languageCode, Map<String, dynamic> descriptor) {
    _byCode[LanguageCodes.canonicalize(languageCode)] = Map.of(descriptor);
  }

  Map<String, dynamic>? rawOrNull(String languageCode) =>
      _byCode[LanguageCodes.canonicalize(languageCode)];

  String? displayNameOrNull(String languageCode) {
    final name = rawOrNull(languageCode)?['displayName'];
    if (name is String && name.trim().isNotEmpty) return name;
    return null;
  }

  String? nativeLabelOrNull(String languageCode) {
    final name = rawOrNull(languageCode)?['nativeLabel'];
    if (name is String && name.trim().isNotEmpty) return name;
    return null;
  }

  String? ttsLocaleOrNull(String languageCode) {
    final locale = rawOrNull(languageCode)?['ttsLocale'];
    if (locale is String && locale.trim().isNotEmpty) return locale;
    return null;
  }

  String? signatureCharsOrNull(String languageCode) {
    final chars = rawOrNull(languageCode)?['signatureChars'];
    if (chars is String && chars.isNotEmpty) return chars;
    return null;
  }

  String? licenseAttributionOrNull(String languageCode) {
    final license = rawOrNull(languageCode)?['license'];
    if (license is Map && license['attribution'] is String) {
      final text = (license['attribution'] as String).trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  LanguageDescriptor? descriptorOrNull(String languageCode) {
    final raw = rawOrNull(languageCode);
    if (raw == null) return null;
    final code = LanguageCodes.canonicalize(languageCode);
    return LanguageDescriptor(
      code: code,
      displayName: displayNameOrNull(code) ?? code,
      ttsLocale: ttsLocaleOrNull(code) ?? code,
      dir: code,
      nativeLabel: nativeLabelOrNull(code),
      signatureChars: signatureCharsOrNull(code),
    );
  }
}
