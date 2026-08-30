import 'dart:io';

import 'package:flutter/foundation.dart';
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
import 'package:turna/application/anki_official/projection/official_anki_projection_paging.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_service.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/data/course_database.dart';

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
  static OfficialAnkiEngine? get engine => projectionEngineFromSession();
  static OfficialAnkiExecutionMode executionMode = OfficialAnkiExecutionMode.none;
  static OfficialAnkiDatabase? readOnlyCatalog;
  static OfficialAnkiPaths? locatorPaths;
  static Future<OfficialAnkiImporter>? _opening;

  static OfficialAnkiRuntimeProbe probe({String? libraryPath}) {
    final flags = OfficialAnkiFeatureFlags.current;
    if (!flags.allowsOfficialImport && !flags.allowsOfficialRenderer) {
      return OfficialAnkiRuntimeProbe(
        ok: false,
        reason: 'flags_off',
        executionMode: executionMode,
      );
    }
    if (!(Platform.isAndroid || Platform.isLinux || Platform.isMacOS)) {
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
        debugPrint(
          '[OfficialAnki] worker isolate failed ($error); fail closed',
        );
        executionMode = OfficialAnkiExecutionMode.none;
        rethrow;
      }
      debugPrint(
        '[OfficialAnki] worker isolate failed ($error); '
        'diagnostics in-process host enabled',
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
  static Future<void> initializeReadOnlyLocator({
    Directory? supportDir,
  }) async {
    if (readOnlyCatalog != null) return;
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
  static OfficialAnkiDatabase _ensureSharedCatalog(OfficialAnkiPaths paths) {
    final wanted = paths.catalogFile.path;
    final existing = readOnlyCatalog;
    if (existing != null && _sharedCatalogPath == wanted) return existing;
    final opened = OfficialAnkiDatabase.file(wanted);
    existing?.close();
    readOnlyCatalog = opened;
    _sharedCatalogPath = wanted;
    locatorPaths = paths;
    return opened;
  }

  static OfficialAnkiCourseProjectionService createProjectionService({
    required OfficialAnkiEngine engine,
    required OfficialAnkiDatabase catalog,
    required CourseDatabase course,
    required String sourceId,
    required String profileId,
    OfficialAnkiFeatureFlags? flags,
  }) {
    return OfficialAnkiCourseProjectionService(
      engine: engine,
      catalog: catalog,
      course: course,
      sourceId: sourceId,
      profileId: profileId,
      flags: flags ?? OfficialAnkiFeatureFlags.current,
      ownerToken: officialAnkiProjectionOwnerToken(profileId),
    );
  }

  /// Test seam: engine used by [projectionEngineFromSession] regardless of
  /// session state. Production never sets this.
  static OfficialAnkiEngine? debugEngineOverride;

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
