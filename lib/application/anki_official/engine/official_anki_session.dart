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
import 'package:turna/application/anki_official/engine/official_anki_operation_coordinator.dart';
import 'package:turna/application/anki_official/engine/official_anki_session_cleanup.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_lifecycle_models.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_import_attempt_dao.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_card_index.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// Persistent worker isolate that owns FFI, hashing, and the catalog.
///
/// Wire protocol (doc 39 P4): every command is `{type, id, reply, …args}`
/// and every reply is `{ok: true, result}` or `{ok: false, code, messageKey,
/// debug}`. The `result` slot carries the typed DTO object itself — isolate
/// ports copy plain object graphs, so neither side re-serializes DTOs
/// (before P4 the worker flattened every DTO to a map and the main isolate
/// parsed it back, constructing each DTO twice per call).
class OfficialAnkiSession implements OfficialAnkiImporter {
  OfficialAnkiSession._({
    required Isolate isolate,
    required SendPort commands,
    required this.handle,
    required this.libraryPath,
    OfficialAnkiNativeTransport? control,
    OfficialAnkiSessionCleanup? cleanup,
  })  : _isolate = isolate,
        _commands = commands,
        _control = control,
        _cleanup = cleanup ?? OfficialAnkiSessionCleanup();

  final Isolate _isolate;
  final SendPort _commands;
  final OfficialAnkiNativeTransport? _control;
  final OfficialAnkiSessionCleanup _cleanup;
  final OfficialAnkiCloseOwnership _closeOwnership =
      OfficialAnkiCloseOwnership();
  final int handle;
  final String? libraryPath;
  var _serial = 0;
  var _disposed = false;
  var _rejecting = false;
  Future<void>? _disposeFuture;
  var orphanCleanup = false;

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
    var isolateLive = true;
    void killSpawned() {
      if (!isolateLive) return;
      isolateLive = false;
      isolate.kill(priority: Isolate.immediate);
    }

    commands.send(<String, Object?>{
      'type': 'init',
      'reply': reply.sendPort,
      'profileId': paths.profileId,
      'profileRoot': paths.profileRoot.path,
      'catalogPath': catalogPath ?? paths.catalogFile.path,
      'libraryPath': libraryPath,
      'useFake': useFake,
    });
    try {
      final init = Map<String, Object?>.from(
        await reply.first.timeout(const Duration(seconds: 20)) as Map,
      );
      if (init['ok'] != true) {
        killSpawned();
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
      try {
        if (!useFake && libraryPath != null) {
          control = OfficialAnkiNativeTransport.open(libraryPath: libraryPath);
        } else if (!useFake) {
          final resolved = resolveOfficialAnkiLibraryPath();
          if (resolved != null) {
            control = OfficialAnkiNativeTransport.open(libraryPath: resolved);
          }
        }
      } catch (error) {
        final disposeReply = ReceivePort();
        commands.send(<String, Object?>{
          'type': 'dispose',
          'reply': disposeReply.sendPort,
        });
        await disposeReply.first.timeout(
          const Duration(seconds: 2),
          onTimeout: () => null,
        );
        disposeReply.close();
        killSpawned();
        rethrow;
      }
      final resolvedLibrary = init['libraryPath'] as String? ??
          resolveOfficialAnkiCleanupLibraryPath(requested: libraryPath);
      return OfficialAnkiSession._(
        isolate: isolate,
        commands: commands,
        handle: handle,
        libraryPath: resolvedLibrary,
        control: control,
      );
    } catch (error) {
      killSpawned();
      if (error is OfficialAnkiException) rethrow;
      throw OfficialAnkiException(
        code: OfficialAnkiErrorCode.capabilityMissing,
        messageKey: 'official_anki.worker_init_failed',
        debugDetails: error.toString(),
      );
    } finally {
      reply.close();
    }
  }

  /// Worker RPC with a guard against a dead/hung isolate. If the worker dies
  /// mid-call (OOM, unhandled error) or a native op stalls outside
  /// `catch_unwind`, `reply.first` would otherwise never complete and every
  /// caller would hang forever — only init had a timeout before. Long ops
  /// (imports) pass an explicit [timeout]; `cancel` stays reachable because
  /// it goes through the control transport, not this queue.
  Future<Map<String, Object?>> _rpc(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration timeout = const Duration(seconds: 120),
  ]) async {
    if (_disposed || _rejecting) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidState,
        messageKey: 'official_anki.engine_disposed',
      );
    }
    _serial += 1;
    final id = _serial;
    final reply = ReceivePort();
    try {
      _commands.send(<String, Object?>{
        'type': type,
        'id': id,
        'reply': reply.sendPort,
        ...payload,
      });
      final raw = Map<String, Object?>.from(
        await reply.first.timeout(
          timeout,
          onTimeout: () => throw TimeoutException(
            'official-anki-worker rpc $type exceeded ${timeout.inSeconds}s',
          ),
        ) as Map,
      );
      if (raw['ok'] != true) {
        throw OfficialAnkiException(
          code: officialAnkiErrorCodeFromName(raw['code'] as String?),
          messageKey:
              raw['messageKey'] as String? ?? 'official_anki.worker_error',
          debugDetails: raw['debug']?.toString(),
        );
      }
      return raw;
    } on TimeoutException {
      throw OfficialAnkiException(
        code: OfficialAnkiErrorCode.schedulerBusy,
        messageKey: 'official_anki.worker_rpc_timeout',
        debugDetails: 'rpc=$type timeoutMs=${timeout.inMilliseconds}',
      );
    } finally {
      reply.close();
    }
  }

  /// Typed RPC: the worker's reply carries the DTO object graph directly.
  Future<T> _call<T>(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
    Duration timeout = const Duration(seconds: 120),
  ]) async {
    final raw = await _rpc(type, payload, timeout);
    return raw['result'] as T;
  }

  @override
  Future<OfficialAnkiImportResult> importFile({
    required String packagePath,
    required String displayName,
    String? requestId,
    bool cancel = false,
  }) {
    // Imports legitimately run for minutes on large decks (media copy +
    // rslib import); the timeout only guards a dead worker.
    return _call<OfficialAnkiImportResult>(
      'importFile',
      {
        'packagePath': packagePath,
        'displayName': displayName,
        'requestId': requestId,
        'cancel': cancel,
      },
      const Duration(minutes: 30),
    );
  }

  Future<OfficialAnkiImportLog> importPackage({
    required String packagePath,
    bool withScheduling = true,
    bool withDeckConfigs = true,
  }) {
    return _call<OfficialAnkiImportLog>(
      'importPackage',
      {
        'packagePath': packagePath,
        'withScheduling': withScheduling,
        'withDeckConfigs': withDeckConfigs,
      },
      const Duration(minutes: 30),
    );
  }

  Future<OfficialAnkiEngineInfo> engineInfo() =>
      _call<OfficialAnkiEngineInfo>('engineInfo');

  Future<String> createBackup() => _call<String>('createBackup');

  Future<void> restoreBackup(String backupId) =>
      _rpc('restoreBackup', {'backupId': backupId});

  Future<Map<int, List<int>>> getNoteCardsBatch(List<int> noteIds) =>
      _call<Map<int, List<int>>>('getNoteCardsBatch', {
        'noteIds': noteIds,
      });

  Future<List<OfficialAnkiCardDescriptor>> getCardDescriptorsBatch(
    List<int> cardIds,
  ) =>
      _call<List<OfficialAnkiCardDescriptor>>('getCardDescriptorsBatch', {
        'cardIds': cardIds,
      });

  Future<List<OfficialAnkiImportResult>> recoverUnfinished() =>
      _call<List<OfficialAnkiImportResult>>('recoverUnfinished');

  /// crash-hunt PR1: run the import receipt segment (per-card catalog
  /// writes + paged engine reads) inside the worker so none of it touches
  /// the UI isolate. Same generous timeout as imports — large decks do
  /// minutes of per-page work here.
  Future<int> commitReceipt({
    required String attemptId,
    required String sourceId,
    required List<int> noteIds,
    required int nowMillis,
  }) {
    return _call<int>(
      'commitReceipt',
      {
        'attemptId': attemptId,
        'sourceId': sourceId,
        'noteIds': noteIds,
        'nowMillis': nowMillis,
      },
      const Duration(minutes: 30),
    );
  }

  /// ADR 0044 R1.5: run the v2 card-index segment (one `anki_source_cards`
  /// row per card + paged engine reads) inside the worker so none of it
  /// touches the UI isolate. Same generous timeout as imports — large decks
  /// do minutes of per-page work here.
  Future<int> v2CardIndex({
    required String attemptId,
    required String sourceId,
  }) {
    return _call<int>(
      'v2CardIndex',
      {'attemptId': attemptId, 'sourceId': sourceId},
      const Duration(minutes: 30),
    );
  }

  /// Latest import progress. The control transport (main-isolate FFI) is
  /// preferred so this stays reachable while the worker is busy inside a
  /// long import; the worker path serves fake engines without a control
  /// transport. Both shapes are parsed by [OfficialAnkiProgress.fromJson].
  Future<OfficialAnkiProgress> latestProgress() async {
    final control = _control;
    if (control != null && handle != 0) {
      final request = OfficialAnkiEnvelopeRequest(
        requestId: 'progress-${DateTime.now().microsecondsSinceEpoch}',
        operation: OfficialAnkiOperation.latestProgress,
      );
      final response = control.call(
        handle,
        OfficialAnkiOperation.idFor(OfficialAnkiOperation.latestProgress),
        request,
      );
      return OfficialAnkiProgress.fromJson(response.requirePayload());
    }
    return _call<OfficialAnkiProgress>('progress');
  }

  /// Cancel the running native op. Same dual-path rationale as
  /// [latestProgress]: the control transport works while the worker is busy.
  Future<void> cancel() async {
    final control = _control;
    if (control != null && handle != 0) {
      control.cancel(handle);
      return;
    }
    await _rpc('cancel');
  }

  Future<OfficialAnkiRenderedCard> renderCard({
    required int cardId,
    bool browser = false,
    bool includeAvTags = true,
  }) =>
      _call<OfficialAnkiRenderedCard>('renderCard', {
        'cardId': cardId,
        'browser': browser,
        'includeAvTags': includeAvTags,
      });

  Future<OfficialAnkiTypedComparison> compareTypedAnswer({
    required int cardId,
    required String marker,
    required String provided,
  }) =>
      _call<OfficialAnkiTypedComparison>('compareTypedAnswer', {
        'cardId': cardId,
        'marker': marker,
        'provided': provided,
      });

  Future<String> extractClozeForTyping({
    required String text,
    required int ordinal,
  }) =>
      _call<String>('extractClozeForTyping', {
        'text': text,
        'ordinal': ordinal,
      });

  Future<List<OfficialAnkiDeckNode>> listDeckTree() =>
      _call<List<OfficialAnkiDeckNode>>('listDeckTree');

  Future<List<OfficialAnkiProjectionSchema>> getProjectionSchemas({
    List<int> notetypeIds = const <int>[],
    bool includeSamples = false,
    int sampleLimit = 3,
  }) =>
      _call<List<OfficialAnkiProjectionSchema>>('getProjectionSchemas', {
        'notetypeIds': notetypeIds,
        'includeSamples': includeSamples,
        'sampleLimit': sampleLimit,
      });

  Future<OfficialAnkiProjectionSnapshot> beginProjectionRead({
    required String cardSetFingerprint,
    int mappingVersion = 1,
  }) =>
      _call<OfficialAnkiProjectionSnapshot>('beginProjectionRead', {
        'cardSetFingerprint': cardSetFingerprint,
        'mappingVersion': mappingVersion,
      });

  Future<OfficialAnkiProjectionPage> getProjectionRowsBatch({
    required List<int> cardIds,
    required String snapshotToken,
  }) =>
      _call<OfficialAnkiProjectionPage>('getProjectionRowsBatch', {
        'cardIds': cardIds,
        'snapshotToken': snapshotToken,
      });

  Future<OfficialAnkiCardPage> searchCardsPage({
    String search = '',
    int pageSize = 200,
    String? pageToken,
  }) =>
      _call<OfficialAnkiCardPage>('searchCardsPage', {
        'search': search,
        'pageSize': pageSize,
        if (pageToken != null) 'pageToken': pageToken,
      });

  Future<void> ensureCollectionOpen() async {
    await _rpc('ensureOpen');
  }

  Future<void> setCurrentDeck(int deckId) async {
    await _rpc('scheduler', {'op': 'setCurrentDeck', 'deckId': deckId});
  }

  Future<OfficialReviewQueue> getReviewQueue({int fetchLimit = 1}) =>
      _call<OfficialReviewQueue>('scheduler', {
        'op': 'getReviewQueue',
        'fetchLimit': fetchLimit,
      });

  Future<OfficialAnswerResult> answerCard({
    required String sessionId,
    required int queueEpoch,
    required String answerToken,
    required int cardId,
    required String rating,
    required int millisecondsTaken,
    int? answeredAtMillis,
    String? clientMutationId,
  }) =>
      _call<OfficialAnswerResult>('scheduler', {
        'op': 'answerCard',
        'sessionId': sessionId,
        'queueEpoch': queueEpoch,
        'answerToken': answerToken,
        'cardId': cardId,
        'rating': rating,
        'millisecondsTaken': millisecondsTaken,
        if (answeredAtMillis != null) 'answeredAtMillis': answeredAtMillis,
        if (clientMutationId != null) 'clientMutationId': clientMutationId,
      });

  Future<OfficialUndoStatus> getUndoStatus() =>
      _call<OfficialUndoStatus>('scheduler', {'op': 'getUndoStatus'});

  Future<OfficialMutationResult> undo() =>
      _call<OfficialMutationResult>('scheduler', {'op': 'undo'});

  Future<OfficialMutationResult> redo() =>
      _call<OfficialMutationResult>('scheduler', {'op': 'redo'});

  Future<OfficialDeckCounts> countsForDeckToday(int deckId) =>
      _call<OfficialDeckCounts>('scheduler', {
        'op': 'countsForDeckToday',
        'deckId': deckId,
      });

  Future<OfficialCongratsInfo> congratsInfo() =>
      _call<OfficialCongratsInfo>('scheduler', {'op': 'congratsInfo'});

  Future<void> buryOrSuspendCards({
    required OfficialBuryOrSuspendAction action,
    List<int> cardIds = const <int>[],
    int? deckId,
  }) async {
    await _rpc('scheduler', {
      'op': 'buryOrSuspendCards',
      'action': action.wireName,
      'cardIds': cardIds,
      if (deckId != null) 'deckId': deckId,
    });
  }

  Future<int> deleteNotes(List<int> noteIds) => _call<int>('scheduler', {
        'op': 'deleteNotes',
        'noteIds': noteIds,
      });

  Future<int> deleteCards(List<int> cardIds) => _call<int>('scheduler', {
        'op': 'deleteCards',
        'cardIds': cardIds,
      });

  Future<OfficialAnkiStatsBatch> statsForCardsBatch(List<int> cardIds) =>
      _call<OfficialAnkiStatsBatch>('scheduler', {
        'op': 'statsForCardsBatch',
        'cardIds': cardIds,
      });

  Future<int> scheduleCardsAsNew(List<int> cardIds) => _call<int>('scheduler', {
        'op': 'scheduleCardsAsNew',
        'cardIds': cardIds,
      });

  Future<OfficialAheadAnswerOutcome> answerAheadCards(
    List<OfficialAheadAnswer> answers,
  ) =>
      _call<OfficialAheadAnswerOutcome>('scheduler', {
        'op': 'answerAheadCards',
        'answers': [for (final answer in answers) answer.toJson()],
      });

  Future<int> ensureTodayNewQuota({
    required int deckId,
    required int neededNew,
  }) =>
      _call<int>('scheduler', {
        'op': 'ensureTodayNewQuota',
        'deckId': deckId,
        'neededNew': neededNew,
      });

  Future<OfficialAnkiGcMediaResult> gcUnusedMedia({bool dryRun = true}) =>
      _call<OfficialAnkiGcMediaResult>('scheduler', {
        'op': 'gcUnusedMedia',
        'dryRun': dryRun,
      });

  Future<OfficialAnkiPruneMetadataResult> pruneEmptyMetadata({
    List<int> notetypeIds = const <int>[],
    List<int> deckIds = const <int>[],
  }) =>
      _call<OfficialAnkiPruneMetadataResult>('scheduler', {
        'op': 'pruneEmptyMetadata',
        'notetypeIds': notetypeIds,
        'deckIds': deckIds,
      });

  Future<OfficialAnkiCompactResult> compactCollection({bool force = false}) =>
      _call<OfficialAnkiCompactResult>('scheduler', {
        'op': 'compactCollection',
        'force': force,
      });

  Future<List<int>> diffCollectionCheckpoint(String checkpointId) =>
      _call<List<int>>('scheduler', {
        'op': 'diffCollectionCheckpoint',
        'checkpointId': checkpointId,
      });

  Future<OfficialAnkiConfigValue> getConfig(String key) =>
      _call<OfficialAnkiConfigValue>('scheduler', {
        'op': 'getConfig',
        'key': key,
      });

  Future<OfficialAnkiConfigWriteResult> setConfig(String key, Object? value) =>
      _call<OfficialAnkiConfigWriteResult>('scheduler', {
        'op': 'setConfig',
        'key': key,
        'value': value,
      });

  Future<void> dispose() {
    return _disposeFuture ??= _disposeOnce();
  }

  Future<void> _disposeOnce() async {
    if (_disposed) return;
    _rejecting = true;
    try {
      final report = await _cleanup.run(
        graceful: () async {
          try {
            _control?.cancel(handle);
          } catch (suppressed) { debugPrint('[OfficialAnkiSession] suppressed error: $suppressed'); }
          await _rpcDispose();
        },
        handle: handle,
        resolvedLibraryPath: libraryPath,
        token: _closeOwnership,
        alreadyClosed: handle == 0,
      );
      orphanCleanup = report.orphan;
    } finally {
      _disposed = true;
      _isolate.kill(priority: Isolate.immediate);
    }
  }

  Future<void> _rpcDispose() async {
    _serial += 1;
    final reply = ReceivePort();
    _commands.send(<String, Object?>{
      'type': 'dispose',
      'id': _serial,
      'reply': reply.sendPort,
    });
    try {
      await reply.first;
    } finally {
      reply.close();
    }
  }
}

/// Mutable worker-side singletons, set by `init` and cleared by `dispose`.
class _WorkerState {
  OfficialAnkiEngine? engine;
  OfficialAnkiDatabase? db;
  OfficialAnkiPaths? paths;
  final ops = OfficialAnkiOperationCoordinator();
}

void officialAnkiWorkerEntrypoint(SendPort ready) {
  final commands = ReceivePort();
  ready.send(commands.sendPort);
  final state = _WorkerState();
  commands.listen((raw) {
    if (raw is Map) {
      _handleWorkerCommand(state, Map<String, Object?>.from(raw));
    }
  });
}

/// One line per worker command: the single dispatch surface (doc 39 P4).
/// Handlers return the typed DTO; the reply envelope wraps it verbatim.
final Map<String, Future<Object?> Function(_WorkerState, Map<String, Object?>)>
    _workerHandlers = {
  'engineInfo': (s, m) => s.engine!.engineInfo(),
  'createBackup': (s, m) => s.engine!.createBackup(),
  'restoreBackup': (s, m) => s.engine!.restoreBackup(m['backupId'] as String),
  'getNoteCardsBatch': (s, m) => s.engine!.getNoteCardsBatch(
        ((m['noteIds'] as List?) ?? const [])
            .whereType<num>()
            .map((n) => n.toInt())
            .toList(),
      ),
  'getCardDescriptorsBatch': (s, m) => s.engine!.getCardDescriptorsBatch(
        ((m['cardIds'] as List?) ?? const [])
            .whereType<num>()
            .map((n) => n.toInt())
            .toList(),
      ),
  'recoverUnfinished': (s, m) async => const <OfficialAnkiImportResult>[],
  'commitReceipt': (s, m) async => 0,
  'v2CardIndex': (s, m) async {
    // ADR 0044 R1.5: the v2 ownership list is one anki_source_cards row
    // per card (sync sqlite). This worker already owns the engine handle
    // and a catalog connection — running the segment here keeps the whole
    // thing (and its per-page engine calls) off the UI isolate.
    return officialAnkiV2RunCardIndex(
      sources: OfficialAnkiSourceDao(s.db!),
      attempts: OfficialAnkiImportAttemptDao(s.db!),
      engine: s.engine!,
      attemptId: m['attemptId'] as String,
      sourceId: m['sourceId'] as String,
    );
  },
  'importFile': (s, m) async {
    // Doc 42 P4: no catalog saga / backup. Product wizard uses startStaging.
    s.ops.guardCollectionMutation();
    s.ops.acquire(OfficialAnkiOperationPhase.importing);
    try {
      if (m['cancel'] == true) {
        await s.engine!.cancel();
        return OfficialAnkiImportResult(
          sourceId: '',
          attemptId: m['requestId'] as String? ?? '',
          state: OfficialAnkiSourceState.cancelled,
          cardCount: 0,
          noteCount: 0,
        );
      }
      final log = await s.engine!.importPackage(
        packagePath: m['packagePath'] as String,
      );
      return OfficialAnkiImportResult(
        sourceId: '',
        attemptId: m['requestId'] as String? ?? '',
        state: OfficialAnkiSourceState.previewReady,
        cardCount: log.cardCount,
        noteCount: log.noteCount,
      );
    } finally {
      s.ops.release(OfficialAnkiOperationPhase.importing);
    }
  },
  'importPackage': (s, m) async {
    s.ops.guardCollectionMutation();
    return s.engine!.importPackage(
      packagePath: m['packagePath'] as String,
      withScheduling: m['withScheduling'] == true,
      withDeckConfigs: m['withDeckConfigs'] != false,
    );
  },
  'progress': (s, m) => s.engine!.latestProgress(),
  'cancel': (s, m) => s.engine!.cancel(),
  'renderCard': (s, m) => s.engine!.renderCard(
        cardId: (m['cardId'] as num).toInt(),
        browser: m['browser'] == true,
        includeAvTags: m['includeAvTags'] != false,
      ),
  'compareTypedAnswer': (s, m) => s.engine!.compareTypedAnswer(
        cardId: (m['cardId'] as num).toInt(),
        marker: m['marker'] as String,
        provided: m['provided'] as String,
      ),
  'listDeckTree': (s, m) => s.engine!.listDeckTree(),
  'getProjectionSchemas': (s, m) => s.engine!.getProjectionSchemas(
        notetypeIds: ((m['notetypeIds'] as List?) ?? const [])
            .whereType<num>()
            .map((n) => n.toInt())
            .toList(),
        includeSamples: m['includeSamples'] == true,
        sampleLimit: (m['sampleLimit'] as num?)?.toInt() ?? 3,
      ),
  'beginProjectionRead': (s, m) => s.engine!.beginProjectionRead(
        cardSetFingerprint: m['cardSetFingerprint'] as String,
        mappingVersion: (m['mappingVersion'] as num?)?.toInt() ?? 1,
      ),
  'getProjectionRowsBatch': (s, m) => s.engine!.getProjectionRowsBatch(
        cardIds: ((m['cardIds'] as List?) ?? const [])
            .whereType<num>()
            .map((n) => n.toInt())
            .toList(),
        snapshotToken: m['snapshotToken'] as String,
      ),
  'extractClozeForTyping': (s, m) => s.engine!.extractClozeForTyping(
        text: m['text'] as String,
        ordinal: (m['ordinal'] as num).toInt(),
      ),
  'searchCardsPage': (s, m) => s.engine!.searchCardsPage(
        search: m['search'] as String? ?? '',
        pageSize: (m['pageSize'] as num?)?.toInt() ?? 200,
        pageToken: m['pageToken'] as String?,
      ),
  'ensureOpen': (s, m) async {
    s.ops.guardCollectionMutation();
    try {
      await s.engine!.openProfile(s.paths!);
    } on OfficialAnkiException catch (error) {
      if (error.code != OfficialAnkiErrorCode.collectionAlreadyOpen) {
        rethrow;
      }
    }
    await s.engine!.checkCollection();
    return null;
  },
  'scheduler': (s, m) =>
      dispatchOfficialAnkiScheduler(s.engine!, m, coordinator: s.ops),
};

Future<void> _handleWorkerCommand(
  _WorkerState state,
  Map<String, Object?> message,
) async {
  final reply = message['reply'] as SendPort;
  final type = message['type'] as String? ?? '';
  try {
    switch (type) {
      case 'init':
        final paths = OfficialAnkiPaths(
          profileId: message['profileId'] as String,
          profileRoot: Directory(message['profileRoot'] as String),
        );
        await paths.ensureLayout();
        state.paths = paths;
        state.db = OfficialAnkiDatabase.file(message['catalogPath'] as String);
        final useFake = message['useFake'] == true;
        String? resolvedLibrary;
        if (useFake) {
          state.engine = FakeOfficialAnkiEngine();
        } else {
          final requested = message['libraryPath'] as String?;
          final transport = OfficialAnkiNativeTransport.open(
            libraryPath: requested,
          );
          resolvedLibrary = transport.libraryPath;
          state.engine = FfiOfficialAnkiEngine.connect(transport);
        }
        reply.send(<String, Object?>{
          'ok': true,
          'handle': state.engine is FfiOfficialAnkiEngine
              ? (state.engine! as FfiOfficialAnkiEngine).handle
              : 0,
          'libraryPath': resolvedLibrary,
        });
        return;
      case 'dispose':
        try {
          await state.engine?.dispose();
        } finally {
          state.db?.close();
          state.db = null;
          state.engine = null;
          state.paths = null;
        }
        reply.send(const <String, Object?>{'ok': true});
        return;
      default:
        final handler = _workerHandlers[type];
        if (handler == null) {
          throw OfficialAnkiException(
            code: OfficialAnkiErrorCode.invalidArgument,
            messageKey: 'official_anki.unknown_worker_command',
            debugDetails: type,
          );
        }
        final result = await handler(state, message);
        reply.send(<String, Object?>{
          'ok': true,
          if (result != null) 'result': result,
        });
        return;
    }
  } on OfficialAnkiException catch (error) {
    if (type == 'init') {
      await state.engine?.dispose();
      state.db?.close();
      state.engine = null;
      state.db = null;
    }
    reply.send(<String, Object?>{
      'ok': false,
      'code': _wireErrorCode(error.code),
      'messageKey': error.messageKey,
      'debug': error.debugDetails ?? error.toString(),
    });
  } catch (error, stack) {
    if (type == 'init') {
      await state.engine?.dispose();
      state.db?.close();
      state.engine = null;
      state.db = null;
    }
    reply.send(<String, Object?>{
      'ok': false,
      'code': 'INTERNAL_ERROR',
      'messageKey': 'official_anki.worker_error',
      'debug': '$error\n$stack',
    });
  }
}

String _wireErrorCode(OfficialAnkiErrorCode code) {
  return code.name
      .replaceAllMapped(RegExp(r'[A-Z]'), (match) => '_${match[0]}')
      .toUpperCase();
}

const _schedulerWriteOps = {
  'setCurrentDeck',
  'answerCard',
  'undo',
  'redo',
  'buryOrSuspendCards',
  'deleteNotes',
  'deleteCards',
  'statsForCardsBatch',
  'scheduleCardsAsNew',
  'answerAheadCards',
  'ensureTodayNewQuota',
  'gcUnusedMedia',
  'pruneEmptyMetadata',
  'compactCollection',
  'setConfig',
};

/// Dispatches one scheduler op and returns its typed DTO (or an int for
/// primitive results, null for void ops) — the worker reply envelope
/// transfers the object as-is (doc 39 P4). Input validation (id lists,
/// actions, quota bounds) stays fail-closed here so both the worker and
/// direct callers share it.
Future<Object?> dispatchOfficialAnkiScheduler(
  OfficialAnkiEngine engine,
  Map<String, Object?> message, {
  OfficialAnkiOperationCoordinator? coordinator,
}) async {
  final op = message['op'] as String? ?? '';
  if (_schedulerWriteOps.contains(op)) {
    coordinator?.guardSchedulerWrite();
  }
  switch (op) {
    case 'setCurrentDeck':
      await engine.setCurrentDeck((message['deckId'] as num).toInt());
      return null;
    case 'getReviewQueue':
      return engine.getReviewQueue(
        fetchLimit: (message['fetchLimit'] as num?)?.toInt() ?? 1,
      );
    case 'answerCard':
      return engine.answerCard(
        sessionId: message['sessionId'] as String,
        queueEpoch: (message['queueEpoch'] as num).toInt(),
        answerToken: message['answerToken'] as String,
        cardId: (message['cardId'] as num).toInt(),
        rating: message['rating'] as String,
        millisecondsTaken: (message['millisecondsTaken'] as num).toInt(),
        answeredAtMillis: (message['answeredAtMillis'] as num?)?.toInt(),
        clientMutationId: message['clientMutationId'] as String?,
      );
    case 'getUndoStatus':
      return engine.getUndoStatus();
    case 'undo':
      return engine.undo();
    case 'redo':
      return engine.redo();
    case 'countsForDeckToday':
      return engine.countsForDeckToday((message['deckId'] as num).toInt());
    case 'congratsInfo':
      return engine.congratsInfo();
    case 'buryOrSuspendCards':
      final action = OfficialBuryOrSuspendAction.parse(
        message['action'] as String?,
      );
      final cardIds = ((message['cardIds'] as List?) ?? const []).map((item) {
        if (item is! num) {
          officialContractError('cardIds[]', item);
        }
        return item.toInt();
      }).toList();
      if (cardIds.any((id) => id <= 0)) {
        officialContractError('cardIds', cardIds);
      }
      if (action.requiresCardIds && cardIds.isEmpty) {
        officialContractError('cardIds', cardIds);
      }
      await engine.buryOrSuspendCards(
        action: action,
        cardIds: cardIds,
        deckId: (message['deckId'] as num?)?.toInt(),
      );
      return null;
    case 'deleteNotes':
      final noteIds = ((message['noteIds'] as List?) ?? const []).map((item) {
        if (item is! num) {
          officialContractError('noteIds[]', item);
        }
        return item.toInt();
      }).toList();
      if (noteIds.any((id) => id <= 0)) {
        officialContractError('noteIds', noteIds);
      }
      if (noteIds.isEmpty) {
        officialContractError('noteIds', noteIds);
      }
      return engine.deleteNotes(noteIds);
    case 'deleteCards':
      final cardIds = ((message['cardIds'] as List?) ?? const []).map((item) {
        if (item is! num) {
          officialContractError('cardIds[]', item);
        }
        return item.toInt();
      }).toList();
      if (cardIds.isEmpty || cardIds.any((id) => id <= 0)) {
        officialContractError('cardIds', cardIds);
      }
      return engine.deleteCards(cardIds);
    case 'statsForCardsBatch':
      final cardIds = ((message['cardIds'] as List?) ?? const []).map((item) {
        if (item is! num) {
          officialContractError('cardIds[]', item);
        }
        return item.toInt();
      }).toList();
      if (cardIds.isEmpty || cardIds.any((id) => id <= 0)) {
        officialContractError('cardIds', cardIds);
      }
      return engine.statsForCardsBatch(cardIds);
    case 'scheduleCardsAsNew':
      final cardIds = ((message['cardIds'] as List?) ?? const []).map((item) {
        if (item is! num) officialContractError('cardIds[]', item);
        return item.toInt();
      }).toList();
      if (cardIds.isEmpty || cardIds.any((id) => id <= 0)) {
        officialContractError('cardIds', cardIds);
      }
      return engine.scheduleCardsAsNew(cardIds);
    case 'answerAheadCards':
      final rawAnswers = (message['answers'] as List?) ?? const [];
      final answers = <OfficialAheadAnswer>[];
      for (final item in rawAnswers) {
        if (item is! Map) officialContractError('answers[]', item);
        final map = Map<String, Object?>.from(item);
        final cardId = (map['cardId'] as num?)?.toInt() ?? 0;
        final rating = map['rating'] as String? ?? '';
        if (cardId <= 0 || rating.isEmpty) {
          officialContractError('answers[]', item);
        }
        answers.add(
          OfficialAheadAnswer(
            cardId: cardId,
            rating: rating,
            millisecondsTaken:
                (map['millisecondsTaken'] as num?)?.toInt() ?? 0,
          ),
        );
      }
      if (answers.isEmpty) officialContractError('answers', rawAnswers);
      return engine.answerAheadCards(answers);
    case 'ensureTodayNewQuota':
      final deckId = (message['deckId'] as num?)?.toInt() ?? 0;
      final neededNew = (message['neededNew'] as num?)?.toInt() ?? 0;
      if (deckId <= 0 || neededNew < 0) {
        officialContractError('ensureTodayNewQuota', message);
      }
      return engine.ensureTodayNewQuota(deckId: deckId, neededNew: neededNew);
    case 'gcUnusedMedia':
      return engine.gcUnusedMedia(dryRun: message['dryRun'] == true);
    case 'pruneEmptyMetadata':
      return engine.pruneEmptyMetadata(
        notetypeIds: ((message['notetypeIds'] as List?) ?? const [])
            .whereType<num>()
            .map((n) => n.toInt())
            .toList(),
        deckIds: ((message['deckIds'] as List?) ?? const [])
            .whereType<num>()
            .map((n) => n.toInt())
            .toList(),
      );
    case 'compactCollection':
      return engine.compactCollection(force: message['force'] == true);
    case 'diffCollectionCheckpoint':
      return engine.diffCollectionCheckpoint(
        message['checkpointId'] as String? ?? '',
      );
    case 'getConfig':
      return engine.getConfig(message['key'] as String? ?? '');
    case 'setConfig':
      return engine.setConfig(
        message['key'] as String? ?? '',
        message['value'],
      );
    default:
      throw OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidArgument,
        messageKey: 'official_anki.unknown_worker_command',
        debugDetails: message['op']?.toString(),
      );
  }
}
