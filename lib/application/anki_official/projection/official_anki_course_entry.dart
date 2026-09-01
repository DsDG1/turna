import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_ids.dart';
import 'package:turna/application/anki_official/render/official_anki_reviewer_router.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_course_read.dart';
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
    OfficialAnkiDatabase? catalog,
    required CourseDatabase course,
  }) async {
    // v2 读面（B6）：视图 section 并入。activeSectionIds 自带 flag 门
    // （关时返回空集）——回退后视图里的历史行不会混入 v1 读面。
    // Catalog is optional: v1 visibility is the Course manifest/index.
    // Missing catalogOf used to return {} and hide a fully projected tree.
    final v2Ids = catalog == null
        ? const <String>{}
        : await OfficialAnkiV2CourseRead(
            catalog: catalog,
            course: course,
          ).activeSectionIds();
    if (catalog != null) {
      catalog.handle.userVersion;
    }
    final manifests = await course.customSelect(
      'SELECT source_id, source_fingerprint FROM official_anki_projection_manifest',
    ).get();
    final ids = <String>{...v2Ids};
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

  /// CourseDatabase index (v1 manifest) plus optional catalog (v2 views).
  /// Never reads projection staging. Catalog may be absent on cold start
  /// before the importer opens — v1 projected sections must still resolve.
  static Future<Set<String>> resolveActiveSectionIds() async {
    final hook = activeSectionIds;
    if (hook != null) return Set<String>.from(hook());
    CourseDatabase? course;
    try {
      course = courseOf?.call() ?? CourseLoader.databaseOrNull();
    } catch (_) {
      course = null;
    }
    if (course == null) return <String>{};
    return lookupActiveSectionIdsAsync(
      catalog: catalogOf?.call(),
      course: course,
    );
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
