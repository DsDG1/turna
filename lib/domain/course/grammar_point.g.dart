// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'grammar_point.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$GrammarPointImpl _$$GrammarPointImplFromJson(Map<String, dynamic> json) =>
    _$GrammarPointImpl(
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

Map<String, dynamic> _$$GrammarPointImplToJson(_$GrammarPointImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'explanation': instance.explanation,
      'exampleExpressionIds': instance.exampleExpressionIds,
      'exampleSentenceIds': instance.exampleSentenceIds,
      'practiceItems': _practiceItemsToJson(instance.practiceItems),
    };
