import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:turna/application/anki_official/lifecycle/official_anki_file_log.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/engine/official_anki_native_transport.dart';
import 'package:turna/application/anki_official/engine/official_anki_session.dart';
import 'package:turna/application/anki_official/engine/official_anki_session_engine.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';

/// One-shot staging collection directory + isolate (doc 42 P1).
class OfficialAnkiStagingManager {
  OfficialAnkiStagingManager({required this.livePaths});

  final OfficialAnkiPaths livePaths;

  OfficialAnkiPaths pathsFor(String attemptId) {
    return OfficialAnkiPaths(
      profileId: livePaths.profileId,
      profileRoot: Directory(
        p.join(livePaths.profileRoot.parent.path, 'staging', attemptId),
      ),
    );
  }

  bool isIntact(OfficialAnkiPaths stagingPaths) {
    final file = stagingPaths.collectionFile;
    return file.existsSync() && file.lengthSync() > 0;
  }

  Future<OfficialAnkiEngine> acquire(OfficialAnkiPaths stagingPaths) async {
    await stagingPaths.ensureLayout();
    final override = OfficialAnkiCompositionRoot.debugStagingEngineOverride;
    final OfficialAnkiEngine engine;
    if (override != null) {
      engine = override;
      OfficialAnkiCompositionRoot.stagingEngine = override;
    } else {
      final session = await OfficialAnkiSession.spawn(
        paths: stagingPaths,
        libraryPath: resolveOfficialAnkiLibraryPath(),
      );
      OfficialAnkiCompositionRoot.stagingSession = session;
      engine = OfficialAnkiSessionEngine(session);
      OfficialAnkiCompositionRoot.stagingEngine = engine;
    }
    // Step1 task B: both branches must open before import — spawn() only
    // engineNew()s, so the production branch used to hand back a Created
    // engine and import_package failed with INVALID_STATE. ensureOpen is
    // idempotent (already-open swallowed, integrity check re-run).
    await engine.openProfile(stagingPaths);
    return engine;
  }

  Future<void> kill() async {
    final override = OfficialAnkiCompositionRoot.debugStagingEngineOverride;
    final session = OfficialAnkiCompositionRoot.stagingSession;
    final engine = OfficialAnkiCompositionRoot.stagingEngine;
    try {
      await engine?.cancel();
    } catch (suppressed) {
      officialAnkiFileLog('OfficialAnkiStagingManager', 'cancel: $suppressed');
    }
    if (session != null) {
      try {
        await session.dispose();
      } catch (suppressed) {
        officialAnkiFileLog('OfficialAnkiStagingManager', 'dispose session: $suppressed');
      }
    } else if (override == null) {
      try {
        await engine?.dispose();
      } catch (suppressed) {
        officialAnkiFileLog('OfficialAnkiStagingManager', 'dispose engine: $suppressed');
      }
    } else {
      try {
        await override.closeCollection();
      } catch (suppressed) {
        officialAnkiFileLog('OfficialAnkiStagingManager', 'close override: $suppressed');
      }
    }
    OfficialAnkiCompositionRoot.stagingSession = null;
    OfficialAnkiCompositionRoot.stagingEngine = null;
  }

  /// Windows may keep the collection file locked until the isolate exits.
  static Future<void> deleteDirectory(
    Directory dir, {
    int attempts = 8,
  }) async {
    for (var i = 0; i < attempts; i++) {
      try {
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
        return;
      } catch (suppressed) {
        officialAnkiFileLog('OfficialAnkiStagingManager', 'delete try $i: $suppressed');
        await Future<void>.delayed(Duration(milliseconds: 50 * (i + 1)));
      }
    }
    if (dir.existsSync()) {
      throw OfficialAnkiException(
        code: OfficialAnkiErrorCode.internalError,
        messageKey: 'official_anki.staging_delete_failed',
        debugDetails: dir.path,
      );
    }
  }
}
