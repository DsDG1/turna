// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lesson_word_link.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$LessonWordLinkImpl _$$LessonWordLinkImplFromJson(Map<String, dynamic> json) =>
    _$LessonWordLinkImpl(
      wordId: json['wordId'] as String,
      lessonId: json['lessonId'] as String,
      lessonName: json['lessonName'] as String,
      type:
          $enumDecodeNullable(_$LinkTypeEnumMap, json['type']) ?? LinkType.word,
      firstSeenAt: DateTime.parse(json['firstSeenAt'] as String),
    );

Map<String, dynamic> _$$LessonWordLinkImplToJson(
        _$LessonWordLinkImpl instance) =>
    <String, dynamic>{
      'wordId': instance.wordId,
      'lessonId': instance.lessonId,
      'lessonName': instance.lessonName,
      'type': _$LinkTypeEnumMap[instance.type]!,
      'firstSeenAt': instance.firstSeenAt.toIso8601String(),
    };

const _$LinkTypeEnumMap = {
  LinkType.word: 'word',
  LinkType.expression: 'expression',
  LinkType.grammarPoint: 'grammarPoint',
};
