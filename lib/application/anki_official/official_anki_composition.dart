import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:turna/application/anki_official/contract/official_anki_contract.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_in_process.dart';
import 'package:turna/application/anki_official/engine/official_anki_native_transport.dart';
import 'package:turna/application/anki_official/engine/official_anki_session.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';

class OfficialAnkiRuntimeProbe {
  const OfficialAnkiRuntimeProbe({
    required this.ok,
    required this.reason,
    this.libraryPath,
    this.abiVersion,
    this.backendCommit,
    this.contractMajor,
  });

  final bool ok;
  final String reason;
  final String? libraryPath;
  final int? abiVersion;
  final String? backendCommit;
  final int? contractMajor;
}

class OfficialAnkiCompositionRoot {
  OfficialAnkiCompositionRoot._();

  static OfficialAnkiImporter? session;

  static OfficialAnkiRuntimeProbe probe({String? libraryPath}) {
    final flags = OfficialAnkiFeatureFlags.current;
    if (!flags.allowsOfficialImport) {
      return const OfficialAnkiRuntimeProbe(
        ok: false,
        reason: 'flags_off',
      );
    }
    if (!(Platform.isAndroid || Platform.isLinux || Platform.isMacOS)) {
      return const OfficialAnkiRuntimeProbe(
        ok: false,
        reason: 'unsupported_platform',
      );
    }
    final resolved = libraryPath ?? resolveOfficialAnkiLibraryPath();
    if (resolved == null) {
      return const OfficialAnkiRuntimeProbe(
        ok: false,
        reason: 'library_missing',
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
        );
      }
      final handle = transport.engineNew();
      try {
        final info = transport.call(
          handle,
          OfficialAnkiOperation.engineInfoId,
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
        );
      } finally {
        transport.engineClose(handle);
      }
    } on OfficialAnkiException catch (error) {
      return OfficialAnkiRuntimeProbe(
        ok: false,
        reason: error.messageKey,
        libraryPath: resolved,
      );
    }
  }

  static Future<OfficialAnkiImporter> requireImporter({
    required Directory supportDir,
    String? libraryPath,
    bool useFake = false,
  }) async {
    final flags = OfficialAnkiFeatureFlags.current;
    if (!flags.allowsOfficialImport) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.capabilityMissing,
        messageKey: 'official_anki.flag_fail_closed',
      );
    }
    if (session != null) return session!;
    final root = Directory('${supportDir.path}/official_anki/default');
    final paths = OfficialAnkiPaths(
      profileId: 'profile-default-01',
      profileRoot: root,
    );
    await paths.ensureLayout();
    final resolved = libraryPath ??
        resolveOfficialAnkiLibraryPath() ??
        (Platform.isAndroid ? 'libturna_anki.so' : null);
    if (useFake) {
      session = await OfficialAnkiSession.spawn(
        paths: paths,
        useFake: true,
      );
      return session!;
    }
    try {
      session = await OfficialAnkiSession.spawn(
        paths: paths,
        libraryPath: resolved,
      );
    } on OfficialAnkiException catch (error) {
      debugPrint(
        '[OfficialAnki] worker isolate failed ($error); using in-process engine',
      );
      session = OfficialAnkiInProcessHost.open(
        paths: paths,
        libraryPath: resolved,
      );
    }
    return session!;
  }
}
