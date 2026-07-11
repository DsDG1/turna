// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:varnamala/courses/languages/swahili_vocab.dart';
import 'package:varnamala/domain/audio/vocab_audio_resolver.dart';

/// Swahili [VocabAudioResolver] backed by [swahiliVocabById].
///
/// The lookup map is populated at startup by [loadSwahiliVocabulary]; until
/// then unknown ids fall back to speaking the raw [wordId] string.
@LazySingleton(as: VocabAudioResolver)
class SwahiliVocabAudioResolver implements VocabAudioResolver {
  @override
  ResolvedVocabAudio resolve(String wordId) {
    final entry = swahiliVocabById[wordId];
    final asset = entry?.audioAsset;
    return ResolvedVocabAudio(
      audioAsset: (asset != null && asset.isNotEmpty) ? asset : null,
      speakText: entry?.term ?? wordId,
    );
  }
}
