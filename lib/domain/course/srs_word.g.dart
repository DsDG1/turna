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
      isSuspended: json['isSuspended'] as bool? ?? false,
      isBuried: json['isBuried'] as bool? ?? false,
      type: $enumDecodeNullable(_$SrsItemTypeEnumMap, json['type']) ??
          SrsItemType.word,
      sourceKind:
          $enumDecodeNullable(_$SrsSourceKindEnumMap, json['sourceKind']) ??
              SrsSourceKind.course,
      sourceId: json['sourceId'] as String? ?? 'course',
      ownerId: json['ownerId'] as String?,
      lastReviewedAt: json['lastReviewedAt'] == null
          ? null
          : DateTime.parse(json['lastReviewedAt'] as String),
      stability: (json['stability'] as num?)?.toDouble(),
      difficulty: (json['difficulty'] as num?)?.toDouble(),
      fsrsState: (json['fsrsState'] as num?)?.toInt() ?? 1,
      learningStep: (json['learningStep'] as num?)?.toInt(),
    );

Map<String, dynamic> _$SrsWordToJson(_SrsWord instance) => <String, dynamic>{
      'wordId': instance.wordId,
      'dueAt': instance.dueAt.toIso8601String(),
      'intervalDays': instance.intervalDays,
      'ease': instance.ease,
      'reps': instance.reps,
      'lapses': instance.lapses,
      'isLeech': instance.isLeech,
      'isSuspended': instance.isSuspended,
      'isBuried': instance.isBuried,
      'type': _$SrsItemTypeEnumMap[instance.type]!,
      'sourceKind': _$SrsSourceKindEnumMap[instance.sourceKind]!,
      'sourceId': instance.sourceId,
      'ownerId': instance.ownerId,
      'lastReviewedAt': instance.lastReviewedAt?.toIso8601String(),
      'stability': instance.stability,
      'difficulty': instance.difficulty,
      'fsrsState': instance.fsrsState,
      'learningStep': instance.learningStep,
    };

const _$SrsItemTypeEnumMap = {
  SrsItemType.word: 'word',
  SrsItemType.expression: 'expression',
};

const _$SrsSourceKindEnumMap = {
  SrsSourceKind.course: 'course',
  SrsSourceKind.grammar: 'grammar',
  SrsSourceKind.ankiLegacy: 'ankiLegacy',
  SrsSourceKind.ankiOfficial: 'ankiOfficial',
};
