import 'dart:convert';

import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/anki/card_introduction_state.dart';
import 'package:turna/domain/anki/card_presentation.dart';
import 'package:turna/domain/anki/course_card_placement.dart';
import 'package:turna/domain/anki/repositories.dart';
import 'package:turna/domain/anki/review_queue_snapshot.dart';
import 'package:turna/domain/anki/study_models.dart';
import 'package:turna/domain/course/interaction.dart';

String _placementKey(String courseId, CanonicalCardKey key) =>
    '$courseId|${key.sourceId}|${key.cardId}';

/// In-process implementation of the unification repositories.
///
/// Drift persistence is layered on top via [AnkiUnificationDao]. Tests and
/// session code drive this type so cardinality, introduction, and queue
/// intersection are the same shipped functions in every environment.
class InMemoryAnkiUnificationStore
    implements
        CourseCardRepository,
        CardPresentationRepository,
        CardIntroductionRepository,
        ReviewQueueRepository {
  InMemoryAnkiUnificationStore({
    this.dueLookup,
    this.ledgerOwnerFor,
  });

  final Future<Set<CanonicalCardKey>> Function(String courseId)? dueLookup;
  final StudyLedgerOwner Function(CanonicalCardKey key)? ledgerOwnerFor;

  final Map<String, CourseCardPlacement> _placements = {};
  final Map<String, CardPresentation> _presentations = {};
  final Map<String, CardIntroductionState> _introductions = {};
  final Set<String> _suspended = {};
  final Set<String> _buried = {};

  void seedPlacement(CourseCardPlacement placement) {
    if (placement.active) {
      _assertNoActiveDuplicate(placement);
    }
    _placements[placement.placementId] = placement;
  }

  void seedPresentation(CardPresentation presentation, {required String courseId}) {
    final key = _placementKey(courseId, presentation.cardKey);
    if (_presentations.containsKey(key)) {
      throw StateError(
        'Active presentation already exists for ${presentation.cardKey}',
      );
    }
    _presentations[key] = presentation;
  }

  void seedIntroduction(CardIntroductionState state) {
    _introductions[_placementKey(state.courseId, state.cardKey)] = state;
  }

  void markSuspended(String courseId, CanonicalCardKey key) {
    _suspended.add(_placementKey(courseId, key));
  }

  void markBuried(String courseId, CanonicalCardKey key) {
    _buried.add(_placementKey(courseId, key));
  }

  @override
  Future<List<CourseCardPlacement>> placementsForLesson(String lessonId) async {
    return _placements.values
        .where((p) => p.active && p.lessonId == lessonId)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  @override
  Future<List<CourseCardPlacement>> activePlacementsForCourse(
    String courseId,
  ) async {
    return _placements.values
        .where((p) => p.active && p.courseId == courseId)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  @override
  Future<CourseCardPlacement?> placementForCard(
    String courseId,
    CanonicalCardKey key,
  ) async {
    for (final placement in _placements.values) {
      if (placement.active &&
          placement.courseId == courseId &&
          placement.cardKey == key) {
        return placement;
      }
    }
    return null;
  }

  @override
  Future<void> publishProjection(CourseProjectionGeneration generation) async {
    _assertCardinality(generation);
    _placements.removeWhere(
      (_, placement) =>
          placement.courseId == generation.courseId &&
          placement.cardKey.sourceId == generation.sourceId,
    );
    _presentations.removeWhere((_, presentation) {
      return presentation.cardKey.sourceId == generation.sourceId;
    });
    for (final placement in generation.placements) {
      seedPlacement(placement);
    }
    for (final row in generation.presentations) {
      seedPresentation(
        _presentationFromRow(row),
        courseId: generation.courseId,
      );
    }
  }

  @override
  Future<void> archivePlacement(String placementId) async {
    final current = _placements[placementId];
    if (current == null) return;
    _placements[placementId] = CourseCardPlacement(
      placementId: current.placementId,
      courseId: current.courseId,
      cardKey: current.cardKey,
      sectionId: current.sectionId,
      unitId: current.unitId,
      lessonId: current.lessonId,
      order: current.order,
      active: false,
      projectionVersion: current.projectionVersion,
      sourceFingerprint: current.sourceFingerprint,
    );
  }

  @override
  Future<CardPresentation> activePresentation(
    String courseId,
    CanonicalCardKey key,
  ) async {
    final found = await activePresentationOrNull(courseId, key);
    if (found == null) {
      throw StateError('No active presentation for $key in $courseId');
    }
    return found;
  }

  @override
  Future<CardPresentation?> activePresentationOrNull(
    String courseId,
    CanonicalCardKey key,
  ) async {
    return _presentations[_placementKey(courseId, key)];
  }

  @override
  Future<void> activateCandidate(PresentationCandidate candidate) async {
    final key = _placementKey(candidate.courseId, candidate.cardKey);
    _presentations[key] = StructuredCardPresentation(
      cardKey: candidate.cardKey,
      kind: candidate.kind,
      interaction: Interaction.fromJson(
        Map<String, dynamic>.from(jsonDecode(candidate.payloadJson) as Map),
      ),
      sourceFingerprint: candidate.sourceFingerprint,
      classifierVersion: candidate.classifierVersion,
      mappingVersion: candidate.mappingVersion,
    );
  }

  @override
  Future<void> markStaleByFingerprint(
    String sourceId,
    String fingerprint,
  ) async {
    _presentations.removeWhere(
      (_, presentation) =>
          presentation.cardKey.sourceId == sourceId &&
          presentation.sourceFingerprint != fingerprint,
    );
  }

  @override
  Future<CardIntroductionState> stateFor(
    String courseId,
    CanonicalCardKey key,
  ) async {
    return _introductions[_placementKey(courseId, key)] ??
        CardIntroductionState(
          courseId: courseId,
          cardKey: key,
          status: CardIntroductionStatus.unintroduced,
        );
  }

  @override
  Future<Set<CanonicalCardKey>> introducedKeys(String courseId) async {
    return {
      for (final state in _introductions.values)
        if (state.courseId == courseId && state.isIntroduced) state.cardKey,
    };
  }

  @override
  Future<void> markIntroduced(
    String courseId,
    CanonicalCardKey key, {
    required CardIntroducedBy by,
    required String lessonId,
  }) async {
    final current = await stateFor(courseId, key);
    if (current.isRetired) return;
    final now = DateTime.now();
    _introductions[_placementKey(courseId, key)] = current.copyWith(
      status: CardIntroductionStatus.introduced,
      introducedBy: current.introducedBy ?? by,
      introducedAt: current.introducedAt ?? now,
      firstLessonId: current.firstLessonId ?? lessonId,
      lastStudiedAt: now,
      version: current.version + 1,
    );
  }

  @override
  Future<void> retire(String courseId, CanonicalCardKey key) async {
    final current = await stateFor(courseId, key);
    _introductions[_placementKey(courseId, key)] = current.copyWith(
      status: CardIntroductionStatus.retired,
      version: current.version + 1,
    );
  }

  @override
  Future<ReviewQueueSnapshot> build({
    required String courseId,
    String? sectionId,
    String? lessonId,
    int limit = 20,
  }) async {
    final placements = (await activePlacementsForCourse(courseId)).where((p) {
      if (sectionId != null && p.sectionId != sectionId) return false;
      if (lessonId != null && p.lessonId != lessonId) return false;
      return true;
    }).toList();
    final introduced = await introducedKeys(courseId);
    final due = dueLookup == null
        ? introduced
        : await dueLookup!(courseId);
    final items = <StudyItem>[];
    var unintroducedNew = 0;
    for (final placement in placements) {
      final identity = _placementKey(courseId, placement.cardKey);
      if (_suspended.contains(identity) || _buried.contains(identity)) {
        continue;
      }
      final intro = await stateFor(courseId, placement.cardKey);
      if (intro.isRetired) continue;
      if (!intro.isIntroduced) {
        unintroducedNew++;
        continue;
      }
      if (!due.contains(placement.cardKey)) continue;
      final presentation = await activePresentationOrNull(
        courseId,
        placement.cardKey,
      );
      if (presentation == null) continue;
      final owner = ledgerOwnerFor?.call(placement.cardKey) ??
          (placement.cardKey.backend == AnkiBackendKind.official
              ? StudyLedgerOwner.officialAnki
              : StudyLedgerOwner.turnaFsrs);
      items.add(
        StudyItem(
          sessionItemId: '${placement.placementId}-review',
          courseId: courseId,
          placementId: placement.placementId,
          cardKey: placement.cardKey,
          presentation: presentation,
          mode: StudyMode.review,
          ledgerOwner: owner,
          capabilities: StudyCapabilities.forMode(StudyMode.review),
        ),
      );
      if (items.length >= limit) break;
    }
    return ReviewQueueSnapshot(
      items: items,
      introducedDue: items.length,
      unintroducedNew: unintroducedNew,
      freshness: ReviewQueueFreshness.ready,
      refreshedAt: DateTime.now(),
    );
  }

  void _assertNoActiveDuplicate(CourseCardPlacement placement) {
    for (final existing in _placements.values) {
      if (existing.active &&
          existing.placementId != placement.placementId &&
          existing.courseId == placement.courseId &&
          existing.cardKey.sourceId == placement.cardKey.sourceId &&
          existing.cardKey.cardId == placement.cardKey.cardId) {
        throw StateError(
          'Active placement already exists for ${placement.cardKey}',
        );
      }
    }
  }

  void _assertCardinality(CourseProjectionGeneration generation) {
    final placementIds = <int>{};
    for (final placement in generation.placements.where((p) => p.active)) {
      if (!placementIds.add(placement.cardKey.cardId)) {
        throw StateError(
          'Generation ${generation.generationId} has two active placements '
          'for card ${placement.cardKey.cardId}',
        );
      }
    }
    final presentationIds = <int>{};
    for (final row in generation.presentations) {
      if (!presentationIds.add(row.cardKey.cardId)) {
        throw StateError(
          'Generation ${generation.generationId} has two active presentations '
          'for card ${row.cardKey.cardId}',
        );
      }
    }
    if (placementIds.length != presentationIds.length ||
        !placementIds.containsAll(presentationIds)) {
      throw StateError(
        'canonical/placement/presentation cardinality mismatch: '
        'placements=${placementIds.length} presentations=${presentationIds.length}',
      );
    }
  }

  CardPresentation _presentationFromRow(PresentationPublishRow row) {
    final kind = CardPresentationKind.values.firstWhere(
      (value) => value.name == row.kindName,
      orElse: () => CardPresentationKind.flip,
    );
    if (kind == CardPresentationKind.flip) {
      final json = jsonDecode(row.payloadJson);
      final map = json is Map ? Map<String, dynamic>.from(json) : <String, dynamic>{};
      return FlipCardPresentation(
        cardKey: row.cardKey,
        frontText: map['front'] as String? ?? '',
        backText: map['back'] as String? ?? '',
        sourceFingerprint: row.sourceFingerprint,
        mappingVersion: row.mappingVersion,
        classifierVersion: row.classifierVersion,
      );
    }
    if (kind == CardPresentationKind.fidelity) {
      return FidelityCardPresentation(
        cardKey: row.cardKey,
        templateRef: CanonicalTemplateRef(
          notetypeId: 0,
          ordinal: 0,
          fingerprint: row.sourceFingerprint,
        ),
        sourceFingerprint: row.sourceFingerprint,
        mappingVersion: row.mappingVersion,
        classifierVersion: row.classifierVersion,
      );
    }
    return StructuredCardPresentation(
      cardKey: row.cardKey,
      kind: kind,
      interaction: Interaction.fromJson(
        Map<String, dynamic>.from(jsonDecode(row.payloadJson) as Map),
      ),
      sourceFingerprint: row.sourceFingerprint,
      mappingVersion: row.mappingVersion,
      classifierVersion: row.classifierVersion,
    );
  }
}
