/// Canonical builtin language codes stored on course rows and [BuiltinCourseScope].
///
/// Historical prefs / wires used `turkish` (the retired TargetLanguage enum
/// name). Packed course trees and `index.json` use ISO-ish codes (`tr`,
/// `fr`).
class LanguageCodes {
  LanguageCodes._();

  static const String turkish = 'tr';

  /// 法语课程是多语言并存机制的验收 fixture，不是正式课程，不在开发
  /// 计划内（见 pubspec.yaml 的资产注释）。
  static const String french = 'fr';

  /// Packed-asset directory for a canonical code when the manifest is not
  /// loaded yet. Manifest [dir] wins at runtime.
  static const Map<String, String> packedDirs = {
    turkish: 'turkish',
    french: 'french',
  };

  static String canonicalize(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return turkish;
    switch (trimmed) {
      case 'turkish':
      case 'tr-TR':
      case 'tr_TR':
      case 'TR':
      case 'tr':
        return turkish;
      case 'french':
      case 'fr-FR':
      case 'fr_FR':
      case 'FR':
      case 'fr':
        return french;
      default:
        return trimmed;
    }
  }
}
