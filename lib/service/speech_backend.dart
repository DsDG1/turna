// Platform text-to-speech backend.
//
// `flutter_tts` has no OpenHarmony implementation, and its community fork is
// unusable here: it names `TargetPlatform.ohos` in its own Dart source and adds
// public API upstream lacks, neither of which can be neutralised under a global,
// platform-blind `dependency_overrides` (ADR 0047 §7.3). The companion build
// therefore speaks through `TtsPlugin.ets` (CoreSpeechKit) over a
// MethodChannel, while Android / iOS keep using `flutter_tts` unchanged.
//
// The two engines do not agree on what a "rate" is, so the rate travels in
// `flutter_tts` units — where 0.5 is the platform default, per that plugin's own
// documentation — and each backend converts on its own side. The conversion is a
// pure function so it can be tested without a device; what the converted number
// actually sounds like cannot, which is why the Android mapping is left exactly
// as the plugin defines it and only the new one is stated as a guess.

// Package imports:
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';

// Project imports:
import 'package:turna/core/logger.dart';
import 'package:turna/core/ohos_target.dart';
import 'package:turna/service/audio_backend.dart';

/// Speaks text with the device's own voice.
abstract class SpeechBackend {
  /// Ensures an engine exists. Safe to call on every utterance.
  ///
  /// [language] is a hint only: a device without that voice must still end up
  /// with a working engine, otherwise nothing can be spoken at all.
  Future<void> init({String? language});

  /// Language tags the device can actually speak, as reported by the platform.
  ///
  /// Empty when the platform cannot answer, which callers must treat as
  /// "unknown" rather than "nothing available".
  Future<List<String>> availableLanguages();

  /// Selects the voice locale, reporting whether the platform accepted it.
  Future<bool> bindLanguage(String language);

  /// Sets the speech rate on the `flutter_tts` scale, where **0.5 is normal**.
  Future<void> setRate(double rate);

  /// Speaks [text] with the bound locale and rate.
  ///
  /// Returns false when the platform refused the request. It cannot report a
  /// later playback failure: the engine is asynchronous on both platforms, so
  /// "accepted" is the strongest answer available here.
  Future<bool> speak(String text);

  /// Stops any in-flight utterance. Best-effort by contract.
  Future<void> stop();
}

/// Android / iOS: `flutter_tts`, with the same calls the app always made.
class FlutterTtsSpeechBackend implements SpeechBackend {
  FlutterTtsSpeechBackend(this._tts);

  final FlutterTts _tts;

  @override
  Future<void> init({String? language}) async {
    // Nothing to do: `flutter_tts` has no explicit init, and the engine is
    // selected by `TtsAvailabilityChecker` through `setEngine`.
  }

  @override
  Future<List<String>> availableLanguages() async {
    // The plugin exposes no "list every voice" call, only a per-tag probe.
    // Returning empty keeps callers on their existing probe path rather than
    // pretending the answer exists.
    return const <String>[];
  }

  @override
  Future<bool> bindLanguage(String language) async {
    final result = await _tts.setLanguage(language);
    return _isTruthy(result);
  }

  @override
  Future<void> setRate(double rate) async {
    await _tts.setSpeechRate(rate);
  }

  @override
  Future<bool> speak(String text) async {
    final result = await _tts.speak(text);
    return result is bool
        ? result
        : result is num
            ? result != 0
            : true;
  }

  @override
  Future<void> stop() async {
    await _tts.stop();
  }

  static bool _isTruthy(Object? value) {
    if (value == null) return true; // some platforms return null on success
    if (value is bool) return value;
    if (value is num) return value != 0;
    return true;
  }
}

/// The OpenHarmony companion build: CoreSpeechKit behind `TtsPlugin.ets`.
class OhosSpeechBackend implements SpeechBackend {
  OhosSpeechBackend({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const String _channelName = 'me.dsdogs.turna/tts';

  final MethodChannel _channel;

  String _language = '';
  double _rate = 0.5;
  List<String>? _voiceCache;
  List<String>? _supportedCache;

  @override
  Future<void> init({String? language}) async {
    final requested = language ?? _language;
    if (_language.isNotEmpty) return;
    final reply = await _channel.invokeMapMethod<String, Object?>(
      'init',
      <String, dynamic>{'language': requested},
    );
    // The native side may have had to walk down to a different voice: the
    // device can refuse the requested language outright (Mate 90 Pro Max has no
    // Turkish voice) and no API lists valid voice ids without an engine, so the
    // engine it settled on is the one worth speaking with — and worth naming in
    // a log rather than assuming.
    _language = reply?['language'] as String? ?? requested;
    logger.d(
      'OhosSpeechBackend: engine ready (requested=$requested, '
      'language=$_language, person=${reply?['person']}, '
      'degraded=${reply?['degraded'] ?? false})',
    );
  }

  @override
  Future<List<String>> availableLanguages() async {
    final cached = _voiceCache;
    if (cached != null) return cached;
    await _loadVoices();
    return _voiceCache ?? const <String>[];
  }

  /// Languages the device could speak **if asked to fetch the voice**, whether
  /// or not that voice is on the device now.
  ///
  /// Empty on platforms that cannot answer the question. This is what tells
  /// "no Turkish voice exists" apart from "Turkish voice is downloadable" — the
  /// two need different answers from the user, and a single empty list makes
  /// both look like a broken feature.
  Future<List<String>> supportedLanguages() async {
    await _loadVoices();
    return _supportedCache ?? const <String>[];
  }

  Future<void> _loadVoices() async {
    if (_voiceCache != null) return;
    final raw = await _channel.invokeMapMethod<String, Object?>('voices');
    _voiceCache = _languagesOf(raw?['installed']);
    final supported = _languagesOf(raw?['supported']);
    // Whatever the device can already speak is by definition supported, so the
    // installed set is merged in: a platform that only answers the installed
    // query must not look like it supports nothing.
    _supportedCache = <String>{...supported, ..._voiceCache!}.toList();
    logger.d(
      'OhosSpeechBackend: voices installed=$_voiceCache '
      'supported=$_supportedCache',
    );
  }

  static List<String> _languagesOf(Object? raw) {
    final out = <String>[];
    for (final entry in raw as List<Object?>? ?? const <Object?>[]) {
      if (entry is Map && entry['language'] is String) {
        final language = entry['language'] as String;
        if (!out.contains(language)) out.add(language);
      }
    }
    return out;
  }

  @override
  Future<bool> bindLanguage(String language) async {
    // The engine is created once and takes its locale per utterance, so there
    // is no separate "set language" step to fail. A voice the device does not
    // have shows up as silence, which `TtsAvailabilityChecker` is expected to
    // have already ruled out via [availableLanguages].
    _language = language;
    return true;
  }

  @override
  Future<void> setRate(double rate) async {
    _rate = rate;
  }

  @override
  Future<bool> speak(String text) async {
    final spoken = await _channel.invokeMethod<bool>('speak', <String, dynamic>{
      'text': text,
      'language': _language,
      'rate': mapFlutterTtsRateToPercent(_rate),
    });
    return spoken ?? false;
  }

  @override
  Future<void> stop() async {
    await _channel.invokeMethod<void>('stop');
  }

  /// Maps a `flutter_tts` rate (0.5 = normal) onto CoreSpeechKit's 0–100
  /// percentage, keeping 50 at the app's default speed.
  ///
  /// The upper half of the range is what the app's own slider uses (its 2.0
  /// maximum arrives here as 1.0), so the mapping spans 25–100 rather than
  /// stopping at the engine's own default — otherwise everything above 1.0x
  /// would sound identical.
  ///
  /// Whether 50 is *exactly* the device's natural rate is not documented; this
  /// mapping is monotonic and clamped, and its audible result has to be
  /// confirmed on a device.
  @visibleForTesting
  static int mapFlutterTtsRateToPercent(double rate) {
    final percent = 50 + (rate - 0.5) * 100;
    return percent.clamp(0, 100).round();
  }
}

/// Offline Turkish TTS via sherpa-onnx, for the OpenHarmony companion build.
///
/// Chosen over CoreSpeechKit because CoreSpeechKit is *silent* on the device this
/// build is verified against: its `listVoices` reports `zh_CN person=13
/// status=INSTALLED`, the engine initialises, `speak` returns true, `onStart`
/// fires, `onComplete` fires about 44 ms later — twice — and no `onError` ever
/// arrives. Nothing is audible in any language. A device that claims an
/// installed voice and then says nothing is not a fallback worth keeping behind
/// a live feature, so this is the primary path rather than the secondary one.
///
/// The model is Turkish-only, which [availableLanguages] reports honestly rather
/// than padding: pretending an English voice exists is what produced the
/// "English is unsupported on this device" conclusion that turned out to be a
/// broken voice id instead.
class SherpaSpeechBackend implements SpeechBackend {
  SherpaSpeechBackend({required AudioBackend speaker}) : _speaker = speaker;

  static const MethodChannel _channel =
      MethodChannel('me.dsdogs.turna/sherpa-tts');

  /// The only language the bundled model speaks.
  static const String modelLanguage = 'tr';

  final AudioBackend _speaker;
  bool _ready = false;
  double _speed = 1.0;

  @override
  Future<void> init({String? language}) async {
    if (_ready) return;
    // Generous: the first call also stages ~35 MB out of the hap, which is a
    // copy of 358 files rather than a model load.
    final reply = await _channel
        .invokeMapMethod<String, Object?>('init')
        .timeout(const Duration(seconds: 120));
    _ready = reply != null && reply['ready'] == true;
    if (!_ready) {
      throw StateError('sherpa model unavailable: $reply');
    }
    logger.d('Sherpa speech backend ready (${reply?['sampleRate']}Hz)');
  }

  @override
  Future<List<String>> availableLanguages() async => <String>[modelLanguage];

  @override
  Future<bool> bindLanguage(String language) async {
    // The engine holds one voice. Accepting any request would mean answering
    // "yes" for Turkish text read by a voice the caller never chose, so the one
    // real answer is given and anything else says no.
    return _normalize(language).startsWith(modelLanguage);
  }

  @override
  Future<void> setRate(double rate) async {
    // `rate` is a UI multiplier where 1.0 is normal; sherpa's `speed` is the same
    // shape, so the conversion is the identity rather than a second scale nobody
    // has heard.
    _speed = rate.clamp(0.5, 2.0);
  }

  @override
  Future<bool> speak(String text) async {
    if (!_ready) {
      await init();
    }
    final reply = await _channel
        .invokeMapMethod<String, Object?>('speak', <String, Object?>{
      'text': text,
      'speed': _speed,
    }).timeout(const Duration(seconds: 60));
    final path = reply?['path'] as String?;
    if (path == null || path.isEmpty) {
      logger.w('sherpa produced no audio for ${text.length} chars');
      return false;
    }
    // Played through the shared audio seam rather than a second player here: that
    // path was fixed and verified on device, and this backend's job ends at
    // having produced a file.
    await _speaker.playFile(path);
    return true;
  }

  @override
  Future<void> stop() async {
    try {
      await _speaker.stop();
    } catch (e) {
      logger.w('sherpa stop failed: $e');
    }
  }

  static String _normalize(String raw) =>
      raw.replaceAll('_', '-').toLowerCase();
}

/// The backend this build should use.
///
/// [speaker] is only needed on the companion build, where the offline engine
/// hands back a file rather than making sound itself.
SpeechBackend createSpeechBackend({
  required FlutterTts tts,
  AudioBackend? speaker,
}) {
  if (isHarmonyOsTarget) {
    if (speaker != null) return SherpaSpeechBackend(speaker: speaker);
    // No speaker to play through. Failing loudly beats silently reverting to an
    // engine that is known not to make a sound on this platform.
    throw StateError('the OHOS speech backend needs a speaker to play through');
  }
  return FlutterTtsSpeechBackend(tts);
}
