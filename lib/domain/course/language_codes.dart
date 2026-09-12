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

  /// Azerbaijani shares Turkish's dotted/dotless-I casing rules (ASCII `I`
  /// lowercases to `ı`, `İ` to `i`). Packed courses never use it, but an
  /// imported pack may.
  static const String azerbaijani = 'az';

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

  /// Fold [text] into the lookup key used by the per-language term index
  /// (`vocabularyByTerm` / dictionary lookups). Must be applied on BOTH the
  /// index-build and the query side.
  ///
  /// `İ` (U+0130) is folded to `i` for every language: plain
  /// `toLowerCase()` turns it into `i` + combining dot (U+0307), a key no
  /// one can type, and no Latin-script language distinguishes `i̇` from
  /// `i` in a way that matters for lookup. The dotless rule — ASCII `I`
  /// folding to `ı` — applies to Turkish-style casing only: content
  /// spelled with a dotted `İ` or ASCII `I` folds to `i`/`ı`, matching
  /// what users of those languages type. Other languages use plain
  /// lowercase.
  static String lookupFoldKey(String text, String languageCode) {
    var s = text.trim();
    s = s.replaceAll('İ', 'i');
    final code = canonicalize(languageCode);
    if (code == turkish || code == azerbaijani) {
      s = s.replaceAll('I', 'ı');
    }
    return s.toLowerCase();
  }
}
