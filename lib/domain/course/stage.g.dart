// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stage.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Stage _$StageFromJson(Map<String, dynamic> json) => _Stage(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      prerequisiteStageIds: (json['prerequisiteStageIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[],
      items: (json['items'] as List<dynamic>)
          .map((e) => Interaction.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$StageToJson(_Stage instance) => <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'description': instance.description,
      'prerequisiteStageIds': instance.prerequisiteStageIds,
      'items': instance.items,
    };
