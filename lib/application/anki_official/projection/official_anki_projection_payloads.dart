import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:turna/application/anki_import/adaptation/card_document_builder.dart';
import 'package:turna/application/anki_import/adaptation/card_media_extractor.dart';
import 'package:turna/application/anki_import/recognition/facts/options_structure.dart';
import 'package:turna/application/anki_import/recognition/facts/text_metrics.dart';
import 'package:turna/application/anki_import/recognition/lexicon/field_roles.dart';
import 'package:turna/application/anki_import/recognition/recognize/result.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_ids.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_paging.dart';
import 'package:turna/domain/anki/adaptation/card_adaptation_plan.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
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

  /// 看图回忆: prompt-side image, recall-then-reveal. Opt-in only (ADR 0057 §4).
  imageRecall,

  /// 听写: prompt-side audio, typed answer. Opt-in only; never shows the
  /// answer text before submit.
  dictation,
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
    this.mediaOccurrences = const <MediaOccurrence>[],
    this.variant = CardContentVariant.none,
    this.document,
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

  /// Every media occurrence on this card, in document order, each with the
  /// face it was proven to belong to (ADR 0057 §5).
  final List<MediaOccurrence> mediaOccurrences;

  /// All-facts-empty instance for fallback paths that only need a valid
  /// receiver (the original-card link payload reads none of the values).
  static const OfficialAnkiRoleValues empty = OfficialAnkiRoleValues(
    target: '',
    native: '',
    pronunciation: '',
    example: '',
    audio: null,
    image: null,
    options: <String>[],
    truncatedRequired: false,
    archetype: CardArchetype.basicPair,
    archetypeConfidence: 0,
    archetypeViolated: false,
    hasExplicitOptions: false,
  );

  /// Set when this card was upgraded inside a broader archetype (plan §3.2):
  /// a cloze/choice/listening card living in a `basicPair` notetype.
  final CardContentVariant variant;

  /// The plan's own layout for this card, when one is active. Null means the
  /// card is presented from the recognizer's role bindings.
  final CardDocument? document;

  /// Media proven to sit on the question face.
  List<String> get frontAudio => _mediaOn(
        MediaOccurrenceSide.front,
        CanonicalMediaKind.audio,
      );
  List<String> get frontImages => _mediaOn(
        MediaOccurrenceSide.front,
        CanonicalMediaKind.image,
      );

  /// Media proven to sit on the answer face.
  List<String> get backAudio => _mediaOn(
        MediaOccurrenceSide.back,
        CanonicalMediaKind.audio,
      );
  List<String> get backImages => _mediaOn(
        MediaOccurrenceSide.back,
        CanonicalMediaKind.image,
      );

  /// Media whose face could not be proven. Never render these before the
  /// reveal; the resolver sends such cards to the original rendering.
  List<String> get unknownSideAudio => [
        for (final occurrence in mediaOccurrences)
          if (!occurrence.sideKnown &&
              occurrence.kind == CanonicalMediaKind.audio)
            occurrence.filename,
      ];

  List<String> get unknownSideImages => [
        for (final occurrence in mediaOccurrences)
          if (!occurrence.sideKnown &&
              occurrence.kind == CanonicalMediaKind.image)
            occurrence.filename,
      ];

  bool get hasUnprovenMediaSide =>
      mediaOccurrences.any((occurrence) => !occurrence.sideKnown);

  List<String> _mediaOn(MediaOccurrenceSide side, CanonicalMediaKind kind) => [
        for (final occurrence in mediaOccurrences)
          if (occurrence.side == side && occurrence.kind == kind)
            occurrence.filename,
      ];

}

class OfficialAnkiProjectionPayloads {
  const OfficialAnkiProjectionPayloads();

  static final RegExp _clozeMarkerRegex = RegExp(
    r'\{\{c(\d+)::(.*?)(?:::([^}]*))?\}\}',
    dotAll: true,
  );

  OfficialAnkiRoleValues values(
    OfficialAnkiProjectionRow row,
    OfficialAnkiMappingSuggestion? mapping, {
    List<String> siblingAnswers = const <String>[],
    CardAdaptationPlan? plan,
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
    // Face ownership comes from the per-template facts persisted with the
    // mapping decision. Without them only the role-bound fields are scanned —
    // a field no template renders must not leak its media onto the card.
    final face = mapping?.faceFor(row.templateOrdinal);
    // Per-template direction (ADR 0057 §3): a reverse template renders the
    // answer-role field on its front face, so the two roles swap for this card.
    // Reading the notetype-level direction instead would show the answer as
    // the question on every reverse card.
    final reversed = face?.isReversed ?? false;
    final promptRole = reversed ? FieldRole.response : FieldRole.prompt;
    final answerRole = reversed ? FieldRole.prompt : FieldRole.response;
    final roleBoundIndices = <int>{
      for (final candidate
          in mapping?.candidates ?? const <OfficialAnkiFieldCandidate>[])
        if (candidate.role != FieldRole.ignored) candidate.fieldIndex,
    };
    final mediaOccurrences = CardMediaExtractor.extract(
      fields: row.fields,
      frontFieldOrds: {
        for (final ordinal in face?.frontFieldOrds ?? const <int>[]) ordinal,
      },
      backFieldOrds: {
        for (final ordinal in face?.backFieldOrds ?? const <int>[]) ordinal,
      },
      fallbackFieldIndices: roleBoundIndices,
    );
    final requiredTruncated = row.truncated &&
        (mapping?.role(FieldRole.prompt) != null ||
            mapping?.role(FieldRole.response) != null ||
            mapping?.role(FieldRole.audio) != null);

    final targetText = text(promptRole);
    final nativeText = text(answerRole);

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
          raw(promptRole).isNotEmpty ? raw(promptRole) : nativeText,
          row.templateOrdinal,
        );
        if (cloze == null) {
          archetypeViolated = true;
        } else {
          clozeSentence = cloze.$1;
          clozeAnswer = cloze.$2;
        }
      case CardArchetype.choice:
        final candidateNames =
            mapping?.candidates.map((c) => c.fieldName).toList() ??
                const <String>[];
        // Raw response, not the collapsed shortText: back-face layouts
        // need their line structure to expose options + answer markers.
        final extracted = _resolveChoice(
          raw(FieldRole.options),
          raw(promptRole),
          raw(answerRole),
          fieldNames: candidateNames,
          fieldValues: row.fields,
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
        final promptRawValue = raw(promptRole);
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
              promptRawValue,
            ) ||
            (EmbeddedOptionsParser.isBareLabelAnswer(nativeText) &&
                EmbeddedOptionsParser.hasUnlabeledOptionLines(
                  promptRawValue,
                ))) {
          final extracted = _resolveChoice(
            '',
            promptRawValue,
            raw(answerRole),
          );
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
      mediaOccurrences: mediaOccurrences,
      variant: effectiveArchetype == archetype
          ? CardContentVariant.none
          : switch (effectiveArchetype) {
              CardArchetype.cloze => CardContentVariant.cloze,
              CardArchetype.choice => CardContentVariant.choice,
              CardArchetype.audioFirst => CardContentVariant.audioFirst,
              _ => CardContentVariant.none,
            },
      document:
          plan == null ? null : buildCardDocument(plan: plan, row: row),
    );
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
    final document = values.document;
    final interaction = switch (kind) {
      OfficialAnkiProjectionKind.showWord => Interaction.showWord(
          id: id,
          wordId: item.wordId,
          term: values.target,
          translation: values.native,
          pronunciation:
              values.pronunciation.isNotEmpty ? values.pronunciation : null,
          audioAsset: values.audio,
          imageAsset: values.image,
          example: values.example.isNotEmpty ? values.example : null,
        ),
      OfficialAnkiProjectionKind.flip => Interaction.ankiCard(
          id: id,
          front: document != null && document.front.text.isNotEmpty
              ? document.front.text
              : values.target,
          back: document != null && document.back.text.isNotEmpty
              ? document.back.text
              : values.native,
          // A plan that lays out this card owns its faces, including media.
          frontAudioAssets:
              document == null ? values.frontAudio : document.front.audio,
          frontImageAssets:
              document == null ? values.frontImages : document.front.images,
          backAudioAssets:
              document == null ? values.backAudio : document.back.audio,
          backImageAssets:
              document == null ? values.backImages : document.back.images,
          // Unproven-side media stays on the legacy all-media lists, which the
          // renderer only shows on the answer face (and the resolver normally
          // diverts such cards to the original rendering first).
          audioAssets: document == null ? values.unknownSideAudio : const [],
          imageAssets: document == null ? values.unknownSideImages : const [],
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
          hint: values.pronunciation.isNotEmpty ? values.pronunciation : null,
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
      OfficialAnkiProjectionKind.imageRecall => Interaction.imageRecall(
          id: id,
          imageAssets: values.frontImages,
          answerText: values.target,
          // No hint: pronunciation and example would give the reading away.
          sourceNoteId: 'official:$sourceId:${item.cardId}',
        ),
      OfficialAnkiProjectionKind.dictation => Interaction.dictation(
          id: id,
          audioAssets: values.frontAudio,
          expected: values.target,
          sourceNoteId: 'official:$sourceId:${item.cardId}',
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

  /// Resolve a choice card from multi-field options, an option-pool field,
  /// or embedded front options. Null when nothing aligns (the caller marks
  /// the card violated — the iron law).
  ({List<String> options, List<int> correctIndices, String prompt})?
      _resolveChoice(
    String optionsRaw,
    String promptRaw,
    String answerText, {
    List<String> fieldNames = const [],
    List<String> fieldValues = const [],
  }) {
    // 1) Multi-field options:
    if (fieldNames.isNotEmpty && fieldValues.isNotEmpty) {
      final multi = EmbeddedOptionsParser.extractMultiFieldOptions(
        fieldNames,
        fieldValues,
      );
      if (multi != null && multi.length >= 2) {
        final correct = EmbeddedOptionsParser.parseCorrectIndices(
          answerText,
          multi,
        );
        if (correct.isNotEmpty) {
          return (
            options: multi,
            correctIndices: correct,
            prompt: CardText.shortText(promptRaw),
          );
        }
      }
    }

    // 2) Delimited option-pool field:
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

    // 3) Embedded front options:
    final embedded = EmbeddedOptionsParser.extractEmbeddedOptions(promptRaw);
    if (embedded == null) {
      // 4) Options and the explicit answer share the back face:
      final back = EmbeddedOptionsParser.extractBackFaceChoice(answerText);
      if (back == null) return null;
      return (
        options: back.options,
        correctIndices: back.correctIndices,
        prompt: CardText.shortText(promptRaw),
      );
    }
    final correct = EmbeddedOptionsParser.parseCorrectIndices(
      answerText,
      embedded.options,
    );
    if (correct.isEmpty) {
      // The back face may still carry an explicit marker even when the
      // answer field itself did not align.
      final back = EmbeddedOptionsParser.extractBackFaceChoice(answerText);
      if (back == null) return null;
      return (
        options: back.options,
        correctIndices: back.correctIndices,
        prompt: embedded.prompt.isNotEmpty
            ? embedded.prompt
            : CardText.shortText(promptRaw),
      );
    }
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
      if (cardCarriesUnsupportedStructure(field)) return true;
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



