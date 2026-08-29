import 'dart:convert';

import 'package:turna/application/anki_official/contract/official_anki_errors.dart';

const int kOfficialAnkiContractMajor = 1;
const int kOfficialAnkiContractMinor = 9;

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
  static const describeNextStates = 'DESCRIBE_NEXT_STATES';
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

  static const engineInfoId = 1;
  static const openCollectionId = 2;
  static const closeCollectionId = 3;
  static const checkCollectionId = 4;
  static const importPackageId = 5;
  static const latestProgressId = 6;
  static const cancelOperationId = 7;
  static const listDeckTreeId = 8;
  static const createBackupId = 17;
  static const searchCardsPageId = 18;
  static const getNoteCardsBatchId = 19;
  static const getCardDescriptorsBatchId = 20;
  static const restoreBackupId = 21;
  static const renderCardId = 10;
  static const compareTypedAnswerId = 22;
  static const extractClozeForTypingId = 23;
  static const getProjectionSchemasId = 24;
  static const beginProjectionReadId = 25;
  static const getProjectionRowsBatchId = 26;
  static const setCurrentDeckId = 11;
  static const getReviewQueueId = 12;
  static const describeNextStatesId = 13;
  static const answerCardId = 14;
  static const getUndoStatusId = 15;
  static const undoId = 16;
  static const redoId = 27;
  static const buryOrSuspendCardsId = 28;
  static const countsForDeckTodayId = 29;
  static const congratsInfoId = 30;
  static const deleteNotesId = 31;
  static const deleteCardsId = 32;
  static const statsForCardsBatchId = 33;
  static const scheduleCardsAsNewId = 34;
  static const answerAheadCardsId = 35;
  static const ensureTodayNewQuotaId = 36;

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
    describeNextStates,
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
  };

  static int idFor(String name) {
    switch (name) {
      case engineInfo:
        return engineInfoId;
      case openCollection:
        return openCollectionId;
      case closeCollection:
        return closeCollectionId;
      case checkCollection:
        return checkCollectionId;
      case importPackage:
        return importPackageId;
      case latestProgress:
        return latestProgressId;
      case cancelOperation:
        return cancelOperationId;
      case listDeckTree:
        return listDeckTreeId;
      case createBackup:
        return createBackupId;
      case restoreBackup:
        return restoreBackupId;
      case searchCardsPage:
        return searchCardsPageId;
      case getNoteCardsBatch:
        return getNoteCardsBatchId;
      case getCardDescriptorsBatch:
        return getCardDescriptorsBatchId;
      case renderCard:
        return renderCardId;
      case compareTypedAnswer:
        return compareTypedAnswerId;
      case extractClozeForTyping:
        return extractClozeForTypingId;
      case getProjectionSchemas:
        return getProjectionSchemasId;
      case beginProjectionRead:
        return beginProjectionReadId;
      case getProjectionRowsBatch:
        return getProjectionRowsBatchId;
      case setCurrentDeck:
        return setCurrentDeckId;
      case getReviewQueue:
        return getReviewQueueId;
      case describeNextStates:
        return describeNextStatesId;
      case answerCard:
        return answerCardId;
      case getUndoStatus:
        return getUndoStatusId;
      case undo:
        return undoId;
      case redo:
        return redoId;
      case buryOrSuspendCards:
        return buryOrSuspendCardsId;
      case countsForDeckToday:
        return countsForDeckTodayId;
      case congratsInfo:
        return congratsInfoId;
      case deleteNotes:
        return deleteNotesId;
      case deleteCards:
        return deleteCardsId;
      case statsForCardsBatch:
        return statsForCardsBatchId;
      case scheduleCardsAsNew:
        return scheduleCardsAsNewId;
      case answerAheadCards:
        return answerAheadCardsId;
      case ensureTodayNewQuota:
        return ensureTodayNewQuotaId;
      default:
        throw OfficialAnkiException(
          code: OfficialAnkiErrorCode.invalidArgument,
          messageKey: 'official_anki.unknown_operation',
        );
    }
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
