// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'unit.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Unit _$UnitFromJson(Map<String, dynamic> json) => _Unit(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      prerequisiteUnitIds: (json['prerequisiteUnitIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[],
      lessons: (json['lessons'] as List<dynamic>)
          .map((e) => Lesson.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$UnitToJson(_Unit instance) => <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'description': instance.description,
      'prerequisiteUnitIds': instance.prerequisiteUnitIds,
      'lessons': instance.lessons,
    };
