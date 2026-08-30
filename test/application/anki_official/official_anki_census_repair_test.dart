import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_repair_executor.dart';
import 'package:turna/application/anki_official/migration/official_anki_startup_census.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/data/course_database.dart';
import 'package:drift/native.dart';

import '../../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  test('census classifies empty catalogs as clean', () async {
    final course = CourseDatabase(NativeDatabase.memory());
    addTearDown(course.close);
    final catalog = OfficialAnkiDatabase.memory();
    addTearDown(catalog.close);
    final report = await const OfficialAnkiStartupCensus().collect(
      course: course,
      catalog: catalog,
    );
    expect(report.rows, isA<List>());
    for (final row in report.rows) {
      expect(row.decision.evidenceHash, isNotEmpty);
    }
  });

  test('repair whitelist is closed', () {
    expect(
      OfficialAnkiRepairExecutor.whitelist,
      containsAll([
        'resumeImport',
        'retryCleanup',
        'quarantine',
        'enqueueMaintenance',
      ]),
    );
    expect(OfficialAnkiRepairExecutor.whitelist.contains('dropCollection'), isFalse);
  });
}
