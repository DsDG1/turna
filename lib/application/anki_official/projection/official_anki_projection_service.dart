import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Variable;
import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:turna/application/anki_import/recognition/recognize/recognizer.dart';
import 'package:turna/application/anki_official/contract/official_anki_contract.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/introduction/imported_history_introducer.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_canonical.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_fingerprint.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_ids.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_jobs.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_paging.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_projector.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_store.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/data/course_database.dart';

const officialAnkiProjectionBatchDefault = officialAnkiProjectionPageDefault;
const officialAnkiProjectionBatchMax = officialAnkiProjectionPageMax;

class OfficialAnkiProjectionCounters {
  var peakIdBuffer = 0;
}

class OfficialAnkiProjectionPublishResult {
  const OfficialAnkiProjectionPublishResult({
    required this.noop,
    required this.itemCount,
    required this.fingerprint,
    this.cancelled = false,
    this.failed = false,
    this.rowCount = 0,
    this.needsMapping = false,
    this.errorCode,
    this.jobId,
  });

  final bool noop;
  final int itemCount;
  final String fingerprint;
  final bool cancelled;
  final bool failed;
  final int rowCount;
  final bool needsMapping;
  final String? errorCode;
  final String? jobId;
}

/// Builds a derived course tree from official Collection rows.
///
/// Production entry pages `anki_source_cards` by source and strictly
/// ascending `card_id`. Crash recovery is rebuild-from-0, not cursor resume.
/// Scheduler writes and Legacy importer/renderer calls stay at 0.
class OfficialAnkiCourseProjectionService {
  OfficialAnkiCourseProjectionService({
    required this.engine,
    required this.catalog,
    required this.course,
    required this.sourceId,
    required this.profileId,
    OfficialAnkiFeatureFlags? flags,
    CardRecognizer? recognizer,
    OfficialAnkiProjectionProjector? projector,
    OfficialAnkiProjectionCounters? counters,
    OfficialAnkiCourseProjectionStore? store,
    OfficialAnkiProjectionJobRepository? jobs,
    int batchSize = officialAnkiProjectionBatchDefault,
    String? ownerToken,
  })  : flags = flags ?? const OfficialAnkiFeatureFlags(),
        recognizer = recognizer ?? const CardRecognizer(),
        projector = projector ?? OfficialAnkiProjectionProjector(),
        counters = counters ?? OfficialAnkiProjectionCounters(),
        store = store ?? OfficialAnkiCourseProjectionStore(course),
        jobs = jobs ?? OfficialAnkiProjectionJobRepository(catalog),
        sources = OfficialAnkiSourceDao(catalog),
        batchSize = batchSize.clamp(1, officialAnkiProjectionBatchMax),
        ownerToken =
            ownerToken ?? officialAnkiProjectionOwnerToken(profileId);

  final OfficialAnkiEngine engine;
  final OfficialAnkiDatabase catalog;
  final CourseDatabase course;
  final String sourceId;
  final String profileId;
  final OfficialAnkiFeatureFlags flags;
  final CardRecognizer recognizer;
  final OfficialAnkiProjectionProjector projector;
  final OfficialAnkiProjectionCounters counters;
  final OfficialAnkiCourseProjectionStore store;
  final OfficialAnkiProjectionJobRepository jobs;
  final OfficialAnkiSourceDao sources;
  final int batchSize;
  final String ownerToken;

  String? _currentJobId;
  var _jobSeq = 0;

  /// Test-only: cancel the job immediately after it is created.
  @visibleForTesting
  var debugCancelImmediately = false;

  /// Test-only: throw after the job exists so exception terminalization is proven.
  @visibleForTesting
  Object? debugThrowDuringProject;

  void cancel() {
    final jobId = _currentJobId ?? jobs.activeWriter(sourceId)?.jobId;
    if (jobId == null) return;
    jobs.requestCancel(
      jobId: jobId,
      ownerToken: ownerToken,
      nowMillis: DateTime.now().millisecondsSinceEpoch,
    );
  }

  String fingerprintFor({
    required String cardSetFingerprint,
    required List<OfficialAnkiProjectionRow> rows,
    required int mappingVersion,
    required int collectionGeneration,
    required String backendCommit,
    Iterable<OfficialAnkiProjectionSchema> schemas = const <OfficialAnkiProjectionSchema>[],
    Map<int, OfficialAnkiMappingSuggestion> mappings =
        const <int, OfficialAnkiMappingSuggestion>{},
  }) {
    return officialAnkiProjectionFingerprint(
      contractMajor: kOfficialAnkiContractMajor,
      contractMinor: kOfficialAnkiContractMinor,
      backendCommit: backendCommit,
      profileId: profileId,
      sourceId: sourceId,
      orderedCardSetFingerprint: cardSetFingerprint,
      collectionGeneration: collectionGeneration,
      schemas: schemas,
      mappingVersion: mappingVersion,
      confirmedMappingHash: officialAnkiConfirmedMappingHash(mappings),
      rows: rows,
    );
  }

  OfficialAnkiMappingSuggestion suggestFor(OfficialAnkiProjectionSchema schema) {
    return officialAnkiSuggestMapping(schema, recognizer);
  }

  void confirmMapping({
    required OfficialAnkiProjectionSchema schema,
    required OfficialAnkiMappingSuggestion suggestion,
    int mappingVersion = 1,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = _readMapping(schema.notetypeId);
    final next = suggestion.copyWith(
      notetypeId: schema.notetypeId,
      schemaFingerprint: schema.schemaFingerprint,
      userConfirmed: true,
      updatedAtMillis: now,
      status: OfficialAnkiMappingStatus.manual,
      recognitionConfidence: 1,
    );
    final nextVersion = existing == null
        ? mappingVersion
        : officialAnkiSameCanonicalMapping(existing, next)
            ? existing.mappingVersion
            : existing.mappingVersion + 1;
    final stored = next.copyWith(mappingVersion: nextVersion);
    catalog.handle.execute('BEGIN IMMEDIATE');
    try {
      catalog.handle.execute(
        'INSERT OR REPLACE INTO anki_projection_mappings '
        '(profile_id, notetype_id, schema_fingerprint, mapping_json, status, '
        'user_confirmed, mapping_version, updated_at_millis) '
        'VALUES (?, ?, ?, ?, ?, 1, ?, ?)',
        [
          profileId,
          schema.notetypeId,
          schema.schemaFingerprint,
          jsonEncode(stored.toJson()),
          stored.status.name,
          nextVersion,
          now,
        ],
      );
      catalog.handle.execute('COMMIT');
    } catch (suppressed) {
      debugPrint('[OfficialAnkiProjectionService] suppressed error: $suppressed');
      catalog.handle.execute('ROLLBACK');
      rethrow;
    }
  }

  void skipNotetype({
    required OfficialAnkiProjectionSchema schema,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = _readMapping(schema.notetypeId);
    final stored = OfficialAnkiMappingSuggestion(
      candidates: const <OfficialAnkiFieldCandidate>[],
      status: OfficialAnkiMappingStatus.skipped,
      notetypeId: schema.notetypeId,
      schemaFingerprint: schema.schemaFingerprint,
      userConfirmed: true,
      updatedAtMillis: now,
      mappingVersion: existing?.mappingVersion ?? 1,
      direction: existing?.direction ?? 'promptToResponse',
      enabledKinds: existing?.enabledKinds ?? const <String>[],
    );
    final nextVersion = existing == null
        ? stored.mappingVersion
        : officialAnkiSameCanonicalMapping(existing, stored)
            ? existing.mappingVersion
            : existing.mappingVersion + 1;
    final written = stored.copyWith(mappingVersion: nextVersion);
    catalog.handle.execute('BEGIN IMMEDIATE');
    try {
      catalog.handle.execute(
        'INSERT OR REPLACE INTO anki_projection_mappings '
        '(profile_id, notetype_id, schema_fingerprint, mapping_json, status, '
        'user_confirmed, mapping_version, updated_at_millis) '
        'VALUES (?, ?, ?, ?, ?, 1, ?, ?)',
        [
          profileId,
          schema.notetypeId,
          schema.schemaFingerprint,
          jsonEncode(written.toJson()),
          written.status.name,
          nextVersion,
          now,
        ],
      );
      catalog.handle.execute('COMMIT');
    } catch (suppressed) {
      debugPrint('[OfficialAnkiProjectionService] suppressed error: $suppressed');
      catalog.handle.execute('ROLLBACK');
      rethrow;
    }
  }

  void lockPlacement({
    required int cardId,
    required String sectionKey,
    required String unitKey,
    required String lessonKey,
  }) {
    if (!_acceptablePlacementKey(sectionKey) ||
        !_acceptablePlacementKey(unitKey) ||
        !_acceptablePlacementKey(lessonKey)) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidArgument,
        messageKey: 'official_anki.placement_not_official',
      );
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    catalog.handle.execute(
      'INSERT OR REPLACE INTO anki_course_placement_overrides '
      '(source_id, card_id, section_key, unit_key, lesson_key, locked, '
      'updated_at_millis) VALUES (?, ?, ?, ?, ?, 1, ?)',
      [sourceId, cardId, sectionKey, unitKey, lessonKey, now],
    );
  }

  /// Production entry: page catalog cards for [sourceId]. [notetypeIds] is
  /// the frozen source scope (doc 42); an empty list evaluates no schemas.
  Future<OfficialAnkiProjectionPublishResult> projectSource({
    required List<int> notetypeIds,
    int mappingVersion = 1,
    bool typeAnswerEnabled = false,
    bool failPublish = false,
    String? resumeJobId,
  }) {
    return _project(
      notetypeIds: notetypeIds,
      mappingVersion: mappingVersion,
      typeAnswerEnabled: typeAnswerEnabled,
      failPublish: failPublish,
      resumeJobId: resumeJobId,
    );
  }

  /// Production Generate: resume the existing `needs_mapping` job.
  Future<OfficialAnkiProjectionPublishResult> generateCourse({
    required List<int> notetypeIds,
    String? jobId,
    int mappingVersion = 1,
    bool typeAnswerEnabled = false,
  }) {
    final resume = jobId ?? jobs.activeWriter(sourceId)?.jobId;
    return _project(
      notetypeIds: notetypeIds,
      mappingVersion: mappingVersion,
      typeAnswerEnabled: typeAnswerEnabled,
      failPublish: false,
      resumeJobId: resume,
    );
  }

  List<int> catalogNotetypeIds() {
    final ids = <int>{};
    for (final card in sources.listCards(sourceId)) {
      final id = card.notetypeId;
      if (id != null) ids.add(id);
    }
    return ids.toList();
  }

  /// Diagnostic/test helper. Not used by the composition root.
  @visibleForTesting
  Future<OfficialAnkiProjectionPublishResult> projectSourceFromCardIdsForTest({
    required List<int> cardIds,
    int mappingVersion = 1,
    bool typeAnswerEnabled = false,
    bool failPublish = false,
  }) async {
    sources.replaceCards(
      sourceId: sourceId,
      cards: [
        for (final id in cardIds)
          OfficialAnkiCardDescriptor(
            cardId: id,
            noteId: id,
            deckId: 1,
            templateOrd: 0,
            noteGuid: 'test-$id',
            notetypeId: 1,
          ),
      ],
    );
    return _project(
      notetypeIds: [
        for (final card in sources.listCards(sourceId))
          if (card.notetypeId != null) card.notetypeId!,
      ],
      mappingVersion: mappingVersion,
      typeAnswerEnabled: typeAnswerEnabled,
      failPublish: failPublish,
    );
  }

  Future<OfficialAnkiProjectionPublishResult> _project({
    required List<int> notetypeIds,
    required int mappingVersion,
    required bool typeAnswerEnabled,
    required bool failPublish,
    String? resumeJobId,
  }) async {
    if (!flags.allowsProjection) {
      return const OfficialAnkiProjectionPublishResult(
        noop: true,
        itemCount: 0,
        fingerprint: '',
      );
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = jobs.activeWriter(sourceId);
    final OfficialAnkiProjectionJob job;
    if (resumeJobId != null) {
      job = jobs.resumeJob(
        jobId: resumeJobId,
        ownerToken: ownerToken,
        nowMillis: now,
      );
    } else if (existing != null &&
        existing.isResumable &&
        existing.ownerToken == ownerToken) {
      job = jobs.resumeJob(
        jobId: existing.jobId,
        ownerToken: ownerToken,
        nowMillis: now,
      );
    } else {
      job = jobs.createJob(
        jobId: 'job-$sourceId-$now-${identityHashCode(this)}-${++_jobSeq}',
        sourceId: sourceId,
        ownerToken: ownerToken,
        nowMillis: now,
      );
    }
    _currentJobId = job.jobId;
    try {
    if (debugCancelImmediately) {
      cancel();
    }
    if (debugThrowDuringProject != null) {
      throw debugThrowDuringProject!;
    }
      jobs.heartbeat(
        jobId: job.jobId,
        ownerToken: ownerToken,
        nowMillis: DateTime.now().millisecondsSinceEpoch,
        state: OfficialAnkiProjectionJobState.scanningSource,
      );
      final scan = await _scanSource(job.jobId);
      if (scan.cancelled) return scan.result;
      jobs.heartbeat(
        jobId: job.jobId,
        ownerToken: ownerToken,
        nowMillis: DateTime.now().millisecondsSinceEpoch,
        state: OfficialAnkiProjectionJobState.scanningSchema,
        cardSetFingerprint: scan.cardSetFingerprint,
        totalCards: scan.total,
      );
      // Doc 38 P5: both inputs of the scan fingerprint are available before
      // any row is read — engine identity (backendCommit) and the content
      // generation (a light BEGIN_PROJECTION_READ; no row traffic).
      final info = await engine.engineInfo();
      final earlySnapshot = await engine.beginProjectionRead(
        cardSetFingerprint: scan.cardSetFingerprint,
        mappingVersion: mappingVersion,
      );
      final schemas = notetypeIds.isEmpty
          ? const <OfficialAnkiProjectionSchema>[]
          : await engine.getProjectionSchemas(
              notetypeIds: notetypeIds,
              includeSamples: true,
              sampleLimit: 30,
            );
      final mappings = <int, OfficialAnkiMappingSuggestion>{
        for (final schema in schemas) schema.notetypeId: suggestFor(schema),
      };
      final mappingOutcome = _mergeAndPersistMappings(
        schemas,
        mappings,
        mappingVersion,
      );
      if (mappingOutcome == _MappingOutcome.needsMapping) {
        jobs.heartbeat(
          jobId: job.jobId,
          ownerToken: ownerToken,
          nowMillis: DateTime.now().millisecondsSinceEpoch,
          state: OfficialAnkiProjectionJobState.needsMapping,
          schemaFingerprint: officialAnkiSchemaSetFingerprint(schemas),
        );
        return OfficialAnkiProjectionPublishResult(
          noop: false,
          itemCount: 0,
          fingerprint: scan.cardSetFingerprint,
          needsMapping: true,
          jobId: job.jobId,
        );
      }
      jobs.heartbeat(
        jobId: job.jobId,
        ownerToken: ownerToken,
        nowMillis: DateTime.now().millisecondsSinceEpoch,
        state: OfficialAnkiProjectionJobState.projecting,
        schemaFingerprint: officialAnkiSchemaSetFingerprint(schemas),
        mappingFingerprint: officialAnkiConfirmedMappingHash(mappings),
      );
      // Doc 38 P5 scan short-circuit: when every non-row factor matches the
      // last successful publish AND the manifest row still exists, the row
      // payloads cannot have changed (see doc 38 §7.1 soundness argument) —
      // skip the full row read and re-hash entirely.
      final scanFingerprint = officialAnkiProjectionScanFingerprint(
        contractMajor: kOfficialAnkiContractMajor,
        contractMinor: kOfficialAnkiContractMinor,
        backendCommit: info.backendCommit,
        profileId: profileId,
        sourceId: sourceId,
        orderedCardSetFingerprint: scan.cardSetFingerprint,
        collectionGeneration: earlySnapshot.collectionGeneration,
        schemasFingerprint: officialAnkiSchemaSetFingerprint(schemas),
        mappingVersion: mappingVersion,
        confirmedMappingHash: officialAnkiConfirmedMappingHash(mappings),
      );
      final active = await _activeFingerprints();
      if (active.scan == scanFingerprint && active.full != null) {
        jobs.markActive(
          jobId: job.jobId,
          ownerToken: ownerToken,
          nowMillis: DateTime.now().millisecondsSinceEpoch,
          sourceFingerprint: active.full!,
        );
        return OfficialAnkiProjectionPublishResult(
          noop: true,
          itemCount: scan.total,
          fingerprint: active.full!,
          rowCount: scan.total,
          jobId: job.jobId,
        );
      }
      final rowsResult = await _readRows(
        jobId: job.jobId,
        cardSetFingerprint: scan.cardSetFingerprint,
        mappingVersion: mappingVersion,
        expectedCount: scan.total,
      );
      if (rowsResult.cancelled) return rowsResult.result;
      if (rowsResult.failed) return rowsResult.result;
      final rows = rowsResult.rows;
      final fingerprint = fingerprintFor(
        cardSetFingerprint: scan.cardSetFingerprint,
        rows: rows,
        mappingVersion: mappingVersion,
        collectionGeneration: rowsResult.collectionGeneration,
        backendCommit: info.backendCommit,
        schemas: schemas,
        mappings: mappings,
      );
      final previous = await _activeFingerprint();
      if (previous == fingerprint) {
        jobs.markActive(
          jobId: job.jobId,
          ownerToken: ownerToken,
          nowMillis: DateTime.now().millisecondsSinceEpoch,
          sourceFingerprint: fingerprint,
        );
        return OfficialAnkiProjectionPublishResult(
          noop: true,
          itemCount: rows.length,
          fingerprint: fingerprint,
          rowCount: rows.length,
          jobId: job.jobId,
        );
      }
      final decks = await engine.listDeckTree();
      // The engine's flattened DFS list emits the synthetic root (deckId 0,
      // level 0) first and real top-level decks at level 1 — but some
      // engines tag top decks level 0. Accept both, never the root.
      final topDeckIds = <String, int>{
        for (final deck in decks)
          if (deck.deckId != 0 && deck.name.isNotEmpty && deck.level <= 1)
            deck.name: deck.deckId,
      };
      final overrides = _loadOverrides();
      final locked = overrides.entries
          .where((entry) => entry.value.locked)
          .map((entry) => entry.key)
          .toSet();
      final plan = projector.project(
        sourceId: sourceId,
        profileId: profileId,
        rows: rows,
        mappings: mappings,
        typeAnswerEnabled: typeAnswerEnabled,
        lockedCardIds: locked,
        placementOverrides: overrides,
        topDeckIds: topDeckIds,
      );
      if (failPublish) {
        jobs.markFailed(
          jobId: job.jobId,
          ownerToken: ownerToken,
          nowMillis: DateTime.now().millisecondsSinceEpoch,
          errorCode: 'publish_failed',
        );
        return OfficialAnkiProjectionPublishResult(
          noop: false,
          itemCount: 0,
          fingerprint: fingerprint,
          failed: true,
          rowCount: rows.length,
          jobId: job.jobId,
          errorCode: 'publish_failed',
        );
      }
      jobs.heartbeat(
        jobId: job.jobId,
        ownerToken: ownerToken,
        nowMillis: DateTime.now().millisecondsSinceEpoch,
        state: OfficialAnkiProjectionJobState.publishing,
      );
      if (jobs.isCancelRequested(job.jobId)) {
        return _cancelled(job.jobId, scan.cardSetFingerprint);
      }
      try {
        await store.replaceOfficialProjection(
          sourceId: sourceId,
          plan: plan,
          sourceFingerprint: fingerprint,
          publishedAtMillis: DateTime.now().millisecondsSinceEpoch,
          studiedCardIds: await _fetchStudiedCardIds(
            planCardIds: {for (final item in plan.items) item.cardId},
          ),
        );
      } catch (error) {
        jobs.markFailed(
          jobId: job.jobId,
          ownerToken: ownerToken,
          nowMillis: DateTime.now().millisecondsSinceEpoch,
          errorCode: 'publish_fault',
        );
        return OfficialAnkiProjectionPublishResult(
          noop: false,
          itemCount: 0,
          fingerprint: fingerprint,
          failed: true,
          rowCount: rows.length,
          jobId: job.jobId,
          errorCode: 'publish_fault',
        );
      }
      _setSourceState(
        'active',
        fingerprint: fingerprint,
        scanFingerprint: scanFingerprint,
        count: plan.items.length,
        jobId: job.jobId,
      );
      jobs.markActive(
        jobId: job.jobId,
        ownerToken: ownerToken,
        nowMillis: DateTime.now().millisecondsSinceEpoch,
        sourceFingerprint: fingerprint,
      );
      return OfficialAnkiProjectionPublishResult(
        noop: false,
        itemCount: plan.items.length,
        fingerprint: fingerprint,
        rowCount: rows.length,
        jobId: job.jobId,
      );
    } on OfficialAnkiException catch (error) {
      jobs.markFailed(
        jobId: job.jobId,
        ownerToken: ownerToken,
        nowMillis: DateTime.now().millisecondsSinceEpoch,
        errorCode: error.code.name,
        retryable: error.recoverable,
      );
      _currentJobId = null;
      return OfficialAnkiProjectionPublishResult(
        noop: false,
        itemCount: 0,
        fingerprint: '',
        failed: true,
        errorCode: error.code.name,
        jobId: job.jobId,
      );
    } catch (suppressed) {
      debugPrint('[OfficialAnkiProjectionService] suppressed error: $suppressed');
      jobs.markFailed(
        jobId: job.jobId,
        ownerToken: ownerToken,
        nowMillis: DateTime.now().millisecondsSinceEpoch,
        errorCode: OfficialAnkiErrorCode.internalError.name,
      );
      _currentJobId = null;
      return OfficialAnkiProjectionPublishResult(
        noop: false,
        itemCount: 0,
        fingerprint: '',
        failed: true,
        errorCode: OfficialAnkiErrorCode.internalError.name,
        jobId: job.jobId,
      );
    }
  }

  Future<void> deleteProjection() async {
    await store.deleteOfficialProjection(sourceId);
    _setSourceState('not_projected');
  }

  Future<({bool cancelled, OfficialAnkiProjectionPublishResult result, String cardSetFingerprint, int total})>
      _scanSource(String jobId) async {
    final idsForHash = StringBuffer();
    var total = 0;
    int? after;
    var first = true;
    while (true) {
      if (jobs.isCancelRequested(jobId)) {
        return (
          cancelled: true,
          result: _cancelled(jobId, ''),
          cardSetFingerprint: '',
          total: total,
        );
      }
      final page = sources.pageSourceCardIds(
        sourceId: sourceId,
        afterCardId: after,
        limit: batchSize,
      );
      counters.peakIdBuffer = math.max(counters.peakIdBuffer, page.cardIds.length);
      if (page.cardIds.isEmpty) break;
      for (final id in page.cardIds) {
        if (!first) idsForHash.write(',');
        idsForHash.write(id);
        first = false;
        total++;
      }
      after = page.lastCardId;
      jobs.heartbeat(
        jobId: jobId,
        ownerToken: ownerToken,
        nowMillis: DateTime.now().millisecondsSinceEpoch,
        cursorCardId: after,
        processedCards: 0,
        totalCards: total,
      );
      if (!page.hasMore) break;
    }
    return (
      cancelled: false,
      result: const OfficialAnkiProjectionPublishResult(
        noop: true,
        itemCount: 0,
        fingerprint: '',
      ),
      cardSetFingerprint: sha256.convert(utf8.encode(idsForHash.toString())).toString(),
      total: total,
    );
  }

  /// Cards of this projection whose imported history (reps>=1) proves they
  /// were already studied. Best-effort: on search failure the projection
  /// still publishes and the home due sync's adopt pass repairs the ledger
  /// on its next refresh.
  Future<Set<int>> _fetchStudiedCardIds({
    required Set<int> planCardIds,
  }) async {
    try {
      final studied = await const ImportedHistoryIntroducer().fetchStudiedCardIds(
        searchPage: engine.searchCardsPage,
      );
      return studied.intersection(planCardIds);
    } catch (error) {
      debugPrint(
        'OfficialAnkiCourseProjectionService: studied-card search failed: '
        '$error',
      );
      return const <int>{};
    }
  }

  Future<
      ({
        bool cancelled,
        bool failed,
        OfficialAnkiProjectionPublishResult result,
        List<OfficialAnkiProjectionRow> rows,
        int collectionGeneration,
      })> _readRows({
    required String jobId,
    required String cardSetFingerprint,
    required int mappingVersion,
    required int expectedCount,
  }) async {
    Future<
        ({
          List<OfficialAnkiProjectionRow> rows,
          List<int> missing,
          int generation,
          String? error,
        })> pass() async {
      final snapshot = await engine.beginProjectionRead(
        cardSetFingerprint: cardSetFingerprint,
        mappingVersion: mappingVersion,
      );
      final rows = <OfficialAnkiProjectionRow>[];
      final missing = <int>[];
      final seen = <int>{};
      int? after;
      while (true) {
        if (jobs.isCancelRequested(jobId)) {
          return (
            rows: rows,
            missing: missing,
            generation: snapshot.collectionGeneration,
            error: 'cancelled',
          );
        }
        final page = sources.pageSourceCardIds(
          sourceId: sourceId,
          afterCardId: after,
          limit: batchSize,
        );
        counters.peakIdBuffer = math.max(counters.peakIdBuffer, page.cardIds.length);
        if (page.cardIds.isEmpty) break;
        OfficialAnkiProjectionPage batch;
        try {
          batch = await engine.getProjectionRowsBatch(
            cardIds: page.cardIds,
            snapshotToken: snapshot.snapshotToken,
          );
        } on OfficialAnkiException catch (error) {
          if (error.code == OfficialAnkiErrorCode.projectionSnapshotStale) {
            return (
              rows: rows,
              missing: missing,
              generation: snapshot.collectionGeneration,
              error: 'PROJECTION_SOURCE_CHANGED',
            );
          }
          rethrow;
        }
        if (batch.missingCardIds.isNotEmpty) {
          missing.addAll(batch.missingCardIds);
        }
        for (final row in batch.rows) {
          if (!seen.add(row.cardId)) {
            return (
              rows: rows,
              missing: missing,
              generation: snapshot.collectionGeneration,
              error: 'duplicate_row',
            );
          }
          rows.add(row);
        }
        after = page.lastCardId;
        jobs.heartbeat(
          jobId: jobId,
          ownerToken: ownerToken,
          nowMillis: DateTime.now().millisecondsSinceEpoch,
          cursorCardId: after,
          processedCards: rows.length,
        );
        if (!page.hasMore) break;
      }
      return (
        rows: rows,
        missing: missing,
        generation: snapshot.collectionGeneration,
        error: null,
      );
    }

    var first = await pass();
    if (first.error == 'cancelled') {
      return (
        cancelled: true,
        failed: false,
        result: _cancelled(jobId, cardSetFingerprint),
        rows: const <OfficialAnkiProjectionRow>[],
        collectionGeneration: first.generation,
      );
    }
    if (first.error != null ||
        first.missing.isNotEmpty ||
        first.rows.length + first.missing.length != expectedCount) {
      if (first.error == 'duplicate_row') {
        return _failClosed(jobId, cardSetFingerprint, 'duplicate_row');
      }
      final retry = await pass();
      if (retry.error == 'cancelled') {
        return (
          cancelled: true,
          failed: false,
          result: _cancelled(jobId, cardSetFingerprint),
          rows: const <OfficialAnkiProjectionRow>[],
          collectionGeneration: retry.generation,
        );
      }
      if (retry.error != null ||
          retry.missing.isNotEmpty ||
          retry.rows.length != expectedCount) {
        return _failClosed(
          jobId,
          cardSetFingerprint,
          retry.error ?? 'PROJECTION_SOURCE_CHANGED',
        );
      }
      first = retry;
    }
    return (
      cancelled: false,
      failed: false,
      result: const OfficialAnkiProjectionPublishResult(
        noop: true,
        itemCount: 0,
        fingerprint: '',
      ),
      rows: first.rows,
      collectionGeneration: first.generation,
    );
  }

  ({
    bool cancelled,
    bool failed,
    OfficialAnkiProjectionPublishResult result,
    List<OfficialAnkiProjectionRow> rows,
    int collectionGeneration,
  }) _failClosed(String jobId, String fingerprint, String code) {
    jobs.markFailed(
      jobId: jobId,
      ownerToken: ownerToken,
      nowMillis: DateTime.now().millisecondsSinceEpoch,
      errorCode: code,
    );
    return (
      cancelled: false,
      failed: true,
      result: OfficialAnkiProjectionPublishResult(
        noop: false,
        itemCount: 0,
        fingerprint: fingerprint,
        failed: true,
        errorCode: code,
        jobId: jobId,
      ),
      rows: const <OfficialAnkiProjectionRow>[],
      collectionGeneration: 0,
    );
  }

  OfficialAnkiProjectionPublishResult _cancelled(String jobId, String fingerprint) {
    jobs.markCancelled(
      jobId: jobId,
      ownerToken: ownerToken,
      nowMillis: DateTime.now().millisecondsSinceEpoch,
    );
    return OfficialAnkiProjectionPublishResult(
      noop: false,
      itemCount: 0,
      fingerprint: fingerprint,
      cancelled: true,
      jobId: jobId,
    );
  }

  _MappingOutcome _mergeAndPersistMappings(
    List<OfficialAnkiProjectionSchema> schemas,
    Map<int, OfficialAnkiMappingSuggestion> mappings,
    int mappingVersion,
  ) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final lookup = catalog.handle.prepare(
      'SELECT schema_fingerprint, mapping_json, user_confirmed, status, '
      'mapping_version FROM anki_projection_mappings '
      'WHERE profile_id = ? AND notetype_id = ?',
    );
    final insert = catalog.handle.prepare(
      'INSERT OR REPLACE INTO anki_projection_mappings '
      '(profile_id, notetype_id, schema_fingerprint, mapping_json, status, '
      'user_confirmed, mapping_version, updated_at_millis) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
    );
    final keepConfirmed = catalog.handle.prepare(
      'UPDATE anki_projection_mappings SET status = ?, '
      'schema_fingerprint = ?, mapping_json = ?, mapping_version = ?, '
      'updated_at_millis = ? '
      'WHERE profile_id = ? AND notetype_id = ?',
    );
    var needsMapping = false;
    try {
      for (final schema in schemas) {
        final existing = lookup.select([profileId, schema.notetypeId]);
        if (existing.isNotEmpty && (existing.first['user_confirmed'] as int? ?? 0) == 1) {
          final raw = existing.first['mapping_json'] as String? ?? '{}';
          final stored = OfficialAnkiMappingSuggestion.fromJson(
            Map<String, Object?>.from(jsonDecode(raw) as Map),
          );
          mappings[schema.notetypeId] = stored;
          if (stored.status == OfficialAnkiMappingStatus.skipped) {
            continue;
          }
          final sameFingerprint =
              (existing.first['schema_fingerprint'] as String?) ==
                  schema.schemaFingerprint;
          if (!sameFingerprint) {
            final reviewed = stored.copyWith(
              status: OfficialAnkiMappingStatus.review,
              schemaFingerprint: schema.schemaFingerprint,
              mappingVersion: stored.mappingVersion + 1,
              updatedAtMillis: now,
            );
            keepConfirmed.execute([
              reviewed.status.name,
              schema.schemaFingerprint,
              jsonEncode(reviewed.toJson()),
              reviewed.mappingVersion,
              now,
              profileId,
              schema.notetypeId,
            ]);
            mappings[schema.notetypeId] = reviewed;
            needsMapping = true;
          }
          continue;
        }
        final suggestion = mappings[schema.notetypeId]!;
        mappings[schema.notetypeId] = suggestion;
        insert.execute([
          profileId,
          schema.notetypeId,
          schema.schemaFingerprint,
          jsonEncode(suggestion.toJson()),
          suggestion.status.name,
          0,
          mappingVersion,
          now,
        ]);
        needsMapping = true;
      }
    } finally {
      lookup.dispose();
      insert.dispose();
      keepConfirmed.dispose();
    }
    return needsMapping ? _MappingOutcome.needsMapping : _MappingOutcome.ready;
  }

  OfficialAnkiMappingSuggestion? _readMapping(int notetypeId) {
    final rows = catalog.handle.select(
      'SELECT mapping_json FROM anki_projection_mappings '
      'WHERE profile_id = ? AND notetype_id = ?',
      [profileId, notetypeId],
    );
    if (rows.isEmpty) return null;
    return OfficialAnkiMappingSuggestion.fromJson(
      Map<String, Object?>.from(
        jsonDecode(rows.first['mapping_json'] as String? ?? '{}') as Map,
      ),
    );
  }

  bool _acceptablePlacementKey(String key) {
    if (key.startsWith('official-anki-')) {
      return officialAnkiIsOwnedTreeId(sourceId: sourceId, id: key);
    }
    if (key.startsWith('anki-')) return false;
    return key.isNotEmpty;
  }

  Map<int, OfficialAnkiPlacementOverride> _loadOverrides() {
    final rows = catalog.handle.select(
      'SELECT card_id, section_key, unit_key, lesson_key, locked '
      'FROM anki_course_placement_overrides WHERE source_id = ?',
      [sourceId],
    );
    final out = <int, OfficialAnkiPlacementOverride>{};
    for (final row in rows) {
      out[(row['card_id'] as int)] = OfficialAnkiPlacementOverride(
        sectionKey: row['section_key'] as String?,
        unitKey: row['unit_key'] as String?,
        lessonKey: row['lesson_key'] as String?,
        locked: (row['locked'] as int? ?? 0) == 1,
      );
    }
    return out;
  }

  /// The catalog fingerprint alone cannot prove a tree exists: the seeder
  /// (and any course-DB wipe) drops the projection tables without touching
  /// the catalog, which would otherwise no-op the next publish forever.
  /// Treat the state as absent unless the course manifest row is still there.
  Future<String?> _activeFingerprint() async =>
      (await _activeFingerprints()).full;

  /// Full + scan fingerprints of the last successful publish, nulled unless
  /// the course manifest row still exists (same fail-safe as above).
  Future<({String? full, String? scan})> _activeFingerprints() async {
    final rows = catalog.handle.select(
      'SELECT source_fingerprint, scan_fingerprint '
      'FROM anki_source_projection_state WHERE source_id = ?',
      [sourceId],
    );
    if (rows.isEmpty) return (full: null, scan: null);
    final full = rows.first['source_fingerprint'] as String?;
    final scan = rows.first['scan_fingerprint'] as String?;
    if (full == null || full.isEmpty) return (full: null, scan: null);
    final manifest = await course.customSelect(
      'SELECT 1 FROM official_anki_projection_manifest '
      'WHERE source_id = ? LIMIT 1',
      variables: [Variable<String>(sourceId)],
    ).get();
    if (manifest.isEmpty) return (full: null, scan: null);
    return (full: full, scan: scan);
  }

  void _setSourceState(
    String state, {
    String? fingerprint,
    String? scanFingerprint,
    int count = 0,
    String? jobId,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    catalog.handle.execute(
      'INSERT OR REPLACE INTO anki_source_projection_state '
      '(source_id, state, active_projection_version, source_fingerprint, '
      'projected_card_count, last_projected_at_millis, active_job_id, '
      'scan_fingerprint) VALUES (?, ?, 1, ?, ?, ?, ?, ?)',
      [
        sourceId,
        state,
        fingerprint,
        count,
        now,
        jobId ?? _currentJobId,
        scanFingerprint,
      ],
    );
  }
}

enum _MappingOutcome { ready, needsMapping }

int officialAnkiCatalogMappingCount(Database db, String profileId) {
  final rows = db.select(
    'SELECT COUNT(*) AS n FROM anki_projection_mappings WHERE profile_id = ?',
    [profileId],
  );
  return (rows.first['n'] as int?) ?? 0;
}
