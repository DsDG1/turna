// Tests for [AudioController.speakWord] offline-audio fallback routing.
// These tests avoid real platform channels by subclassing [AudioController]
// and overriding the methods that would touch [AudioPlayer] / [FlutterTts].

import 'dart:io';

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
import 'package:turna/domain/audio/vocab_audio_resolver.dart';
import 'package:turna/service/locator.dart';
import '../support/fake_audio_backend.dart';
import 'package:turna/service/speech_backend.dart';

class _FakeFlutterTts implements FlutterTts {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeLanguageProvider implements LanguageProvider {
  @override
  String selectedLanguageCode = 'tr';

  @override
  String get ttsLanguageCode => 'tr';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AttemptRecordingAudioBackend extends FakeAudioBackend {
  @override
  Future<void> playAsset(String assetPath) async {
    playedAssets.add(assetPath);
    final error = failure;
    if (error != null) throw error;
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }
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
  final List<String> packCalls = [];
  final List<String> officialCalls = [];
  final FakeAudioBackend speechBackend;
  bool officialMediaAvailable = false;

  factory _TestAudioController(VocabAudioResolver resolver) {
    final speechBackend = _AttemptRecordingAudioBackend();
    return _TestAudioController._(resolver, speechBackend);
  }

  _TestAudioController._(VocabAudioResolver resolver, this.speechBackend)
      : super(
          FlutterTtsSpeechBackend(_FakeFlutterTts()),
          _FakeLanguageProvider(),
          getIt<SettingsProvider>(),
          getIt<AccessibilityProvider>(),
          resolver,
          effects: FakeAudioBackend(name: 'effects'),
          speech: speechBackend,
        );

  @override
  Future<void> speak(String text, {double? speed, String? languageCode}) async {
    ttsCalls.add(text);
  }

  @override
  Future<TtsSpeakResult> speakWithResult(
    String text, {
    double? speed,
    String? languageCode,
  }) async {
    ttsCalls.add(text);
    return const TtsSpeakResult(source: TtsSpeakSource.system);
  }

  @override
  Future<void> speakFromAsset(String assetPath) async {
    assetCalls.add(assetPath);
  }

  @override
  Future<bool> playCoursePackMedia(String ref) async {
    packCalls.add(ref);
    return true;
  }

  @override
  Future<bool> playOfficialMediaFile(String rawName) async {
    officialCalls.add(rawName);
    return officialMediaAvailable;
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

    test('bundledListeningAssetPath maps Turkish ids to packed audio', () {
      expect(
        AudioController.bundledListeningAssetPath('l-pilot', 'tr'),
        'assets/sounds/turkish/listening/l-pilot.mp3',
      );
      expect(
        AudioController.bundledListeningAssetPath('l-pilot', 'es'),
        'assets/sounds/es/listening/l-pilot.mp3',
      );
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
      controller.speechBackend.failure = StateError('missing bundled audio');
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

    test('turnapack reference → pack playback before asset routing', () async {
      await controller.speakListenContent(
        audioAsset: 'turnapack://es/hola.mp3',
        transcript: 'must not use TTS',
      );
      expect(controller.packCalls, ['turnapack://es/hola.mp3']);
      expect(controller.assetCalls, isEmpty);
      expect(controller.ttsCalls, isEmpty);
    });

    test('bare listening id → canonical bundled MP3 before TTS', () async {
      controller.speechBackend.failure = null;
      await controller.speakListenContent(
        audioAsset: 'l-pilot',
        transcript: 'Merhaba',
      );
      expect(
        controller.speechBackend.playedAssets,
        ['sounds/turkish/listening/l-pilot.mp3'],
      );
      expect(controller.officialCalls, ['l-pilot']);
      expect(controller.ttsCalls, isEmpty);
    });

    test('official media wins over bundled listening audio', () async {
      controller.officialMediaAvailable = true;
      await controller.speakListenContent(audioAsset: 'l-official');
      expect(controller.officialCalls, ['l-official']);
      expect(controller.speechBackend.playedAssets, isEmpty);
      expect(controller.ttsCalls, isEmpty);
    });

    test('missing bundled audio falls back to transcript TTS', () async {
      await controller.speakListenContent(
        audioAsset: 'l-pilot',
        transcript: 'Merhaba',
      );
      expect(
        controller.speechBackend.playedAssets,
        ['sounds/turkish/listening/l-pilot.mp3'],
      );
      expect(controller.ttsCalls, ['Merhaba']);
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

    test('resolved pack reference plays from the sandbox file', () async {
      final root = await Directory.systemTemp.createTemp('pack-audio-');
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      CoursePackMedia.debugPersistRoot = root;
      final file = File(p.join(root.path, 'es', 'media', 'hola.mp3'))
        ..createSync(recursive: true)
        ..writeAsBytesSync(const [1, 2, 3]);
      final speechPlayer = FakeAudioBackend(name: 'speech');
      final controller = AudioController(
        FlutterTtsSpeechBackend(_FakeFlutterTts()),
        _FakeLanguageProvider(),
        getIt<SettingsProvider>(),
        getIt<AccessibilityProvider>(),
        _MapVocabAudioResolver({}),
        effects: FakeAudioBackend(name: 'effects'),
        speech: speechPlayer,
      );

      expect(
        await controller.playCoursePackMedia('turnapack://es/hola.mp3'),
        isTrue,
      );
      expect(speechPlayer.playedFiles.single, file.path);
      expect(speechPlayer.playedAssets, isEmpty);
    });
  });
}
