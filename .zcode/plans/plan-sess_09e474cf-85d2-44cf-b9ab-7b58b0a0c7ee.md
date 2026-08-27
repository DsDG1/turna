## 修复方案：CardIntroductionStore 冷启动回灌（从账本重建 introduced 集合）

### 根因回顾
`CardIntroductionStore` 把 introduced 状态持久化到 `anki_card_introduction_states` 表，但从不读回：App 重启后内存集合 `_introduced` 为空，而正式复习的资格交集 `schedulerDue ∩ activePlacement ∩ introduced − …` 依赖它 → 所有到期卡被过滤 → 「暂无待复习的 Anki 卡片」。调时间只影响 `schedulerDue`，改不了空的 introduced 集合，故无效。设计文档 `docs/anki-maintainability-cleanup/01-due-state.md:81`（「冷启动由完整 due sync 从 ledger 重建 introduced 状态」）描述的契约从未实现。

已确认：内存集合的全部生产消费方（loader:184、snapshot builder:59）都走 `CardIntroductionStore`，回灌内存一处即覆盖全部；课程数据库在 `setupLocator()` 内打开且先于 `runApp`，启动期回灌可行。

### 代码改动（5 个文件）

1. **`lib/data/anki_unification_dao.dart`** — 新增查询方法 `allIntroductionRefs()`：`SELECT source_id, card_id, status FROM anki_card_introduction_states`，返回 `List<({String sourceId, int cardId, CardIntroductionStatus status})>`。

2. **`lib/application/anki_official/introduction/card_introduction_store.dart`** — 新增公开方法 `hydrateFromLedger()`：
   - 语义：幂等合并（只增不删），从 DAO 读全部 introduced 行，把 `card:$sourceId:$cardId` token 并入 `_introduced`（这是 `introducedCardIdsForSource` 唯一认的 token 格式），随后从 card token 重建 `_introducedBySource` 保证计数精确；
   - 用 `Future<void>? _hydrationInFlight` 做并发去重（仿 `OfficialAnkiHomeDueSync.refresh()` 模式）；失败吞掉并允许下次重试（回灌失败不阻塞业务，下次调用重试）；
   - `_dao == null`（测试 fallback 实例）直接 no-op；
   - 不发 `changes` 事件（回灌是缓存填充而非账本变更；due 快照下次全量刷新自愈）；
   - **只回灌 introduced 行**：`_retired`/retired 行在当前生产中无任何写入方（卸载是硬删行），且 `isFormallyEligibleWord` 按 wordId 匹配无法从 DB 行重建，回灌 retired 是死代码，明确不做。

3. **`lib/service/locator.dart`** — :421 注册后立即 `await getIt<CardIntroductionStore>().hydrateFromLedger();`（启动期一次，DB 此刻刚打开，单条 SELECT 成本可忽略）。

4. **`lib/application/anki_official/review/official_formal_review_production_loader.dart`** — `load()` 开头（flags 检查后、读取 `introducedCardIdsForSource` 的 :184 之前）加 `await CardIntroductionStore.resolve().hydrateFromLedger();`。这是复习会话关键路径的自愈点：即使启动期回灌失败或漏跑，打开复习页时也会补齐。

5. **`lib/application/anki_official/engine/official_anki_home_due_sync.dart`** — `_refreshOnce()` 首行加同一调用，使 Home/Play Hub/Profile 的 due 角标同样在冷启动后恢复正确。

6. **`docs/anki-maintainability-cleanup/01-due-state.md`** — 把 :81 的「冷启动从 ledger 重建」段落更新为已实现的回灌机制描述（store 幂等回灌 + due sync/loader 触发点），使文档与实现一致。

### 测试（3 处）

7. **`test/data/anki_unification_dao_test.dart`** — 扩展覆盖 `allIntroductionRefs()`：经 `upsertIntroduction` 写 introduced/unintroduced/retired 三种行，断言映射正确。

8. **新建 `test/application/anki_official/card_introduction_store_hydration_test.dart`**（模式：`emptyInMemoryCourseDatabase()` + `AnkiUnificationDao(db)`，参照 `test/data/anki_unification_dao_test.dart:14-17`）：
   - 回灌修复回归：向 DB 写 2 个 source 的 introduced 行 → 新建带 DAO 的 store（模拟重启）→ `introducedCardIdsForSource` 先断言为空（bug 复现）→ `hydrateFromLedger()` 后按 source 返回正确集合；
   - 幂等/合并：连续 hydrate 两次、穿插 `markFromLesson`，集合与计数无重复无丢失；
   - 无 DAO 的 store：no-op 不抛错。

9. **新建 loader 回归测试**（仿 `test/views/anki/anki_review_session_official_path_test.dart` 的 harness：`FakeOfficialAnkiEngine.seedPackage` + `resolveTarget`/`sessionFactory`/`presentationsForCards` seams，**不传** `introducedCardIds` override 走生产读取路径）：
   - `CardIntroductionStore.debugOverride` 指向带 DAO 的新 store 实例，DB 里只有 introduced 行（无内存标记）→ `loader.load()` 必须返回 `OfficialFormalReviewReady`（修复前返回 NoDue，即本 bug 的最小复现）。

### 验证与收尾

- `flutter analyze`（基线：4 个预存 info，不得新增）；
- 定向跑新增/受影响测试：`flutter test test/data/anki_unification_dao_test.dart test/application/anki_official/card_introduction_store_hydration_test.dart test/views/anki/anki_review_session_official_path_test.dart test/application/anki_official/official_formal_due_card_ids_sync_test.dart test/application/anki/card_introduction_eligibility_test.dart`；
- 手工验收路径：做错一张卡 → 杀 App → 时间调过到期点（>10 分钟）→ 重启进复习，应出卡且复习中心角标计数恢复。

### 明确不做 / 后续项（不在本次范围）

- **第二缺口**：官方导入时自带复习历史（reps>0/revlog）的卡一律 seed 成 `unintroduced`，`CardIntroducedBy.importedHistory` 从不写入 → 这类卡在任何首复都不会出现。修复应落在导入发布链路（`official_anki_projection_store.dart:238` 附近：查集合中带历史的卡并 upsert introduced）或 loader 的 revlog 兜底，涉及原生查询面设计，单独立项。
- `retired` 行回灌、`CardIntroductionRepository.retire`（无实现无调用）、`study_session_controller` 的 `markIntroduced` 死路径：均不动。
- 不改 native/rslib（时间语义已验证正确）。