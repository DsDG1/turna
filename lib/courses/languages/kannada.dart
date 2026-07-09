// Project imports:
import 'package:words625/courses/course_loader.dart';
import 'package:words625/domain/course/section.dart';

/// Top-level Swahili course structure: sections → units → lessons → stages.
///
/// Course data lives under `assets/courses/swahili/` — an `index.json` plus
/// one JSON file per section (see [SwahiliCourse.indexAsset]). At startup
/// only the index is read, so this returns **section shells** (id/name/
/// description/prerequisiteSectionIds, `units` empty). A section's full body
/// is loaded on demand via [SwahiliCourse.loadSection] (wired through
/// `CourseProvider.ensureSectionLoaded`). This file is kept as a thin
/// convenience re-export so call sites can keep using
/// [loadSwahiliSectionShells].
///
/// NOTE: The on-disk JSON still contains Kannada lesson data while the
/// Swahili content is being prepared.
Future<List<Section>> loadSwahiliSectionShells() async {
  final course = await SwahiliCourse.load();
  return course.sectionShells;
}