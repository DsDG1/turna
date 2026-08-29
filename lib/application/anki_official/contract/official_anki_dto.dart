import 'package:turna/application/anki_official/contract/official_anki_errors.dart';

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
    this.queue = 0,
    this.suspended = false,
    this.buried = false,
    this.flag = 0,
    this.marked = false,
    this.tags = const <String>[],
  });

  final int cardId;
  final int noteId;
  final int deckId;
  final int templateOrd;
  final String? noteGuid;
  final int queue;
  final bool suspended;
  final bool buried;
  final int flag;
  final bool marked;
  final List<String> tags;

  factory OfficialAnkiCardDescriptor.fromJson(Map<String, Object?> json) {
    return OfficialAnkiCardDescriptor(
      cardId: (json['cardId'] as num).toInt(),
      noteId: (json['noteId'] as num).toInt(),
      deckId: (json['deckId'] as num).toInt(),
      templateOrd: (json['templateOrd'] as num).toInt(),
      noteGuid: json['noteGuid'] as String?,
      queue: (json['queue'] as num?)?.toInt() ?? 0,
      suspended: json['suspended'] == true,
      buried: json['buried'] == true,
      flag: (json['flag'] as num?)?.toInt() ?? 0,
      marked: json['marked'] == true,
      tags: (json['tags'] as List?)
              ?.map((tag) => tag.toString())
              .toList(growable: false) ??
          const <String>[],
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
      operationToken:
          (json['operationToken'] ?? json['nativeImportToken']) as String?,
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
        fieldText:
            json['fieldText'] as String? ?? json['field_text'] as String? ?? '',
        lang: json['lang'] as String?,
        voices: voices is List
            ? voices.map((e) => e.toString()).toList()
            : const <String>[],
        speed: (json['speed'] as num?)?.toDouble(),
        otherArgs: args is List
            ? args.map((e) => e.toString()).toList()
            : const <String>[],
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
      fontFamily: json['fontFamily'] as String? ??
          json['font_family'] as String? ??
          'Arial',
      fontSizePx:
          (json['fontSizePx'] as num? ?? json['font_size_px'] as num? ?? 20)
              .toInt(),
      combining: json['combining'] != false,
      clozeOrdinal:
          (json['clozeOrdinal'] as num? ?? json['cloze_ordinal'] as num?)
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
          .map((item) =>
              OfficialAnkiAvTag.fromJson(Map<String, Object?>.from(item)))
          .toList();
    }

    String html(String camel, String snake) =>
        json[camel] as String? ?? json[snake] as String? ?? '';

    OfficialAnkiTypedAnswerHint? typed;
    final typedRaw = json['typedAnswer'] ?? json['typed_answer'];
    if (typedRaw is Map) {
      typed = OfficialAnkiTypedAnswerHint.fromJson(
          Map<String, Object?>.from(typedRaw));
    }

    final questionHtml = html('questionHtml', 'question_html');
    final answerHtml = html('answerHtml', 'answer_html');
    return OfficialAnkiRenderedCard(
      cardId: (json['cardId'] as num? ?? json['card_id'] as num? ?? 0).toInt(),
      questionHtml: questionHtml,
      answerHtml: answerHtml,
      questionDisplayHtml: html('questionDisplayHtml', 'question_display_html')
              .isEmpty
          ? html('question_text_without_av', 'questionTextWithoutAv').isEmpty
              ? questionHtml
              : html('question_text_without_av', 'questionTextWithoutAv')
          : html('questionDisplayHtml', 'question_display_html'),
      answerDisplayHtml:
          html('answerDisplayHtml', 'answer_display_html').isEmpty
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
    this.newCount = 0,
    this.learnCount = 0,
    this.reviewCount = 0,
  });

  final int deckId;
  final String name;
  final int level;
  final int newCount;
  final int learnCount;
  final int reviewCount;

  int get dueCount => newCount + learnCount + reviewCount;

  factory OfficialAnkiDeckNode.fromJson(Map<String, Object?> json) {
    int count(String camel, String snake) {
      return (json[camel] as num? ?? json[snake] as num?)?.toInt() ?? 0;
    }

    return OfficialAnkiDeckNode(
      deckId: (json['deckId'] as num? ?? json['deck_id'] as num? ?? 0).toInt(),
      name: json['name'] as String? ?? '',
      level: (json['level'] as num?)?.toInt() ?? 0,
      newCount: count('newCount', 'new_count'),
      learnCount: count('learnCount', 'learn_count'),
      reviewCount: count('reviewCount', 'review_count'),
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
      fields: raw is List
          ? raw.map((e) => e.toString()).toList()
          : const <String>[],
      truncated: json['truncated'] == true,
    );
  }
}

/// Derived per-template structural facts (contract 1.9). Field references
/// are ordinals into the notetype's field list; `filters` carry the
/// template-level facts the recognizer treats as structure. Absent (empty
/// hash) when talking to a pre-1.9 engine — callers must degrade to
/// lexicon + positional signals only.
class OfficialAnkiTemplateFact {
  const OfficialAnkiTemplateFact({
    required this.ord,
    required this.name,
    this.frontFields = const <int>[],
    this.backFields = const <int>[],
    this.typeIn = false,
    this.tts = const <String>[],
    this.hint = const <String>[],
    this.script = false,
    this.complexHtml = false,
  });

  final int ord;
  final String name;
  final List<int> frontFields;
  final List<int> backFields;
  final bool typeIn;
  final List<String> tts;
  final List<String> hint;
  final bool script;
  final bool complexHtml;

  factory OfficialAnkiTemplateFact.fromJson(Map<String, Object?> json) {
    List<int> ords(String key) {
      final raw = json[key];
      if (raw is! List) return const <int>[];
      return raw.map((e) => (e as num?)?.toInt() ?? 0).toList();
    }

    List<String> names(String key) {
      final raw = json[key];
      if (raw is! List) return const <String>[];
      return raw.map((e) => e.toString()).toList();
    }

    final filters = json['filters'];
    final filterMap =
        filters is Map ? Map<String, Object?>.from(filters) : const <String, Object?>{};
    return OfficialAnkiTemplateFact(
      ord: (json['ord'] as num? ?? 0).toInt(),
      name: json['name'] as String? ?? '',
      frontFields: ords('frontFields'),
      backFields: ords('backFields'),
      typeIn: filterMap['typeIn'] == true,
      tts: names('tts'),
      hint: names('hint'),
      script: filterMap['script'] == true,
      complexHtml: filterMap['complexHtml'] == true,
    );
  }
}

/// One entry of the notetype's precomputed `config.reqs`: which fields a
/// card of `cardOrd` depends on (ANY = at least one, ALL = all).
class OfficialAnkiCardRequirement {
  const OfficialAnkiCardRequirement({
    required this.cardOrd,
    required this.kind,
    this.fieldOrds = const <int>[],
  });

  final int cardOrd;
  final String kind;
  final List<int> fieldOrds;

  factory OfficialAnkiCardRequirement.fromJson(Map<String, Object?> json) {
    final raw = json['fieldOrds'];
    return OfficialAnkiCardRequirement(
      cardOrd: (json['cardOrd'] as num? ?? 0).toInt(),
      kind: json['kind'] as String? ?? 'NONE',
      fieldOrds: raw is List
          ? raw.map((e) => (e as num?)?.toInt() ?? 0).toList()
          : const <int>[],
    );
  }
}

class OfficialAnkiTemplateFacts {
  const OfficialAnkiTemplateFacts({
    this.hash = '',
    this.templates = const <OfficialAnkiTemplateFact>[],
    this.reqs = const <OfficialAnkiCardRequirement>[],
  });

  final String hash;
  final List<OfficialAnkiTemplateFact> templates;
  final List<OfficialAnkiCardRequirement> reqs;

  bool get isAvailable => hash.isNotEmpty;

  factory OfficialAnkiTemplateFacts.fromJson(Map<String, Object?> json) {
    final templates = json['templates'];
    final reqs = json['reqs'];
    return OfficialAnkiTemplateFacts(
      hash: json['hash'] as String? ?? '',
      templates: templates is List
          ? templates
              .whereType<Map>()
              .map((item) =>
                  OfficialAnkiTemplateFact.fromJson(Map<String, Object?>.from(item)))
              .toList()
          : const <OfficialAnkiTemplateFact>[],
      reqs: reqs is List
          ? reqs
              .whereType<Map>()
              .map((item) =>
                  OfficialAnkiCardRequirement.fromJson(Map<String, Object?>.from(item)))
              .toList()
          : const <OfficialAnkiCardRequirement>[],
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
    this.templateFacts,
  });

  final int notetypeId;
  final String name;
  final String kind;
  final List<String> fieldNames;
  final List<String> templateNames;
  final String schemaFingerprint;
  final List<OfficialAnkiProjectionSample> samples;
  final OfficialAnkiTemplateFacts? templateFacts;

  factory OfficialAnkiProjectionSchema.fromJson(Map<String, Object?> json) {
    List<String> names(String camel, String snake) {
      final raw = json[camel] ?? json[snake];
      if (raw is! List) return const <String>[];
      return raw.map((e) => e.toString()).toList();
    }

    final samples = json['samples'];
    final templateFacts = json['templateFacts'];
    return OfficialAnkiProjectionSchema(
      notetypeId:
          (json['notetypeId'] as num? ?? json['notetype_id'] as num? ?? 0)
              .toInt(),
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
      templateFacts: templateFacts is Map
          ? OfficialAnkiTemplateFacts.fromJson(
              Map<String, Object?>.from(templateFacts))
          : null,
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
      noteGuid:
          json['noteGuid'] as String? ?? json['note_guid'] as String? ?? '',
      notetypeId:
          (json['notetypeId'] as num? ?? json['notetype_id'] as num? ?? 0)
              .toInt(),
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
      again: officialRequireNonEmpty(json, 'again'),
      hard: officialRequireNonEmpty(json, 'hard'),
      good: officialRequireNonEmpty(json, 'good'),
      easy: officialRequireNonEmpty(json, 'easy'),
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
    if (labels is! Map) {
      officialContractError('labels', labels);
    }
    return OfficialReviewQueueCard(
      cardId: officialRequirePositiveId(json, 'cardId'),
      noteId: officialRequirePositiveId(json, 'noteId'),
      deckId: officialRequirePositiveId(json, 'deckId'),
      templateOrdinal: officialRequireNonNegativeInt(json, 'templateOrdinal'),
      queueKind: officialRequireNonEmpty(json, 'queueKind'),
      answerToken: officialRequireNonEmpty(json, 'answerToken'),
      labels: OfficialReviewIntervalLabels.fromJson(
        Map<String, Object?>.from(labels),
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
    if (cards is! List) {
      officialContractError('cards', cards);
    }
    return OfficialReviewQueue(
      sessionId: officialRequireNonEmpty(json, 'sessionId'),
      queueEpoch: officialRequirePositiveId(json, 'queueEpoch'),
      newCount: officialRequireNonNegativeInt(json, 'newCount'),
      learningCount: officialRequireNonNegativeInt(json, 'learningCount'),
      reviewCount: officialRequireNonNegativeInt(json, 'reviewCount'),
      cards: [
        for (final item in cards)
          OfficialReviewQueueCard.fromJson(
            item is Map
                ? Map<String, Object?>.from(item)
                : officialContractError('cards[]', item),
          ),
      ],
    );
  }
}

class OfficialAnswerResult {
  const OfficialAnswerResult({
    required this.cardId,
    required this.queue,
    required this.revlogCount,
    required this.millisecondsTaken,
    this.clientMutationId,
    this.rating = '',
    this.queueEpoch = 0,
    this.committed = true,
  });

  final int cardId;
  final String queue;
  final int revlogCount;
  final int millisecondsTaken;
  final String? clientMutationId;
  final String rating;
  final int queueEpoch;
  final bool committed;

  factory OfficialAnswerResult.fromJson(Map<String, Object?> json) {
    return OfficialAnswerResult(
      cardId: officialRequirePositiveId(json, 'cardId'),
      queue: officialRequireNonEmpty(json, 'queue'),
      revlogCount: officialRequireNonNegativeInt(json, 'revlogCount'),
      millisecondsTaken:
          officialRequireNonNegativeInt(json, 'millisecondsTaken'),
      clientMutationId: json['clientMutationId'] as String?,
      rating: officialRequireNonEmpty(json, 'rating'),
      queueEpoch: officialRequirePositiveId(json, 'queueEpoch'),
      committed: officialRequireBool(json, 'committed'),
    );
  }
}

/// One Official rating issued outside the live review session (lesson redo).
class OfficialAheadAnswer {
  const OfficialAheadAnswer({
    required this.cardId,
    required this.rating,
    this.millisecondsTaken = 0,
  });

  final int cardId;

  /// `again` / `hard` / `good` / `easy`.
  final String rating;
  final int millisecondsTaken;

  Map<String, Object?> toJson() => {
        'cardId': cardId,
        'rating': rating,
        'millisecondsTaken': millisecondsTaken,
      };
}

class OfficialUndoStatus {
  const OfficialUndoStatus({
    required this.canUndo,
    required this.canRedo,
    this.undoLabel,
    this.redoLabel,
  });

  final bool canUndo;
  final bool canRedo;
  final String? undoLabel;
  final String? redoLabel;

  factory OfficialUndoStatus.fromJson(Map<String, Object?> json) {
    return OfficialUndoStatus(
      canUndo: json['canUndo'] == true || json['can_undo'] == true,
      canRedo: json['canRedo'] == true || json['can_redo'] == true,
      undoLabel: json['undoLabel'] as String?,
      redoLabel: json['redoLabel'] as String?,
    );
  }
}

class OfficialMutationResult {
  const OfficialMutationResult({
    required this.ok,
    this.undone = false,
    this.redone = false,
    this.queueEpoch = 0,
  });

  final bool ok;
  final bool undone;
  final bool redone;
  final int queueEpoch;

  factory OfficialMutationResult.fromJson(Map<String, Object?> json) {
    final ok = officialRequireBool(json, 'ok');
    return OfficialMutationResult(
      ok: ok,
      undone: json['undone'] == true,
      redone: json['redone'] == true,
      queueEpoch: officialRequirePositiveId(json, 'queueEpoch'),
    );
  }
}

class OfficialDeckCounts {
  const OfficialDeckCounts({
    required this.deckId,
    required this.newCount,
    required this.reviewCount,
  });

  final int deckId;
  final int newCount;
  final int reviewCount;

  @Deprecated('Use newCount')
  int get newStudied => newCount;

  @Deprecated('Use reviewCount')
  int get reviewStudied => reviewCount;

  factory OfficialDeckCounts.fromJson(Map<String, Object?> json) {
    final newRaw = json['new'] ?? json['newStudied'];
    final reviewRaw = json['review'] ?? json['reviewStudied'];
    if (newRaw is! num) {
      officialContractError('new', newRaw);
    }
    if (reviewRaw is! num) {
      officialContractError('review', reviewRaw);
    }
    if (newRaw.toInt() < 0) {
      officialContractError('new', newRaw);
    }
    if (reviewRaw.toInt() < 0) {
      officialContractError('review', reviewRaw);
    }
    return OfficialDeckCounts(
      deckId: officialRequirePositiveId(json, 'deckId'),
      newCount: newRaw.toInt(),
      reviewCount: reviewRaw.toInt(),
    );
  }
}

/// Additive, exact-card statistics returned by one native batch. Callers may
/// sum non-overlapping batches; [foundCardCount] must equal
/// [requestedCardCount] or the catalog/collection evidence is stale.
class OfficialAnkiStatsBatch {
  const OfficialAnkiStatsBatch({
    required this.requestedCardCount,
    required this.foundCardCount,
    required this.newCards,
    required this.learningCards,
    required this.reviewCards,
    required this.suspendedCards,
    required this.buriedCards,
    required this.todayAnswerCount,
    required this.todayLearnCount,
    required this.todayReviewCount,
    required this.todayRelearnCount,
    required this.forecastDueToday,
    required this.forecastDue7Days,
    required this.forecastDue30Days,
    required this.revlogCount,
    required this.retentionPassed,
    required this.retentionFailed,
  });

  final int requestedCardCount;
  final int foundCardCount;
  final int newCards;
  final int learningCards;
  final int reviewCards;
  final int suspendedCards;
  final int buriedCards;
  final int todayAnswerCount;
  final int todayLearnCount;
  final int todayReviewCount;
  final int todayRelearnCount;
  final int forecastDueToday;
  final int forecastDue7Days;
  final int forecastDue30Days;
  final int revlogCount;
  final int retentionPassed;
  final int retentionFailed;

  int get retentionSample => retentionPassed + retentionFailed;

  factory OfficialAnkiStatsBatch.fromJson(Map<String, Object?> json) {
    int value(String key) => officialRequireNonNegativeInt(json, key);
    return OfficialAnkiStatsBatch(
      requestedCardCount: value('requestedCardCount'),
      foundCardCount: value('foundCardCount'),
      newCards: value('newCards'),
      learningCards: value('learningCards'),
      reviewCards: value('reviewCards'),
      suspendedCards: value('suspendedCards'),
      buriedCards: value('buriedCards'),
      todayAnswerCount: value('todayAnswerCount'),
      todayLearnCount: value('todayLearnCount'),
      todayReviewCount: value('todayReviewCount'),
      todayRelearnCount: value('todayRelearnCount'),
      forecastDueToday: value('forecastDueToday'),
      forecastDue7Days: value('forecastDue7Days'),
      forecastDue30Days: value('forecastDue30Days'),
      revlogCount: value('revlogCount'),
      retentionPassed: value('retentionPassed'),
      retentionFailed: value('retentionFailed'),
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
    this.deckDescription = '',
  });

  final int learnRemaining;
  final bool reviewRemaining;
  final bool newRemaining;
  final bool haveSchedBuried;
  final bool haveUserBuried;
  final bool isFilteredDeck;
  final int secsUntilNextLearn;
  final String deckDescription;

  factory OfficialCongratsInfo.fromJson(Map<String, Object?> json) {
    return OfficialCongratsInfo(
      learnRemaining: (json['learnRemaining'] as num? ?? 0).toInt(),
      reviewRemaining: json['reviewRemaining'] == true,
      newRemaining: json['newRemaining'] == true,
      haveSchedBuried: json['haveSchedBuried'] == true,
      haveUserBuried: json['haveUserBuried'] == true,
      isFilteredDeck: json['isFilteredDeck'] == true,
      secsUntilNextLearn: (json['secsUntilNextLearn'] as num? ?? 0).toInt(),
      deckDescription: json['deckDescription'] as String? ?? '',
    );
  }
}

enum OfficialBuryOrSuspendAction {
  suspend,
  burySched,
  buryUser,
  restoreCards,
  unburyDeckAll,
  unburyDeckSchedOnly,
  unburyDeckUserOnly;

  static OfficialBuryOrSuspendAction parse(String? wire) {
    final name = wire ?? '';
    for (final action in OfficialBuryOrSuspendAction.values) {
      if (action.wireName == name) return action;
    }
    throw OfficialAnkiException(
      code: OfficialAnkiErrorCode.invalidArgument,
      messageKey: 'official_anki.invalid_bury_action',
      debugDetails: name,
    );
  }

  bool get requiresCardIds =>
      this == OfficialBuryOrSuspendAction.suspend ||
      this == OfficialBuryOrSuspendAction.burySched ||
      this == OfficialBuryOrSuspendAction.buryUser ||
      this == OfficialBuryOrSuspendAction.restoreCards;
}

extension OfficialBuryOrSuspendActionX on OfficialBuryOrSuspendAction {
  String get wireName {
    switch (this) {
      case OfficialBuryOrSuspendAction.suspend:
        return 'suspend';
      case OfficialBuryOrSuspendAction.burySched:
        return 'burySched';
      case OfficialBuryOrSuspendAction.buryUser:
        return 'buryUser';
      case OfficialBuryOrSuspendAction.restoreCards:
        return 'restoreCards';
      case OfficialBuryOrSuspendAction.unburyDeckAll:
        return 'unburyDeckAll';
      case OfficialBuryOrSuspendAction.unburyDeckSchedOnly:
        return 'unburyDeckSchedOnly';
      case OfficialBuryOrSuspendAction.unburyDeckUserOnly:
        return 'unburyDeckUserOnly';
    }
  }
}

Never officialContractError(String field, Object? value) {
  throw OfficialAnkiException(
    code: OfficialAnkiErrorCode.invalidArgument,
    messageKey: 'official_anki.contract_decode_failed',
    debugDetails: 'field=$field value=$value',
  );
}

int officialRequirePositiveId(Map<String, Object?> json, String key) {
  final raw = json[key];
  if (raw is! num) officialContractError(key, raw);
  final value = raw.toInt();
  if (value <= 0) officialContractError(key, value);
  return value;
}

int officialRequireNonNegativeInt(Map<String, Object?> json, String key) {
  final raw = json[key];
  if (raw is! num) officialContractError(key, raw);
  final value = raw.toInt();
  if (value < 0) officialContractError(key, value);
  return value;
}

String officialRequireNonEmpty(Map<String, Object?> json, String key) {
  final raw = json[key];
  if (raw is! String || raw.isEmpty) officialContractError(key, raw);
  return raw;
}

bool officialRequireBool(
  Map<String, Object?> json,
  String key, {
  List<String> aliases = const <String>[],
}) {
  for (final candidate in [key, ...aliases]) {
    if (!json.containsKey(candidate)) continue;
    final raw = json[candidate];
    if (raw is bool) return raw;
    officialContractError(candidate, raw);
  }
  officialContractError(key, null);
}
