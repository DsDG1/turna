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

  String get canonicalLanguageCode =>
      LanguageCodes.canonicalize(languageCode);

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

/// Outcome of resolving a legacy persisted scope value against the source
/// catalog. Ambiguous values (one key matching both a Legacy import and an
/// Official source) must fall back to builtin — never guess by shape.
enum LegacyScopeResolution {
  /// Value maps to exactly one known source.
  resolved,

  /// Old broken `anki:src` truncation or an unknown id: repair path.
  ambiguousOrUnknown,

  /// The stored key already used the v1 codec.
  alreadyEncoded,
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

  /// A v1 wire key must be treated as opaque; this cheap check lets the
  /// preference migrator distinguish encoded keys from legacy values.
  static bool isEncodedKey(String raw) => raw.startsWith(prefix);

  /// Parses legacy persisted values (plan 34 D1):
  /// - `''` → the current builtin language
  /// - `anki:<importId>` → Legacy import when the id resolves to one
  /// - `anki:<fullOfficialSourceId>` → Official source when it resolves
  /// - `anki:src` (truncated) or unknown ids → ambiguous, caller repairs
  ///
  /// [resolveLegacyImport] / [resolveOfficialSource] receive the raw id and
  /// return whether exactly one source of that kind owns it. When both
  /// return true the value is ambiguous by definition.
  static (LegacyScopeResolution, CourseScope?) decodeLegacy(
    String raw, {
    required String currentLanguageCode,
    required bool Function(String importId) resolveLegacyImport,
    required bool Function(String sourceId) resolveOfficialSource,
  }) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return (
        LegacyScopeResolution.resolved,
        BuiltinCourseScope(LanguageCodes.canonicalize(currentLanguageCode))
      );
    }
    if (isEncodedKey(trimmed)) {
      return (LegacyScopeResolution.alreadyEncoded, decode(trimmed));
    }
    const ankiPrefix = 'anki:';
    if (!trimmed.startsWith(ankiPrefix)) {
      // Unknown shape: treat as builtin language code (older builds stored
      // bare language ids before the anki: scheme existed).
      return (
        LegacyScopeResolution.resolved,
        BuiltinCourseScope(LanguageCodes.canonicalize(trimmed)),
      );
    }
    final id = trimmed.substring(ankiPrefix.length);
    if (id.isEmpty) {
      return (LegacyScopeResolution.ambiguousOrUnknown, null);
    }
    final legacyHit = resolveLegacyImport(id);
    final officialHit = resolveOfficialSource(id);
    if (legacyHit && officialHit) {
      // Never guess the owner by string shape (plan 34 D1).
      return (LegacyScopeResolution.ambiguousOrUnknown, null);
    }
    if (legacyHit) {
      return (
        LegacyScopeResolution.resolved,
        LegacyAnkiCourseScope(id),
      );
    }
    if (officialHit) {
      return (
        LegacyScopeResolution.resolved,
        OfficialAnkiCourseScope(
          profileId: 'default',
          sourceId: id,
        ),
      );
    }
    // `anki:src` truncations and deleted imports land here.
    return (LegacyScopeResolution.ambiguousOrUnknown, null);
  }

  static String _encode(String segment) => Uri.encodeComponent(segment);

  static String _decode(String segment) => Uri.decodeComponent(segment);
}
