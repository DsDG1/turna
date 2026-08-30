// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'official_anki_dto.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

OfficialAnkiCardPage _$OfficialAnkiCardPageFromJson(
        Map<String, dynamic> json) =>
    OfficialAnkiCardPage(
      cardIds: (json['cardIds'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          [],
      nextPageToken: json['nextPageToken'] as String?,
      totalHint: (json['totalHint'] as num?)?.toInt(),
    );

OfficialAnkiTypedAnswerHint _$OfficialAnkiTypedAnswerHintFromJson(
        Map<String, dynamic> json) =>
    OfficialAnkiTypedAnswerHint(
      marker: json['marker'] as String? ?? '',
      fontFamily: json['fontFamily'] as String? ?? 'Arial',
      fontSizePx: (json['fontSizePx'] as num?)?.toInt() ?? 20,
      combining: json['combining'] as bool? ?? true,
      clozeOrdinal: (json['clozeOrdinal'] as num?)?.toInt(),
    );

OfficialAnkiTypedComparison _$OfficialAnkiTypedComparisonFromJson(
        Map<String, dynamic> json) =>
    OfficialAnkiTypedComparison(
      comparisonHtml: json['comparisonHtml'] as String? ?? '',
      hasExpected: json['hasExpected'] as bool? ?? false,
    );

OfficialAnkiProjectionSample _$OfficialAnkiProjectionSampleFromJson(
        Map<String, dynamic> json) =>
    OfficialAnkiProjectionSample(
      noteId: (json['noteId'] as num?)?.toInt() ?? 0,
      fields: (json['fields'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      truncated: json['truncated'] as bool? ?? false,
    );

OfficialAnkiCardRequirement _$OfficialAnkiCardRequirementFromJson(
        Map<String, dynamic> json) =>
    OfficialAnkiCardRequirement(
      cardOrd: (json['cardOrd'] as num?)?.toInt() ?? 0,
      kind: json['kind'] as String? ?? 'NONE',
      fieldOrds: (json['fieldOrds'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          [],
    );

OfficialAnkiTemplateFacts _$OfficialAnkiTemplateFactsFromJson(
        Map<String, dynamic> json) =>
    OfficialAnkiTemplateFacts(
      hash: json['hash'] as String? ?? '',
      templates: (json['templates'] as List<dynamic>?)
              ?.map((e) =>
                  OfficialAnkiTemplateFact.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      reqs: (json['reqs'] as List<dynamic>?)
              ?.map((e) => OfficialAnkiCardRequirement.fromJson(
                  e as Map<String, dynamic>))
              .toList() ??
          [],
    );

OfficialAnkiProjectionSchema _$OfficialAnkiProjectionSchemaFromJson(
        Map<String, dynamic> json) =>
    OfficialAnkiProjectionSchema(
      notetypeId: (json['notetypeId'] as num?)?.toInt() ?? 0,
      name: json['name'] as String? ?? '',
      kind: json['kind'] as String? ?? 'normal',
      fieldNames: (json['fieldNames'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      templateNames: (json['templateNames'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      schemaFingerprint: json['schemaFingerprint'] as String? ?? '',
      samples: (json['samples'] as List<dynamic>?)
              ?.map((e) => OfficialAnkiProjectionSample.fromJson(
                  e as Map<String, dynamic>))
              .toList() ??
          [],
      templateFacts: json['templateFacts'] == null
          ? null
          : OfficialAnkiTemplateFacts.fromJson(
              json['templateFacts'] as Map<String, dynamic>),
    );

OfficialAnkiProjectionSnapshot _$OfficialAnkiProjectionSnapshotFromJson(
        Map<String, dynamic> json) =>
    OfficialAnkiProjectionSnapshot(
      snapshotToken: json['snapshotToken'] as String? ?? '',
      collectionGeneration:
          (json['collectionGeneration'] as num?)?.toInt() ?? 0,
      backendCommit: json['backendCommit'] as String? ?? '',
    );

OfficialAnkiProjectionRow _$OfficialAnkiProjectionRowFromJson(
        Map<String, dynamic> json) =>
    OfficialAnkiProjectionRow(
      cardId: (json['cardId'] as num?)?.toInt() ?? 0,
      noteId: (json['noteId'] as num?)?.toInt() ?? 0,
      noteGuid: json['noteGuid'] as String? ?? '',
      notetypeId: (json['notetypeId'] as num?)?.toInt() ?? 0,
      deckId: (json['deckId'] as num?)?.toInt() ?? 0,
      deckPath: (json['deckPath'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      templateOrdinal: (json['templateOrdinal'] as num?)?.toInt() ?? 0,
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ??
              [],
      fields: (json['fields'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      sourceFingerprint: json['sourceFingerprint'] as String? ?? '',
      truncated: json['truncated'] as bool? ?? false,
    );

OfficialAnkiProjectionPage _$OfficialAnkiProjectionPageFromJson(
        Map<String, dynamic> json) =>
    OfficialAnkiProjectionPage(
      rows: (json['rows'] as List<dynamic>?)
              ?.map((e) =>
                  OfficialAnkiProjectionRow.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      missingCardIds: (json['missingCardIds'] as List<dynamic>?)
              ?.map((e) => (e as num).toInt())
              .toList() ??
          [],
    );

OfficialAheadAnswerOutcome _$OfficialAheadAnswerOutcomeFromJson(
        Map<String, dynamic> json) =>
    OfficialAheadAnswerOutcome(
      answered: (json['answeredCards'] as num?)?.toInt() ?? 0,
      skippedRatedToday: (json['skippedRatedToday'] as num?)?.toInt() ?? 0,
    );

OfficialCongratsInfo _$OfficialCongratsInfoFromJson(
        Map<String, dynamic> json) =>
    OfficialCongratsInfo(
      learnRemaining: (json['learnRemaining'] as num?)?.toInt() ?? 0,
      reviewRemaining: json['reviewRemaining'] as bool? ?? false,
      newRemaining: json['newRemaining'] as bool? ?? false,
      haveSchedBuried: json['haveSchedBuried'] as bool? ?? false,
      haveUserBuried: json['haveUserBuried'] as bool? ?? false,
      isFilteredDeck: json['isFilteredDeck'] as bool? ?? false,
      secsUntilNextLearn: (json['secsUntilNextLearn'] as num?)?.toInt() ?? 0,
      deckDescription: json['deckDescription'] as String? ?? '',
    );
