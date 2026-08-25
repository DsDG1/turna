import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';
import 'package:turna/application/anki/card_introduction_eligibility.dart';
import 'package:turna/application/course_catalog.dart';

class FormalReviewSourceTarget {
  const FormalReviewSourceTarget({
    required this.importOrSourceId,
    required this.displayName,
    required this.owner,
  });

  final String importOrSourceId;
  final String displayName;
  final AnkiEngineKind owner;

  String get courseId => owner == AnkiEngineKind.official
      ? CardIntroductionEligibility.courseIdForOfficialSource(
          importOrSourceId,
        )
      : CardIntroductionEligibility.courseIdForLegacyImport(importOrSourceId);
}

class FormalReviewSourceFailure {
  const FormalReviewSourceFailure({required this.target, required this.error});

  final FormalReviewSourceTarget target;
  final Object error;
}

/// Review All freezes source identity/order at launch, then opens exactly one
/// owner-specific session at a time. Card order remains live inside each
/// source's scheduler.
class FormalReviewSourceCoordinator {
  FormalReviewSourceCoordinator(List<FormalReviewSourceTarget> targets)
      : targets = List.unmodifiable(targets);

  factory FormalReviewSourceCoordinator.fromCatalog(
    List<CourseCatalogEntry> entries,
  ) {
    return FormalReviewSourceCoordinator([
      for (final entry in entries)
        if (!entry.isBuiltin && entry.officialSourceId != null)
          FormalReviewSourceTarget(
            importOrSourceId: entry.officialSourceId!,
            displayName: entry.displayName,
            owner: AnkiEngineKind.official,
          )
        else if (!entry.isBuiltin && entry.legacyImportId != null)
          FormalReviewSourceTarget(
            importOrSourceId: entry.legacyImportId!,
            displayName: entry.displayName,
            owner: AnkiEngineKind.legacy,
          ),
    ]);
  }

  /// Cold-start fallback while the course catalog is still loading. The due
  /// repository already carries exact Official source ids, so Review All can
  /// fail closed to those ids instead of reverting to a synthetic empty
  /// Legacy session.
  factory FormalReviewSourceCoordinator.fromOfficialSourceIds(
    Iterable<String> sourceIds,
  ) {
    return FormalReviewSourceCoordinator([
      for (final sourceId in sourceIds)
        FormalReviewSourceTarget(
          importOrSourceId: sourceId,
          displayName: sourceId,
          owner: AnkiEngineKind.official,
        ),
    ]);
  }

  final List<FormalReviewSourceTarget> targets;
  final List<FormalReviewSourceFailure> failures = [];
  int _index = 0;
  int totalCount = 0;
  int rememberedCount = 0;
  int forgottenCount = 0;

  FormalReviewSourceTarget? get current =>
      _index < targets.length ? targets[_index] : null;
  int get currentIndex => _index;
  bool get isComplete => _index >= targets.length;

  void recordSession({
    required int total,
    required int remembered,
    required int forgotten,
  }) {
    totalCount += total;
    rememberedCount += remembered;
    forgottenCount += forgotten;
  }

  void recordFailure(Object error) {
    final target = current;
    if (target != null) {
      failures.add(FormalReviewSourceFailure(target: target, error: error));
    }
  }

  void advance() {
    if (_index < targets.length) _index++;
  }
}
