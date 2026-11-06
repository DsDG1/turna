import 'package:flutter/material.dart';
import 'package:turna/application/smart_speech.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/domain/course/dialogue_scene.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/lesson/components/cached_asset_image.dart';
import 'package:turna/views/widgets/tts_feedback.dart';
import 'package:turna/views/widgets/turna_sheet.dart';

List<DialogueTurn> visibleDialogueTurns(
  DialogueScene scene,
  String currentInteractionId,
) {
  final visible = <DialogueTurn>[];
  for (final turn in scene.turns) {
    visible.add(turn);
    if (turn.interactionId == currentInteractionId) break;
  }
  return visible;
}

class DialogueSceneHeader extends StatelessWidget {
  const DialogueSceneHeader({
    super.key,
    required this.scene,
    required this.interactions,
    required this.currentInteractionId,
    required this.currentSubmitted,
  });

  final DialogueScene scene;
  final List<Interaction> interactions;
  final String currentInteractionId;
  final bool currentSubmitted;

  @override
  Widget build(BuildContext context) {
    final interactionById = <String, Interaction>{
      for (final item in interactions) item.id: item,
    };
    final visible = visibleDialogueTurns(scene, currentInteractionId);
    final recent =
        visible.length <= 3 ? visible : visible.sublist(visible.length - 3);
    final activeSpeakerId = scene.turns
        .where((turn) => turn.interactionId == currentInteractionId)
        .map((turn) => turn.speakerId)
        .firstOrNull;

    return Container(
      margin: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      padding: const EdgeInsets.all(16),
      decoration: TurnaTheme.flatPaperDecoration(
        context,
        borderRadius: BorderRadius.circular(TurnaTheme.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  scene.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: TurnaTheme.textPrimaryColor(context),
                      ),
                ),
              ),
              IconButton(
                tooltip: AppStrings.lessonDialogueFullTranscript,
                icon: const Icon(Icons.forum_outlined),
                onPressed: () => _showTranscript(
                  context,
                  visible,
                  interactionById,
                ),
              ),
            ],
          ),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (final character in scene.characters)
                _CharacterBadge(
                  character: character,
                  active: character.id == activeSpeakerId,
                ),
            ],
          ),
          const SizedBox(height: 12),
          for (final turn in recent)
            _DialogueLine(
              turn: turn,
              speakerName: _speakerName(turn.speakerId),
              text: _turnText(turn, interactionById),
              obscure: turn.interactionId == currentInteractionId &&
                  !currentSubmitted,
              onSpeak: _speak,
            ),
        ],
      ),
    );
  }

  String _speakerName(String id) {
    for (final character in scene.characters) {
      if (character.id == id) return character.name;
    }
    return id;
  }

  String _turnText(
    DialogueTurn turn,
    Map<String, Interaction> interactionById,
  ) {
    if (turn.text != null) return turn.text!;
    if (turn.interactionId == currentInteractionId && !currentSubmitted) {
      return AppStrings.lessonDialogueYourTurn;
    }
    final item = interactionById[turn.interactionId];
    return item == null ? '' : interactionCorrectAnswerLabel(item) ?? '';
  }

  Future<void> _speak(BuildContext context, String speaker, String text) async {
    final result = await speakTargetChip(text);
    if (result != null && context.mounted) {
      showTtsFailureFeedback(context, result);
    }
  }

  void _showTranscript(
    BuildContext context,
    List<DialogueTurn> visible,
    Map<String, Interaction> interactionById,
  ) {
    showTurnaSheet<void>(
      context: context,
      title: scene.title,
      subtitle: AppStrings.lessonDialogueFullTranscript,
      isScrollControlled: true,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          for (final turn in visible)
            _DialogueLine(
              turn: turn,
              speakerName: _speakerName(turn.speakerId),
              text: _turnText(turn, interactionById),
              obscure: turn.interactionId == currentInteractionId &&
                  !currentSubmitted,
              onSpeak: _speak,
            ),
        ],
      ),
    );
  }
}

class _CharacterBadge extends StatelessWidget {
  const _CharacterBadge({required this.character, required this.active});

  final DialogueCharacter character;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final avatar = character.imageAsset == null
        ? Icon(
            Icons.face_rounded,
            color: TurnaTheme.brandTeal,
            size: 26,
          )
        : ExcludeSemantics(
            child: ClipOval(
              child: SizedBox(
                width: 42,
                height: 42,
                child: CachedAssetImage(
                  asset: character.imageAsset!,
                  maxHeight: 42,
                ),
              ),
            ),
          );
    return Semantics(
      label: active
          ? AppStrings.lessonDialogueCurrentSpeaker(character.name)
          : character.name,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? TurnaTheme.brandTeal.withValues(alpha: 0.10)
              : Colors.transparent,
          border: Border.all(
            color: active ? TurnaTheme.brandTeal : Colors.transparent,
            width: active ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 42, height: 42, child: Center(child: avatar)),
            const SizedBox(width: 6),
            Text(
              character.name,
              style: TextStyle(
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: TurnaTheme.textPrimaryColor(context),
              ),
            ),
            if (active) ...[
              const SizedBox(width: 4),
              const Icon(Icons.volume_up_rounded, size: 17),
            ],
          ],
        ),
      ),
    );
  }
}

class _DialogueLine extends StatelessWidget {
  const _DialogueLine({
    required this.turn,
    required this.speakerName,
    required this.text,
    required this.obscure,
    required this.onSpeak,
  });

  final DialogueTurn turn;
  final String speakerName;
  final String text;
  final bool obscure;
  final Future<void> Function(BuildContext, String, String) onSpeak;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  speakerName,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: TurnaTheme.textSecondaryColor(context),
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: TurnaTheme.textPrimaryColor(context),
                        fontStyle: obscure ? FontStyle.italic : null,
                      ),
                ),
              ],
            ),
          ),
          if (!obscure && text.isNotEmpty)
            IconButton(
              tooltip: AppStrings.lessonDialogueSpeakLine(speakerName),
              icon: const Icon(Icons.volume_up_outlined),
              onPressed: () => onSpeak(context, speakerName, text),
            ),
        ],
      ),
    );
  }
}
