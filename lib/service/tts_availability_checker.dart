// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:flutter_tts/flutter_tts.dart';
import 'package:injectable/injectable.dart';

/// Inspects the device's local TTS capabilities and, when appropriate, selects
/// the Google TTS engine on Android.
///
/// This class does not play audio; it only answers "can we use the system TTS
/// for [languageCode]?" and configures the preferred engine.
@lazySingleton
class TtsAvailabilityChecker {
  final FlutterTts _tts;

  TtsAvailabilityChecker(this._tts);

  static const String _googleEngine = 'com.google.android.tts';

  /// Whether [configureSystemEngine] has already completed successfully once
  /// in this process. Used by [AudioController] to avoid redundant setEngine
  /// calls while still allowing an explicit reconfigure from settings.
  bool _engineConfigured = false;

  bool get isEngineConfigured => _engineConfigured;

  /// Locale candidates for a base BCP-47 language code (e.g. `sw`).
  ///
  /// Android TTS engines sometimes only report region-specific tags as
  /// available (`sw-KE` / `sw_KE`) even when the base code `sw` is intended.
  static List<String> languageCandidates(String languageCode) {
    final base = languageCode.trim();
    if (base.isEmpty) return const [];

    final normalized = base.replaceAll('_', '-');
    final parts = normalized.split('-');
    final lang = parts.first.toLowerCase();

    final candidates = <String>{
      lang,
      if (parts.length > 1) '$lang-${parts[1].toUpperCase()}',
      if (parts.length > 1) '${lang}_${parts[1].toUpperCase()}',
    };

    // Swahili: common Google / OEM pack tags.
    if (lang == 'sw') {
      candidates.addAll(const [
        'sw-KE',
        'sw-TZ',
        'sw_KE',
        'sw_TZ',
      ]);
    }

    return candidates.toList(growable: false);
  }

  /// Returns the first locale the current (preferred) engine reports as
  /// available for [languageCode], or `null` if none work.
  ///
  /// On Android this prefers the Google TTS engine first via
  /// [configureSystemEngine].
  Future<String?> resolveLanguageCode(String languageCode) async {
    if (kIsWeb) return null;

    try {
      await configureSystemEngine();

      for (final candidate in languageCandidates(languageCode)) {
        final available = await _tts.isLanguageAvailable(candidate);
        if (_isTruthy(available)) return candidate;
      }
      return null;
    } catch (e, st) {
      debugPrint(
        'TtsAvailabilityChecker: failed to resolve language: $e\n$st',
      );
      return null;
    }
  }

  /// Returns `true` when the device has a local TTS engine that claims to
  /// support [languageCode].
  ///
  /// On Android we prefer the Google TTS engine **before** querying language
  /// availability, so a non-Google default engine without Swahili does not
  /// incorrectly report the system as unavailable.
  Future<bool> isSystemTtsAvailable(String languageCode) async {
    if (kIsWeb) return false;

    try {
      final resolved = await resolveLanguageCode(languageCode);
      if (resolved == null) return false;

      if (defaultTargetPlatform == TargetPlatform.android) {
        // Even if the language is reported available, make sure at least one
        // engine is installed. flutter_tts.getEngines returns a list of engine
        // names (String on newer versions, Map on older versions).
        final engines = await _tts.getEngines;
        if (engines is! List || engines.isEmpty) return false;
      }

      return true;
    } catch (e, st) {
      debugPrint(
        'TtsAvailabilityChecker: failed to query availability: $e\n$st',
      );
      return false;
    }
  }

  /// Explicitly selects the Google TTS engine on Android when it is installed.
  ///
  /// This is a no-op on other platforms because they do not expose engine
  /// selection through flutter_tts.
  ///
  /// Safe to call multiple times. Set [force] to re-run even if already
  /// configured in this process (e.g. user switched back to system TTS).
  Future<void> configureSystemEngine({bool force = false}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      _engineConfigured = true;
      return;
    }
    if (_engineConfigured && !force) return;

    try {
      final engines = await _tts.getEngines;
      if (engines is! List) {
        _engineConfigured = true;
        return;
      }

      final hasGoogle = engines.any(
        (e) => _engineName(e) == _googleEngine,
      );

      if (hasGoogle) {
        await _tts.setEngine(_googleEngine);
        debugPrint('TtsAvailabilityChecker: selected Google TTS engine');
      }
      _engineConfigured = true;
    } catch (e, st) {
      debugPrint('TtsAvailabilityChecker: failed to set engine: $e\n$st');
      // Still mark configured to avoid retry thrashing; caller can force.
      _engineConfigured = true;
    }
  }

  /// Normalises an engine entry from [FlutterTts.getEngines].
  ///
  /// Newer versions return `List<String>`, older versions return
  /// `List<Map<String, String>>`. Both shapes are handled defensively.
  static String _engineName(dynamic engine) {
    if (engine is String) return engine;
    if (engine is Map) return (engine['name'] ?? engine.toString()).toString();
    return engine.toString();
  }

  /// Returns `true` for bool `true` or integer `1`.
  static bool _isTruthy(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;
    if (value is num) return value == 1;
    return false;
  }
}
