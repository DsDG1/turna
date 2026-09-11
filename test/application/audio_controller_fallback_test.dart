// Tests for [AudioController.speakWord] offline-audio fallback routing.
// These tests avoid real platform channels by subclassing [AudioController]
// and overriding the methods that would touch [AudioPlayer] / [FlutterTts].

import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/accessibility_provider.dart';
import 'package:turna/application/audio_controller.dart';
import 'package:turna/application/course_pack/course_pack_media.dart';
import 'package:turna/application/language_provider.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/audio/anki_audio_resolver.dart';
import 'package:turna/domain/audio/vocab_audio_resolver.dart';
import 'package:turna/service/locator.dart';

class _FakeFlutterTts implements FlutterTts {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLanguageProvider implements LanguageProvider {
  @override
  String get ttsLanguageCode => 'tr';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAudioPlayer implements AudioPlayer {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RecordingAudioPlayer implements AudioPlayer {
  final List<Source> playedSources = [];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    if (invocation.memberName == #play) {
      playedSources.add(invocation.positionalArguments.first as Source);
      return Future<void>.value();
    }
    if (invocation.memberName == #stop ||
        invocation.memberName == #dispose ||
        invocation.memberName == #release) {
      return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

class _FakeAnkiAudioResolver extends AnkiAudioResolver {
  final Map<String, String> paths;

  _FakeAnkiAudioResolver(this.paths);

  @override
  Future<String?> resolveMediaPath(String assetPath) async => paths[assetPath];
}

/// In-memory [VocabAudioResolver] for speakWord routing tests.
class _MapVocabAudioResolver implements VocabAudioResolver {
  final Map<String, ResolvedVocabAudio> entries;

  _MapVocabAudioResolver(this.entries);

  @override
  ResolvedVocabAudio resolve(String wordId) {
    return entries[wordId] ?? ResolvedVocabAudio(speakText: wordId);
  }
}

class _TestAudioController extends AudioController {
  final List<String> ttsCalls = [];
  final List<String> assetCalls = [];
  final List<String> ankiCalls = [];
  final List<String> packCalls = [];

  _TestAudioController(VocabAudioResolver resolver)
      : super(
          _FakeFlutterTts(),
          _FakeLanguageProvider(),
          getIt<SettingsProvider>(),
          getIt<AccessibilityProvider>(),
          resolver,
          audioPlayer: _FakeAudioPlayer(),
          speechPlayer: _FakeAudioPlayer(),
        );

  @override
  Future<void> speak(String text, {double? speed, String? languageCode}) async {
    ttsCalls.add(text);
  }

  @override
  Future<void> speakFromAsset(String assetPath) async {
    assetCalls.add(assetPath);
  }

  @override
  Future<bool> playAnkiMedia(String ref) async {
    ankiCalls.add(ref);
    return true;
  }

  @override
  Future<bool> playCoursePackMedia(String ref) async {
    packCalls.add(ref);
    return true;
  }
}

void main() {
  group('AudioController.speakWord fallback', () {
    late _TestAudioController controller;
    late _MapVocabAudioResolver resolver;

    setUp(() async {
      // AudioController reads ttsSpeed from SettingsProvider on construction,
      // so register a real one backed by mock prefs before building it.
      await getIt.reset();
      SharedPreferences.setMockInitialValues({});
      final sp = await StreamingSharedPreferences.instance;
      final prefs = AppPrefs(sp);
      getIt.registerLazySingleton<AppPrefs>(() => prefs);
      getIt.registerLazySingleton<SettingsProvider>(
        () => SettingsProvider(prefs),
      );
      getIt.registerLazySingleton<AccessibilityProvider>(
        () => AccessibilityProvider(prefs),
      );
      resolver = _MapVocabAudioResolver({});
      controller = _TestAudioController(resolver);
    });

    tearDown(() async {
      await getIt.reset();
    });

    test('audioAsset present → speaks from asset, no TTS', () async {
      resolver.entries['w-test-audio'] = const ResolvedVocabAudio(
        audioAsset: 'assets/audio/turkish/test.mp3',
        speakText: 'Test',
      );

      await controller.speakWord('w-test-audio');

      expect(controller.assetCalls, ['assets/audio/turkish/test.mp3']);
      expect(controller.ttsCalls, isEmpty);
    });

    test('audioAsset turnapack URI → pack playback, no TTS', () async {
      resolver.entries['w-pack'] = const ResolvedVocabAudio(
        audioAsset: 'turnapack://es/hola.mp3',
        speakText: 'hola',
      );

      await controller.speakWord('w-pack');

      expect(controller.packCalls, ['turnapack://es/hola.mp3']);
      expect(controller.assetCalls, isEmpty);
      expect(controller.ttsCalls, isEmpty);
    });

    test('audioAsset null → falls back to TTS with term', () async {
      resolver.entries['w-test-no-audio'] = const ResolvedVocabAudio(
        speakText: 'Habari',
      );

      await controller.speakWord('w-test-no-audio');

      expect(controller.assetCalls, isEmpty);
      expect(controller.ttsCalls, ['Habari']);
    });

    test('audioAsset empty → falls back to TTS with term', () async {
      // Empty asset is treated as absent by the vocab resolver; the map
      // resolver mirrors that by omitting audioAsset.
      resolver.entries['w-test-empty-audio'] = const ResolvedVocabAudio(
        speakText: 'Jambo',
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

  group('AudioController asset path helpers', () {
    test('isAssetPath detects paths vs word ids', () {
      expect(AudioController.isAssetPath('assets/audio/x.mp3'), isTrue);
      expect(AudioController.isAssetPath('audio/turkish/x.mp3'), isTrue);
      expect(AudioController.isAssetPath('/assets/audio/x.mp3'), isTrue);
      expect(AudioController.isAssetPath('w-habari'), isFalse);
      expect(AudioController.isAssetPath('habari'), isFalse);
    });

    test('normalizeAssetPath strips assets/ and leading slash', () {
      expect(
        AudioController.normalizeAssetPath('assets/audio/x.mp3'),
        'audio/x.mp3',
      );
      expect(
        AudioController.normalizeAssetPath('/assets/audio/x.mp3'),
        'audio/x.mp3',
      );
      expect(
        AudioController.normalizeAssetPath('audio/x.mp3'),
        'audio/x.mp3',
      );
    });
  });

  group('AudioController.speakListenContent', () {
    late _TestAudioController controller;

    setUp(() async {
      await getIt.reset();
      SharedPreferences.setMockInitialValues({});
      final sp = await StreamingSharedPreferences.instance;
      final prefs = AppPrefs(sp);
      getIt.registerLazySingleton<AppPrefs>(() => prefs);
      getIt.registerLazySingleton<SettingsProvider>(
        () => SettingsProvider(prefs),
      );
      getIt.registerLazySingleton<AccessibilityProvider>(
        () => AccessibilityProvider(prefs),
      );
      controller = _TestAudioController(_MapVocabAudioResolver({
        'w-habari': const ResolvedVocabAudio(speakText: 'Habari'),
      }));
    });

    tearDown(() async {
      await getIt.reset();
    });

    test('asset path → speakFromAsset', () async {
      await controller.speakListenContent(
        audioAsset: 'assets/sounds/turkish/listening/x.mp3',
      );
      expect(controller.assetCalls, ['assets/sounds/turkish/listening/x.mp3']);
      expect(controller.ttsCalls, isEmpty);
    });

    test('anki reference → local Anki playback before generic asset routing',
        () async {
      await controller.speakListenContent(
        audioAsset: 'anki://imp/voice.mp3',
        transcript: 'must not use TTS',
      );

      expect(controller.ankiCalls, ['anki://imp/voice.mp3']);
      expect(controller.assetCalls, isEmpty);
      expect(controller.ttsCalls, isEmpty);
    });

    test('turnapack reference → pack playback before asset routing', () async {
      await controller.speakListenContent(
        audioAsset: 'turnapack://es/hola.mp3',
        transcript: 'must not use TTS',
      );
      expect(controller.packCalls, ['turnapack://es/hola.mp3']);
      expect(controller.assetCalls, isEmpty);
      expect(controller.ttsCalls, isEmpty);
    });

    test('word id with transcript → prefer transcript TTS', () async {
      await controller.speakListenContent(
        audioAsset: 'w-habari',
        transcript: 'Habari yako',
      );
      expect(controller.ttsCalls, ['Habari yako']);
      expect(controller.assetCalls, isEmpty);
    });

    test('word id without transcript → speakWord', () async {
      await controller.speakListenContent(audioAsset: 'w-habari');
      expect(controller.ttsCalls, ['Habari']);
    });

    test('transcript only → speak transcript', () async {
      await controller.speakListenContent(transcript: 'Karibu');
      expect(controller.ttsCalls, ['Karibu']);
    });
  });

  group('AudioController.playAnkiMedia', () {
    setUp(() async {
      await getIt.reset();
      SharedPreferences.setMockInitialValues({});
      final sp = await StreamingSharedPreferences.instance;
      final prefs = AppPrefs(sp);
      getIt.registerLazySingleton<AppPrefs>(() => prefs);
      getIt.registerLazySingleton<SettingsProvider>(
        () => SettingsProvider(prefs),
      );
      getIt.registerLazySingleton<AccessibilityProvider>(
        () => AccessibilityProvider(prefs),
      );
    });

    tearDown(() async => getIt.reset());

    test('resolved anki reference plays through DeviceFileSource', () async {
      final speechPlayer = _RecordingAudioPlayer();
      final controller = AudioController(
        _FakeFlutterTts(),
        _FakeLanguageProvider(),
        getIt<SettingsProvider>(),
        getIt<AccessibilityProvider>(),
        _MapVocabAudioResolver({}),
        audioPlayer: _FakeAudioPlayer(),
        speechPlayer: speechPlayer,
        ankiMediaResolver: _FakeAnkiAudioResolver({
          'anki://imp/voice.mp3': r'C:\media\voice.mp3',
        }),
      );

      expect(await controller.playAnkiMedia('anki://imp/voice.mp3'), isTrue);
      expect(speechPlayer.playedSources, hasLength(1));
      expect(speechPlayer.playedSources.single, isA<DeviceFileSource>());
      expect(
        (speechPlayer.playedSources.single as DeviceFileSource).path,
        r'C:\media\voice.mp3',
      );
    });

    test('missing or non-Anki references return false without playback',
        () async {
      final speechPlayer = _RecordingAudioPlayer();
      final controller = AudioController(
        _FakeFlutterTts(),
        _FakeLanguageProvider(),
        getIt<SettingsProvider>(),
        getIt<AccessibilityProvider>(),
        _MapVocabAudioResolver({}),
        audioPlayer: _FakeAudioPlayer(),
        speechPlayer: speechPlayer,
        ankiMediaResolver: _FakeAnkiAudioResolver({}),
      );

      expect(await controller.playAnkiMedia('anki://imp/missing.mp3'), isFalse);
      expect(await controller.playAnkiMedia('assets/audio.mp3'), isFalse);
      expect(speechPlayer.playedSources, isEmpty);
    });
  });

  group('AudioController.playCoursePackMedia', () {
    setUp(() async {
      await getIt.reset();
      SharedPreferences.setMockInitialValues({});
      final sp = await StreamingSharedPreferences.instance;
      final prefs = AppPrefs(sp);
      getIt.registerLazySingleton<AppPrefs>(() => prefs);
      getIt.registerLazySingleton<SettingsProvider>(
        () => SettingsProvider(prefs),
      );
      getIt.registerLazySingleton<AccessibilityProvider>(
        () => AccessibilityProvider(prefs),
      );
    });

    tearDown(() async {
      CoursePackMedia.debugPersistRoot = null;
      await getIt.reset();
    });

    test('resolved pack reference plays through DeviceFileSource', () async {
      final root = await Directory.systemTemp.createTemp('pack-audio-');
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      CoursePackMedia.debugPersistRoot = root;
      final file = File(p.join(root.path, 'es', 'media', 'hola.mp3'))
        ..createSync(recursive: true)
        ..writeAsBytesSync(const [1, 2, 3]);
      final speechPlayer = _RecordingAudioPlayer();
      final controller = AudioController(
        _FakeFlutterTts(),
        _FakeLanguageProvider(),
        getIt<SettingsProvider>(),
        getIt<AccessibilityProvider>(),
        _MapVocabAudioResolver({}),
        audioPlayer: _FakeAudioPlayer(),
        speechPlayer: speechPlayer,
      );

      expect(
        await controller.playCoursePackMedia('turnapack://es/hola.mp3'),
        isTrue,
      );
      expect(speechPlayer.playedSources.single, isA<DeviceFileSource>());
      expect(
        (speechPlayer.playedSources.single as DeviceFileSource).path,
        file.path,
      );
    });
  });
}
