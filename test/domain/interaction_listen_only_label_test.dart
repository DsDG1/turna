// Regression: [interactionCorrectAnswerLabel] for [Interaction.listenOnly]
// used to fall back to the audioAsset path when no transcript was set,
// leaking file paths into the mistake log / UI. It should now return
// null — ListenOnly has no correctness verdict by design.

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/domain/course/interaction.dart';

void main() {
  group('interactionCorrectAnswerLabel', () {
    test('ListenOnly returns null regardless of transcript / audioAsset', () {
      expect(
        interactionCorrectAnswerLabel(
          const Interaction.listenOnly(
            id: 'lo1',
            transcript: '',
            audioAsset: 'assets/audio/some/audio.mp3',
          ),
        ),
        isNull,
      );
      expect(
        interactionCorrectAnswerLabel(
          const Interaction.listenOnly(
            id: 'lo2',
            transcript: 'spoken words',
            audioAsset: 'assets/audio/some/audio.mp3',
          ),
        ),
        isNull,
        reason: 'ListenOnly is listen-and-continue; no correct answer.',
      );
    });
  });
}
