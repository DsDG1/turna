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
import 'package:turna/application/anki_official/import/official_anki_import_orchestrator.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
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

  @override
  Future<OfficialAnkiImportResult> importFile({
    required String packagePath,
    required String displayName,
    String? requestId,
    bool cancel = false,
  }) async {
    final raw = await _rpc(
      'importFile',
      {
        'packagePath': packagePath,
        'displayName': displayName,
        'requestId': requestId,
        'cancel': cancel,
      },
      // Imports legitimately run for minutes on large decks (media copy +
      // rslib import); the timeout only guards a dead worker.
      const Duration(minutes: 30),
    );
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
    final raw = await _rpc('progress');
    return OfficialAnkiProgress.fromJson(raw);
  }

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
  }) async {
    final raw = await _rpc('renderCard', {
      'cardId': cardId,
      'browser': browser,
      'includeAvTags': includeAvTags,
    });
    return OfficialAnkiRenderedCard.fromJson(
      Map<String, Object?>.from(raw['card'] as Map),
    );
  }

  Future<OfficialAnkiTypedComparison> compareTypedAnswer({
    required int cardId,
    required String marker,
    required String provided,
  }) async {
    final raw = await _rpc('compareTypedAnswer', {
      'cardId': cardId,
      'marker': marker,
      'provided': provided,
    });
    return OfficialAnkiTypedComparison.fromJson(
      Map<String, Object?>.from(raw['comparison'] as Map),
    );
  }

  Future<String> extractClozeForTyping({
    required String text,
    required int ordinal,
  }) async {
    final raw = await _rpc('extractClozeForTyping', {
      'text': text,
      'ordinal': ordinal,
    });
    return raw['text'] as String? ?? '';
  }

  Future<List<OfficialAnkiDeckNode>> listDeckTree() async {
    final raw = await _rpc('listDeckTree');
    final items = raw['decks'] as List? ?? const [];
    return items
        .whereType<Map>()
        .map(
          (item) =>
              OfficialAnkiDeckNode.fromJson(Map<String, Object?>.from(item)),
        )
        .toList();
  }

  Future<List<OfficialAnkiProjectionSchema>> getProjectionSchemas({
    List<int> notetypeIds = const <int>[],
    bool includeSamples = false,
    int sampleLimit = 3,
  }) async {
    final raw = await _rpc('getProjectionSchemas', {
      'notetypeIds': notetypeIds,
      'includeSamples': includeSamples,
      'sampleLimit': sampleLimit,
    });
    final items = raw['schemas'] as List? ?? const [];
    return items
        .whereType<Map>()
        .map(
          (item) => OfficialAnkiProjectionSchema.fromJson(
            Map<String, Object?>.from(item),
          ),
        )
        .toList();
  }

  Future<OfficialAnkiProjectionSnapshot> beginProjectionRead({
    required String cardSetFingerprint,
    int mappingVersion = 1,
  }) async {
    final raw = await _rpc('beginProjectionRead', {
      'cardSetFingerprint': cardSetFingerprint,
      'mappingVersion': mappingVersion,
    });
    return OfficialAnkiProjectionSnapshot.fromJson(
      Map<String, Object?>.from(raw['snapshot'] as Map? ?? raw),
    );
  }

  Future<OfficialAnkiProjectionPage> getProjectionRowsBatch({
    required List<int> cardIds,
    required String snapshotToken,
  }) async {
    final raw = await _rpc('getProjectionRowsBatch', {
      'cardIds': cardIds,
      'snapshotToken': snapshotToken,
    });
    return OfficialAnkiProjectionPage.fromJson(
      Map<String, Object?>.from(raw['page'] as Map? ?? raw),
    );
  }

  Future<OfficialAnkiCardPage> searchCardsPage({
    String search = '',
    int pageSize = 200,
    String? pageToken,
  }) async {
    final raw = await _rpc('searchCardsPage', {
      'search': search,
      'pageSize': pageSize,
      if (pageToken != null) 'pageToken': pageToken,
    });
    return OfficialAnkiCardPage.fromJson(
      Map<String, Object?>.from(raw['page'] as Map? ?? raw),
    );
  }

  Future<void> ensureCollectionOpen() async {
    await _rpc('ensureOpen');
  }

  Future<void> setCurrentDeck(int deckId) async {
    await _rpc('scheduler', {'op': 'setCurrentDeck', 'deckId': deckId});
  }

  Future<OfficialReviewQueue> getReviewQueue({int fetchLimit = 1}) async {
    final raw = await _rpc('scheduler', {
      'op': 'getReviewQueue',
      'fetchLimit': fetchLimit,
    });
    return OfficialReviewQueue.fromJson(
      Map<String, Object?>.from(raw['payload'] as Map? ?? raw),
    );
  }

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
    final raw = await _rpc('scheduler', {
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
    return OfficialAnswerResult.fromJson(
      Map<String, Object?>.from(raw['payload'] as Map? ?? raw),
    );
  }

  Future<OfficialUndoStatus> getUndoStatus() async {
    final raw = await _rpc('scheduler', {'op': 'getUndoStatus'});
    return OfficialUndoStatus.fromJson(
      Map<String, Object?>.from(raw['payload'] as Map? ?? raw),
    );
  }

  Future<OfficialMutationResult> undo() async {
    final raw = await _rpc('scheduler', {'op': 'undo'});
    return OfficialMutationResult.fromJson(
      Map<String, Object?>.from(raw['payload'] as Map? ?? raw),
    );
  }

  Future<OfficialMutationResult> redo() async {
    final raw = await _rpc('scheduler', {'op': 'redo'});
    return OfficialMutationResult.fromJson(
      Map<String, Object?>.from(raw['payload'] as Map? ?? raw),
    );
  }

  Future<OfficialDeckCounts> countsForDeckToday(int deckId) async {
    final raw = await _rpc('scheduler', {
      'op': 'countsForDeckToday',
      'deckId': deckId,
    });
    return OfficialDeckCounts.fromJson(
      Map<String, Object?>.from(raw['payload'] as Map? ?? raw),
    );
  }

  Future<OfficialCongratsInfo> congratsInfo() async {
    final raw = await _rpc('scheduler', {'op': 'congratsInfo'});
    return OfficialCongratsInfo.fromJson(
      Map<String, Object?>.from(raw['payload'] as Map? ?? raw),
    );
  }

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

  Future<int> deleteNotes(List<int> noteIds) async {
    final raw = await _rpc('scheduler', {
      'op': 'deleteNotes',
      'noteIds': noteIds,
    });
    final payload = Map<String, Object?>.from(raw['payload'] as Map? ?? raw);
    return (payload['removedCards'] as num?)?.toInt() ?? 0;
  }

  Future<int> deleteCards(List<int> cardIds) async {
    final raw = await _rpc('scheduler', {
      'op': 'deleteCards',
      'cardIds': cardIds,
    });
    final payload = Map<String, Object?>.from(raw['payload'] as Map? ?? raw);
    return (payload['removedCards'] as num?)?.toInt() ?? 0;
  }

  Future<OfficialAnkiStatsBatch> statsForCardsBatch(List<int> cardIds) async {
    final raw = await _rpc('scheduler', {
      'op': 'statsForCardsBatch',
      'cardIds': cardIds,
    });
    return OfficialAnkiStatsBatch.fromJson(
      Map<String, Object?>.from(raw['payload'] as Map? ?? raw),
    );
  }

  Future<int> scheduleCardsAsNew(List<int> cardIds) async {
    final raw = await _rpc('scheduler', {
      'op': 'scheduleCardsAsNew',
      'cardIds': cardIds,
    });
    final payload = Map<String, Object?>.from(raw['payload'] as Map? ?? raw);
    return (payload['scheduledCards'] as num?)?.toInt() ?? 0;
  }

  Future<OfficialAheadAnswerOutcome> answerAheadCards(
    List<OfficialAheadAnswer> answers,
  ) async {
    final raw = await _rpc('scheduler', {
      'op': 'answerAheadCards',
      'answers': [for (final answer in answers) answer.toJson()],
    });
    final payload = Map<String, Object?>.from(raw['payload'] as Map? ?? raw);
    return OfficialAheadAnswerOutcome.fromJson(payload);
  }

  Future<int> ensureTodayNewQuota({
    required int deckId,
    required int neededNew,
  }) async {
    final raw = await _rpc('scheduler', {
      'op': 'ensureTodayNewQuota',
      'deckId': deckId,
      'neededNew': neededNew,
    });
    final payload = Map<String, Object?>.from(raw['payload'] as Map? ?? raw);
    return (payload['extendedBy'] as num?)?.toInt() ?? 0;
  }

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
          } catch (_) {}
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

void officialAnkiWorkerEntrypoint(SendPort ready) {
  final commands = ReceivePort();
  ready.send(commands.sendPort);
  OfficialAnkiEngine? engine;
  OfficialAnkiDatabase? db;
  OfficialAnkiImportOrchestrator? orchestrator;
  OfficialAnkiPaths? paths;
  final ops = OfficialAnkiOperationCoordinator();

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
          String? resolvedLibrary;
          if (useFake) {
            engine = FakeOfficialAnkiEngine();
          } else {
            final requested = message['libraryPath'] as String?;
            final transport = OfficialAnkiNativeTransport.open(
              libraryPath: requested,
            );
            resolvedLibrary = transport.libraryPath;
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
          reply.send(<String, Object?>{
            'ok': true,
            'handle': engine is FfiOfficialAnkiEngine
                ? (engine! as FfiOfficialAnkiEngine).handle
                : 0,
            'libraryPath': resolvedLibrary,
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
          ops.guardCollectionMutation();
          ops.acquire(OfficialAnkiOperationPhase.importing);
          try {
            final result = await orchestrator!.importFile(
              packagePath: message['packagePath'] as String,
              displayName: message['displayName'] as String,
              requestId: message['requestId'] as String?,
              cancel: message['cancel'] == true,
            );
            reply.send(_resultMap(result));
          } finally {
            ops.release(OfficialAnkiOperationPhase.importing);
          }
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
        case 'renderCard':
          final card = await engine!.renderCard(
            cardId: (message['cardId'] as num).toInt(),
            browser: message['browser'] == true,
            includeAvTags: message['includeAvTags'] != false,
          );
          reply.send(<String, Object?>{
            'ok': true,
            'card': _renderedCardMap(card),
          });
          return;
        case 'compareTypedAnswer':
          final comparison = await engine!.compareTypedAnswer(
            cardId: (message['cardId'] as num).toInt(),
            marker: message['marker'] as String,
            provided: message['provided'] as String,
          );
          reply.send(<String, Object?>{
            'ok': true,
            'comparison': <String, Object?>{
              'comparisonHtml': comparison.comparisonHtml,
              'hasExpected': comparison.hasExpected,
            },
          });
          return;
        case 'listDeckTree':
          final decks = await engine!.listDeckTree();
          reply.send(<String, Object?>{
            'ok': true,
            'decks': decks
                .map(
                  (deck) => <String, Object?>{
                    'deckId': deck.deckId,
                    'name': deck.name,
                    'level': deck.level,
                  },
                )
                .toList(),
          });
          return;
        case 'getProjectionSchemas':
          final schemas = await engine!.getProjectionSchemas(
            notetypeIds: ((message['notetypeIds'] as List?) ?? const [])
                .whereType<num>()
                .map((n) => n.toInt())
                .toList(),
            includeSamples: message['includeSamples'] == true,
            sampleLimit: (message['sampleLimit'] as num?)?.toInt() ?? 3,
          );
          reply.send(<String, Object?>{
            'ok': true,
            'schemas': schemas
                .map(
                  (schema) => <String, Object?>{
                    'notetypeId': schema.notetypeId,
                    'name': schema.name,
                    'kind': schema.kind,
                    'fieldNames': schema.fieldNames,
                    'templateNames': schema.templateNames,
                    'schemaFingerprint': schema.schemaFingerprint,
                    'samples': schema.samples
                        .map(
                          (sample) => <String, Object?>{
                            'noteId': sample.noteId,
                            'fields': sample.fields,
                            'truncated': sample.truncated,
                          },
                        )
                        .toList(),
                  },
                )
                .toList(),
          });
          return;
        case 'beginProjectionRead':
          final snapshot = await engine!.beginProjectionRead(
            cardSetFingerprint: message['cardSetFingerprint'] as String,
            mappingVersion: (message['mappingVersion'] as num?)?.toInt() ?? 1,
          );
          reply.send(<String, Object?>{
            'ok': true,
            'snapshotToken': snapshot.snapshotToken,
            'collectionGeneration': snapshot.collectionGeneration,
            'backendCommit': snapshot.backendCommit,
          });
          return;
        case 'getProjectionRowsBatch':
          final page = await engine!.getProjectionRowsBatch(
            cardIds: ((message['cardIds'] as List?) ?? const [])
                .whereType<num>()
                .map((n) => n.toInt())
                .toList(),
            snapshotToken: message['snapshotToken'] as String,
          );
          reply.send(<String, Object?>{
            'ok': true,
            'rows': page.rows
                .map(
                  (row) => <String, Object?>{
                    'cardId': row.cardId,
                    'noteId': row.noteId,
                    'noteGuid': row.noteGuid,
                    'notetypeId': row.notetypeId,
                    'deckId': row.deckId,
                    'deckPath': row.deckPath,
                    'templateOrdinal': row.templateOrdinal,
                    'tags': row.tags,
                    'fields': row.fields,
                    'sourceFingerprint': row.sourceFingerprint,
                    'truncated': row.truncated,
                  },
                )
                .toList(),
            'missingCardIds': page.missingCardIds,
          });
          return;
        case 'extractClozeForTyping':
          final text = await engine!.extractClozeForTyping(
            text: message['text'] as String,
            ordinal: (message['ordinal'] as num).toInt(),
          );
          reply.send(<String, Object?>{'ok': true, 'text': text});
          return;
        case 'searchCardsPage':
          final page = await engine!.searchCardsPage(
            search: message['search'] as String? ?? '',
            pageSize: (message['pageSize'] as num?)?.toInt() ?? 200,
            pageToken: message['pageToken'] as String?,
          );
          reply.send(<String, Object?>{
            'ok': true,
            'page': <String, Object?>{
              'cardIds': page.cardIds,
              'nextPageToken': page.nextPageToken,
              'totalHint': page.totalHint,
            },
          });
          return;
        case 'ensureOpen':
          ops.guardCollectionMutation();
          try {
            await engine!.openProfile(paths!);
          } on OfficialAnkiException catch (error) {
            if (error.code != OfficialAnkiErrorCode.collectionAlreadyOpen) {
              rethrow;
            }
          }
          await engine!.checkCollection();
          reply.send(const <String, Object?>{'ok': true});
          return;
        case 'scheduler':
          final payload = await dispatchOfficialAnkiScheduler(
            engine!,
            message,
            coordinator: ops,
          );
          reply.send(<String, Object?>{
            'ok': true,
            'payload': payload,
          });
          return;
        case 'dispose':
          try {
            await engine?.dispose();
          } finally {
            db?.close();
            db = null;
            engine = null;
            orchestrator = null;
          }
          reply.send(const <String, Object?>{'ok': true});
          commands.close();
          return;
        default:
          throw OfficialAnkiException(
            code: OfficialAnkiErrorCode.invalidArgument,
            messageKey: 'official_anki.unknown_worker_command',
            debugDetails: type,
          );
      }
    } on OfficialAnkiException catch (error) {
      if (type == 'init') {
        await engine?.dispose();
        db?.close();
        engine = null;
        db = null;
      }
      reply.send(<String, Object?>{
        'ok': false,
        'code': _wireErrorCode(error.code),
        'messageKey': error.messageKey,
        'debug': error.debugDetails ?? error.toString(),
      });
    } catch (error, stack) {
      if (type == 'init') {
        await engine?.dispose();
        db?.close();
        engine = null;
        db = null;
      }
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
};

Future<Map<String, Object?>> dispatchOfficialAnkiScheduler(
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
      return const <String, Object?>{};
    case 'getReviewQueue':
      final queue = await engine.getReviewQueue(
        fetchLimit: (message['fetchLimit'] as num?)?.toInt() ?? 1,
      );
      return <String, Object?>{
        'sessionId': queue.sessionId,
        'queueEpoch': queue.queueEpoch,
        'newCount': queue.newCount,
        'learningCount': queue.learningCount,
        'reviewCount': queue.reviewCount,
        'cards': queue.cards
            .map(
              (card) => <String, Object?>{
                'cardId': card.cardId,
                'noteId': card.noteId,
                'deckId': card.deckId,
                'templateOrdinal': card.templateOrdinal,
                'queueKind': card.queueKind,
                'answerToken': card.answerToken,
                'labels': <String, Object?>{
                  'again': card.labels.again,
                  'hard': card.labels.hard,
                  'good': card.labels.good,
                  'easy': card.labels.easy,
                },
              },
            )
            .toList(),
      };
    case 'answerCard':
      final answered = await engine.answerCard(
        sessionId: message['sessionId'] as String,
        queueEpoch: (message['queueEpoch'] as num).toInt(),
        answerToken: message['answerToken'] as String,
        cardId: (message['cardId'] as num).toInt(),
        rating: message['rating'] as String,
        millisecondsTaken: (message['millisecondsTaken'] as num).toInt(),
        answeredAtMillis: (message['answeredAtMillis'] as num?)?.toInt(),
        clientMutationId: message['clientMutationId'] as String?,
      );
      return <String, Object?>{
        'cardId': answered.cardId,
        'queue': answered.queue,
        'revlogCount': answered.revlogCount,
        'millisecondsTaken': answered.millisecondsTaken,
        'clientMutationId': answered.clientMutationId,
        'rating': answered.rating,
        'queueEpoch': answered.queueEpoch,
        'committed': answered.committed,
      };
    case 'getUndoStatus':
      final status = await engine.getUndoStatus();
      return <String, Object?>{
        'canUndo': status.canUndo,
        'canRedo': status.canRedo,
        'undoLabel': status.undoLabel,
        'redoLabel': status.redoLabel,
      };
    case 'undo':
      final undone = await engine.undo();
      return <String, Object?>{
        'ok': undone.ok,
        'undone': undone.undone,
        'queueEpoch': undone.queueEpoch,
      };
    case 'redo':
      final redone = await engine.redo();
      return <String, Object?>{
        'ok': redone.ok,
        'redone': redone.redone,
        'queueEpoch': redone.queueEpoch,
      };
    case 'countsForDeckToday':
      final counts = await engine.countsForDeckToday(
        (message['deckId'] as num).toInt(),
      );
      return <String, Object?>{
        'deckId': counts.deckId,
        'new': counts.newCount,
        'review': counts.reviewCount,
      };
    case 'congratsInfo':
      final info = await engine.congratsInfo();
      return <String, Object?>{
        'learnRemaining': info.learnRemaining,
        'reviewRemaining': info.reviewRemaining,
        'newRemaining': info.newRemaining,
        'haveSchedBuried': info.haveSchedBuried,
        'haveUserBuried': info.haveUserBuried,
        'isFilteredDeck': info.isFilteredDeck,
        'secsUntilNextLearn': info.secsUntilNextLearn,
        'deckDescription': info.deckDescription,
      };
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
      return const <String, Object?>{};
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
      final removedCards = await engine.deleteNotes(noteIds);
      return <String, Object?>{'removedCards': removedCards};
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
      final removedCards = await engine.deleteCards(cardIds);
      return <String, Object?>{'removedCards': removedCards};
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
      final stats = await engine.statsForCardsBatch(cardIds);
      return <String, Object?>{
        'requestedCardCount': stats.requestedCardCount,
        'foundCardCount': stats.foundCardCount,
        'newCards': stats.newCards,
        'learningCards': stats.learningCards,
        'reviewCards': stats.reviewCards,
        'suspendedCards': stats.suspendedCards,
        'buriedCards': stats.buriedCards,
        'todayAnswerCount': stats.todayAnswerCount,
        'todayLearnCount': stats.todayLearnCount,
        'todayReviewCount': stats.todayReviewCount,
        'todayRelearnCount': stats.todayRelearnCount,
        'forecastDueToday': stats.forecastDueToday,
        'forecastDue7Days': stats.forecastDue7Days,
        'forecastDue30Days': stats.forecastDue30Days,
        'revlogCount': stats.revlogCount,
        'retentionPassed': stats.retentionPassed,
        'retentionFailed': stats.retentionFailed,
      };
    case 'scheduleCardsAsNew':
      final cardIds = ((message['cardIds'] as List?) ?? const []).map((item) {
        if (item is! num) officialContractError('cardIds[]', item);
        return item.toInt();
      }).toList();
      if (cardIds.isEmpty || cardIds.any((id) => id <= 0)) {
        officialContractError('cardIds', cardIds);
      }
      final scheduledCards = await engine.scheduleCardsAsNew(cardIds);
      return <String, Object?>{'scheduledCards': scheduledCards};
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
      final outcome = await engine.answerAheadCards(answers);
      return <String, Object?>{
        'answeredCards': outcome.answered,
        'skippedRatedToday': outcome.skippedRatedToday,
      };
    case 'ensureTodayNewQuota':
      final deckId = (message['deckId'] as num?)?.toInt() ?? 0;
      final neededNew = (message['neededNew'] as num?)?.toInt() ?? 0;
      if (deckId <= 0 || neededNew < 0) {
        officialContractError('ensureTodayNewQuota', message);
      }
      final extendedBy = await engine.ensureTodayNewQuota(
        deckId: deckId,
        neededNew: neededNew,
      );
      return <String, Object?>{'extendedBy': extendedBy};
    default:
      throw OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidArgument,
        messageKey: 'official_anki.unknown_worker_command',
        debugDetails: message['op']?.toString(),
      );
  }
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

Map<String, Object?> _renderedCardMap(OfficialAnkiRenderedCard card) {
  return <String, Object?>{
    'cardId': card.cardId,
    'questionHtml': card.questionHtml,
    'answerHtml': card.answerHtml,
    'questionDisplayHtml': card.questionDisplayHtml,
    'answerDisplayHtml': card.answerDisplayHtml,
    'css': card.css,
    'latexSvg': card.latexSvg,
    'isEmpty': card.isEmpty,
    'questionAvTags': card.questionAvTags.map(_avTagMap).toList(),
    'answerAvTags': card.answerAvTags.map(_avTagMap).toList(),
    'typedAnswer': card.typedAnswer == null
        ? null
        : <String, Object?>{
            'marker': card.typedAnswer!.marker,
            'fontFamily': card.typedAnswer!.fontFamily,
            'fontSizePx': card.typedAnswer!.fontSizePx,
            'combining': card.typedAnswer!.combining,
            'clozeOrdinal': card.typedAnswer!.clozeOrdinal,
          },
    'templateOrdinal': card.templateOrdinal,
    'bodyClass': card.bodyClass,
  };
}

Map<String, Object?> _avTagMap(OfficialAnkiAvTag tag) {
  if (tag.kind == OfficialAnkiAvKind.tts) {
    return <String, Object?>{
      'kind': 'tts',
      'fieldText': tag.fieldText,
      'lang': tag.lang,
      'voices': tag.voices,
      'speed': tag.speed,
      'otherArgs': tag.otherArgs,
    };
  }
  return <String, Object?>{
    'kind': 'sound_or_video',
    'filename': tag.filename,
  };
}
