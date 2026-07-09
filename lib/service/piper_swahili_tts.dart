// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:audioplayers/audioplayers.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

/// Offline Piper TTS for Swahili.
///
/// Bundles the int8-quantized `sw_CD-lanfrica-medium` Piper model under
/// `assets/voices/swahili/vits-piper-sw_CD-lanfrica-medium-int8/` and copies
/// it to app storage on first use. Models are synthesized at runtime, so no
/// per-word/per-sentence MP3 assets are needed.
@lazySingleton
class PiperSwahiliTts {
  static const String _assetDir =
      'assets/voices/swahili/vits-piper-sw_CD-lanfrica-medium-int8';
  static const String _modelFile = 'sw_CD-lanfrica-medium.onnx';
  static const String _tokensFile = 'tokens.txt';
  static const String _dataDir = 'espeak-ng-data';

  sherpa_onnx.OfflineTts? _tts;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _initializing = false;
  bool _initFailed = false;

  /// True if the model is ready to synthesize.
  bool get isReady => _tts != null;

  /// Synthesize [text] with Piper and play it.
  ///
  /// Initializes the model on the first call. If initialization fails or the
  /// platform is unsupported, throws so the caller can fall back to another
  /// TTS engine (e.g. flutter_tts).
  Future<void> speak(String text, {double speed = 1.0}) async {
    if (text.isEmpty) return;

    if (_tts == null) {
      if (_initFailed) {
        throw StateError('Piper Swahili TTS initialization previously failed');
      }
      await _init();
    }

    final tts = _tts;
    if (tts == null) {
      throw StateError('Piper Swahili TTS is not available');
    }

    final genConfig = sherpa_onnx.OfflineTtsGenerationConfig(
      sid: 0,
      speed: speed,
      silenceScale: 0.2,
    );

    final audio = tts.generateWithConfig(text: text, config: genConfig);

    final tempDir = await getTemporaryDirectory();
    final filename = p.join(
      tempDir.path,
      'piper_swahili_${DateTime.now().millisecondsSinceEpoch}.wav',
    );

    final ok = sherpa_onnx.writeWave(
      filename: filename,
      samples: audio.samples,
      sampleRate: audio.sampleRate,
    );

    if (!ok) {
      throw StateError('Piper failed to write wave file');
    }

    await _audioPlayer.stop();
    await _audioPlayer.play(DeviceFileSource(filename));
  }

  /// Dispose native resources.
  void dispose() {
    _tts?.free();
    _tts = null;
    _audioPlayer.dispose();
  }

  Future<void> _init() async {
    if (_initializing || _tts != null) return;
    _initializing = true;

    try {
      sherpa_onnx.initBindings();

      final docDir = await getApplicationDocumentsDirectory();
      final modelDir = p.join(docDir.path, 'voices', 'swahili',
          'vits-piper-sw_CD-lanfrica-medium-int8');

      final modelPath =
          await _copyAssetFile(p.join(_assetDir, _modelFile), modelDir);
      final tokensPath =
          await _copyAssetFile(p.join(_assetDir, _tokensFile), modelDir);
      final dataDirPath =
          await _copyAssetDir(p.join(_assetDir, _dataDir), modelDir);

      final vits = sherpa_onnx.OfflineTtsVitsModelConfig(
        model: modelPath,
        tokens: tokensPath,
        dataDir: dataDirPath,
      );

      final modelConfig = sherpa_onnx.OfflineTtsModelConfig(
        vits: vits,
        kokoro: const sherpa_onnx.OfflineTtsKokoroModelConfig(),
        numThreads: 2,
        debug: kDebugMode,
        provider: 'cpu',
      );

      final config = sherpa_onnx.OfflineTtsConfig(
        model: modelConfig,
        maxNumSenetences: 1,
      );

      _tts = sherpa_onnx.OfflineTts(config);
    } catch (e, st) {
      _initFailed = true;
      debugPrint('PiperSwahiliTts init failed: $e\n$st');
      rethrow;
    } finally {
      _initializing = false;
    }
  }

  Future<String> _copyAssetFile(String assetPath, String destDir) async {
    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
    final target = p.join(destDir, p.basename(assetPath));
    final file = File(target);

    // Skip copy if the file already exists and has the same size.
    if (await file.exists() && await file.length() == bytes.length) {
      return target;
    }

    await file.create(recursive: true);
    await file.writeAsBytes(bytes, flush: true);
    return target;
  }

  Future<String> _copyAssetDir(String assetDir, String destRoot) async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final allAssets = manifest.listAssets();

    for (final assetPath in allAssets) {
      if (!assetPath.startsWith('$assetDir/')) continue;

      final relativePath = p.relative(assetPath, from: assetDir);
      final targetPath = p.join(destRoot, p.basename(assetDir), relativePath);
      final data = await rootBundle.load(assetPath);
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final file = File(targetPath);

      if (await file.exists() && await file.length() == bytes.length) {
        continue;
      }

      await file.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
    }

    return p.join(destRoot, p.basename(assetDir));
  }
}
