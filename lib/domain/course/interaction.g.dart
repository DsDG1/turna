// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'interaction.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$ShowWordImpl _$$ShowWordImplFromJson(Map<String, dynamic> json) =>
    _$ShowWordImpl(
      id: json['id'] as String? ?? '',
      wordId: json['wordId'] as String,
      context: json['context'] as String?,
      grammarPointId: json['grammarPointId'] as String?,
      expressionId: json['expressionId'] as String?,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$$ShowWordImplToJson(_$ShowWordImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'wordId': instance.wordId,
      'context': instance.context,
      'grammarPointId': instance.grammarPointId,
      'expressionId': instance.expressionId,
      'runtimeType': instance.$type,
    };

_$MultipleChoiceImpl _$$MultipleChoiceImplFromJson(Map<String, dynamic> json) =>
    _$MultipleChoiceImpl(
      id: json['id'] as String? ?? '',
      prompt: json['prompt'] as String,
      options:
          (json['options'] as List<dynamic>).map((e) => e as String).toList(),
      correctIndex: (json['correctIndex'] as num).toInt(),
      imageAsset: json['imageAsset'] as String?,
      grammarPointId: json['grammarPointId'] as String?,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$$MultipleChoiceImplToJson(
        _$MultipleChoiceImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'prompt': instance.prompt,
      'options': instance.options,
      'correctIndex': instance.correctIndex,
      'imageAsset': instance.imageAsset,
      'grammarPointId': instance.grammarPointId,
      'runtimeType': instance.$type,
    };

_$MultiSelectImpl _$$MultiSelectImplFromJson(Map<String, dynamic> json) =>
    _$MultiSelectImpl(
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

Map<String, dynamic> _$$MultiSelectImplToJson(_$MultiSelectImpl instance) =>
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

_$FillBlankImpl _$$FillBlankImplFromJson(Map<String, dynamic> json) =>
    _$FillBlankImpl(
      id: json['id'] as String? ?? '',
      sentence: json['sentence'] as String,
      answer: json['answer'] as String,
      hint: json['hint'] as String?,
      grammarPointId: json['grammarPointId'] as String?,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$$FillBlankImplToJson(_$FillBlankImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'sentence': instance.sentence,
      'answer': instance.answer,
      'hint': instance.hint,
      'grammarPointId': instance.grammarPointId,
      'runtimeType': instance.$type,
    };

_$TranslateSentenceImpl _$$TranslateSentenceImplFromJson(
        Map<String, dynamic> json) =>
    _$TranslateSentenceImpl(
      id: json['id'] as String? ?? '',
      source: json['source'] as String,
      expected: json['expected'] as String,
      hints:
          (json['hints'] as List<dynamic>?)?.map((e) => e as String).toList() ??
              const <String>[],
      grammarPointId: json['grammarPointId'] as String?,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$$TranslateSentenceImplToJson(
        _$TranslateSentenceImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'source': instance.source,
      'expected': instance.expected,
      'hints': instance.hints,
      'grammarPointId': instance.grammarPointId,
      'runtimeType': instance.$type,
    };

_$ListenAndPickImpl _$$ListenAndPickImplFromJson(Map<String, dynamic> json) =>
    _$ListenAndPickImpl(
      id: json['id'] as String? ?? '',
      audioAsset: json['audioAsset'] as String,
      prompt: json['prompt'] as String,
      options:
          (json['options'] as List<dynamic>).map((e) => e as String).toList(),
      correctIndex: (json['correctIndex'] as num).toInt(),
      grammarPointId: json['grammarPointId'] as String?,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$$ListenAndPickImplToJson(_$ListenAndPickImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'audioAsset': instance.audioAsset,
      'prompt': instance.prompt,
      'options': instance.options,
      'correctIndex': instance.correctIndex,
      'grammarPointId': instance.grammarPointId,
      'runtimeType': instance.$type,
    };

_$TypeTheWordImpl _$$TypeTheWordImplFromJson(Map<String, dynamic> json) =>
    _$TypeTheWordImpl(
      id: json['id'] as String? ?? '',
      audioAsset: json['audioAsset'] as String,
      prompt: json['prompt'] as String,
      expected: json['expected'] as String,
      grammarPointId: json['grammarPointId'] as String?,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$$TypeTheWordImplToJson(_$TypeTheWordImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'audioAsset': instance.audioAsset,
      'prompt': instance.prompt,
      'expected': instance.expected,
      'grammarPointId': instance.grammarPointId,
      'runtimeType': instance.$type,
    };

_$ListenOnlyImpl _$$ListenOnlyImplFromJson(Map<String, dynamic> json) =>
    _$ListenOnlyImpl(
      id: json['id'] as String? ?? '',
      audioAsset: json['audioAsset'] as String?,
      transcript: json['transcript'] as String? ?? '',
      prompt: json['prompt'] as String? ?? 'Listen to the summary',
      grammarPointId: json['grammarPointId'] as String?,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$$ListenOnlyImplToJson(_$ListenOnlyImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'audioAsset': instance.audioAsset,
      'transcript': instance.transcript,
      'prompt': instance.prompt,
      'grammarPointId': instance.grammarPointId,
      'runtimeType': instance.$type,
    };

_$ReorderSentenceImpl _$$ReorderSentenceImplFromJson(
        Map<String, dynamic> json) =>
    _$ReorderSentenceImpl(
      id: json['id'] as String? ?? '',
      scrambled:
          (json['scrambled'] as List<dynamic>).map((e) => e as String).toList(),
      correct:
          (json['correct'] as List<dynamic>).map((e) => e as String).toList(),
      grammarPointId: json['grammarPointId'] as String?,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$$ReorderSentenceImplToJson(
        _$ReorderSentenceImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'scrambled': instance.scrambled,
      'correct': instance.correct,
      'grammarPointId': instance.grammarPointId,
      'runtimeType': instance.$type,
    };

_$ReadingMcqImpl _$$ReadingMcqImplFromJson(Map<String, dynamic> json) =>
    _$ReadingMcqImpl(
      id: json['id'] as String? ?? '',
      prompt: json['prompt'] as String,
      options:
          (json['options'] as List<dynamic>).map((e) => e as String).toList(),
      correctIndex: (json['correctIndex'] as num).toInt(),
      grammarPointId: json['grammarPointId'] as String?,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$$ReadingMcqImplToJson(_$ReadingMcqImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'prompt': instance.prompt,
      'options': instance.options,
      'correctIndex': instance.correctIndex,
      'grammarPointId': instance.grammarPointId,
      'runtimeType': instance.$type,
    };

_$ReadingTrueFalseImpl _$$ReadingTrueFalseImplFromJson(
        Map<String, dynamic> json) =>
    _$ReadingTrueFalseImpl(
      id: json['id'] as String? ?? '',
      statement: json['statement'] as String,
      answer: json['answer'] as bool,
      grammarPointId: json['grammarPointId'] as String?,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$$ReadingTrueFalseImplToJson(
        _$ReadingTrueFalseImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'statement': instance.statement,
      'answer': instance.answer,
      'grammarPointId': instance.grammarPointId,
      'runtimeType': instance.$type,
    };

_$ReadingShortAnswerImpl _$$ReadingShortAnswerImplFromJson(
        Map<String, dynamic> json) =>
    _$ReadingShortAnswerImpl(
      id: json['id'] as String? ?? '',
      prompt: json['prompt'] as String,
      expectedAnswer: json['expectedAnswer'] as String,
      grammarPointId: json['grammarPointId'] as String?,
      $type: json['runtimeType'] as String?,
    );

Map<String, dynamic> _$$ReadingShortAnswerImplToJson(
        _$ReadingShortAnswerImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'prompt': instance.prompt,
      'expectedAnswer': instance.expectedAnswer,
      'grammarPointId': instance.grammarPointId,
      'runtimeType': instance.$type,
    };
