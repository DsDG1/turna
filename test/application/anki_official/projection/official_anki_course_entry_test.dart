import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/projection/official_anki_course_entry.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/data/course_database.dart';

import '../../../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  late CourseDatabase db;

  const sourceId = 'src-7b34bc7f8f154dc99892ef455aff4547';
  const sectionId =
      'official-anki-src-7b34bc7f8f154dc99892ef455aff4547-s1788263817735';
  const fingerprint =
      'b60c685a9598ddcff42b37a5ebadbf2a2cb4e8ffbb11888d1412f7dbda4d09a5';

  setUp(() async {
    db = await seedInMemoryCourseDb();
    OfficialAnkiCourseEntry.resetHooks();
    OfficialAnkiCourseEntry.flagsOf =
        () => OfficialAnkiFeatureFlags.productionAndroid;
    OfficialAnkiCourseEntry.courseOf = () => db;
    await db.customStatement(
      'INSERT INTO sections (id, name, level, sort_order) VALUES (?, ?, ?, ?)',
      [sectionId, 'German', 'OfficialAnki', 100],
    );
    await db.customStatement(
      "INSERT INTO official_anki_projection_manifest (source_id, "
      "active_generation, source_fingerprint, projection_version, "
      "section_count, lesson_count, item_count, published_at_millis) "
      "VALUES (?, ?, ?, 1, 1, 1, 1, 1)",
      [sourceId, fingerprint, fingerprint],
    );
    await db.customStatement(
      "INSERT INTO official_anki_projection_index (source_id, card_id, "
      "word_id, section_id, unit_id, lesson_id, projection_kind, "
      "source_fingerprint, projection_version) VALUES "
      "(?, 1, 'word-1', ?, 'official-anki-$sourceId-u1', "
      "'official-anki-$sourceId-l1-p1', 'canonicalLink', ?, 1)",
      [sourceId, sectionId, fingerprint],
    );
  });

  tearDown(() async {
    OfficialAnkiCourseEntry.resetHooks();
    CourseLoader.clearDatabaseOverride();
    await db.close();
  });

  test('resolveActiveSectionIds uses course manifest when catalogOf is null',
      () async {
    expect(OfficialAnkiCourseEntry.catalogOf, isNull);

    final ids = await OfficialAnkiCourseEntry.resolveActiveSectionIds();

    expect(ids, {sectionId});
  });
}
