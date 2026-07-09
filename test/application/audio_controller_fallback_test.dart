// Tests for [AudioController.speakWord] offline-audio fallback routing.
// These tests avoid real platform channels by subclassing [AudioController]
// and overriding the methods that would touch [AudioPlayer] / [FlutterTts].

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:words625/application/audio_controller.dart';
import 'package:words625/application/language_provider.dart';
import 'package:words625/courses/languages/swahili_vocab.dart';
import 'package:words625/domain/course/word_entry.dart';

class _FakeFlutterTts implements FlutterTts {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLanguageProvider implements LanguageProvider {
  @override
  String get ttsLanguageCode => 'sw';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAudioPlayer implements AudioPlayer {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _TestAudioController extends AudioController {
  final List<String> ttsCalls = [];
  final List<String> assetCalls = [];

  _TestAudioController()
      : super(
          _FakeFlutterTts(),
          _FakeLanguageProvider(),
          audioPlayer: _FakeAudioPlayer(),
          speechPlayer: _FakeAudioPlayer(),
        );

  @override
  Future<void> speak(String text, {double? speed}) async {
    ttsCalls.add(text);
  }

  @override
  Future<void> speakFromAsset(String assetPath) async {
    assetCalls.add(assetPath);
  }
}

void main() {
  group('AudioController.speakWord fallback', () {
    late _TestAudioController controller;

    setUp(() {
      controller = _TestAudioController();
    });

    tearDown(() {
      swahiliVocabById.remove('w-test-audio');
      swahiliVocabById.remove('w-test-no-audio');
      swahiliVocabById.remove('w-test-empty-audio');
    });

    test('audioAsset present → speaks from asset, no TTS', () async {
      swahiliVocabById['w-test-audio'] = const WordEntry(
        id: 'w-test-audio',
        term: 'Test',
        translation: 'Test',
        audioAsset: 'assets/audio/swahili/test.mp3',
      );

      await controller.speakWord('w-test-audio');

      expect(controller.assetCalls, ['assets/audio/swahili/test.mp3']);
      expect(controller.ttsCalls, isEmpty);
    });

    test('audioAsset null → falls back to TTS with term', () async {
      swahiliVocabById['w-test-no-audio'] = const WordEntry(
        id: 'w-test-no-audio',
        term: 'Habari',
        translation: 'Hello',
      );

      await controller.speakWord('w-test-no-audio');

      expect(controller.assetCalls, isEmpty);
      expect(controller.ttsCalls, ['Habari']);
    });

    test('audioAsset empty → falls back to TTS with term', () async {
      swahiliVocabById['w-test-empty-audio'] = const WordEntry(
        id: 'w-test-empty-audio',
        term: 'Jambo',
        translation: 'Hi',
        audioAsset: '',
      );

      await controller.speakWord('w-test-empty-audio');

      expect(controller.assetCalls, isEmpty);
      expect(controller.ttsCalls, ['Jambo']);
    });

    test('unknown wordId → falls back to TTS with wordId', () async {
      await controller.speakWord('w-unknown');

      expect(controller.assetCalls, isEmpty);
      expect(controller.ttsCalls, ['w-unknown']);
    });
  });
}
