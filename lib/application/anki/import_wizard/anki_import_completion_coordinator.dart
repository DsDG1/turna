import 'package:turna/application/anki/import_wizard/anki_import_wizard_state.dart';
import 'package:turna/application/anki/import_wizard/anki_import_dependencies.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/courses/course_loader.dart';

/// Shared post-commit work for BOTH flows (maintainability plan §10.6):
/// cache invalidation, course reload and course-order persistence. "完成"
/// never switches the active course — that stays a page-level intent
/// ("立即学习") — so this coordinator only refreshes data.
class AnkiImportCompletionCoordinator {
  const AnkiImportCompletionCoordinator();

  /// Returns the wire key of the freshly imported course when a new
  /// catalog entry appeared (and was appended to the course order).
  Future<String?> complete({
    required CourseProvider courseProvider,
    required String importId,
    required AnkiImportSummary summary,
  }) async {
    CourseLoader.invalidateCaches();
    // Refresh the catalog and stay on the user's current course — the
    // import must never steal the active scope (plan 34 R1-4).
    await courseProvider.reloadCourse();
    final newWire = _wireForImportId(importId, courseProvider);
    if (newWire != null) {
      final wires = [
        for (final entry in courseProvider.catalogEntries) entry.wireKey,
      ];
      if (!wires.contains(newWire)) {
        wires.add(newWire);
        await courseProvider.persistCourseOrder(wires);
      }
    }
    return newWire;
  }

  String? _wireForImportId(String id, CourseProvider courseProvider) {
    for (final entry in courseProvider.catalogEntries) {
      if (entry.legacyImportId == id || entry.officialSourceId == id) {
        return entry.wireKey;
      }
    }
    return null;
  }
}

/// Exposed for the done step's navigation intents ("立即学习"/"查看牌组").
typedef AnkiImportCompletion = ({String importId, String? wireKey});

extension AnkiImportCompletionWire on AnkiImportDependencies {
  String? wireKeyForImportId(String id) =>
      const AnkiImportCompletionCoordinator()
          ._wireForImportId(id, courseProvider);
}
