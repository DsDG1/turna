import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/audio_controller.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/widgets/tts_feedback.dart';

void main() {
  test('cancellation and success do not produce error feedback', () {
    expect(
      ttsFailureMessage(const TtsSpeakResult(source: TtsSpeakSource.cancelled)),
      isNull,
    );
    expect(
      ttsFailureMessage(const TtsSpeakResult(source: TtsSpeakSource.system)),
      isNull,
    );
  });

  test('structured failures map to actionable copy without raw exceptions', () {
    const result = TtsSpeakResult(
      source: TtsSpeakSource.failed,
      failureReason: TtsFailureReason.voiceMissing,
      error: 'Bad state: internal platform detail',
    );
    expect(ttsFailureMessage(result), AppStrings.ttsFailureVoiceMissing);
    expect(ttsFailureMessage(result), isNot(contains('Bad state')));

    const timeout = TtsSpeakResult(
      source: TtsSpeakSource.failed,
      failureReason: TtsFailureReason.timeout,
    );
    expect(ttsFailureMessage(timeout), AppStrings.ttsFailureTimeout);
  });
}
