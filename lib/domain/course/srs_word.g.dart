// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'srs_word.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_SrsWord _$SrsWordFromJson(Map<String, dynamic> json) => _SrsWord(
      wordId: json['wordId'] as String,
      dueAt: DateTime.parse(json['dueAt'] as String),
      intervalDays: (json['intervalDays'] as num?)?.toInt() ?? 1,
      ease: (json['ease'] as num?)?.toDouble() ?? 2.5,
      reps: (json['reps'] as num?)?.toInt() ?? 0,
      lapses: (json['lapses'] as num?)?.toInt() ?? 0,
      isLeech: json['isLeech'] as bool? ?? false,
      type: $enumDecodeNullable(_$SrsItemTypeEnumMap, json['type']) ??
          SrsItemType.word,
    );

Map<String, dynamic> _$SrsWordToJson(_SrsWord instance) => <String, dynamic>{
      'wordId': instance.wordId,
      'dueAt': instance.dueAt.toIso8601String(),
      'intervalDays': instance.intervalDays,
      'ease': instance.ease,
      'reps': instance.reps,
      'lapses': instance.lapses,
      'isLeech': instance.isLeech,
      'type': _$SrsItemTypeEnumMap[instance.type]!,
    };

const _$SrsItemTypeEnumMap = {
  SrsItemType.word: 'word',
  SrsItemType.expression: 'expression',
};
