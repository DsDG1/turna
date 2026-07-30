# Plan: 智能 Anki 卡片对接 + 完善记忆曲线

> 两条工作流，共享同一套底层改动（SQLite 化的 SRS + 逐卡复习历史）。
> A = Anki 智能对接（对应到 Anki 自身结构，低风险）；B = 记忆曲线完整模型 + SQLite 化（重路径，用户已选）。

## 目标

1. **Anki 智能对接**：导入时用 Anki 的**标签 / 牌组层级 / notetype 字段**把卡片组织成有意义的 Unit/Lesson（取代现在固定 20 张切片 `Deck #1/#2`），并在预览页展示识别到的组织结构。同时解析 Anki `revlog` 复习日志，迁移为历史复习事件。
2. **记忆曲线完整模型**：把 SRS 状态从 `StreamingSharedPreferences` JSON blob 迁移到 SQLite（schema v6→v7）；新增逐卡复习历史表；实现遗忘曲线/保留率模型（FSRS 风格 `R = e^{-Δt/S}`）+ 到期预测 + 成熟度分布；用 `fl_chart` 可视化；修复 SRS 准确率记录 bug。

---

## 现状关键事实（来自探索）

- `SrsQueueProvider`（基类，`srs_queue_provider.dart`）的 `state` 是同步 `Map<String,SrsWord>`，**所有消费者同步**（`dueCount`/`getDueWords()`/`context.select`）。`persist()`（:219）是唯一写钩子，notify-then-write。
- SRS 状态在 prefs blob：`srs.state`、`grammarReview.state`（`LocalStateKeys`，locator.dart:131/139）。`SrsWord`（srs_word.dart）**无 `lastReviewedAt`**，只有 `dueAt`。
- `Sm2Engine.review()`（sm2.dart:39）返回新 `SrsWord`（不就地修改），但内部用 `DateTime.now()` + 共享 RNG fuzz。
- SQLite（Drift）`course_database.dart`：`schemaVersion=6`，`onUpgrade` 用 `if(from<N)` 级联；降级时按表名 wipe 再 `createAll`（:191-201）。SRS **无表**。
- DAO 约定：`@lazySingleton` + `final CourseDatabase _db` + 普通 DTO（如 `AnkiImportRecord`），**不用** `@DriftAccessor`。`CourseDatabase` 是 eager singleton（setupLocator:203），DAO lazy。
- `AnkiNote.tags` 已是 `String`（空格分隔，anki_models.dart:90），importer 已读取（anki_importer.dart:283），但 assembler **完全没用**。
- `AnkiDeckAssembler` 固定 20 张/Lesson，`'$deckName #$chunkNum'`（anki_deck_assembler.dart:41/296）。`AnkiCard` Interaction 无 tags 字段（interaction.dart:152）。
- `revlog` **未解析**；`AnkiSrsMigrator.migrate()` 只接收 `List<AnkiCardData>`，无复习事件输出。
- 准确率 bug：`srs_review_screen.dart:105-106` 把每次 SRS 复习都记为 `correctCount=reviewedCount, incorrectCount=0`。
- 无图表库；`learning_stats.dart` 的 `_WeeklyXpBars` 是纯 `Container` 矩形。

---

## Phase 0 — 前置与清理

- `pubspec.yaml`：新增 `fl_chart: ^0.69.0`（纯 Dart canvas，无原生通道，OHos fork 可用；构建时验证）。
- 清理死代码：移除 `ICourseRepository.recordAnkiImport` / `CourseRepository.recordAnciImport` / 测试 fake 中的桩（工作树重构遗留，已无调用方）。
- 跑一次 `flutter pub run build_runner build --delete-conflicting-outputs` 基线，确认当前工作树可生成。

## Phase 1 — SRS 状态 SQLite 化（schema v7 第 1 部分）

**新增表 `SrsStates`**（course_database.dart，镜像 `AnkiImports` 表写法）：
```
wordId TEXT PK, queue TEXT('srs'|'grammar'), dueAt INTEGER(millis),
intervalDays INTEGER, ease REAL, reps INTEGER, lapses INTEGER,
isLeech INTEGER, type TEXT('word'|'expression'), lastReviewedAt INTEGER NULL
```
- 加进 `@DriftDatabase(tables:[...])`；`schemaVersion` 6→7；`onUpgrade` 加 `if(from<7){ await m.createTable(srsStates); await m.createTable(reviewEvents); }`；降级 wipe 列表加 `'srs_states','review_events'`。
- `SrsWord` 加 `DateTime? lastReviewedAt`（freezed 3.x `@freezed abstract class`，regen）。

**新增 `SrsStateDao @lazySingleton`**（镜像 `AnkiImportDao`）：`Future<Map<String,SrsWord>> loadQueue(String queue)`、`upsert(String queue, SrsWord)`、`upsertBatch(...)`、`delete(String wordId)`、`deleteByPrefix(String prefix)`、`clear(String queue)`。普通 DTO 不需要（直接用 `SrsWord`，因 freezed 已是数据类）。

**重构 `SrsQueueProvider`**（保持同步语义）：
- 构造函数加 `SrsStateDao`：`SrsQueueProvider(this.appPrefs, this.linkStore, this.srsDao)`。
- 新增抽象 `String get queueId`（'srs' / 'grammar'）。
- `state` getter 仍返回内存 `_cachedState`；新增 `Future<void> ensureLoaded()`：从 DAO `loadQueue(queueId)` 灌入 `_cachedState`（仅首次）。
- `persist`/`importStates`/`removeItemsByPrefix`/`clear`：更新内存 cache + notify（同步，不变），然后**写穿**到 DAO（fire-and-forget，沿用现在的 log-and-never-rethrow 降级语义）。
- `reviewItem`：更新 SrsWord 时写入 `lastReviewedAt = DateTime.now()`。
- `SrsProvider`/`GrammarReviewProvider`：加 `queueId` override；构造函数透传 DAO（DI regen）。

**一次性数据迁移**（post-DI，main.dart/setupLocator 在 `configureDependencies()` 之后）：
- `migrateSrsStateToSqlite()`：检查 prefs flag `srs.migratedToSqlite`；若未迁移，读 `srs.state`/`grammarReview.state` 旧 blob，`upsertBatch` 写入 `SrsStates`（`lastReviewedAt=null`），置 flag；然后 `await getIt<SrsProvider>().ensureLoaded()` + `GrammarReviewProvider`。
- 在 `CourseReadyGuard` 放行前的启动路径调用（DB 已 open+seed）。

**测试**：`test/data/srs_state_dao_test.dart`（in-memory DB 往返，参照 `test/helpers/in_memory_course_db.dart`）；`test/data/schema_migration_test.dart` 加 v6→v7（断言新表空表创建，加 v8 stub）；`test/application/srs_provider_sqlite_test.dart`（hydrate + 写穿）；更新现有 srs/grammar 测试以注入 DAO。

## Phase 2 — 逐卡复习历史 + 准确率修复（schema v7 第 2 部分）

**新增表 `ReviewEvents`**：
```
id INTEGER PK AUTOINCREMENT, cardId TEXT, queue TEXT,
reviewedAt INTEGER(millis), quality INTEGER(0-5),
prevIntervalDays INTEGER, nextIntervalDays INTEGER,
prevEase REAL, nextEase REAL, reps INTEGER, lapses INTEGER, type TEXT
```
索引 `cardId`、`reviewedAt`。

**`ReviewHistoryDao @lazySingleton`**：`insertEvent(ReviewEventRecord)`、`eventsForCard(cardId)`、`recentEvents({limit, since})`、`allEvents()`、`deleteByPrefix(prefix)`（Anki 卸载时清历史）。普通 DTO `ReviewEventRecord`。

**写事件**：`SrsQueueProvider.reviewItem` 在算出 `updated` 后，构造 `ReviewEventRecord`（prev=word, next=updated）写入 DAO（fire-and-forget）。需把 DAO 注入基类构造函数（与 `SrsStateDao` 一并）。

**准确率修复**（srs_review_screen.dart）：`_onRate` 累加 `_sessionCorrect`/`_sessionIncorrect`（`grade==ReviewGrade.known` → correct++，else incorrect++）；`_grantSessionRewards` 用真实计数替换 `correctCount: reviewedCount, incorrectCount: 0`。

**测试**：`test/data/review_history_dao_test.dart`；扩展 `test/application/srs_review_flow_test.dart` 断言事件落库 + 准确率反映真实 grade。

## Phase 3 — 记忆曲线模型 + 可视化

**`Sm2Engine` 预览**（sm2.dart）：新增 `int previewIntervalDays(SrsWord word, int quality, {Random? random})`——复用 `review()` 逻辑但只返回 `intervalDays`（接受 fuzz 非确定性，或传固定 RNG）。用于复习页「认识 → ~N 天」预览，不落库。

**`MemoryCurveProvider @lazySingleton`**（注入 `ReviewHistoryDao` + `SrsProvider` + `GrammarReviewProvider`），计算：
- **保留率（当前）**：遍历当前 SrsStates，对每卡 `Δt = now - lastReviewedAt`，`S ≈ intervalDays`，`R = exp(-Δt_days / S)`（S≤0 → 1.0）；按卡加权平均得总体保留率。
- **保留率曲线（历史）**：从 `ReviewEvents` 按「距上次复习天数」分桶，算每桶实际召回率（quality≥3 占比）→ 一条 R(t) 散点/曲线。
- **到期预测**：SrsStates 按 `dueAt` 统计未来 1/7/30 天到期数。
- **成熟度分布**：new(reps==0) / young(reps≤2 或 interval<21) / mature(interval≥21) / leech 计数。
- **快照** `MemoryCurveSnapshot`（plain class）一次性返回以上全部，供 UI 单次 `Future` 拉取。

**UI — `_MemoryCurveCard`**（learning_stats.dart，插在 `_WeeklyXpBars` 之后，沿用 `Container`+`cardBg`+`statCardBorder` chrome）：
- `fl_chart` `LineChart`：保留率随时间曲线（历史召回 + 模型曲线叠加）。
- 到期预测：7 日柱状（`BarChart`）或文字 `1d/7d/30d` 计数。
- 成熟度：4 个 chip + 计数。
- State 加 `Future<MemoryCurveSnapshot>? _curveFuture`，`_refreshFutures` 一并刷新（参照 `_overallFuture`）。
- 新 l10n 串：`app_en.arb`/`app_zh.arb` + regen（memoryCurveTitle, retentionLabel, forecastLabel, mature/young/new/leech 等）。

**UI — 复习页下次间隔预览**（srs_review_screen.dart，`_showAnswer` 块内 `ReviewRatingBar` 上方）：显示 `认识 → ~{previewIntervalDays(known)} 天` / `不认识 → 明天`。新 l10n 串。

**测试**：`test/application/memory_curve_provider_test.dart`（保留率数学、预测计数、成熟度分桶）；`test/core/sm2_test.dart` 扩展预览；可选 golden `_MemoryCurveCard`。

## Phase 4 — Anki 智能组织（对应 Anki 自身结构）

**新增 `AnkiOrganizationResolver`**（pure，`lib/application/anki/anki_organization_resolver.dart`）：输入 `AnkiNote` + `AnkiCardData` + `AnkiDeckInfo` + `AnkiNotetype`，输出 `(String unitKey, String lessonKey)`。分层解析：
1. **notetype 字段**：字段名含 `unit/lesson/chapter/单元/课` → 取其字段值。
2. **tags**：匹配 `unit::N` / `lesson::name` / `unit:N` / `chapter:N` / 层级 `foo::bar`（Anki 常见 `tag::subtag` 约定）。
3. **deck 层级**：`Parent::Child::Grand` → 取倒数第二级为 unit、末级为 lesson（保留现有 deck→Section/Unit 骨架时做精化）。
4. **兜底**：返回 `null` → 走原 20 张切片。

**改 `AnkiDeckAssembler`**：
- 在 deck→Unit 骨架基础上，对每个 Unit 内的卡片按 resolver 的 `(unitKey,lessonKey)` 分组生成 Lesson；Lesson 名用 `lessonKey`（而非 `#1`）；同一 lessonKey 超过 20 张仍切片为 `"$lessonKey #2"` 保 `LessonViewModel` 列表有界。
- resolver 全部返回 null 时，退回当前行为（零回归）。
- 给 `wordEntry` 适配路径的 `WordEntry.tags` 追加 note 原始 tags（`['anki:$importId', ...noteTags]`），丰富词典筛选（anki_card_adapter.dart `_adaptWordEntry` :295）。

**预览页**（anki_import_screen.dart `_buildPreviewStep`，:229 Deck structure 卡之后）：新增「Organization」`_InfoCard`——展示识别到的 unit/lesson 分组预览（按 unit 聚合计数）+ 一个 `智能分组/扁平切片` 开关（`_smartGrouping`，默认 true），传入 `assembler.assemble(..., smartGrouping: _smartGrouping)`。

**测试**：`test/anki/anki_organization_resolver_test.dart`（纯函数：字段/tags/deck/兜底各路径）；扩展 `test/anki/anki_deck_assembler_test.dart`（tag 驱动分组、>20 切片、兜底）。

## Phase 5 — Anki revlog 解析与迁移

**模型**（anki_models.dart，镜像 `AnkiCardData` freezed 风格）：`AnkiRevlogEntry{id,cid,usn,ease,ivl,lastIvl,factor,time,type}`；`AnkiCollection` 加 `@Default(<AnkiRevlogEntry>[]) List<AnkiRevlogEntry> revlog`。

**解析**（anki_importer.dart）：新增 `_parseRevlog(db,...)`，镜像 `_parseCards` 分页（`_pageSize=500`，`SELECT id,cid,usn,ease,ivl,lastIvl,factor,time,type FROM revlog ORDER BY id LIMIT ? OFFSET ?`，进度/取消同模式）；在 `_parseCards` 之后、deck 计数之前调用；传入 `AnkiCollection(revlog: revlog, ...)`（:135）。OHos 不支持分支已 throw，revlog 同样不可达，无需特殊处理。

**迁移**（anki_srs_migrator.dart）：`migrate(...)` 加 `required List<AnkiRevlogEntry> revlog`；构建 `cid -> wordId`（经 `cards` 的 `nid`）；遍历 revlog 写 `ReviewEventRecord`：
- `quality`：Anki ease 按钮 1=again→1, 2=hard→3, 3=good→4, 4=easy→5（type=1 learning 的 again 也→1）。
- `prevIntervalDays=lastIvl`，`nextIntervalDays=ivl`，`prevEase/nextEase=factor/1000`，`reviewedAt=DateTime.fromMillisecondsSinceEpoch(time)`，`reps/lapses` 从对应 card 取或留 0。
- 经新 `ReviewHistoryDao.insertEvent` 批量写入（fire-and-forget）。

**向导接线**（anki_import_screen.dart）：`_executeImport` 把 `effectiveCollection.revlog` 传给 `migrator.migrate`（:562）；`skipExisting` 分支的 `copyWith` 同步过滤 revlog（按 cid→nid→已存在 wordId 过滤，:531）。

**测试**：`test/anki/anki_srs_migrator_test.dart` 扩展 revlog→events 映射；importer 解析测试（若有 `.apkg` fixture 则覆盖 revlog，否则单元测 `_parseRevlog` SQL 构造）。

---

## 跨阶段：DI / 代码生成 / 基线

- 所有新 DAO/Provider 加 `@lazySingleton`，构造函数注入 `CourseDatabase`/DAO；跑 `build_runner` regen `injection.config.dart` + freezed/g.dart + drift `.g.dart`。
- 受影响 regen：`srs_word.*`、`anki_models.*`、`course_database.g.dart`、`injection.config.dart`。
- `flutter analyze` + `flutter test` 全绿；更新 `test/BASELINE.md` 计数。
- l10n：所有新用户可见串加 `app_en.arb` + `app_zh.arb` 并 regen `app_localizations*.dart`。
- ADR：新增 `docs/decisions/0021-anki-smart-mapping-and-srs-sqlite.md` 记录 schema v7、prefs→SQLite 迁移、revlog 迁移、组织解析决策。

## 风险与缓解

- **同步消费者**：保留内存 cache 为读源，`ensureLoaded()` 启动预热 + 写穿 DAO，不改任何调用方签名（零 async 扩散）。
- **迁移失败**：flag 门控 + log-and-never-rethrow；旧 prefs blob 保留不删，可重试。
- **OHos**：fl_chart 纯 Dart 可用；revlog/sqlite3 FFI 走现有 OHos 不支持分支。
- **降级兼容**：新表加入 wipe 列表，避免降级 `createAll` 冲突。
- **大牌组**：revlog 可能很大，分页解析 + 批量 insert（单事务），与现有 notes/cards 处理一致。

## 执行顺序

Phase 0 → 1 → 2 → 3 → 4 → 5。每阶段独立可测、可提交。Phase 1/2 是 B 的地基，Phase 3 是 B 的可见产出，Phase 4/5 是 A。建议每个 Phase 结束跑 `flutter test` + `flutter analyze` 并提交。
