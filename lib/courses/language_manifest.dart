import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

import 'package:turna/domain/course/language_codes.dart';

/// One packed builtin language as declared in `assets/courses/manifest.json`.
class LanguageDescriptor {
  const LanguageDescriptor({
    required this.code,
    required this.displayName,
    required this.ttsLocale,
    required this.dir,
    this.nativeLabel,
    this.signatureChars,
  });

  /// Canonical language code (`tr`, `fr`, …).
  final String code;
  final String displayName;

  /// Preferred TTS locale (`tr-TR`, `fr-FR`).
  final String ttsLocale;

  /// Directory under `assets/courses/`.
  final String dir;

  /// How the language names itself ("Türkçe öğren", "Apprendre le
  /// français") for splash copy; falls back to [displayName].
  final String? nativeLabel;

  /// Letters that mark this language in Latin-script text (`ğĞıİşŞ` for tr,
  /// `àâæçéèêëîïôœùûüÿ…` for fr). Consumed by `LanguageDetector` to pick a
  /// TTS voice: text containing one of these is definitely the target
  /// language. `null` = no signature (Latin-only detection).
  final String? signatureChars;

  String get displayNativeLabel => nativeLabel ?? displayName;

  String get assetBaseDir => 'assets/courses/$dir';

  /// Base BCP-47 language subtag for TTS (`tr` from `tr-TR`).
  String get ttsLanguageCode {
    final normalized = ttsLocale.replaceAll('_', '-');
    final dash = normalized.indexOf('-');
    if (dash <= 0) return normalized.toLowerCase();
    return normalized.substring(0, dash).toLowerCase();
  }

  factory LanguageDescriptor.fromJson(Map<String, dynamic> json) {
    final code = LanguageCodes.canonicalize('${json['code'] ?? ''}');
    return LanguageDescriptor(
      code: code,
      displayName: '${json['displayName'] ?? code}',
      ttsLocale: '${json['ttsLocale'] ?? code}',
      dir: '${json['dir'] ?? LanguageCodes.packedDirs[code] ?? code}',
      nativeLabel: json['nativeLabel'] == null
          ? null
          : '${json['nativeLabel']}',
      signatureChars: json['signatureChars'] == null
          ? null
          : '${json['signatureChars']}',
    );
  }
}

/// Loads the packed language list. [rootBundle] cannot enumerate directories,
/// so the manifest is required rather than optional.
class LanguageManifest {
  LanguageManifest._();

  static const String assetPath = 'assets/courses/manifest.json';

  /// Fallback list matching the packed manifest. 法语条目是多语言并存
  /// 机制的验收 fixture，不是正式课程，不在开发计划内。
  static const List<LanguageDescriptor> packedFallback = [
    LanguageDescriptor(
      code: LanguageCodes.turkish,
      displayName: 'Turkish',
      ttsLocale: 'tr-TR',
      dir: 'turkish',
      nativeLabel: 'Türkçe öğren',
      signatureChars: 'ğĞıİşŞ',
    ),
    LanguageDescriptor(
      code: LanguageCodes.french,
      displayName: 'French',
      ttsLocale: 'fr-FR',
      dir: 'french',
      nativeLabel: 'Apprendre le français',
      signatureChars: 'àâæçéèêëîïôœùûüÿÀÂÆÇÉÈÊËÎÏÔŒÙÛÜŸ',
    ),
  ];

  @visibleForTesting
  static AssetBundle? debugBundle;

  static Future<List<LanguageDescriptor>> load({AssetBundle? bundle}) async {
    final source = bundle ?? debugBundle ?? rootBundle;
    try {
      final raw = await source.loadString(assetPath);
      final decoded = jsonDecode(raw);
      final list = decoded is Map<String, dynamic>
          ? decoded['languages']
          : decoded;
      if (list is! List) return packedFallback;
      final parsed = <LanguageDescriptor>[
        for (final item in list)
          if (item is Map<String, dynamic>) LanguageDescriptor.fromJson(item),
      ];
      return parsed.isEmpty ? packedFallback : parsed;
    } catch (_) {
      return packedFallback;
    }
  }
}
