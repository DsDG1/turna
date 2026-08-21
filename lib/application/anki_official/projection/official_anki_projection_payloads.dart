import 'dart:convert';

import 'package:turna/application/anki/card_presentation_policy.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_canonical.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_ids.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_mapper.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_paging.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_projector.dart';
import 'package:turna/application/anki_practice/card_classifier.dart';
import 'package:turna/application/anki_practice/card_classifier_models.dart';
import 'package:turna/domain/course/interaction.dart';

class OfficialAnkiPayloadOverflow implements Exception {
  const OfficialAnkiPayloadOverflow();
}

class OfficialAnkiRoleValues {
  const OfficialAnkiRoleValues({
    required this.target,
    required this.native,
    required this.pronunciation,
    required this.example,
    required this.audio,
    required this.image,
    required this.options,
    required this.truncatedRequired,
    this.classification,
    this.hasExplicitOptions = false,
  });

  final String target;
  final String native;
  final String pronunciation;
  final String example;
  final String? audio;
  final String? image;
  final List<String> options;
  final bool truncatedRequired;
  final AnkiPracticeClassification? classification;
  final bool hasExplicitOptions;
}

class OfficialAnkiProjectionPayloads {
  OfficialAnkiProjectionPayloads({OfficialAnkiProjectionMapper? mapper})
      : mapper = mapper ?? OfficialAnkiProjectionMapper();

  final OfficialAnkiProjectionMapper mapper;

  OfficialAnkiRoleValues values(
    OfficialAnkiProjectionRow row,
    OfficialAnkiMappingSuggestion? mapping, {
    List<String> siblingAnswers = const <String>[],
  }) {
    String text(OfficialAnkiFieldRole role) {
      final candidate = mapping?.role(role);
      if (candidate == null) return '';
      if (candidate.fieldIndex < 0 || candidate.fieldIndex >= row.fields.length) {
        return '';
      }
      return mapper.shortText(row.fields[candidate.fieldIndex]);
    }

    String raw(OfficialAnkiFieldRole role) {
      final candidate = mapping?.role(role);
      if (candidate == null) return '';
      if (candidate.fieldIndex < 0 || candidate.fieldIndex >= row.fields.length) {
        return '';
      }
      return row.fields[candidate.fieldIndex];
    }

    final audio = mapper.extractMediaFilename(raw(OfficialAnkiFieldRole.audio));
    final image = mapper.extractMediaFilename(raw(OfficialAnkiFieldRole.image));
    final mappedOptions =
        mapper.parseOptionPool(raw(OfficialAnkiFieldRole.optionPool));
    final requiredTruncated = row.truncated &&
        (mapping?.role(OfficialAnkiFieldRole.targetText) != null ||
            mapping?.role(OfficialAnkiFieldRole.nativeText) != null ||
            mapping?.role(OfficialAnkiFieldRole.audio) != null);

    final targetText = text(OfficialAnkiFieldRole.targetText);
    final nativeText = text(OfficialAnkiFieldRole.nativeText);

    final input = AnkiPracticeCardInput(
      cardId: row.cardId,
      notetypeId: row.notetypeId,
      fields: row.fields,
      fieldNames: mapping?.candidates.map((c) => c.fieldName).toList() ?? const <String>[],
      questionText: targetText,
      answerText: nativeText,
      rawQuestionHtml: raw(OfficialAnkiFieldRole.targetText),
      rawAnswerHtml: raw(OfficialAnkiFieldRole.nativeText),
      tags: row.tags,
      deckPath: row.deckPath,
      siblingAnswers: siblingAnswers,
    );
    final classification = AnkiPracticeCardClassifier.classify(input);

    return OfficialAnkiRoleValues(
      target: targetText.isNotEmpty ? targetText : classification.term,
      native: nativeText.isNotEmpty ? nativeText : classification.meaning,
      pronunciation: text(OfficialAnkiFieldRole.pronunciation).isNotEmpty
          ? text(OfficialAnkiFieldRole.pronunciation)
          : (classification.pronunciation ?? ''),
      example: text(OfficialAnkiFieldRole.exampleTarget).isNotEmpty
          ? text(OfficialAnkiFieldRole.exampleTarget)
          : (classification.example ?? ''),
      audio: audio ?? classification.audioFilename,
      image: image ?? classification.imageFilename,
      options: mappedOptions.isNotEmpty
          ? mappedOptions
          : (classification.options.isNotEmpty
              ? classification.options
              : siblingAnswers),
      truncatedRequired: requiredTruncated,
      classification: classification,
      hasExplicitOptions: mappedOptions.isNotEmpty ||
          classification.options.isNotEmpty,
    );
  }

  /// Exactly one active kind per card. Extra drills are not formal placements.
  List<OfficialAnkiProjectionKind> kindsFor({
    required OfficialAnkiRoleValues values,
    required OfficialAnkiMappingSuggestion? mapping,
    required bool typeAnswerEnabled,
  }) {
    return [
      const CardPresentationPolicy().selectOfficialKind(
        values: values,
        mapping: mapping,
        typeAnswerEnabled: typeAnswerEnabled,
      ),
    ];
  }

  Map<String, Object?> interactionJson({
    required OfficialAnkiProjectionKind kind,
    required OfficialAnkiProjectedItem item,
    required OfficialAnkiRoleValues values,
    required String sourceId,
  }) {
    final id = officialAnkiItemId(
      wordId: item.wordId,
      projectionKind: kind.name,
      ordinal: 0,
    );
    final shuffled = _shuffledOptions(
      answer: values.target,
      pool: values.options,
      sourceFingerprint: item.sourceFingerprint,
      cardId: item.cardId,
      kind: kind.name,
    );
    final interaction = switch (kind) {
      OfficialAnkiProjectionKind.showWord => Interaction.showWord(
          id: id,
          wordId: item.wordId,
          term: values.target.isNotEmpty
              ? values.target
              : (values.classification?.term ?? ''),
          translation: values.native.isNotEmpty
              ? values.native
              : (values.classification?.meaning ?? ''),
          pronunciation: values.pronunciation.isNotEmpty
              ? values.pronunciation
              : values.classification?.pronunciation,
          audioAsset: values.audio ?? values.classification?.audioFilename,
          imageAsset: values.image ?? values.classification?.imageFilename,
          example: values.example.isNotEmpty
              ? values.example
              : values.classification?.example,
        ),
      OfficialAnkiProjectionKind.flip => Interaction.ankiCard(
          id: id,
          front: values.target,
          back: values.native,
          audioAssets: values.audio == null ? const <String>[] : [values.audio!],
          imageAssets: values.image == null ? const <String>[] : [values.image!],
          hint: values.pronunciation.isEmpty ? null : values.pronunciation,
          sourceNoteId: 'official:$sourceId:${item.cardId}',
        ),
      OfficialAnkiProjectionKind.multipleChoice => Interaction.multipleChoice(
          id: id,
          prompt: values.classification?.options.isNotEmpty == true &&
                  values.classification!.term.isNotEmpty
              ? values.classification!.term
              : (values.native.isEmpty ? 'Choose the target' : values.native),
          options: values.classification?.options.isNotEmpty == true
              ? values.classification!.options
              : shuffled.options,
          correctIndex: values.classification?.correctIndex ?? shuffled.correctIndex,
          imageAsset: values.image,
          audioAssets: values.audio == null ? const <String>[] : [values.audio!],
        ),
      OfficialAnkiProjectionKind.multiSelect => Interaction.multiSelect(
          id: id,
          prompt: values.classification?.term.isNotEmpty == true
              ? values.classification!.term
              : values.native,
          options: values.classification?.options.isNotEmpty == true
              ? values.classification!.options
              : shuffled.options,
          correctIndices: values.classification?.correctIndices ?? const [0],
          minSelections: values.classification?.correctIndices?.length ?? 1,
          maxSelections: values.classification?.correctIndices?.length ?? 1,
          imageAsset: values.image,
        ),
      OfficialAnkiProjectionKind.fillBlank => Interaction.fillBlank(
          id: id,
          sentence: values.classification?.clozeSentence?.isNotEmpty == true
              ? values.classification!.clozeSentence!
              : values.target,
          answer: values.classification?.clozeAnswer?.isNotEmpty == true
              ? values.classification!.clozeAnswer!
              : values.native,
          hint: values.pronunciation.isNotEmpty
              ? values.pronunciation
              : values.classification?.pronunciation,
          audioAssets: values.audio == null ? const <String>[] : [values.audio!],
          imageAssets: values.image == null ? const <String>[] : [values.image!],
        ),
      OfficialAnkiProjectionKind.listenPick => Interaction.listenAndPick(
          id: id,
          audioAsset: values.audio ?? values.classification?.audioFilename ?? '',
          prompt: values.native.isEmpty ? 'Listen and pick' : values.native,
          options: shuffled.options,
          correctIndex: shuffled.correctIndex,
        ),
      OfficialAnkiProjectionKind.typeAnswer => Interaction.typeTheWord(
          id: id,
          audioAsset: values.audio ?? values.classification?.audioFilename ?? '',
          prompt: values.target.isEmpty ? 'Type the answer' : values.target,
          expected: values.native,
        ),
      OfficialAnkiProjectionKind.translate => Interaction.translateSentence(
          id: id,
          source: values.target,
          expected: values.native,
        ),
      OfficialAnkiProjectionKind.canonicalLink => Interaction.showWord(
          id: id,
          wordId: officialAnkiCanonicalWordId(
            sourceId: sourceId,
            cardId: item.cardId,
          ),
          context: 'official-canonical-link:$sourceId:${item.cardId}',
        ),
    };
    final json = Map<String, Object?>.from(interaction.toJson());
    final encoded = utf8.encode(jsonEncode(json));
    if (encoded.length > officialAnkiProjectionItemJsonMaxBytes) {
      throw const OfficialAnkiPayloadOverflow();
    }
    return json;
  }

  ({List<String> options, int correctIndex}) _shuffledOptions({
    required String answer,
    required List<String> pool,
    required String sourceFingerprint,
    required int cardId,
    required String kind,
  }) {
    final distractors = <String>[];
    final seen = <String>{answer.toLowerCase()};
    for (final option in pool) {
      if (!seen.add(option.toLowerCase())) continue;
      if (option.trim().isEmpty) continue;
      distractors.add(option);
      if (distractors.length >= 3) break;
    }
    final options = officialAnkiDeterministicShuffle(
      [answer, ...distractors.take(3)],
      officialAnkiShuffleSeed(
        sourceFingerprint: sourceFingerprint,
        cardId: cardId,
        kind: kind,
      ),
    );
    return (
      options: options,
      correctIndex: options.indexWhere(
        (option) => option.toLowerCase() == answer.toLowerCase(),
      ),
    );
  }
}
