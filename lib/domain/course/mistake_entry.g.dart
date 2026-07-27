// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'mistake_entry.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_MistakeEntry _$MistakeEntryFromJson(Map<String, dynamic> json) =>
    _MistakeEntry(
      id: json['id'] as String,
      lessonId: json['lessonId'] as String,
      stageId: json['stageId'] as String,
      interactionId: json['interactionId'] as String,
      wordId: json['wordId'] as String?,
      expressionId: json['expressionId'] as String?,
      grammarPointId: json['grammarPointId'] as String?,
      interactionSnapshot:
          _interactionSnapshotFromJson(json['interactionSnapshot']),
      userAnswer: json['userAnswer'] as String? ?? '',
      correctAnswer: json['correctAnswer'] as String? ?? '',
      timestamp: DateTime.parse(json['timestamp'] as String),
      rewriteCount: (json['rewriteCount'] as num?)?.toInt() ?? 0,
    );

Map<String, dynamic> _$MistakeEntryToJson(_MistakeEntry instance) =>
    <String, dynamic>{
      'id': instance.id,
      'lessonId': instance.lessonId,
      'stageId': instance.stageId,
      'interactionId': instance.interactionId,
      'wordId': instance.wordId,
      'expressionId': instance.expressionId,
      'grammarPointId': instance.grammarPointId,
      'interactionSnapshot':
          _interactionSnapshotToJson(instance.interactionSnapshot),
      'userAnswer': instance.userAnswer,
      'correctAnswer': instance.correctAnswer,
      'timestamp': instance.timestamp.toIso8601String(),
      'rewriteCount': instance.rewriteCount,
    };
