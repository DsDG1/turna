// Package imports:
import 'package:freezed_annotation/freezed_annotation.dart';

import 'interaction.dart';

part 'listening_phase.freezed.dart';
part 'listening_phase.g.dart';

/// The three phases of a listening lesson.
enum ListeningPhaseType {
  /// Phase 1: word pairing (TL audio ↔ English meaning).
  wordPairing,

  /// Phase 2: dialogue with comprehension questions.
  dialogue,

  /// Phase 3: summary audio, no questions.
  summary,
}

/// One phase of a listening lesson.
@freezed
class ListeningPhase with _$ListeningPhase {
  const factory ListeningPhase({
    required String id,
    required String name,

    /// Which part of the listening lesson this phase represents.
    @Default(ListeningPhaseType.dialogue) ListeningPhaseType type,

    /// Audio asset to play for this phase.
    String? audioAsset,

    /// Optional transcript shown after the audio has played.
    @Default('') String transcript,

    /// Interactions for this phase. Word-pairing and dialogue phases use these;
    /// summary phases leave it empty.
    @Default(<Interaction>[]) List<Interaction> items,
  }) = _ListeningPhase;

  factory ListeningPhase.fromJson(Map<String, dynamic> json) =>
      _$ListeningPhaseFromJson(json);
}
