// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'anki_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_AnkiNotetype _$AnkiNotetypeFromJson(Map<String, dynamic> json) =>
    _AnkiNotetype(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      fieldNames: (json['fieldNames'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      templateNames: (json['templateNames'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[],
      isCloze: json['isCloze'] as bool? ?? false,
    );

Map<String, dynamic> _$AnkiNotetypeToJson(_AnkiNotetype instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'fieldNames': instance.fieldNames,
      'templateNames': instance.templateNames,
      'isCloze': instance.isCloze,
    };

_AnkiDeckInfo _$AnkiDeckInfoFromJson(Map<String, dynamic> json) =>
    _AnkiDeckInfo(
      id: (json['id'] as num).toInt(),
      name: json['name'] as String,
      parentId: (json['parentId'] as num?)?.toInt() ?? 0,
      cardCount: (json['cardCount'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$AnkiDeckInfoToJson(_AnkiDeckInfo instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'parentId': instance.parentId,
      'cardCount': instance.cardCount,
    };
