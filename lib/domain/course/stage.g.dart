// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'stage.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_$StageImpl _$$StageImplFromJson(Map<String, dynamic> json) => _$StageImpl(
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

Map<String, dynamic> _$$StageImplToJson(_$StageImpl instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'description': instance.description,
      'prerequisiteStageIds': instance.prerequisiteStageIds,
      'items': instance.items,
    };
