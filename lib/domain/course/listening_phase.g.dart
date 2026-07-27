// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'listening_phase.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_ListeningPhase _$ListeningPhaseFromJson(Map<String, dynamic> json) =>
    _ListeningPhase(
      id: json['id'] as String,
      name: json['name'] as String,
      type: $enumDecodeNullable(_$ListeningPhaseTypeEnumMap, json['type']) ??
          ListeningPhaseType.dialogue,
      audioAsset: json['audioAsset'] as String?,
      transcript: json['transcript'] as String? ?? '',
      items: (json['items'] as List<dynamic>?)
              ?.map((e) => Interaction.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <Interaction>[],
    );

Map<String, dynamic> _$ListeningPhaseToJson(_ListeningPhase instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'type': _$ListeningPhaseTypeEnumMap[instance.type]!,
      'audioAsset': instance.audioAsset,
      'transcript': instance.transcript,
      'items': instance.items,
    };

const _$ListeningPhaseTypeEnumMap = {
  ListeningPhaseType.wordPairing: 'wordPairing',
  ListeningPhaseType.dialogue: 'dialogue',
  ListeningPhaseType.summary: 'summary',
};
