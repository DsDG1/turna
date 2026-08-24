import 'dart:io';

import 'package:turna/application/anki_official/engine/official_anki_native_availability.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';

enum AnkiEngineKind { legacy, official }

/// Production cutover gate. Default **true**: together with
/// [OfficialAnkiFeatureFlags.productionAndroid] this is the single product
/// mode — Android Official vs Anki unavailable. Builds that need to pause
/// new Official traffic may pass `--dart-define=TURNA_OFFICIAL_ANKI_CUTOVER=false`
/// (locked by `official_anki_p5d_routing_test.dart`).
class LegacyAnkiMigrationFlags {
  const LegacyAnkiMigrationFlags._();

  static const cutoverEnabled = bool.fromEnvironment(
    'TURNA_OFFICIAL_ANKI_CUTOVER',
    defaultValue: true,
  );
}

AnkiEngineKind? parseRecordedKind(String? raw) {
  if (raw == 'official') return AnkiEngineKind.official;
  if (raw == 'legacy') return AnkiEngineKind.legacy;
  return null;
}

const _p5cFixtureHashes = <String>{
  'bbe354db3925f4b4d7e8d66b0770e83f2ce38586e1071398e762d821636cad58', // 04-cloze / basic-cloze (anki21b stub)
  '65dfa64e305edaab6bae7690c66e54918a5d944dc702f2b6fe2821f27f170570', // 01-basic-unicode
  '1d2f1284644961ac713c1ebcd8225d464cc156339f42665a0b6bd3c65168cd84', // 02-basic-reversed
  '28d89bb7bf41df25513e148e96acbdac93bcc71fadcee8e552b57d4413394d02', // update1.apkg classic hello/world
};

/// Allowlist check for P5-C single-source fixture pilot.
/// Rejects user decks and any non-allowlist imports.
bool isFixturePilotSource({
  String? importId,
  String? sourceHash,
}) {
  if (importId != null && importId.startsWith('p5c-fixture-')) {
    return true;
  }
  if (sourceHash != null && _p5cFixtureHashes.contains(sourceHash)) {
    return true;
  }
  return false;
}

class AnkiSourceRoute {
  const AnkiSourceRoute({
    required this.sourceKey,
    required this.engine,
  });

  final String sourceKey;
  final AnkiEngineKind engine;
}

/// Resolves review/import ownership. Does not write.
/// Official only when cutover is on and the source is official-owned.
///
/// Doc 34: recorded Official owner never degrades to Legacy when the native
/// library is missing (fail-closed at the review gate instead). Unrecorded
/// Android sources assume Official only when the library is present; missing
/// library does not invent a Legacy owner for new traffic.
class AnkiSourceRouteResolver {
  const AnkiSourceRouteResolver();

  AnkiEngineKind resolve({
    required String sourceKey,
    AnkiEngineKind? recordedKind,
    bool officialCatalogHasSource = false,
    bool? cutoverEnabled,
    String? platform,
    bool? libraryAvailable,
  }) {
    if (sourceKey.isEmpty) return AnkiEngineKind.legacy;
    // Doc 34 W0-06: a persisted Official owner never degrades to Legacy when
    // cutover / capability flags are off. Review fails closed instead.
    if (recordedKind == AnkiEngineKind.official) {
      return AnkiEngineKind.official;
    }
    if (recordedKind == AnkiEngineKind.legacy) {
      return AnkiEngineKind.legacy;
    }
    if (officialCatalogHasSource) {
      return AnkiEngineKind.official;
    }
    final cutover =
        cutoverEnabled ?? LegacyAnkiMigrationFlags.cutoverEnabled;
    if (!cutover) return AnkiEngineKind.legacy;
    final plat =
        platform ?? OfficialAnkiCapabilityMatrix.current().platform;
    if (plat == 'android') {
      final libraryOk =
          libraryAvailable ?? OfficialAnkiNativeAvailability.current;
      // Missing native runtime: do not invent a Legacy owner for unrecorded
      // sources. Callers that need a binary kind for "no official route"
      // still see legacy here only as "not official"; new-import planners
      // fail-closed separately and never write Legacy.
      return libraryOk ? AnkiEngineKind.official : AnkiEngineKind.legacy;
    }
    // Non-Android: never invent a new Legacy writer. Only an already-known
    // Official catalog source stays Official (read/repair); everything else
    // is treated as non-official so product mode can mark Anki unavailable.
    return officialCatalogHasSource
        ? AnkiEngineKind.official
        : AnkiEngineKind.legacy;
  }

  AnkiSourceRoute routeFor({
    required String sourceKey,
    AnkiEngineKind? recordedKind,
    bool officialCatalogHasSource = false,
    bool? cutoverEnabled,
    String? platform,
    bool? libraryAvailable,
  }) {
    return AnkiSourceRoute(
      sourceKey: sourceKey,
      engine: resolve(
        sourceKey: sourceKey,
        recordedKind: recordedKind,
        officialCatalogHasSource: officialCatalogHasSource,
        cutoverEnabled: cutoverEnabled,
        platform: platform,
        libraryAvailable: libraryAvailable,
      ),
    );
  }
}

class OfficialAnkiPlatformCapability {
  const OfficialAnkiPlatformCapability({
    required this.platform,
    required this.officialCore,
    required this.officialReviewer,
    required this.officialScheduler,
    required this.legacyFallbackRequired,
  });

  final String platform;
  final bool officialCore;
  final bool officialReviewer;
  final bool officialScheduler;
  final bool legacyFallbackRequired;
}

class OfficialAnkiCapabilityMatrix {
  const OfficialAnkiCapabilityMatrix._();

  static OfficialAnkiPlatformCapability current([
    OfficialAnkiFeatureFlags? flags,
  ]) {
    return forPlatform(_hostPlatform(), flags);
  }

  static OfficialAnkiPlatformCapability forPlatform(
    String platform, [
    OfficialAnkiFeatureFlags? flags,
  ]) {
    final resolved = flags ?? OfficialAnkiFeatureFlags.current;
    switch (platform) {
      case 'android':
        return OfficialAnkiPlatformCapability(
          platform: platform,
          officialCore: true,
          officialReviewer: resolved.allowsOfficialRenderer,
          officialScheduler: resolved.allowsOfficialScheduler,
          // Doc 34: never fall back to Legacy writers for new imports.
          legacyFallbackRequired: false,
        );
      case 'linux':
      case 'macos':
        // Host FFI may exist for tests; product Anki remains unavailable and
        // must not open a Legacy writer (doc 34 platform matrix).
        return OfficialAnkiPlatformCapability(
          platform: platform,
          officialCore: true,
          officialReviewer: false,
          officialScheduler: false,
          legacyFallbackRequired: false,
        );
      case 'ios':
      case 'windows':
      default:
        // Unknown / unsupported platforms (including retired OHOS) never open
        // a Legacy writer. Product mode maps these to ankiUnavailable.
        return OfficialAnkiPlatformCapability(
          platform: platform,
          officialCore: false,
          officialReviewer: false,
          officialScheduler: false,
          legacyFallbackRequired: false,
        );
    }
  }

  /// Test seam: force the host platform reported by [_hostPlatform] so host
  /// tests can exercise the android-only production routing. Production code
  /// never sets this.
  static String? overrideHostPlatformForTests;

  static String _hostPlatform() {
    final overridden = overrideHostPlatformForTests;
    if (overridden != null) return overridden;
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    return 'unknown';
  }
}
