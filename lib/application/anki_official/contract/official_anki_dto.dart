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
    this.operationToken,
    this.elapsedMillis = 0,
  });

  final List<int> newNoteIds;
  final List<int> updatedNoteIds;
  final List<int> duplicateNoteIds;
  final List<int> conflictingNoteIds;
  final int noteCount;
  final int cardCount;
  final String? operationToken;
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
      operationToken: (json['operationToken'] ?? json['nativeImportToken'])
          as String?,
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

class OfficialAnkiAvTag {
  const OfficialAnkiAvTag.sound(this.filename)
      : kind = OfficialAnkiAvKind.soundOrVideo,
        fieldText = null,
        lang = null,
        voices = const <String>[],
        speed = null,
        otherArgs = const <String>[];

  const OfficialAnkiAvTag.tts({
    required this.fieldText,
    this.lang,
    this.voices = const <String>[],
    this.speed,
    this.otherArgs = const <String>[],
  })  : kind = OfficialAnkiAvKind.tts,
        filename = null;

  final OfficialAnkiAvKind kind;
  final String? filename;
  final String? fieldText;
  final String? lang;
  final List<String> voices;
  final double? speed;
  final List<String> otherArgs;

  factory OfficialAnkiAvTag.fromJson(Map<String, Object?> json) {
    final kind = json['kind'] as String? ?? '';
    if (kind == 'tts') {
      final voices = json['voices'];
      final args = json['otherArgs'] ?? json['other_args'];
      return OfficialAnkiAvTag.tts(
        fieldText: json['fieldText'] as String? ?? json['field_text'] as String? ?? '',
        lang: json['lang'] as String?,
        voices: voices is List ? voices.map((e) => e.toString()).toList() : const <String>[],
        speed: (json['speed'] as num?)?.toDouble(),
        otherArgs: args is List ? args.map((e) => e.toString()).toList() : const <String>[],
      );
    }
    return OfficialAnkiAvTag.sound(
      json['filename'] as String? ?? '',
    );
  }
}

enum OfficialAnkiAvKind { soundOrVideo, tts }

class OfficialAnkiTypedAnswerHint {
  const OfficialAnkiTypedAnswerHint({
    required this.marker,
    this.fontFamily = 'Arial',
    this.fontSizePx = 20,
    this.combining = true,
    this.clozeOrdinal,
  });

  final String marker;
  final String fontFamily;
  final int fontSizePx;
  final bool combining;
  final int? clozeOrdinal;

  factory OfficialAnkiTypedAnswerHint.fromJson(Map<String, Object?> json) {
    return OfficialAnkiTypedAnswerHint(
      marker: json['marker'] as String? ?? '',
      fontFamily: json['fontFamily'] as String? ?? json['font_family'] as String? ?? 'Arial',
      fontSizePx:
          (json['fontSizePx'] as num? ?? json['font_size_px'] as num? ?? 20).toInt(),
      combining: json['combining'] != false,
      clozeOrdinal: (json['clozeOrdinal'] as num? ?? json['cloze_ordinal'] as num?)
          ?.toInt(),
    );
  }
}

class OfficialAnkiTypedComparison {
  const OfficialAnkiTypedComparison({
    required this.comparisonHtml,
    required this.hasExpected,
  });

  final String comparisonHtml;
  final bool hasExpected;

  factory OfficialAnkiTypedComparison.fromJson(Map<String, Object?> json) {
    return OfficialAnkiTypedComparison(
      comparisonHtml: json['comparisonHtml'] as String? ??
          json['comparison_html'] as String? ??
          '',
      hasExpected: json['hasExpected'] == true || json['has_expected'] == true,
    );
  }
}

class OfficialAnkiRenderedCard {
  const OfficialAnkiRenderedCard({
    required this.cardId,
    required this.questionHtml,
    required this.answerHtml,
    required this.questionDisplayHtml,
    required this.answerDisplayHtml,
    required this.css,
    this.latexSvg = false,
    this.isEmpty = false,
    this.questionAvTags = const <OfficialAnkiAvTag>[],
    this.answerAvTags = const <OfficialAnkiAvTag>[],
    this.typedAnswer,
    this.templateOrdinal = 0,
    this.bodyClass = 'card card1',
  });

  final int cardId;
  final String questionHtml;
  final String answerHtml;
  final String questionDisplayHtml;
  final String answerDisplayHtml;
  final String css;
  final bool latexSvg;
  final bool isEmpty;
  final List<OfficialAnkiAvTag> questionAvTags;
  final List<OfficialAnkiAvTag> answerAvTags;
  final OfficialAnkiTypedAnswerHint? typedAnswer;
  final int templateOrdinal;
  final String bodyClass;

  factory OfficialAnkiRenderedCard.fromJson(Map<String, Object?> json) {
    List<OfficialAnkiAvTag> tags(String camel, String snake) {
      final raw = json[camel] ?? json[snake];
      if (raw is! List) return const <OfficialAnkiAvTag>[];
      return raw
          .whereType<Map>()
          .map((item) => OfficialAnkiAvTag.fromJson(Map<String, Object?>.from(item)))
          .toList();
    }

    String html(String camel, String snake) =>
        json[camel] as String? ?? json[snake] as String? ?? '';

    OfficialAnkiTypedAnswerHint? typed;
    final typedRaw = json['typedAnswer'] ?? json['typed_answer'];
    if (typedRaw is Map) {
      typed = OfficialAnkiTypedAnswerHint.fromJson(Map<String, Object?>.from(typedRaw));
    }

    final questionHtml = html('questionHtml', 'question_html');
    final answerHtml = html('answerHtml', 'answer_html');
    return OfficialAnkiRenderedCard(
      cardId: (json['cardId'] as num? ?? json['card_id'] as num? ?? 0).toInt(),
      questionHtml: questionHtml,
      answerHtml: answerHtml,
      questionDisplayHtml: html('questionDisplayHtml', 'question_display_html').isEmpty
          ? html('question_text_without_av', 'questionTextWithoutAv').isEmpty
              ? questionHtml
              : html('question_text_without_av', 'questionTextWithoutAv')
          : html('questionDisplayHtml', 'question_display_html'),
      answerDisplayHtml: html('answerDisplayHtml', 'answer_display_html').isEmpty
          ? html('answer_text_without_av', 'answerTextWithoutAv').isEmpty
              ? answerHtml
              : html('answer_text_without_av', 'answerTextWithoutAv')
          : html('answerDisplayHtml', 'answer_display_html'),
      css: json['css'] as String? ?? '',
      latexSvg: json['latexSvg'] == true || json['latex_svg'] == true,
      isEmpty: json['isEmpty'] == true || json['is_empty'] == true,
      questionAvTags: tags('questionAvTags', 'question_av_tags'),
      answerAvTags: tags('answerAvTags', 'answer_av_tags'),
      typedAnswer: typed,
      templateOrdinal: (json['templateOrdinal'] as num? ??
              json['template_ordinal'] as num? ??
              0)
          .toInt(),
      bodyClass: json['bodyClass'] as String? ??
          json['body_class'] as String? ??
          'card card1',
    );
  }
}

class OfficialAnkiDeckNode {
  const OfficialAnkiDeckNode({
    required this.deckId,
    required this.name,
    this.level = 0,
  });

  final int deckId;
  final String name;
  final int level;

  factory OfficialAnkiDeckNode.fromJson(Map<String, Object?> json) {
    return OfficialAnkiDeckNode(
      deckId: (json['deckId'] as num? ?? json['deck_id'] as num? ?? 0).toInt(),
      name: json['name'] as String? ?? '',
      level: (json['level'] as num?)?.toInt() ?? 0,
    );
  }
}

class OfficialAnkiProjectionSample {
  const OfficialAnkiProjectionSample({
    required this.noteId,
    required this.fields,
    this.truncated = false,
  });

  final int noteId;
  final List<String> fields;
  final bool truncated;

  factory OfficialAnkiProjectionSample.fromJson(Map<String, Object?> json) {
    final raw = json['fields'];
    return OfficialAnkiProjectionSample(
      noteId: (json['noteId'] as num? ?? json['note_id'] as num? ?? 0).toInt(),
      fields: raw is List ? raw.map((e) => e.toString()).toList() : const <String>[],
      truncated: json['truncated'] == true,
    );
  }
}

class OfficialAnkiProjectionSchema {
  const OfficialAnkiProjectionSchema({
    required this.notetypeId,
    required this.name,
    required this.kind,
    required this.fieldNames,
    required this.templateNames,
    required this.schemaFingerprint,
    this.samples = const <OfficialAnkiProjectionSample>[],
  });

  final int notetypeId;
  final String name;
  final String kind;
  final List<String> fieldNames;
  final List<String> templateNames;
  final String schemaFingerprint;
  final List<OfficialAnkiProjectionSample> samples;

  factory OfficialAnkiProjectionSchema.fromJson(Map<String, Object?> json) {
    List<String> names(String camel, String snake) {
      final raw = json[camel] ?? json[snake];
      if (raw is! List) return const <String>[];
      return raw.map((e) => e.toString()).toList();
    }

    final samples = json['samples'];
    return OfficialAnkiProjectionSchema(
      notetypeId:
          (json['notetypeId'] as num? ?? json['notetype_id'] as num? ?? 0).toInt(),
      name: json['name'] as String? ?? '',
      kind: json['kind'] as String? ?? 'normal',
      fieldNames: names('fieldNames', 'field_names'),
      templateNames: names('templateNames', 'template_names'),
      schemaFingerprint: json['schemaFingerprint'] as String? ??
          json['schema_fingerprint'] as String? ??
          '',
      samples: samples is List
          ? samples
              .whereType<Map>()
              .map(
                (item) => OfficialAnkiProjectionSample.fromJson(
                  Map<String, Object?>.from(item),
                ),
              )
              .toList()
          : const <OfficialAnkiProjectionSample>[],
    );
  }
}

class OfficialAnkiProjectionSnapshot {
  const OfficialAnkiProjectionSnapshot({
    required this.snapshotToken,
    required this.collectionGeneration,
    required this.backendCommit,
  });

  final String snapshotToken;
  final int collectionGeneration;
  final String backendCommit;

  factory OfficialAnkiProjectionSnapshot.fromJson(Map<String, Object?> json) {
    return OfficialAnkiProjectionSnapshot(
      snapshotToken: json['snapshotToken'] as String? ??
          json['snapshot_token'] as String? ??
          '',
      collectionGeneration: (json['collectionGeneration'] as num? ??
              json['collection_generation'] as num? ??
              0)
          .toInt(),
      backendCommit: json['backendCommit'] as String? ??
          json['backend_commit'] as String? ??
          '',
    );
  }
}

class OfficialAnkiProjectionRow {
  const OfficialAnkiProjectionRow({
    required this.cardId,
    required this.noteId,
    required this.noteGuid,
    required this.notetypeId,
    required this.deckId,
    required this.deckPath,
    required this.templateOrdinal,
    required this.tags,
    required this.fields,
    required this.sourceFingerprint,
    this.truncated = false,
  });

  final int cardId;
  final int noteId;
  final String noteGuid;
  final int notetypeId;
  final int deckId;
  final List<String> deckPath;
  final int templateOrdinal;
  final List<String> tags;
  final List<String> fields;
  final String sourceFingerprint;
  final bool truncated;

  factory OfficialAnkiProjectionRow.fromJson(Map<String, Object?> json) {
    List<String> list(String camel, String snake) {
      final raw = json[camel] ?? json[snake];
      if (raw is! List) return const <String>[];
      return raw.map((e) => e.toString()).toList();
    }

    return OfficialAnkiProjectionRow(
      cardId: (json['cardId'] as num? ?? json['card_id'] as num? ?? 0).toInt(),
      noteId: (json['noteId'] as num? ?? json['note_id'] as num? ?? 0).toInt(),
      noteGuid: json['noteGuid'] as String? ?? json['note_guid'] as String? ?? '',
      notetypeId:
          (json['notetypeId'] as num? ?? json['notetype_id'] as num? ?? 0).toInt(),
      deckId: (json['deckId'] as num? ?? json['deck_id'] as num? ?? 0).toInt(),
      deckPath: list('deckPath', 'deck_path'),
      templateOrdinal: (json['templateOrdinal'] as num? ??
              json['template_ordinal'] as num? ??
              0)
          .toInt(),
      tags: list('tags', 'tags'),
      fields: list('fields', 'fields'),
      sourceFingerprint: json['sourceFingerprint'] as String? ??
          json['source_fingerprint'] as String? ??
          '',
      truncated: json['truncated'] == true,
    );
  }
}

class OfficialAnkiProjectionPage {
  const OfficialAnkiProjectionPage({
    required this.rows,
    this.missingCardIds = const <int>[],
  });

  final List<OfficialAnkiProjectionRow> rows;
  final List<int> missingCardIds;

  factory OfficialAnkiProjectionPage.fromJson(Map<String, Object?> json) {
    final rows = json['rows'];
    final missing = json['missingCardIds'] ?? json['missing_card_ids'];
    return OfficialAnkiProjectionPage(
      rows: rows is List
          ? rows
              .whereType<Map>()
              .map(
                (item) => OfficialAnkiProjectionRow.fromJson(
                  Map<String, Object?>.from(item),
                ),
              )
              .toList()
          : const <OfficialAnkiProjectionRow>[],
      missingCardIds: missing is List
          ? missing.whereType<num>().map((n) => n.toInt()).toList()
          : const <int>[],
    );
  }
}

class OfficialReviewIntervalLabels {
  const OfficialReviewIntervalLabels({
    required this.again,
    required this.hard,
    required this.good,
    required this.easy,
  });

  final String again;
  final String hard;
  final String good;
  final String easy;

  factory OfficialReviewIntervalLabels.fromJson(Map<String, Object?> json) {
    return OfficialReviewIntervalLabels(
      again: json['again'] as String? ?? '',
      hard: json['hard'] as String? ?? '',
      good: json['good'] as String? ?? '',
      easy: json['easy'] as String? ?? '',
    );
  }
}

class OfficialReviewQueueCard {
  const OfficialReviewQueueCard({
    required this.cardId,
    required this.noteId,
    required this.deckId,
    required this.templateOrdinal,
    required this.queueKind,
    required this.answerToken,
    required this.labels,
  });

  final int cardId;
  final int noteId;
  final int deckId;
  final int templateOrdinal;
  final String queueKind;
  final String answerToken;
  final OfficialReviewIntervalLabels labels;

  factory OfficialReviewQueueCard.fromJson(Map<String, Object?> json) {
    final labels = json['labels'];
    return OfficialReviewQueueCard(
      cardId: (json['cardId'] as num? ?? 0).toInt(),
      noteId: (json['noteId'] as num? ?? 0).toInt(),
      deckId: (json['deckId'] as num? ?? 0).toInt(),
      templateOrdinal: (json['templateOrdinal'] as num? ?? 0).toInt(),
      queueKind: json['queueKind'] as String? ?? '',
      answerToken: json['answerToken'] as String? ?? '',
      labels: labels is Map
          ? OfficialReviewIntervalLabels.fromJson(Map<String, Object?>.from(labels))
          : const OfficialReviewIntervalLabels(
              again: '',
              hard: '',
              good: '',
              easy: '',
            ),
    );
  }
}

class OfficialReviewQueue {
  const OfficialReviewQueue({
    required this.sessionId,
    required this.queueEpoch,
    required this.newCount,
    required this.learningCount,
    required this.reviewCount,
    required this.cards,
  });

  final String sessionId;
  final int queueEpoch;
  final int newCount;
  final int learningCount;
  final int reviewCount;
  final List<OfficialReviewQueueCard> cards;

  factory OfficialReviewQueue.fromJson(Map<String, Object?> json) {
    final cards = json['cards'];
    return OfficialReviewQueue(
      sessionId: json['sessionId'] as String? ?? '',
      queueEpoch: (json['queueEpoch'] as num? ?? 0).toInt(),
      newCount: (json['newCount'] as num? ?? 0).toInt(),
      learningCount: (json['learningCount'] as num? ?? 0).toInt(),
      reviewCount: (json['reviewCount'] as num? ?? 0).toInt(),
      cards: cards is List
          ? cards
              .whereType<Map>()
              .map(
                (item) => OfficialReviewQueueCard.fromJson(
                  Map<String, Object?>.from(item),
                ),
              )
              .toList()
          : const <OfficialReviewQueueCard>[],
    );
  }
}

class OfficialAnswerResult {
  const OfficialAnswerResult({
    required this.cardId,
    required this.queue,
    required this.revlogCount,
    required this.millisecondsTaken,
  });

  final int cardId;
  final String queue;
  final int revlogCount;
  final int millisecondsTaken;

  factory OfficialAnswerResult.fromJson(Map<String, Object?> json) {
    return OfficialAnswerResult(
      cardId: (json['cardId'] as num? ?? 0).toInt(),
      queue: json['queue'] as String? ?? '',
      revlogCount: (json['revlogCount'] as num? ?? 0).toInt(),
      millisecondsTaken: (json['millisecondsTaken'] as num? ?? 0).toInt(),
    );
  }
}

class OfficialUndoStatus {
  const OfficialUndoStatus({
    required this.canUndo,
    required this.canRedo,
  });

  final bool canUndo;
  final bool canRedo;

  factory OfficialUndoStatus.fromJson(Map<String, Object?> json) {
    return OfficialUndoStatus(
      canUndo: json['canUndo'] == true || json['can_undo'] == true,
      canRedo: json['canRedo'] == true || json['can_redo'] == true,
    );
  }
}

class OfficialMutationResult {
  const OfficialMutationResult({
    required this.ok,
    this.undone = false,
    this.redone = false,
  });

  final bool ok;
  final bool undone;
  final bool redone;

  factory OfficialMutationResult.fromJson(Map<String, Object?> json) {
    return OfficialMutationResult(
      ok: true,
      undone: json['undone'] == true,
      redone: json['redone'] == true,
    );
  }
}

class OfficialDeckCounts {
  const OfficialDeckCounts({
    required this.deckId,
    required this.newStudied,
    required this.reviewStudied,
  });

  final int deckId;
  final int newStudied;
  final int reviewStudied;

  factory OfficialDeckCounts.fromJson(Map<String, Object?> json) {
    return OfficialDeckCounts(
      deckId: (json['deckId'] as num? ?? 0).toInt(),
      newStudied: (json['newStudied'] as num? ?? 0).toInt(),
      reviewStudied: (json['reviewStudied'] as num? ?? 0).toInt(),
    );
  }
}

class OfficialCongratsInfo {
  const OfficialCongratsInfo({
    required this.learnRemaining,
    required this.reviewRemaining,
    required this.newRemaining,
    required this.haveSchedBuried,
    required this.haveUserBuried,
    required this.isFilteredDeck,
    required this.secsUntilNextLearn,
  });

  final int learnRemaining;
  final bool reviewRemaining;
  final bool newRemaining;
  final bool haveSchedBuried;
  final bool haveUserBuried;
  final bool isFilteredDeck;
  final int secsUntilNextLearn;

  factory OfficialCongratsInfo.fromJson(Map<String, Object?> json) {
    return OfficialCongratsInfo(
      learnRemaining: (json['learnRemaining'] as num? ?? 0).toInt(),
      reviewRemaining: json['reviewRemaining'] == true,
      newRemaining: json['newRemaining'] == true,
      haveSchedBuried: json['haveSchedBuried'] == true,
      haveUserBuried: json['haveUserBuried'] == true,
      isFilteredDeck: json['isFilteredDeck'] == true,
      secsUntilNextLearn: (json['secsUntilNextLearn'] as num? ?? 0).toInt(),
    );
  }
}

enum OfficialBuryOrSuspendAction {
  buryCard,
  burySiblings,
  unburyDeck,
  suspendCards,
  unsuspendCards,
}

extension OfficialBuryOrSuspendActionX on OfficialBuryOrSuspendAction {
  String get wireName {
    switch (this) {
      case OfficialBuryOrSuspendAction.buryCard:
        return 'bury_card';
      case OfficialBuryOrSuspendAction.burySiblings:
        return 'bury_siblings';
      case OfficialBuryOrSuspendAction.unburyDeck:
        return 'unbury_deck';
      case OfficialBuryOrSuspendAction.suspendCards:
        return 'suspend_cards';
      case OfficialBuryOrSuspendAction.unsuspendCards:
        return 'unsuspend_cards';
    }
  }
}
