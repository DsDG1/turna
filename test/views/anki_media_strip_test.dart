import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/l10n/app_strings.dart';
import 'package:varnamala/views/lesson/components/anki_media_strip.dart';

void main() {
  Future<void> pumpStrip(
    WidgetTester tester, {
    required Future<String?> Function(String) resolve,
    required Future<bool> Function(String) play,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnkiMediaStrip(
            audioAssets: const ['anki://imp/voice.mp3'],
            resolveMediaPath: resolve,
            playAudio: play,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('available audio is manual-only and plays once per tap',
      (tester) async {
    final calls = <String>[];
    await pumpStrip(
      tester,
      resolve: (_) async => '/media/voice.mp3',
      play: (ref) async {
        calls.add(ref);
        return true;
      },
    );

    expect(calls, isEmpty);
    final button = find.byKey(const ValueKey('anki-audio-0'));
    expect(button, findsOneWidget);

    await tester.tap(button);
    await tester.pump();

    expect(calls, ['anki://imp/voice.mp3']);
  });

  testWidgets('missing audio keeps a visible disabled button', (tester) async {
    await pumpStrip(
      tester,
      resolve: (_) async => null,
      play: (_) async => true,
    );

    final button = tester.widget<IconButton>(
      find.byKey(const ValueKey('anki-audio-0')),
    );
    expect(button.onPressed, isNull);
    expect(find.byTooltip(AppStrings.lessonAudioMissing), findsOneWidget);
  });

  testWidgets('playback failure shows user feedback', (tester) async {
    await pumpStrip(
      tester,
      resolve: (_) async => '/media/voice.mp3',
      play: (_) async => false,
    );

    await tester.tap(find.byKey(const ValueKey('anki-audio-0')));
    await tester.pump();

    expect(find.text(AppStrings.lessonAudioPlaybackFailed), findsOneWidget);
  });
}
