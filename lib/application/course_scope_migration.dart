import 'package:turna/application/course_catalog.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/course_scope.dart';
import 'package:turna/service/locator.dart';

/// Result of a one-shot courseScope / courseOrder preference repair.
class CourseScopeRepairResult {
  const CourseScopeRepairResult({
    required this.oldScopeWire,
    required this.newScopeWire,
    required this.oldOrderWire,
    required this.newOrderWire,
    required this.reason,
  });

  final String oldScopeWire;
  final String newScopeWire;
  final String oldOrderWire;
  final String newOrderWire;
  final String reason;

  bool get changedScope => oldScopeWire != newScopeWire;
  bool get changedOrder => oldOrderWire != newOrderWire;
}

/// Idempotent migrator from legacy persisted scope strings to the v1 codec
/// (plan 34 §6.4 / R1-6).
///
/// Startup order contract: this runs AFTER the CourseDatabase is open and
/// the source catalog is readable, and BEFORE CourseProvider consumes the
/// preference. Broken `anki:src` truncations are repaired against the real
/// catalog — single Official source resolves to it; multiple sources fall
/// back to builtin (never pick the first). Nothing here deletes Official
/// collections, projections or study records.
class CourseScopePreferenceMigrator {
  CourseScopePreferenceMigrator._();

  /// Repairs the persisted [PrefsConstants.courseScope] and
  /// [PrefsConstants.courseOrder]. Safe to run on every startup: encoded
  /// values pass through unchanged and repairs land in
  /// `course_scope_repair_journal` exactly once per change.
  static Future<CourseScopeRepairResult?> repair({
    String currentLanguageCode = 'turkish',
    CourseDatabase? courseDb,
  }) async {
    final prefs = _prefsOrNull();
    if (prefs == null) return null;
    CourseDatabase? db = courseDb;
    try {
      db ??= CourseLoader.databaseOrNull();
    } catch (_) {
      db = null;
    }
    if (db == null) return null;

    final catalog = await CourseCatalog.load(courseDb: db);
    final officialSourceIds = {
      for (final entry in catalog)
        if (entry.officialSourceId != null) entry.officialSourceId!,
    };
    final legacyImportIds = {
      for (final entry in catalog)
        if (entry.legacyImportId != null) entry.legacyImportId!,
    };

    final rawScope = prefs.preferences
        .getString(PrefsConstants.courseScope, defaultValue: '')
        .getValue();
    final (resolution, scope) = CourseScopeCodec.decodeLegacy(
      rawScope,
      currentLanguageCode: currentLanguageCode,
      resolveLegacyImport: legacyImportIds.contains,
      resolveOfficialSource: officialSourceIds.contains,
    );

    CourseScope effective;
    String reason;
    switch (resolution) {
      case LegacyScopeResolution.alreadyEncoded:
        if (scope != null) {
          // Already migrated; still validate the target still exists.
          if (_scopeExists(scope, catalog)) {
            return null;
          }
          effective = BuiltinCourseScope(currentLanguageCode);
          reason = 'encoded-scope-target-missing';
        } else {
          effective = BuiltinCourseScope(currentLanguageCode);
          reason = 'malformed-encoded-scope';
        }
      case LegacyScopeResolution.resolved:
        effective = scope!;
        reason = 'legacy-string-migrated';
      case LegacyScopeResolution.ambiguousOrUnknown:
        // `anki:src` truncation or deleted source. With exactly one
        // Official source we may re-bind to it; with more we must not
        // guess (plan 34 R1-6).
        final raw = rawScope.trim();
        final truncatedAnki = raw == 'anki:src' || raw == 'anki:';
        if (truncatedAnki && officialSourceIds.length == 1) {
          effective = OfficialAnkiCourseScope(
            profileId: CourseCatalog.officialProfileId,
            sourceId: officialSourceIds.single,
          );
          reason = 'truncated-scope-rebound-single-official';
        } else {
          effective = BuiltinCourseScope(currentLanguageCode);
          reason = truncatedAnki
              ? 'truncated-scope-ambiguous-fallback-builtin'
              : 'unknown-scope-fallback-builtin';
        }
    }

    final newScopeWire = CourseScopeCodec.encode(effective);
    var changedScope = rawScope != newScopeWire;
    if (changedScope) {
      await prefs.setString(PrefsConstants.courseScope, newScopeWire);
    }

    // --- courseOrder repair: rebuild truncated/dead entries from the
    // catalog, preserving the valid prefix order.
    final storedOrder = prefs.preferences.getStringList(
        PrefsConstants.courseOrder,
        defaultValue: const []).getValue();
    // Map legacy order entries onto v1 wires.
    final wireByLegacyKey = <String, String>{};
    for (final entry in catalog) {
      switch (entry.scope) {
        case BuiltinCourseScope():
          wireByLegacyKey[''] = entry.wireKey;
        case LegacyAnkiCourseScope(importId: final id):
          wireByLegacyKey['anki:$id'] = entry.wireKey;
        case OfficialAnkiCourseScope(sourceId: final id):
          wireByLegacyKey['anki:$id'] = entry.wireKey;
      }
    }
    final rebuilt = <String>[];
    final seen = <String>{};
    for (final stored in storedOrder) {
      final mapped = CourseScopeCodec.isEncodedKey(stored)
          ? stored
          : wireByLegacyKey[stored];
      if (mapped == null) continue;
      if (!seen.add(mapped)) continue;
      rebuilt.add(mapped);
    }
    // Append catalog entries missing from the stored order.
    for (final entry in catalog) {
      if (seen.add(entry.wireKey)) rebuilt.add(entry.wireKey);
    }
    final newOrderWire = rebuilt.join('\u0000');
    final oldOrderWire = storedOrder.join('\u0000');
    final changedOrder = oldOrderWire != newOrderWire;
    if (changedOrder) {
      await prefs.setStringList(PrefsConstants.courseOrder, rebuilt);
    }

    if (!changedScope && !changedOrder) return null;

    final result = CourseScopeRepairResult(
      oldScopeWire: rawScope,
      newScopeWire: newScopeWire,
      oldOrderWire: oldOrderWire,
      newOrderWire: newOrderWire,
      reason: reason,
    );
    logger.i(
      'CourseScopePreferenceMigrator: repaired scope '
      '"${result.oldScopeWire}" → "${result.newScopeWire}" (${result.reason})',
    );
    return result;
  }

  static bool _scopeExists(
      CourseScope scope, List<CourseCatalogEntry> catalog) {
    return catalog.any((entry) => entry.scope == scope);
  }

  static AppPrefs? _prefsOrNull() {
    try {
      return getIt<AppPrefs>();
    } catch (_) {
      return null;
    }
  }
}
