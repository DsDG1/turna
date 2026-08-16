import 'dart:convert';

import 'package:turna/application/anki_official/contract/official_anki_errors.dart';

const int kOfficialAnkiContractMajor = 1;
const int kOfficialAnkiContractMinor = 0;

abstract final class OfficialAnkiOperation {
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
      error = OfficialAnkiException.fromJson(Map<String, Object?>.from(errorRaw));
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
