// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'anki_card_adapter.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_NotetypeMapping _$NotetypeMappingFromJson(Map<String, dynamic> json) =>
    _NotetypeMapping(
      type: $enumDecode(_$NotetypeMappingTypeEnumMap, json['type']),
      frontFieldIndex: (json['frontFieldIndex'] as num?)?.toInt() ?? 0,
      backFieldIndex: (json['backFieldIndex'] as num?)?.toInt() ?? 1,
      reason: json['reason'] as String? ?? '',
    );

Map<String, dynamic> _$NotetypeMappingToJson(_NotetypeMapping instance) =>
    <String, dynamic>{
      'type': _$NotetypeMappingTypeEnumMap[instance.type]!,
      'frontFieldIndex': instance.frontFieldIndex,
      'backFieldIndex': instance.backFieldIndex,
      'reason': instance.reason,
    };

const _$NotetypeMappingTypeEnumMap = {
  NotetypeMappingType.ankiCard: 'ankiCard',
  NotetypeMappingType.wordEntry: 'wordEntry',
  NotetypeMappingType.expression: 'expression',
  NotetypeMappingType.cloze: 'cloze',
  NotetypeMappingType.multipleChoice: 'multipleChoice',
  NotetypeMappingType.multiSelect: 'multiSelect',
  NotetypeMappingType.fillBlank: 'fillBlank',
  NotetypeMappingType.typeAnswer: 'typeAnswer',
  NotetypeMappingType.listenPick: 'listenPick',
};
