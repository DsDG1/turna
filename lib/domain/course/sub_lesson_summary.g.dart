// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'sub_lesson_summary.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_SubLessonSummary _$SubLessonSummaryFromJson(Map<String, dynamic> json) =>
    _SubLessonSummary(
      id: json['id'] as String,
      name: json['name'] as String,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$SubLessonSummaryToJson(_SubLessonSummary instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'sortOrder': instance.sortOrder,
    };
