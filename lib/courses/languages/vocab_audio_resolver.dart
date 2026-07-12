// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:varnamala/courses/languages/vocab.dart';
import 'package:varnamala/domain/audio/vocab_audio_resolver.dart';

/// [VocabAudioResolver] backed by [vocabById].
///
/// The lookup map is populated at startup by [loadVocabulary]; until
/// then unknown ids fall back to speaking the raw [wordId] string.
@LazySingleton(as: VocabAudioResolver)
class VocabAudioResolverImpl implements VocabAudioResolver {
  @override
  ResolvedVocabAudio resolve(String wordId) {
    final entry = vocabById[wordId];
    final asset = entry?.audioAsset;
    return ResolvedVocabAudio(
      audioAsset: (asset != null && asset.isNotEmpty) ? asset : null,
      speakText: entry?.term ?? wordId,
    );
  }
}