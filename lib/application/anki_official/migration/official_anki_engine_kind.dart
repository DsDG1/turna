import 'dart:io';

import 'package:turna/application/anki_official/official_anki_feature_flags.dart';

enum AnkiEngineKind { legacy, official }

/// Hard stop for P5-C/D. This batch must not switch user sources.
class LegacyAnkiMigrationFlags {
  const LegacyAnkiMigrationFlags._();

  static const cutoverEnabled = false;
}

const _p5cFixtureHashes = <String>{
  'bbe354db3925f4b4d7e8d66b0770e83f2ce38586e1071398e762d821636cad58', // 04-cloze / basic-cloze
  '65dfa64e305edaab6bae7690c66e54918a5d944dc702f2b6fe2821f27f170570', // 01-basic-unicode
  '1d2f1284644961ac713c1ebcd8225d464cc156339f42665a0b6bd3c65168cd84', // 02-basic-reversed
};

/// Allowlist check for P5-C single-source fixture pilot.
/// Rejects user decks and any non-allowlist imports.
bool isFixturePilotSource({
  String? importId,
  String? sourceHash,
  String? displayName,
}) {
  if (importId != null && importId.startsWith('p5c-fixture-')) {
    return true;
  }
  if (displayName != null && displayName.contains('p5c-fixture')) {
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

/// Resolves review/import ownership. Does not write. Cutover stays false.
class AnkiSourceRouteResolver {
  const AnkiSourceRouteResolver();

  AnkiEngineKind resolve({
    required String sourceKey,
    AnkiEngineKind? recordedKind,
    bool officialCatalogHasSource = false,
  }) {
    if (sourceKey.isEmpty) return AnkiEngineKind.legacy;
    if (!LegacyAnkiMigrationFlags.cutoverEnabled) {
      if (recordedKind != null) return recordedKind;
      return officialCatalogHasSource
          ? AnkiEngineKind.official
          : AnkiEngineKind.legacy;
    }
    if (recordedKind != null) return recordedKind;
    return officialCatalogHasSource
        ? AnkiEngineKind.official
        : AnkiEngineKind.legacy;
  }

  AnkiSourceRoute routeFor({
    required String sourceKey,
    AnkiEngineKind? recordedKind,
    bool officialCatalogHasSource = false,
  }) {
    return AnkiSourceRoute(
      sourceKey: sourceKey,
      engine: resolve(
        sourceKey: sourceKey,
        recordedKind: recordedKind,
        officialCatalogHasSource: officialCatalogHasSource,
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
          legacyFallbackRequired: !resolved.allowsOfficialScheduler,
        );
      case 'linux':
      case 'macos':
        return OfficialAnkiPlatformCapability(
          platform: platform,
          officialCore: true,
          officialReviewer: false,
          officialScheduler: resolved.allowsOfficialScheduler,
          legacyFallbackRequired: true,
        );
      case 'ios':
      case 'ohos':
      case 'windows':
      default:
        return OfficialAnkiPlatformCapability(
          platform: platform,
          officialCore: false,
          officialReviewer: false,
          officialScheduler: false,
          legacyFallbackRequired: true,
        );
    }
  }

  static String _hostPlatform() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isLinux) return 'linux';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    return 'unknown';
  }
}
