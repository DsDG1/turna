// Project imports:
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/anki/card_introduction_state.dart';

/// Persistence for the card-introduction table (`anki_card_introduction_states`,
/// schema v18): which canonical cards a course has already surfaced.
///
/// Concrete: `AnkiUnificationDao` in `lib/data`.
abstract class IAnkiUnificationStore {
  /// Runs [action] inside a single database transaction so multi-row
  /// identity writes are all-or-nothing.
  Future<T> transaction<T>(Future<T> Function() action);

  /// Upsert the introduction state for one canonical card in [courseId].
  Future<void> upsertIntroduction({
    required String courseId,
    required CanonicalCardKey key,
    required CardIntroductionStatus status,
    CardIntroducedBy? introducedBy,
    DateTime? introducedAt,
    String? firstLessonId,
    DateTime? lastStudiedAt,
  });

  /// Current introduction state for one card (absent → `notIntroduced`).
  Future<CardIntroductionState> introductionState({
    required String courseId,
    required CanonicalCardKey key,
  });

  /// Card ids already marked `introduced` for one source (import) id.
  Future<Set<int>> introducedCardIdsForSource({required String sourceId});

  /// Insert an initial row without clobbering a later introduced/retired
  /// state.
  Future<void> ensureInitial({
    required String courseId,
    required CanonicalCardKey key,
    required CardIntroductionStatus status,
    CardIntroducedBy? introducedBy,
    DateTime? introducedAt,
    String? firstLessonId,
  });

  /// Adopt imported review history: mark the card introduced at
  /// [adoptedAt] when it has no prior state.
  Future<bool> adoptImportedHistory({
    required String courseId,
    required CanonicalCardKey key,
    required DateTime adoptedAt,
  });

  /// Remove every introduction row owned by [courseId].
  Future<void> deleteByCourseId(String courseId);
}
