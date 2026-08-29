import 'package:flutter/foundation.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/introduction/card_introduction_store.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_store.dart';
import 'package:turna/courses/course_loader.dart';

/// P1: the course-completion gate lives in the Official scheduler.
///
/// Cards of a source the introduction ledger has NOT introduced stay
/// suspended (`BuryOrSuspendMode::Suspend`), so the scheduler queue, the
/// due/learn/new searches and the deck counts all exclude them without any
/// Dart-side set arithmetic. Reconcile is one-directional by design: it only
/// suspends unintroduced cards and never restores — a user suspension of an
/// introduced card is invisible state to the ledger and must survive every
/// reconcile pass. Unlocking happens exactly once, at lesson completion,
/// through [unlockCards].
class OfficialAnkiLockReconciler {
  const OfficialAnkiLockReconciler({this.engine});

  final OfficialAnkiEngine? engine;

  /// Test seam. Production resolves through the composition root.
  static OfficialAnkiLockReconciler? debugOverride;

  static OfficialAnkiLockReconciler resolve() =>
      debugOverride ?? const OfficialAnkiLockReconciler();

  /// The bridge caps one bury/suspend batch at 100 card ids.
  static const _batchSize = 100;

  /// Suspend-every-unintroduced-card of [sourceId]. Idempotent: cards
  /// already suspended stay suspended, introduced cards (course-taught or
  /// imported history) are never touched. Fail-closed — errors are logged
  /// and retried on the next refresh, never thrown.
  Future<int> reconcileSource({required String sourceId}) async {
    try {
      final resolved = engine ?? OfficialAnkiCompositionRoot.engine;
      if (resolved == null) return 0;
      final course = CourseLoader.databaseOrNull();
      if (course == null) return 0;
      final rows = await OfficialAnkiCourseProjectionStore(course)
          .listIndexRows(sourceId);
      if (rows.isEmpty) return 0;
      // Ledger-direct on purpose: the lock must not depend on any
      // in-memory mirror (a cold process would otherwise suspend
      // everything, introduced cards included).
      final introduced = await CardIntroductionStore.resolve()
          .introducedCardIdsFromLedger(sourceId);
      final toSuspend = [
        for (final row in rows)
          if (!introduced.contains(row.cardId)) row.cardId,
      ]..sort();
      if (toSuspend.isEmpty) return 0;
      await _applyInBatches(
        resolved,
        OfficialBuryOrSuspendAction.suspend,
        toSuspend,
      );
      return toSuspend.length;
    } catch (error) {
      debugPrint('[OfficialAnkiLockReconciler] reconcile failed: $error');
      return 0;
    }
  }

  /// Restores the lock suspension of exactly [cardIds] at lesson
  /// completion. Unlike [reconcileSource] this rethrows: the caller must
  /// abort the introduction marking when the restore fails, so ledger and
  /// scheduler never disagree (both stay "unintroduced + suspended", and
  /// any later completion of the lesson retries).
  Future<void> unlockCards({
    required String sourceId,
    required List<int> cardIds,
  }) async {
    if (cardIds.isEmpty) return;
    final resolved = engine ?? OfficialAnkiCompositionRoot.engine;
    if (resolved == null) {
      throw StateError(
        'official engine unavailable; cannot unlock cards of $sourceId',
      );
    }
    await _applyInBatches(
      resolved,
      OfficialBuryOrSuspendAction.restoreCards,
      cardIds,
    );
  }

  Future<void> _applyInBatches(
    OfficialAnkiEngine resolved,
    OfficialBuryOrSuspendAction action,
    List<int> cardIds,
  ) async {
    for (var start = 0; start < cardIds.length; start += _batchSize) {
      final end = start + _batchSize < cardIds.length
          ? start + _batchSize
          : cardIds.length;
      await resolved.buryOrSuspendCards(
        action: action,
        cardIds: cardIds.sublist(start, end),
      );
    }
  }
}