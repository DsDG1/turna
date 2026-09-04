// Package imports:
import 'package:drift/drift.dart';

// Project imports:
import 'package:turna/core/logger.dart';

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
  TextColumn get notetypesJson => text().withDefault(const Constant('{}'))();
  BoolColumn get aiEnhanced => boolean().withDefault(const Constant(false))();
  IntColumn get version => integer().withDefault(const Constant(1))();

  @override
  Set<Column> get primaryKey => {importId};
}

/// `anki_notetypes` — leftover Legacy NoteStore snapshot of each notetype
/// (field names, `qfmt`/`afmt`, `css`, `allowJs`). Official fidelity does
/// not read this table. One row per (import, mid). `templatesJson` is
/// `[{name,qfmt,afmt}]`; `fieldNamesJson` is `["Front","Back"]`. Row class
/// is renamed via [DataClassName] to avoid colliding with retired parser
/// models.
@DataClassName('AnkiNotetypeRow')
class AnkiNotetypes extends Table {
  TextColumn get importId => text().customConstraint(
        'NOT NULL REFERENCES anki_imports(import_id) ON DELETE CASCADE',
      )();
  IntColumn get mid => integer()();
  TextColumn get name => text().withDefault(const Constant(''))();
  BoolColumn get isCloze => boolean().withDefault(const Constant(false))();
  TextColumn get fieldNamesJson => text().withDefault(const Constant('[]'))();
  TextColumn get templatesJson => text().withDefault(const Constant('[]'))();
  TextColumn get css => text().withDefault(const Constant(''))();

  /// Whether this notetype's qfmt/afmt contains `<script>` / `on*=` handlers,
  /// enabling JS in the fidelity WebView (decision 3: default off + container
  /// isolation via navigationDelegate + restricted file access).
  BoolColumn get allowJs => boolean().withDefault(const Constant(false))();

  @override
  Set<Column> get primaryKey => {importId, mid};
}

/// `anki_notes` — leftover Legacy NoteStore raw notes (`fieldsJson` aligned
/// with the notetype's `fieldNamesJson`). Kept for Legacy-owned browser
/// search until W9-E schema drop. Row class renamed to avoid colliding
/// with retired parser models.
@DataClassName('AnkiNoteRow')
class AnkiNotes extends Table {
  TextColumn get importId => text().customConstraint(
        'NOT NULL REFERENCES anki_imports(import_id) ON DELETE CASCADE',
      )();
  IntColumn get noteId => integer()();
  IntColumn get mid => integer()();
  TextColumn get tags => text().withDefault(const Constant(''))();
  TextColumn get fieldsJson => text().withDefault(const Constant('[]'))();
  TextColumn get sfld => text().withDefault(const Constant(''))();
  TextColumn get guid => text().withDefault(const Constant(''))();
  IntColumn get mod => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {importId, noteId};
}

/// `anki_cards_meta` — leftover Legacy per-card display metadata
/// (`suspended` / flag / marked). Official scheduling lives in the
/// Collection; `wordId` is `anki-<importId>-c<cardId>`.
@DataClassName('AnkiCardMetaRow')
class AnkiCardsMeta extends Table {
  TextColumn get importId => text().customConstraint(
        'NOT NULL REFERENCES anki_imports(import_id) ON DELETE CASCADE',
      )();
  IntColumn get cardId => integer()();
  IntColumn get noteId => integer()();
  IntColumn get ord => integer().withDefault(const Constant(0))();
  IntColumn get did => integer().withDefault(const Constant(0))();
  TextColumn get wordId => text()();
  TextColumn get renderMode => text().withDefault(const Constant('hybrid'))();
  TextColumn get schedulingJson => text().withDefault(const Constant('{}'))();

  @override
  Set<Column> get primaryKey => {importId, cardId};
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
  BoolColumn get isSuspended => boolean().withDefault(const Constant(false))();
  BoolColumn get isBuried => boolean().withDefault(const Constant(false))();
  TextColumn get type => text().withDefault(const Constant('word'))();
  IntColumn get lastReviewedAt => integer().nullable()();
  // FSRS continuous memory fields (ADR 0028 / schema v8). Nullable so rows
  // created under SM-2 migrate lazily on first review.
  RealColumn get stability => real().nullable()();
  RealColumn get difficulty => real().nullable()();
  IntColumn get fsrsState => integer().withDefault(const Constant(1))();
  IntColumn get learningStep => integer().nullable()();
  TextColumn get sourceKind => text().nullable()();
  TextColumn get sourceId => text().nullable()();
  TextColumn get ownerId => text().nullable()();

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
@TableIndex(
  name: 'review_events_source_idx',
  columns: {#sourceKey},
  unique: true,
)
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
  TextColumn get sourceKey => text().nullable()();
  TextColumn get sourceKind => text().nullable()();
  TextColumn get sourceId => text().nullable()();
  TextColumn get ownerId => text().nullable()();
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
    AnkiNotetypes,
    AnkiNotes,
    AnkiCardsMeta,
    SrsStates,
    ReviewEvents,
  ],
)
class CourseDatabase extends _$CourseDatabase {
  CourseDatabase(super.e);

  /// Single source of truth for the drift schema version, so tests and
  /// backup code never hard-code a stale literal.
  static const int kSchemaVersion = 24;

  @override
  int get schemaVersion => kSchemaVersion;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _addAnkiStateColumns(m.database);
          await _ensureAnkiCanonicalV2(m.database);
          await _ensureFunLabSnapshotTables(m.database);
          await _ensureAnkiUnificationTables(m.database);
          await _ensureAiCompanionTables(m.database);
          await _ensureGemEconomyTables(m.database);
          await _ensureV2CourseTreeView(m.database);
          await _backfillReviewSourceIdentity(m.database);
        },
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
            logger
                .w('Course DB downgrade $from -> $to; recreating schema fresh');
            for (final tableName in [
              'lesson_contents',
              'lessons',
              'units',
              'sections',
              'vocabulary',
              'grammar_points',
              'expressions',
              'course_meta',
              'anki_notetypes',
              'anki_notes',
              'anki_cards_meta',
              'srs_states',
              'review_events',
              'fun_lab_snapshot_anki_state',
              'fun_lab_snapshot_review_events',
              'fun_lab_snapshot_srs',
              'fun_lab_snapshot_meta',
              'anki_card_introduction_states',
              'study_product_events',
              'anki_course_tree_view',
            ]) {
              await m.deleteTable(tableName);
            }
            await m.createAll();
            await _addAnkiStateColumns(m.database);
            await _ensureAnkiCanonicalV2(m.database);
            await _ensureFunLabSnapshotTables(m.database);
            await _ensureAnkiUnificationTables(m.database);
            await _ensureAiCompanionTables(m.database);
            await _ensureV2CourseTreeView(m.database);
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
          if (from < 9) {
            // v9: Anki NoteStore - per-notetype templates/css + raw note fields
            // + card meta, so the fidelity track can re-render cards from the
            // source templates without re-parsing the .apkg (deep-adaptation
            // plan §3.2.1). All three start empty; populated at import time.
            await m.createTable(ankiNotetypes);
            await m.createTable(ankiNotes);
            await m.createTable(ankiCardsMeta);
          }
          if (from < 11) {
            // v11: preserve Anki note identity/scheduling provenance and keep
            // imported suspended/buried state out of the normal due queue.
            // Upgrades from before v9 create the Anki tables using the
            // current definitions in the v9 createTable step, so only an
            // already-existing v10 NoteStore needs ALTER TABLE here.
            if (from >= 10) {
              await m.addColumn(ankiNotes, ankiNotes.guid);
              await m.addColumn(ankiNotes, ankiNotes.mod);
              await m.addColumn(ankiCardsMeta, ankiCardsMeta.schedulingJson);
            }
            // v7+ databases already had these tables; older upgrades create
            // them from the current definitions during their earlier step.
            if (from >= 7) {
              await m.addColumn(srsStates, srsStates.isSuspended);
              await m.addColumn(srsStates, srsStates.isBuried);
              await m.addColumn(reviewEvents, reviewEvents.sourceKey);
            }
            await m.database.customStatement('''
              CREATE UNIQUE INDEX IF NOT EXISTS review_events_source_idx
              ON review_events(source_key)
            ''');
          }
          if (from < 12) {
            // v12: user-facing Anki card state used by the review menu and
            // browser. Existing cards default to the neutral state.
            await _addAnkiStateColumns(m.database);
          }
          if (from < 13) {
            // v13: canonical import lifecycle, deck navigation index,
            // optional practice projections, diagnostics, and count
            // reconciliation. Raw SQL keeps this migration additive and
            // preserves all v12 rows.
            await _ensureAnkiCanonicalV2(m.database);
          }
          if (from < 14) {
            // v14: re-key Anki SRS state from the pre-pivot note-based word
            // id (`anki-<importId>-n<noteId>`) to the card-level
            // `anki-<importId>-c<cardId>` (decision 2). The card-level
            // AnkiSrsMigrator change orphaned legacy rows (the review
            // assembler extracts the import id via `lastIndexOf('-c')`,
            // returning '' for `-n` ids). See [_rekeyLegacyAnkiWordIds].
            await _rekeyLegacyAnkiWordIds(m.database);
          }
          if (from < 15) {
            // v15: one persistent Fun Lab checkpoint. Raw tables intentionally
            // mirror the live progress tables so snapshots can be copied and
            // restored with transactional INSERT ... SELECT statements.
            await _ensureFunLabSnapshotTables(m.database);
          }
          if (from < 16) {
            await _ensureAiCompanionTables(m.database);
          }
          if (from < 18) {
            await _ensureAnkiUnificationTables(m.database);
          }
          if (from < 19) {
            // v19: gem ledger + cosmetic entitlements (Plan 2 §8.4) — the
            // atomic-purchase tables for the cosmetics economy.
            await _ensureGemEconomyTables(m.database);
          }
          if (from < 20) {
            await _addReviewSourceIdentityColumns(m.database);
            await _backfillReviewSourceIdentity(m.database);
          }
          if (from < 22) {
            // v22: drop the anki_prerendered_html cache ("智能去解密"). Its
            // only writer (upsertPrerenderedFace) lost its last production
            // caller when the legacy Anki layer was removed (doc 35), so the
            // table has been guaranteed empty since. IF EXISTS also covers
            // fresh installs and pre-v10 upgrades, which never created it.
            await m.database.customStatement(
                'DROP TABLE IF EXISTS anki_prerendered_html');
          }
          if (from < 23) {
            // v23 (ADR 0043 D3 / step4.md B3): the v2 course-tree view —
            // the ONLY course-tree storage for v2-chain sources. A
            // stateless materialized view: one row per card, DROP+REBUILD
            // at any time from Collection + config decisions + ledger. The
            // v1 projection tables stay untouched (flag-off = v1 exactly).
            await _ensureV2CourseTreeView(m.database);
          }
          if (from < 24) {
            // v24 (ADR 0043 D4 / ADR 0044 / step6.md): drop all 11 legacy v1
            // anki projection, placement, presentation, and migration tables.
            // Only anki_course_tree_view and anki_card_introduction_states remain.
            const ankiTablesToDrop = [
              'official_anki_projection_index',
              'official_anki_projection_manifest',
              'anki_course_card_placements',
              'anki_card_presentations',
              'anki_practice_projections',
              'anki_decks',
              'anki_import_issues',
              'anki_course_sources',
              'anki_owner_transitions',
              'course_scope_repair_journal',
              'anki_import_jobs',
              'legacy_pending_migrations',
              'course_meta_v21_codec',
            ];

            for (final table in ankiTablesToDrop) {
              await m.database.customStatement('DROP TABLE IF EXISTS $table');
            }
            await _ensureAnkiUnificationTables(m.database);
            await _ensureV2CourseTreeView(m.database);
          }
        },
      );

  static Future<void> _addReviewSourceIdentityColumns(
    GeneratedDatabase database,
  ) async {
    Future<void> add(String table, String column) async {
      final columns =
          await database.customSelect('PRAGMA table_info($table)').get();
      if (columns.isEmpty) return;
      if (columns.any((row) => row.read<String>('name') == column)) return;
      await database.customStatement(
        'ALTER TABLE $table ADD COLUMN $column TEXT',
      );
    }

    for (final table in const [
      'srs_states',
      'review_events',
      'fun_lab_snapshot_srs',
      'fun_lab_snapshot_review_events',
    ]) {
      for (final column in const ['source_kind', 'source_id', 'owner_id']) {
        await add(table, column);
      }
    }
  }

  static Future<void> _backfillReviewSourceIdentity(
    GeneratedDatabase database,
  ) async {
    // This is the only legacy prefix interpretation. It runs once while the
    // v19 database is exclusively migrating; production readers use columns.
    for (final tableAndId in const [
      ('srs_states', 'word_id'),
      ('review_events', 'card_id'),
      ('fun_lab_snapshot_srs', 'word_id'),
      ('fun_lab_snapshot_review_events', 'card_id'),
    ]) {
      final table = tableAndId.$1;
      final id = tableAndId.$2;
      final columns =
          await database.customSelect('PRAGMA table_info($table)').get();
      if (columns.isEmpty) continue;
      await database.customStatement('''
        UPDATE $table SET
          source_kind = CASE
            WHEN queue = 'grammar' THEN 'grammar'
            WHEN $id LIKE 'official-anki-%-c%' THEN 'ankiOfficial'
            WHEN $id LIKE 'anki-%-c%' THEN 'ankiLegacy'
            ELSE 'course'
          END,
          source_id = CASE
            WHEN queue = 'grammar' THEN 'grammar'
            WHEN $id LIKE 'official-anki-%-c%' THEN
              substr($id, 15, instr(substr($id, 15), '-c') - 1)
            WHEN $id LIKE 'anki-%-c%' THEN
              substr($id, 6, instr(substr($id, 6), '-c') - 1)
            ELSE 'course'
          END
        WHERE source_kind IS NULL OR source_id IS NULL
      ''');
    }
    await database.customStatement('''
      CREATE INDEX IF NOT EXISTS srs_states_source_identity_idx
      ON srs_states(source_kind, source_id)
    ''');
    await database.customStatement('''
      CREATE INDEX IF NOT EXISTS review_events_source_identity_idx
      ON review_events(source_kind, source_id, reviewed_at)
    ''');
  }

  /// Gem economy (Plan 2 §8.4): append-only ledger + entitlement rows.
  /// `gem_ledger.transaction_id` is the idempotency key; `event_id` guards
  /// against double-crediting the same game event. Purchases write the spend
  /// row and the entitlement in ONE transaction, so a crash can never leave
  /// "gems deducted but item not unlocked".
  static Future<void> _ensureGemEconomyTables(
    GeneratedDatabase database,
  ) async {
    await database.customStatement('''
      CREATE TABLE IF NOT EXISTS gem_ledger (
        transaction_id TEXT PRIMARY KEY NOT NULL,
        event_id TEXT UNIQUE,
        kind TEXT NOT NULL,
        amount INTEGER NOT NULL,
        reason TEXT NOT NULL DEFAULT '',
        item_id TEXT,
        created_at INTEGER NOT NULL,
        status TEXT NOT NULL DEFAULT 'committed'
      )
    ''');
    await database.customStatement('''
      CREATE TABLE IF NOT EXISTS cosmetic_entitlements (
        item_id TEXT PRIMARY KEY NOT NULL,
        acquired_by_transaction TEXT NOT NULL,
        acquired_at INTEGER NOT NULL,
        catalog_version INTEGER NOT NULL DEFAULT 1
      )
    ''');
  }

  static Future<void> _ensureAiCompanionTables(
    GeneratedDatabase database,
  ) async {
    await database.customStatement('''
      CREATE TABLE IF NOT EXISTS ai_sessions (
        id TEXT PRIMARY KEY NOT NULL,
        mode TEXT NOT NULL,
        title TEXT NOT NULL,
        language TEXT NOT NULL,
        goal_id TEXT,
        source_context_json TEXT NOT NULL DEFAULT '{}',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        summary TEXT NOT NULL DEFAULT '',
        status TEXT NOT NULL DEFAULT 'active',
        prompt_version TEXT NOT NULL DEFAULT '',
        model TEXT NOT NULL DEFAULT '',
        total_tokens INTEGER NOT NULL DEFAULT 0,
        estimated_cost REAL NOT NULL DEFAULT 0.0
      )
    ''');
    await database.customStatement('''
      CREATE TABLE IF NOT EXISTS ai_messages (
        id TEXT PRIMARY KEY NOT NULL,
        session_id TEXT NOT NULL,
        role TEXT NOT NULL,
        content TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        state TEXT NOT NULL DEFAULT 'complete',
        citations_json TEXT NOT NULL DEFAULT '[]',
        linked_knowledge_ids_json TEXT NOT NULL DEFAULT '[]',
        feedback TEXT
      )
    ''');
    await database.customStatement('''
      CREATE TABLE IF NOT EXISTS learning_evidence (
        id TEXT PRIMARY KEY NOT NULL,
        timestamp INTEGER NOT NULL,
        source_type TEXT NOT NULL,
        source_id TEXT NOT NULL,
        knowledge_type TEXT NOT NULL,
        knowledge_id TEXT NOT NULL,
        question_type TEXT,
        result TEXT NOT NULL,
        error_type TEXT NOT NULL,
        response_time_ms INTEGER,
        hint_level_used INTEGER NOT NULL DEFAULT 0,
        confidence REAL NOT NULL DEFAULT 1.0,
        metadata_json TEXT NOT NULL DEFAULT '{}',
        model TEXT,
        prompt_version TEXT,
        user_confirmed INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await database.customStatement('''
      CREATE TABLE IF NOT EXISTS knowledge_mastery (
        knowledge_type TEXT NOT NULL,
        knowledge_id TEXT NOT NULL,
        mastery REAL NOT NULL,
        confidence REAL NOT NULL,
        evidence_count INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        last_successful_recall_at INTEGER,
        stability_days REAL NOT NULL,
        PRIMARY KEY (knowledge_type, knowledge_id)
      )
    ''');
    await database.customStatement('''
      CREATE TABLE IF NOT EXISTS diagnosis_snapshots (
        id TEXT PRIMARY KEY NOT NULL,
        created_at INTEGER NOT NULL,
        data_window_days INTEGER NOT NULL,
        data_sufficiency TEXT NOT NULL,
        weak_areas_json TEXT NOT NULL,
        narrative TEXT NOT NULL,
        prompt_version TEXT NOT NULL
      )
    ''');
    await database.customStatement('''
      CREATE TABLE IF NOT EXISTS study_plans (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        target_minutes INTEGER NOT NULL DEFAULT 15,
        status TEXT NOT NULL DEFAULT 'active'
      )
    ''');
    await database.customStatement('''
      CREATE TABLE IF NOT EXISTS study_plan_items (
        id TEXT PRIMARY KEY NOT NULL,
        plan_id TEXT NOT NULL,
        kind TEXT NOT NULL,
        title TEXT NOT NULL,
        estimated_minutes INTEGER NOT NULL DEFAULT 5,
        item_order INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'pending',
        reason TEXT NOT NULL DEFAULT '',
        route TEXT,
        payload_json TEXT NOT NULL DEFAULT '{}'
      )
    ''');
    await database.customStatement('''
      CREATE TABLE IF NOT EXISTS ai_notes (
        id TEXT PRIMARY KEY NOT NULL,
        title TEXT NOT NULL,
        body TEXT NOT NULL,
        source TEXT NOT NULL,
        language TEXT,
        course_path TEXT,
        tags_json TEXT NOT NULL DEFAULT '[]',
        knowledge_ids_json TEXT NOT NULL DEFAULT '[]',
        status TEXT NOT NULL DEFAULT 'active',
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        next_review_at INTEGER
      )
    ''');
    await database.customStatement('''
      CREATE TABLE IF NOT EXISTS ai_request_metrics (
        request_id TEXT PRIMARY KEY NOT NULL,
        feature TEXT NOT NULL,
        session_id TEXT,
        prompt_version TEXT NOT NULL,
        model TEXT NOT NULL,
        started_at INTEGER NOT NULL,
        latency_ms INTEGER NOT NULL,
        input_tokens INTEGER NOT NULL,
        output_tokens INTEGER NOT NULL,
        cache_hit INTEGER NOT NULL DEFAULT 0,
        outcome TEXT NOT NULL,
        estimated_cost REAL NOT NULL DEFAULT 0.0
      )
    ''');
  }

  /// Schema v23: v2 chain materialized course-tree view (ADR 0043 D3 — the
  /// two v1 projection tables collapse into this one). No independent
  /// state: rebuilds are DELETE+INSERT inside a single transaction, so a
  /// kill mid-rebuild leaves the previous view fully intact (K11). Kept in
  /// course.db (not the catalog) because it is course-tree-shaped derived
  /// data, wipe-safe on downgrade like every other row here.
  static Future<void> _ensureV2CourseTreeView(
    GeneratedDatabase database,
  ) async {
    await database.customStatement('''
      CREATE TABLE IF NOT EXISTS anki_course_tree_view (
        source_id TEXT NOT NULL,
        card_id INTEGER NOT NULL,
        note_id INTEGER NOT NULL,
        deck_id INTEGER NOT NULL,
        word_id TEXT NOT NULL,
        section_key TEXT NOT NULL,
        section_id TEXT NOT NULL,
        unit_id TEXT NOT NULL,
        lesson_id TEXT NOT NULL,
        lesson_key TEXT NOT NULL,
        presentation_kind TEXT NOT NULL,
        source_hash TEXT NOT NULL,
        mapping_version INTEGER NOT NULL,
        rebuilt_at_millis INTEGER NOT NULL,
        PRIMARY KEY(source_id, card_id)
      )
    ''');
    await database.customStatement('''
      CREATE INDEX IF NOT EXISTS anki_course_tree_view_lesson_idx
      ON anki_course_tree_view(lesson_id, card_id)
    ''');
    await database.customStatement('''
      CREATE INDEX IF NOT EXISTS anki_course_tree_view_section_idx
      ON anki_course_tree_view(section_id)
    ''');
  }

  /// Canonical introduction state and study product events.
  static Future<void> _ensureAnkiUnificationTables(
    GeneratedDatabase database,
  ) async {
    await database.customStatement('''
      CREATE TABLE IF NOT EXISTS anki_card_introduction_states (
        course_id TEXT NOT NULL,
        source_id TEXT NOT NULL,
        card_id INTEGER NOT NULL,
        status TEXT NOT NULL,
        introduced_by TEXT,
        introduced_at INTEGER,
        first_lesson_id TEXT,
        last_studied_at INTEGER,
        version INTEGER NOT NULL DEFAULT 1,
        PRIMARY KEY(course_id, source_id, card_id)
      )
    ''');
    await database.customStatement('''
      CREATE TABLE IF NOT EXISTS study_product_events (
        event_id TEXT PRIMARY KEY NOT NULL,
        idempotency_key TEXT NOT NULL UNIQUE,
        course_id TEXT NOT NULL,
        source_id TEXT NOT NULL,
        card_id INTEGER NOT NULL,
        ledger_owner TEXT NOT NULL,
        mode TEXT NOT NULL,
        outcome TEXT NOT NULL,
        native_event_ref TEXT,
        reviewed_at INTEGER NOT NULL,
        next_due_at INTEGER,
        session_id TEXT,
        undone_at INTEGER,
        effects_state TEXT NOT NULL DEFAULT 'applied'
      )
    ''');
  }

  static Future<void> _ensureFunLabSnapshotTables(
    GeneratedDatabase database,
  ) async {
    await database.customStatement('''
      CREATE TABLE IF NOT EXISTS fun_lab_snapshot_meta (
        id INTEGER PRIMARY KEY CHECK (id = 1),
        created_at INTEGER NOT NULL,
        content_fingerprint TEXT NOT NULL,
        prefs_json TEXT NOT NULL,
        srs_item_count INTEGER NOT NULL DEFAULT 0
      )
    ''');
    await database.customStatement('''
      CREATE TABLE IF NOT EXISTS fun_lab_snapshot_srs (
        word_id TEXT PRIMARY KEY,
        queue TEXT NOT NULL,
        due_at INTEGER NOT NULL,
        interval_days INTEGER NOT NULL,
        ease REAL NOT NULL,
        reps INTEGER NOT NULL,
        lapses INTEGER NOT NULL,
        is_leech INTEGER NOT NULL,
        is_suspended INTEGER NOT NULL,
        is_buried INTEGER NOT NULL,
        type TEXT NOT NULL,
        last_reviewed_at INTEGER,
        stability REAL,
        difficulty REAL,
        fsrs_state INTEGER NOT NULL,
        learning_step INTEGER,
        source_kind TEXT,
        source_id TEXT,
        owner_id TEXT
      )
    ''');
    await database.customStatement('''
      CREATE TABLE IF NOT EXISTS fun_lab_snapshot_review_events (
        id INTEGER PRIMARY KEY,
        card_id TEXT NOT NULL,
        queue TEXT NOT NULL,
        reviewed_at INTEGER NOT NULL,
        quality INTEGER NOT NULL,
        prev_interval_days INTEGER NOT NULL,
        next_interval_days INTEGER NOT NULL,
        prev_ease REAL NOT NULL,
        next_ease REAL NOT NULL,
        reps INTEGER NOT NULL,
        lapses INTEGER NOT NULL,
        type TEXT NOT NULL,
        source_key TEXT,
        source_kind TEXT,
        source_id TEXT,
        owner_id TEXT
      )
    ''');
    await database.customStatement('''
      CREATE TABLE IF NOT EXISTS fun_lab_snapshot_anki_state (
        import_id TEXT NOT NULL,
        card_id INTEGER NOT NULL,
        suspended INTEGER NOT NULL,
        buried_until INTEGER,
        marked INTEGER NOT NULL,
        flag INTEGER NOT NULL,
        PRIMARY KEY (import_id, card_id)
      )
    ''');
  }

  static Future<void> _addAnkiStateColumns(GeneratedDatabase database) async {
    Future<void> addColumn(
        String table, String column, String definition) async {
      final columns =
          await database.customSelect('PRAGMA table_info($table)').get();
      if (columns.any((row) => row.read<String>('name') == column)) return;
      await database.customStatement(
        'ALTER TABLE $table ADD COLUMN $column $definition',
      );
    }

    await addColumn('anki_imports', 'daily_new_limit', 'INTEGER');
    await addColumn('anki_imports', 'daily_review_limit', 'INTEGER');
    await addColumn(
      'anki_cards_meta',
      'suspended',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await addColumn('anki_cards_meta', 'buried_until', 'INTEGER');
    await addColumn('anki_cards_meta', 'marked', 'INTEGER NOT NULL DEFAULT 0');
    await addColumn('anki_cards_meta', 'flag', 'INTEGER NOT NULL DEFAULT 0');
  }

  static Future<void> _ensureAnkiCanonicalV2(
    GeneratedDatabase database,
  ) async {
    Future<void> addColumn(
      String table,
      String column,
      String definition,
    ) async {
      final columns =
          await database.customSelect('PRAGMA table_info($table)').get();
      if (columns.any((row) => row.read<String>('name') == column)) return;
      await database.customStatement(
        'ALTER TABLE $table ADD COLUMN $column $definition',
      );
    }

    await addColumn(
      'anki_imports',
      'status',
      "TEXT NOT NULL DEFAULT 'complete'",
    );
    await addColumn(
      'anki_imports',
      'source_card_count',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await addColumn(
      'anki_imports',
      'stored_card_count',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await addColumn(
      'anki_imports',
      'indexed_card_count',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await addColumn(
      'anki_imports',
      'imported_scheduling',
      'INTEGER NOT NULL DEFAULT 0',
    );
    await addColumn('anki_imports', 'last_error', 'TEXT');

    // v24 (step6.md) dropped the v1 projection tables this helper used to
    // create (`anki_decks`, `anki_practice_projections`,
    // `anki_import_issues`); only the raw-SQL columns and indexes that the
    // drift schema does not model survive here.
    await database.customStatement('''
      CREATE INDEX IF NOT EXISTS anki_cards_meta_note_idx
      ON anki_cards_meta(import_id, note_id)
    ''');
    await database.customStatement('''
      CREATE INDEX IF NOT EXISTS anki_cards_meta_deck_idx
      ON anki_cards_meta(import_id, did)
    ''');
    await database.customStatement('''
      CREATE UNIQUE INDEX IF NOT EXISTS anki_cards_meta_word_idx
      ON anki_cards_meta(word_id)
    ''');
    await database.customStatement('''
      CREATE INDEX IF NOT EXISTS anki_notes_guid_idx
      ON anki_notes(import_id, guid)
    ''');
  }

  /// Re-key Anki SRS rows from the pre-pivot note-based word id
  /// (`anki-<importId>-n<noteId>`) to the card-level
  /// `anki-<importId>-c<cardId>` (decision 2). Before this pivot, SRS state
  /// and review history were keyed by note id; the card-level
  /// [AnkiSrsMigrator] change orphaned them (the review assembler extracts the
  /// import id via `lastIndexOf('-c')`, returning '' for `-n` ids, so they
  /// dropped out of due counts and could not resolve to an interaction). This
  /// one-time migration uses the authoritative `anki_cards_meta`
  /// (import_id, note_id) -> word_id mapping to re-key `srs_states.word_id`
  /// and `review_events.card_id`. Unresolvable rows (deck already unloaded)
  /// are left untouched rather than deleted.
  static Future<void> _rekeyLegacyAnkiWordIds(
    GeneratedDatabase database,
  ) async {
    final meta = await database
        .customSelect(
          'SELECT import_id, note_id, word_id FROM anki_cards_meta',
        )
        .get();
    // (importId, noteId) -> new card-level wordId.
    final noteToWord = <String, String>{};
    for (final row in meta) {
      noteToWord[
              '${row.read<String>('import_id')}|${row.read<int>('note_id')}'] =
          row.read<String>('word_id');
    }
    await _rekeyLegacyColumn(
      database,
      'srs_states',
      'word_id',
      noteToWord,
      isPrimaryKey: true,
    );
    await _rekeyLegacyColumn(
      database,
      'review_events',
      'card_id',
      noteToWord,
      isPrimaryKey: false,
    );
  }

  static Future<void> _rekeyLegacyColumn(
    GeneratedDatabase database,
    String table,
    String column,
    Map<String, String> noteToWord, {
    required bool isPrimaryKey,
  }) async {
    final legacy = await database
        .customSelect(
          "SELECT $column AS id FROM $table "
          "WHERE $column LIKE 'anki-%' AND $column LIKE '%-n%'",
        )
        .get();
    for (final row in legacy) {
      final legacyId = row.read<String>('id');
      final parsed = _parseLegacyAnkiWordId(legacyId);
      if (parsed == null) continue;
      final newId = noteToWord['${parsed.importId}|${parsed.noteId}'];
      if (newId == null || newId == legacyId) continue;
      if (isPrimaryKey) {
        // srs_states.word_id is the PK: if the target card-level row already
        // exists (e.g. the deck was re-imported after the pivot), drop the
        // legacy row instead of colliding on the PK.
        final exists = await database.customSelect(
          'SELECT 1 FROM $table WHERE $column = ? LIMIT 1',
          variables: [Variable.withString(newId)],
        ).get();
        if (exists.isNotEmpty) {
          await database.customStatement(
            'DELETE FROM $table WHERE $column = ?',
            [legacyId],
          );
          continue;
        }
      }
      await database.customStatement(
        'UPDATE $table SET $column = ? WHERE $column = ?',
        [newId, legacyId],
      );
    }
  }

  /// Parse a legacy note-based Anki word id (`anki-<importId>-n<noteId>`).
  /// `importId` is `anki_import_<ms>` (no hyphens), so the single `-n`
  /// separates importId from noteId. Returns null for non-legacy (card-level)
  /// ids or anything that does not parse.
  static ({String importId, int noteId})? _parseLegacyAnkiWordId(
    String wordId,
  ) {
    const prefix = 'anki-';
    if (!wordId.startsWith(prefix)) return null;
    final nIdx = wordId.lastIndexOf('-n');
    if (nIdx <= prefix.length) return null;
    final importId = wordId.substring(prefix.length, nIdx);
    final noteId = int.tryParse(wordId.substring(nIdx + 2));
    if (noteId == null) return null;
    return (importId: importId, noteId: noteId);
  }
}
