// Package imports:
import 'package:drift/drift.dart';

// Project imports:
import 'package:varnamala/core/logger.dart';

part 'course_database.g.dart';

/// Course index + content, stored as a normalized tree with lesson bodies
/// kept as JSON blobs (`LessonContent.toJson()`). The DB is a derived cache
/// seeded from the bundled JSON assets (`DatabaseSeeder`); the assets remain
/// the source of truth.
///
/// `prerequisiteSectionIds` / `prerequisiteUnitIds` / `prerequisiteLessonIds`
/// and vocabulary `tags` are stored as JSON-encoded `TEXT` (small lists; v1
/// trade-off — can be promoted to join tables in a future schema bump).

/// `sections` index rows — one per [Section]. `level` stores the CEFR tag
/// ("A1"…"B2") or the "Anki" marker for imported decks (empty = unknown;
/// added in v6 — older rows read back as `null`).
class Sections extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get description => text().withDefault(const Constant(''))();
  TextColumn get level => text().withDefault(const Constant(''))();
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

/// `anki_imports` — one row per imported Anki deck (.apkg/.colpkg).
/// `notetypesJson` stores the original notetype definitions plus the mapping
/// decisions made at import time so re-imports can reuse them.
/// `sourceHash` (sha256 of the package file) powers incremental-update
/// detection; `importedAt` is epoch seconds.
class AnkiImports extends Table {
  TextColumn get importId => text()();
  TextColumn get sourcePath => text()();
  TextColumn get sourceHash => text()();
  IntColumn get importedAt => integer()();
  IntColumn get deckCount => integer().withDefault(const Constant(0))();
  IntColumn get noteCount => integer().withDefault(const Constant(0))();
  IntColumn get cardCount => integer().withDefault(const Constant(0))();
  IntColumn get mediaCount => integer().withDefault(const Constant(0))();
  TextColumn get notetypesJson =>
      text().withDefault(const Constant('{}'))();
  BoolColumn get aiEnhanced =>
      boolean().withDefault(const Constant(false))();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {importId};
}

/// `srs_states` - one row per tracked SRS item ([SrsWord]), keyed by `wordId`.
/// The durable store for SRS scheduling state (migrated from the old
/// `StreamingSharedPreferences` JSON blob in v7). `queue` discriminates the
/// owning queue (`'srs'` for words/expressions, `'grammar'` for grammar
/// points) so the two [SrsQueueProvider] subclasses share one table while
/// keeping their data isolated, mirroring the old separate prefs blobs.
/// `dueAt` / `lastReviewedAt` are epoch milliseconds; `type` is the
/// [SrsItemType] name (`'word'` / `'expression'`).
class SrsStates extends Table {
  TextColumn get wordId => text()();
  TextColumn get queue => text()();
  IntColumn get dueAt => integer()();
  IntColumn get intervalDays => integer().withDefault(const Constant(1))();
  RealColumn get ease => real().withDefault(const Constant(2.5))();
  IntColumn get reps => integer().withDefault(const Constant(0))();
  IntColumn get lapses => integer().withDefault(const Constant(0))();
  BoolColumn get isLeech => boolean().withDefault(const Constant(false))();
  TextColumn get type => text().withDefault(const Constant('word'))();
  IntColumn get lastReviewedAt => integer().nullable()();
  // FSRS continuous memory fields (ADR 0028 / schema v8). Nullable so rows
  // created under SM-2 migrate lazily on first review.
  RealColumn get stability => real().nullable()();
  RealColumn get difficulty => real().nullable()();
  IntColumn get fsrsState => integer().withDefault(const Constant(1))();
  IntColumn get learningStep => integer().nullable()();

  @override
  Set<Column> get primaryKey => {wordId};
}

/// `review_events` - one row per SRS review (the per-card history that powers
/// the memory-curve / retention features). Written from
/// [SrsQueueProvider.reviewItem] on every grade. `cardId` matches the
/// `srs_states.wordId`; `queue` matches [SrsQueueProvider.queueId];
/// `reviewedAt` is epoch milliseconds; `quality` is the SM-2 grade (0..5);
/// `prev*`/`next*` capture the interval/ease transition; `type` is the
/// [SrsItemType] name. Not purged - the forgetting-curve model needs full
/// history.
@TableIndex(name: 'review_events_card_idx', columns: {#cardId})
@TableIndex(name: 'review_events_time_idx', columns: {#reviewedAt})
class ReviewEvents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get cardId => text()();
  TextColumn get queue => text()();
  IntColumn get reviewedAt => integer()();
  IntColumn get quality => integer()();
  IntColumn get prevIntervalDays => integer()();
  IntColumn get nextIntervalDays => integer()();
  RealColumn get prevEase => real()();
  RealColumn get nextEase => real()();
  IntColumn get reps => integer()();
  IntColumn get lapses => integer()();
  TextColumn get type => text().withDefault(const Constant('word'))();
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
    AnkiImports,
    SrsStates,
    ReviewEvents,
  ],
)
class CourseDatabase extends _$CourseDatabase {
  CourseDatabase(QueryExecutor e) : super(e);

  @override
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async => await m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from > to) {
            // App downgrade: the on-disk schema is newer than this code
            // expects. The course DB is a derived cache reseedable from the
            // bundled JSON assets, so the safe policy is to wipe all course
            // tables and let `createAll` rebuild the current schema.
            // `setupLocator` runs `DatabaseSeeder.seedIfNeeded` right after
            // open, which will reseed (the `contentVersion` meta is also
            // wiped, forcing a reseed). This avoids crashing an
            // already-downgraded app for a reseedable cache.
            logger.w('Course DB downgrade $from -> $to; recreating schema fresh');
            for (final tableName in [
              'lesson_contents',
              'lessons',
              'units',
              'sections',
              'vocabulary',
              'grammar_points',
              'expressions',
              'course_meta',
              'anki_imports',
              'srs_states',
              'review_events',
            ]) {
              await m.deleteTable(tableName);
            }
            await m.createAll();
            return;
          }
          if (from < 2) {
            // v2: grammar points table without practiceItems (added in v3).
            // Use raw SQL so the v3 addColumn step is always meaningful.
            await m.database.customStatement('''
              CREATE TABLE IF NOT EXISTS grammar_points (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                explanation TEXT NOT NULL DEFAULT '',
                example_expression_ids TEXT NOT NULL DEFAULT '[]',
                example_sentence_ids TEXT NOT NULL DEFAULT '[]'
              )
            ''');
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
          if (from < 6) {
            // v6: Anki deck import metadata + persisted section level (CEFR /
            // "Anki") so level-based filtering survives restarts.
            await m.createTable(ankiImports);
            await m.addColumn(sections, sections.level);
          }
          if (from < 7) {
            // v7: SRS scheduling state moves from a SharedPreferences JSON blob
            // to SQLite (`srs_states`), and a per-card review-history table
            // (`review_events`) is added to power the memory-curve features.
            // Both start empty; SRS state is backfilled from the old prefs keys
            // by `SrsQueueProvider.ensureLoaded` (one-time, per queue).
            await m.createTable(srsStates);
            await m.createTable(reviewEvents);
          }
          if (from < 8) {
            // v8: FSRS continuous memory fields on srs_states (ADR 0028).
            // Only alter tables that already existed at v7. Upgrades from
            // from < 7 create `srs_states` via createTable with the *current*
            // table definition (already includes these columns).
            if (from >= 7) {
              await m.addColumn(srsStates, srsStates.stability);
              await m.addColumn(srsStates, srsStates.difficulty);
              await m.addColumn(srsStates, srsStates.fsrsState);
              await m.addColumn(srsStates, srsStates.learningStep);
            }
          }
        },
      );
}