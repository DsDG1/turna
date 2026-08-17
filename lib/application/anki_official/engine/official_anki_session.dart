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
import 'package:turna/application/anki_official/engine/official_anki_session_cleanup.dart';
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
    OfficialAnkiSessionCleanup? cleanup,
  })  : _isolate = isolate,
        _commands = commands,
        _control = control,
        _cleanup = cleanup ?? OfficialAnkiSessionCleanup();

  final Isolate _isolate;
  final SendPort _commands;
  final OfficialAnkiNativeTransport? _control;
  final OfficialAnkiSessionCleanup _cleanup;
  final OfficialAnkiCloseOwnership _closeOwnership = OfficialAnkiCloseOwnership();
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

  Future<Map<String, Object?>> _rpc(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
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
          (item) => OfficialAnkiDeckNode.fromJson(Map<String, Object?>.from(item)),
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

  Future<List<OfficialAnkiSourceRow>> listSources() async {
    final raw = await _rpc('listSources');
    final items = raw['sources'] as List? ?? const [];
    return items
        .whereType<Map>()
        .map(
          (item) => OfficialAnkiSourceRow(
            sourceId: item['sourceId'] as String,
            profileId: item['profileId'] as String? ?? '',
            sourceHash: item['sourceHash'] as String? ?? '',
            state: item['state'] as String? ?? '',
            displayName: item['displayName'] as String? ?? '',
          ),
        )
        .toList();
  }

  Future<List<OfficialAnkiCardDescriptor>> listCards(String sourceId) async {
    final raw = await _rpc('listCards', {'sourceId': sourceId});
    final items = raw['cards'] as List? ?? const [];
    return items
        .whereType<Map>()
        .map(
          (item) => OfficialAnkiCardDescriptor.fromJson(
            Map<String, Object?>.from(item),
          ),
        )
        .toList();
  }

  Future<void> ensureCollectionOpen() async {
    await _rpc('ensureOpen');
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
        case 'listSources':
          final sources = OfficialAnkiSourceDao(db!).listSources(paths!.profileId);
          reply.send(<String, Object?>{
            'ok': true,
            'sources': sources
                .map(
                  (row) => <String, Object?>{
                    'sourceId': row.sourceId,
                    'profileId': row.profileId,
                    'sourceHash': row.sourceHash,
                    'state': row.state,
                    'displayName': row.displayName,
                  },
                )
                .toList(),
          });
          return;
        case 'listCards':
          final cards = OfficialAnkiSourceDao(db!).listCards(
            message['sourceId'] as String,
          );
          reply.send(<String, Object?>{
            'ok': true,
            'cards': cards
                .map(
                  (card) => <String, Object?>{
                    'cardId': card.cardId,
                    'noteId': card.noteId,
                    'deckId': card.deckId,
                    'templateOrd': card.templateOrd,
                    'noteGuid': card.noteGuid,
                  },
                )
                .toList(),
          });
          return;
        case 'ensureOpen':
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
        case 'dispose':
          try {
            await engine?.dispose();
          } finally {
            db?.close();
            db = null;
            engine = null;
            orchestrator = null;
            recovery = null;
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
        'code': error.code.name.toUpperCase(),
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
