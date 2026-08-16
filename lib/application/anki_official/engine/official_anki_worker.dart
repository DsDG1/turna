import 'dart:async';
import 'dart:collection';

import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';

/// Serializes all engine calls on one owner. Tests inject a fake inner engine.
class OfficialAnkiWorker implements OfficialAnkiEngine {
  OfficialAnkiWorker(this._inner);

  final OfficialAnkiEngine _inner;
  final Queue<Future<void> Function()> _queue = Queue<Future<void> Function()>();
  bool _draining = false;
  bool _disposed = false;
  String? _openProfileId;

  Future<T> _enqueue<T>(Future<T> Function() work) {
    if (_disposed) {
      return Future<T>.error(
        const OfficialAnkiException(
          code: OfficialAnkiErrorCode.invalidState,
          messageKey: 'official_anki.engine_disposed',
        ),
      );
    }
    final completer = Completer<T>();
    _queue.add(() async {
      try {
        completer.complete(await work());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    _drain();
    return completer.future;
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    while (_queue.isNotEmpty) {
      final job = _queue.removeFirst();
      await job();
    }
    _draining = false;
  }

  @override
  Future<OfficialAnkiEngineInfo> engineInfo() => _enqueue(_inner.engineInfo);

  @override
  Future<void> openProfile(OfficialAnkiPaths paths) {
    return _enqueue(() async {
      if (_openProfileId != null && _openProfileId != paths.profileId) {
        await _inner.closeCollection();
      }
      await _inner.openProfile(paths);
      _openProfileId = paths.profileId;
    });
  }

  @override
  Future<void> closeCollection() {
    return _enqueue(() async {
      await _inner.closeCollection();
      _openProfileId = null;
    });
  }

  @override
  Future<void> checkCollection() => _enqueue(_inner.checkCollection);

  @override
  Future<String> createBackup() => _enqueue(_inner.createBackup);

  @override
  Future<void> restoreBackup(String backupId) {
    return _enqueue(() => _inner.restoreBackup(backupId));
  }

  @override
  Future<OfficialAnkiImportLog> importPackage({
    required String packagePath,
    bool withScheduling = true,
    bool withDeckConfigs = true,
  }) {
    return _enqueue(
      () => _inner.importPackage(
        packagePath: packagePath,
        withScheduling: withScheduling,
        withDeckConfigs: withDeckConfigs,
      ),
    );
  }

  @override
  Future<OfficialAnkiProgress> latestProgress() => _inner.latestProgress();

  @override
  Future<void> cancel() => _inner.cancel();

  @override
  Future<OfficialAnkiCardPage> searchCardsPage({
    String search = '',
    int pageSize = 200,
    String? pageToken,
  }) {
    return _enqueue(
      () => _inner.searchCardsPage(
        search: search,
        pageSize: pageSize,
        pageToken: pageToken,
      ),
    );
  }

  @override
  Future<Map<int, List<int>>> getNoteCardsBatch(List<int> noteIds) {
    return _enqueue(() => _inner.getNoteCardsBatch(noteIds));
  }

  @override
  Future<List<OfficialAnkiCardDescriptor>> getCardDescriptorsBatch(
    List<int> cardIds,
  ) {
    return _enqueue(() => _inner.getCardDescriptorsBatch(cardIds));
  }

  @override
  Future<void> dispose() {
    return _enqueue(() async {
      await _inner.dispose();
      _disposed = true;
    });
  }
}
