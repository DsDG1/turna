import 'package:turna/domain/review/official_anki_review_ledger.dart';
import 'package:turna/domain/review/review_ledger.dart';
import 'package:turna/domain/review/review_source.dart';
import 'package:turna/domain/review/turna_review_ledger.dart';

/// Resolves the unique authoritative [ReviewLedger] for a given [ReviewSource].
///
/// Invariant: One card, one interaction, one unique writer. No double writes.
class ReviewLedgerResolver {
  final TurnaReviewLedger _turnaLedger;
  final OfficialAnkiReviewLedger? _officialLedger;

  ReviewLedgerResolver({
    required TurnaReviewLedger turnaLedger,
    OfficialAnkiReviewLedger? officialLedger,
  })  : _turnaLedger = turnaLedger,
        _officialLedger = officialLedger;

  ReviewLedger resolve(ReviewSource source) {
    switch (source) {
      case TurnaCourseSource():
      case LegacyAnkiSource():
        return _turnaLedger;
      case OfficialAnkiSource():
        if (_officialLedger == null) {
          throw StateError(
            'OfficialAnkiReviewLedger is not available for $source',
          );
        }
        return _officialLedger;
    }
  }
}
