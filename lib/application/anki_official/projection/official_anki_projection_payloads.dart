import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:turna/application/anki_import/recognition/facts/options_structure.dart';
import 'package:turna/application/anki_import/recognition/facts/text_metrics.dart';
import 'package:turna/application/anki_import/recognition/lexicon/field_roles.dart';
import 'package:turna/application/anki_import/recognition/policy/presentation_policy.dart';
import 'package:turna/application/anki_import/recognition/recognize/result.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_ids.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_paging.dart';
import 'package:turna/domain/course/interaction.dart';

enum OfficialAnkiProjectionKind {
  showWord,
  flip,
  multipleChoice,
  multiSelect,
  listenPick,
  typeAnswer,
  fillBlank,
  translate,
  canonicalLink,
}

class OfficialAnkiProjectedVocabulary {
  const OfficialAnkiProjectedVocabulary({
    required this.term,
    required this.translation,
    this.pronunciation,
    this.audioAsset,
  });

  final String term;
  final String translation;
  final String? pronunciation;
  final String? audioAsset;
}

class OfficialAnkiProjectedItem {
  const OfficialAnkiProjectedItem({
    required this.kind,
    required this.cardId,
    required this.wordId,
    required this.sectionId,
    required this.unitId,
    required this.lessonId,
    required this.sectionName,
    required this.unitName,
    required this.lessonName,
    required this.payload,
    required this.sourceFingerprint,
    this.vocabulary,
  });

  final OfficialAnkiProjectionKind kind;
  final int cardId;
  final String wordId;
  final String sectionId;
  final String unitId;
  final String lessonId;
  final String sectionName;
  final String unitName;
  final String lessonName;
  final Map<String, Object?> payload;
  final String sourceFingerprint;
  final OfficialAnkiProjectedVocabulary? vocabulary;
}

String officialAnkiShuffleSeed({
  required String sourceFingerprint,
  required int cardId,
  required String kind,
  int algorithmVersion = officialAnkiProjectionAlgorithmVersion,
}) {
  return '$sourceFingerprint|$cardId|$kind|$algorithmVersion';
}

List<T> officialAnkiDeterministicShuffle<T>(List<T> items, String seed) {
  final out = List<T>.from(items);
  if (out.length < 2) return out;
  final digest = sha256.convert(utf8.encode(seed)).bytes;
  var state = ByteData.sublistView(Uint8List.fromList(digest)).getUint32(0);
  int next() {
    state = (1664525 * state + 1013904223) & 0xffffffff;
    return state;
  }

  for (var i = out.length - 1; i > 0; i--) {
    final j = next() % (i + 1);
    final tmp = out[i];
    out[i] = out[j];
    out[j] = tmp;
  }
  return out;
}

class OfficialAnkiPayloadOverflow implements Exception {
  const OfficialAnkiPayloadOverflow();
}

/// Per-card extracted values under the notetype's recognition plan:
/// the archetype decided once per notetype, bindings deciding where each
/// value comes from, and this card's conformance to the archetype
/// (doc 37 §3.7 — cards only get validated and extracted, never
/// re-classified).
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
    required this.archetype,
    required this.archetypeConfidence,
    required this.archetypeViolated,
    required this.hasExplicitOptions,
    this.mcqPrompt = '',
    this.correctIndex,
    this.correctIndices,
    this.clozeSentence,
    this.clozeAnswer,
    this.siblingDistractors = const <String>[],
  });

  final String target;
  final String native;
  final String pronunciation;
  final String example;
  final String? audio;
  final String? image;
  final List<String> options;
  final bool truncatedRequired;
  final CardArchetype archetype;
  final double archetypeConfidence;

  /// This card violated the notetype archetype (missing cloze markers,
  /// unalignable options, or script/complex content the samples missed)
  /// and must fall back to the fidelity rendering.
  final bool archetypeViolated;

  /// An option pool or embedded options actually resolved for this card.
  final bool hasExplicitOptions;

  /// Question text for choice cards with an embedded-option prompt.
  final String mcqPrompt;
  final int? correctIndex;
  final List<int>? correctIndices;
  final String? clozeSentence;
  final String? clozeAnswer;

  /// Same-bucket answers used only to pad listenPick distractors — never
  /// enough to mint a formal MCQ (that requires an explicit option pool).
  final List<String> siblingDistractors;
}

class OfficialAnkiProjectionPayloads {
  static final RegExp _clozeMarkerRegex = RegExp(
    r'\{\{c(\d+)::(.*?)(?:::([^}]*))?\}\}',
    dotAll: true,
  );

  OfficialAnkiRoleValues values(
    OfficialAnkiProjectionRow row,
    OfficialAnkiMappingSuggestion? mapping, {
    List<String> siblingAnswers = const <String>[],
  }) {
    String raw(FieldRole role) {
      final candidate = mapping?.role(role);
      if (candidate == null) return '';
      if (candidate.fieldIndex < 0 ||
          candidate.fieldIndex >= row.fields.length) {
        return '';
      }
      return row.fields[candidate.fieldIndex];
    }

    String text(FieldRole role) => CardText.shortText(raw(role));

    final archetype = mapping?.cardArchetype ?? CardArchetype.basicPair;
    final archetypeConfidence = mapping?.recognitionConfidence ?? 0;

    final audio = CardText.extractAudioFilename(
      '${raw(FieldRole.audio)} ${raw(FieldRole.prompt)} '
      '${raw(FieldRole.response)}',
    );
    final image = CardText.extractImageFilename(raw(FieldRole.image));
    final requiredTruncated = row.truncated &&
        (mapping?.role(FieldRole.prompt) != null ||
            mapping?.role(FieldRole.response) != null ||
            mapping?.role(FieldRole.audio) != null);

    final targetText = text(FieldRole.prompt);
    final nativeText = text(FieldRole.response);

    // ── L3: card-level validation & extraction (§3.7) ─────────────────
    var archetypeViolated = false;
    String? clozeSentence;
    String? clozeAnswer;
    var options = const <String>[];
    int? correctIndex;
    List<int>? correctIndices;
    var mcqPrompt = '';
    var effectiveArchetype = archetype;

    if (_cardCarriesScriptOrComplexHtml(row.fields)) {
      archetypeViolated = true;
    }

    switch (archetype) {
      case CardArchetype.cloze:
        final cloze = _extractCloze(
          raw(FieldRole.prompt).isNotEmpty
              ? raw(FieldRole.prompt)
              : nativeText,
          row.templateOrdinal,
        );
        if (cloze == null) {
          archetypeViolated = true;
        } else {
          clozeSentence = cloze.$1;
          clozeAnswer = cloze.$2;
        }
      case CardArchetype.choice:
        final extracted = _resolveChoice(
          raw(FieldRole.options),
          raw(FieldRole.prompt),
          nativeText,
        );
        if (extracted == null) {
          archetypeViolated = true;
        } else {
          options = extracted.options;
          correctIndices = extracted.correctIndices;
          correctIndex = extracted.correctIndices.length == 1
              ? extracted.correctIndices.first
              : null;
          mcqPrompt = extracted.prompt;
        }
      case CardArchetype.audioFirst:
        // The presentation policy downgrades to flip when this card has
        // no playable audio; that is a preference fallback, not an
        // archetype violation.
        break;
      case CardArchetype.richHtml:
      case CardArchetype.typeIn:
        break;
      case CardArchetype.basicPair:
        // Card-level upgrades inside the universal fallback (old rules
        // 3/4 parity): a minority cloze or options card inside a basic
        // notetype still gets the right exercise — or the iron-law
        // fidelity downgrade when the options never align.
        final promptRawValue = raw(FieldRole.prompt);
        if (_clozeMarkerRegex.hasMatch(CardText.stripHtml(promptRawValue))) {
          final cloze = _extractCloze(promptRawValue, row.templateOrdinal);
          if (cloze != null) {
            effectiveArchetype = CardArchetype.cloze;
            clozeSentence = cloze.$1;
            clozeAnswer = cloze.$2;
          } else {
            // Markers exist but no deletion parses (old cloze_unparsed):
            // keep fidelity rather than flip raw {{cN::}} text.
            archetypeViolated = true;
          }
        } else if (EmbeddedOptionsParser.looksLikeEmbeddedOptions(
          CardText.stripHtml(promptRawValue),
        )) {
          final extracted = _resolveChoice('', promptRawValue, nativeText);
          if (extracted == null) {
            archetypeViolated = true;
          } else {
            effectiveArchetype = CardArchetype.choice;
            options = extracted.options;
            correctIndices = extracted.correctIndices;
            correctIndex = extracted.correctIndices.length == 1
                ? extracted.correctIndices.first
                : null;
            mcqPrompt = extracted.prompt;
          }
        } else if (CardText.extractAudioFilename(promptRawValue) != null &&
            CardText.isShortAnswer(nativeText)) {
          // Old rule 5 parity: a sound marker on the prompt side with a
          // short answer side is a listening card even in a basic deck.
          effectiveArchetype = CardArchetype.audioFirst;
        }
    }

    return OfficialAnkiRoleValues(
      target: targetText,
      native: nativeText,
      pronunciation: text(FieldRole.pronunciation),
      example: text(FieldRole.example),
      audio: audio,
      image: image,
      options: options,
      truncatedRequired: requiredTruncated,
      archetype: effectiveArchetype,
      archetypeConfidence: archetypeConfidence,
      archetypeViolated: archetypeViolated,
      hasExplicitOptions: options.isNotEmpty,
      mcqPrompt: mcqPrompt,
      correctIndex: correctIndex,
      correctIndices: correctIndices,
      clozeSentence: clozeSentence,
      clozeAnswer: clozeAnswer,
      siblingDistractors: siblingAnswers
          .where(
            (answer) =>
                answer.trim().isNotEmpty &&
                answer.toLowerCase() != nativeText.toLowerCase() &&
                answer.toLowerCase() != targetText.toLowerCase(),
          )
          .toList(),
    );
  }

  /// Exactly one active kind per card. Extra drills are not formal
  /// placements.
  List<OfficialAnkiProjectionKind> kindsFor({
    required OfficialAnkiRoleValues values,
    required OfficialAnkiMappingSuggestion? mapping,
    required bool typeAnswerEnabled,
  }) {
    return [
      const OfficialAnkiPresentationPolicy().selectOfficialKind(
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
    final interaction = switch (kind) {
      OfficialAnkiProjectionKind.showWord => Interaction.showWord(
          id: id,
          wordId: item.wordId,
          term: values.target,
          translation: values.native,
          pronunciation: values.pronunciation.isNotEmpty
              ? values.pronunciation
              : null,
          audioAsset: values.audio,
          imageAsset: values.image,
          example: values.example.isNotEmpty ? values.example : null,
        ),
      OfficialAnkiProjectionKind.flip => Interaction.ankiCard(
          id: id,
          front: values.target,
          back: values.native,
          audioAssets:
              values.audio == null ? const <String>[] : [values.audio!],
          imageAssets:
              values.image == null ? const <String>[] : [values.image!],
          hint: values.pronunciation.isEmpty ? null : values.pronunciation,
          sourceNoteId: 'official:$sourceId:${item.cardId}',
        ),
      OfficialAnkiProjectionKind.multipleChoice => _multipleChoice(
          id: id,
          item: item,
          values: values,
        ),
      OfficialAnkiProjectionKind.multiSelect => _multiSelect(
          id: id,
          item: item,
          values: values,
        ),
      OfficialAnkiProjectionKind.fillBlank => Interaction.fillBlank(
          id: id,
          sentence: values.clozeSentence?.isNotEmpty == true
              ? values.clozeSentence!
              : values.target,
          answer: values.clozeAnswer?.isNotEmpty == true
              ? values.clozeAnswer!
              : values.native,
          hint: values.pronunciation.isNotEmpty
              ? values.pronunciation
              : null,
          audioAssets:
              values.audio == null ? const <String>[] : [values.audio!],
          imageAssets:
              values.image == null ? const <String>[] : [values.image!],
        ),
      OfficialAnkiProjectionKind.listenPick => _listenPick(
          id: id,
          item: item,
          values: values,
        ),
      OfficialAnkiProjectionKind.typeAnswer => Interaction.typeTheWord(
          id: id,
          audioAsset: values.audio ?? '',
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

  Interaction _multipleChoice({
    required String id,
    required OfficialAnkiProjectedItem item,
    required OfficialAnkiRoleValues values,
  }) {
    final correct = values.correctIndex ?? 0;
    final shuffled = _shuffledOptions(
      answer: values.options[correct],
      pool: values.options,
      sourceFingerprint: item.sourceFingerprint,
      cardId: item.cardId,
      kind: OfficialAnkiProjectionKind.multipleChoice.name,
    );
    final prompt = values.mcqPrompt.isNotEmpty
        ? values.mcqPrompt
        : (values.target.isNotEmpty
            ? values.target
            : (values.native.isEmpty ? 'Choose the target' : values.native));
    return Interaction.multipleChoice(
      id: id,
      prompt: prompt,
      options: shuffled.options,
      correctIndex: shuffled.correctIndex,
      imageAsset: values.image,
      audioAssets: values.audio == null ? const <String>[] : [values.audio!],
    );
  }

  Interaction _multiSelect({
    required String id,
    required OfficialAnkiProjectedItem item,
    required OfficialAnkiRoleValues values,
  }) {
    final correct = (values.correctIndices ?? const [0]).toSet();
    final answers = [
      for (var i = 0; i < values.options.length; i++)
        if (correct.contains(i)) values.options[i],
    ];
    final shuffled = officialAnkiDeterministicShuffle(
      values.options,
      officialAnkiShuffleSeed(
        sourceFingerprint: item.sourceFingerprint,
        cardId: item.cardId,
        kind: OfficialAnkiProjectionKind.multiSelect.name,
      ),
    );
    final remap = <String, int>{};
    for (var i = 0; i < shuffled.length; i++) {
      remap[shuffled[i]] = i;
    }
    final correctAfterShuffle = answers
        .map((answer) => remap[answer] ?? shuffled.indexOf(answer))
        .toList()
      ..sort();
    final prompt = values.mcqPrompt.isNotEmpty
        ? values.mcqPrompt
        : (values.target.isNotEmpty
            ? values.target
            : (values.native.isEmpty ? 'Choose the target' : values.native));
    return Interaction.multiSelect(
      id: id,
      prompt: prompt,
      options: shuffled,
      correctIndices: correctAfterShuffle,
      minSelections: correctAfterShuffle.length,
      maxSelections: correctAfterShuffle.length,
      imageAsset: values.image,
    );
  }

  Interaction _listenPick({
    required String id,
    required OfficialAnkiProjectedItem item,
    required OfficialAnkiRoleValues values,
  }) {
    // Audio drives the front; the answer to pick is the response text,
    // the options pool and same-bucket siblings pad the distractors. The
    // prompt must not leak the answer, so it only shows auxiliary front
    // text when present.
    final answer = values.native.isNotEmpty ? values.native : values.target;
    final pool = <String>[
      ...values.options.where((o) => o.isNotEmpty),
      ...values.siblingDistractors,
    ];
    final shuffled = _shuffledOptions(
      answer: answer,
      pool: pool,
      sourceFingerprint: item.sourceFingerprint,
      cardId: item.cardId,
      kind: OfficialAnkiProjectionKind.listenPick.name,
    );
    return Interaction.listenAndPick(
      id: id,
      audioAsset: values.audio ?? '',
      prompt: values.target.isEmpty ? 'Listen and pick' : values.target,
      options: shuffled.options,
      correctIndex: shuffled.correctIndex,
    );
  }

  /// Resolve a choice card from either an option-pool field or embedded
  /// front options. Null when nothing aligns (the caller marks the card
  /// violated — the iron law).
  ({List<String> options, List<int> correctIndices, String prompt})?
      _resolveChoice(
    String optionsRaw,
    String promptRaw,
    String answerText,
  ) {
    final pool = EmbeddedOptionsParser.parseOptionPool(optionsRaw);
    if (pool.length >= 2) {
      final correct = EmbeddedOptionsParser.parseCorrectIndices(
        answerText,
        pool,
      );
      if (correct.isNotEmpty) {
        return (
          options: pool,
          correctIndices: correct,
          prompt: CardText.shortText(promptRaw),
        );
      }
      return null;
    }
    final embedded = EmbeddedOptionsParser.extractEmbeddedOptions(promptRaw);
    if (embedded == null) return null;
    final correct = EmbeddedOptionsParser.parseCorrectIndices(
      answerText,
      embedded.options,
    );
    if (correct.isEmpty) return null;
    return (
      options: embedded.options,
      correctIndices: correct,
      prompt: embedded.prompt,
    );
  }

  /// Extract the cloze deletion for this card's ordinal (marker number =
  /// template ordinal + 1), falling back to the first marker.
  (String, String)? _extractCloze(String rawPrompt, int templateOrdinal) {
    final plain = CardText.stripHtml(rawPrompt);
    final markers = _clozeMarkerRegex.allMatches(plain).toList();
    if (markers.isEmpty) return null;
    RegExpMatch? preferred;
    for (final marker in markers) {
      final number = int.tryParse(marker.group(1) ?? '');
      if (number == templateOrdinal + 1) {
        preferred = marker;
        break;
      }
    }
    preferred ??= markers.first;
    final answer = (preferred.group(2) ?? '').trim();
    if (answer.isEmpty) return null;
    final sentence = plain.replaceAll(_clozeMarkerRegex, '_____');
    return (CardText.shortText(sentence), CardText.shortText(answer));
  }

  bool _cardCarriesScriptOrComplexHtml(List<String> fields) {
    for (final field in fields) {
      final lower = field.toLowerCase();
      if (lower.contains('<script') || lower.contains('javascript:')) {
        return true;
      }
      if (RegExp(r'on[a-z]+\s*=', caseSensitive: false).hasMatch(field)) {
        return true;
      }
      if (RegExp(
        r'<(table|svg|video|iframe|canvas|object|embed|form|input|button)\b',
        caseSensitive: false,
      ).hasMatch(field)) {
        return true;
      }
    }
    return false;
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
