// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'reading_passage.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ReadingPassage _$ReadingPassageFromJson(Map<String, dynamic> json) =>
    _ReadingPassage(
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
      wordFormMap: (json['wordFormMap'] as Map<String, dynamic>?)?.map(
            (k, e) => MapEntry(k, e as String),
          ) ??
          const <String, String>{},
      imageAsset: json['imageAsset'] as String?,
      imageAlt: json['imageAlt'] as String? ?? '',
    );

Map<String, dynamic> _$ReadingPassageToJson(_ReadingPassage instance) =>
    <String, dynamic>{
      'title': instance.title,
      'paragraphs': instance.paragraphs,
      'difficulty': instance.difficulty,
      'linkedWordIds': instance.linkedWordIds,
      'linkedExpressionIds': instance.linkedExpressionIds,
      'wordFormMap': instance.wordFormMap,
      'imageAsset': instance.imageAsset,
      'imageAlt': instance.imageAlt,
    };
