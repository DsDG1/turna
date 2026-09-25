import 'package:turna/domain/course/language_codes.dart';

/// Typed course scope identity (plan 34 D1).
///
/// A course scope names exactly one selectable course: the built-in
/// language course, one Legacy Anki import, or one Official Anki source.
/// Business code must compare [CourseScope] values — never sniff string
/// prefixes — and string matching is allowed only inside [CourseScopeCodec]
/// and the one-time preference migrator.
sealed class CourseScope {
  const CourseScope();

  const factory CourseScope.builtin(String languageCode) = BuiltinCourseScope;
  const factory CourseScope.legacyAnki(String importId) = LegacyAnkiCourseScope;
  const factory CourseScope.officialAnki({
    required String profileId,
    required String sourceId,
  }) = OfficialAnkiCourseScope;

  /// Encodes to the versioned wire key via [CourseScopeCodec].
  String get wireKey => CourseScopeCodec.encode(this);
}

class BuiltinCourseScope extends CourseScope {
  const BuiltinCourseScope(this.languageCode);

  final String languageCode;

  String get canonicalLanguageCode => LanguageCodes.canonicalize(languageCode);

  @override
  bool operator ==(Object other) =>
      other is BuiltinCourseScope &&
      other.canonicalLanguageCode == canonicalLanguageCode;

  @override
  int get hashCode => Object.hash('builtin', canonicalLanguageCode);

  @override
  String toString() => 'BuiltinCourseScope($languageCode)';
}

class LegacyAnkiCourseScope extends CourseScope {
  const LegacyAnkiCourseScope(this.importId);

  final String importId;

  @override
  bool operator ==(Object other) =>
      other is LegacyAnkiCourseScope && other.importId == importId;

  @override
  int get hashCode => Object.hash('legacy', importId);

  @override
  String toString() => 'LegacyAnkiCourseScope($importId)';
}

class OfficialAnkiCourseScope extends CourseScope {
  const OfficialAnkiCourseScope(
      {required this.profileId, required this.sourceId});

  final String profileId;
  final String sourceId;

  @override
  bool operator ==(Object other) =>
      other is OfficialAnkiCourseScope &&
      other.profileId == profileId &&
      other.sourceId == sourceId;

  @override
  int get hashCode => Object.hash('official', profileId, sourceId);

  @override
  String toString() => 'OfficialAnkiCourseScope($profileId, $sourceId)';
}

/// Versioned, unambiguous codec for persisted course scopes (plan 34 D1).
///
/// Wire format:
/// ```text
/// course-scope:v1:builtin:<languageCode>
/// course-scope:v1:legacy:<importId>
/// course-scope:v1:official:<profileId>:<sourceId>
/// ```
/// Dynamic segments are percent-encoded, so ids containing `:` or other
/// delimiters round-trip safely.
///
/// Pre-cutover raw values (`''`, `anki:<id>`, bare language codes) are no
/// longer decoded — [decode] returns null for them and callers fall back to
/// a builtin course (plan P1; the one-shot preference migrator is retired).
class CourseScopeCodec {
  static const String prefix = 'course-scope:v1:';

  CourseScopeCodec._();

  static String encode(CourseScope scope) => switch (scope) {
        BuiltinCourseScope(languageCode: final code) =>
          '${prefix}builtin:${_encode(LanguageCodes.canonicalize(code))}',
        LegacyAnkiCourseScope(importId: final importId) =>
          '${prefix}legacy:${_encode(importId)}',
        OfficialAnkiCourseScope(
          profileId: final profileId,
          sourceId: final sourceId,
        ) =>
          '${prefix}official:${_encode(profileId)}:${_encode(sourceId)}',
      };

  /// Decodes a v1 wire key. Returns `null` for anything that is not a
  /// well-formed v1 key (legacy values included — those go through
  /// [decodeLegacy]).
  static CourseScope? decode(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith(prefix)) return null;
    final body = trimmed.substring(prefix.length);
    final separator = body.indexOf(':');
    if (separator < 0) {
      // Every v1 key carries a kind segment; a bare body is malformed.
      return null;
    }
    final kind = body.substring(0, separator);
    final rest = body.substring(separator + 1);
    switch (kind) {
      case 'builtin':
        return BuiltinCourseScope(LanguageCodes.canonicalize(_decode(rest)));
      case 'legacy':
        return LegacyAnkiCourseScope(_decode(rest));
      case 'official':
        final second = rest.indexOf(':');
        if (second < 0) return null;
        return OfficialAnkiCourseScope(
          profileId: _decode(rest.substring(0, second)),
          sourceId: _decode(rest.substring(second + 1)),
        );
      default:
        return null;
    }
  }

  /// A v1 wire key must be treated as opaque; this cheap check lets
  /// callers distinguish encoded keys from foreign values.
  static bool isEncodedKey(String raw) => raw.startsWith(prefix);

  static String _encode(String segment) => Uri.encodeComponent(segment);

  static String _decode(String segment) => Uri.decodeComponent(segment);
}
