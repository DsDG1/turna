// Dart imports:
import 'dart:async';
import 'dart:io';

// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:audioplayers/audioplayers.dart';
import 'package:injectable/injectable.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// Project imports:
import 'package:varnamala/service/piper_tts_worker.dart';

/// Health / readiness of the offline Piper engine for settings UI.
enum PiperTtsStatus {
  /// Model not loaded yet; next speak/prewarm will try.
  idle,

  /// Asset copy + isolate init in progress.
  loading,

  /// Ready to synthesize.
  ready,

  /// Last init failed; [resetFailure] or speak may retry.
  failed,
}

/// Offline Piper TTS for Swahili.
///
/// Bundles the int8-quantized `sw_CD-lanfrica-medium` Piper model under
/// `assets/voices/swahili/vits-piper-sw_CD-lanfrica-medium-int8/` and copies
/// it to app storage on first use. The ONNX model lives in a long-lived
/// background isolate ([PiperTtsWorker]) so neural synthesis never blocks the
/// UI thread; only the WAV playback (a platform channel) runs on the main
/// isolate.
@lazySingleton
class PiperSwahiliTts {
  static const String _assetDir =
      'assets/voices/swahili/vits-piper-sw_CD-lanfrica-medium-int8';
  static const String _modelFile = 'sw_CD-lanfrica-medium.onnx';
  static const String _tokensFile = 'tokens.txt';
  static const String _dataDir = 'espeak-ng-data';

  /// How many automatic re-inits after a failed prewarm/speak before giving up
  /// until [resetFailure] is called.
  static const int _maxAutoRetries = 2;

  PiperTtsWorker? _worker;
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _initializing = false;
  bool _initFailed = false;
  int _autoRetryCount = 0;
  String? _lastError;

  /// In-flight init waiters share this completer (no busy-wait polling).
  Completer<void>? _initCompleter;

  // Serializes synthesize requests: only one inference runs at a time so the
  // single worker isolate isn't asked to overlap generations.
  Future<void> _inflight = Future<void>.value();

  /// True if the model is ready to synthesize.
  bool get isReady => _worker != null;

  bool get initFailed => _initFailed;

  String? get lastError => _lastError;

  PiperTtsStatus get status {
    if (_worker != null) return PiperTtsStatus.ready;
    if (_initializing) return PiperTtsStatus.loading;
    if (_initFailed) return PiperTtsStatus.failed;
    return PiperTtsStatus.idle;
  }

  /// Clears a sticky failure so the next [speak] / [prewarm] can re-init.
  void resetFailure() {
    _initFailed = false;
    _autoRetryCount = 0;
    _lastError = null;
    debugPrint('PiperSwahiliTts: failure state cleared (retry allowed)');
  }

  /// Synthesize [text] with Piper and play it.
  ///
  /// Initializes the worker isolate on the first call. If initialization fails
  /// or the platform is unsupported, throws so the caller can fall back to
  /// another TTS engine (e.g. flutter_tts).
  Future<void> speak(String text, {double speed = 1.0}) async {
    if (text.isEmpty) return;

    if (_worker == null) {
      if (_initFailed) {
        if (_autoRetryCount < _maxAutoRetries) {
          _autoRetryCount++;
          _initFailed = false;
          debugPrint(
            'PiperSwahiliTts: auto-retry init '
            '($_autoRetryCount/$_maxAutoRetries)',
          );
        } else {
          throw StateError(
            'Piper Swahili TTS initialization previously failed'
            '${_lastError != null ? ": $_lastError" : ""}',
          );
        }
      }
      await _init();
    }

    final worker = _worker;
    if (worker == null) {
      throw StateError('Piper Swahili TTS is not available');
    }

    // Queue: chain each request after the previous one completes so the
    // worker handles them in order.
    _inflight = _inflight.then((_) => _synthesizeAndPlay(worker, text, speed));
    await _inflight;
  }

  /// Eagerly start the worker isolate + model load without synthesizing, so
  /// the first [speak] does not pay the init latency. Safe to call from a
  /// post-frame callback on the splash screen.
  ///
  /// Failures are recorded but do **not** permanently ban later [speak]
  /// retries ([_maxAutoRetries] still applies).
  Future<void> prewarm() async {
    if (_worker != null || _initializing) return;
    if (_initFailed && _autoRetryCount >= _maxAutoRetries) return;
    try {
      if (_initFailed) {
        _initFailed = false;
        _autoRetryCount++;
      }
      await _init();
    } catch (e) {
      // Best-effort: leave _initFailed set; speak may still auto-retry.
      debugPrint('PiperSwahiliTts: prewarm failed (non-fatal): $e');
    }
  }

  Future<void> _synthesizeAndPlay(
    PiperTtsWorker worker,
    String text,
    double speed,
  ) async {
    final tempDir = await getTemporaryDirectory();
    final outPath = p.join(
      tempDir.path,
      'piper_swahili_${DateTime.now().millisecondsSinceEpoch}.wav',
    );

    debugPrint('PiperSwahiliTts: synthesize len=${text.length} speed=$speed');
    await worker.synthesize(text, speed, outPath);

    await _audioPlayer.stop();
    await _audioPlayer.play(DeviceFileSource(outPath));
    debugPrint('PiperSwahiliTts: playing $outPath');
  }

  /// Dispose native resources (worker isolate + model + audio player).
  void dispose() {
    _worker?.dispose();
    _worker = null;
    _audioPlayer.dispose();
  }

  Future<void> _init() async {
    // Join an in-flight init instead of busy-polling `_initializing`.
    final inFlight = _initCompleter;
    if (inFlight != null) {
      await inFlight.future;
      if (_worker != null) return;
      if (_initFailed) {
        throw StateError(
          'Piper Swahili TTS initialization previously failed'
          '${_lastError != null ? ": $_lastError" : ""}',
        );
      }
      return;
    }
    if (_worker != null) return;

    final completer = Completer<void>();
    _initCompleter = completer;
    _initializing = true;

    try {
      final docDir = await getApplicationDocumentsDirectory();
      final modelDir = p.join(docDir.path, 'voices', 'swahili',
          'vits-piper-sw_CD-lanfrica-medium-int8');

      debugPrint('PiperSwahiliTts: copying assets → $modelDir');

      // Asset copying stays on the main isolate — rootBundle / path_provider
      // are main-isolate services. The worker only needs the resulting paths.
      final modelPath =
          await _copyAssetFile(p.join(_assetDir, _modelFile), modelDir);
      final tokensPath =
          await _copyAssetFile(p.join(_assetDir, _tokensFile), modelDir);
      final dataDirPath =
          await _copyAssetDir(p.join(_assetDir, _dataDir), modelDir);

      debugPrint(
        'PiperSwahiliTts: spawning worker model=$modelPath dataDir=$dataDirPath',
      );

      _worker = await PiperTtsWorker.spawn(
        modelPath: modelPath,
        tokensPath: tokensPath,
        dataDirPath: dataDirPath,
        numThreads: 2,
        debug: kDebugMode,
      );
      _initFailed = false;
      _lastError = null;
      _autoRetryCount = 0;
      debugPrint('PiperSwahiliTts: worker initialized from $_assetDir');
      if (!completer.isCompleted) completer.complete();
    } catch (e, st) {
      _initFailed = true;
      _lastError = e.toString();
      debugPrint('PiperSwahiliTts init failed: $e\n$st');
      // Complete (not completeError) so waiters re-check `_initFailed` /
      // `_worker` with a consistent StateError message.
      if (!completer.isCompleted) completer.complete();
      rethrow;
    } finally {
      _initializing = false;
      _initCompleter = null;
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

    var copied = 0;
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
      copied++;
    }

    debugPrint(
      'PiperSwahiliTts: espeak-ng-data copy done (new/updated files=$copied)',
    );
    return p.join(destRoot, p.basename(assetDir));
  }
}
