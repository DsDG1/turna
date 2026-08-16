class OfficialAnkiEngineInfo {
  const OfficialAnkiEngineInfo({
    required this.abiVersion,
    required this.backendCommit,
    required this.contractMajor,
    required this.contractMinor,
    required this.capabilities,
  });

  final int abiVersion;
  final String backendCommit;
  final int contractMajor;
  final int contractMinor;
  final Set<String> capabilities;

  factory OfficialAnkiEngineInfo.fromJson(Map<String, Object?> json) {
    final raw = json['capabilities'];
    return OfficialAnkiEngineInfo(
      abiVersion: (json['abiVersion'] as num?)?.toInt() ?? 0,
      backendCommit: json['backendCommit'] as String? ?? '',
      contractMajor: (json['contractMajor'] as num?)?.toInt() ?? 0,
      contractMinor: (json['contractMinor'] as num?)?.toInt() ?? 0,
      capabilities: raw is List
          ? raw.map((item) => item.toString()).toSet()
          : const <String>{},
    );
  }

  bool has(String operation) => capabilities.contains(operation);
}

class OfficialAnkiCardDescriptor {
  const OfficialAnkiCardDescriptor({
    required this.cardId,
    required this.noteId,
    required this.deckId,
    required this.templateOrd,
    this.noteGuid,
  });

  final int cardId;
  final int noteId;
  final int deckId;
  final int templateOrd;
  final String? noteGuid;

  factory OfficialAnkiCardDescriptor.fromJson(Map<String, Object?> json) {
    return OfficialAnkiCardDescriptor(
      cardId: (json['cardId'] as num).toInt(),
      noteId: (json['noteId'] as num).toInt(),
      deckId: (json['deckId'] as num).toInt(),
      templateOrd: (json['templateOrd'] as num).toInt(),
      noteGuid: json['noteGuid'] as String?,
    );
  }
}

class OfficialAnkiImportLog {
  const OfficialAnkiImportLog({
    required this.newNoteIds,
    required this.updatedNoteIds,
    required this.duplicateNoteIds,
    required this.conflictingNoteIds,
    required this.noteCount,
    required this.cardCount,
    this.nativeImportToken,
    this.elapsedMillis = 0,
  });

  final List<int> newNoteIds;
  final List<int> updatedNoteIds;
  final List<int> duplicateNoteIds;
  final List<int> conflictingNoteIds;
  final int noteCount;
  final int cardCount;
  final String? nativeImportToken;
  final int elapsedMillis;

  List<int> get associatedNoteIds {
    final ids = <int>{
      ...newNoteIds,
      ...updatedNoteIds,
      ...duplicateNoteIds,
      ...conflictingNoteIds,
    };
    return ids.toList(growable: false);
  }

  factory OfficialAnkiImportLog.fromJson(Map<String, Object?> json) {
    List<int> ids(String snake, String camel) {
      final raw = json[snake] ?? json[camel];
      if (raw is! List) return const <int>[];
      return raw.whereType<num>().map((n) => n.toInt()).toList();
    }

    return OfficialAnkiImportLog(
      newNoteIds: ids('new_note_ids', 'newNoteIds'),
      updatedNoteIds: ids('updated_note_ids', 'updatedNoteIds'),
      duplicateNoteIds: ids('duplicate_note_ids', 'duplicateNoteIds'),
      conflictingNoteIds: ids('conflicting_note_ids', 'conflictingNoteIds'),
      noteCount: (json['note_count'] as num? ?? json['noteCount'] as num? ?? 0)
          .toInt(),
      cardCount: (json['card_count'] as num? ?? json['cardCount'] as num? ?? 0)
          .toInt(),
      nativeImportToken: json['nativeImportToken'] as String?,
      elapsedMillis:
          (json['elapsed_millis'] as num? ?? json['elapsedMillis'] as num? ?? 0)
              .toInt(),
    );
  }
}

class OfficialAnkiCardPage {
  const OfficialAnkiCardPage({
    required this.cardIds,
    this.nextPageToken,
    this.totalHint,
  });

  final List<int> cardIds;
  final String? nextPageToken;
  final int? totalHint;

  factory OfficialAnkiCardPage.fromJson(Map<String, Object?> json) {
    final raw = json['cardIds'];
    return OfficialAnkiCardPage(
      cardIds: raw is List
          ? raw.whereType<num>().map((n) => n.toInt()).toList()
          : const <int>[],
      nextPageToken: json['nextPageToken'] as String?,
      totalHint: (json['totalHint'] as num?)?.toInt(),
    );
  }
}

class OfficialAnkiProgress {
  const OfficialAnkiProgress({
    required this.stage,
    this.current = 0,
    this.total = 0,
    this.canCancel = false,
  });

  final String stage;
  final int current;
  final int total;
  final bool canCancel;
}
