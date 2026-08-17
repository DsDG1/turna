import 'dart:convert';

import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_canonical.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_ids.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_mapper.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_paging.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_projector.dart';
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
  });

  final String target;
  final String native;
  final String pronunciation;
  final String example;
  final String? audio;
  final String? image;
  final List<String> options;
  final bool truncatedRequired;
}

class OfficialAnkiProjectionPayloads {
  OfficialAnkiProjectionPayloads({OfficialAnkiProjectionMapper? mapper})
      : mapper = mapper ?? OfficialAnkiProjectionMapper();

  final OfficialAnkiProjectionMapper mapper;

  OfficialAnkiRoleValues values(
    OfficialAnkiProjectionRow row,
    OfficialAnkiMappingSuggestion? mapping,
  ) {
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
    final options = mapper.parseOptionPool(raw(OfficialAnkiFieldRole.optionPool));
    final requiredTruncated = row.truncated &&
        (mapping?.role(OfficialAnkiFieldRole.targetText) != null ||
            mapping?.role(OfficialAnkiFieldRole.nativeText) != null ||
            mapping?.role(OfficialAnkiFieldRole.audio) != null);
    return OfficialAnkiRoleValues(
      target: text(OfficialAnkiFieldRole.targetText),
      native: text(OfficialAnkiFieldRole.nativeText),
      pronunciation: text(OfficialAnkiFieldRole.pronunciation),
      example: text(OfficialAnkiFieldRole.exampleTarget),
      audio: audio,
      image: image,
      options: options,
      truncatedRequired: requiredTruncated,
    );
  }

  List<OfficialAnkiProjectionKind> kindsFor({
    required OfficialAnkiRoleValues values,
    required OfficialAnkiMappingSuggestion? mapping,
    required bool typeAnswerEnabled,
  }) {
    if (mapping == null ||
        mapping.status == OfficialAnkiMappingStatus.needsMapping ||
        mapping.status == OfficialAnkiMappingStatus.needsReview ||
        mapping.status == OfficialAnkiMappingStatus.skipped) {
      return const [OfficialAnkiProjectionKind.canonicalLink];
    }
    final enabled = mapping.enabledKinds.toSet();
    final kinds = <OfficialAnkiProjectionKind>[];
    if (values.truncatedRequired) {
      return const [OfficialAnkiProjectionKind.canonicalLink];
    }
    if (enabled.contains('flip') &&
        values.target.isNotEmpty &&
        values.native.isNotEmpty) {
      kinds.add(OfficialAnkiProjectionKind.flip);
    }
    final uniqueDistractors = values.options
        .where((option) => option.toLowerCase() != values.target.toLowerCase())
        .toSet()
        .toList();
    if (enabled.contains('multipleChoice') &&
        values.target.isNotEmpty &&
        uniqueDistractors.length >= 3) {
      kinds.add(OfficialAnkiProjectionKind.multipleChoice);
    }
    if (enabled.contains('listenPick') &&
        values.audio != null &&
        values.target.isNotEmpty &&
        uniqueDistractors.length >= 3) {
      kinds.add(OfficialAnkiProjectionKind.listenPick);
    }
    if (typeAnswerEnabled &&
        enabled.contains('typeAnswer') &&
        values.native.isNotEmpty) {
      kinds.add(OfficialAnkiProjectionKind.typeAnswer);
    }
    if (kinds.isEmpty) kinds.add(OfficialAnkiProjectionKind.canonicalLink);
    return kinds;
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
          prompt: values.native.isEmpty ? 'Choose the target' : values.native,
          options: shuffled.options,
          correctIndex: shuffled.correctIndex,
          imageAsset: values.image,
          audioAssets: values.audio == null ? const <String>[] : [values.audio!],
        ),
      OfficialAnkiProjectionKind.listenPick => Interaction.listenAndPick(
          id: id,
          audioAsset: values.audio ?? '',
          prompt: values.native.isEmpty ? 'Listen and pick' : values.native,
          options: shuffled.options,
          correctIndex: shuffled.correctIndex,
        ),
      OfficialAnkiProjectionKind.typeAnswer => Interaction.typeTheWord(
          id: id,
          audioAsset: values.audio ?? '',
          prompt: values.target.isEmpty ? 'Type the answer' : values.target,
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
