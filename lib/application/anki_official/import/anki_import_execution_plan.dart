import 'package:turna/application/anki_official/engine/official_anki_native_availability.dart';
import 'package:turna/application/anki_official/import/anki_import_facade.dart';
import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';

/// Product-level Anki mode for the running build (doc 34 W0).
///
/// Legacy is not a product mode for new imports — it remains a migration
/// read path only. Production is either Official-on-Android or Anki
/// unavailable.
enum AnkiProductMode {
  /// Android production: new imports and formal review are Official-owned.
  officialAndroid,

  /// Anki new-import / formal review are unavailable (non-Android, EOL, or
  /// deliberately paused). Must not create Legacy Anki writers.
  ankiUnavailable,
}

/// One atomic import execution outcome. Computed once per pick/commit and
/// threaded through parse/preview/saga/projection/SRS/identity/summary so
/// those stages cannot each re-read flags and disagree.
enum AnkiImportExecutionKind {
  /// Official Collection is the only writer; zero Legacy NoteStore / Turna
  /// Anki SRS rows.
  officialFirst,

  /// Platform or product mode does not support Anki import.
  unsupported,

  /// Official was required but native/runtime/capability is missing. No new
  /// source may be created; never degrade to Legacy.
  failClosed,

  /// Explicit Legacy-only path for tests / short-term haemostasis builds.
  /// Production routers must not select this unless [allowLegacyOnly] is set.
  legacyOnly,
}

/// Persisted owner that the execution plan will record for a successful
/// import. `null` means no source is created (unsupported / fail-closed).
enum AnkiImportOwner {
  official,
  legacy,
}

class AnkiImportExecutionPlan {
  const AnkiImportExecutionPlan({
    required this.productMode,
    required this.kind,
    required this.owner,
    required this.platform,
    required this.writesLegacyNoteStore,
    required this.writesTurnaAnkiSrs,
    required this.writesOfficialCollection,
    required this.reason,
  });

  final AnkiProductMode productMode;
  final AnkiImportExecutionKind kind;

  /// Owner that must be persisted on success. Null when [kind] creates no
  /// source (`unsupported` / `failClosed`).
  final AnkiImportOwner? owner;

  final String platform;
  final bool writesLegacyNoteStore;
  final bool writesTurnaAnkiSrs;
  final bool writesOfficialCollection;
  final String reason;

  bool get createsSource => owner != null;

  bool get isOfficialFirst => kind == AnkiImportExecutionKind.officialFirst;

  bool get isFailClosed => kind == AnkiImportExecutionKind.failClosed;

  bool get isUnsupported => kind == AnkiImportExecutionKind.unsupported;

  bool get isLegacyOnly => kind == AnkiImportExecutionKind.legacyOnly;

  /// Maps onto the older facade enum for call sites that have not migrated.
  AnkiImportDecision get facadeDecision {
    switch (kind) {
      case AnkiImportExecutionKind.officialFirst:
        return AnkiImportDecision.official;
      case AnkiImportExecutionKind.legacyOnly:
        return AnkiImportDecision.legacy;
      case AnkiImportExecutionKind.unsupported:
      case AnkiImportExecutionKind.failClosed:
        return AnkiImportDecision.failClosed;
    }
  }

  /// True when identity/backend rows must be recorded as Official.
  bool get persistedOwnerIsOfficial => owner == AnkiImportOwner.official;
}

/// Single resolver for product mode + import execution plan (doc 34 W0).
///
/// Invariants:
/// - `actual writer == persisted owner == review route owner` for any plan
///   that creates a source.
/// - Missing/mismatched native runtime on Android never selects Legacy for a
///   new import.
/// - Unsupported platforms never select a Legacy writer.
class AnkiImportExecutionPlanner {
  const AnkiImportExecutionPlanner();

  AnkiProductMode productModeFor({
    required String platform,
    bool? cutoverEnabled,
  }) {
    final cutover = cutoverEnabled ?? LegacyAnkiMigrationFlags.cutoverEnabled;
    if (!cutover) return AnkiProductMode.ankiUnavailable;
    if (platform == 'android') return AnkiProductMode.officialAndroid;
    return AnkiProductMode.ankiUnavailable;
  }

  /// Resolve the atomic plan for one import attempt.
  ///
  /// [allowLegacyOnly] is a test / explicit haemostasis escape hatch. It is
  /// never implied by production defaults.
  AnkiImportExecutionPlan resolve({
    required OfficialAnkiFeatureFlags flags,
    String? platform,
    bool? cutoverEnabled,
    bool? libraryAvailable,
    bool isSample = false,
    String filePath = '',
    bool allowLegacyOnly = false,
    String? extensionOverride,
  }) {
    final plat =
        platform ?? OfficialAnkiCapabilityMatrix.current().platform;
    final cutover = cutoverEnabled ?? LegacyAnkiMigrationFlags.cutoverEnabled;
    final mode = productModeFor(platform: plat, cutoverEnabled: cutover);
    final libraryOk = libraryAvailable ??
        // Lazy import to keep this file free of dart:io probe side effects in
        // pure unit tests that pass [libraryAvailable] explicitly.
        _libraryAvailable();
    final ext = (extensionOverride ?? _extensionOf(filePath)).toLowerCase();

    if (mode == AnkiProductMode.ankiUnavailable) {
      if (allowLegacyOnly && plat != 'android') {
        // Explicit test haemostasis only — still never the production default.
        return _legacyOnly(
          mode: mode,
          platform: plat,
          reason: 'explicit_legacy_only_haemostasis',
        );
      }
      return AnkiImportExecutionPlan(
        productMode: mode,
        kind: AnkiImportExecutionKind.unsupported,
        owner: null,
        platform: plat,
        writesLegacyNoteStore: false,
        writesTurnaAnkiSrs: false,
        writesOfficialCollection: false,
        reason: cutover
            ? 'platform_anki_unavailable:$plat'
            : 'cutover_disabled_import_paused',
      );
    }

    // mode == officialAndroid
    if (!flags.allowsOfficialImport) {
      if (allowLegacyOnly) {
        return _legacyOnly(
          mode: mode,
          platform: plat,
          reason: 'explicit_legacy_only_flags_off',
        );
      }
      return AnkiImportExecutionPlan(
        productMode: mode,
        kind: AnkiImportExecutionKind.failClosed,
        owner: null,
        platform: plat,
        writesLegacyNoteStore: false,
        writesTurnaAnkiSrs: false,
        writesOfficialCollection: false,
        reason: 'official_flags_incomplete',
      );
    }

    if (!libraryOk) {
      return AnkiImportExecutionPlan(
        productMode: mode,
        kind: AnkiImportExecutionKind.failClosed,
        owner: null,
        platform: plat,
        writesLegacyNoteStore: false,
        writesTurnaAnkiSrs: false,
        writesOfficialCollection: false,
        reason: 'native_library_missing_or_abi_mismatch',
      );
    }

    if (isSample) {
      // In-memory sample is not an Official package; production must not
      // pretend it is Official-owned. Tests may opt into legacyOnly.
      if (allowLegacyOnly) {
        return _legacyOnly(
          mode: mode,
          platform: plat,
          reason: 'sample_deck_legacy_only',
        );
      }
      return AnkiImportExecutionPlan(
        productMode: mode,
        kind: AnkiImportExecutionKind.failClosed,
        owner: null,
        platform: plat,
        writesLegacyNoteStore: false,
        writesTurnaAnkiSrs: false,
        writesOfficialCollection: false,
        reason: 'sample_deck_not_official_package',
      );
    }

    if (ext == '.colpkg') {
      return AnkiImportExecutionPlan(
        productMode: mode,
        kind: AnkiImportExecutionKind.unsupported,
        owner: null,
        platform: plat,
        writesLegacyNoteStore: false,
        writesTurnaAnkiSrs: false,
        writesOfficialCollection: false,
        reason: 'colpkg_not_supported_until_official_backend',
      );
    }

    if (ext.isNotEmpty && ext != '.apkg') {
      return AnkiImportExecutionPlan(
        productMode: mode,
        kind: AnkiImportExecutionKind.unsupported,
        owner: null,
        platform: plat,
        writesLegacyNoteStore: false,
        writesTurnaAnkiSrs: false,
        writesOfficialCollection: false,
        reason: 'unsupported_extension:$ext',
      );
    }

    // Official-first is the only production writer on Android.
    if (!flags.allowsOfficialFirstImport && allowLegacyOnly) {
      return _legacyOnly(
        mode: mode,
        platform: plat,
        reason: 'explicit_legacy_only_official_first_flag_off',
      );
    }

    if (!flags.allowsOfficialFirstImport) {
      // Production must not fall into the old mixed half-state (Legacy
      // NoteStore + Official identity / no Collection). Fail closed instead.
      return AnkiImportExecutionPlan(
        productMode: mode,
        kind: AnkiImportExecutionKind.failClosed,
        owner: null,
        platform: plat,
        writesLegacyNoteStore: false,
        writesTurnaAnkiSrs: false,
        writesOfficialCollection: false,
        reason: 'official_first_required_but_flag_off',
      );
    }

    return AnkiImportExecutionPlan(
      productMode: mode,
      kind: AnkiImportExecutionKind.officialFirst,
      owner: AnkiImportOwner.official,
      platform: plat,
      writesLegacyNoteStore: false,
      writesTurnaAnkiSrs: false,
      writesOfficialCollection: true,
      reason: 'android_official_first',
    );
  }

  static AnkiImportExecutionPlan _legacyOnly({
    required AnkiProductMode mode,
    required String platform,
    required String reason,
  }) {
    return AnkiImportExecutionPlan(
      productMode: mode,
      kind: AnkiImportExecutionKind.legacyOnly,
      owner: AnkiImportOwner.legacy,
      platform: platform,
      writesLegacyNoteStore: true,
      writesTurnaAnkiSrs: true,
      writesOfficialCollection: false,
      reason: reason,
    );
  }

  static String _extensionOf(String path) {
    final name = path.trim();
    final dot = name.lastIndexOf('.');
    if (dot < 0 || dot == name.length - 1) return '';
    return name.substring(dot).toLowerCase();
  }

  static bool _libraryAvailable() => OfficialAnkiNativeAvailability.current;
}
