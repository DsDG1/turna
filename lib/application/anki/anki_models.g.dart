// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'anki_models.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_AnkiTemplate _$AnkiTemplateFromJson(Map<String, dynamic> json) =>
    _AnkiTemplate(
      name: json['name'] as String,
      qfmt: json['qfmt'] as String? ?? '',
      afmt: json['afmt'] as String? ?? '',
    );

Map<String, dynamic> _$AnkiTemplateToJson(_AnkiTemplate instance) =>
    <String, dynamic>{
      'name': instance.name,
      'qfmt': instance.qfmt,
      'afmt': instance.afmt,
    };

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
      templates: (json['templates'] as List<dynamic>?)
              ?.map((e) => AnkiTemplate.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <AnkiTemplate>[],
      isCloze: json['isCloze'] as bool? ?? false,
    );

Map<String, dynamic> _$AnkiNotetypeToJson(_AnkiNotetype instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'fieldNames': instance.fieldNames,
      'templateNames': instance.templateNames,
      'templates': instance.templates,
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
