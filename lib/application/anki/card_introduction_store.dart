import 'dart:async';

import 'package:turna/application/anki/anki_models.dart';
import 'package:turna/application/anki/card_introduction_eligibility.dart';
import 'package:turna/data/anki_unification_dao.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/anki/card_introduction_state.dart';
import 'package:turna/domain/course/srs_word.dart';

/// What changed in the introduction ledger (maintainability plan §7.4).
enum CardIntroductionChangeKind { introduced, retired }

/// Published AFTER the ledger write succeeded, so a listener that commits
/// the change elsewhere never persists a failure as fact.
class CardIntroductionChanged {
  const CardIntroductionChanged({
    required this.sourceId,
    required this.cardId,
    required this.kind,
  });

  final String sourceId;
  final int cardId;
  final CardIntroductionChangeKind kind;
}

/// In-memory + Drift introduction ledger used by course submit and formal
/// review. Missing rows are unintroduced unless imported history (reps>0)
/// proves the card was already studied in Anki.
class CardIntroductionStore {
  CardIntroductionStore({
    AnkiUnificationDao? dao,
    this.eligibility = const CardIntroductionEligibility(),
  }) : _dao = dao;

  final AnkiUnificationDao? _dao;
  final CardIntroductionEligibility eligibility;

  /// Test seam. Production uses GetIt when registered.
  static CardIntroductionStore? debugOverride;
  static final CardIntroductionStore _fallback = CardIntroductionStore();

  static final StreamController<CardIntroductionChanged> _changes =
      StreamController<CardIntroductionChanged>.broadcast();

  /// Every successful ledger mutation, regardless of which store instance
  /// wrote it. The formal-due repository listens here to keep its snapshots
  /// current without getter-time bypasses.
  static Stream<CardIntroductionChanged> get changes => _changes.stream;

  factory CardIntroductionStore.resolve() {
    final override = debugOverride;
    if (override != null) return override;
    if (getIt.isRegistered<CardIntroductionStore>()) {
      return getIt<CardIntroductionStore>();
    }
    return _fallback;
  }

  final Set<String> _introduced = {};
  final Set<String> _retired = {};
  final Map<String, int> _introducedBySource = {};

  void resetForTest() {
    _introduced.clear();
    _retired.clear();
    _introducedBySource.clear();
  }

  bool isFormallyEligibleWord(SrsWord word) {
    if (word.isSuspended || word.isBuried) return false;
    if (_retired.contains(word.wordId)) return false;
    if (_introduced.contains(word.wordId)) return true;
    return eligibility.isFormallyEligible(stored: null, reps: word.reps);
  }

  bool isIntroducedCard({
    required String sourceId,
    required int cardId,
  }) {
    return _introduced.contains(_cardToken(sourceId, cardId));
  }

  int introducedCountForSource(String sourceId) {
    return _introducedBySource[sourceId] ?? 0;
  }

  Set<int> introducedCardIdsForSource(String sourceId) {
    final prefix = 'card:$sourceId:';
    final ids = <int>{};
    for (final token in _introduced) {
      if (!token.startsWith(prefix)) continue;
      final id = int.tryParse(token.substring(prefix.length));
      if (id != null) ids.add(id);
    }
    return ids;
  }

  Future<void> markFromLesson({
    required String wordId,
    required String lessonId,
  }) async {
    final key = CardIntroductionEligibility.keyFromLessonAndWordId(
      lessonId: lessonId,
      wordId: wordId,
    );
    if (key == null) return;
    final courseId = key.backend == AnkiBackendKind.official
        ? CardIntroductionEligibility.courseIdForOfficialSource(key.sourceId)
        : CardIntroductionEligibility.courseIdForLegacyImport(key.sourceId);
    final dao = _dao;
    if (dao != null) {
      // Persist first: a failed write must not optimistically mark the card
      // as introduced anywhere (maintainability plan §7.4).
      await dao.upsertIntroduction(
        courseId: courseId,
        key: key,
        status: CardIntroductionStatus.introduced,
        introducedBy: CardIntroducedBy.course,
        introducedAt: DateTime.now(),
        firstLessonId: lessonId,
        lastStudiedAt: DateTime.now(),
      );
    }
    _rememberIntroduced(
      wordId: wordId,
      sourceId: key.sourceId,
      cardId: key.cardId,
    );
  }

  Future<void> seedLegacyImport({
    required String importId,
    required List<AnkiCardData> cards,
    Set<int> revlogCardIds = const {},
  }) async {
    final courseId =
        CardIntroductionEligibility.courseIdForLegacyImport(importId);
    for (final card in cards) {
      final key = CanonicalCardKey(
        backend: AnkiBackendKind.legacyTurna,
        profileId: CardIntroductionEligibility.defaultProfileId,
        sourceId: importId,
        cardId: card.id,
      );
      final status = eligibility.initialStatus(
        reps: card.reps,
        hasRevlog: revlogCardIds.contains(card.id),
      );
      await _dao?.ensureInitial(
        courseId: courseId,
        key: key,
        status: status,
        introducedBy: status == CardIntroductionStatus.introduced
            ? CardIntroducedBy.importedHistory
            : null,
        introducedAt:
            status == CardIntroductionStatus.introduced ? DateTime.now() : null,
      );
      if (status == CardIntroductionStatus.introduced) {
        _rememberIntroduced(
          wordId: 'anki-$importId-c${card.id}',
          sourceId: importId,
          cardId: card.id,
        );
      }
    }
  }

  Future<void> seedOfficialProjection({
    required String sourceId,
    required Iterable<int> cardIds,
  }) async {
    final courseId =
        CardIntroductionEligibility.courseIdForOfficialSource(sourceId);
    for (final cardId in cardIds) {
      final key = CanonicalCardKey(
        backend: AnkiBackendKind.official,
        profileId: CardIntroductionEligibility.defaultProfileId,
        sourceId: sourceId,
        cardId: cardId,
      );
      await _dao?.ensureInitial(
        courseId: courseId,
        key: key,
        status: CardIntroductionStatus.unintroduced,
      );
    }
  }

  void _rememberIntroduced({
    required String wordId,
    required String sourceId,
    required int cardId,
  }) {
    final wasNew = _introduced.add(wordId);
    _introduced.add(_cardToken(sourceId, cardId));
    if (wasNew) {
      _introducedBySource[sourceId] = (_introducedBySource[sourceId] ?? 0) + 1;
    }
    _changes.add(
      CardIntroductionChanged(
        sourceId: sourceId,
        cardId: cardId,
        kind: CardIntroductionChangeKind.introduced,
      ),
    );
  }

  String _cardToken(String sourceId, int cardId) => 'card:$sourceId:$cardId';
}
