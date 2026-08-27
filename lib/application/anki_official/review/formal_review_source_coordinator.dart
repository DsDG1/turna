import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';
import 'package:turna/application/anki_official/introduction/card_introduction_eligibility.dart';
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

/// What stopped a source from completing (maintainability plan §9.4).
enum FormalReviewFailureKind {
  /// The source's batch could not be loaded (target resolution, engine).
  load,

  /// Cards failed to render (Blocked result).
  render,

  /// The session itself threw mid-run.
  runtime,
}

class FormalReviewSourceFailure {
  const FormalReviewSourceFailure({
    required this.target,
    required this.error,
    this.kind = FormalReviewFailureKind.runtime,
    this.retryable = true,
    this.code = 'unknown',
  });

  final FormalReviewSourceTarget target;
  final Object error;
  final FormalReviewFailureKind kind;

  /// Whether the completion page should offer a retry entry.
  final bool retryable;

  /// Stable machine code (`OfficialAnkiErrorCode.name` or
  /// `render_internal_error` style).
  final String code;
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
    // Doc 35 L2: Legacy-owned sources have no runtime anymore — Review
    // All skips them (fail-closed) instead of opening retired semantics.
    return FormalReviewSourceCoordinator([
      for (final entry in entries)
        if (!entry.isBuiltin && entry.officialSourceId != null)
          FormalReviewSourceTarget(
            importOrSourceId: entry.officialSourceId!,
            displayName: entry.displayName,
            owner: AnkiEngineKind.official,
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

  int get completedSourceCount => targets.length - failures.length;

  /// Targets eligible for a retry from the completion page.
  List<FormalReviewSourceTarget> get failedTargets => [
        for (final failure in failures)
          if (failure.retryable) failure.target,
      ];

  void recordSession({
    required int total,
    required int remembered,
    required int forgotten,
  }) {
    totalCount += total;
    rememberedCount += remembered;
    forgottenCount += forgotten;
  }

  void recordFailure(
    Object error, {
    FormalReviewFailureKind kind = FormalReviewFailureKind.runtime,
    bool retryable = true,
    String code = 'unknown',
  }) {
    final target = current;
    if (target != null) {
      failures.add(
        FormalReviewSourceFailure(
          target: target,
          error: error,
          kind: kind,
          retryable: retryable,
          code: code,
        ),
      );
    }
  }

  void advance() {
    if (_index < targets.length) _index++;
  }
}
