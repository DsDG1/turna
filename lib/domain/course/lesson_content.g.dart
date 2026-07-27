// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'lesson_content.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_LessonContent _$LessonContentFromJson(Map<String, dynamic> json) =>
    _LessonContent(
      stages: (json['stages'] as List<dynamic>?)
              ?.map((e) => Stage.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <Stage>[],
      subLessons: (json['subLessons'] as List<dynamic>?)
              ?.map((e) => SubLesson.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <SubLesson>[],
      listeningPhases: (json['listeningPhases'] as List<dynamic>?)
              ?.map((e) => ListeningPhase.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <ListeningPhase>[],
      readingPassage: json['readingPassage'] == null
          ? null
          : ReadingPassage.fromJson(
              json['readingPassage'] as Map<String, dynamic>),
      passage: json['passage'] as String? ?? '',
      audioAsset: json['audioAsset'] as String?,
      linkedGrammarPointIds: (json['linkedGrammarPointIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[],
    );

Map<String, dynamic> _$LessonContentToJson(_LessonContent instance) =>
    <String, dynamic>{
      'stages': instance.stages,
      'subLessons': instance.subLessons,
      'listeningPhases': instance.listeningPhases,
      'readingPassage': instance.readingPassage,
      'passage': instance.passage,
      'audioAsset': instance.audioAsset,
      'linkedGrammarPointIds': instance.linkedGrammarPointIds,
    };
