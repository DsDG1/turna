import 'dart:io';
import 'dart:isolate';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_session.dart';
import 'package:turna/application/anki_official/engine/official_anki_session_cleanup.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';

void main() {
  test('spawn open dispose reopen 100 times with fake worker', () async {
    for (var i = 0; i < 100; i++) {
      final root = Directory.systemTemp.createTempSync('turna-dispose-$i-');
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      final paths = OfficialAnkiPaths(
        profileId: 'profile-disp${i.toString().padLeft(2, '0')}',
        profileRoot: Directory('${root.path}/profile'),
      );
      final session = await OfficialAnkiSession.spawn(
        paths: paths,
        catalogPath: '${root.path}/catalog.sqlite',
        useFake: true,
      );
      await session.engineInfo();
      await session.dispose();
      await session.dispose();
      expect(
        () => session.engineInfo(),
        throwsA(
          isA<OfficialAnkiException>().having(
            (e) => e.code,
            'code',
            OfficialAnkiErrorCode.invalidState,
          ),
        ),
      );
    }
  });

  test('ensureCollectionOpen can be called twice on the same session', () async {
    final root = Directory.systemTemp.createTempSync('turna-ensure-open-');
    addTearDown(() => root.deleteSync(recursive: true));
    final session = await OfficialAnkiSession.spawn(
      paths: OfficialAnkiPaths(
        profileId: 'profile-open01',
        profileRoot: Directory('${root.path}/profile'),
      ),
      catalogPath: '${root.path}/catalog.sqlite',
      useFake: true,
    );
    addTearDown(session.dispose);
    await session.ensureCollectionOpen();
    await session.ensureCollectionOpen();
    final info = await session.engineInfo();
    expect(info.has('RENDER_CARD'), isTrue);
  });

  test('double dispose is idempotent', () async {
    final root = Directory.systemTemp.createTempSync('turna-dispose-once-');
    addTearDown(() => root.deleteSync(recursive: true));
    final session = await OfficialAnkiSession.spawn(
      paths: OfficialAnkiPaths(
        profileId: 'profile-once01',
        profileRoot: Directory('${root.path}/profile'),
      ),
      catalogPath: '${root.path}/catalog.sqlite',
      useFake: true,
    );
    final first = session.dispose();
    final second = session.dispose();
    await Future.wait([first, second]);
  });

  test('timed-out handle cleanup is not engineClose on the caller isolate', () async {
    final caller = Isolate.current.debugName;
    officialAnkiCloseHandleInCleanupIsolate(handle: 0, libraryPath: '');
    final remoteName = await Isolate.run(() => Isolate.current.debugName);
    expect(remoteName, isNot(caller));
    await officialAnkiCloseHandleOffUiIsolate(handle: 0, libraryPath: '');
  });
}
