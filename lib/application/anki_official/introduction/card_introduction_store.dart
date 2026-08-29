import 'dart:async';

import 'package:turna/application/anki_official/introduction/card_introduction_eligibility.dart';
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
///
/// P1: due visibility no longer reads the in-memory set at all — the
/// scheduler itself locks unintroduced cards (see the lock reconciler), so
/// the memory set is only a same-session cache. Anything that must not
/// depend on process lifetime (completion unlocking, lock reconciliation)
/// reads the ledger through [introducedCardIdsFromLedger] instead.
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

  /// Introduced card ids of [sourceId] from the durable ledger — the
  /// process-lifetime-safe read for completion unlocking and lock
  /// reconciliation. Test instances without a DAO fall back to the
  /// in-memory set.
  Future<Set<int>> introducedCardIdsFromLedger(String sourceId) async {
    final dao = _dao;
    if (dao == null) return introducedCardIdsForSource(sourceId);
    return dao.introducedCardIdsForSource(sourceId: sourceId);
  }

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

  void _recountIntroducedBySource() {
    _introducedBySource.clear();
    for (final token in _introduced) {
      if (!token.startsWith(_cardTokenPrefix)) continue;
      final rest = token.substring(_cardTokenPrefix.length);
      final separator = rest.lastIndexOf(':');
      if (separator < 0) continue;
      if (int.tryParse(rest.substring(separator + 1)) == null) continue;
      final sourceId = rest.substring(0, separator);
      _introducedBySource[sourceId] =
          (_introducedBySource[sourceId] ?? 0) + 1;
    }
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

  /// Introduces one Official card by its structured projection identity
  /// (P0). Unlike [markFromLesson] this never parses an id out of a string:
  /// the caller holds the projection-index row (source, card, wordId) it
  /// wants introduced.
  Future<void> markIntroducedCard({
    required String sourceId,
    required int cardId,
    required String wordId,
    required String lessonId,
  }) async {
    final key = CanonicalCardKey(
      backend: AnkiBackendKind.official,
      profileId: CardIntroductionEligibility.defaultProfileId,
      sourceId: sourceId,
      cardId: cardId,
    );
    final courseId =
        CardIntroductionEligibility.courseIdForOfficialSource(sourceId);
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
      sourceId: sourceId,
      cardId: cardId,
    );
  }


  /// Seeds the introduction ledger for a freshly published projection.
  ///
  /// Cards whose imported history proves they were already studied
  /// ([studiedCardIds], collected via the `prop:reps>=1` collection search)
  /// seed as introduced — `initialStatus` is the single rule. Seeded rows
  /// fold into memory silently (no [changes] event): at publish time the
  /// due repository does not track the source yet, and every consumer
  /// re-hydrates at entry.
  Future<void> seedOfficialProjection({
    required String sourceId,
    required Iterable<int> cardIds,
    Set<int> studiedCardIds = const {},
  }) async {
    final courseId =
        CardIntroductionEligibility.courseIdForOfficialSource(sourceId);
    var memoryAdded = false;
    for (final cardId in cardIds) {
      final key = CanonicalCardKey(
        backend: AnkiBackendKind.official,
        profileId: CardIntroductionEligibility.defaultProfileId,
        sourceId: sourceId,
        cardId: cardId,
      );
      final studied = studiedCardIds.contains(cardId);
      await _dao?.ensureInitial(
        courseId: courseId,
        key: key,
        status: eligibility.initialStatus(reps: studied ? 1 : 0),
        introducedBy:
            studied ? CardIntroducedBy.importedHistory : null,
        introducedAt: studied ? DateTime.now() : null,
      );
      if (studied && _introduced.add(_cardToken(sourceId, cardId))) {
        memoryAdded = true;
      }
    }
    if (memoryAdded) _recountIntroducedBySource();
  }

  /// Self-healing backfill (01-due-state.md): imported history proves these
  /// cards were already studied, so ledger rows seeded `unintroduced` are
  /// upgraded to introduced. Already-introduced and retired rows are left
  /// untouched. Persist first; only rows that actually changed are folded
  /// into memory and announced via [changes] so the due repository can
  /// refresh its snapshot.
  Future<void> adoptImportedHistory({
    required String sourceId,
    required Iterable<int> cardIds,
  }) async {
    final courseId =
        CardIntroductionEligibility.courseIdForOfficialSource(sourceId);
    final dao = _dao;
    for (final cardId in cardIds) {
      final key = CanonicalCardKey(
        backend: AnkiBackendKind.official,
        profileId: CardIntroductionEligibility.defaultProfileId,
        sourceId: sourceId,
        cardId: cardId,
      );
      final changed = dao == null ||
          await dao.adoptImportedHistory(
            courseId: courseId,
            key: key,
            adoptedAt: DateTime.now(),
          );
      if (!changed) continue;
      _rememberIntroducedCard(sourceId: sourceId, cardId: cardId);
    }
  }

  void _rememberIntroduced({
    required String wordId,
    required String sourceId,
    required int cardId,
  }) {
    _introduced.add(wordId);
    _rememberIntroducedCard(sourceId: sourceId, cardId: cardId);
  }

  void _rememberIntroducedCard({
    required String sourceId,
    required int cardId,
  }) {
    // Count once per distinct CARD, not per word-id alias — hydration
    // merges card tokens too, so the count must be card-token based.
    final wasNew = _introduced.add(_cardToken(sourceId, cardId));
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

  static const _cardTokenPrefix = 'card:';
}
