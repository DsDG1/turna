// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:flutter_tts/flutter_tts.dart';
import 'package:injectable/injectable.dart';
import 'package:url_launcher/url_launcher.dart';

/// Snapshot of the device's TTS capabilities for UI / debugging.
class TtsDiagnostics {
  const TtsDiagnostics({
    required this.engines,
    required this.hasGoogleEngine,
    required this.resolvedLocale,
    required this.localeInstalled,
    required this.preferredAvailable,
  });

  final List<String> engines;
  final bool hasGoogleEngine;
  final String? resolvedLocale;

  /// On Android: whether the resolved locale's voice data is installed.
  /// On other platforms: same as "available" when [resolvedLocale] is non-null.
  final bool localeInstalled;
  final bool preferredAvailable;

  /// Coarse status for settings / splash copy.
  TtsPreferredStatus get preferredStatus {
    if (!hasGoogleEngine &&
        defaultTargetPlatform == TargetPlatform.android &&
        !kIsWeb) {
      return TtsPreferredStatus.googleMissing;
    }
    if (resolvedLocale == null) {
      return hasGoogleEngine
          ? TtsPreferredStatus.turkishVoiceMissing
          : TtsPreferredStatus.googleMissing;
    }
    if (!localeInstalled) {
      return TtsPreferredStatus.turkishVoiceMissing;
    }
    return TtsPreferredStatus.ready;
  }
}

/// Product-facing status of the preferred system voice (Google + Turkish).
enum TtsPreferredStatus {
  /// Google engine selected and a Turkish locale is usable.
  ready,

  /// Google TTS package not visible / not installed (Android).
  googleMissing,

  /// Engine present but Turkish voice data not installed or locale unsupported.
  turkishVoiceMissing,
}

/// Inspects the device's local TTS capabilities and, when appropriate, selects
/// the Google TTS engine on Android.
///
/// Product priority: **Google TTS is the preferred system voice** for Turkish.
/// There is no bundled offline fallback in this build — if the system voice
/// is unavailable, the audio controller reports an error to the UI.
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

  /// In-flight [configureSystemEngine] future. Concurrent callers await this
  /// instead of issuing a second [FlutterTts.setEngine], which races the
  /// flutter_tts Android plugin and crashes with "Reply already submitted".
  Future<void>? _configureInFlight;

  bool get isEngineConfigured => _engineConfigured;

  /// Locale candidates for a base BCP-47 language code (e.g. `tr`).
  ///
  /// Android TTS engines sometimes only report region-specific tags as
  /// available (`tr-TR` / `tr_TR`) even when the base code `tr` is intended.
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

    // Turkish: common Google / OEM pack tags.
    if (lang == 'tr') {
      candidates.addAll(const [
        'tr-TR',
        'tr_TR',
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
  /// [configureSystemEngine]. When possible, prefers a locale whose voice
  /// **data is installed** (not merely advertised as available).
  Future<String?> resolveLanguageCode(String languageCode) async {
    if (kIsWeb) return null;

    try {
      await configureSystemEngine();

      final candidates = languageCandidates(languageCode);
      String? firstAvailable;

      for (final candidate in candidates) {
        final available = await _tts.isLanguageAvailable(candidate);
        if (!_isTruthy(available)) continue;

        firstAvailable ??= candidate;

        // Prefer installed voice data when the platform supports the check.
        if (defaultTargetPlatform == TargetPlatform.android) {
          final installed = await _isLanguageInstalledSafe(candidate);
          if (installed == true) {
            debugPrint(
              'TtsAvailabilityChecker: resolved installed language '
              '"$candidate" for "$languageCode"',
            );
            return candidate;
          }
          if (installed == false) {
            debugPrint(
              'TtsAvailabilityChecker: "$candidate" available but not installed',
            );
            continue;
          }
          // installed == null → API unsupported / failed; fall through.
        }

        debugPrint(
          'TtsAvailabilityChecker: resolved language "$candidate" for "$languageCode"',
        );
        return candidate;
      }

      // No installed pack found: if something was merely available, still
      // return it so callers can attempt speak (network voice / OEM quirks).
      if (firstAvailable != null) {
        debugPrint(
          'TtsAvailabilityChecker: using available-but-maybe-uninstalled '
          'locale "$firstAvailable" for "$languageCode"',
        );
        return firstAvailable;
      }

      debugPrint(
        'TtsAvailabilityChecker: no available locale for "$languageCode" '
        '(candidates=$candidates)',
      );
      return null;
    } catch (e, st) {
      debugPrint(
        'TtsAvailabilityChecker: failed to resolve language: $e\n$st',
      );
      return null;
    }
  }

  /// True when the resolved locale has offline voice data installed.
  ///
  /// On non-Android platforms, returns `true` if any locale resolved.
  Future<bool> isLanguageDataInstalled(String languageCode) async {
    if (kIsWeb) return false;

    final resolved = await resolveLanguageCode(languageCode);
    if (resolved == null) return false;

    if (defaultTargetPlatform != TargetPlatform.android) {
      return true;
    }

    final installed = await _isLanguageInstalledSafe(resolved);
    // If the install check is unavailable, treat "available" as good enough.
    return installed ?? true;
  }

  /// Returns `true` when *any* local TTS engine claims to support [languageCode].
  ///
  /// On Android we prefer the Google TTS engine **before** querying language
  /// availability, so a non-Google default engine without Turkish does not
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
  ///   locale for [languageCode] after [configureSystemEngine], with voice
  ///   data installed when the platform can report that.
  /// - **iOS / other:** same as [isSystemTtsAvailable] (system voices only).
  Future<bool> isPreferredSystemTtsAvailable(String languageCode) async {
    if (kIsWeb) return false;

    if (defaultTargetPlatform == TargetPlatform.ohos) {
      return false;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      final hasGoogle = await hasGoogleTtsEngine();
      if (!hasGoogle) {
        debugPrint(
          'TtsAvailabilityChecker: preferred system TTS unavailable '
          '(Google TTS not installed or not visible — check AndroidManifest '
          '<queries> for TTS_SERVICE)',
        );
        return false;
      }
    }

    final resolved = await resolveLanguageCode(languageCode);
    if (resolved == null) {
      debugPrint(
        'TtsAvailabilityChecker: preferred system TTS unavailable '
        '(no locale for $languageCode)',
      );
      return false;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      final installed = await _isLanguageInstalledSafe(resolved);
      if (installed == false) {
        debugPrint(
          'TtsAvailabilityChecker: preferred system TTS unavailable '
          '(locale $resolved not installed — download Turkish voice data)',
        );
        return false;
      }
    }

    debugPrint(
      'TtsAvailabilityChecker: preferred system TTS available '
      '(lang=$languageCode, resolved=$resolved)',
    );
    return true;
  }

  /// Collects engine / locale status for settings UI and troubleshooting.
  Future<TtsDiagnostics> diagnose(String languageCode) async {
    final engines = await listEngineNames();
    final hasGoogle = await hasGoogleTtsEngine();
    final resolved = await resolveLanguageCode(languageCode);
    var installed = false;
    if (resolved != null) {
      if (defaultTargetPlatform == TargetPlatform.android && !kIsWeb) {
        installed = await _isLanguageInstalledSafe(resolved) ?? true;
      } else {
        installed = true;
      }
    }
    final preferred = await isPreferredSystemTtsAvailable(languageCode);
    return TtsDiagnostics(
      engines: engines,
      hasGoogleEngine: hasGoogle,
      resolvedLocale: resolved,
      localeInstalled: installed,
      preferredAvailable: preferred,
    );
  }

  /// Explicitly selects the Google TTS engine on Android when it is installed.
  ///
  /// This is a no-op on other platforms because they do not expose engine
  /// selection through flutter_tts.
  ///
  /// Safe to call multiple times and **safe under concurrent callers**: only
  /// one [FlutterTts.setEngine] runs at a time. Concurrent [setEngine] races
  /// crash flutter_tts on Android with `IllegalStateException: Reply already
  /// submitted`. Set [force] to re-run after a prior successful configure
  /// (e.g. user switched back to system TTS).
  Future<void> configureSystemEngine({bool force = false}) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      _engineConfigured = true;
      return;
    }

    // Loop so force-reconfigure after joining an in-flight run is safe, and so
    // we never issue overlapping FlutterTts.setEngine calls.
    while (true) {
      if (_engineConfigured && !force) return;

      final inFlight = _configureInFlight;
      if (inFlight != null) {
        await inFlight;
        // Non-force callers are done once any successful configure finished.
        if (!force) return;
        // force: another waiter may still hold the lock — loop and recheck.
        continue;
      }

      // Claim the lock synchronously before any await in the body.
      final done = Completer<void>();
      _configureInFlight = done.future;
      try {
        // Another completer may have finished between our null-check and claim
        // only if we yielded — we did not. Still re-check configured for force.
        if (_engineConfigured && !force) return;
        await _configureSystemEngineBody();
      } finally {
        if (!done.isCompleted) done.complete();
        if (identical(_configureInFlight, done.future)) {
          _configureInFlight = null;
        }
      }
      return;
    }
  }

  Future<void> _configureSystemEngineBody() async {
    try {
      final engines = await _tts.getEngines;
      if (engines is! List) {
        debugPrint(
          'TtsAvailabilityChecker: getEngines returned non-list ($engines). '
          'If Google TTS is installed, ensure AndroidManifest declares '
          '<queries> for android.intent.action.TTS_SERVICE.',
        );
        _engineConfigured = true;
        return;
      }

      final engineNames = engines.map(_engineName).toList(growable: false);
      debugPrint('TtsAvailabilityChecker: engines=$engineNames');

      if (engineNames.isEmpty) {
        debugPrint(
          'TtsAvailabilityChecker: empty engine list. On Android 11+ this '
          'often means missing <queries> for TTS_SERVICE in AndroidManifest.',
        );
      }

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
      const channel = MethodChannel('turna/tts_settings');
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

  /// [null] = check failed / unsupported; [true]/[false] = definitive.
  Future<bool?> _isLanguageInstalledSafe(String language) async {
    try {
      final result = await _tts.isLanguageInstalled(language);
      if (result is bool) return result;
      if (result is num) return result == 1;
      if (result is String) {
        final lower = result.toLowerCase();
        if (lower == 'true' || lower == '1') return true;
        if (lower == 'false' || lower == '0') return false;
      }
      return null;
    } catch (e) {
      debugPrint(
        'TtsAvailabilityChecker: isLanguageInstalled($language) failed: $e',
      );
      return null;
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
