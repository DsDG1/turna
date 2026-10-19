// Guards for a removal that cannot be pinned by a widget test.
//
// Anki cards are no longer read aloud by the app. The visible half of that is
// testable (`test/views/anki_card_renderer_test.dart` asserts no speaker
// control on either face), but the auto-read half is not: it runs through
// `autoReadOnTapForActiveCourse()`, which needs the DI graph, and it fires from
// a post-frame callback in `initState` — a path a widget test cannot arrange
// without standing up half the app. The review page's counterpart
// (`_maybeAutoSpeak` for `OfficialTemplateContent`) is a private method on a
// `State` that mounts a real engine. Source scans are the same technique the
// voice-copy batch used for a branch the host SDK cannot execute.
//
// What must NOT be caught here: the card's own media. `[sound:]` playback goes
// through `OfficialAnkiAvCoordinator` / `AnkiMediaStrip`, which this file does
// not touch — removing the app's TTS must not remove the card's audio.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _read(String path) => File(path).readAsStringSync();

void main() {
  test('the Anki flip-card renderer carries no TTS path', () {
    const path =
        'lib/views/lesson/components/interactions/anki_card_renderer.dart';
    final source = _read(path);

    // Positive markers first: a moved or truncated file would otherwise pass
    // every "must not contain" below without checking anything.
    expect(source, contains('class AnkiCardRenderer'),
        reason: 'the renderer moved; this guard is reading the wrong file');
    expect(source, contains('AnkiMediaStrip'),
        reason: 'the card media strip is the part that must survive');

    expect(source, isNot(contains('AudioController')),
        reason: 'the app must not speak an Anki card');
    expect(source, isNot(contains('autoReadOnTapForActiveCourse')),
        reason: 'auto-read is the same feature as the speaker button');
    expect(source, isNot(contains('currentSpeechLanguages')),
        reason: 'resolving a course voice for a card face is the removed path');
    expect(source, isNot(contains('detectCardPair')));
  });

  test('the review page does not speak official Anki cards', () {
    const path = 'lib/views/review/unified_review_page.dart';
    final source = _read(path);

    expect(source, contains('class _UnifiedReviewPageState'),
        reason: 'the review page moved; this guard is reading the wrong file');
    // Course cards keep their read-aloud; the Anki branch is the one that read
    // the card's HTML through the stripper and is now gone.
    expect(source, contains('_speakText(content.frontText)'));

    expect(
      source,
      isNot(contains('_speakText(stripHtml')),
      reason: 'reading an Anki card aloud is what the removal deleted',
    );
  });
}
