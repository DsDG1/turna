import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/engine/official_anki_operation_coordinator.dart';
import 'package:turna/application/anki_official/migration/official_anki_fixture_pilot_saga.dart';
import 'package:turna/application/anki_official/migration/official_anki_fixture_rollback_drill.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_dao.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';

/// Opt-in runner: P5C_RB_PROFILE_ROOT=/tmp/p5c-rb-device flutter test \
///   --no-pub test/application/anki_official/official_anki_p5c_device_rollback_runner_test.dart
void main() {
  final rootPath = Platform.environment['P5C_RB_PROFILE_ROOT'];
  if (rootPath == null || rootPath.isEmpty) {
    test('device rollback runner skipped without P5C_RB_PROFILE_ROOT', () {});
    return;
  }

  test('apply Device A fixture rollback drill to pulled catalog', () async {
    final paths = OfficialAnkiPaths(
      profileId: 'profile-default-01',
      profileRoot: Directory(rootPath),
    );
    expect(paths.catalogFile.existsSync(), isTrue);
    final catalog = OfficialAnkiDatabase.file(paths.catalogFile.path);
    addTearDown(catalog.close);
    final dao = OfficialAnkiMigrationDao(catalog);
    final sources = OfficialAnkiSourceDao(catalog);
    var userCards = 0;
    for (final source in sources.listSources(paths.profileId)) {
      if (source.displayName.startsWith('p5c-fixture')) continue;
      userCards += sources.cardCount(source.sourceId);
    }
    final saga = OfficialAnkiFixturePilotSaga(
      dao: dao,
      coordinator: OfficialAnkiOperationCoordinator(),
    );
    final report = await const OfficialAnkiFixtureRollbackDrill().runBothPaths(
      saga: saga,
      dao: dao,
      paths: paths,
      profileId: paths.profileId,
      userCardCount: userCards,
    );
    // ignore: avoid_print
    print(
      'ROLLBACK_DRILL bothPassed=${report.bothPassed} detail=${report.detail} '
      'gt0=${report.mutationGt0?.migrationId}/${report.mutationGt0?.state.name}/${report.mutationGt0?.recordedKind}/d=${report.mutationGt0?.delta} '
      'eq0=${report.mutationEq0?.migrationId}/${report.mutationEq0?.state.name}/${report.mutationEq0?.recordedKind}/d=${report.mutationEq0?.delta} '
      'userCards=${report.userCardCount} collection=${report.collectionPresent}',
    );
    expect(report.bothPassed, isTrue);
    expect(report.userCardCount, 181);
    expect(report.collectionPresent, isTrue);
  });
}
