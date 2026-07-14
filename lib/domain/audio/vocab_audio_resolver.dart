/// Resolved audio payload for a vocabulary word id.
///
/// Prefer [audioAsset] (offline pre-recorded) when non-null and non-empty;
/// otherwise TTS [speakText].
class ResolvedVocabAudio {
  const ResolvedVocabAudio({
    this.audioAsset,
    required this.speakText,
  });

  /// Offline asset path when present; may still include an `assets/` prefix.
  final String? audioAsset;

  /// Text to speak via TTS when no usable [audioAsset] is available.
  final String speakText;
}

/// Resolves vocabulary word ids to offline audio or TTS text.
///
/// Keeps [AudioController] free of language-specific content imports.
/// The Turkish build ships one implementation; other languages can register their own
/// without changing the audio stack (see ADR 0010).
abstract class VocabAudioResolver {
  /// Resolve [wordId] to an offline asset and/or TTS term.
  ResolvedVocabAudio resolve(String wordId);
}
