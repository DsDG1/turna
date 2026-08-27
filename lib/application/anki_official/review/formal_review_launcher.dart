import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:turna/application/anki_official/review/official_study_batch_assembler.dart';
import 'package:turna/application/study_session/study_ledger_adapters.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_review_session.dart';
import 'package:turna/application/anki_official/review/official_formal_review_coordinator.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/anki/card_presentation.dart';
import 'package:turna/domain/anki/study_models.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/review/official_anki_review_ledger.dart';
import 'package:turna/l10n/app_strings.dart';
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

/// Result of assembling an Official formal-review batch for the shared host.
class OfficialFormalReviewBatch {
  const OfficialFormalReviewBatch({
    required this.items,
    required this.ledger,
    required this.session,
    this.fidelityInteractions = const {},
    this.liveQueue,
    this.failures = const [],
  });

  final List<StudyItem> items;
  final OfficialStudyLedger ledger;
  final OfficialReviewSession session;

  /// HTML faces for [FidelityCardPresentation] items, keyed by
  /// [StudyItem.sessionItemId]. Required when any item uses fidelity.
  final Map<String, AnkiHtmlCard> fidelityInteractions;

  /// Live queue driver (plan 34 D4): when present, the shared host MUST
  /// rebuild the batch from the scheduler's refreshed queue after every
  /// mutation instead of advancing a fixed item array.
  final OfficialFormalReviewLiveQueue? liveQueue;

  /// Non-blocking render failures from the initial pass — surfaced in the
  /// session summary (maintainability plan §8.2).
  final List<OfficialCardRenderFailure> failures;
}

/// Typed load outcome for the shared formal-review host (maintainability
/// plan §8.2). The scheduler queue being non-empty can never surface as
/// [OfficialFormalReviewNoDue].
sealed class OfficialFormalReviewLoadResult {
  const OfficialFormalReviewLoadResult();
}

/// At least one card rendered and stayed in the queue; non-blocking render
/// failures ride along for the session summary.
final class OfficialFormalReviewReady
    extends OfficialFormalReviewLoadResult {
  const OfficialFormalReviewReady(this.batch);

  final OfficialFormalReviewBatch batch;

  /// Non-blocking render failures ride on the batch (§8.2).
  List<OfficialCardRenderFailure> get failures => batch.failures;
}

/// The scheduler queue is genuinely empty for this source.
final class OfficialFormalReviewNoDue extends OfficialFormalReviewLoadResult {
  const OfficialFormalReviewNoDue();
}

/// The queue is non-empty but NOTHING could be rendered — a visible,
/// retryable product error. The session was disposed by the loader; no
/// answer, bury or suspend was issued (maintainability plan §8.2).
final class OfficialFormalReviewBlocked
    extends OfficialFormalReviewLoadResult {
  const OfficialFormalReviewBlocked({
    required this.sourceId,
    required this.failures,
    required this.schedulerCardCount,
  });

  final String sourceId;
  final List<OfficialCardRenderFailure> failures;
  final int schedulerCardCount;
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
    required bool schedulerRuntimeAvailable,
  }) {
    final scope = StudyScope(
      courseId: courseId,
      sectionId: sectionId,
      lessonId: lessonId,
    );
    if (officialOwner && !schedulerRuntimeAvailable) {
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

  /// Assemble Official queue ∩ formal-due into StudyItems + OfficialStudyLedger.
  ///
  /// Shared session hosts must use this path for Official owners instead of
  /// Legacy [AnkiReviewAssembler] + Turna SRS.
  OfficialFormalReviewBatch assembleOfficialBatch({
    required OfficialReviewSession session,
    required String sourceId,
    required String courseId,
    required Iterable<OfficialReviewQueueCard> queueCards,
    required Map<CanonicalCardKey, CardPresentation> presentations,
    required Set<CanonicalCardKey> activePlacementCardKeys,
    required Set<CanonicalCardKey> introducedCardKeys,
    Set<CanonicalCardKey> suspendedCardKeys = const {},
    Set<CanonicalCardKey> buriedCardKeys = const {},
    Set<CanonicalCardKey> retiredCardKeys = const {},
    Map<String, AnkiHtmlCard> fidelityInteractions = const {},
    int? limit,
    OfficialStudyBatchAssembler assembler = const OfficialStudyBatchAssembler(),
  }) {
    final items = assembler.assembleFromEligibility(
      sourceId: sourceId,
      courseId: courseId,
      queueCards: queueCards,
      presentations: presentations,
      activePlacementCardKeys: activePlacementCardKeys,
      introducedCardKeys: introducedCardKeys,
      suspendedCardKeys: suspendedCardKeys,
      buriedCardKeys: buriedCardKeys,
      retiredCardKeys: retiredCardKeys,
      limit: limit,
    );
    return OfficialFormalReviewBatch(
      items: items,
      ledger: OfficialStudyLedger(OfficialAnkiReviewLedger(session)),
      session: session,
      fidelityInteractions: fidelityInteractions,
    );
  }

  /// Snapshot used by routing tests: every entry maps to the same host name.
  Map<FormalReviewEntryKind, String> productionHostSnapshot({
    required bool officialOwner,
    required bool schedulerRuntimeAvailable,
  }) {
    return {
      for (final entry in productionEntries)
        entry: resolve(
          entry: entry,
          courseId: 'course',
          officialOwner: officialOwner,
          schedulerRuntimeAvailable: schedulerRuntimeAvailable,
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
    required bool schedulerRuntimeAvailable,
  }) {
    final decision = resolve(
      entry: entry,
      courseId: courseId,
      sectionId: sectionId,
      lessonId: lessonId,
      officialOwner: officialOwner,
      schedulerRuntimeAvailable: schedulerRuntimeAvailable,
    );
    return FormalReviewNavigator.openSession(
      context,
      decision: decision,
      sectionId: sectionId,
      officialOwner: officialOwner,
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
    bool officialOwner = false,
  }) async {
    if (decision.isFailClosed) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.officialAnkiError(
              FormalReviewLauncher.failClosedMessage,
            ),
          ),
        ),
      );
      return;
    }
    final override = debugOpenSession;
    if (override != null) {
      await override(context, sectionId);
      return;
    }
    if (!context.mounted) return;
    await context.router.push(
      AnkiReviewSessionRoute(
        sectionId: sectionId,
        officialOwner: officialOwner,
      ),
    );
  }
}
