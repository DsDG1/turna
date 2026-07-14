// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lesson.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$LessonImpl _$$LessonImplFromJson(Map<String, dynamic> json) => _$LessonImpl(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      type: $enumDecodeNullable(_$LessonTypeEnumMap, json['type']) ??
          LessonType.normal,
      template:
          $enumDecodeNullable(_$LessonTemplateEnumMap, json['template']) ??
              LessonTemplate.legacy,
      prerequisiteLessonIds: (json['prerequisiteLessonIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[],
      content: LessonContent.fromJson(json['content'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$$LessonImplToJson(_$LessonImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'description': instance.description,
      'type': _$LessonTypeEnumMap[instance.type]!,
      'template': _$LessonTemplateEnumMap[instance.template]!,
      'prerequisiteLessonIds': instance.prerequisiteLessonIds,
      'content': instance.content,
    };

const _$LessonTypeEnumMap = {
  LessonType.normal: 'normal',
  LessonType.listening: 'listening',
  LessonType.reading: 'reading',
  LessonType.review: 'review',
  LessonType.challenge: 'challenge',
};

const _$LessonTemplateEnumMap = {
  LessonTemplate.intro: 'intro',
  LessonTemplate.listening: 'listening',
  LessonTemplate.practice: 'practice',
  LessonTemplate.reading: 'reading',
  LessonTemplate.review: 'review',
  LessonTemplate.mastery: 'mastery',
  LessonTemplate.legacy: 'legacy',
};
