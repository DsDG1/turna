// Project imports:
import 'package:turna/application/course_pack/imported_languages.dart';
import 'package:turna/application/language_registry.dart';
import 'package:turna/domain/course/course_scope.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/language_codes.dart';

/// Resolved target-language context for AI companion and generation surfaces.
///
/// When [isGeneric] is `true` ([displayName] is `null`), the AI surface must
/// NOT assume Turkish or any preset course language — instead it instructs the
/// model to infer the language or subject domain from the card/question text
/// itself (the generic mode for imported memory-card decks).
class AiTargetLanguage {
  const AiTargetLanguage._({
    required this.code,
    required this.displayName,
  });

  const AiTargetLanguage.named({
    required String code,
    required String displayName,
  }) : this._(code: code, displayName: displayName);

  const AiTargetLanguage.generic() : this._(code: null, displayName: null);

  /// Canonical language code (e.g. `tr`, `fr`), or `null` in generic mode.
  final String? code;

  /// Human/model-facing language name (e.g. `Turkish`, `Japanese`), or `null`
  /// in generic mode.
  final String? displayName;

  bool get isGeneric => displayName == null || displayName!.trim().isEmpty;

  @override
  bool operator ==(Object other) =>
      other is AiTargetLanguage &&
      other.code == code &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(code, displayName);

  @override
  String toString() => isGeneric
      ? 'AiTargetLanguage.generic()'
      : 'AiTargetLanguage($code: $displayName)';
}

/// Single source of truth for mapping the active course / lesson / card onto
/// an [AiTargetLanguage].
///
/// Prevents non-language scopes (such as imported memory-card decks under
/// [OfficialAnkiCourseScope] or card interactions inside a deck lesson) from
/// silently falling back to [LanguageRegistry.defaultCode] (Turkish).
abstract final class AiTargetLanguageResolver {
  /// Sentinel code persisted on custom AI courses that target generic /
  /// auto-detected content rather than one fixed language.
  static const String genericCode = 'generic';

  /// Resolve from the active [CourseScope].
  static AiTargetLanguage fromCourseScope(CourseScope scope) {
    return switch (scope) {
      BuiltinCourseScope(languageCode: final code) => fromLanguageCode(code),
      OfficialAnkiCourseScope() => const AiTargetLanguage.generic(),
    };
  }

  /// Resolve for an in-lesson interaction.
  ///
  /// Any deck-card scope, deck-card interaction ([AnkiCard] / [AnkiHtmlCard]),
  /// or card owned by an imported deck returns [AiTargetLanguage.generic] so
  /// deck lessons never get explained as Turkish.
  static AiTargetLanguage forLessonInteraction({
    required CourseScope scope,
    required Interaction interaction,
    bool isAnkiOwned = false,
  }) {
    if (scope is OfficialAnkiCourseScope) {
      return const AiTargetLanguage.generic();
    }
    if (isAnkiOwned || interaction is AnkiCard || interaction is AnkiHtmlCard) {
      return const AiTargetLanguage.generic();
    }
    return fromCourseScope(scope);
  }

  /// Resolve from a stored language code or free-form language label.
  ///
  /// Empty strings and [genericCode] resolve to [AiTargetLanguage.generic].
  static AiTargetLanguage fromLanguageCode(String? rawCode,
      {String? fallbackDisplayName}) {
    final trimmed = rawCode?.trim() ?? '';
    if (trimmed.isEmpty || trimmed.toLowerCase() == genericCode) {
      final fallback = fallbackDisplayName?.trim() ?? '';
      if (fallback.isNotEmpty && fallback.toLowerCase() != genericCode) {
        return AiTargetLanguage.named(code: fallback, displayName: fallback);
      }
      return const AiTargetLanguage.generic();
    }
    final canonical = LanguageCodes.canonicalize(trimmed);
    final imported =
        ImportedLanguageRegistry.instance.displayNameOrNull(canonical);
    if (imported != null && imported.trim().isNotEmpty) {
      return AiTargetLanguage.named(code: canonical, displayName: imported);
    }
    final registered = LanguageRegistry.instance.byCode(canonical);
    final display = registered.displayName.trim();
    if (display.isNotEmpty && display != canonical) {
      return AiTargetLanguage.named(code: canonical, displayName: display);
    }
    final fallback = fallbackDisplayName?.trim() ?? '';
    if (fallback.isNotEmpty) {
      return AiTargetLanguage.named(code: canonical, displayName: fallback);
    }
    return AiTargetLanguage.named(code: canonical, displayName: trimmed);
  }
}
