# 38 — Anki 集成减负与性能批次一（删码 / 快照失效 / N+1 / 浏览器渲染 / 投影短路）

> 状态：**已施工（2026-08-30，P1–P5 一批完成，P4-B 按计划条件推迟）**。施工明细与偏差见 §12 施工记录；Rust 侧（P1-D/E、P2、P3）本机无 cargo/protoc 静态编写，**待工具链主机 `cargo test -p turna_anki_bridge` + `gen_fixtures` 复验后方可发布**。
> 范围：五个独立施工包 P1–P5：①删除已验证零生产引用的死代码（约 4,000 行）；②修复搜索/投影快照失效缺口（正确性）；③Rust 桥接 N+1 批量化与 import 计数改 SQL；④浏览器逐卡渲染治理与 catalog 连接治理；⑤投影 noop 短路与发布事务批量化。**不改变**渲染保真、调度语义、备份流程、collection 数据所有权。
> 前置阅读：[34](./34-official-anki-production-cutover-and-ohos-retirement-plan.md)（契约与发布口径）、[35](./35-duplicate-legacy-layer-cleanup-plan.md)（L0–L3 已删范围，本计划 P1 是其顺延）、[36](./36-projection-tree-ordering-and-limits.md)（投影写入语义与 60/40 限额）、[37](./37-generic-card-recognizer-plan.md)（契约 1.9 现状）。
> 铁律：**每个施工包独立 commit、独立可回滚**；Rust 契约 minor 逐次递增、号码永不复用（operations.md append-only 政策）；**本机（Windows 开发机）无 cargo/protoc（已核实，同 doc 37 §10 受限），Rust 改动必须在具备 Rust 1.97.1 + protoc 31.1 的主机通过 `cargo test -p turna_anki_bridge` 后方可合入**——这是硬门禁，不是建议。

## 0. 一句话

把 2026-08-30 屎山分析里「可行性已复核」的五件事按依赖顺序落地：先删约 4,000 行零引用代码，再用双计数器修好「删卡后搜索仍吐旧数据」的正确性缺口并顺手消除「答题即全量重投影」的隐患，然后把桥接层三处 N+1（最坏 2,000 查询/调用）压成常数条 SQL、import 后两次全表扫压成两条 `count()`，浏览器从 1,000 次串行 FFI 渲染改为按可见行懒渲染，投影未变化源从「全量读行+逐行哈希」短路为「指纹比对即返回」、发布事务从每卡 1–2 条 await 改为分块多行插入。

## 1. 背景与证据摘要

分析覆盖三块：Rust 桥接（`native/turna_anki_core/bridge/src`，6,415 行）、Dart official 层（`lib/application/anki_official` + `lib/views/anki_official`，约 30,900 行）、Legacy 残件（约 3,500 行）。本计划只收录五项；其余发现（DTO 手写样板、操作表四处维护、adapter 纯转发层、错误模型三套并存等结构性债务）留待批次二，见 §11。

所有 file:line 均于 2026-08-30 对照工作树核实。关键证据：

| 证据 | 位置 |
|---|---|
| `bump_page_generation` 生产调用点仅 import 一处 | `engine.rs:367-371`；`ops.rs:350`、`engine.rs:326-328/388-390`（后两处内联等价） |
| 其余全部变更操作只调 `invalidate_tokens`，不触 `page_generation` | `ops.rs:565,814,874,894,973,1002,1035,1173,1303,1365` |
| 分页缓存与投影快照按 `page_generation` 判命中 | `query.rs:97-105`、`projection.rs:391-393` |
| 批量描述符每卡 2 查询（get_card+get_note），上限 1,000 卡 | `query.rs:183-203` |
| 投影行批每行 3 查询（card+note+deck），上限 500 行 | `projection.rs:425-450` |
| import 成功后 `search_notes("")`+`search_cards("")` 全表扫只为计数 | `ops.rs:341-348` |
| 浏览器在循环里逐卡 `await engine.renderCard(...)` | `official_anki_source_aware_browser.dart:226-264`（pageSize 1000） |
| 投影先全量读行再比对指纹，noop 路径也付全量读+哈希 | `official_anki_projection_service.dart:454-488` |
| 发布事务每卡 1–2 条 awaited INSERT | `official_anki_projection_store.dart:191-231` |
| Fixture pilot 簇仅被 internal 调试页引用，测试零引用 | grep 核实：imports 仅 `official_anki_internal_page.dart:14-15` |
| `AnkiNoteDao` 全部写方法零生产调用 | 逐方法 grep lib/，仅 `test/data/anki_note_dao_test.dart` 与 write-fence 矩阵测试调用 |

## 2. 可行性复核结论（对原建议的修正）

复核否决或降级了原分析中的三个方案，这是本节存在的理由：

| # | 原建议 | 复核结论 | 依据 |
|---|---|---|---|
| V1 | 把 `bump_page_generation` 折进 `invalidate_tokens`（一行级修复） | **否决**。`get_review_queue` 每次调用都走 `begin_queue_epoch → invalidate_tokens`（`ops.rs:586`）——折叠等于每次拉队列都清分页缓存，浏览缓存报废、`PAGE_TOKEN_STALE` 风暴。改为**双计数器**显式落点，见 P2 | `engine.rs:198-200`、`ops.rs:586` |
| V2 | `std::mem::take` 把 Collection 移出锁外跑 import/backup，消除分钟级锁阻塞 | **降级为不做**。Dart 侧全部引擎调用经单一 worker isolate 串行派发（`official_anki_session.dart:165-170,943-953`），Rust 锁竞争在现架构下不会成为用户可感瓶颈（import 期间其它调用在 Dart 排队，120s 超时转 `schedulerBusy`，与 Rust 锁无关）；而 take 窗口内 `close_collection` 无 busy 检查会把 Closed 引擎与归还的 Collection 错配（`engine.rs:337-349`）。只保留便宜的忙位不变量加固，见 P3-5 | worker 串行：`session.dart:943-953`；hazards：`engine.rs:337-349`、`projection.rs:356-384` |
| V3 | catalog「每次构造重跑 9 版迁移检查」是性能问题 | **修正**。版本已至 9 时构造只做 open + 2 条 PRAGMA（`official_anki_database.dart:43-45`），CPU 可忽略。真问题是：`_openImporter` 覆盖 `OfficialAnkiCourseEntry.catalogOf` 为每调用工厂，`resolveActiveSectionIds()` 每次开一个**永不关闭**的连接（`composition.dart:184-186`、`official_anki_course_entry.dart:97`）；且跨 isolate 多连接下默认 rollback journal、无 `busy_timeout`，存在潜在 `SQLITE_BUSY`。P4 按此修 | `official_anki_database.dart:33-45`、`composition.dart:184-186` |

其余可行性前提（已核实成立）：

| 前提 | 判定 | 关键事实 |
|---|---|---|
| rslib 无公开批量读取 API，但有官方逃生口 | 成立 | 单条 getter 均 `pub` 单 id（`storage/card/mod.rs:123`、`storage/note/mod.rs:27`）；`col.storage.db() -> &Connection` 是文档认可的 escape hatch（`storage/sqlite.rs:92-99`），桥接已有 `revlog_count` 直查先例（`ops.rs:1411-1421`）；`rusqlite 0.36` 是直接依赖 |
| `cid:/nid:` id 列表内联 SQL 安全且有限例 | 成立 | rslib 自己就把 id 列表内联进 SQL（`search/sqlwriter.rs:192-194` `c.id in ({cids})`）；桥接已在 `schedule_cards_as_new` 内联至 10,000 个 id（`ops.rs:1153-1161`）；id 来自 JSON 反序列化的 u64，无注入面 |
| 契约可纯增量 bump | 成立 | 现为 1.9（`contract.rs:16`、`contract/VERSION`）；fail-fast 只卡 major（`contract.rs:262-268`）；minor 历史 +8 次零 major。本计划三次 minor bump：P1 退役 SEARCH_CARDS →1.10、P2 投影 generation 语义 →1.11（若与 P1 同 PR 可合并为一次）、P4B 新 op → 下一个可用 minor |
| 新增 op 的全链路落点已知 | 成立 | 9 处 Rust（OP 常量/dispatch/handler/name→id/capabilities/minor/VERSION/operations.md/fixtures regen/能力测试）+ 6 处 Dart（contract 四张表/engine 接口/ffi/worker/session/fake）。P4B 附完整清单 |
| note 内容变更检测有权威信号 | 成立 | `notes.mod`（mtime）列存在（`schema11.sql:20`）；桥接目前取了 Note 却丢弃 mtime（`query.rs:186-201`）——P5 的 scan 指纹不直接依赖它，靠 P2 的 content_generation 兜住（见 P5 健全性论证） |
| 投影行可用裸 SQL 重建 | 有条件成立 | `notes.flds` 以 `\u{1f}` 分隔（Anki 稳定格式）；deck 路径=名字+父链；notetype 模板事实每 notetype 缓存。风险=与 rslib 行为漂移，P3-3 用**双实现对拍测试**兜底 |
| 工具链 | **受限于本机** | 本机无 cargo/protoc（doc 37 §10 同记）；Rust 包一律「本机静态编写 → 工具链主机 `cargo test` 全绿 → 合入」 |

## 3. P1 — 删除零引用死代码（约 4,000 行）

### 3.1 删除簇与证据

**簇 A：Fixture pilot 脚手架（≈1,800 行）**，单独 commit（可整体 revert）：

| 目标 | 位置 | 证据 |
|---|---|---|
| `official_anki_fixture_pilot_saga.dart`（449 行） | `migration/` | 仅被 internal page `:14` 引用；测试 grep 0 命中 |
| `official_anki_fixture_rollback_drill.dart`（360 行） | `migration/` | 仅被 internal page `:15` 引用 |
| `official_anki_internal_page.dart`（936 行）整个页面 | `application/anki_official/` | 路由 `routing.dart:79-80`（挂 `DiagnosticsReleaseGuard`）、唯一入口 `developer_settings_page.dart:64`；生产对应面（迁移中心、源管理页）已存在 |
| 路由注册与守卫名单 | `routing.dart:79-80`、`routing.gr.dart`（regen）、`diagnostics_release_guard.dart:19` guardedRouteNames | 删页后同步清 |
| 泄漏进生产文件的 fixture 分支 | `projection_service.dart:289-299,344-350,885-915`（`projectSourceForFixturePilot` 等）；`migration_dao.dart:109-131`（`LIKE 'p5c-fixture-%'`）；`official_anki_user_allowlist.dart`（22 行，删前 grep 确认无他处 gate）；`preview_loader` 的 observing fixture 目标 | 全部仅被簇内调用 |
| 硬编码设备路径 | `/sdcard/Download/p5c-*.apkg` 等（internal page `:51-65,351-354`） | 随页面消亡 |

**簇 B：`AnkiNoteDao` 写侧（~600/1028 行）**：删 `replaceDeckIndex/replaceImportIssues/replacePracticeProjections/deckIdsIncludingDescendants/upsertNotetype/notetype/notetypesFor/upsertNote/note/upsertCardMeta/cardMeta/cardMetaByWordId/wordIdsForDecks/clearBuriedBefore/flaggedCards/upsertNotetypeBatch/upsertNoteBatch/upsertCardMetaBatch`（行号见 `anki_note_dao.dart:31-611` 各方法）及只服务它们的私有助手（`_withState`、`_applyStateBatch` 视剩余引用裁剪）与 `AnkiTemplate` JSON 类（`:895-922`）。保留 `searchNotes/setCardState/projectionForCard/deleteByImport`（均有生产调用者）。生产调用零命中已逐方法核实；与 `official_anki_architecture_guard_test.dart:336-349`（禁 legacy writer 复活）方向一致。

**簇 C：`AnkiImportDao` 写侧**：删 `upsert(:17)/markComplete(:51)/markFailed(:90)/markAiEnhanced(:152)`，保留全部读访问器与 `delete`。

**簇 D：零引用符号**（逐个已核实定义即全部引用）：

- Dart：`officialAnkiJsonPreview`（`native_transport.dart:411`）、`decodeOfficialEnvelope`（`engine_ffi.dart:515-517`）、`officialRoutedImportIdsFromCatalogFile`（`production_router.dart:446-462`）、`ankiImportIdFromWordId`（`:464-466`）、`lessonContentJson`（`projection_store.dart:358-360`）、`OfficialAnkiDeckCounts.newStudied/reviewStudied`（`dto.dart:952-956`）。
- 审计管道：`OfficialAnkiAuditLog` 及 scheduler 回复里的 `'audit'` key（写入 `session.dart:660,947-953,1035`；消费方 grep 0）；`official_anki_scheduler_audit.dart` 四个从未递增、仅被测试断言 `==0` 的计数器，连同断言一起删；`OfficialAnkiProjectionCounters.officialSchedulerWrites/legacyCalls`（`projection_service.dart:31-32`）同删。
- Rust：`live_handle_count`（`engine.rs:254-257`）、`TokenRequest.session_id/queue_epoch` 死字段（`ops.rs:147-151`）、`EnvelopeError.retry_after_millis`（从未填充；`debug_details` **保留**——P3 错误映射改进的现成载体，批次二启用）、`projection.rs:397` 死读与 `:407-414` 重复边界检查（`take(MAX_BATCH.max(DEFAULT_BATCH))` 收敛为一处）。`dispatch_op` 未知 op 兜底臂（`ops.rs:250-260`）**保留**——直连 `dispatch` 的测试仍可达，属防御。

**簇 E：Rust 遗留 `SEARCH_CARDS`（op 9）退役**：Dart 仅用 `SEARCH_CARDS_PAGE`（op 18；`contract.dart:33,68,155-156`），op 9 从未进 capabilities；其 handler（`ops.rs:401-448`）会全量 dump 整个集合每条笔记的每个字段，无界成本。删 handler + dispatch 臂（`engine.rs:404`）+ name→id（`contract.rs:194`）+ 相关测试；`operations.md` 将 9 标记 retired（号码永不复用）；minor → 1.10。施工时先 grep `contract/fixtures/` 与桥接测试对 op 9 的引用。

### 3.2 簇 B/C 的测试处置

- `test/data/anki_note_dao_test.dart`：删被删方法的用例，保留 `searchNotes/setCardState/deleteByImport` 用例。
- `test/application/anki_official/official_legacy_write_fence_matrix_test.dart`：现用被删 writer 造数（`:102,149`）。矩阵测试本身保留（仍覆盖存留 mutator 的 fence 语义），造数改为 drift 直插或仅用存留方法。
- 在 `official_anki_architecture_guard_test.dart` 增一条「fixture pilot 簇保持删除」规则（仿 doc 35 L1 模式），防复活。

## 4. P2 — 快照失效修复（双计数器）

### 4.1 缺口

变更操作（answer/undo/redo/bury/suspend/delete/schedule_as_new/answer_ahead/quota）只失效答题 token，不清 `page_snapshot`/`projection_snapshot`。后果：`delete_notes` 后 `search_cards_page` 继续命中旧缓存返回已删卡 id 与过期 `totalHint`（`query.rs:97-105`）；投影快照同理（`projection.rs:391-393`）。

### 4.2 设计

**两个计数器，两类消费者**：

1. `page_generation`（现有）：门分页 token 与 `page_snapshot`。在下列操作的提交点**新增显式** `bump_page_generation` 调用（不折进 `invalidate_tokens`，理由见 §2 V1）：
   `set_current_deck`（`ops.rs:565` 附近）、`answer_card`（:814 后）、`undo`（:874）、`redo`（:894）、`bury_or_suspend`（:973）、`delete_notes`（:1002）、`delete_cards`（:1035）、`schedule_cards_as_new`（:1173）、`answer_ahead_cards`（:1303）、`ensure_today_new_quota`（:1365）。`get_review_queue` 的 `begin_queue_epoch` **不得**触碰它。
2. `content_generation`（新增字段，init 1）：门投影快照与 `beginProjectionRead` 返回的 `collectionGeneration`。仅在**内容变更**操作后递增：`import_package`、`delete_notes`、`delete_cards`、`undo`、`redo`（undo 可能回滚删除，保守纳入；`schedule_cards_as_new` 只改调度不改内容，不纳入）。`begin_projection_read`/`get_projection_rows_batch` 的快照检查与返回值从 `page_generation` 切到 `content_generation`。

**为什么必须双计数器**：投影行的内容=fields/deck/guid/tags/ord，答题/挂起不改变其中任何一项。若投影沿用 `page_generation`（P2-1 之后每次答题都递增），则每次复习后下一次 `projectSource` 全量重投影（1 万卡源≈全量读行+全删全插）——修一个 bug 引入一个更重的回归。`fingerprintFor` 含 `collectionGeneration`（`projection_service.dart:127-150`），切到 `content_generation` 后答题不再扰动投影指纹，这是本设计的第二收益。

### 4.3 Dart 侧配套

- `pageTokenStale` 现为 recoverable=true 但 **Dart 零 catch 点**（grep 核实）。P2 之后后台答题与分页搜索可交错（home due sync 分页 pageSize 500 期间用户答题）：`OfficialAnkiHomeDueSync._refreshOnce` 捕获 `pageTokenStale` 整体重启一次刷新（现兜底是 `markUnavailable` 降级，可接受但不必）；浏览器 `_searchOfficial` 分页循环同样捕获后重开一次搜索。
- 契约：`beginProjectionRead` 返回的 `collectionGeneration` 语义从「任意变更代」变「内容变更代」。minor bump（与 P1 可合并为 1.10 一次），`operations.md` 注明语义。

### 4.4 测试（Rust 新增——现状零覆盖）

- `delete_notes` 后 `search_cards_page` 冷缓存重建、旧 page_token 返回 `PAGE_TOKEN_STALE`；
- `answer_card` 后同上（搜索结果含 `is:due/rated:` 类变化）；
- `answer_card`/`bury_or_suspend` 后投影快照**存活**（`content_generation` 未变）；
- `import`/`delete` 后投影快照失效（`PROJECTION_SNAPSHOT_STALE`）；
- `get_review_queue` 连续两次调用不清 `page_snapshot`（缓存仍命中）。

## 5. P3 — Rust 批量化、import 计数与不变量

### 5.1 批量化（裸 SQL，走 `db()` 逃生口）

| # | 现场 | 改法 |
|---|---|---|
| 1 | `get_note_cards_batch`（`query.rs:157-172`）每 note 一次 `all_cards_of_note` | 一条 `SELECT id, nid, ord FROM cards WHERE nid IN (…)`，`ORDER BY nid, ord`（与 `all_cards_of_note` 的模板序对齐，实现时核对 `storage/card/mod.rs:472` 的 ORDER BY） |
| 2 | `get_card_descriptors_batch`（`query.rs:183-203`）每卡 get_card+get_note | 一条 JOIN：`SELECT c.id, c.nid, c.did, c.ord, c.queue, c.flags, n.guid, n.tags FROM cards c JOIN notes n ON n.id = c.nid WHERE c.id IN (…)`；tags=对 `notes.tags` 字符串 split（与 rslib Note 解析对拍）；分块 ≥500/条 |
| 3 | `get_projection_rows_batch`（`projection.rs:425-450`）每行 card+note+deck | cards/notes 裸 SQL（`flds` 按 `\u{1f}` 分列）；deck：调用内按 deck_id 缓存 `get_deck`（deck 数≪卡数）或一次父链查询；notetype 模板事实调用内缓存。**迁移期双实现对拍**：同一 fixture 集合上旧实现与新实现输出 JSON 必须全等（保留旧实现为 `#[cfg(test)]` 对拍函数，测试通过后下个 pin 刷新时删） |

id 列表内联 SQL 的安全依据见 §2（u64 反序列化 + rslib 同款做法）。schema 列名知识被复制的漂移风险由对拍测试 + 上游 pin 刷新时重跑契约/fixture 门禁（README 维护规则）兜住。

### 5.2 import 计数（`ops.rs:341-348`）

`search_notes("")`+`search_cards("")` 两次全表扫 + 两个全量 Vec → 两条 `select count() from notes/cards`（`db()` 直查，O(1) 内存）。现有断言计数的测试（`ops.rs:1549` 小 fixtures manifest、`:2587` 100k NO-GO 记录）保持全绿即为验收。

### 5.3 便宜的不变量加固（非性能项）

- `close_collection` 补 busy 检查：busy 时返回 `INVALID_STATE`（现为无检查直入，`engine.rs:337-349`）；
- 手写 lock+state 检查统一为 `require_open`（fail-fast 而非阻塞排队）：`query.rs:82-85,151-154,176-179`、`projection.rs:281-284,363-366,416-419`、`import.rs:127-129,186-187`。

### 5.4 明确不做

`mem::take` 无锁 import/backup（§2 V2）；`answer_card` 内三次 `revlog_count` 合并、`render_card` 三重加载（批次二，涉答题/渲染热路径需单独性能基线）；`template_facts` 缓存（对拍落地后按需）。

## 6. P4 — 浏览器渲染与 catalog 连接治理

### 6.1 Phase A：纯 Dart（无契约变更，先行合入）

1. **懒渲染 + 缓存替代预渲染循环**：`official_anki_source_aware_browser.dart:226-264` 的逐卡 `renderCard` 改为 ListView 按可见行触发 + `cardId → (front,back)` LRU(200) 缓存；缓存命中零 FFI。翻面/详情视图仍走全量 `renderCard` 保真路径不变。
2. **补错误处理**（现存 bug）：`AnkiCardBrowserPageState._load` 无 try/catch，搜索抛错则 `_loading` 永真卡死转圈（`anki_card_browser_page.dart:74-139`）；补 finally 复位 + 错误态 UI。
3. **筛选芯片/牌组下拉接 250ms 防抖**（`:323-358,389-392` 现直调 `_load` 无防抖；搜索框已有防抖 `:141-144` 对齐即可）。

### 6.2 Phase B：`RENDER_PREVIEWS_BATCH` 新 op（契约 minor 递增）

Phase A 后每可见行仍是 1 次 FFI 往返；如仍有滚动白屏感再上 Phase B。**返回纯文本预览而非 HTML**——envelope payload 上限 1 MiB（`contract.rs:19`），100 张卡的完整 HTML 必然超限，且消费方只做 `stripHtml`（`html_stripper.dart:7`）。Rust 侧循环渲染 + 标签剥离（预览级保真即可），每批 ≤100 卡。

落点清单（新增 op 全链路，已核实）：

- Rust：`engine.rs:47-81` OP 常量（下一个可用 id=37；STATUS_* 是另一命名空间不冲突）+ `:399-414` dispatch；`ops.rs:224-262` handler + DTO + 批量上限；`contract.rs:183-223` name→id；`contract.rs:111-147` capabilities；`contract.rs:16` minor+1（`ops.rs:2805` 的 minor 断言同步）；`contract/VERSION`；`contract/operations.md` 增行+散文（append-only 政策）；`contract/fixtures/response_engine_info.json` regen（`cargo run --bin turna_anki_gen_fixtures`）；`ops.rs:2776` 能力测试更新。
- Dart：`official_anki_contract.dart` 名/ID/productionNames/idFor 四张表；`engine.dart` 接口；`engine_ffi.dart`；`official_anki_session.dart` 客户端方法+worker 分支；`engine_fake.dart` 实现+capabilities（fake 已有 `renderCount/failRenderFor` 插桩可复用，`:336-367`）。

### 6.3 catalog 连接治理

1. **修 `catalogOf` 覆盖泄漏**：`composition.dart:184-186` `_openImporter` 把 `OfficialAnkiCourseEntry.catalogOf` 覆写为每调用工厂 → `resolveActiveSectionIds()`（`official_anki_course_entry.dart:97`）每次开一个不关的连接。改为常返共享 `readOnlyCatalog`（主 isolate）；worker isolate 维持自己的连接不变（`:673,959`）。
2. `OfficialAnkiHomeDueSync._refreshOnce` 复用主 isolate 共享读句柄，去掉每次刷新 open/close（`:75,260`）。
3. `OfficialAnkiDatabase` 打开时执行 `PRAGMA journal_mode=WAL` + `PRAGMA busy_timeout=5000`：catalog 是跨 isolate 多连接库，默认 rollback journal + 无 busy timeout 存在潜在 `SQLITE_BUSY`（现无任何 journal 设定，grep 核实）。v9→无 schema 变更，仅打开期 PRAGMA。

## 7. P5 — 投影 noop 短路与发布批量化

### 7.1 scan 指纹短路（前置：P2 的 `content_generation`）

现状：`_project` 先 `_readRows` 全量读行+逐行 SHA（`:698-839`）→ 算全量 `fingerprintFor`（含 rows，`:127-150`）→ 才与 `_activeFingerprint()`（`:1051-1066`）比对判 noop（`:474-488`）。未变化源每次发布付全量读+哈希。

改法：

1. catalog `anki_source_projection_state` 增列 `scan_fingerprint`（schema v9→v10，加列+NULL 回填；NULL=未知→走全量一次）。`scan_fingerprint = hash(contractMajor/Minor, backendCommit, profileId, sourceId, orderedCardSetFingerprint, contentGeneration, schemasFingerprint, mappingVersion, confirmedMappingHash)`——即现 `fingerprintFor` 除 rows 外的全部因子。
2. `projectSource` 顺序重排：`beginProjectionRead`（轻，无行读取）提前 → 算 scan 指纹（`_scanSource` 的 id 哈希 `:626-675`、schemas `:398-453`、mapping 本就在读行前可得）→ 与库中 `scan_fingerprint` 相等且 manifest 行存在 ⇒ `markActive` + noop 返回，**不进 `_readRows`**；不等 ⇒ 走全量并在发布成功时连同全量指纹一起落 `scan_fingerprint`。
3. 全量路径的最终判 noop（全指纹比对）保留——scan 短路是快路径，全指纹是权威判据，两层不冲突。

**健全性论证**（为何 scan 相等可推 rows 相等）：rows 内容=fields/deck/guid/tags/ord，仅经桥接操作变更；应用独占 collection 文件（无外部编辑面）；全部内容变更操作（import/delete/undo/redo）均递增 `content_generation`（P2）；卡编辑类操作未在契约中暴露。任一因子变化（含契约版本、mapping、notetype 模板）都在 scan 因子里。论证写入本节作为评审锚点。

### 7.2 发布事务批量化（`projection_store.dart`）

| 现场 | 改法 |
|---|---|
| 每卡 1–2 条 awaited INSERT：`official_anki_projection_index`（`:191-211`）+ vocabulary `INSERT OR REPLACE`（`:212-231`）——O(cards) 主项 | 多行 `INSERT ... VALUES (...),(...)` 分块（每块 ≤200 行，参数上限 32766/列数，安全）；vocabulary 同法 |
| `_deleteOwnedTree` 每课/每单元/每节一条 DELETE（`:443-458`） | 每表 `DELETE ... WHERE id IN (分块)` |
| sections/units/lessons 逐条 insert（`:132-189`） | **保留**——受 doc 36 的 60/40 限额约束是小 N |
| `_compactSectionSortOrders`（`:288-304`） | 保留（仅 UPDATE 有变化行，≤60 节） |

fault 注入语义：`tick()`/`statements` 计数（`:109-116`）改为按块递增；依赖精确语句序号的故障注入测试（`official_anki_projection_test.dart`）同步改用块序号。`CardIntroductionStore.seedOfficialProjection`（事务外，`:259-263`）不动。

## 8. 依赖与施工顺序

```text
P1（任意时点，先做——缩表面积，纯删除）
 └─ P2（正确性，双计数器；契约语义变更与 P1 可共用一次 minor bump 1.9→1.10）
     ├─ P3（P2 之后：同触 projection.rs 读路径与 ops.rs 变更点，避免双改冲突）
     │    └─ P5（依赖 P2 的 content_generation；受益于 P3 的行批量化）
     └─ P4A（纯 Dart，随时可并行）
P4B（契约新 op：等 P1/P2 的 minor 落定后取下一个 minor，避免号码竞争）
```

每个施工包 = 独立 PR/commit 组，按仓库规则附命令、指标与证据；P1 内簇 A–E 亦各自独立 commit。

## 9. 风险表

| 风险 | 等级 | 缓解 |
|---|---|---|
| P2 落点遗漏某个变更操作 | 中 | 以 `invalidate_tokens` 调用清单（§1）为核对表逐点落 bump；新增 Rust 测试覆盖 answer/delete/import 三类代表 |
| P2 使后台分页搜索撞 `PAGE_TOKEN_STALE` | 中 | §4.3 两处重启一次的兜底；错误本身 recoverable=true |
| P3 裸 SQL 与 rslib 解析漂移（tags/flds/deck 路径/排序） | 中 | 双实现对拍测试（全部 fixtures 上 JSON 全等）；对拍函数保留至下次 pin 刷新 |
| P3 schema 列名知识复制 | 低 | rslib pin 冻结；pin 刷新时契约/fixture 门禁强制重跑（README 规则） |
| P4B 预览文本保真低于现 Dart strip | 低 | 预览仅列表用；详情仍走全量 renderCard；Phase A 先行可无限期推迟 B |
| P5 scan 短路漏判内容变化 | 低 | §7.1 健全性论证 + NULL 回退全量 + 全指纹权威判据保留；上线首个版本可只记日志不短路（影子模式）验证一轮 |
| P5 批量插入改变故障注入测试语义 | 低 | 块序号替换语句序号，测试同 commit 更新 |
| P1 误删仍有引用的符号 | 低 | 全部零引用已 grep 核实并留证；簇 E 施工时补 grep fixtures/测试 |
| 本机无 Rust 工具链导致「写完测不了」 | 中 | 硬门禁：Rust 包在工具链主机 `cargo test` 全绿后才合入；Dart 包不受阻 |

## 10. 验证与验收

每包验收基线（施工时填实际数字）：

```bash
# Dart 侧（本机可跑）
flutter analyze                      # 0 issues（doc 34 基线）
flutter test                         # 全量绿（基线 1852；P1 删除死码测试后数量下降属预期，逐条列出被删用例）
flutter test test/application/anki_official/official_anki_projection_test.dart
flutter test test/application/anki/official_anki_architecture_guard_test.dart
flutter test test/application/anki_official/official_anki_source_aware_browser_stats_test.dart

# Rust 侧（工具链主机；本机无 cargo/protoc，见铁律）
cd native/turna_anki_core
export PROTOC="$PWD/tools/protoc/bin/protoc" PROTOC_BINARY="$PROTOC"
cargo test -p turna_anki_bridge      # 全绿（doc 34 基线 68；P2/P3 新增用例后数量上升）
cargo run --bin turna_anki_gen_fixtures   # 契约变更包（P1 簇E/P4B）后 regen 并 diff review

# Android（涉及 .so 的包：P1E/P2/P3/P4B）
./build-android/build.sh             # 按 doc 34 真机矩阵口径 smoke
```

量化验收口径（施工时以实测量填）：

| 包 | 指标 |
|---|---|
| P3 | 1 万卡源 `GET_CARD_DESCRIPTORS_BATCH`（1000 卡）SQL 条数 2000→2；import 后计数 SQL 条数 2 次全扫→2 条 count；100k fixture import 总时长对比 |
| P4A | 1000 卡牌组进入浏览页的 renderCard FFI 次数 1000→≤可见行数（首屏≈15–20） |
| P5 | 未变化源重复 `projectSource` 的行读取批次 500/批×N→0（noop 短路命中）；1 万卡发布事务语句数 ~2 万→~百级 |

## 11. 明确不做（留批次二及以后）

DTO `fromJson` 手写样板 codegen 化（~700 行）、Rust 操作表四处事实源合一、Dart engine adapter 四层折叠（session_engine/worker 纯转发 ~600 行）、错误模型三套并存统一（`debug_details` 启用、`DECK_NOT_FOUND` 误映射、`catch(_){}` 八处）、`answer_card` 三重 `revlog_count` 与 `render_card` 三重加载、复习每卡 3+1 RPC 精简、registry 句柄回收与 buffer ABI 加固、`mem::take` 无锁 import、envelope 三重解析/序列化削减。这些与 P1–P5 无文件级冲突，但单独成批可避免本批 PR 膨胀。

## 12. 施工记录（2026-08-30）

### 12.1 提交清单（独立 commit，按依赖序）

| 施工包 | commit | 摘要 |
|---|---|---|
| 登记 | dd3c2740 | doc 38 + README 登记 |
| P1-A | c949b46d | fixture pilot 脚手架簇删除（4 文件 + 路由/守卫/泄漏分支 + migrationPilot 旗标） |
| P1-B/C | 74f2ad8c | AnkiNoteDao 1028→444 行、AnkiImportDao 写侧删除 + 测试处置 |
| P1-D | f0a81b19 | Dart/Rust 零引用符号与 audit 链删除 |
| P1-E | 96a1c2c6 | SEARCH_CARDS(op9) 退役，契约 1.9→1.10 |
| P2 | d365810f | 双计数器 + 十个落点 + Dart 兜底 + 5 个 Rust 新测试 |
| P3 | 86ce71ec | 三处 N+1 SQL 化 + import 计数 + 不变量 + 对拍测试 |
| P4-A | e7836d67 | 浏览器懒渲染 LRU + 错误兜底 + 防抖 |
| P4-C | 9c3985ae | catalog 共享句柄 + WAL/busy_timeout（+ a1bf7dec 金子 minor 补遗） |
| P5 | 721da80f | scan 指纹短路（schema v10）+ 发布批量化 |

### 12.2 验收实测（本机 Windows，flutter 侧）

- `flutter analyze`：**0 issues**。
- `flutter test`：**施工前后逐例对照均为 29 例失败 → 施工后 28 例**，且 28 例与基线 74ae31c5 的失败集合**完全一致**（在基线提交点重跑全量套件比对确认）——全部为本机 Windows 环境预存失败，与 doc 38 无关：
  - `official_anki_media_resolver_test.dart`（9 例）：fixture 向量含 `question?.png`/`hash#tag.bin` 文件名，Windows 下 `?`/`#` 非法（errno 123）；
  - golden/无障碍快照（11 例：course_tree/dictionary/settings_reminder/srs_review/round2_accessibility）：Windows 字体渲染与基线快照差异；
  - `official_anki_composition_test.dart` single-flight（1 例）：fake worker 的 catalog 连接不随测试 dispose，目录删除 errno 32；
  - `anki_import_official_first_test`/`lesson_flow`/`backup_snapshot`/`reviewer_behavior`/`reviewer_ui_av`/`review_dashboard`/`review_progress_provider`/`review_history_dao`（8 例）：基线同样失败的集成/时序/大量数据用例。
  - 施工引入且**已修复**的两例：diagnostics guard 测试对已删路由的 containsAll 断言（e9e3710f）；基线失败的 `official_anki_import_orchestrator` future-schema 文件锁反被 P4-C 的 dispose-on-failed-migration 修复（基线 29→施工后 28 的净来源）。
- P4-A 指标（fake 引擎计量）：进入浏览页 renderCard FFI **1000→0**；每未缓存可见卡恰 **1** 次；缓存命中 **0** 次。
- P5 指标（fake 引擎计量）：未变化源重复 `projectSource` 行读取批次 **N→0**（短路命中，`projectionBatchCalls` 不增）；行内容变更（override+generation bump）正确破短路全量重建。
- P3 指标：SQL 条数为结构性收敛（描述符 1000 卡 2000 查询→**2** 条 JOIN；import 计数 2 次全表扫→**2** 条 `count()`）——本机无 cargo，运行时数字待工具链主机复验。
- 被删用例清单（P1 删除死码测试后数量下降，逐条）：`anki_import_dao_test.dart` 整文件（4 例 markFailed）；`anki_note_dao_test.dart` 删 7 例（notetype/note/cardMeta round-trip×2、deck 诊断、计数对账、practice projection 原 seed 用例改直插、wordIdsForDecks）；p5d 路由测试删 allowlist 2 例 + 2 断言；write-fence 矩阵缩至存留 mutator；新增对拍 2 例、P2 3 例、P5 1 例、架构守卫 2 规则、P4-A 懒渲染断言。

### 12.3 偏差与增补（对照本计划正文）

1. **簇 A 范围比 §3.1 大**：复核发现文档未列的三处泄漏——`engine_kind.dart` 的 `isFixturePilotSource`/`_p5cFixtureHashes`、`migration_preview_page.dart` 的 `onFixturePilot` 参数与按钮、`migrationPilot` 旗标（env `TURNA_OFFICIAL_ANKI_MIGRATION_PILOT`）及其 flags 测试断言——一并删除，否则删 allowlist/saga 后悬空引用。
2. **簇 B/C 测试处置**：文档预想的「drift 直插」落为共享助手 `test/helpers/anki_import_seed.dart`（复刻 upsert/markComplete/markFailed 的 SQL，仅测试可用）；`anki_import_dao_test.dart` 整文件删除（全部用例都是被删的 markFailed）。
3. **簇 D**：`OfficialAnkiSchedulerAudit` 从未递增计数器实为 **5** 个（文档写四个）：另含 `courseProjectionWritesDuringReview`；audit 链的删除面比 §3.1 大——`official_anki_review_session.dart` 的 `audit` 字段/`_audit()` 四处调用一并删除（构造方从未传非空）。
4. **簇 E 测试迁移**：queue 断言从名称字符串（`new/review`）改为原始 queue 值（描述符 batch 的整数）；原 `due` 断言经核实是比较 `Null==Null`（旧 handler 从不输出 due），删除；unicode 字段断言改走 `GET_PROJECTION_SCHEMAS` samples。
5. **P2**：契约 minor 与 P1-E **共用 1.9→1.10 一次 bump**（§8 明示允许）；`open_collection`/`reopen_open_collection` 统一按内容变更处理（restore 无法自证文件未变，保守失效；代价是 `create_backup` 后首个投影发布多付一次全量，备份为低频操作可接受）；**import.rs 两处不统一为 `require_open`**——`BusyGuard` 持有期间 busy 位为真，`require_open` 会自锁误判，维持显式状态检查。
6. **P3**：对拍参照实现保留为 `#[cfg(test)]`（query.rs `mod reference` / projection.rs `reference_rows`），四个 fixture 包全量 JSON 对拍；发现并修复一处对拍级缺陷——新实现初版把**截断后** fields 喂给指纹，而参照用未截断 `Note::fields()`，已改为指纹用原始 fields、截断副本仅展示。
7. **P4-B（RENDER_PREVIEWS_BATCH）未实施**：按 §6.2 前提「Phase A 后如仍有滚动白屏感再上」，Phase A 已把进入成本压到 0 FFI、每可见卡 1 FFI；新 op 落点清单（§6.2）保留备用，待真机滚动体验反馈后再决策。
8. **P4-C 增补**：共享句柄实现为**按路径单例**（路径变化换柄并释放旧柄，兼顾 profile 切换与测试隔离）；`OfficialAnkiDatabase` 构造器在 migrate 失败（如未来版本）时 dispose 连接再抛——修复未来版本探测测试在 Windows 下的文件锁泄漏（errno 32，P4-C 引入后即时发现即时修复）。
9. **P5**：fake 引擎的 `projectionRowOverrides` 改为写入即 bump `collectionGeneration`（MapBase 包装）——测试侧行内容变更必须遵守引擎契约「内容变更⇒内容代递增」，否则短路误判；`locked placement` 等既有测试借此继续走全量路径验证重建。**重启行为（如实记录）**：`content_generation` 是内存计数器，随引擎重建归 1，scan 指纹含该因子 ⇒ 每次应用重启后的首个发布必走一次全量（与改造前一致），短路收益集中在同会话内的重复发布——与全指纹 noop 的既有行为对齐，无回归。
10. **金子文件**：`request_engine_info.json`/`response_engine_info.json` 手改 minor=10；工具链主机需重跑 `cargo run --bin turna_anki_gen_fixtures` 校验（diff 应为空或仅次序）。

### 12.4 待办门禁（合入发布前）

1. **工具链主机**：`cargo test -p turna_anki_bridge` 全绿（含新增：对拍 2、P2 3、既有全部）；`cargo run --bin turna_anki_gen_fixtures` regen + diff review。
2. **Android 真机矩阵**（涉及 .so 的包 P1-E/P2/P3）：`./build-android/build.sh` smoke。
3. 真机滚动体验反馈 → P4-B 决策。
4. pin 刷新时删除 P3 对拍参照实现（`reference`/`reference_rows`）。
