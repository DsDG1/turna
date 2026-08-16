import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:turna/application/anki_official/contract/official_anki_contract.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_ffi.dart';
import 'package:turna/application/anki_official/engine/official_anki_native_transport.dart';
import 'package:turna/application/anki_official/import/official_anki_import_orchestrator.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
import 'package:turna/application/anki_official/import/official_anki_recovery_service.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_import_attempt_dao.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';

/// Persistent worker isolate that owns FFI, hashing, and the catalog.
class OfficialAnkiSession implements OfficialAnkiImporter {
  OfficialAnkiSession._({
    required Isolate isolate,
    required SendPort commands,
    required this.handle,
    required this.libraryPath,
    OfficialAnkiNativeTransport? control,
  })  : _isolate = isolate,
        _commands = commands,
        _control = control;

  final Isolate _isolate;
  final SendPort _commands;
  final OfficialAnkiNativeTransport? _control;
  final int handle;
  final String? libraryPath;
  var _serial = 0;
  var _disposed = false;

  static Future<OfficialAnkiSession> spawn({
    required OfficialAnkiPaths paths,
    String? libraryPath,
    String? catalogPath,
    bool useFake = false,
  }) async {
    final ready = ReceivePort();
    final isolate = await Isolate.spawn(
      officialAnkiWorkerEntrypoint,
      ready.sendPort,
      debugName: 'official-anki-worker',
    );
    final commands = await ready.first as SendPort;
    ready.close();
    final reply = ReceivePort();
    commands.send(<String, Object?>{
      'type': 'init',
      'reply': reply.sendPort,
      'profileId': paths.profileId,
      'profileRoot': paths.profileRoot.path,
      'catalogPath': catalogPath ?? paths.catalogFile.path,
      'libraryPath': libraryPath,
      'useFake': useFake,
    });
    final init = Map<String, Object?>.from(await reply.first as Map);
    reply.close();
    if (init['ok'] != true) {
      isolate.kill(priority: Isolate.immediate);
      throw OfficialAnkiException(
        code: OfficialAnkiErrorCode.capabilityMissing,
        messageKey: 'official_anki.worker_init_failed',
        debugDetails:
            '${init['messageKey'] ?? ''} ${init['debug'] ?? init['error'] ?? ''}'
                .trim(),
      );
    }
    final handle = (init['handle'] as num?)?.toInt() ?? 0;
    OfficialAnkiNativeTransport? control;
    if (!useFake && libraryPath != null) {
      control = OfficialAnkiNativeTransport.open(libraryPath: libraryPath);
    } else if (!useFake) {
      final resolved = resolveOfficialAnkiLibraryPath();
      if (resolved != null) {
        control = OfficialAnkiNativeTransport.open(libraryPath: resolved);
      }
    }
    return OfficialAnkiSession._(
      isolate: isolate,
      commands: commands,
      handle: handle,
      libraryPath: libraryPath,
      control: control,
    );
  }

  Future<Map<String, Object?>> _rpc(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
  ]) async {
    if (_disposed) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidState,
        messageKey: 'official_anki.engine_disposed',
      );
    }
    _serial += 1;
    final id = _serial;
    final reply = ReceivePort();
    _commands.send(<String, Object?>{
      'type': type,
      'id': id,
      'reply': reply.sendPort,
      ...payload,
    });
    final raw = Map<String, Object?>.from(await reply.first as Map);
    reply.close();
    if (raw['ok'] != true) {
      throw OfficialAnkiException(
        code: officialAnkiErrorCodeFromName(raw['code'] as String?),
        messageKey: raw['messageKey'] as String? ?? 'official_anki.worker_error',
        debugDetails: raw['debug']?.toString(),
      );
    }
    return raw;
  }

  @override
  Future<OfficialAnkiImportResult> importFile({
    required String packagePath,
    required String displayName,
    String? requestId,
    bool cancel = false,
  }) async {
    final raw = await _rpc('importFile', {
      'packagePath': packagePath,
      'displayName': displayName,
      'requestId': requestId,
      'cancel': cancel,
    });
    return OfficialAnkiImportResult(
      sourceId: raw['sourceId'] as String,
      attemptId: raw['attemptId'] as String,
      state: OfficialAnkiSourceStateWire.parse(raw['state'] as String),
      cardCount: (raw['cardCount'] as num?)?.toInt() ?? 0,
      noteCount: (raw['noteCount'] as num?)?.toInt() ?? 0,
      alreadyImported: raw['alreadyImported'] == true,
    );
  }

  Future<OfficialAnkiEngineInfo> engineInfo() async {
    final raw = await _rpc('engineInfo');
    return OfficialAnkiEngineInfo.fromJson(
      Map<String, Object?>.from(raw['info'] as Map),
    );
  }

  Future<List<OfficialAnkiImportResult>> recoverUnfinished() async {
    final raw = await _rpc('recoverUnfinished');
    final items = raw['results'] as List? ?? const [];
    return items
        .whereType<Map>()
        .map(
          (item) => OfficialAnkiImportResult(
            sourceId: item['sourceId'] as String,
            attemptId: item['attemptId'] as String,
            state: OfficialAnkiSourceStateWire.parse(item['state'] as String),
            cardCount: (item['cardCount'] as num?)?.toInt() ?? 0,
            noteCount: (item['noteCount'] as num?)?.toInt() ?? 0,
          ),
        )
        .toList();
  }

  Future<OfficialAnkiProgress> latestProgress() async {
    final control = _control;
    if (control != null && handle != 0) {
      final request = OfficialAnkiEnvelopeRequest(
        requestId: 'progress-${DateTime.now().microsecondsSinceEpoch}',
        operation: 'LATEST_PROGRESS',
      );
      final response = control.call(handle, 6, request);
      final payload = response.requirePayload();
      final wantAbort = payload['want_abort'] == true;
      return OfficialAnkiProgress(
        stage: wantAbort
            ? 'cancelling'
            : (payload['operation_kind'] as String? ?? 'idle'),
        canCancel: payload['can_cancel'] == true,
      );
    }
    final raw = await _rpc('progress');
    return OfficialAnkiProgress(
      stage: raw['stage'] as String? ?? 'idle',
      canCancel: raw['canCancel'] == true,
    );
  }

  Future<void> cancel() async {
    final control = _control;
    if (control != null && handle != 0) {
      control.cancel(handle);
      return;
    }
    await _rpc('cancel');
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await _rpc('dispose').timeout(const Duration(seconds: 8));
    } catch (_) {}
    _isolate.kill(priority: Isolate.immediate);
  }
}

void officialAnkiWorkerEntrypoint(SendPort ready) {
  final commands = ReceivePort();
  ready.send(commands.sendPort);
  OfficialAnkiEngine? engine;
  OfficialAnkiDatabase? db;
  OfficialAnkiImportOrchestrator? orchestrator;
  OfficialAnkiRecoveryService? recovery;
  OfficialAnkiPaths? paths;

  Future<void> handle(Map<String, Object?> message) async {
    final reply = message['reply'] as SendPort;
    final type = message['type'] as String? ?? '';
    try {
      switch (type) {
        case 'init':
          paths = OfficialAnkiPaths(
            profileId: message['profileId'] as String,
            profileRoot: Directory(message['profileRoot'] as String),
          );
          await paths!.ensureLayout();
          db = OfficialAnkiDatabase.file(message['catalogPath'] as String);
          final useFake = message['useFake'] == true;
          if (useFake) {
            engine = FakeOfficialAnkiEngine();
          } else {
            final transport = OfficialAnkiNativeTransport.open(
              libraryPath: message['libraryPath'] as String?,
            );
            engine = FfiOfficialAnkiEngine.connect(transport);
          }
          final sources = OfficialAnkiSourceDao(db!);
          final attempts = OfficialAnkiImportAttemptDao(db!);
          orchestrator = OfficialAnkiImportOrchestrator(
            engine: engine!,
            sources: sources,
            attempts: attempts,
            paths: paths!,
          );
          recovery = OfficialAnkiRecoveryService(
            sources: sources,
            attempts: attempts,
            engine: engine!,
            orchestrator: orchestrator!,
          );
          reply.send(<String, Object?>{
            'ok': true,
            'handle': engine is FfiOfficialAnkiEngine
                ? (engine! as FfiOfficialAnkiEngine).handle
                : 0,
          });
          return;
        case 'engineInfo':
          final info = await engine!.engineInfo();
          reply.send(<String, Object?>{
            'ok': true,
            'info': <String, Object?>{
              'abiVersion': info.abiVersion,
              'backendCommit': info.backendCommit,
              'contractMajor': info.contractMajor,
              'contractMinor': info.contractMinor,
              'capabilities': info.capabilities.toList(),
            },
          });
          return;
        case 'importFile':
          final result = await orchestrator!.importFile(
            packagePath: message['packagePath'] as String,
            displayName: message['displayName'] as String,
            requestId: message['requestId'] as String?,
            cancel: message['cancel'] == true,
          );
          reply.send(_resultMap(result));
          return;
        case 'recoverUnfinished':
          final results = await recovery!.recoverUnfinished();
          reply.send(<String, Object?>{
            'ok': true,
            'results': results.map(_resultPayload).toList(),
          });
          return;
        case 'progress':
          final progress = await engine!.latestProgress();
          reply.send(<String, Object?>{
            'ok': true,
            'stage': progress.stage,
            'canCancel': progress.canCancel,
          });
          return;
        case 'cancel':
          await engine!.cancel();
          reply.send(const <String, Object?>{'ok': true});
          return;
        case 'dispose':
          await engine?.dispose();
          db?.close();
          reply.send(const <String, Object?>{'ok': true});
          return;
        default:
          throw OfficialAnkiException(
            code: OfficialAnkiErrorCode.invalidArgument,
            messageKey: 'official_anki.unknown_worker_command',
            debugDetails: type,
          );
      }
    } on OfficialAnkiException catch (error) {
      reply.send(<String, Object?>{
        'ok': false,
        'code': error.code.name.toUpperCase(),
        'messageKey': error.messageKey,
        'debug': error.debugDetails ?? error.toString(),
      });
    } catch (error, stack) {
      reply.send(<String, Object?>{
        'ok': false,
        'code': 'INTERNAL_ERROR',
        'messageKey': 'official_anki.worker_error',
        'debug': '$error\n$stack',
      });
    }
  }

  commands.listen((raw) {
    if (raw is Map) {
      handle(Map<String, Object?>.from(raw));
    }
  });
}

Map<String, Object?> _resultPayload(OfficialAnkiImportResult result) {
  return <String, Object?>{
    'sourceId': result.sourceId,
    'attemptId': result.attemptId,
    'state': result.state.wire,
    'cardCount': result.cardCount,
    'noteCount': result.noteCount,
    'alreadyImported': result.alreadyImported,
  };
}

Map<String, Object?> _resultMap(OfficialAnkiImportResult result) {
  return <String, Object?>{
    'ok': true,
    ..._resultPayload(result),
  };
}
