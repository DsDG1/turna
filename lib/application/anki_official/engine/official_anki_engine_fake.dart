import 'package:turna/application/anki_official/contract/official_anki_contract.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';

/// In-process engine for tests. Does not reimplement the import saga.
class FakeOfficialAnkiEngine implements OfficialAnkiEngine {
  FakeOfficialAnkiEngine({
    this.backendCommit = '967aa0d578fc75181e292e95326f9b58698da25c',
    this.openCount = 0,
  });

  final String backendCommit;
  int openCount;
  int importCount = 0;
  bool cancelRequested = false;
  bool disposed = false;
  String? openProfileId;
  final Map<String, OfficialAnkiImportLog> logsByPackage = {};
  final Map<int, List<int>> cardsByNote = {};
  final Map<int, OfficialAnkiCardDescriptor> cards = {};
  bool failImport = false;

  void seedPackage({
    required String packagePath,
    required int notes,
    required int cards,
  }) {
    final noteIds = List<int>.generate(notes, (i) => i + 1);
    final cardIds = <int>[];
    cardsByNote.clear();
    this.cards.clear();
    var cardId = 1;
    for (final noteId in noteIds) {
      final ids = <int>[];
      final extra = notes == 1 && cards == 2 ? 2 : 1;
      for (var ord = 0; ord < extra && cardId <= cards; ord++) {
        ids.add(cardId);
        this.cards[cardId] = OfficialAnkiCardDescriptor(
          cardId: cardId,
          noteId: noteId,
          deckId: 1,
          templateOrd: ord,
          noteGuid: 'guid-$noteId',
        );
        cardId++;
      }
      cardsByNote[noteId] = ids;
      cardIds.addAll(ids);
    }
    while (this.cards.length < cards) {
      final id = this.cards.length + 1;
      final noteId = ((id - 1) % notes) + 1;
      this.cards[id] = OfficialAnkiCardDescriptor(
        cardId: id,
        noteId: noteId,
        deckId: 1,
        templateOrd: 0,
        noteGuid: 'guid-$noteId',
      );
      cardsByNote.putIfAbsent(noteId, () => <int>[]).add(id);
    }
    logsByPackage[packagePath] = OfficialAnkiImportLog(
      newNoteIds: noteIds,
      updatedNoteIds: const <int>[],
      duplicateNoteIds: const <int>[],
      conflictingNoteIds: const <int>[],
      noteCount: notes,
      cardCount: this.cards.length,
      nativeImportToken: 'tok-$packagePath',
    );
  }

  @override
  Future<OfficialAnkiEngineInfo> engineInfo() async {
    return OfficialAnkiEngineInfo(
      abiVersion: 1,
      backendCommit: backendCommit,
      contractMajor: kOfficialAnkiContractMajor,
      contractMinor: kOfficialAnkiContractMinor,
      capabilities: {
        OfficialAnkiOperation.engineInfo,
        OfficialAnkiOperation.importPackage,
        OfficialAnkiOperation.searchCardsPage,
        OfficialAnkiOperation.getNoteCardsBatch,
        OfficialAnkiOperation.getCardDescriptorsBatch,
      },
    );
  }

  @override
  Future<void> openProfile(OfficialAnkiPaths paths) async {
    if (openProfileId != null && openProfileId != paths.profileId) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.collectionAlreadyOpen,
        messageKey: 'official_anki.collection_already_open',
      );
    }
    openProfileId = paths.profileId;
    openCount++;
  }

  @override
  Future<void> closeCollection() async {
    openProfileId = null;
  }

  @override
  Future<void> checkCollection() async {}

  @override
  Future<String> createBackup() async => 'bk-fake';

  @override
  Future<OfficialAnkiImportLog> importPackage({
    required String packagePath,
    bool withScheduling = true,
    bool withDeckConfigs = true,
  }) async {
    if (cancelRequested) {
      cancelRequested = false;
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.importCancelled,
        messageKey: 'official_anki.import_cancelled',
        recoverable: true,
      );
    }
    if (failImport) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.packageInvalid,
        messageKey: 'official_anki.package_invalid',
      );
    }
    importCount++;
    return logsByPackage[packagePath] ??
        const OfficialAnkiImportLog(
          newNoteIds: <int>[1],
          updatedNoteIds: <int>[],
          duplicateNoteIds: <int>[],
          conflictingNoteIds: <int>[],
          noteCount: 1,
          cardCount: 1,
          nativeImportToken: 'tok-default',
        );
  }

  @override
  Future<OfficialAnkiProgress> latestProgress() async {
    return OfficialAnkiProgress(
      stage: cancelRequested ? 'cancelling' : 'idle',
      canCancel: true,
    );
  }

  @override
  Future<void> cancel() async {
    cancelRequested = true;
  }

  @override
  Future<OfficialAnkiCardPage> searchCardsPage({
    String search = '',
    int pageSize = 200,
    String? pageToken,
  }) async {
    final ids = cards.keys.toList()..sort();
    final start = int.tryParse(pageToken ?? '0') ?? 0;
    final end = (start + pageSize).clamp(0, ids.length);
    return OfficialAnkiCardPage(
      cardIds: ids.sublist(start, end),
      nextPageToken: end < ids.length ? '$end' : null,
      totalHint: ids.length,
    );
  }

  @override
  Future<Map<int, List<int>>> getNoteCardsBatch(List<int> noteIds) async {
    return {
      for (final id in noteIds) id: List<int>.from(cardsByNote[id] ?? const <int>[]),
    };
  }

  @override
  Future<List<OfficialAnkiCardDescriptor>> getCardDescriptorsBatch(
    List<int> cardIds,
  ) async {
    return [
      for (final id in cardIds)
        if (cards[id] != null) cards[id]!,
    ];
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    openProfileId = null;
  }
}
