// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dialogue_scene.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

_DialogueCharacter _$DialogueCharacterFromJson(Map<String, dynamic> json) =>
    _DialogueCharacter(
      id: json['id'] as String,
      name: json['name'] as String,
      imageAsset: json['imageAsset'] as String?,
    );

Map<String, dynamic> _$DialogueCharacterToJson(_DialogueCharacter instance) =>
    <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'imageAsset': instance.imageAsset,
    };

_DialogueTurn _$DialogueTurnFromJson(Map<String, dynamic> json) =>
    _DialogueTurn(
      id: json['id'] as String,
      speakerId: json['speakerId'] as String,
      text: json['text'] as String?,
      interactionId: json['interactionId'] as String?,
    );

Map<String, dynamic> _$DialogueTurnToJson(_DialogueTurn instance) =>
    <String, dynamic>{
      'id': instance.id,
      'speakerId': instance.speakerId,
      'text': instance.text,
      'interactionId': instance.interactionId,
    };

_DialogueScene _$DialogueSceneFromJson(Map<String, dynamic> json) =>
    _DialogueScene(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      characters: (json['characters'] as List<dynamic>?)
              ?.map(
                  (e) => DialogueCharacter.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <DialogueCharacter>[],
      turns: (json['turns'] as List<dynamic>?)
              ?.map((e) => DialogueTurn.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const <DialogueTurn>[],
    );

Map<String, dynamic> _$DialogueSceneToJson(_DialogueScene instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'characters': instance.characters,
      'turns': instance.turns,
    };
