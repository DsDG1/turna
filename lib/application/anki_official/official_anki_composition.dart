import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:turna/application/anki_official/contract/official_anki_contract.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/engine/official_anki_in_process.dart';
import 'package:turna/application/anki_official/engine/official_anki_native_transport.dart';
import 'package:turna/application/anki_official/engine/official_anki_session.dart';
import 'package:turna/application/anki_official/engine/official_anki_session_engine.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/projection/official_anki_course_entry.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/core/ohos_target.dart';

class OfficialAnkiRuntimeProbe {
  const OfficialAnkiRuntimeProbe({
    required this.ok,
    required this.reason,
    this.libraryPath,
    this.abiVersion,
    this.backendCommit,
    this.contractMajor,
    this.contractMinor,
    this.executionMode = OfficialAnkiExecutionMode.none,
  });

  final bool ok;
  final String reason;
  final String? libraryPath;
  final int? abiVersion;
  final String? backendCommit;
  final int? contractMajor;
  final int? contractMinor;
  final OfficialAnkiExecutionMode executionMode;
}

class OfficialAnkiCompositionRoot {
  OfficialAnkiCompositionRoot._();

  static OfficialAnkiImporter? session;
  static OfficialAnkiSession? stagingSession;
  static OfficialAnkiEngine? stagingEngine;
  static OfficialAnkiEngine? get engine => projectionEngineFromSession();
  static OfficialAnkiExecutionMode executionMode =
      OfficialAnkiExecutionMode.none;
  static OfficialAnkiDatabase? readOnlyCatalog;
  static OfficialAnkiPaths? locatorPaths;
  static Future<OfficialAnkiImporter>? _opening;
  static bool stagingDiscardRequested = false;

  static OfficialAnkiRuntimeProbe probe({String? libraryPath}) {
    final flags = OfficialAnkiFeatureFlags.current;
    if (!flags.allowsOfficialImport && !flags.allowsOfficialRenderer) {
      return OfficialAnkiRuntimeProbe(
        ok: false,
        reason: 'flags_off',
        executionMode: executionMode,
      );
    }
    // `isHarmonyOsTarget` is checked here as a peer of the Platform.is*
    // branches rather than as one of them: every Platform.is* is false on
    // HarmonyOS (§2.1 receipt), so there is no Platform spelling of this
    // condition. ADR 0050 §6 step 3 — the refusal this replaces also blocked
    // the only path that could answer §4.2's API question, which is why that
    // question needed a separate probe.
    if (!(Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isLinux ||
        Platform.isMacOS ||
        isHarmonyOsTarget)) {
      return OfficialAnkiRuntimeProbe(
        ok: false,
        reason: 'unsupported_platform',
        executionMode: executionMode,
      );
    }
    final resolved = libraryPath ?? resolveOfficialAnkiLibraryPath();
    if (resolved == null) {
      return OfficialAnkiRuntimeProbe(
        ok: false,
        reason: 'library_missing',
        executionMode: executionMode,
      );
    }
    try {
      final transport = OfficialAnkiNativeTransport.open(libraryPath: resolved);
      final abi = transport.abiVersion();
      if (abi != 1) {
        return OfficialAnkiRuntimeProbe(
          ok: false,
          reason: 'abi_mismatch',
          libraryPath: resolved,
          abiVersion: abi,
          executionMode: executionMode,
        );
      }
      final handle = transport.engineNew();
      try {
        final info = transport.call(
          handle,
          OfficialAnkiOperation.idFor(OfficialAnkiOperation.engineInfo),
          const OfficialAnkiEnvelopeRequest(
            requestId: 'probe-engine-info',
            operation: OfficialAnkiOperation.engineInfo,
          ),
        );
        final payload = info.requirePayload();
        return OfficialAnkiRuntimeProbe(
          ok: true,
          reason: 'ready',
          libraryPath: resolved,
          abiVersion: abi,
          backendCommit: payload['backendCommit'] as String?,
          contractMajor: (payload['contractMajor'] as num?)?.toInt(),
          contractMinor: (payload['contractMinor'] as num?)?.toInt(),
          executionMode: executionMode,
        );
      } finally {
        transport.engineClose(handle);
      }
    } on OfficialAnkiException catch (error) {
      return OfficialAnkiRuntimeProbe(
        ok: false,
        reason: error.messageKey,
        libraryPath: resolved,
        executionMode: executionMode,
      );
    }
  }

  static void rejectInProcessForProduction(OfficialAnkiFeatureFlags flags) {
    if (executionMode != OfficialAnkiExecutionMode.inProcess) return;
    if (flags.allowsOfficialImport || flags.allowsOfficialRenderer) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.capabilityMissing,
        messageKey: 'official_anki.in_process_forbidden',
      );
    }
  }

  static Future<OfficialAnkiImporter> requireImporter({
    Directory? supportDir,
    String? libraryPath,
    bool useFake = false,
    bool allowInProcessFallback = false,
  }) async {
    final flags = OfficialAnkiFeatureFlags.current;
    if (!flags.allowsOfficialImport && !useFake) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.capabilityMissing,
        messageKey: 'official_anki.flag_fail_closed',
      );
    }
    if (session != null) {
      rejectInProcessForProduction(flags);
      return session!;
    }
    final support = supportDir ?? await getApplicationSupportDirectory();
    final inFlight = _opening;
    if (inFlight != null) return inFlight;
    final opening = _openImporter(
      supportDir: support,
      libraryPath: libraryPath,
      useFake: useFake,
      allowInProcessFallback: allowInProcessFallback,
    );
    _opening = opening;
    try {
      return await opening;
    } finally {
      if (identical(_opening, opening)) _opening = null;
    }
  }

  static Future<OfficialAnkiImporter> _openImporter({
    required Directory supportDir,
    String? libraryPath,
    required bool useFake,
    required bool allowInProcessFallback,
  }) async {
    final flags = OfficialAnkiFeatureFlags.current;
    if (session != null) {
      rejectInProcessForProduction(flags);
      return session!;
    }
    final root = Directory('${supportDir.path}/official_anki/default');
    final paths = OfficialAnkiPaths(
      profileId: 'profile-default-01',
      profileRoot: root,
    );
    await paths.ensureLayout();
    // Doc 38 P4-C: the entry-page catalog hook must return the shared
    // read locator handle. A per-call factory leaked one open connection
    // per `resolveActiveSectionIds()` call.
    OfficialAnkiCourseEntry.catalogOf = () => _ensureSharedCatalog(paths);
    final resolved = libraryPath ??
        resolveOfficialAnkiLibraryPath() ??
        (Platform.isAndroid ? 'libturna_anki.so' : null);
    if (useFake) {
      session = await OfficialAnkiSession.spawn(
        paths: paths,
        useFake: true,
      );
      executionMode = OfficialAnkiExecutionMode.fake;
      return session!;
    }
    try {
      session = await OfficialAnkiSession.spawn(
        paths: paths,
        libraryPath: resolved,
      );
      executionMode = OfficialAnkiExecutionMode.worker;
    } on OfficialAnkiException catch (error) {
      if (!allowInProcessFallback ||
          flags.allowsOfficialImport ||
          flags.allowsOfficialRenderer) {
        logger.w(
          '[OfficialAnki] worker isolate failed ($error); fail closed',
        );
        executionMode = OfficialAnkiExecutionMode.none;
        rethrow;
      }
      logger.w(
        '[OfficialAnki] worker isolate failed ($error); '
        'in-process fallback enabled',
      );
      session = OfficialAnkiInProcessHost.open(
        paths: paths,
        libraryPath: resolved,
      );
      executionMode = OfficialAnkiExecutionMode.inProcess;
    }
    return session!;
  }

  /// Cold-start catalog locator. Opens catalog only — no Collection writer.
  ///
  /// No-op on the OpenHarmony companion build, and the reason is narrow: the
  /// shared catalog is a `sqlite3` FFI database, [_ensureSharedCatalog] throws
  /// `Unsupported platform: ohos` out of `sqlite3`'s loader, and the platform
  /// ships no `libsqlite3.so` to load. That is not a recoverable error here —
  /// this runs on every cold start, so the throw aborts the whole startup
  /// continuation and the splash never gets past "course did not load" even
  /// though the course database itself is fine (it is ArkData-backed, see
  /// `HarmonyOsRdbExecutor`).
  ///
  /// **This is the Turna-side catalog, not the engine.** The engine's own
  /// SQLite is `bundled` into `libturna_anki.so` and was verified working on
  /// device (ADR 0046); the gap is the separate FFI library this class opens,
  /// not the engine. ADR 0050 §4.1 authorises shipping one; this early return
  /// is removed by the wiring batch, not by any flag.
  ///
  /// Degrading is the specified behaviour, not a shortcut: the companion build
  /// currently cannot import Official decks, so there is no Anki deck to read.
  /// Leaving `catalogOf` unbound means Official sections resolve to empty,
  /// which is the correct answer for a build that cannot import them.
  /// The degradation is logged rather than swallowed, and the settings page
  /// surfaces it to the user.
  static Future<void> initializeReadOnlyLocator({
    Directory? supportDir,
  }) async {
    if (isHarmonyOsTarget) {
      logger.w(
        'Official Anki shared catalog is not available on the OpenHarmony '
        'companion build (no sqlite3 FFI for the Turna-side catalog; the '
        'engine itself is unaffected per ADR 0046). Wiring pending ADR 0050; '
        'until then the Learn tree shows builtin courses only.',
      );
      return;
    }
    if (readOnlyCatalog != null && locatorPaths != null && supportDir == null) {
      _bindCourseEntryCatalog(locatorPaths!);
      return;
    }
    final support = supportDir ?? await getApplicationSupportDirectory();
    final paths = OfficialAnkiPaths(
      profileId: 'profile-default-01',
      profileRoot: Directory('${support.path}/official_anki/default'),
    );
    await paths.ensureLayout();
    _ensureSharedCatalog(paths);
  }

  static String? _sharedCatalogPath;

  /// Opens (once per catalog file) and returns the main-isolate shared
  /// catalog handle. Both the cold-start locator and the importer path land
  /// here so exactly one main-isolate connection exists per file; the
  /// worker isolate keeps its own. A different path (profile switch, tests)
  /// swaps the handle and disposes the previous one.
  /// Course-tree visibility reads [OfficialAnkiCourseEntry.catalogOf]. Cold
  /// start used to open [readOnlyCatalog] without this hook, so
  /// [OfficialAnkiCourseEntry.resolveActiveSectionIds] returned empty and
  /// imported Official sections were filtered out of the Learn tree.
  static void _bindCourseEntryCatalog(OfficialAnkiPaths paths) {
    OfficialAnkiCourseEntry.catalogOf = () => _ensureSharedCatalog(paths);
  }

  static OfficialAnkiDatabase _ensureSharedCatalog(OfficialAnkiPaths paths) {
    final wanted = paths.catalogFile.path;
    final existing = readOnlyCatalog;
    final OfficialAnkiDatabase catalog;
    if (existing != null && _sharedCatalogPath == wanted) {
      catalog = existing;
    } else {
      final opened = OfficialAnkiDatabase.file(wanted);
      existing?.close();
      readOnlyCatalog = opened;
      _sharedCatalogPath = wanted;
      locatorPaths = paths;
      catalog = opened;
    }
    _bindCourseEntryCatalog(paths);
    return catalog;
  }

  /// Test seam: engine used by [projectionEngineFromSession] regardless of
  /// session state. Production never sets this.
  static OfficialAnkiEngine? debugEngineOverride;

  /// Test seam: staging-collection engine (must not be the live override).
  static OfficialAnkiEngine? debugStagingEngineOverride;

  static OfficialAnkiEngine? projectionEngineFromSession() {
    final overridden = debugEngineOverride;
    if (overridden != null) return overridden;
    final current = session;
    if (current is OfficialAnkiInProcessHost) return current.engine;
    if (current is OfficialAnkiSession) {
      return OfficialAnkiSessionEngine(current);
    }
    return null;
  }

  static OfficialAnkiEngine? stagingEngineFromSession() {
    final overridden = debugStagingEngineOverride;
    if (overridden != null) return overridden;
    if (stagingEngine != null) return stagingEngine;
    final current = stagingSession;
    if (current != null) return OfficialAnkiSessionEngine(current);
    return null;
  }

  static OfficialAnkiSession requireWorkerSession() {
    final current = session;
    if (current is! OfficialAnkiSession ||
        executionMode != OfficialAnkiExecutionMode.worker) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.capabilityMissing,
        messageKey: 'official_anki.worker_required',
      );
    }
    return current;
  }
}
