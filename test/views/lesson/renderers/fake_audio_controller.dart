import 'package:varnamala/application/audio_controller.dart';

/// A no-op [AudioController] for renderer/widget tests.
///
/// Records calls to [speak] and [speakWord] so tests can verify that tapping
/// a word or sentence triggered the right utterance.
class FakeAudioController implements AudioController {
  final List<String> spoken = [];

  String? get lastSpoken => spoken.isEmpty ? null : spoken.last;

  @override
  double get ttsSpeed => 1.0;

  @override
  Future<void> playRandomErrorSound() async {}

  @override
  Future<void> playRandomLevelUpSound() async {}

  @override
  Future<void> speak(String text, {double? speed}) async {
    spoken.add(text);
  }

  @override
  Future<TtsSpeakResult> speakWithResult(String text, {double? speed}) async {
    spoken.add(text);
    return const TtsSpeakResult(source: TtsSpeakSource.system);
  }

  @override
  TtsSpeakResult? get lastSpeakResult => null;

  @override
  Future<void> stopSystemTts() async {}

  @override
  Future<void> speakFromAsset(String assetPath) async {
    spoken.add(assetPath);
  }

  @override
  Future<void> speakWord(String wordId) async {
    spoken.add(wordId);
  }

  @override
  Future<void> speakListenContent({
    String? audioAsset,
    String transcript = '',
  }) async {
    final asset = audioAsset?.trim();
    final text = transcript.trim();
    if (asset != null && asset.isNotEmpty) {
      if (AudioController.isAssetPath(asset)) {
        await speakFromAsset(asset);
      } else if (text.isNotEmpty) {
        await speak(text);
      } else {
        await speakWord(asset);
      }
    } else if (text.isNotEmpty) {
      await speak(text);
    }
  }

  @override
  void setTtsSpeed(double speed) {}

  @override
  Future<void> rebindSystemTts() async {}
}
