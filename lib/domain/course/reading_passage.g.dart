// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reading_passage.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$ReadingPassageImpl _$$ReadingPassageImplFromJson(Map<String, dynamic> json) =>
    _$ReadingPassageImpl(
      title: json['title'] as String,
      paragraphs: (json['paragraphs'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[],
      difficulty: (json['difficulty'] as num?)?.toInt() ?? 1,
      linkedWordIds: (json['linkedWordIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[],
      linkedExpressionIds: (json['linkedExpressionIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[],
    );

Map<String, dynamic> _$$ReadingPassageImplToJson(
        _$ReadingPassageImpl instance) =>
    <String, dynamic>{
      'title': instance.title,
      'paragraphs': instance.paragraphs,
      'difficulty': instance.difficulty,
      'linkedWordIds': instance.linkedWordIds,
      'linkedExpressionIds': instance.linkedExpressionIds,
    };
