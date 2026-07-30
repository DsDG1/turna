# 05. 数据层（Data Layer）

> 路径：`lib/data/`
>
> 数据层负责把 Domain 接口落到具体存储上。本项目使用 **Drift (SQLite)** 作为课程内容、Anki 导入、SRS 状态的持久化层；**StreamingSharedPreferences** 作为小型键值与 StudyLog 的存储。

---

## 5.1 文件总览

| 文件 | 职责 |
|---|---|
| [`course_database.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/data/course_database.dart) | Drift `@DriftDatabase` 定义 + 全部 Table + Migration |
| [`course_database.g.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/data/course_database.g.dart) | drift_dev 生成代码（不要手改） |
| [`course_database_seeder.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/data/course_database_seeder.dart) | 从 `assets/courses/turkish/` seed DB；版本比对触发 reseed |
| [`course_repository.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/data/course_repository.dart) | `CourseRepository` 实现 `ICourseRepository` |
| [`study_log_repository.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/data/study_log_repository.dart) | `StudyLogRepository` 实现 `IStudyLogRepository`（SharedPreferences 存储） |
| [`srs_state_dao.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/data/srs_state_dao.dart) | `SrsStates` 表的 DAO |
| [`review_history_dao.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/data/review_history_dao.dart) | `ReviewEvents` 表的 DAO |
| [`anki_import_dao.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/data/anki_import_dao.dart) | `AnkiImports` 表的 DAO |
| [`rdb_query_executor.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/data/rdb_query_executor.dart) | 跨平台的 Drift `QueryExecutor` 工厂 |

---

## 5.2 Schema 设计

### 5.2.1 Schema 版本：v8

当前 `schemaVersion = 8`（[`course_database.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/data/course_database.dart#L232)）。

**Schema 演进历史**：

| 版本 | 内容 | 触发场景 |
|---|---|---|
| v1 | 基础 sections/units/lessons/lesson_contents/vocabulary/grammar_points | 初始 |
| v2 | `grammar_points` 表（不带 practiceItems） | |
| v3 | `grammar_points.practiceItems` 列（JSON） | |
| v4 | `course_meta` 表（contentVersion 缓存） | reseed 决策 |
| v5 | `expressions` 表（多词表达） | 表达级 SRS |
| v6 | `anki_imports` 表 + `sections.level` 列（CEFR / "Anki" 标记） | Anki 导入 |
| v7 | `srs_states` + `review_events` 表（SRS 状态从 prefs 迁移） | 规模化 SRS |
| v8 | `srs_states` 增加 FSRS 字段（`stability`、`difficulty`、`fsrsState`、`learningStep`） | ADR 0028 |

### 5.2.2 表清单

| Table | 类 | 主键 | 关键列 |
|---|---|---|---|
| `sections` | [`Sections`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/data/course_database.dart#L21) | `id` | name, level, prerequisiteSectionIds (JSON), sortOrder |
| `units` | [`Units`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/data/course_database.dart#L35) | `id` | sectionId (FK), name, prerequisiteUnitIds, sortOrder |
| `lessons` | [`Lessons`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/data/course_database.dart#L51) | `id` | unitId (FK), name, type, template, prerequisiteLessonIds |
| `lesson_contents` | [`LessonContents`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/data/course_database.dart#L71) | `lessonId` | contentJson（**完整 LessonContent JSON blob**） |
| `vocabulary` | [`Vocabulary`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/data/course_database.dart#L82) | `id` | term, translation, pronunciation, audioAsset, tags |
| `grammar_points` | [`GrammarPoints`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/data/course_database.dart#L97) | `id` | title, explanation, exampleExpressionIds, practiceItems (JSON) |
| `course_meta` | [`CourseMeta`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/data/course_database.dart#L112) | `key` | value |
| `expressions` | [`Expressions`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/data/course_database.dart#L121) | `id` | term, translation, audioAsset, tags |
| `anki_imports` | [`AnkiImports`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/data/course_database.dart#L139) | `importId` | sourcePath, sourceHash, importedAt, deckCount, notetypesJson, aiEnhanced, version |
| `srs_states` | [`SrsStates`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/data/course_database.dart#L166) | `wordId` | queue（'srs'/'grammar'）, dueAt, intervalDays, ease, reps, lapses, isLeech, type, lastReviewedAt, stability, difficulty, fsrsState, learningStep |
| `review_events` | [`ReviewEvents`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/data/course_database.dart#L198) | `id` (auto) | cardId, queue, reviewedAt, quality, prev/nextIntervalDays, prev/nextEase, reps, lapses, type |

### 5.2.3 关键索引

```dart
@TableIndex(name: 'review_events_card_idx', columns: {#cardId})
@TableIndex(name: 'review_events_time_idx', columns: {#reviewedAt})
class ReviewEvents extends Table { ... }
```

### 5.2.4 JSON 编码列

下列列以 JSON 字符串存储 list/small structure（小数据量时可避免连接表）：

- `prerequisiteSectionIds` / `prerequisiteUnitIds` / `prerequisiteLessonIds`
- `tags`（vocabulary, expressions）
- `exampleExpressionIds` / `exampleSentenceIds` / `practiceItems`（grammar_points）
- `contentJson`（lesson_contents — 完整 LessonContent）

> 这是 v1 trade-off；未来 schema bump 可改用 join 表。

---

## 5.3 Migration 策略

[`MigrationStrategy`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/data/course_database.dart#L235) 的关键设计：

```dart
@override
MigrationStrategy get migration => MigrationStrategy(
  onCreate: (m) async => await m.createAll(),
  onUpgrade: (m, from, to) async {
    if (from > to) {
      // App 降级：DB schema 比代码新 → wipe + createAll
      // 因为 DB 是 reseedable 的派生缓存，这样做安全
      for (final tableName in [...所有表...]) {
        await m.deleteTable(tableName);
      }
      await m.createAll();
      return;
    }
    if (from < 2) { /* v2 */ }
    if (from < 3) { /* v3 */ }
    ...
    if (from < 8) { /* v8 - FSRS 字段 */ }
  },
);
```

**降级安全**：DB 是从 JSON 派生的可 reseed 缓存，因此降级时 wipe + recreate 不会丢用户数据（用户进度在 prefs 与 srs_states 表中，reseed 不会触碰）。

---

## 5.4 CourseRepository 实现

[`course_repository.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/data/course_repository.dart) 实现 [`ICourseRepository`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/repositories/i_course_repository.dart) 接口。

### 5.4.1 三级加载（L0 / L1 / L2）

```dart
@LazySingleton(as: ICourseRepository)
class CourseRepository implements ICourseRepository {
  final db.CourseDatabase database;

  /// L0: 轻量 section shells（units 为空）
  @override
  Future<List<Section>> sectionShells();

  /// L1: section 树（units + lessons 元数据，content 为空）
  @override
  Future<Section> section(String id);

  /// L2: 完整 LessonContent
  @override
  Future<Lesson> lessonById(String id);
}
```

**为什么分级**：~10k lessons 时，启动时反序列化全部 LessonContent JSON 会卡顿。L0 仅用于课程树首页；L1 用于展开 section；L2 仅在用户进入 lesson 时按需加载。

### 5.4.2 Bulk 写入

```dart
@override
Future<void> bulkInsertCourseTree(Section section);   // 事务式 upsert
@override
Future<void> bulkInsertVocabulary(List<WordEntry> words);
@override
Future<int> deleteByTag(String tag);                   // Anki 卸载
@override
Future<void> deleteSection(String sectionId);
```

---

## 5.5 SrsStateDao

[`srs_state_dao.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/data/srs_state_dao.dart) — `srs_states` 表的 DAO。

```dart
@lazySingleton
class SrsStateDao {
  final CourseDatabase _db;

  Future<Map<String, SrsWord>> loadQueue(String queue);     // 启动时 hydrate
  Future<void> upsert(String queue, SrsWord word);          // 写穿透
  Future<void> upsertBatch(String queue, Iterable<SrsWord>); // Anki bulk import
  Future<void> delete(String wordId);
  Future<void> deleteByPrefix(String prefix);               // Anki 卸载
  Future<void> clearQueue(String queue);                    // content update reset
  Future<List<SrsWord>> recentReviews({                    // AI tutor context
    String queue = 'srs',
    int limit = 20,
    DateTime? since,
  });
}
```

**写穿透策略**：SrsQueueProvider 持有内存 `Map<String, SrsWord>` 缓存（用于同步读取），每次更新通过 `dao.upsert()` 同步写 SQLite。`ensureLoaded()` 时一次性 hydrate。

---

## 5.6 ReviewHistoryDao

[`review_history_dao.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/data/review_history_dao.dart) — `review_events` 表的 DAO（每张卡的复习历史）。

```dart
@lazySingleton
class ReviewHistoryDao {
  final CourseDatabase _db;

  Future<void> insertEvent(ReviewEventRecord event);     // 单条
  Future<void> insertBatch(Iterable<ReviewEventRecord>); // Anki revlog migration
  Future<List<ReviewEventRecord>> eventsForCard(String cardId);
  Future<List<ReviewEventRecord>> recentEvents({int limit = 500});
}
```

**不清理历史**：遗忘曲线模型需要完整 review_events 历史来计算保留率。

---

## 5.7 DatabaseSeeder

[`course_database_seeder.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/data/course_database_seeder.dart) — 从 `assets/courses/turkish/` seed DB。

### 5.7.1 Reseed 决策

```dart
class DatabaseSeeder {
  static const String metaContentVersion = 'contentVersion';

  Future<bool> seedIfNeeded() async {
    // 读取 bundle 中 index.json + expressions.json 的 version
    final assetVersion = '$indexVersion+$expressionsVersion';

    final storedVersion = await _readMeta(metaContentVersion);
    final existingSections = await (db.select(db.sections)..limit(1)).get();
    final hasSections = existingSections.isNotEmpty;

    // 跳过条件：version 匹配 AND sections 已存在
    if (storedVersion == assetVersion && hasSections) {
      return false;
    }
    // 否则：clear + full seed
    await _clearCourseTables();
    CourseLoader.invalidateCaches();
    // ... seed
  }
}
```

**复合版本号**：`indexVersion + expressionsVersion`。任一文件 version 变化都触发 reseed。

### 5.7.2 写入策略

每次写入**先清空**课程相关表，再 INSERT：

```dart
Future<void> _clearCourseTables() async {
  await db.transaction(() async {
    await db.delete(db.lessonContents).go();
    await db.delete(db.lessons).go();
    await db.delete(db.units).go();
    await db.delete(db.sections).go();
    await db.delete(db.vocabulary).go();
    await db.delete(db.grammarPoints).go();
    await db.delete(db.expressions).go();
  });
}
```

---

## 5.8 StudyLogRepository

[`study_log_repository.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/data/study_log_repository.dart) — 实现 [`IStudyLogRepository`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/domain/repositories/i_study_log_repository.dart)。

### 5.8.1 存储位置

**SharedPreferences**（不是 SQLite）。StudyLog 是高写入频率的"近期事件流"，适合 KV 存储。

### 5.8.2 追加策略（ADR 0012）

```dart
static const int _maxLogDays = 90;
static const int recentCap = 200;  // 增量队列阈值

@override
Future<void> appendLog(StudyLog log) async {
  await _enqueueWrite(() async {
    final recent = await _readRecentLogs();
    recent.add(log);
    _purgeOldLogs(recent);
    if (recent.length >= recentCap) {
      await _mergeRecentIntoMain(recent);   // 合并到主日志
    } else {
      await _writeRecentLogs(recent);       // 写入增量队列
    }
    await _updateDailyStats(log);
  });
}
```

**双 blob 设计**：
- `study.logs`：主日志（最近 90 天）
- `study.logs.recent`：增量队列（≤200 条），`readLogs()` 自动合并两个 blob

**避免每次都重写 90 天 JSON blob**。

### 5.8.3 写入串行化

```dart
Future<void> _writeChain = Future.value();

Future<void> _enqueueWrite(Future<void> Function() op) async {
  final completer = Completer<void>();
  final prev = _writeChain;
  _writeChain = completer.future;
  try {
    await prev;
    await op();
    completer.complete();
  } catch (e, st) {
    completer.completeError(e, st);
  }
}
```

**防止并发写 SharedPreferences** 时的 read-modify-write 竞争（参考 `LessonLinkStore._writeChain`）。

---

## 5.9 AnkiImportDao

[`anki_import_dao.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/data/anki_import_dao.dart) — `anki_imports` 表的 DAO。

记录每次 Anki deck 导入的元数据：

- `sourcePath` / `sourceHash`（增量更新检测）
- `notetypesJson`（notetype 定义 + 映射决策，重导入可复用）
- `deckCount` / `noteCount` / `cardCount` / `mediaCount`
- `aiEnhanced`（是否经过 AI 增强）
- `version`

---

## 5.10 跨平台 QueryExecutor

[`rdb_query_executor.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/data/rdb_query_executor.dart) — 根据平台返回合适的 Drift `QueryExecutor`：

| 平台 | 实现 |
|---|---|
| Android / iOS / macOS | `NativeDatabase`（sqlite3_flutter_libs） |
| Windows / Linux | `NativeDatabase` + 文件路径 |
| Web | `WasmDatabase`（仅 dev/test） |
| OHos | 通过 dependency_overrides 适配 |

---

## 5.11 数据流：写入与读取

### 5.11.1 课程内容

```
写:  bundle/index.json → CourseLoader → DatabaseSeeder → SQLite tables
读:  CourseProvider → CourseRepository → SQLite → Freezed models
```

### 5.11.2 SRS 状态

```
读:  SrsQueueProvider._cachedState (内存) ← SrsStateDao.loadQueue() (启动)
写:  reviewItem() → 内存 cache + SrsStateDao.upsert() (穿透)
```

### 5.11.3 StudyLog

```
写:  StudyStatsProvider.recordActivity() → StudyLogRepository.appendLog()
      → 增量队列 / 主日志 / 每日聚合
读:  StudyStatsProvider → StudyLogRepository.readLogs() / readLastNDays()
```

### 5.11.4 错题本

**特殊**：错题本**不存储在 SQLite**，而是 SharedPreferences 的 JSON blob（[`mistake_provider.dart`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/lib/application/mistake_provider.dart)）。小数据量、临时，FIFO 用 list add + removeAt(0) 即可。