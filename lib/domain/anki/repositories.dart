import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/anki/card_introduction_state.dart';
import 'package:turna/domain/anki/card_presentation.dart';
import 'package:turna/domain/anki/course_card_placement.dart';
import 'package:turna/domain/anki/review_queue_snapshot.dart';

abstract interface class CanonicalAnkiRepository {
  Future<CanonicalSource> importPackage(ImportPackageRequest request);
  Future<CanonicalSource?> sourceById(String profileId, String sourceId);
  Future<List<CanonicalCardKey>> cardKeysForSource(String sourceId);
  Future<CanonicalCard> loadCard(CanonicalCardKey key);
  Future<List<CanonicalCard>> loadCards(List<CanonicalCardKey> keys);
  Future<void> archiveSource(String sourceId);
}

abstract interface class CourseCardRepository {
  Future<List<CourseCardPlacement>> placementsForLesson(String lessonId);
  Future<List<CourseCardPlacement>> activePlacementsForCourse(String courseId);
  Future<CourseCardPlacement?> placementForCard(
    String courseId,
    CanonicalCardKey key,
  );
  Future<void> publishProjection(CourseProjectionGeneration generation);
  Future<void> archivePlacement(String placementId);
}

abstract interface class CardPresentationRepository {
  Future<CardPresentation> activePresentation(
    String courseId,
    CanonicalCardKey key,
  );
  Future<CardPresentation?> activePresentationOrNull(
    String courseId,
    CanonicalCardKey key,
  );
  Future<void> activateCandidate(PresentationCandidate candidate);
  Future<void> markStaleByFingerprint(String sourceId, String fingerprint);
}

abstract interface class CardIntroductionRepository {
  Future<CardIntroductionState> stateFor(
    String courseId,
    CanonicalCardKey key,
  );
  Future<Set<CanonicalCardKey>> introducedKeys(String courseId);
  Future<void> markIntroduced(
    String courseId,
    CanonicalCardKey key, {
    required CardIntroducedBy by,
    required String lessonId,
  });
  Future<void> retire(String courseId, CanonicalCardKey key);
}

abstract interface class ReviewQueueRepository {
  Future<ReviewQueueSnapshot> build({
    required String courseId,
    String? sectionId,
    String? lessonId,
    int limit = 20,
  });
}
