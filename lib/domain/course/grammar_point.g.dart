// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'grammar_point.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_GrammarPoint _$GrammarPointFromJson(Map<String, dynamic> json) =>
    _GrammarPoint(
      id: json['id'] as String,
      title: json['title'] as String,
      explanation: json['explanation'] as String? ?? '',
      exampleExpressionIds: (json['exampleExpressionIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[],
      exampleSentenceIds: (json['exampleSentenceIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[],
      practiceItems: json['practiceItems'] == null
          ? const <Interaction>[]
          : _practiceItemsFromJson(json['practiceItems']),
    );

Map<String, dynamic> _$GrammarPointToJson(_GrammarPoint instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'explanation': instance.explanation,
      'exampleExpressionIds': instance.exampleExpressionIds,
      'exampleSentenceIds': instance.exampleSentenceIds,
      'practiceItems': _practiceItemsToJson(instance.practiceItems),
    };
