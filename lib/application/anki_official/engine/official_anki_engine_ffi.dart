import 'dart:convert';

import 'package:turna/application/anki_official/contract/official_anki_contract.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/engine/official_anki_scheduler_audit.dart';
import 'package:turna/application/anki_official/engine/official_anki_native_transport.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';

typedef OfficialAnkiNativeCall = OfficialAnkiEnvelopeResponse Function({
  required int operationId,
  required OfficialAnkiEnvelopeRequest request,
});

/// Production FFI adapter. Tests may inject [nativeCall]; production uses
/// [OfficialAnkiNativeTransport.open].
class FfiOfficialAnkiEngine implements OfficialAnkiEngine {
  FfiOfficialAnkiEngine({required this.nativeCall})
      : transport = null,
        handle = 0;

  FfiOfficialAnkiEngine.connect(OfficialAnkiNativeTransport this.transport)
      : nativeCall = null,
        handle = transport.engineNew();

  final OfficialAnkiNativeCall? nativeCall;
  final OfficialAnkiNativeTransport? transport;
  final int handle;
  var _requestSerial = 0;
  OfficialAnkiPaths? _paths;
  bool _closed = false;
  Set<String>? _capabilities;

  OfficialAnkiEnvelopeResponse _call(
    String operation, [
    Map<String, Object?>? payload,
  ]) {
    _requestSerial += 1;
    final request = OfficialAnkiEnvelopeRequest(
      requestId: 'dart-$_requestSerial',
      operation: operation,
      payload: payload ?? const <String, Object?>{},
    );
    final OfficialAnkiEnvelopeResponse response;
    if (transport != null) {
      response = transport!.call(
        handle,
        OfficialAnkiOperation.idFor(operation),
        request,
      );
    } else {
      response = nativeCall!(
        operationId: OfficialAnkiOperation.idFor(operation),
        request: request,
      );
    }
    if (response.engine.contractMajor != kOfficialAnkiContractMajor) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.contractVersionMismatch,
        messageKey: 'official_anki.contract_version_mismatch',
      );
    }
    return response;
  }

  @override
  Future<OfficialAnkiEngineInfo> engineInfo() async {
    final payload = _call(OfficialAnkiOperation.engineInfo).requirePayload();
    final info = OfficialAnkiEngineInfo.fromJson(payload);
    _capabilities = info.capabilities;
    return info;
  }

  @override
  Future<void> openProfile(OfficialAnkiPaths paths) async {
    await paths.ensureLayout();
    try {
      _call(
        OfficialAnkiOperation.openCollection,
        paths.openPayload(backendCommit: ''),
      ).requirePayload();
      _paths = paths;
    } on OfficialAnkiException catch (error) {
      if (error.code == OfficialAnkiErrorCode.collectionAlreadyOpen) {
        _paths = paths;
        return;
      }
      _paths = null;
      rethrow;
    } catch (_) {
      _paths = null;
      rethrow;
    }
  }

  @override
  Future<void> closeCollection() async {
    _call(OfficialAnkiOperation.closeCollection);
    _paths = null;
  }

  @override
  Future<void> checkCollection() async {
    _call(OfficialAnkiOperation.checkCollection);
  }

  @override
  Future<String> createBackup() async {
    final payload = _call(OfficialAnkiOperation.createBackup).requirePayload();
    return payload['backupId'] as String? ?? 'bk';
  }

  @override
  Future<void> restoreBackup(String backupId) async {
    _call(OfficialAnkiOperation.restoreBackup, {'backup_id': backupId});
  }

  @override
  Future<OfficialAnkiImportLog> importPackage({
    required String packagePath,
    bool withScheduling = true,
    bool withDeckConfigs = true,
  }) async {
    final payload = _call(OfficialAnkiOperation.importPackage, {
      'package_path': packagePath,
      'with_scheduling': withScheduling,
      'with_deck_configs': withDeckConfigs,
    }).requirePayload();
    return OfficialAnkiImportLog.fromJson(payload);
  }

  @override
  Future<OfficialAnkiProgress> latestProgress() async {
    final payload = _call(OfficialAnkiOperation.latestProgress).requirePayload();
    final wantAbort = payload['want_abort'] == true;
    final busy = payload['can_cancel'] == true;
    return OfficialAnkiProgress(
      stage: wantAbort
          ? 'cancelling'
          : (payload['operation_kind'] as String? ?? 'idle'),
      canCancel: busy,
    );
  }

  @override
  Future<void> cancel() async {
    final native = transport;
    if (native != null && handle != 0) {
      native.cancel(handle);
      return;
    }
    _call(OfficialAnkiOperation.cancelOperation);
  }

  @override
  Future<OfficialAnkiCardPage> searchCardsPage({
    String search = '',
    int pageSize = 200,
    String? pageToken,
  }) async {
    final payload = _call(OfficialAnkiOperation.searchCardsPage, {
      'search': search,
      'page_size': pageSize,
      if (pageToken != null) 'page_token': pageToken,
    }).requirePayload();
    return OfficialAnkiCardPage.fromJson(payload);
  }

  @override
  Future<Map<int, List<int>>> getNoteCardsBatch(List<int> noteIds) async {
    final payload = _call(OfficialAnkiOperation.getNoteCardsBatch, {
      'note_ids': noteIds,
    }).requirePayload();
    final notes = payload['notes'];
    final out = <int, List<int>>{};
    if (notes is List) {
      for (final item in notes) {
        if (item is Map) {
          final noteId = (item['noteId'] as num).toInt();
          final cards = item['cardIds'];
          out[noteId] = cards is List
              ? cards.whereType<num>().map((n) => n.toInt()).toList()
              : const <int>[];
        }
      }
    }
    return out;
  }

  @override
  Future<List<OfficialAnkiCardDescriptor>> getCardDescriptorsBatch(
    List<int> cardIds,
  ) async {
    final payload = _call(OfficialAnkiOperation.getCardDescriptorsBatch, {
      'card_ids': cardIds,
    }).requirePayload();
    final cards = payload['cards'];
    if (cards is! List) return const <OfficialAnkiCardDescriptor>[];
    return cards
        .whereType<Map>()
        .map((item) => OfficialAnkiCardDescriptor.fromJson(
              Map<String, Object?>.from(item),
            ))
        .toList();
  }

  @override
  Future<OfficialAnkiRenderedCard> renderCard({
    required int cardId,
    bool browser = false,
    bool includeAvTags = true,
  }) async {
    final payload = _call(OfficialAnkiOperation.renderCard, {
      'cardId': cardId,
      'browser': browser,
      'includeAvTags': includeAvTags,
    }).requirePayload();
    return OfficialAnkiRenderedCard.fromJson(payload);
  }

  @override
  Future<OfficialAnkiTypedComparison> compareTypedAnswer({
    required int cardId,
    required String marker,
    required String provided,
  }) async {
    final payload = _call(OfficialAnkiOperation.compareTypedAnswer, {
      'cardId': cardId,
      'marker': marker,
      'provided': provided,
    }).requirePayload();
    return OfficialAnkiTypedComparison.fromJson(payload);
  }

  @override
  Future<String> extractClozeForTyping({
    required String text,
    required int ordinal,
  }) async {
    final payload = _call(OfficialAnkiOperation.extractClozeForTyping, {
      'text': text,
      'ordinal': ordinal,
    }).requirePayload();
    return payload['text'] as String? ?? '';
  }

  @override
  Future<List<OfficialAnkiDeckNode>> listDeckTree() async {
    final payload = _call(OfficialAnkiOperation.listDeckTree).requirePayload();
    final decks = payload['decks'];
    if (decks is! List) return const <OfficialAnkiDeckNode>[];
    return decks
        .whereType<Map>()
        .map(
          (item) => OfficialAnkiDeckNode.fromJson(Map<String, Object?>.from(item)),
        )
        .toList();
  }

  @override
  Future<List<OfficialAnkiProjectionSchema>> getProjectionSchemas({
    List<int> notetypeIds = const <int>[],
    bool includeSamples = false,
    int sampleLimit = 3,
  }) async {
    final payload = _call(OfficialAnkiOperation.getProjectionSchemas, {
      'notetypeIds': notetypeIds,
      'includeSamples': includeSamples,
      'sampleLimit': sampleLimit,
    }).requirePayload();
    final schemas = payload['schemas'];
    if (schemas is! List) return const <OfficialAnkiProjectionSchema>[];
    return schemas
        .whereType<Map>()
        .map(
          (item) => OfficialAnkiProjectionSchema.fromJson(
            Map<String, Object?>.from(item),
          ),
        )
        .toList();
  }

  @override
  Future<OfficialAnkiProjectionSnapshot> beginProjectionRead({
    required String cardSetFingerprint,
    int mappingVersion = 1,
  }) async {
    final payload = _call(OfficialAnkiOperation.beginProjectionRead, {
      'cardSetFingerprint': cardSetFingerprint,
      'mappingVersion': mappingVersion,
    }).requirePayload();
    return OfficialAnkiProjectionSnapshot.fromJson(payload);
  }

  @override
  Future<OfficialAnkiProjectionPage> getProjectionRowsBatch({
    required List<int> cardIds,
    required String snapshotToken,
  }) async {
    final payload = _call(OfficialAnkiOperation.getProjectionRowsBatch, {
      'cardIds': cardIds,
      'snapshotToken': snapshotToken,
    }).requirePayload();
    return OfficialAnkiProjectionPage.fromJson(payload);
  }

  void _requireScheduler(String operation) {
    final caps = _capabilities;
    if (caps != null && !caps.contains(operation)) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.schedulerCapabilityMissing,
        messageKey: 'official_anki.scheduler_capability_missing',
      );
    }
  }

  @override
  Future<void> setCurrentDeck(int deckId) async {
    _requireScheduler(OfficialAnkiOperation.setCurrentDeck);
    _call(OfficialAnkiOperation.setCurrentDeck, {'deckId': deckId});
  }

  @override
  Future<OfficialReviewQueue> getReviewQueue({int fetchLimit = 1}) async {
    _requireScheduler(OfficialAnkiOperation.getReviewQueue);
    final payload = _call(OfficialAnkiOperation.getReviewQueue, {
      'fetchLimit': fetchLimit,
    }).requirePayload();
    return OfficialReviewQueue.fromJson(payload);
  }

  @override
  Future<OfficialReviewIntervalLabels> describeNextStates({
    required String sessionId,
    required int queueEpoch,
    required String answerToken,
  }) async {
    _requireScheduler(OfficialAnkiOperation.describeNextStates);
    final payload = _call(OfficialAnkiOperation.describeNextStates, {
      'sessionId': sessionId,
      'queueEpoch': queueEpoch,
      'answerToken': answerToken,
    }).requirePayload();
    final labels = payload['labels'];
    if (labels is! Map) {
      officialContractError('labels', labels);
    }
    return OfficialReviewIntervalLabels.fromJson(
      Map<String, Object?>.from(labels),
    );
  }

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
    _requireScheduler(OfficialAnkiOperation.answerCard);
    final payload = _call(OfficialAnkiOperation.answerCard, {
      'sessionId': sessionId,
      'queueEpoch': queueEpoch,
      'answerToken': answerToken,
      'cardId': cardId,
      'rating': rating,
      'millisecondsTaken': millisecondsTaken,
      if (answeredAtMillis != null) 'answeredAtMillis': answeredAtMillis,
      if (clientMutationId != null) 'clientMutationId': clientMutationId,
    }).requirePayload();
    OfficialAnkiSchedulerAudit.officialSchedulerAnswers += 1;
    return OfficialAnswerResult.fromJson(payload);
  }

  @override
  Future<OfficialUndoStatus> getUndoStatus() async {
    _requireScheduler(OfficialAnkiOperation.getUndoStatus);
    return OfficialUndoStatus.fromJson(
      _call(OfficialAnkiOperation.getUndoStatus).requirePayload(),
    );
  }

  @override
  Future<OfficialMutationResult> undo() async {
    _requireScheduler(OfficialAnkiOperation.undo);
    final payload = _call(OfficialAnkiOperation.undo).requirePayload();
    OfficialAnkiSchedulerAudit.officialSchedulerUndo += 1;
    return OfficialMutationResult.fromJson(payload);
  }

  @override
  Future<OfficialMutationResult> redo() async {
    _requireScheduler(OfficialAnkiOperation.redo);
    final payload = _call(OfficialAnkiOperation.redo).requirePayload();
    OfficialAnkiSchedulerAudit.officialSchedulerRedo += 1;
    return OfficialMutationResult.fromJson(payload);
  }

  @override
  Future<OfficialDeckCounts> countsForDeckToday(int deckId) async {
    _requireScheduler(OfficialAnkiOperation.countsForDeckToday);
    return OfficialDeckCounts.fromJson(
      _call(OfficialAnkiOperation.countsForDeckToday, {'deckId': deckId})
          .requirePayload(),
    );
  }

  @override
  Future<OfficialCongratsInfo> congratsInfo() async {
    _requireScheduler(OfficialAnkiOperation.congratsInfo);
    return OfficialCongratsInfo.fromJson(
      _call(OfficialAnkiOperation.congratsInfo).requirePayload(),
    );
  }

  @override
  Future<void> buryOrSuspendCards({
    required OfficialBuryOrSuspendAction action,
    List<int> cardIds = const <int>[],
    int? deckId,
  }) async {
    _requireScheduler(OfficialAnkiOperation.buryOrSuspendCards);
    _call(OfficialAnkiOperation.buryOrSuspendCards, {
      'mode': action.wireName,
      'cardIds': cardIds,
      if (deckId != null) 'deckId': deckId,
    });
    OfficialAnkiSchedulerAudit.officialSchedulerBurySuspend += 1;
  }

  @override
  Future<int> deleteNotes(List<int> noteIds) async {
    _requireScheduler(OfficialAnkiOperation.deleteNotes);
    final payload = _call(OfficialAnkiOperation.deleteNotes, {
      'noteIds': noteIds,
    }).requirePayload();
    return (payload['removedCards'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    try {
      if (_paths != null) {
        await closeCollection();
      }
    } catch (_) {
      _paths = null;
    }
    transport?.engineClose(handle);
  }
}

/// Decode helper used by tests that feed golden JSON bytes.
OfficialAnkiEnvelopeResponse decodeOfficialEnvelope(String jsonText) {
  return OfficialAnkiEnvelopeResponse.decode(utf8.encode(jsonText));
}
