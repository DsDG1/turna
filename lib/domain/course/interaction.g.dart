// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'interaction.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

ShowWord _$ShowWordFromJson(Map<String, dynamic> json) => ShowWord(
      id: json['id'] as String? ?? '',
      wordId: json['wordId'] as String,
      context: json['context'] as String?,
      grammarPointId: json['grammarPointId'] as String?,
      expressionId: json['expressionId'] as String?,
      term: json['term'] as String?,
      translation: json['translation'] as String?,
      pronunciation: json['pronunciation'] as String?,
      audioAsset: json['audioAsset'] as String?,
      imageAsset: json['imageAsset'] as String?,
      example: json['example'] as String?,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$ShowWordToJson(ShowWord instance) => <String, dynamic>{
      'id': instance.id,
      'wordId': instance.wordId,
      'context': instance.context,
      'grammarPointId': instance.grammarPointId,
      'expressionId': instance.expressionId,
      'term': instance.term,
      'translation': instance.translation,
      'pronunciation': instance.pronunciation,
      'audioAsset': instance.audioAsset,
      'imageAsset': instance.imageAsset,
      'example': instance.example,
      'runtimeType': instance.$type,
    };

MultipleChoice _$MultipleChoiceFromJson(Map<String, dynamic> json) =>
    MultipleChoice(
      id: json['id'] as String? ?? '',
      prompt: json['prompt'] as String,
      options:
          (json['options'] as List<dynamic>).map((e) => e as String).toList(),
      correctIndex: (json['correctIndex'] as num).toInt(),
      imageAsset: json['imageAsset'] as String?,
      audioAssets: (json['audioAssets'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[],
      grammarPointId: json['grammarPointId'] as String?,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$MultipleChoiceToJson(MultipleChoice instance) =>
    <String, dynamic>{
      'id': instance.id,
      'prompt': instance.prompt,
      'options': instance.options,
      'correctIndex': instance.correctIndex,
      'imageAsset': instance.imageAsset,
      'audioAssets': instance.audioAssets,
      'grammarPointId': instance.grammarPointId,
      'runtimeType': instance.$type,
    };

MultiSelect _$MultiSelectFromJson(Map<String, dynamic> json) => MultiSelect(
      id: json['id'] as String? ?? '',
      prompt: json['prompt'] as String,
      options:
          (json['options'] as List<dynamic>).map((e) => e as String).toList(),
      correctIndices: (json['correctIndices'] as List<dynamic>)
          .map((e) => (e as num).toInt())
          .toList(),
      minSelections: (json['minSelections'] as num?)?.toInt() ?? 1,
      maxSelections: (json['maxSelections'] as num?)?.toInt() ?? 2147483647,
      imageAsset: json['imageAsset'] as String?,
      grammarPointId: json['grammarPointId'] as String?,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$MultiSelectToJson(MultiSelect instance) =>
    <String, dynamic>{
      'id': instance.id,
      'prompt': instance.prompt,
      'options': instance.options,
      'correctIndices': instance.correctIndices,
      'minSelections': instance.minSelections,
      'maxSelections': instance.maxSelections,
      'imageAsset': instance.imageAsset,
      'grammarPointId': instance.grammarPointId,
      'runtimeType': instance.$type,
    };

FillBlank _$FillBlankFromJson(Map<String, dynamic> json) => FillBlank(
      id: json['id'] as String? ?? '',
      sentence: json['sentence'] as String,
      answer: json['answer'] as String,
      hint: json['hint'] as String?,
      audioAssets: (json['audioAssets'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[],
      imageAssets: (json['imageAssets'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[],
      grammarPointId: json['grammarPointId'] as String?,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$FillBlankToJson(FillBlank instance) => <String, dynamic>{
      'id': instance.id,
      'sentence': instance.sentence,
      'answer': instance.answer,
      'hint': instance.hint,
      'audioAssets': instance.audioAssets,
      'imageAssets': instance.imageAssets,
      'grammarPointId': instance.grammarPointId,
      'runtimeType': instance.$type,
    };

TranslateSentence _$TranslateSentenceFromJson(Map<String, dynamic> json) =>
    TranslateSentence(
      id: json['id'] as String? ?? '',
      source: json['source'] as String,
      expected: json['expected'] as String,
      hints:
          (json['hints'] as List<dynamic>?)?.map((e) => e as String).toList() ??
              const <String>[],
      grammarPointId: json['grammarPointId'] as String?,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$TranslateSentenceToJson(TranslateSentence instance) =>
    <String, dynamic>{
      'id': instance.id,
      'source': instance.source,
      'expected': instance.expected,
      'hints': instance.hints,
      'grammarPointId': instance.grammarPointId,
      'runtimeType': instance.$type,
    };

ListenAndPick _$ListenAndPickFromJson(Map<String, dynamic> json) =>
    ListenAndPick(
      id: json['id'] as String? ?? '',
      audioAsset: json['audioAsset'] as String,
      prompt: json['prompt'] as String,
      options:
          (json['options'] as List<dynamic>).map((e) => e as String).toList(),
      correctIndex: (json['correctIndex'] as num).toInt(),
      grammarPointId: json['grammarPointId'] as String?,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$ListenAndPickToJson(ListenAndPick instance) =>
    <String, dynamic>{
      'id': instance.id,
      'audioAsset': instance.audioAsset,
      'prompt': instance.prompt,
      'options': instance.options,
      'correctIndex': instance.correctIndex,
      'grammarPointId': instance.grammarPointId,
      'runtimeType': instance.$type,
    };

TypeTheWord _$TypeTheWordFromJson(Map<String, dynamic> json) => TypeTheWord(
      id: json['id'] as String? ?? '',
      audioAsset: json['audioAsset'] as String,
      prompt: json['prompt'] as String,
      expected: json['expected'] as String,
      grammarPointId: json['grammarPointId'] as String?,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$TypeTheWordToJson(TypeTheWord instance) =>
    <String, dynamic>{
      'id': instance.id,
      'audioAsset': instance.audioAsset,
      'prompt': instance.prompt,
      'expected': instance.expected,
      'grammarPointId': instance.grammarPointId,
      'runtimeType': instance.$type,
    };

ListenOnly _$ListenOnlyFromJson(Map<String, dynamic> json) => ListenOnly(
      id: json['id'] as String? ?? '',
      audioAsset: json['audioAsset'] as String?,
      transcript: json['transcript'] as String? ?? '',
      prompt: json['prompt'] as String? ?? 'Listen to the summary',
      grammarPointId: json['grammarPointId'] as String?,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$ListenOnlyToJson(ListenOnly instance) =>
    <String, dynamic>{
      'id': instance.id,
      'audioAsset': instance.audioAsset,
      'transcript': instance.transcript,
      'prompt': instance.prompt,
      'grammarPointId': instance.grammarPointId,
      'runtimeType': instance.$type,
    };

ReorderSentence _$ReorderSentenceFromJson(Map<String, dynamic> json) =>
    ReorderSentence(
      id: json['id'] as String? ?? '',
      scrambled:
          (json['scrambled'] as List<dynamic>).map((e) => e as String).toList(),
      correct:
          (json['correct'] as List<dynamic>).map((e) => e as String).toList(),
      grammarPointId: json['grammarPointId'] as String?,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$ReorderSentenceToJson(ReorderSentence instance) =>
    <String, dynamic>{
      'id': instance.id,
      'scrambled': instance.scrambled,
      'correct': instance.correct,
      'grammarPointId': instance.grammarPointId,
      'runtimeType': instance.$type,
    };

ReadingMcq _$ReadingMcqFromJson(Map<String, dynamic> json) => ReadingMcq(
      id: json['id'] as String? ?? '',
      prompt: json['prompt'] as String,
      options:
          (json['options'] as List<dynamic>).map((e) => e as String).toList(),
      correctIndex: (json['correctIndex'] as num).toInt(),
      grammarPointId: json['grammarPointId'] as String?,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$ReadingMcqToJson(ReadingMcq instance) =>
    <String, dynamic>{
      'id': instance.id,
      'prompt': instance.prompt,
      'options': instance.options,
      'correctIndex': instance.correctIndex,
      'grammarPointId': instance.grammarPointId,
      'runtimeType': instance.$type,
    };

ReadingTrueFalse _$ReadingTrueFalseFromJson(Map<String, dynamic> json) =>
    ReadingTrueFalse(
      id: json['id'] as String? ?? '',
      statement: json['statement'] as String,
      answer: json['answer'] as bool,
      grammarPointId: json['grammarPointId'] as String?,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$ReadingTrueFalseToJson(ReadingTrueFalse instance) =>
    <String, dynamic>{
      'id': instance.id,
      'statement': instance.statement,
      'answer': instance.answer,
      'grammarPointId': instance.grammarPointId,
      'runtimeType': instance.$type,
    };

ReadingShortAnswer _$ReadingShortAnswerFromJson(Map<String, dynamic> json) =>
    ReadingShortAnswer(
      id: json['id'] as String? ?? '',
      prompt: json['prompt'] as String,
      expectedAnswer: json['expectedAnswer'] as String,
      grammarPointId: json['grammarPointId'] as String?,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$ReadingShortAnswerToJson(ReadingShortAnswer instance) =>
    <String, dynamic>{
      'id': instance.id,
      'prompt': instance.prompt,
      'expectedAnswer': instance.expectedAnswer,
      'grammarPointId': instance.grammarPointId,
      'runtimeType': instance.$type,
    };

AnkiCard _$AnkiCardFromJson(Map<String, dynamic> json) => AnkiCard(
      id: json['id'] as String? ?? '',
      front: json['front'] as String,
      back: json['back'] as String,
      audioAssets: (json['audioAssets'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[],
      imageAssets: (json['imageAssets'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[],
      hint: json['hint'] as String?,
      sourceNoteId: json['sourceNoteId'] as String?,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$AnkiCardToJson(AnkiCard instance) => <String, dynamic>{
      'id': instance.id,
      'front': instance.front,
      'back': instance.back,
      'audioAssets': instance.audioAssets,
      'imageAssets': instance.imageAssets,
      'hint': instance.hint,
      'sourceNoteId': instance.sourceNoteId,
      'runtimeType': instance.$type,
    };

AnkiHtmlCard _$AnkiHtmlCardFromJson(Map<String, dynamic> json) => AnkiHtmlCard(
      id: json['id'] as String? ?? '',
      frontHtml: json['frontHtml'] as String,
      backHtml: json['backHtml'] as String,
      css: json['css'] as String? ?? '',
      mediaBasePath: json['mediaBasePath'] as String? ?? '',
      allowJs: json['allowJs'] as bool? ?? false,
      audioAssets: (json['audioAssets'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[],
      sourceNoteId: json['sourceNoteId'] as String?,
      sourceCardId: json['sourceCardId'] as String?,
      wordId: json['wordId'] as String?,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$AnkiHtmlCardToJson(AnkiHtmlCard instance) =>
    <String, dynamic>{
      'id': instance.id,
      'frontHtml': instance.frontHtml,
      'backHtml': instance.backHtml,
      'css': instance.css,
      'mediaBasePath': instance.mediaBasePath,
      'allowJs': instance.allowJs,
      'audioAssets': instance.audioAssets,
      'sourceNoteId': instance.sourceNoteId,
      'sourceCardId': instance.sourceCardId,
      'wordId': instance.wordId,
      'runtimeType': instance.$type,
    };
