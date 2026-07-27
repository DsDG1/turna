// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'section.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_Section _$SectionFromJson(Map<String, dynamic> json) => _Section(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      level: json['level'] as String?,
      prerequisiteSectionIds: (json['prerequisiteSectionIds'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          const <String>[],
      units: (json['units'] as List<dynamic>)
          .map((e) => Unit.fromJson(e as Map<String, dynamic>))
          .toList(),
    );

Map<String, dynamic> _$SectionToJson(_Section instance) => <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'description': instance.description,
      'level': instance.level,
      'prerequisiteSectionIds': instance.prerequisiteSectionIds,
      'units': instance.units,
    };
