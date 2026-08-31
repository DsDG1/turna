import 'dart:convert';

import 'package:turna/application/anki_official/contract/official_anki_errors.dart';

const int kOfficialAnkiContractMajor = 1;
const int kOfficialAnkiContractMinor = 12;

abstract final class OfficialAnkiOperation {
  /// Native `GET_REVIEW_QUEUE` accepts `1..=100` (bridge `ops.rs`).
  static const minReviewQueueFetchLimit = 1;
  static const maxReviewQueueFetchLimit = 100;

  static int clampReviewQueueFetchLimit(int fetchLimit) {
    if (fetchLimit < minReviewQueueFetchLimit) {
      return minReviewQueueFetchLimit;
    }
    if (fetchLimit > maxReviewQueueFetchLimit) {
      return maxReviewQueueFetchLimit;
    }
    return fetchLimit;
  }

  static const engineInfo = 'ENGINE_INFO';
  static const openCollection = 'OPEN_COLLECTION';
  static const closeCollection = 'CLOSE_COLLECTION';
  static const checkCollection = 'CHECK_COLLECTION';
  static const createBackup = 'CREATE_BACKUP';
  static const restoreBackup = 'RESTORE_BACKUP';
  static const importPackage = 'IMPORT_PACKAGE';
  static const latestProgress = 'LATEST_PROGRESS';
  static const cancelOperation = 'CANCEL_OPERATION';
  static const listDeckTree = 'LIST_DECK_TREE';
  static const searchCardsPage = 'SEARCH_CARDS_PAGE';
  static const getNoteCardsBatch = 'GET_NOTE_CARDS_BATCH';
  static const getCardDescriptorsBatch = 'GET_CARD_DESCRIPTORS_BATCH';
  static const renderCard = 'RENDER_CARD';
  static const compareTypedAnswer = 'COMPARE_TYPED_ANSWER';
  static const extractClozeForTyping = 'EXTRACT_CLOZE_FOR_TYPING';
  static const getProjectionSchemas = 'GET_PROJECTION_SCHEMAS';
  static const beginProjectionRead = 'BEGIN_PROJECTION_READ';
  static const getProjectionRowsBatch = 'GET_PROJECTION_ROWS_BATCH';
  static const setCurrentDeck = 'SET_CURRENT_DECK';
  static const getReviewQueue = 'GET_REVIEW_QUEUE';
  // DESCRIBE_NEXT_STATES (op 13) stays on the Rust side (append-only
  // policy) but its Dart call face was deleted in doc 39 P1-E: no business
  // caller ever used it — interval labels come from the queue cards.
  static const answerCard = 'ANSWER_CARD';
  static const getUndoStatus = 'GET_UNDO_STATUS';
  static const undo = 'UNDO';
  static const redo = 'REDO';
  static const buryOrSuspendCards = 'BURY_OR_SUSPEND_CARDS';
  static const countsForDeckToday = 'COUNTS_FOR_DECK_TODAY';
  static const congratsInfo = 'CONGRATS_INFO';
  static const deleteNotes = 'DELETE_NOTES';
  static const deleteCards = 'DELETE_CARDS';
  static const statsForCardsBatch = 'STATS_FOR_CARDS_BATCH';
  static const scheduleCardsAsNew = 'SCHEDULE_CARDS_AS_NEW';
  static const answerAheadCards = 'ANSWER_AHEAD_CARDS';
  static const ensureTodayNewQuota = 'ENSURE_TODAY_NEW_QUOTA';
  static const gcUnusedMedia = 'GC_UNUSED_MEDIA';
  static const pruneEmptyMetadata = 'PRUNE_EMPTY_METADATA';
  static const compactCollection = 'COMPACT_COLLECTION';
  static const diffCollectionCheckpoint = 'DIFF_COLLECTION_CHECKPOINT';
  static const getConfig = 'GET_CONFIG';
  static const setConfig = 'SET_CONFIG';

  /// Single source of truth for the wire contract (doc 39 P2): every live
  /// operation name → its stable id, exactly as `contract/operations.md`
  /// defines them. Append-only — ids are never reused or renumbered.
  static const Map<String, int> ids = {
    engineInfo: 1,
    openCollection: 2,
    closeCollection: 3,
    checkCollection: 4,
    importPackage: 5,
    latestProgress: 6,
    cancelOperation: 7,
    listDeckTree: 8,
    renderCard: 10,
    setCurrentDeck: 11,
    getReviewQueue: 12,
    answerCard: 14,
    getUndoStatus: 15,
    undo: 16,
    createBackup: 17,
    searchCardsPage: 18,
    getNoteCardsBatch: 19,
    getCardDescriptorsBatch: 20,
    restoreBackup: 21,
    compareTypedAnswer: 22,
    extractClozeForTyping: 23,
    getProjectionSchemas: 24,
    beginProjectionRead: 25,
    getProjectionRowsBatch: 26,
    redo: 27,
    buryOrSuspendCards: 28,
    countsForDeckToday: 29,
    congratsInfo: 30,
    deleteNotes: 31,
    deleteCards: 32,
    statsForCardsBatch: 33,
    scheduleCardsAsNew: 34,
    answerAheadCards: 35,
    ensureTodayNewQuota: 36,
    gcUnusedMedia: 37,
    pruneEmptyMetadata: 38,
    compactCollection: 39,
    diffCollectionCheckpoint: 40,
    getConfig: 41,
    setConfig: 42,
  };

  static const productionNames = <String>{
    engineInfo,
    openCollection,
    closeCollection,
    checkCollection,
    createBackup,
    restoreBackup,
    importPackage,
    latestProgress,
    cancelOperation,
    listDeckTree,
    searchCardsPage,
    getNoteCardsBatch,
    getCardDescriptorsBatch,
    renderCard,
    compareTypedAnswer,
    extractClozeForTyping,
    getProjectionSchemas,
    beginProjectionRead,
    getProjectionRowsBatch,
    setCurrentDeck,
    getReviewQueue,
    answerCard,
    getUndoStatus,
    undo,
    redo,
    buryOrSuspendCards,
    countsForDeckToday,
    congratsInfo,
    deleteNotes,
    deleteCards,
    statsForCardsBatch,
    scheduleCardsAsNew,
    answerAheadCards,
    ensureTodayNewQuota,
    gcUnusedMedia,
    pruneEmptyMetadata,
    compactCollection,
    diffCollectionCheckpoint,
    getConfig,
    setConfig,
  };

  static int idFor(String name) {
    final id = ids[name];
    if (id == null) {
      throw OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidArgument,
        messageKey: 'official_anki.unknown_operation',
      );
    }
    return id;
  }

}

class OfficialAnkiEnvelopeRequest {
  const OfficialAnkiEnvelopeRequest({
    required this.requestId,
    required this.operation,
    this.payload = const <String, Object?>{},
    this.major = kOfficialAnkiContractMajor,
    this.minor = kOfficialAnkiContractMinor,
  });

  final String requestId;
  final String operation;
  final Map<String, Object?> payload;
  final int major;
  final int minor;

  Map<String, Object?> toJson() => <String, Object?>{
        'contractVersion': <String, int>{'major': major, 'minor': minor},
        'requestId': requestId,
        'operation': operation,
        'payload': payload,
      };

  List<int> encode() => utf8.encode(jsonEncode(toJson()));
}

class OfficialAnkiEngineMeta {
  const OfficialAnkiEngineMeta({
    required this.abiVersion,
    required this.backendCommit,
    required this.contractMajor,
    required this.contractMinor,
  });

  final int abiVersion;
  final String backendCommit;
  final int contractMajor;
  final int contractMinor;

  factory OfficialAnkiEngineMeta.fromJson(Map<String, Object?> json) {
    return OfficialAnkiEngineMeta(
      abiVersion: (json['abiVersion'] as num?)?.toInt() ?? 0,
      backendCommit: json['backendCommit'] as String? ?? '',
      contractMajor: (json['contractMajor'] as num?)?.toInt() ?? 0,
      contractMinor: (json['contractMinor'] as num?)?.toInt() ?? 0,
    );
  }
}

class OfficialAnkiEnvelopeResponse {
  const OfficialAnkiEnvelopeResponse({
    required this.requestId,
    required this.ok,
    required this.engine,
    required this.durationMillis,
    this.payload,
    this.error,
    this.major = kOfficialAnkiContractMajor,
    this.minor = kOfficialAnkiContractMinor,
  });

  final String requestId;
  final bool ok;
  final Map<String, Object?>? payload;
  final OfficialAnkiException? error;
  final OfficialAnkiEngineMeta engine;
  final int durationMillis;
  final int major;
  final int minor;

  factory OfficialAnkiEnvelopeResponse.decode(List<int> bytes) {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.internalError,
        messageKey: 'official_anki.invalid_envelope',
      );
    }
    return OfficialAnkiEnvelopeResponse.fromJson(
      Map<String, Object?>.from(decoded),
    );
  }

  factory OfficialAnkiEnvelopeResponse.fromJson(Map<String, Object?> json) {
    final version = json['contractVersion'];
    var major = kOfficialAnkiContractMajor;
    var minor = kOfficialAnkiContractMinor;
    if (version is Map) {
      major = (version['major'] as num?)?.toInt() ?? major;
      minor = (version['minor'] as num?)?.toInt() ?? minor;
    }
    if (major != kOfficialAnkiContractMajor) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.contractVersionMismatch,
        messageKey: 'official_anki.contract_version_mismatch',
      );
    }
    final engineRaw = json['engine'];
    final engine = engineRaw is Map
        ? OfficialAnkiEngineMeta.fromJson(Map<String, Object?>.from(engineRaw))
        : const OfficialAnkiEngineMeta(
            abiVersion: 0,
            backendCommit: '',
            contractMajor: 0,
            contractMinor: 0,
          );
    OfficialAnkiException? error;
    final errorRaw = json['error'];
    if (errorRaw is Map) {
      error =
          OfficialAnkiException.fromJson(Map<String, Object?>.from(errorRaw));
    }
    Map<String, Object?>? payload;
    final payloadRaw = json['payload'];
    if (payloadRaw is Map) {
      payload = Map<String, Object?>.from(payloadRaw);
    }
    return OfficialAnkiEnvelopeResponse(
      requestId: json['requestId'] as String? ?? '',
      ok: json['ok'] == true,
      payload: payload,
      error: error,
      engine: engine,
      durationMillis: (json['durationMillis'] as num?)?.toInt() ?? 0,
      major: major,
      minor: minor,
    );
  }

  Map<String, Object?> requirePayload() {
    if (!ok || payload == null) {
      throw error ??
          const OfficialAnkiException(
            code: OfficialAnkiErrorCode.internalError,
            messageKey: 'official_anki.empty_payload',
          );
    }
    return payload!;
  }
}
