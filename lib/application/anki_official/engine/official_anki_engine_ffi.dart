import 'dart:convert';

import 'package:turna/application/anki_official/contract/official_anki_contract.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
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
    return OfficialAnkiEngineInfo.fromJson(payload);
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
