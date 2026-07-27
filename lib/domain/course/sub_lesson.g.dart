// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sub_lesson.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_SubLesson _$SubLessonFromJson(Map<String, dynamic> json) => _SubLesson(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      stages: (json['stages'] as List<dynamic>?)
              ?.map((e) => Stage.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <Stage>[],
    );

Map<String, dynamic> _$SubLessonToJson(_SubLesson instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'description': instance.description,
      'sortOrder': instance.sortOrder,
      'stages': instance.stages,
    };
