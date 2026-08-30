import 'package:turna/application/anki_official/introduction/card_introduction_eligibility.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_store.dart';
import 'package:turna/data/anki_owner_authority_dao.dart';
import 'package:turna/data/anki_unification_dao.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/data/course_database.dart';

class UnifiedAnkiImportResult {
  const UnifiedAnkiImportResult({
    required this.canonicalCardCount,
    required this.placementCount,
    required this.presentationCount,
  });

  final int canonicalCardCount;
  final int placementCount;
  final int presentationCount;

  bool get cardinalityOk =>
      canonicalCardCount == placementCount &&
      placementCount == presentationCount;
}

/// Publishes placement/presentation identity for official sources.
/// The legacy `begin/finalize/importPackage` path (Dart-parsed card lists,
/// Turna SRS registration, `persistedOwnerIsOfficial == false`) was dead in
/// production — every production caller goes through [publishFromProjection]
/// — and was deleted in doc 39 P1-C.
class UnifiedAnkiImportOrchestrator {
  UnifiedAnkiImportOrchestrator();

  static final UnifiedAnkiImportOrchestrator instance =
      UnifiedAnkiImportOrchestrator();

  /// Runs one identity insert; a UNIQUE conflict means the 1:1 identity row
  /// already exists (dedup miss / re-import) and is skipped, while any other
  /// failure (disk full, locked db, schema drift) propagates and aborts the
  /// surrounding transaction instead of being silently swallowed.
  static Future<bool> _insertConflictSafe(
    Future<void> Function() insert,
  ) async {
    try {
      await insert();
      return true;
    } catch (error) {
      if (error.toString().contains('UNIQUE constraint')) return false;
      rethrow;
    }
  }

  /// P5F-22: publish placements/presentations for an official source from
  /// its course projection index — real section/unit/lesson ids and the
  /// projected presentation kind — instead of the Dart-parsed card list.
  /// One row per projected card; duplicates keep the existing 1:1 identity.
  Future<UnifiedAnkiImportResult> publishFromProjection({
    required String sourceId,
    required String sourceHash,
  }) async {
    final course = getIt<CourseDatabase>();
    final rows =
        await OfficialAnkiCourseProjectionStore(course).listIndexRows(sourceId);
    if (!getIt.isRegistered<AnkiUnificationDao>() ||
        !getIt.isRegistered<AnkiOwnerAuthorityDao>()) {
      throw StateError(
        'identity+authority DAOs missing; refuse false completion',
      );
    }
    final dao = getIt<AnkiUnificationDao>();
    final courseId =
        CardIntroductionEligibility.courseIdForOfficialSource(sourceId);
    final ids = [for (final row in rows) row.cardId];
    var placements = 0;
    var presentations = 0;
    var order = 0;
    await dao.transaction(() async {
      if (!getIt.isRegistered<AnkiOwnerAuthorityDao>()) {
        throw StateError('authority dao missing inside identity transaction');
      }
      for (final row in rows) {
        final key = CanonicalCardKey(
          backend: AnkiBackendKind.official,
          profileId: CardIntroductionEligibility.defaultProfileId,
          sourceId: sourceId,
          cardId: row.cardId,
        );
        if (await _insertConflictSafe(
          () => dao.insertActivePlacement(
            placementId: '$courseId-${row.cardId}',
            courseId: courseId,
            profileId: CardIntroductionEligibility.defaultProfileId,
            key: key,
            sectionId: row.sectionId,
            unitId: row.unitId,
            lessonId: row.lessonId,
            order: order++,
            sourceFingerprint: sourceHash,
          ),
        )) {
          placements++;
        }
        if (await _insertConflictSafe(
          () => dao.insertActivePresentation(
            courseId: courseId,
            key: key,
            kind: row.kind,
            payloadJson: '{}',
            sourceFingerprint: sourceHash,
          ),
        )) {
          presentations++;
        }
      }
      final authority = getIt<AnkiOwnerAuthorityDao>();
      await authority.upsertSource(
        courseId: courseId,
        profileId: 'profile-default-01',
        sourceId: sourceId,
        backendKind: 'official',
        displayName: sourceId,
        sourceHash: sourceHash,
        sourceFingerprint: sourceHash,
        state: AnkiSourceVisibility.staging,
      );
      await authority.commitVisibility(
        courseId: courseId,
        state: AnkiSourceVisibility.active,
        activeProjectionGeneration: sourceHash,
      );
      final verified = await authority.findBySource(
        profileId: 'profile-default-01',
        sourceId: sourceId,
      );
      if (verified == null || verified.state != AnkiSourceVisibility.active) {
        throw StateError('authority active commit did not persist');
      }
    });
    return UnifiedAnkiImportResult(
      canonicalCardCount: ids.length,
      placementCount: placements,
      presentationCount: presentations,
    );
  }
}
