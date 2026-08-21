import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:turna/domain/anki/study_models.dart';
import 'package:turna/routing/routing.gr.dart';

/// Production formal-review entries. Each may only change [StudyScope].
enum FormalReviewEntryKind {
  playHub,
  ankiHub,
  courseReview,
  deckSection,
  statsContinue,
}

enum FormalReviewHostKind {
  sharedSession,
  failClosed,
}

class FormalReviewLaunchDecision {
  const FormalReviewLaunchDecision({
    required this.host,
    required this.scope,
    required this.entry,
  });

  final FormalReviewHostKind host;
  final StudyScope scope;
  final FormalReviewEntryKind entry;

  /// Single production session route. Callers must not pick Official vs Legacy
  /// pages from engine kind.
  static const sessionRouteName = 'AnkiReviewSessionRoute';

  bool get isFailClosed => host == FormalReviewHostKind.failClosed;
}

/// Resolves every formal Anki review entry onto one session host.
class FormalReviewLauncher {
  const FormalReviewLauncher();

  static const productionEntries = FormalReviewEntryKind.values;

  static const sessionRouteName = FormalReviewLaunchDecision.sessionRouteName;

  static const failClosedMessage = 'official_anki.review_fail_closed';

  FormalReviewLaunchDecision resolve({
    required FormalReviewEntryKind entry,
    required String courseId,
    String? sectionId,
    String? lessonId,
    required bool officialOwner,
    required bool officialCapable,
  }) {
    final scope = StudyScope(
      courseId: courseId,
      sectionId: sectionId,
      lessonId: lessonId,
    );
    if (officialOwner && !officialCapable) {
      return FormalReviewLaunchDecision(
        host: FormalReviewHostKind.failClosed,
        scope: scope,
        entry: entry,
      );
    }
    return FormalReviewLaunchDecision(
      host: FormalReviewHostKind.sharedSession,
      scope: scope,
      entry: entry,
    );
  }

  /// Snapshot used by routing tests: every entry maps to the same host name.
  Map<FormalReviewEntryKind, String> productionHostSnapshot({
    required bool officialOwner,
    required bool officialCapable,
  }) {
    return {
      for (final entry in productionEntries)
        entry: resolve(
          entry: entry,
          courseId: 'course',
          officialOwner: officialOwner,
          officialCapable: officialCapable,
        ).isFailClosed
            ? 'failClosed'
            : sessionRouteName,
    };
  }

  /// Production navigation used by every formal-review entry.
  ///
  /// Always opens [AnkiReviewSessionRoute] (the shared session host). Never
  /// selects Official vs Legacy pages. Tests may intercept via
  /// [FormalReviewNavigator.debugOpenSession].
  Future<void> open(
    BuildContext context, {
    required FormalReviewEntryKind entry,
    required String courseId,
    String? sectionId,
    String? lessonId,
    required bool officialOwner,
    required bool officialCapable,
  }) {
    final decision = resolve(
      entry: entry,
      courseId: courseId,
      sectionId: sectionId,
      lessonId: lessonId,
      officialOwner: officialOwner,
      officialCapable: officialCapable,
    );
    return FormalReviewNavigator.openSession(
      context,
      decision: decision,
      sectionId: sectionId,
    );
  }
}

/// Single navigator for production Anki formal review.
class FormalReviewNavigator {
  FormalReviewNavigator._();

  /// Test seam. Production pushes [AnkiReviewSessionRoute].
  static Future<void> Function(BuildContext context, String? sectionId)?
      debugOpenSession;

  static Future<void> openSession(
    BuildContext context, {
    required FormalReviewLaunchDecision decision,
    String? sectionId,
  }) async {
    if (decision.isFailClosed) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(FormalReviewLauncher.failClosedMessage)),
      );
      return;
    }
    final override = debugOpenSession;
    if (override != null) {
      await override(context, sectionId);
      return;
    }
    if (!context.mounted) return;
    await context.router.push(AnkiReviewSessionRoute(sectionId: sectionId));
  }
}
