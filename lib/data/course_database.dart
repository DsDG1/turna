// Package imports:
import 'package:drift/drift.dart';

part 'course_database.g.dart';

/// Course index + content, stored as a normalized tree with lesson bodies
/// kept as JSON blobs (`LessonContent.toJson()`). The DB is a derived cache
/// seeded from the bundled JSON assets (`DatabaseSeeder`); the assets remain
/// the source of truth.
///
/// `prerequisiteSectionIds` / `prerequisiteUnitIds` / `prerequisiteLessonIds`
/// and vocabulary `tags` are stored as JSON-encoded `TEXT` (small lists; v1
/// trade-off — can be promoted to join tables in a future schema bump).

/// `sections` index rows — one per [Section].
class Sections extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get prerequisiteSectionIds =>
      text().withDefault(const Constant('[]'))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// `units` index rows — one per [Unit], scoped to a section.
class Units extends Table {
  TextColumn get id => text()();
  TextColumn get sectionId => text().customConstraint(
        'NOT NULL REFERENCES sections(id) ON DELETE CASCADE',
      )();
  TextColumn get name => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get prerequisiteUnitIds =>
      text().withDefault(const Constant('[]'))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// `lessons` index rows — one per [Lesson], scoped to a unit.
class Lessons extends Table {
  TextColumn get id => text()();
  TextColumn get unitId => text().customConstraint(
        'NOT NULL REFERENCES units(id) ON DELETE CASCADE',
      )();
  TextColumn get name => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get type => text().withDefault(const Constant('normal'))();
  TextColumn get template => text().withDefault(const Constant('legacy'))();
  TextColumn get prerequisiteLessonIds =>
      text().withDefault(const Constant('[]'))();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Lesson body — the full [LessonContent] serialized as JSON. One row per
/// lesson. Stored normalized (the seeder runs `_normalizeSection` first), so
/// reads are a pure `LessonContent.fromJson(jsonDecode(blob))`.
class LessonContents extends Table {
  TextColumn get lessonId => text().customConstraint(
        'NOT NULL REFERENCES lessons(id) ON DELETE CASCADE',
      )();
  TextColumn get contentJson => text()();

  @override
  Set<Column> get primaryKey => {lessonId};
}

/// Vocabulary — one row per [WordEntry].
class Vocabulary extends Table {
  TextColumn get id => text()();
  TextColumn get term => text()();
  TextColumn get translation => text()();
  TextColumn get pronunciation => text().nullable()();
  TextColumn get audioAsset => text().nullable()();
  TextColumn get tags => text().withDefault(const Constant('[]'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Grammar points — one row per [GrammarPoint]. `exampleExpressionIds` /
/// `exampleSentenceIds` stored as JSON-encoded `TEXT` (id lists).
/// `practiceItems` is a JSON-encoded list of [Interaction] drills.
class GrammarPoints extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get explanation => text().withDefault(const Constant(''))();
  TextColumn get exampleExpressionIds =>
      text().withDefault(const Constant('[]'))();
  TextColumn get exampleSentenceIds =>
      text().withDefault(const Constant('[]'))();
  TextColumn get practiceItems => text().withDefault(const Constant('[]'))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Key-value meta for the course cache (e.g. content version from index.json).
class CourseMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Expressions — one row per [Expression].
@DataClassName('ExpressionEntry')
class Expressions extends Table {
  TextColumn get id => text()();
  TextColumn get term => text()();
  TextColumn get translation => text()();
  TextColumn get pronunciation => text().nullable()();
  TextColumn get audioAsset => text().nullable()();
  TextColumn get tags => text().withDefault(const Constant('[]'))();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(
  tables: [
    Sections,
    Units,
    Lessons,
    LessonContents,
    Vocabulary,
    GrammarPoints,
    CourseMeta,
    Expressions,
  ],
)
class CourseDatabase extends _$CourseDatabase {
  CourseDatabase(QueryExecutor e) : super(e);

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async => await m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // v2: grammar points table. Rows are seeded by [DatabaseSeeder]
            // (seedIfEmpty checks grammar_points independently of sections).
            await m.createTable(grammarPoints);
          }
          if (from < 3) {
            // v3: practice drills on grammar points (JSON Interaction list).
            await m.addColumn(grammarPoints, grammarPoints.practiceItems);
          }
          if (from < 4) {
            // v4: content-version meta for reseed invalidation.
            await m.createTable(courseMeta);
          }
          if (from < 5) {
            // v5: expression table for phrase-level SRS.
            await m.createTable(expressions);
          }
        },
      );
}