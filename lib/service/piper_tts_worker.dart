// Dart imports:
import 'dart:async';
import 'dart:isolate';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa_onnx;

/// Background-isolate worker that owns the Piper [sherpa_onnx.OfflineTts]
/// instance so neural inference never runs on the main isolate.
///
/// [sherpa_onnx.OfflineTts] holds an FFI native pointer that cannot cross
/// isolate boundaries, so `compute()` (which re-initializes per call) is not
/// viable. Instead this worker is spawned once and reused: the main isolate
/// sends `init` with on-disk model paths, then `synthesize` requests, and the
/// worker writes a WAV file to an agreed `outPath` that the main isolate plays
/// back via [audioplayers] (a platform channel — must stay on the main
/// isolate).
///
/// Message protocol (all values are SendPort-serializable primitives/Maps):
///  - main → worker `{'op':'init','model','tokens','dataDir','numThreads','debug'}`
///    → reply `{'ok':true}` | `{'ok':false,'error'}`
///  - main → worker `{'op':'synthesize','text','speed','outPath'}`
///    → reply `{'ok':true,'path'}` | `{'ok':false,'error'}`
///  - main → worker `{'op':'dispose'}` → reply `{'ok':true}`, then exits.
class PiperTtsWorker {
  PiperTtsWorker._(this._sendPort, this._replies, this._isolate);

  final SendPort _sendPort;
  final ReceivePort _replies;
  final Isolate _isolate;

  /// Spawns the worker isolate and sends `init`. Resolves once the worker has
  /// loaded the model, or throws the worker's error string.
  static Future<PiperTtsWorker> spawn({
    required String modelPath,
    required String tokensPath,
    required String dataDirPath,
    int numThreads = 2,
    bool debug = false,
  }) async {
    final replies = ReceivePort();
    final isolate = await Isolate.spawn(_entry, replies.sendPort);
    // First message from the worker is its command SendPort.
    final commandPort = await replies.first as SendPort;

    final worker = PiperTtsWorker._(commandPort, replies, isolate);
    await worker._roundTrip({
      'op': 'init',
      'model': modelPath,
      'tokens': tokensPath,
      'dataDir': dataDirPath,
      'numThreads': numThreads,
      'debug': debug,
    });
    return worker;
  }

  /// Synthesize [text] into the WAV at [outPath]. Throws on worker error.
  Future<void> synthesize(String text, double speed, String outPath) async {
    await _roundTrip({
      'op': 'synthesize',
      'text': text,
      'speed': speed,
      'outPath': outPath,
    });
  }

  /// Release the native model and tear down the isolate.
  Future<void> dispose() async {
    try {
      await _roundTrip({'op': 'dispose'});
    } catch (_) {
      // Best-effort: even if the reply fails, kill the isolate below.
    }
    _replies.close();
    _isolate.kill(priority: Isolate.immediate);
  }

  Future<void> _roundTrip(Map<String, Object?> request) async {
    final completer = Completer<Map<String, Object?>>();
    late StreamSubscription sub;
    sub = _replies.listen((message) {
      final map = message as Map<String, Object?>;
      sub.cancel();
      if (map['ok'] == true) {
        completer.complete(map);
      } else {
        completer.completeError(
          StateError(map['error']?.toString() ?? 'Piper TTS worker error'),
        );
      }
    });
    try {
      _sendPort.send(request);
    } catch (e) {
      // The isolate may have died (send throws). Cancel the listener and
      // complete the future so the caller isn't left awaiting forever.
      sub.cancel();
      completer.completeError(
        StateError('Piper TTS worker send failed: $e'),
      );
    }
    await completer.future;
  }

  // ──────────────────────────────────────────────────────────────────────
  // Isolate entry + command loop
  // ──────────────────────────────────────────────────────────────────────

  static void _entry(SendPort mainPort) {
    final commands = ReceivePort();
    mainPort.send(commands.sendPort);

    sherpa_onnx.OfflineTts? tts;

    void reply(Map<String, Object?> m) => mainPort.send(m);

    commands.listen((raw) {
      final req = raw as Map<String, Object?>;
      final op = req['op'] as String;
      try {
        switch (op) {
          case 'init':
            // FFI bindings are isolate-local: each worker must init its own.
            sherpa_onnx.initBindings();
            final vits = sherpa_onnx.OfflineTtsVitsModelConfig(
              model: req['model'] as String,
              tokens: req['tokens'] as String,
              dataDir: req['dataDir'] as String,
            );
            final modelConfig = sherpa_onnx.OfflineTtsModelConfig(
              vits: vits,
              kokoro: const sherpa_onnx.OfflineTtsKokoroModelConfig(),
              numThreads: (req['numThreads'] as num?)?.toInt() ?? 2,
              debug: (req['debug'] as bool?) ?? false,
              provider: 'cpu',
            );
            final config = sherpa_onnx.OfflineTtsConfig(
              model: modelConfig,
              maxNumSenetences: 1,
            );
            tts = sherpa_onnx.OfflineTts(config);
            reply({'ok': true});
            break;

          case 'synthesize':
            final t = tts;
            if (t == null) {
              reply({'ok': false, 'error': 'Piper worker not initialized'});
              break;
            }
            final audio = t.generateWithConfig(
              text: req['text'] as String,
              config: sherpa_onnx.OfflineTtsGenerationConfig(
                sid: 0,
                speed: (req['speed'] as num?)?.toDouble() ?? 1.0,
                silenceScale: 0.2,
              ),
            );
            final outPath = req['outPath'] as String;
            final ok = sherpa_onnx.writeWave(
              filename: outPath,
              samples: audio.samples,
              sampleRate: audio.sampleRate,
            );
            if (!ok) {
              reply({'ok': false, 'error': 'Piper failed to write wave file'});
              break;
            }
            reply({'ok': true, 'path': outPath});
            break;

          case 'dispose':
            tts?.free();
            tts = null;
            reply({'ok': true});
            commands.close();
            Isolate.exit();
            // Isolate.exit() is Never — no break needed.

          default:
            reply({'ok': false, 'error': 'Unknown op: $op'});
        }
      } catch (e, st) {
        debugPrint('PiperTtsWorker $op failed: $e\n$st');
        reply({'ok': false, 'error': e.toString()});
      }
    });
  }
}