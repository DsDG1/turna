// Project imports:
import 'package:turna/courses/course_loader.dart';
import 'package:turna/domain/course/section.dart';

/// Top-level course structure: sections → units → lessons → stages.
///
/// Course data lives under `assets/courses/turkish/` — an `index.json` plus
/// one JSON file per section (see [CourseLoader.indexAsset]). At startup
/// only the index is read, so this returns **section shells** (id/name/
/// description/prerequisiteSectionIds, `units` empty). A section's full body
/// is loaded on demand via [CourseLoader.loadSection] (wired through
/// `CourseProvider.ensureSectionLoaded`). This file is kept as a thin
/// convenience re-export so call sites can keep using
/// [loadSectionShells].
Future<List<Section>> loadSectionShells() async {
  final course = await CourseLoader.load();
  return course.sectionShells;
}