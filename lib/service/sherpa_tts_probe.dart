// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

// Project imports:
import 'package:turna/core/logger.dart';
import 'package:turna/core/ohos_target.dart';
import 'package:turna/service/audio_backend.dart';

/// What the sherpa probe managed to do, kept as values rather than exceptions so
/// the caller can log the *reason* rather than a stringified failure.
sealed class SherpaProbeResult {
  const SherpaProbeResult();
}

/// The model loaded and a phrase was synthesised and handed to the player.
class SherpaProbeOk extends SherpaProbeResult {
  const SherpaProbeOk({
    required this.samples,
    required this.synthesisMs,
    required this.sampleRate,
  });

  final int samples;
  final int synthesisMs;
  final int sampleRate;
}

/// A named step failed. [stage] is the first thing that did not work, because
/// "TTS failed" is the same unhelpful sentence this whole area keeps producing.
class SherpaProbeFailed extends SherpaProbeResult {
  const SherpaProbeFailed(this.stage, this.detail);

  final String stage;
  final String detail;
}

/// One-shot check that the bundled sherpa model can actually speak.
///
/// Exists for the same reason as [probeAudioChannel]: on this platform a
/// missing or broken capability answers with silence rather than an error, and
/// CoreSpeechKit has already demonstrated how that looks — an engine that
/// initialises, a `speak` that returns true, and nothing audible in any
/// language. "The model loaded" and "a voice came out" are different claims and
/// only the second one is worth anything.
///
/// Playback goes through the [AudioBackend], not through a second player here:
/// that path was fixed and verified on device (fd source, state-machine driven),
/// and sherpa's job ends at producing a file.
Future<SherpaProbeResult> probeSherpaTts({
  required AudioBackend speaker,
  String phrase = 'Merhaba',
}) async {
  if (kIsWeb || !isHarmonyOsTarget) {
    return const SherpaProbeFailed('platform', 'not the companion build');
  }
  const channel = MethodChannel('me.dsdogs.turna/sherpa-tts');
  try {
    final init = await channel
        .invokeMapMethod<String, Object?>('init')
        .timeout(const Duration(seconds: 120),
            onTimeout: () => throw TimeoutException(
                  'sherpa init did not answer within 120s '
                  '(the first run copies ~35 MB out of the hap)',
                ));
    if (init == null || init['ready'] != true) {
      return SherpaProbeFailed('init', 'plugin reported not ready: $init');
    }

    final spoken = await channel
        .invokeMapMethod<String, Object?>('speak', <String, Object?>{
      'text': phrase,
      'speed': 1.0,
    }).timeout(const Duration(seconds: 60),
            onTimeout: () => throw TimeoutException(
                  'sherpa speak did not answer within 60s',
                ));
    final path = spoken?['path'] as String?;
    if (path == null || path.isEmpty) {
      return SherpaProbeFailed('speak', 'no wav produced: $spoken');
    }

    await speaker.playFile(path);
    final result = SherpaProbeOk(
      samples: (spoken?['sampleRate'] == null ? 0 : 1),
      synthesisMs: spoken?['ms'] as int? ?? 0,
      sampleRate: spoken?['sampleRate'] as int? ?? 0,
    );
    logger
        .d('Sherpa probe ok: ${result.synthesisMs}ms @${result.sampleRate}Hz');
    await _echo(
        'sherpa probe ok: ${result.synthesisMs}ms @${result.sampleRate}Hz $path');
    return result;
  } catch (e) {
    logger.w('Sherpa probe failed: $e');
    await _echo('sherpa probe FAILED: $e');
    return SherpaProbeFailed('exception', '$e');
  }
}

/// Mirrors the outcome into the platform log.
///
/// The Dart logger does not reach hilog on this embedding, and the app-domain
/// buffer has been observed to rotate, so a probe outcome that is only recorded
/// in Dart is not evidence — it is a line that happens to exist.
Future<void> _echo(String message) async {
  const audioChannel = MethodChannel('me.dsdogs.turna/audio');
  try {
    await audioChannel.invokeMethod<void>('reportDiagnostic', <String, dynamic>{
      'message': message,
    }).timeout(const Duration(seconds: 3));
  } catch (e) {
    // Best-effort: the echo is a diagnostic aid, and failing to deliver it must
    // not change the probe's own result.
  }
}
