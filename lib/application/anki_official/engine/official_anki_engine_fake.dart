import 'package:turna/application/anki_official/contract/official_anki_contract.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/engine/official_anki_scheduler_audit.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';

/// In-process engine for tests. Does not reimplement the import saga.
class FakeOfficialAnkiEngine implements OfficialAnkiEngine {
  FakeOfficialAnkiEngine({
    this.backendCommit = '967aa0d578fc75181e292e95326f9b58698da25c',
    this.openCount = 0,
  });

  final String backendCommit;
  int openCount;
  int importCount = 0;
  int noteBatchCalls = 0;
  int descriptorBatchCalls = 0;
  bool cancelRequested = false;
  bool disposed = false;
  String? openProfileId;
  final Map<String, OfficialAnkiImportLog> logsByPackage = {};
  final Map<int, List<int>> cardsByNote = {};
  final Map<int, OfficialAnkiCardDescriptor> cards = {};
  final Map<int, OfficialAnkiRenderedCard> renders = {};
  var renderCount = 0;
  var compareCount = 0;
  bool failImport = false;
  bool failRender = false;

  /// Per-card render failures for unrenderable-card tests
  /// (maintainability plan Wave 2).
  Set<int> failRenderFor = {};
  bool failDeleteNotes = false;
  var collectionGeneration = 1;
  String? projectionToken;
  String? projectionFingerprint;
  final projectionRowOverrides = <int, OfficialAnkiProjectionRow>{};
  final projectionBatchSizes = <int>[];
  var projectionBatchCalls = 0;
  final missingOnRead = <int>{};
  var emitDuplicateRows = false;
  var invalidateSnapshotOnRead = false;
  final projectionSchemaFingerprint = 'fake-basic';
  final deletedNoteIds = <int>{};

  void seedPackage({
    required String packagePath,
    required int notes,
    required int cards,
  }) {
    final noteIds = List<int>.generate(notes, (i) => i + 1);
    final cardIds = <int>[];
    cardsByNote.clear();
    this.cards.clear();
    answeredIds.clear();
    ratedTodayIds.clear();
    officialAnswers = 0;
    failRender = false;
    failRenderFor.clear();
    buried.clear();
    suspended.clear();
    var cardId = 1;
    for (final noteId in noteIds) {
      final ids = <int>[];
      final extra = notes == 1 && cards == 2 ? 2 : 1;
      for (var ord = 0; ord < extra && cardId <= cards; ord++) {
        ids.add(cardId);
        this.cards[cardId] = OfficialAnkiCardDescriptor(
          cardId: cardId,
          noteId: noteId,
          deckId: 1,
          templateOrd: ord,
          noteGuid: 'guid-$noteId',
        );
        cardId++;
      }
      cardsByNote[noteId] = ids;
      cardIds.addAll(ids);
    }
    while (this.cards.length < cards) {
      final id = this.cards.length + 1;
      final noteId = ((id - 1) % notes) + 1;
      this.cards[id] = OfficialAnkiCardDescriptor(
        cardId: id,
        noteId: noteId,
        deckId: 1,
        templateOrd: 0,
        noteGuid: 'guid-$noteId',
      );
      cardsByNote.putIfAbsent(noteId, () => <int>[]).add(id);
    }
    logsByPackage[packagePath] = OfficialAnkiImportLog(
      newNoteIds: noteIds,
      updatedNoteIds: const <int>[],
      duplicateNoteIds: const <int>[],
      conflictingNoteIds: const <int>[],
      noteCount: notes,
      cardCount: this.cards.length,
      operationToken: 'tok-$packagePath',
    );
  }

  @override
  Future<OfficialAnkiEngineInfo> engineInfo() async {
    return OfficialAnkiEngineInfo(
      abiVersion: 1,
      backendCommit: backendCommit,
      contractMajor: kOfficialAnkiContractMajor,
      contractMinor: kOfficialAnkiContractMinor,
      capabilities: {
        OfficialAnkiOperation.engineInfo,
        OfficialAnkiOperation.importPackage,
        OfficialAnkiOperation.searchCardsPage,
        OfficialAnkiOperation.getNoteCardsBatch,
        OfficialAnkiOperation.getCardDescriptorsBatch,
        OfficialAnkiOperation.renderCard,
        OfficialAnkiOperation.compareTypedAnswer,
        OfficialAnkiOperation.extractClozeForTyping,
        OfficialAnkiOperation.listDeckTree,
        OfficialAnkiOperation.getProjectionSchemas,
        OfficialAnkiOperation.beginProjectionRead,
        OfficialAnkiOperation.getProjectionRowsBatch,
        OfficialAnkiOperation.setCurrentDeck,
        OfficialAnkiOperation.getReviewQueue,
        OfficialAnkiOperation.describeNextStates,
        OfficialAnkiOperation.answerCard,
        OfficialAnkiOperation.getUndoStatus,
        OfficialAnkiOperation.undo,
        OfficialAnkiOperation.redo,
        OfficialAnkiOperation.buryOrSuspendCards,
        OfficialAnkiOperation.countsForDeckToday,
        OfficialAnkiOperation.congratsInfo,
        OfficialAnkiOperation.deleteNotes,
        OfficialAnkiOperation.deleteCards,
        OfficialAnkiOperation.statsForCardsBatch,
        OfficialAnkiOperation.scheduleCardsAsNew,
        OfficialAnkiOperation.answerAheadCards,
        OfficialAnkiOperation.ensureTodayNewQuota,
      },
    );
  }

  @override
  Future<void> openProfile(OfficialAnkiPaths paths) async {
    if (openProfileId != null && openProfileId != paths.profileId) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.collectionAlreadyOpen,
        messageKey: 'official_anki.collection_already_open',
      );
    }
    openProfileId = paths.profileId;
    openCount++;
  }

  @override
  Future<void> closeCollection() async {
    openProfileId = null;
  }

  @override
  Future<void> checkCollection() async {}

  @override
  Future<String> createBackup() async => 'bk-fake';

  @override
  Future<void> restoreBackup(String backupId) async {}

  @override
  Future<OfficialAnkiImportLog> importPackage({
    required String packagePath,
    bool withScheduling = true,
    bool withDeckConfigs = true,
  }) async {
    if (cancelRequested) {
      cancelRequested = false;
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.importCancelled,
        messageKey: 'official_anki.import_cancelled',
        recoverable: true,
      );
    }
    if (failImport) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.packageInvalid,
        messageKey: 'official_anki.package_invalid',
      );
    }
    importCount++;
    collectionGeneration += 1;
    projectionToken = null;
    return logsByPackage[packagePath] ??
        const OfficialAnkiImportLog(
          newNoteIds: <int>[1],
          updatedNoteIds: <int>[],
          duplicateNoteIds: <int>[],
          conflictingNoteIds: <int>[],
          noteCount: 1,
          cardCount: 1,
          operationToken: 'tok-default',
        );
  }

  @override
  Future<OfficialAnkiProgress> latestProgress() async {
    return OfficialAnkiProgress(
      stage: cancelRequested ? 'cancelling' : 'idle',
      canCancel: true,
    );
  }

  @override
  Future<void> cancel() async {
    cancelRequested = true;
  }

  @override
  Future<OfficialAnkiCardPage> searchCardsPage({
    String search = '',
    int pageSize = 200,
    String? pageToken,
  }) async {
    final raw = search.trim().toLowerCase();
    final excludeSuspended = raw.contains('-is:suspended');
    final wantSuspended =
        !excludeSuspended && raw.contains('is:suspended');
    final excludeBuried = raw.contains('-is:buried');
    final wantBuried = !excludeBuried && raw.contains('is:buried');
    final excludeMarked = raw.contains('-tag:marked');
    final wantMarked = !excludeMarked && raw.contains('tag:marked');
    final wantStudied = raw.contains('prop:reps>=1') ||
        raw.contains('prop:reps>0');
    final wantRatedToday = raw.contains('rated:1');
    final flagMatch = RegExp(r'(?:^|\s)flag:(\d+)').firstMatch(raw);
    final tagMatch = RegExp(r'(?:^|\s)tag:"([^"]+)"').firstMatch(raw);
    final needle = raw
        .replaceAll('-is:suspended', '')
        .replaceAll('is:suspended', '')
        .replaceAll('-is:buried', '')
        .replaceAll('is:buried', '')
        .replaceAll('-tag:marked', '')
        .replaceAll('tag:marked', '')
        .replaceAll('prop:reps>=1', '')
        .replaceAll('prop:reps>0', '')
        .replaceAll('rated:1', '')
        .replaceAll(RegExp(r'(?:^|\s)flag:\d+'), '')
        .replaceAll(RegExp(r'(?:^|\s)tag:"[^"]+"'), '')
        .trim();
    var ids = cards.keys.toList()..sort();
    if (wantSuspended) {
      ids = ids.where(suspended.contains).toList();
    } else if (excludeSuspended) {
      ids = ids.where((id) => !suspended.contains(id)).toList();
    }
    if (wantBuried) {
      ids = ids.where(buried.contains).toList();
    } else if (excludeBuried) {
      ids = ids.where((id) => !buried.contains(id)).toList();
    }
    if (wantMarked) {
      ids = ids.where((id) => cards[id]?.marked == true).toList();
    } else if (excludeMarked) {
      ids = ids.where((id) => cards[id]?.marked != true).toList();
    }
    if (wantStudied) {
      ids = ids.where(studiedCardIds.contains).toList();
    }
    if (wantRatedToday) {
      ids = ids.where(ratedTodayIds.contains).toList();
    }
    if (flagMatch != null) {
      final flag = int.parse(flagMatch.group(1)!);
      ids = ids.where((id) => cards[id]?.flag == flag).toList();
    }
    if (tagMatch != null) {
      final tag = tagMatch.group(1)!;
      ids = ids
          .where((id) => cards[id]?.tags
              .any((candidate) => candidate.toLowerCase() == tag) == true)
          .toList();
    }
    if (needle.isNotEmpty) {
      ids = [
        for (final id in ids)
          if (id.toString().contains(needle) ||
              'q$id'.contains(needle) ||
              'a$id'.contains(needle) ||
              (cards[id]?.noteGuid ?? '').toLowerCase().contains(needle))
            id,
      ];
    }
    final start = int.tryParse(pageToken ?? '0') ?? 0;
    final end = (start + pageSize).clamp(0, ids.length);
    return OfficialAnkiCardPage(
      cardIds: ids.sublist(start, end),
      nextPageToken: end < ids.length ? '$end' : null,
      totalHint: ids.length,
    );
  }

  @override
  Future<Map<int, List<int>>> getNoteCardsBatch(List<int> noteIds) async {
    noteBatchCalls++;
    return {
      for (final id in noteIds)
        id: List<int>.from(cardsByNote[id] ?? const <int>[]),
    };
  }

  @override
  Future<List<OfficialAnkiCardDescriptor>> getCardDescriptorsBatch(
    List<int> cardIds,
  ) async {
    descriptorBatchCalls++;
    return [
      for (final id in cardIds)
        if (cards[id] case final card?)
          OfficialAnkiCardDescriptor(
            cardId: card.cardId,
            noteId: card.noteId,
            deckId: card.deckId,
            templateOrd: card.templateOrd,
            noteGuid: card.noteGuid,
            queue: card.queue,
            suspended: suspended.contains(id) || card.suspended,
            buried: buried.contains(id) || card.buried,
            flag: card.flag,
            marked: card.marked,
            tags: card.tags,
          ),
    ];
  }

  @override
  Future<OfficialAnkiRenderedCard> renderCard({
    required int cardId,
    bool browser = false,
    bool includeAvTags = true,
  }) async {
    if (failRender || failRenderFor.contains(cardId)) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.renderFailed,
        messageKey: 'official_anki.render_failed',
      );
    }
    renderCount++;
    final seeded = renders[cardId];
    if (seeded != null) return seeded;
    if (cards[cardId] == null) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.cardNotFound,
        messageKey: 'official_anki.card_not_found',
      );
    }
    return OfficialAnkiRenderedCard(
      cardId: cardId,
      questionHtml: 'Q$cardId',
      answerHtml: 'A$cardId',
      questionDisplayHtml: 'Q$cardId',
      answerDisplayHtml: 'A$cardId',
      css: '.card{}',
      templateOrdinal: 0,
      bodyClass: 'card card1',
    );
  }

  @override
  Future<OfficialAnkiTypedComparison> compareTypedAnswer({
    required int cardId,
    required String marker,
    required String provided,
  }) async {
    compareCount++;
    if (cards[cardId] == null && renders[cardId] == null) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.cardNotFound,
        messageKey: 'official_anki.card_not_found',
      );
    }
    if (marker.contains('NoSuchField')) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.typedFieldNotFound,
        messageKey: 'official_anki.typed_field_not_found',
      );
    }
    final expected =
        renders[cardId]?.typedAnswer?.marker == marker ? provided : provided;
    return OfficialAnkiTypedComparison(
      comparisonHtml:
          '<code id=typeans><span class=typeGood>$expected</span></code>',
      hasExpected: true,
    );
  }

  @override
  Future<String> extractClozeForTyping({
    required String text,
    required int ordinal,
  }) async {
    final match = RegExp('\\{\\{c$ordinal::([^}]+)\\}\\}').firstMatch(text);
    final value = match?.group(1) ?? '';
    if (value.isEmpty) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.typedClozeEmpty,
        messageKey: 'official_anki.typed_cloze_empty',
      );
    }
    return value;
  }

  List<OfficialAnkiDeckNode> deckTree = const [
    OfficialAnkiDeckNode(deckId: 1, name: 'Default', level: 0),
  ];

  @override
  Future<List<OfficialAnkiDeckNode>> listDeckTree() async {
    return List<OfficialAnkiDeckNode>.of(deckTree);
  }

  @override
  Future<List<OfficialAnkiProjectionSchema>> getProjectionSchemas({
    List<int> notetypeIds = const <int>[],
    bool includeSamples = false,
    int sampleLimit = 3,
  }) async {
    return [
      OfficialAnkiProjectionSchema(
        notetypeId: 1,
        name: 'Basic',
        kind: 'normal',
        fieldNames: const ['Front', 'Back'],
        templateNames: const ['Card 1'],
        schemaFingerprint: projectionSchemaFingerprint,
        samples: includeSamples
            ? const [
                OfficialAnkiProjectionSample(
                  noteId: 1,
                  fields: ['hello', '你好'],
                ),
              ]
            : const <OfficialAnkiProjectionSample>[],
      ),
    ];
  }

  @override
  Future<OfficialAnkiProjectionSnapshot> beginProjectionRead({
    required String cardSetFingerprint,
    int mappingVersion = 1,
  }) async {
    projectionFingerprint = cardSetFingerprint;
    projectionToken = 'fake-$collectionGeneration-$mappingVersion';
    return OfficialAnkiProjectionSnapshot(
      snapshotToken: projectionToken!,
      collectionGeneration: collectionGeneration,
      backendCommit: backendCommit,
    );
  }

  @override
  Future<OfficialAnkiProjectionPage> getProjectionRowsBatch({
    required List<int> cardIds,
    required String snapshotToken,
  }) async {
    if (cardIds.length > 500) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidArgument,
        messageKey: 'official_anki.invalid_argument',
      );
    }
    if (snapshotToken != projectionToken) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.projectionSnapshotStale,
        messageKey: 'official_anki.projection_snapshot_stale',
        recoverable: true,
      );
    }
    if (invalidateSnapshotOnRead) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.projectionSnapshotStale,
        messageKey: 'official_anki.projection_snapshot_stale',
        recoverable: true,
      );
    }
    projectionBatchCalls += 1;
    projectionBatchSizes.add(cardIds.length);
    final rows = <OfficialAnkiProjectionRow>[];
    final missing = <int>[];
    for (final id in cardIds) {
      if (missingOnRead.contains(id)) {
        missing.add(id);
        continue;
      }
      final override = projectionRowOverrides[id];
      if (override != null) {
        rows.add(override);
        continue;
      }
      final card = cards[id];
      if (card == null) {
        missing.add(id);
        continue;
      }
      rows.add(
        OfficialAnkiProjectionRow(
          cardId: id,
          noteId: card.noteId,
          noteGuid: card.noteGuid ?? 'guid-$id',
          notetypeId: 1,
          deckId: card.deckId,
          deckPath: const ['Default'],
          templateOrdinal: card.templateOrd,
          tags: const <String>[],
          fields: const ['hello', '你好'],
          sourceFingerprint: 'row-$id',
        ),
      );
    }
    if (emitDuplicateRows && rows.isNotEmpty) {
      rows.add(rows.first);
    }
    return OfficialAnkiProjectionPage(rows: rows, missingCardIds: missing);
  }

  var queueEpoch = 0;
  var sessionSerial = 0;
  String? activeSessionId;
  final issuedTokens = <String, int>{};
  final consumedTokens = <String>{};
  var officialAnswers = 0;
  var officialUndos = 0;
  var officialRedos = 0;
  var lastMillisecondsTaken = 0;
  var currentDeckId = 1;
  final buried = <int>{};
  final suspended = <int>{};
  /// Cards with imported history (cards.reps >= 1) — matched by the
  /// `prop:reps>=1` search term (imported-history introduction seeding).
  final studiedCardIds = <int>{};
  final answeredIds = <int>{};
  /// Cards Official-rated on the fake "today" — `rated:1` search.
  final ratedTodayIds = <int>{};
  int? newPerDayLimit;

  @override
  Future<void> setCurrentDeck(int deckId) async {
    currentDeckId = deckId;
    _invalidateTokens();
  }

  @override
  Future<OfficialReviewQueue> getReviewQueue({int fetchLimit = 1}) async {
    if (fetchLimit < 1 || fetchLimit > 100) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidArgument,
        messageKey: 'official_anki.invalid_argument',
      );
    }
    _invalidateTokens();
    final ids = cards.entries
        .where(
          (entry) =>
              !buried.contains(entry.key) &&
              !suspended.contains(entry.key) &&
              !answeredIds.contains(entry.key) &&
              entry.value.deckId == currentDeckId,
        )
        .map((entry) => entry.key)
        .toList()
      ..sort();
    final dayCapped =
        newPerDayLimit != null && officialAnswers >= newPerDayLimit!;
    if (ids.isEmpty || dayCapped) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.queueEmpty,
        messageKey: 'official_anki.queue_empty',
      );
    }
    final take = ids.take(fetchLimit).toList();
    final queued = <OfficialReviewQueueCard>[];
    for (final id in take) {
      final token = 'tok-$activeSessionId-$queueEpoch-$id';
      issuedTokens[token] = id;
      queued.add(
        OfficialReviewQueueCard(
          cardId: id,
          noteId: cards[id]?.noteId ?? id,
          deckId: cards[id]?.deckId ?? currentDeckId,
          templateOrdinal: cards[id]?.templateOrd ?? 0,
          queueKind: 'review',
          answerToken: token,
          labels: const OfficialReviewIntervalLabels(
            again: '1m',
            hard: '6d',
            good: '15d',
            easy: '1mo',
          ),
        ),
      );
    }
    return OfficialReviewQueue(
      sessionId: activeSessionId!,
      queueEpoch: queueEpoch,
      newCount: take.length,
      learningCount: 0,
      reviewCount: 0,
      cards: queued,
    );
  }

  @override
  Future<OfficialReviewIntervalLabels> describeNextStates({
    required String sessionId,
    required int queueEpoch,
    required String answerToken,
  }) async {
    if (sessionId != activeSessionId ||
        queueEpoch != this.queueEpoch ||
        !issuedTokens.containsKey(answerToken) ||
        consumedTokens.contains(answerToken)) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.schedulingContextStale,
        messageKey: 'official_anki.scheduling_context_stale',
      );
    }
    return const OfficialReviewIntervalLabels(
      again: '1m',
      hard: '6d',
      good: '15d',
      easy: '1mo',
    );
  }

  var failNextAnswerUnwritten = false;
  var failNextAnswerUnknown = false;
  String? lastClientMutationId;

  @override
  Future<OfficialAnswerResult> answerCard({
    required String sessionId,
    required int queueEpoch,
    required String answerToken,
    required int cardId,
    required String rating,
    required int millisecondsTaken,
    int? answeredAtMillis,
    String? clientMutationId,
  }) async {
    if (millisecondsTaken < 0 || millisecondsTaken > 24 * 60 * 60 * 1000) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidArgument,
        messageKey: 'official_anki.invalid_argument',
      );
    }
    final expected = issuedTokens[answerToken];
    if (expected == null ||
        consumedTokens.contains(answerToken) ||
        sessionId != activeSessionId ||
        queueEpoch != this.queueEpoch ||
        expected != cardId) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.schedulingContextStale,
        messageKey: 'official_anki.scheduling_context_stale',
      );
    }
    if (failNextAnswerUnwritten) {
      failNextAnswerUnwritten = false;
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.answerFailed,
        messageKey: 'official_anki.answer_failed',
        recoverable: true,
      );
    }
    if (failNextAnswerUnknown) {
      failNextAnswerUnknown = false;
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.answerCommitUnknown,
        messageKey: 'official_anki.answer_commit_unknown',
        recoverable: true,
      );
    }
    consumedTokens.add(answerToken);
    officialAnswers += 1;
    answeredIds.add(cardId);
    ratedTodayIds.add(cardId);
    lastMillisecondsTaken = millisecondsTaken;
    lastClientMutationId = clientMutationId;
    OfficialAnkiSchedulerAudit.officialSchedulerAnswers += 1;
    _invalidateTokens();
    return OfficialAnswerResult(
      cardId: cardId,
      queue: rating,
      revlogCount: officialAnswers,
      millisecondsTaken: millisecondsTaken,
      clientMutationId: clientMutationId,
      rating: rating,
      queueEpoch: this.queueEpoch,
      committed: true,
    );
  }

  @override
  Future<OfficialUndoStatus> getUndoStatus() async {
    return OfficialUndoStatus(
      canUndo: officialAnswers > officialUndos,
      canRedo: officialUndos > officialRedos,
    );
  }

  @override
  Future<OfficialMutationResult> undo() async {
    if (officialAnswers <= officialUndos) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.undoUnavailable,
        messageKey: 'official_anki.undo_unavailable',
      );
    }
    officialUndos += 1;
    OfficialAnkiSchedulerAudit.officialSchedulerUndo += 1;
    _invalidateTokens();
    return OfficialMutationResult(
        ok: true, undone: true, queueEpoch: queueEpoch);
  }

  @override
  Future<OfficialMutationResult> redo() async {
    if (officialUndos <= officialRedos) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.redoUnavailable,
        messageKey: 'official_anki.redo_unavailable',
      );
    }
    officialRedos += 1;
    OfficialAnkiSchedulerAudit.officialSchedulerRedo += 1;
    _invalidateTokens();
    return OfficialMutationResult(
        ok: true, redone: true, queueEpoch: queueEpoch);
  }

  @override
  Future<OfficialDeckCounts> countsForDeckToday(int deckId) async {
    return OfficialDeckCounts(
      deckId: deckId,
      newCount: officialAnswers,
      reviewCount: officialAnswers,
    );
  }

  @override
  Future<OfficialCongratsInfo> congratsInfo() async {
    final remaining =
        cards.keys.any((id) => !buried.contains(id) && !suspended.contains(id));
    return OfficialCongratsInfo(
      learnRemaining: remaining ? 1 : 0,
      reviewRemaining: remaining,
      newRemaining: remaining,
      haveSchedBuried: buried.isNotEmpty,
      haveUserBuried: buried.isNotEmpty,
      isFilteredDeck: false,
      secsUntilNextLearn: remaining ? 60 : 86400,
    );
  }

  @override
  Future<void> buryOrSuspendCards({
    required OfficialBuryOrSuspendAction action,
    List<int> cardIds = const <int>[],
    int? deckId,
  }) async {
    switch (action) {
      case OfficialBuryOrSuspendAction.buryUser:
      case OfficialBuryOrSuspendAction.burySched:
        buried.addAll(cardIds);
      case OfficialBuryOrSuspendAction.unburyDeckAll:
      case OfficialBuryOrSuspendAction.unburyDeckSchedOnly:
      case OfficialBuryOrSuspendAction.unburyDeckUserOnly:
        buried.clear();
      case OfficialBuryOrSuspendAction.suspend:
        suspended.addAll(cardIds);
      case OfficialBuryOrSuspendAction.restoreCards:
        for (final id in cardIds) {
          suspended.remove(id);
        }
    }
    OfficialAnkiSchedulerAudit.officialSchedulerBurySuspend += 1;
    _invalidateTokens();
  }

  @override
  Future<int> deleteNotes(List<int> noteIds) async {
    if (failDeleteNotes) {
      throw StateError('simulated collection deleteNotes failure');
    }
    final noteIdSet = noteIds.toSet();
    final removedCards = <int>[];
    cards.removeWhere((cardId, card) {
      if (!noteIdSet.contains(card.noteId)) return false;
      removedCards.add(cardId);
      return true;
    });
    cardsByNote.removeWhere((noteId, _) => noteIdSet.contains(noteId));
    for (final cardId in removedCards) {
      buried.remove(cardId);
      suspended.remove(cardId);
      answeredIds.remove(cardId);
    }
    deletedNoteIds.addAll(noteIdSet);
    collectionGeneration += 1;
    projectionToken = null;
    _invalidateTokens();
    return removedCards.length;
  }

  @override
  Future<int> deleteCards(List<int> cardIds) async {
    if (failDeleteNotes) {
      throw StateError('simulated collection deleteCards failure');
    }
    final requested = cardIds.toSet();
    final removedNoteIds = <int>{};
    var removed = 0;
    cards.removeWhere((cardId, card) {
      if (!requested.contains(cardId)) return false;
      removedNoteIds.add(card.noteId);
      removed++;
      return true;
    });
    for (final cardId in requested) {
      buried.remove(cardId);
      suspended.remove(cardId);
      answeredIds.remove(cardId);
    }
    for (final noteId in removedNoteIds) {
      final remaining = cards.values
          .where((card) => card.noteId == noteId)
          .map((card) => card.cardId)
          .toList();
      if (remaining.isEmpty) {
        cardsByNote.remove(noteId);
        deletedNoteIds.add(noteId);
      } else {
        cardsByNote[noteId] = remaining;
      }
    }
    collectionGeneration += 1;
    projectionToken = null;
    _invalidateTokens();
    return removed;
  }

  @override
  Future<OfficialAnkiStatsBatch> statsForCardsBatch(List<int> cardIds) async {
    final requested = cardIds.toSet();
    final found = requested.where(cards.containsKey).toSet();
    final suspendedCount = found.where(suspended.contains).length;
    final buriedCount = found.where(buried.contains).length;
    final active = found.length - suspendedCount - buriedCount;
    final reviewed = found.where(answeredIds.contains).length;
    return OfficialAnkiStatsBatch(
      requestedCardCount: requested.length,
      foundCardCount: found.length,
      newCards: active,
      learningCards: 0,
      reviewCards: 0,
      suspendedCards: suspendedCount,
      buriedCards: buriedCount,
      todayAnswerCount: reviewed,
      todayLearnCount: 0,
      todayReviewCount: reviewed,
      todayRelearnCount: 0,
      forecastDueToday: 0,
      forecastDue7Days: 0,
      forecastDue30Days: 0,
      revlogCount: reviewed,
      retentionPassed: reviewed,
      retentionFailed: 0,
    );
  }

  @override
  Future<int> scheduleCardsAsNew(List<int> cardIds) async {
    final found = cardIds.toSet().where(cards.containsKey).toSet();
    answeredIds.removeAll(found);
    buried.removeAll(found);
    collectionGeneration += 1;
    projectionToken = null;
    _invalidateTokens();
    return found.length;
  }

  final List<OfficialAheadAnswer> aheadAnswers = [];

  @override
  Future<int> answerAheadCards(List<OfficialAheadAnswer> answers) async {
    var n = 0;
    for (final answer in answers) {
      if (answer.cardId <= 0) continue;
      if (cards.isNotEmpty && !cards.containsKey(answer.cardId)) continue;
      aheadAnswers.add(answer);
      answeredIds.add(answer.cardId);
      ratedTodayIds.add(answer.cardId);
      officialAnswers += 1;
      OfficialAnkiSchedulerAudit.officialSchedulerAnswers += 1;
      n++;
    }
    _invalidateTokens();
    return n;
  }

  @override
  Future<int> ensureTodayNewQuota({
    required int deckId,
    required int neededNew,
  }) async {
    if (neededNew <= 0) return 0;
    if (deckId <= 0) return 0;
    final currentLimit = newPerDayLimit;
    if (currentLimit == null) return 0;
    final remaining = (currentLimit - officialAnswers).clamp(0, currentLimit);
    if (remaining >= neededNew) return 0;
    final extra = neededNew - remaining;
    newPerDayLimit = currentLimit + extra;
    return extra;
  }

  void _invalidateTokens() {
    issuedTokens.clear();
    queueEpoch += 1;
    sessionSerial += 1;
    activeSessionId = 'session-$sessionSerial';
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    openProfileId = null;
  }
}
