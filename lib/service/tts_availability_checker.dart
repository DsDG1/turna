// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:flutter_tts/flutter_tts.dart';
import 'package:injectable/injectable.dart';
import 'package:url_launcher/url_launcher.dart';

/// Inspects the device's local TTS capabilities and, when appropriate, selects
/// the Google TTS engine on Android.
///
/// Product priority: **Google TTS is the preferred system voice** for Swahili.
/// Piper is only an explicit offline choice / emergency fallback (see
/// [AudioController]), not a silent replacement when Google is missing.
///
/// This class does not play audio; it answers availability questions and
/// configures the preferred engine.
@lazySingleton
class TtsAvailabilityChecker {
  final FlutterTts _tts;

  TtsAvailabilityChecker(this._tts);

  /// Android package / engine id for Google Text-to-speech.
  static const String googleEngineId = 'com.google.android.tts';

  /// Play Store page for Google Speech Recognition & Synthesis.
  static final Uri googleTtsPlayStoreUri = Uri.parse(
    'https://play.google.com/store/apps/details?id=$googleEngineId',
  );

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

  /// Engine package names currently reported by the platform (Android).
  Future<List<String>> listEngineNames() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const [];
    }
    try {
      final engines = await _tts.getEngines;
      if (engines is! List) return const [];
      return engines.map(_engineName).toList(growable: false);
    } catch (e, st) {
      debugPrint('TtsAvailabilityChecker: listEngineNames failed: $e\n$st');
      return const [];
    }
  }

  /// Whether Google TTS (`com.google.android.tts`) appears in the engine list.
  Future<bool> hasGoogleTtsEngine() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      // Non-Android: no separate Google engine package to select.
      return defaultTargetPlatform != TargetPlatform.android && !kIsWeb;
    }
    final names = await listEngineNames();
    return names.contains(googleEngineId);
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
        if (_isTruthy(available)) {
          debugPrint(
            'TtsAvailabilityChecker: resolved language "$candidate" for "$languageCode"',
          );
          return candidate;
        }
      }
      debugPrint(
        'TtsAvailabilityChecker: no available locale for "$languageCode" '
        '(candidates=${languageCandidates(languageCode)})',
      );
      return null;
    } catch (e, st) {
      debugPrint(
        'TtsAvailabilityChecker: failed to resolve language: $e\n$st',
      );
      return null;
    }
  }

  /// Returns `true` when *any* local TTS engine claims to support [languageCode].
  ///
  /// On Android we prefer the Google TTS engine **before** querying language
  /// availability, so a non-Google default engine without Swahili does not
  /// incorrectly report the system as unavailable when Google has the pack.
  ///
  /// Prefer [isPreferredSystemTtsAvailable] for product decisions about whether
  /// Google is ready for learning quality.
  Future<bool> isSystemTtsAvailable(String languageCode) async {
    if (kIsWeb) return false;

    try {
      final resolved = await resolveLanguageCode(languageCode);
      if (resolved == null) return false;

      if (defaultTargetPlatform == TargetPlatform.android) {
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

  /// Whether the **preferred** system voice for learning is available.
  ///
  /// - **Android:** Google TTS must be installed **and** report a usable
  ///   locale for [languageCode] after [configureSystemEngine].
  /// - **iOS / other:** same as [isSystemTtsAvailable] (system voices only).
  Future<bool> isPreferredSystemTtsAvailable(String languageCode) async {
    if (kIsWeb) return false;

    if (defaultTargetPlatform == TargetPlatform.android) {
      final hasGoogle = await hasGoogleTtsEngine();
      if (!hasGoogle) {
        debugPrint(
          'TtsAvailabilityChecker: preferred system TTS unavailable '
          '(Google TTS not installed)',
        );
        return false;
      }
    }

    final resolved = await resolveLanguageCode(languageCode);
    final ok = resolved != null;
    debugPrint(
      'TtsAvailabilityChecker: preferred system TTS '
      '${ok ? "available" : "unavailable"} (lang=$languageCode, resolved=$resolved)',
    );
    return ok;
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

      final engineNames = engines.map(_engineName).toList(growable: false);
      debugPrint('TtsAvailabilityChecker: engines=$engineNames');

      final hasGoogle = engineNames.contains(googleEngineId);

      if (hasGoogle) {
        await _tts.setEngine(googleEngineId);
        debugPrint('TtsAvailabilityChecker: selected Google TTS engine');
      } else {
        debugPrint(
          'TtsAvailabilityChecker: Google TTS not installed; using device default engine',
        );
      }
      _engineConfigured = true;
    } catch (e, st) {
      debugPrint('TtsAvailabilityChecker: failed to set engine: $e\n$st');
      // Still mark configured to avoid retry thrashing; caller can force.
      _engineConfigured = true;
    }
  }

  /// Opens the Play Store (or browser) page for Google TTS.
  ///
  /// Returns `false` if the URL cannot be launched (e.g. no browser / no GMS).
  Future<bool> openGoogleTtsInstallPage() async {
    try {
      if (await canLaunchUrl(googleTtsPlayStoreUri)) {
        return launchUrl(
          googleTtsPlayStoreUri,
          mode: LaunchMode.externalApplication,
        );
      }
      debugPrint(
        'TtsAvailabilityChecker: cannot launch Google TTS store URL',
      );
      return false;
    } catch (e, st) {
      debugPrint(
        'TtsAvailabilityChecker: openGoogleTtsInstallPage failed: $e\n$st',
      );
      return false;
    }
  }

  /// Opens the system Text-to-speech settings screen on Android.
  ///
  /// Uses [Intent] via platform channel so the user can pick Google as the
  /// preferred engine and download language data. No-op / returns false on
  /// non-Android.
  Future<bool> openSystemTtsSettings() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      // android.settings.TTS_SETTINGS is the public action for TTS prefs.
      const channel = MethodChannel('varnamala/tts_settings');
      final result = await channel.invokeMethod<bool>('openTtsSettings');
      return result == true;
    } on MissingPluginException {
      // Fallback when native side is not wired: try a common settings URI.
      debugPrint(
        'TtsAvailabilityChecker: openTtsSettings channel missing; '
        'user should open Settings → Accessibility → Text-to-speech',
      );
      return false;
    } catch (e, st) {
      debugPrint(
        'TtsAvailabilityChecker: openSystemTtsSettings failed: $e\n$st',
      );
      return false;
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
