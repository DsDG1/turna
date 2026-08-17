import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_ids.dart';
import 'package:turna/application/anki_official/render/official_anki_reviewer_router.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/data/course_database.dart' hide Section, Unit, Lesson, LessonContent;
import 'package:drift/drift.dart';
import 'package:turna/domain/course/section.dart';

class OfficialAnkiCanonicalRef {
  const OfficialAnkiCanonicalRef({
    required this.sourceId,
    required this.cardId,
  });

  final String sourceId;
  final int cardId;
}

/// CourseProvider only shows official sections when course-entry is on and
/// the source projection is active. Staging is never read.
class OfficialAnkiCourseEntry {
  static OfficialAnkiFeatureFlags Function() flagsOf =
      () => OfficialAnkiFeatureFlags.current;

  static Set<String> Function()? activeSectionIds;
  static OfficialAnkiDatabase Function()? catalogOf;
  static CourseDatabase Function()? courseOf;

  /// Test-only path override. The shipped opener still pushes
  /// [OfficialAnkiReviewerPage]; this only replaces `path_provider`.
  static OfficialAnkiPaths Function()? pathsOf;

  static void resetHooks() {
    flagsOf = () => OfficialAnkiFeatureFlags.current;
    activeSectionIds = null;
    catalogOf = null;
    courseOf = null;
    pathsOf = null;
  }

  static bool isOfficialSectionId(String id) => id.startsWith('official-anki-');

  static OfficialAnkiCanonicalRef? parseCanonicalLink(String? context) {
    const prefix = 'official-canonical-link:';
    if (context == null || !context.startsWith(prefix)) return null;
    final rest = context.substring(prefix.length);
    final split = rest.lastIndexOf(':');
    if (split <= 0 || split == rest.length - 1) return null;
    final sourceId = rest.substring(0, split);
    final cardId = int.tryParse(rest.substring(split + 1));
    if (sourceId.isEmpty || cardId == null) return null;
    return OfficialAnkiCanonicalRef(sourceId: sourceId, cardId: cardId);
  }

  static Future<Set<String>> lookupActiveSectionIdsAsync({
    required OfficialAnkiDatabase catalog,
    required CourseDatabase course,
  }) async {
    // Catalog is the job/recovery mirror only; Course manifest is visibility.
    catalog.handle.userVersion;
    final manifests = await course.customSelect(
      'SELECT source_id, source_fingerprint FROM official_anki_projection_manifest',
    ).get();
    final ids = <String>{};
    for (final row in manifests) {
      final sourceId = row.read<String>('source_id');
      final fingerprint = row.read<String>('source_fingerprint');
      final sections = await course.customSelect(
        'SELECT DISTINCT section_id, source_fingerprint '
        'FROM official_anki_projection_index WHERE source_id = ?',
        variables: [Variable(sourceId)],
      ).get();
      if (sections.isEmpty) continue;
      final consistent = sections.every(
        (section) => section.read<String>('source_fingerprint') == fingerprint,
      );
      if (!consistent) continue;
      for (final section in sections) {
        final id = section.read<String>('section_id');
        if (officialAnkiIsOwnedTreeId(sourceId: sourceId, id: id)) {
          ids.add(id);
        }
      }
    }
    return ids;
  }

  /// Catalog + CourseDatabase index. Never reads projection staging.
  static Future<Set<String>> resolveActiveSectionIds() async {
    final hook = activeSectionIds;
    if (hook != null) return Set<String>.from(hook());
    final catalog = catalogOf?.call();
    CourseDatabase? course;
    try {
      course = courseOf?.call() ?? CourseLoader.databaseOrNull();
    } catch (_) {
      course = null;
    }
    if (catalog == null || course == null) return <String>{};
    return lookupActiveSectionIdsAsync(catalog: catalog, course: course);
  }

  static List<Section> filterShells(
    List<Section> shells, {
    Set<String>? activeIds,
  }) {
    final flags = flagsOf();
    if (!flags.allowsCourseEntry) {
      return [
        for (final section in shells)
          if (!isOfficialSectionId(section.id)) section,
      ];
    }
    final active = activeIds ?? activeSectionIds?.call();
    if (active == null) {
      return [
        for (final section in shells)
          if (!isOfficialSectionId(section.id)) section,
      ];
    }
    return [
      for (final section in shells)
        if (!isOfficialSectionId(section.id) || active.contains(section.id))
          section,
    ];
  }

  static OfficialAnkiReviewTarget resolveCanonicalLink({
    required String? context,
    OfficialAnkiFeatureFlags? flags,
    bool rendererAvailable = true,
  }) {
    if (parseCanonicalLink(context) == null) {
      return OfficialAnkiReviewTarget.error;
    }
    return OfficialAnkiReviewerRouter.resolve(
      kind: OfficialAnkiSourceKind.official,
      flags: flags ?? flagsOf(),
      rendererAvailable: rendererAvailable,
    );
  }

  /// Same default profile the official preview / composition root uses.
  static Future<OfficialAnkiPaths> resolveDefaultPaths() async {
    final override = pathsOf;
    if (override != null) return override();
    final support = await getApplicationSupportDirectory();
    return OfficialAnkiPaths(
      profileId: 'profile-default-01',
      profileRoot: Directory('${support.path}/official_anki/default'),
    );
  }
}
