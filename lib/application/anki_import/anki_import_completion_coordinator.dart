import 'package:turna/application/anki_import/anki_import_wizard_state.dart';
import 'package:turna/application/anki_import/anki_import_dependencies.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/courses/course_loader.dart';

/// Wire key of the catalog entry owned by [id] (legacy import id or
/// official source id), or null. Doc 39 P5: single copy — the import
/// screen's hand-rolled loop was deleted.
String? ankiImportWireKeyFor(CourseProvider courseProvider, String id) {
  for (final entry in courseProvider.catalogEntries) {
    if (entry.legacyImportId == id || entry.officialSourceId == id) {
      return entry.wireKey;
    }
  }
  return null;
}

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
    final newWire = ankiImportWireKeyFor(courseProvider, importId);
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
}

/// Doc 39 P5: the import screen's hand-rolled wire-key copy was deleted;
/// both the coordinator and the page resolve through the single
/// top-level lookup above.
extension AnkiImportCompletionWire on AnkiImportDependencies {
  String? wireKeyForImportId(String id) =>
      ankiImportWireKeyFor(courseProvider, id);
}
