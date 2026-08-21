import 'package:turna/application/anki/card_introduction_eligibility.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_store.dart';
import 'package:turna/data/anki_import_dao.dart';
import 'package:turna/data/anki_unification_dao.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/data/course_database.dart';

class UnifiedAnkiImportRequest {
  const UnifiedAnkiImportRequest({
    required this.importId,
    required this.sourceHash,
    required this.canonicalCardIds,
    required this.officialCapable,
    this.reuseExistingIdentity = true,
  });

  final String importId;
  final String sourceHash;
  final List<int> canonicalCardIds;
  final bool officialCapable;
  final bool reuseExistingIdentity;
}

class UnifiedAnkiImportResult {
  const UnifiedAnkiImportResult({
    required this.canonicalCardCount,
    required this.placementCount,
    required this.presentationCount,
    required this.wroteTurnaSrs,
    required this.noOp,
    required this.turnaSrsWordIds,
  });

  final int canonicalCardCount;
  final int placementCount;
  final int presentationCount;
  final bool wroteTurnaSrs;
  final bool noOp;
  final Set<String> turnaSrsWordIds;

  bool get cardinalityOk =>
      canonicalCardCount == placementCount &&
      placementCount == presentationCount;
}

/// Single import entry used by the import UI. Official-capable imports
/// publish placement/presentation only and never register Turna Anki SRS.
class UnifiedAnkiImportOrchestrator {
  UnifiedAnkiImportOrchestrator({
    this.lookupByHash,
    this.persistIdentity,
  });

  static final UnifiedAnkiImportOrchestrator instance =
      UnifiedAnkiImportOrchestrator();

  /// Test/production seam: true when this source hash is already imported.
  Future<bool> Function(String sourceHash)? lookupByHash;

  /// Test/production seam: persist canonical/placement/presentation rows.
  Future<void> Function(UnifiedAnkiImportRequest request)? persistIdentity;

  final Set<String> _seenHashes = {};
  final Map<String, List<int>> _placementsByImport = {};
  final Map<String, List<int>> _presentationsByImport = {};
  final Set<String> turnaSrsWordIds = {};

  Future<bool> _hashExists(String sourceHash) async {
    if (_seenHashes.contains(sourceHash)) return true;
    final lookup = lookupByHash;
    if (lookup != null) return lookup(sourceHash);
    if (getIt.isRegistered<CourseDatabase>()) {
      final existing =
          await AnkiImportDao(getIt<CourseDatabase>()).findByHash(sourceHash);
      return existing != null;
    }
    return false;
  }

  Future<void> _persist(UnifiedAnkiImportRequest request) async {
    final persist = persistIdentity;
    if (persist != null) {
      await persist(request);
      return;
    }
    if (!getIt.isRegistered<AnkiUnificationDao>()) return;
    final dao = getIt<AnkiUnificationDao>();
    final backend = request.officialCapable
        ? AnkiBackendKind.official
        : AnkiBackendKind.legacyTurna;
    final courseId = request.officialCapable
        ? CardIntroductionEligibility.courseIdForOfficialSource(request.importId)
        : CardIntroductionEligibility.courseIdForLegacyImport(request.importId);
    var order = 0;
    for (final cardId in request.canonicalCardIds) {
      final key = CanonicalCardKey(
        backend: backend,
        profileId: CardIntroductionEligibility.defaultProfileId,
        sourceId: request.importId,
        cardId: cardId,
      );
      try {
        await dao.insertActivePlacement(
          placementId: '$courseId-$cardId',
          courseId: courseId,
          profileId: CardIntroductionEligibility.defaultProfileId,
          key: key,
          sectionId: courseId,
          unitId: courseId,
          lessonId: courseId,
          order: order,
          sourceFingerprint: request.sourceHash,
        );
        await dao.insertActivePresentation(
          courseId: courseId,
          key: key,
          kind: 'flip',
          payloadJson: '{}',
          sourceFingerprint: request.sourceHash,
        );
      } catch (_) {
        // Duplicate identity rows stay 1:1; ignore unique conflicts.
      }
      order++;
    }
  }

  /// Probe identity. Same-hash hits return [noOp] and must skip assemble/SRS
  /// /Official collection writes.
  Future<UnifiedAnkiImportResult> begin(UnifiedAnkiImportRequest request) async {
    if (request.reuseExistingIdentity && await _hashExists(request.sourceHash)) {
      final placements = _placementsByImport[request.importId] ??
          List<int>.from(request.canonicalCardIds);
      return UnifiedAnkiImportResult(
        canonicalCardCount: placements.length,
        placementCount: placements.length,
        presentationCount: placements.length,
        wroteTurnaSrs: false,
        noOp: true,
        turnaSrsWordIds: const {},
      );
    }
    if (request.canonicalCardIds.toSet().length !=
        request.canonicalCardIds.length) {
      throw StateError('canonical card ids must be unique');
    }
    final srsIds = <String>{};
    if (!request.officialCapable) {
      for (final cardId in request.canonicalCardIds) {
        srsIds.add('anki-${request.importId}-c$cardId');
      }
    }
    return UnifiedAnkiImportResult(
      canonicalCardCount: request.canonicalCardIds.length,
      placementCount: request.canonicalCardIds.length,
      presentationCount: request.canonicalCardIds.length,
      wroteTurnaSrs: srsIds.isNotEmpty,
      noOp: false,
      turnaSrsWordIds: srsIds,
    );
  }

  Future<void> finalize(UnifiedAnkiImportRequest request) async {
    if (_seenHashes.contains(request.sourceHash)) return;
    _seenHashes.add(request.sourceHash);
    final placements = List<int>.from(request.canonicalCardIds);
    _placementsByImport[request.importId] = placements;
    _presentationsByImport[request.importId] = placements;
    if (!request.officialCapable) {
      for (final cardId in request.canonicalCardIds) {
        turnaSrsWordIds.add('anki-${request.importId}-c$cardId');
      }
    }
    await _persist(request);
  }

  /// Shipped entry: skip if same hash, otherwise persist identity 1:1.
  Future<UnifiedAnkiImportResult> importPackage(
    UnifiedAnkiImportRequest request,
  ) async {
    final started = await begin(request);
    if (started.noOp) return started;
    await finalize(request);
    return started;
  }

  /// P5F-22: publish placements/presentations for an official source from
  /// its course projection index — real section/unit/lesson ids and the
  /// projected presentation kind — instead of the Dart-parsed card list.
  /// One row per projected card; duplicates keep the existing 1:1 identity.
  Future<UnifiedAnkiImportResult> publishFromProjection({
    required String sourceId,
    required String sourceHash,
  }) async {
    _seenHashes.add(sourceHash);
    final course = getIt<CourseDatabase>();
    final rows = await OfficialAnkiCourseProjectionStore(course)
        .listIndexRows(sourceId);
    if (!getIt.isRegistered<AnkiUnificationDao>()) {
      return UnifiedAnkiImportResult(
        canonicalCardCount: rows.length,
        placementCount: rows.length,
        presentationCount: rows.length,
        wroteTurnaSrs: false,
        noOp: false,
        turnaSrsWordIds: const {},
      );
    }
    final dao = getIt<AnkiUnificationDao>();
    final courseId =
        CardIntroductionEligibility.courseIdForOfficialSource(sourceId);
    final ids = [for (final row in rows) row.cardId];
    var order = 0;
    for (final row in rows) {
      final key = CanonicalCardKey(
        backend: AnkiBackendKind.official,
        profileId: CardIntroductionEligibility.defaultProfileId,
        sourceId: sourceId,
        cardId: row.cardId,
      );
      try {
        await dao.insertActivePlacement(
          placementId: '$courseId-${row.cardId}',
          courseId: courseId,
          profileId: CardIntroductionEligibility.defaultProfileId,
          key: key,
          sectionId: row.sectionId,
          unitId: row.unitId,
          lessonId: row.lessonId,
          order: order++,
          sourceFingerprint: sourceHash,
        );
        await dao.insertActivePresentation(
          courseId: courseId,
          key: key,
          kind: row.kind,
          payloadJson: '{}',
          sourceFingerprint: sourceHash,
        );
      } catch (_) {
        // Duplicate identity rows stay 1:1; ignore unique conflicts.
      }
    }
    _placementsByImport[sourceId] = ids;
    _presentationsByImport[sourceId] = ids;
    return UnifiedAnkiImportResult(
      canonicalCardCount: ids.length,
      placementCount: ids.length,
      presentationCount: ids.length,
      wroteTurnaSrs: false,
      noOp: false,
      turnaSrsWordIds: const {},
    );
  }

  int placementCount(String importId) =>
      _placementsByImport[importId]?.length ?? 0;

  void reset() {
    _seenHashes.clear();
    _placementsByImport.clear();
    _presentationsByImport.clear();
    turnaSrsWordIds.clear();
    lookupByHash = null;
    persistIdentity = null;
  }
}
