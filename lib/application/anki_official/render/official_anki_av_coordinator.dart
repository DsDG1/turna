import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/render/official_anki_media_resolver.dart';

enum OfficialAnkiAvSide { question, answer }

/// Plays official AV/TTS tags. Never scans HTML for [sound:] markers.
class OfficialAnkiAvCoordinator {
  OfficialAnkiAvCoordinator({
    required this.resolver,
    required this.player,
  });

  final OfficialAnkiMediaResolver resolver;
  final OfficialAnkiAvPlayer player;

  var _generation = 0;
  OfficialAnkiAvSide? _playingSide;
  OfficialAnkiRenderedCard? _card;
  String? lastError;

  int get generation => _generation;

  void attachCard(OfficialAnkiRenderedCard card) {
    _card = card;
    _generation += 1;
    _playingSide = null;
    lastError = null;
  }

  Future<void> showQuestion({bool autoplay = true}) async {
    await stop();
    await _playSide(OfficialAnkiAvSide.question, autoplay: autoplay);
  }

  Future<void> showAnswer({bool autoplay = true}) async {
    await stop();
    await _playSide(OfficialAnkiAvSide.answer, autoplay: autoplay);
  }

  Future<void> replay() async {
    final side = _playingSide ?? OfficialAnkiAvSide.question;
    await stop();
    await _playSide(side, autoplay: true, force: true);
  }

  /// Starts autoplay for [side] only if [token] is still the live generation.
  /// A flip must [stop] first; this must not be awaited by the flip path.
  Future<void> startAutoplay({
    required OfficialAnkiAvSide side,
    required int token,
  }) async {
    if (token != _generation) return;
    await _playSide(side, autoplay: true, force: true, token: token);
  }

  Future<void> nextCard() async {
    await stop();
    _card = null;
    _playingSide = null;
    _generation += 1;
  }

  Future<void> dispose() async {
    await nextCard();
    await player.dispose();
  }

  Future<void> _playSide(
    OfficialAnkiAvSide side, {
    required bool autoplay,
    bool force = false,
    int? token,
  }) async {
    if (!autoplay) {
      _playingSide = side;
      return;
    }
    if (!force && _playingSide == side) {
      return;
    }
    _playingSide = side;
    final playToken = token ?? _generation;
    if (playToken != _generation) return;
    final card = _card;
    if (card == null) return;
    final tags = side == OfficialAnkiAvSide.question
        ? card.questionAvTags
        : card.answerAvTags;
    for (final tag in tags) {
      if (playToken != _generation) return;
      await _playTag(tag, playToken);
      if (playToken != _generation) return;
    }
  }

  Future<void> _playTag(OfficialAnkiAvTag tag, int token) async {
    if (token != _generation) return;
    lastError = null;
    if (tag.kind == OfficialAnkiAvKind.soundOrVideo) {
      final name = tag.filename ?? '';
      final decision = resolver.resolveRelativeName(name);
      if (!decision.allowed || decision.file == null) {
        if (token == _generation) {
          lastError = 'official_anki.media_missing:$name';
        }
        return;
      }
      await player.playFile(decision.file!.path);
      return;
    }
    final text = tag.fieldText ?? '';
    if (text.isEmpty) {
      if (token == _generation) {
        lastError = 'official_anki.tts_empty';
      }
      return;
    }
    final spoken = await player.speak(
      text: text,
      lang: tag.lang,
      voices: tag.voices,
      speed: tag.speed,
      otherArgs: tag.otherArgs,
    );
    if (!spoken && token == _generation) {
      lastError = 'official_anki.tts_voice_unavailable';
    }
  }

  Future<void> stop() async {
    _generation += 1;
    await player.stop();
  }
}

abstract class OfficialAnkiAvPlayer {
  Future<void> playFile(String path);
  Future<bool> speak({
    required String text,
    String? lang,
    List<String> voices,
    double? speed,
    List<String> otherArgs = const <String>[],
  });
  Future<void> stop();
  Future<void> dispose();
}
