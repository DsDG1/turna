import 'package:freezed_annotation/freezed_annotation.dart';

part 'dialogue_scene.freezed.dart';
part 'dialogue_scene.g.dart';

@freezed
abstract class DialogueCharacter with _$DialogueCharacter {
  const factory DialogueCharacter({
    required String id,
    required String name,
    String? imageAsset,
  }) = _DialogueCharacter;

  factory DialogueCharacter.fromJson(Map<String, dynamic> json) =>
      _$DialogueCharacterFromJson(json);
}

@freezed
abstract class DialogueTurn with _$DialogueTurn {
  const factory DialogueTurn({
    required String id,
    required String speakerId,
    String? text,
    String? interactionId,
  }) = _DialogueTurn;

  factory DialogueTurn.fromJson(Map<String, dynamic> json) =>
      _$DialogueTurnFromJson(json);
}

@freezed
abstract class DialogueScene with _$DialogueScene {
  const factory DialogueScene({
    required String id,
    @Default('') String title,
    @Default(<DialogueCharacter>[]) List<DialogueCharacter> characters,
    @Default(<DialogueTurn>[]) List<DialogueTurn> turns,
  }) = _DialogueScene;

  factory DialogueScene.fromJson(Map<String, dynamic> json) =>
      _$DialogueSceneFromJson(json);
}
