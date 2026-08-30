# 41 — Official Anki 导入生命周期与存储回收修复计划

> 文档代号：ANKI-LIFECYCLE-STORAGE-REMEDIATION
>
> 日期：2026-08-30
>
> 状态：**施工中（Dart host 行为已落地；Android arm64 `.so` 已按 contract 1.11 重建；Android 强杀矩阵未跑）**；P0 数据生命周期阻断，**生产验收 NO-GO**。本文件是 [doc 34](./34-official-anki-production-cutover-and-ohos-retirement-plan.md) 下的专项修复入口，不宣称现有问题已修复；完成状态必须以本文 §16 门禁和 §18 收据为准。
>
> **范围修订（2026-08-31，ADR 0042）**：本文的导入链路修复部分（S1 控制权、S2 启动恢复的导入分支、S4 §9.2 preview scope、S6 checkpoint 体系对新导入）**由 [doc 42](./42-staging-first-official-import-lifecycle-plan.md) 的 staging-first 重设计取代**，不再按本文原波次施工。本文保留并继续有效的范围：S3 verified hard uninstall、S4 source 元数据/mapping 生命周期（§9.2 除外）、S5 media GC、S7 compact、S8 存量 census/repair center、§7.4 存量无主数据善后、§11.4 存量 checkpoint inventory。
>
> 前置阅读：[34](./34-official-anki-production-cutover-and-ohos-retirement-plan.md)、[34 收据](./34-cutover-receipt.md)、[38](./38-debt-and-perf-batch-1-plan.md)、[39](./39-debt-and-perf-batch-2-plan.md)、[40](./40-doc39-remainder-completion-plan.md)、[ADR 0036](../decisions/0036-official-anki-core-migration.md)、[ADR 0037](../decisions/0037-anki-course-review-unification.md)。
>
> 当前源码基线（2026-08-31）：`CourseDatabase.kSchemaVersion = 22`、Official catalog schema `11`、Official contract `1.11`（ops 37–40）。Android arm64 `libturna_anki.so` 已按 1.11 重建（2026-08-31 01:59，23,062,296 bytes，SHA-256 `C2808E58FE5AD28A5BD8B6A7CDFDEC4769785216F7F89F0765FB95283FD55530`；`verify_symbols.sh` pass；ELF AArch64 Android 24 / NDK r28c）。Android 强杀矩阵仍未跑。
>
> 铁律：**先写可稳定复现的失败测试，再改行为**；每个施工包独立 commit、独立可回滚；任何删除都先保留可恢复所有权证据；不把“UI 消失”“SQL 行已删”“物理字节已回收”混为同一状态；Rust/contract 改动必须在具备项目规定 Rust + protoc 工具链的主机通过 native 全量门禁并重建 Android `.so`。

---

## 0. 一句话与最终目标

当前 Official-first 链路先把 APKG 写进 `collection.anki2` / `collection.media`，再写 Official catalog，最后生成 CourseDatabase 投影并提交 owner 可见性；取消、返回、进程强杀和 authority 提交失败都可能把流程停在中间。删除链路只覆盖部分 source 级逻辑记录，不回收全局 notetype/deck/mapping、媒体、内部 checkpoint 和 SQLite 空闲页。

本计划把这条链路修成一个**可恢复、可取消、可验证、可回收**的单来源 saga：

1. 导入只在 Collection、source index、投影、identity、authority 全部验证后才算 `active`；
2. 显式取消必须完成 rollback，进程强杀必须在下次启动继续或进入可见隔离态；
3. 删除先验证 Collection 中目标卡确实不存在，再删除所有权索引；
4. 新导入只读取当前 source 的 deck/notetype，不再混入已删除来源；
5. 媒体按整个 Collection 的真实引用做 GC，共享文件不得误删；
6. rollback checkpoint 有明确用途、状态和上限，成功后自动清理；
7. SQLite 逻辑删除与物理压缩分层，但最终必须有可观测、可重试的字节回收结果；
8. 存量 staging/unfinished/pending/无主数据必须有一次性 census 与修复路径。

---

## 1. 问题定义与复现合同

### 1.1 症状 A：导入后退出，卡片不可见但占空间

当前调用链：

```text
AnkiImportController.proceedWithPath
  → OfficialAnkiOfficialFirstService.importThenPreview
    → OfficialAnkiImportOrchestrator.importFile
      → createBackup
      → native IMPORT_PACKAGE                  # Collection 已提交
      → attempt note ids / anki_source_cards   # catalog 关联
      → catalog source = active
    → preparePreview
  → 用户确认
  → projectSource                              # CourseDatabase 投影
  → publishFromProjection                      # identity + authority active
  → CourseProvider reload                      # UI 可见
```

任一中断点都可能留下部分状态：

| 中断点 | Collection | catalog | CourseDB 投影 | authority | 当前结果 |
|---|---:|---:|---:|---:|---|
| backup 后、native import 前 | 未变 | staging attempt | 无 | staging | 隐藏 checkpoint |
| native import 后、note ids 落库前 | 已写入 | 无完整 card owner | 无 | staging | 最危险的无主卡 |
| card index 完成、preview 前后 | 已写入 | source/card 完整 | 无 | staging | 卡存在但课程不可见 |
| projection 完成、identity/authority 前 | 已写入 | 完整 | 有 | staging | 隐藏投影 |
| authority 提交异常被吞 | 已写入 | 完整 | 有 | staging/缺失 | UI 可能误报成功 |
| active 后、checkpoint 删除前 | 完整 | 完整 | 完整 | active | 功能正常但磁盘泄漏 |

#### 必须新增的复现用例

1. `afterImportBeforeNoteIds` fault：重启后不得形成永久无主卡；
2. `afterNoteIdsBeforeCards` fault：重启后从 cursor 继续索引；
3. preview 页系统返回：必须出现“继续导入 / 放弃并清理”选择；
4. parsing 时按取消：native 收到 cancel；若 import 已提交，必须 rollback；
5. projection transaction 完成后强杀：重启后幂等完成 publish；
6. authority 写入注入失败：done 页不得出现“导入完成”；
7. app process kill：下次启动出现明确“正在恢复导入”或“导入待处理”，不得静默消失。

### 1.2 症状 B：删除后旧索引、牌组和映射混入新导入

当前有两类数据：

- source 级：`anki_source_cards`、projection index/manifest、jobs、placement overrides；
- profile/Collection 级：`anki_projection_mappings`、Anki notetype、deck definition、媒体文件、SQLite index pages。

成功卸载目前会删除第一类的大部分行，但明确保留 profile 级 mapping；native `LIST_DECK_TREE` 和 `GET_PROJECTION_SCHEMAS` 又默认读取整个 Collection。结果是 source A 删除后，source B 的预览仍可能出现 A 的空 deck、零使用 notetype 和历史 mapping。

#### 必须新增的复现用例

1. 导入 A（自定义 deck/notetype）→ 删除 A → 导入 B：B 的 preview 不得出现 A；
2. A/B 共享同一 card/notetype/media：删除 A 后 B 完整可用；删除最后 owner 后全局垃圾可回收；
3. 删除处于 `pending_cleanup` / `staging` / `retired` 的 sibling，shared-card 判定不得永久保护无 owner 卡；
4. 已确认 mapping 仅在 schema fingerprint 一致且仍有有效 source 引用时复用；
5. `anki_projection_mappings` 不得随“导入→删除不同 notetype”循环线性增长。

### 1.3 症状 C：删除后物理体积不下降

体积至少来自：

```text
collection.anki2
collection.media/
collection.media.db2
official_catalog.sqlite (+ WAL/SHM)
course.db (+ WAL/SHM)
backups/*.anki2
Anki 自身可能生成的 *.colpkg
```

当前 source uninstall 只调用 `DELETE_CARDS`，不执行 Official media GC、checkpoint retention 或 catalog/course DB compact。SQLite 删除行后通常只增加 freelist，不会自动截短文件；下一次 import 的 `CHECK_COLLECTION` 虽会触发 `vacuum; reindex; analyze`，但它既不是删除完成的一部分，也不覆盖 catalog、CourseDatabase、媒体和历史 checkpoint。

#### 必须新增的复现用例

1. 导入带 10 MiB 独占媒体的 A → 删除 A → maintenance 完成：媒体目录回到允许误差内；
2. A/B 引用同一媒体名与内容：删除 A 不删共享文件，删除 B 后才回收；
3. 连续导入/删除 20 次：resolved checkpoint 数量和总字节有上界；
4. 连续导入 A/B/C：不得保留 `[]`、`[A]`、`[A+B]` 这种无限完整 `.anki2` 快照链；
5. 删除大量卡后，logical count 立即归零；compact 完成后 freelist 比例和物理文件大小满足 §16 指标；
6. compact 空间不足/文件锁定：逻辑删除仍成功，maintenance 保持 pending 并可重试，不能复活课程。

### 1.4 单卡“删除”的产品语义

当前卡片浏览器只有 Suspend/Unsuspend，没有单卡 hard delete。本文不顺手新增卡片编辑器；施工时必须：

- UI 继续明确写“暂停”，不得使用“删除”文案；
- source uninstall 是本计划唯一 hard-delete 产品入口；
- 若未来新增单卡 hard delete，必须复用本文 S3/S4/S5 的 owner、projection、media、compact 协议，不得直接调用 `DELETE_CARDS` 后只刷新列表。

---

## 2. 现状审计与已确认根因

所有位置均按 2026-08-30 工作树核实；施工时行号漂移以符号为准。

| # | 根因 | 当前位置 | 影响 |
|---|---|---|---|
| R1 | controller cancel/reset/dispose 只改内存状态 | `anki_import_controller.dart` `cancel/reset/disposeAsync` | 导入继续运行，结果被丢弃，无 rollback |
| R2 | 返回按钮直接 `maybePop` | `anki_import_screen.dart` AppBar leading | preview/source 可被无提示遗弃 |
| R3 | native import 与 attempt note-id 持久化之间有跨库窗口 | `official_anki_import_orchestrator.dart` `importPackage` → `attempts.transition` | 强杀可产生无 owner Collection 数据 |
| R4 | catalog source 在 projection/publish 前就标 `active` | `official_anki_import_orchestrator.dart` `_indexCards` 尾部 | catalog active 不等于产品 active |
| R5 | authority commit 异常被吞 | `unified_anki_import_orchestrator.dart` `publishFromProjection` | done 假成功、staging 永久隐藏 |
| R6 | recovery service 未接生产启动 | `official_anki_recovery_service.dart`；`main.dart` 无调用 | unfinished 只在测试可恢复 |
| R7 | startup census 只分类和写 `scanned`，不执行 action | `official_anki_startup_census.dart` | `rebuildProjection/retryCleanup` 多为纸面建议 |
| R8 | startup cleanup 只处理 `pending_cleanup` | `main.dart` + `AnkiDeckManager.retryPendingOfficialCleanups` | staging/unfinished/active-without-projection 不处理 |
| R9 | preview/project 读取 Collection 全量 schemas/decks | `official_anki_official_first_service.dart`、`official_anki_projection_service.dart` | 旧 notetype/deck 污染新来源 |
| R10 | mapping 主键无 source，deleteSource 明确保留 | catalog `anki_projection_mappings(profile_id, notetype_id)` | mapping 只增不减 |
| R11 | native `DELETE_CARDS` 只删 cards/最终孤儿 note | bridge `ops.rs::delete_cards` | 不删 media/notetype/deck，不压缩 |
| R12 | Official source 没有 media 所有权或 GC | catalog/bridge 均无 source-media 表/操作 | 媒体永久留存 |
| R13 | 每次 import 都完整复制 `.anki2` checkpoint | bridge `import.rs::create_backup` | 多次导入的快照和 live Collection 叠加 |
| R14 | checkpoint 只写 ID，不 restore、不 retention | attempt `checkpoint_id`；生产无 `restoreBackup` 调用 | 备份成为永久垃圾 |
| R15 | storage inventory 按 profile 聚合 Official 目录 | `storage_inventory_service.dart::_scanOfficialDirectories` | 看得到总大，看不到哪个 source/文件可清理 |
| R16 | delete 使用 bool，无法表达逻辑删除/媒体/compact 分阶段状态 | `AnkiDeckManager.uninstall` | UI 只能说完成/待清理，诊断不足 |

### 2.1 必须保留的现有正确能力

以下能力不是重写目标：

- `CourseDatabase` authority 是产品可见性真源；
- `official_anki_projection_index` 是 source→课程树的可重建派生索引；
- Official Collection 是卡片、note、模板、调度和 revlog 的事实源；
- `pending_cleanup` 先保留 owner rows、后删 Collection 的顺序；
- `DELETE_CARDS` 对缺失卡幂等，最后一张卡删除后再删孤儿 note；
- shared-card 不能因为删除一个 source 而破坏另一个有效 source；
- `CardIntroductionStore`、review history、mistake、unification 的现有 source 清理面；
- worker isolate 单 writer 和 operation coordinator；
- projection 的 full atomic rebuild、fingerprint、job/manifest。

---

## 3. 不可破坏的不变量

### 3.1 数据与可见性

1. `anki_course_sources.state = active` 是唯一产品可见条件；
2. `active` 必须意味着下列事实同时成立：
   - Collection 中 source card 集合可读取；
   - catalog source/card associations 完整；
   - projection manifest/index cardinality 通过；
   - placement/presentation identity 完整；
   - authority 指向对应 active projection generation；
3. catalog 的 `anki_sources.state = active` 不得早于 authority active；两者最终语义必须一致；
4. `staging` 必须在“待完成导入”界面可发现，不能只占磁盘；
5. 任何跨库 commit 都允许重放，重复运行不得增加 source、card association 或 placement 数量。

### 3.2 删除与共享所有权

1. 删除 Collection 数据前必须有 durable source ownership snapshot；
2. 删除 owner rows 前必须验证待删 exclusive card IDs 已不在 Collection；
3. shared card 的有效 owner 只包括有继续保留意图的 source；`retired/cancelled/failed/rollback_pending/pending_cleanup` 不得无限保护卡片；
4. app-side cleanup 失败时，journal 必须保留足够信息继续，不得退回 active；
5. source 已隐藏不等于删除完成；物理 maintenance 未完成也必须可见于诊断。

### 3.3 备份、媒体与物理空间

1. rollback checkpoint 是内部事务资产，不是永久用户备份；
2. 每个 in-flight attempt 最多一个当前 checkpoint；
3. checkpoint 只有 `creating/ready/restoring/released/quarantined` 五类状态，文件与元数据必须能互相 census；
4. 媒体只按整个 Collection 的当前引用清理，不能按文件名前缀猜 owner；
5. compact 失败不能撤销已经完成的逻辑删除；
6. `VACUUM` 前必须检查可用空间并释放冲突句柄；
7. 所有 maintenance 操作可重复、可中断、可在下次启动续跑。

### 3.4 隐私与安全

- 日志、receipt 和测试 artifact 只记录 ID、hash、count、bytes、phase、error code；
- 不记录字段正文、卡片 HTML、媒体内容或 API key；
- diagnostics 导出默认不包含卡片内容；
- 任何自动删除仅限 durable evidence 能证明无引用的对象；不明确的数据进入 quarantine。

---

## 4. 目标状态机与提交边界

### 4.1 Source 状态

将 `anki_sources.state` 从“导入内部步骤”收敛为 source 生命周期：

```text
staging
  ├─→ active
  ├─→ rollback_pending → retired
  ├─→ pending_cleanup → retired
  └─→ quarantined

active
  ├─→ pending_cleanup → retired
  └─→ quarantined
```

语义：

| 状态 | 可进课程 | 可继续导入 | 可删除 | startup action |
|---|---:|---:|---:|---|
| `staging` | 否 | 是 | 是 | resume 或等待用户 mapping |
| `active` | 是 | 幂等 noop/更新另立 source | 是 | verify/light reconcile |
| `rollback_pending` | 否 | 否 | 正在执行 | restore/delete partial data |
| `pending_cleanup` | 否 | 否 | 正在执行 | retry hard uninstall |
| `retired` | 否 | 否 | 幂等完成 | checkpoint/maintenance sweep |
| `quarantined` | 否 | 否 | 仅显式修复 | diagnostics，不自动破坏数据 |

### 4.2 Attempt 状态

详细步骤只放在 `anki_import_attempts.state`：

```text
preparing
→ backing_up
→ importing_official
→ indexing_notes
→ indexing_cards
→ preview_ready
→ projecting
→ publish_ready
→ publishing
→ completed
```

旁路：

```text
任意非终态 → cancel_requested → rollback_pending → rolled_back
无法证明 native 是否提交 → native_commit_unknown → rollback_pending/quarantined
可重试错误 → retry_wait → 原步骤
不可安全自动处理 → needs_reconciliation/quarantined
```

### 4.3 User intent

attempt 新增持久化 `user_intent`：

- `continue`：进程中断后恢复；
- `discard`：必须 rollback，不再自动 publish；
- `undecided`：老版本数据迁移或 preview 映射待用户确认；

页面返回时必须先落 intent，再执行或交给后台 saga；不能依赖 controller 是否仍 mounted。

### 4.4 Native commit 三态

attempt 新增：

- `not_started`：可直接删除 staging 元数据；
- `committed`：已有 durable associated note/card IDs，可 resume 或 source delete；
- `unknown`：可能已经写入 Collection，但 catalog receipt 不完整，只能在独占 maintenance lock 下恢复 checkpoint或进入 quarantine。

`IMPORT_PACKAGE` 返回不等于 receipt 已 durable。只有 catalog 同一事务完成下面内容后，才把状态改为 `committed`：

1. associated note IDs；
2. source card descriptors；
3. source notetype/deck association；
4. collection generation / operation token；
5. attempt cursor 和 heartbeat。

### 4.5 最终 active 提交

CourseDatabase 内必须提供一个单事务入口，完成：

1. 校验 projection manifest/index count；
2. upsert placement；
3. upsert presentation；
4. 校验 canonical/placement/presentation cardinality；
5. authority `staging → active`；
6. 写 active projection generation。

不得再把 identity transaction 与 authority commit 拆成两个 transaction；authority 写失败必须向上传播，controller 不得进入 done。

### 4.6 “完成”定义

```text
functionalComplete = source active + projection/identity/authority verified
logicalDeleteComplete = Collection cards absent + owner/app rows retired
physicalMaintenanceComplete = unused media/checkpoint removed + DB compact policy satisfied
```

UI 可以在 `functionalComplete` 后显示导入成功；删除页必须区分 `logicalDeleteComplete` 与后台 `physicalMaintenanceComplete`，但不能把 maintenance pending 隐藏为“已释放全部空间”。

---

## 5. S0 — 复现、审计与失败测试先行

### 5.1 增加统一审计快照

新增只读 `OfficialAnkiStorageAudit`（名称可按现有 convention 调整），一次采集：

- Collection cards/notes/notetypes/decks count；
- catalog 每状态 source/attempt/card association/mapping/job count；
- CourseDB authority/projection/placement/presentation count；
- `collection.anki2`、media DB、catalog、CourseDB、WAL/SHM、media、checkpoint、backup bytes；
- SQLite `page_count/freelist_count/page_size`；
- unused media count/bytes（native 能力落地后补）；
- maintenance job 状态。

输出 JSON receipt，只含 §3.4 允许字段。

### 5.2 失败测试

先新增并确认在旧实现上失败：

| 测试文件/层 | 必测断言 |
|---|---|
| controller widget | parsing cancel 调 native cancel；preview back 不直接 pop；discard await/持久化 rollback |
| import orchestrator | 每个 fault point 重启后的唯一合法状态 |
| startup integration | unfinished/staging/publish_ready 自动恢复或可见待处理 |
| authority integration | authority 注入失败时 controller 不进入 completed |
| cleanup surfaces | Collection delete 后验证 absence，再删 catalog |
| source-scoped preview | A 删除后 B schemas/decks 无 A |
| mapping lifecycle | refcount 归零后 orphan mapping 删除 |
| native media | 独占/共享/模板静态媒体 GC |
| checkpoint | 成功、取消、强杀、重复恢复后的文件上界 |
| physical size | delete+maintenance 后 freelist/bytes 收敛 |

### 5.3 Fault points

保留现有 fault points，并新增：

- `afterNativeImportBeforeReceiptCommit`；
- `afterReceiptBeforeCardIndexComplete`；
- `afterPreviewReady`；
- `midProjectionPublish`；
- `afterProjectionBeforeIdentityCommit`；
- `midIdentityAuthorityTransaction`；
- `afterActiveBeforeCheckpointRelease`；
- `afterCollectionDeleteBeforeVerification`；
- `afterCollectionDeleteBeforeAppCleanup`；
- `midMediaTrash`；
- `afterCheckpointFileDeleteBeforeMetadataRelease`；
- `midCompact`。

测试不能只调用 fake 成功路径；至少一组必须跑真实文件型 SQLite，native 相关在 Rust fixture 上执行。

### 5.4 S0 验收

- 旧代码上复现 A/B/C 三类问题，失败原因与本文一致；
- audit before/after artifact 可比较；
- 无行为修复混入 S0 commit；
- 不因测试临时文件改变生产目录。

---

## 6. S1 — P0 导入控制权与 UI 退出补偿

### 6.1 Saga 必须脱离页面生命周期

把长操作所有权从 `AnkiImportController` 移到 application service：

```text
OfficialAnkiImportSagaCoordinator
  - start(path, plan)
  - requestCancel(attemptId)
  - requestDiscard(attemptId)
  - resume(attemptId)
  - observe(attemptId)
```

Controller 只订阅 durable attempt 状态并发送 intent。页面 dispose 不再“取消 future 并忘记结果”；后台 coordinator 即使失去页面，也必须完成当前原子步骤并留下下一启动可恢复的 journal。

### 6.2 Cancel 行为

1. `requestCancel` 先把 `user_intent=discard/state=cancel_requested` 落库；
2. 调 worker session 的真实 `cancel()`；
3. 等 native 返回：
   - 明确未提交：删 staging rows，释放 checkpoint；
   - 已提交且 receipt 完整：走 source-scoped rollback delete；
   - commit unknown：进入 S2 checkpoint restore；
4. UI 只有收到 `rolled_back` 或 durable `rollback_pending` handoff 后才允许退出；
5. timeout 不得丢状态，显示“已安排清理，重启后继续”。

现有 orchestrator 的静态 `cancel` 参数不得继续作为 UI cancel 主通道；它可保留为测试 seam，最终应由 coordinator 的动态 cancel 统一。

### 6.3 Back/系统返回行为

使用 `PopScope` 或当前 Flutter 等价 API：

| 页面状态 | 返回行为 |
|---|---|
| selecting | 直接返回 |
| importing/indexing/projecting/publishing | 对话框：继续等待 / 取消并清理；禁止无提示 pop |
| preview_ready | 对话框：稍后继续 / 放弃并清理；“稍后继续”保留可见 pending import |
| completed | 直接返回 |
| rollback_pending | 可返回，但 durable cleanup 必须继续；显示状态入口 |

### 6.4 Authority fail-closed

- 删除 `publishFromProjection` 对 authority upsert/commit 的吞异常；
- `AnkiUnificationDao` 或 `AnkiOwnerAuthorityDao` 缺失时不得提前返回伪成功；
- identity + authority 放进 §4.5 的单事务；
- 完成后读回 authority row、generation 和 cardinality；
- done 页只有读回验证成功才出现。

### 6.5 Pending import 产品入口

Course management 或导入首页增加“待完成导入”区域，至少显示：

- display name；
- phase；
- card count（已知时）；
- 上次错误的人类可读描述；
- “继续”“放弃并清理”；

它不是 active course，不得进入课程复习；但也不能不可见。

### 6.6 S1 验收

- controller dispose 后 saga 不丢；
- cancel 注入所有时序均落到 terminal/pending durable 状态；
- authority 失败时 done 不出现；
- pending import 在重启后可见；
- 任何路径不会创建第二个相同 attempt writer。

---

## 7. S2 — 启动恢复与 ambiguous native commit 处理

### 7.1 启动顺序调整

目标启动顺序：

```text
打开 CourseDatabase / 应用 restore
→ 初始化 shared Official catalog
→ 获取 profile maintenance exclusive lease
→ census unfinished import + staging + pending cleanup + maintenance
→ 启动/复用 Official worker
→ 执行有确定证据的恢复
→ 释放或降级 lease
→ CourseProvider.load（只读 active authority）
→ 后台执行非阻断 physical maintenance
```

恢复失败不能阻止内置 Turkish 课程启动，但必须保留 pending/quarantine 状态和入口。

### 7.2 Recovery matrix

| attempt/source 证据 | 自动动作 | 禁止动作 |
|---|---|---|
| preparing，native 未开始 | 清 attempt/source staging；删 checkpoint partial | 打开 active |
| backing_up，checkpoint 未 ready | 删除 partial；重建 checkpoint 或等待用户 | 使用不完整 backup |
| importing，native=`not_started` | 回到 backing_up/import | 猜测已提交 |
| importing，native=`unknown`，checkpoint 可用且无后续 generation | restore checkpoint → media GC → rolled_back | 在后续 mutation 后覆盖 Collection |
| importing，unknown，checkpoint 不可安全 restore | quarantine + diagnostics | 自动删当前 Collection |
| indexing_notes/cards，associated IDs 完整 | 从 cursor 继续，批次幂等 upsert | 从 0 创建第二 source |
| preview_ready，需要 mapping | 展示 pending import，等待用户 | 自动确认低置信 mapping |
| preview_ready，不需要用户决策 | 可后台进入 projecting | 改 scheduler/revlog |
| projecting/publish_ready | 校验或重建 projection，再走 §4.5 | 重跑 native import |
| authority staging + 完整 projection/identity | 幂等 authority active commit | 新建 source ID |
| catalog active + authority 非 active（旧版） | 降回 staging 语义后按证据恢复 | 直接相信 catalog active |
| pending_cleanup | S3 重试 | 删除 owner rows 后再找 cards |
| active + projection 缺失 | projection-only rebuild | 重导 APKG、重置 scheduler |
| retired + maintenance pending | S5–S7 后台继续 | 复活 course |

### 7.3 Checkpoint restore 安全条件

只有同时满足才允许自动 restore：

1. checkpoint `ready` 且完整性验证通过；
2. attempt 是该 profile 最后一个可能改变 Collection 的操作；
3. checkpoint generation 与 journal 的 pre-import generation 一致；
4. 之后无 answer/import/delete/undo/redo receipt；
5. maintenance exclusive lease 已阻止新操作；
6. restore 后 Collection check 通过。

若条件不全，必须 quarantine；不能为了清垃圾覆盖用户后来产生的学习记录。

### 7.4 旧版本无主数据

对 “native 已提交、note IDs 未落库” 的老数据，按优先级：

1. 有可验证 checkpoint 且满足 §7.3：restore；
2. checkpoint 与当前 Collection 可安全 diff：由 native 只读 `DIFF_COLLECTION_CHECKPOINT`（候选能力）返回新增 note/card IDs，再建立 source association 或执行删除；
3. APKG 文件仍可访问且 hash 一致：只用于 identity 对拍，不直接再次 import；
4. 无法证明：quarantine，提供诊断导出和用户确认的“保留 Collection / 重置 Official Anki 数据”高级操作；绝不静默删。

### 7.5 Recovery lease

lease 至少包含：

- profile ID；
- owner token；
- operation kind；
- acquired/heartbeat/expires timestamp；
- process/session identity；

worker import、review write、delete、restore、media GC、compact 都必须经过同一 coordinator；启动恢复期间 scheduler 写 fail-closed 为 busy，而不是并行穿透。

### 7.6 S2 验收

- fault matrix 每一点重启后都到预期状态；
- `recoverUnfinished()` 不再只存在于测试；
- census 的 action 有生产 executor，且只执行白名单 action；
- ambiguous restore 不会覆盖后续 review mutation；
- 连续启动恢复两次结果完全幂等。

---

## 8. S3 — 可验证的 hard-uninstall saga

### 8.1 返回模型

把 `Future<bool> uninstall(...)` 升级为结构化结果（具体命名按现有 style）：

```text
OfficialAnkiUninstallResult
  sourceId
  phase
  logicalDeleteComplete
  collectionCardsRequested
  collectionCardsRemoved
  collectionCardsRemaining
  appRowsRemaining
  mediaGcPending
  compactPending
  retryable
  errorCode
```

UI 兼容层可临时把结果映射为 completed/pending/failed，但内部不得继续只用 bool。

### 8.2 删除步骤

```text
D0 acquire maintenance lease
D1 authority/source → pending_cleanup（先隐藏）
D2 durable cleanup receipt + ownership snapshot
D3 计算 target/exclusive/shared card set
D4 分批 native DELETE_CARDS
D5 重新查询并验证 exclusive IDs 全部 absent
D6 删除 projection/vocabulary/unification/history/mistake/introduction
D7 删除 catalog source associations/attempt/jobs/overrides
D8 authority → retired
D9 enqueue metadata prune/media GC/checkpoint release/compact
D10 receipt logical_complete；maintenance 后 physical_complete
```

D4–D8 任一步强杀，下次启动必须从 receipt 重放；每步必须幂等。

### 8.3 Ownership snapshot

删除前 snapshot 至少记录：

- source card IDs、note IDs、notetype IDs、deck IDs；
- 每张 card 的其他有效 source owners；
- projection generation/cardinality；
- source hash；
- attempt/checkpoint references；
- cleanup generation。

snapshot 只存 ID/hash，不存正文。

### 8.4 Shared-card 判定

当前仅按“catalog 中存在 sibling source row”判断不够。新规则：

```text
retainingOwners(cardId) = sibling association
  ∩ source state in {staging-with-continue-intent, active, repairing}
```

- `retired/cancelled/failed/rollback_pending` 不保留；
- `pending_cleanup` 表示删除意图，不应无限保护；
- staging 只有 `user_intent=continue` 且 attempt 可恢复时才保留；
- 同一 profile 所有 delete 串行，ownership snapshot 带 generation，变化则重算；
- 删除 A 后 B 仍拥有 card 时只删 A association；删除最后 owner 时才删 Collection card。

### 8.5 验证而不是相信 removed count

`DELETE_CARDS.removedCards` 不能独自证明成功，因为重试时缺失卡返回 0 也是合法。D5 必须通过批量 descriptor/search 读回：

- exclusive IDs 全部 missing；
- shared IDs 仍存在；
- 最后一张 card 删除后 note 不存在；
- scheduler/search/projection snapshot generation 已失效；

验证失败保留 owner snapshot 和 `pending_cleanup`，不得执行 D7。

### 8.6 不完整 source index

若 source 声称 active/staging，但 catalog card count 小于 import receipt/Collection diff：

- 禁止按部分 ID 删除后清 source row；
- 先 S2 reconstruct association；
- 无法 reconstruct 时 quarantine；
- diagnostics 显示“所有权索引不完整”，不得显示“删除成功”。

### 8.7 S3 验收

- 成功删除后 source exclusive cards 在真实 Collection 中为 0；
- 每个 D0–D10 fault 重启可收敛；
- A/B shared-card 矩阵无误删、无永久保护；
- owner rows 仅在 Collection verification 后删除；
- UI 能区分 logical complete 与 maintenance pending。

---

## 9. S4 — Source-scoped deck/notetype/mapping 与元数据清理

### 9.1 建立 source 元数据关联

Official catalog 增加：

```sql
CREATE TABLE anki_source_notetypes (
  source_id TEXT NOT NULL REFERENCES anki_sources(source_id) ON DELETE CASCADE,
  notetype_id INTEGER NOT NULL,
  schema_fingerprint TEXT NOT NULL,
  PRIMARY KEY (source_id, notetype_id)
);

CREATE TABLE anki_source_decks (
  source_id TEXT NOT NULL REFERENCES anki_sources(source_id) ON DELETE CASCADE,
  deck_id INTEGER NOT NULL,
  PRIMARY KEY (source_id, deck_id)
);
```

`OfficialAnkiCardDescriptor` 候选新增 `notetypeId`；若 contract 评审认为 descriptor 不应扩大，则新增 source metadata batch op。两种方案只能选一套，禁止同时保留重复 RPC。

### 9.2 Preview source scope

- `preparePreview` 从 source associations 得到 notetype IDs，显式传给 `getProjectionSchemas(notetypeIds: ...)`；
- deck tree 从 source deck IDs 过滤，保留必要祖先用于层级展示；
- synthetic root 和 Default 只在当前 source 真有卡时出现；
- projection service 使用同一 frozen source scope，不能 preview 一套、publish 又读全 Collection；
- source scope fingerprint 加入 notetype/deck association hash，变化时失效。

### 9.3 Mapping 生命周期

保留 profile+native notetype ID 的全局复用价值，但加引用约束：

1. mapping 只对 schema fingerprint 完全一致的 source 生效；
2. source delete 后计算剩余 `anki_source_notetypes` 引用；
3. 引用为 0 且 Collection use_count=0：删除 mapping；
4. 引用为 0 但 Collection 仍有 notes：先 reconstruct owner/quarantine，不删 mapping；
5. user-confirmed mapping 遇 fingerprint 变化继续进入 review，不静默套用；
6. 一次性 migration 清理可证明 orphan 的 mapping。

### 9.4 Empty notetype/deck prune

新增 native metadata prune（可合并为一个 operation）：

- 输入候选 notetype/deck IDs，来自删除 snapshot；
- native 再次验证 use count/card count 为 0；
- stock notetype、Default deck、仍为其他 source ancestor 的 deck 禁删；
- notetype 删除前验证无 notes；
- deck 删除从叶到根，仅删候选和空祖先；
- 返回 pruned/skipped/reason counts；
- prune 失败只进入 maintenance pending，不影响 logical delete。

若第一波不安全，最低可接受止血是“source-scoped preview + mapping ref cleanup”；native empty metadata prune 可单独后置，但必须保留 task 和验收，不得写已完成。

### 9.5 修改版 APKG 的语义

当前 exact hash dedupe 不等于“更新同一个牌组”。本计划不凭文件名自动替换旧 source：

- hash 完全相同：幂等返回原 source；
- hash 不同：默认新 source，UI 明确提示可能与已有 deck/note GUID 重叠；
- 未来要支持 replace/update，必须先设计稳定 source identity 和用户确认；
- overlapping GUID/card 仍按 shared-owner 处理，不能因为显示名相同就删除旧 source。

### 9.6 S4 验收

- A 删除后 B preview/project 读取不到 A-only schema/deck；
- mapping count 在循环测试后回到基线；
- shared notetype/deck 在最后 owner 删除前保留；
- source scope preview 与最终 projection card/notetype/deck 集合一致；
- prune 不删除 stock/default/非空 metadata。

---

## 10. S5 — Official media GC

### 10.1 原则

不维护“导入时复制了哪些文件，因此删除 source 就删哪些文件”的脆弱所有权模型。Anki 媒体会因同名、模板静态引用、共享 note、CSS/字体等产生跨 source 引用，权威判据只能是：

> 删除目标 cards/notes 后，扫描整个当前 Collection 的 note/template 引用，只有全局 unused 文件才可删除。

### 10.2 Native 能力

优先新增一个 bounded native operation，例如：

```text
GC_UNUSED_MEDIA
request:
  mode: dryRun | trashAndDelete
  maxFilesPerBatch / continuationToken（若上游 API 需要）
response:
  scannedFiles
  unusedFiles
  removedFiles
  remainingFiles
  reclaimedBytes
  trashBytes
  collectionGeneration
```

具体 operation ID 从施工时 contract 单表的下一个未占用编号分配；不得依据本文预占号码。Contract major 保持 1，minor 从当前 1.10 的下一个可用值递增，并同步：Rust/Dart op table、capabilities、VERSION、operations.md、fixtures、fake、worker/session/engine。

实现复用 rslib `check_media`、`trash_media_files`、`empty_trash` 语义，不在 Dart 重新解析 HTML/CSS 媒体引用。大目录不得把全部 filename 放进 8 MiB envelope；生产回复只返回 count/bytes，测试 seam 可返回受限样本。

### 10.3 执行顺序

1. 停止 Official audio player/WebView 对目标媒体的活跃读取；
2. 获取 maintenance exclusive lease；
3. 确认 collection logical delete 已完成；
4. `check_media` 得到全局 unused；
5. 文件进入 trash；
6. 更新/同步 media DB；
7. 验证 remaining notes/templates 不报告 missing；
8. empty trash；
9. 写 reclaimed bytes receipt。

文件锁或进程中断时保持 `media_gc_pending`，下次重跑 check；不能因部分 trash 导致 active source missing media。

### 10.4 必测媒体矩阵

- note 字段图片/音频；
- 模板/CSS 静态字体和背景图；
- cloze/type answer/AV tag；
- A/B 共用同名同内容；
- A/B 同名不同内容被 Anki rename；
- Unicode、空格、括号、NFC/NFD；
- media.trash 中断恢复；
- WebView/audio 文件句柄锁定；
- 10k 文件性能与响应 payload 上限；
- 删除后 active source 全量 media check 无 missing。

### 10.5 S5 验收

- 独占媒体全部回收；
- 共享/模板静态媒体不误删；
- GC 强杀可重入；
- response 不泄漏字段正文/完整文件清单；
- media DB 与目录一致；
- 回收 bytes 进入 storage diagnostics。

---

## 11. S6 — Checkpoint、Anki backup 与保留策略

### 11.1 分离两种概念

```text
rollback checkpoint：一次 import saga 的内部临时恢复点
user/Anki backup：用户预期可长期恢复的正式备份
```

当前 `create_backup` 同时调用 Anki `maybe_backup()` 并额外复制完整 `.anki2`，职责混合。整改：

- import saga 使用专用 `checkpoints/<attemptId>.anki2`；
- 一次 attempt 最多一个 checkpoint；
- checkpoint 创建必须 atomic copy + fsync + independent open/check；
- 不在每次 import checkpoint 时额外触发一份长期 `.colpkg`；
- 正式 Anki backup 继续走其独立保留策略，不由 import 次数隐式触发；
- checkpoint 不进入普通远程备份的长期对象集合，除非 manifest 明确标为 unresolved recovery asset。

### 11.2 Checkpoint metadata

Catalog 新增 `anki_checkpoint_files`：

```text
checkpoint_id PK
attempt_id UNIQUE
source_id
relative_path
state
bytes
pre_import_generation
sha256（或可验证等价摘要）
created_at_millis
updated_at_millis
released_at_millis
last_error_code
```

状态与文件操作顺序：

```text
creating → ready → restoring → released
                     └────────→ quarantined
```

- 先写 `creating`，临时文件 fsync+rename 后写 `ready`；
- 成功 active 且读回验证完成后标 release intent，再删文件，再写 `released`；
- 文件已删、metadata 未更新时重试只补状态；
- metadata 已 released、文件仍在时 startup sweep 删除已知 orphan；
- unresolved attempt 的 ready checkpoint 永不按年龄自动删。

### 11.3 保留策略

新数据硬上限：

- resolved attempt：0 个 rollback checkpoint；
- 每个 in-flight attempt：最多 1 个；
- 同 profile 正常只允许 1 个 import writer，因此正常最多 1 个 ready checkpoint；
- quarantined checkpoint 单独计数、用户确认前保留；
- 正式 user/Anki backup 按独立产品设置，不与 rollback checkpoint 混算。

### 11.4 存量 `backups/bk-*.anki2` 迁移

第一版不得直接全删：

1. 列出所有文件；
2. 用 unfinished attempt `checkpoint_id` 标出 referenced；
3. 对 referenced 做完整性校验并迁入 metadata；
4. unreferenced 老文件标 `legacy_unknown`；
5. diagnostics 展示数量/字节，并提供“保留最新安全副本 + 清理其余内部导入检查点”的用户确认操作；
6. 只有能证明由已完成 attempt 创建且另有有效 active Collection/正式备份的文件，才允许自动按保留规则清理；
7. `.colpkg` 与 `.anki2` 分开计数，不把正式备份误认成内部 checkpoint。

后续版本在 metadata 覆盖率达到 100% 后，才允许完全自动 retention。

### 11.5 S6 验收

- 导入成功/取消/rollback 后 resolved checkpoint 为 0；
- 强杀不丢唯一可用 checkpoint；
- 20 次导入不会生成 20 个完整内部 `.anki2`；
- 正式 backup 不被误删；
- legacy unknown 先报告后处理；
- checkpoint release fault matrix 幂等。

---

## 12. S7 — SQLite 物理压缩与 maintenance 调度

### 12.1 分层

| 数据库 | logical delete | compact/回收 |
|---|---|---|
| `collection.anki2` | native remove cards/notes | native maintenance op / check_database optimize |
| `official_catalog.sqlite` | source/mapping/job/checkpoint rows | WAL checkpoint + VACUUM |
| `course.db` | projection/identity/history rows | Drift 外层 maintenance + WAL checkpoint/VACUUM |
| `collection.media.db2` | media GC 同步 | rslib media maintenance |

### 12.2 Collection compact

不要继续把完整 `CHECK_COLLECTION` 同时当“完整性检查”和“普通删除压缩”的隐式工具。候选方案：

- 新增专用 `COMPACT_COLLECTION` operation；或
- 明确复用 `CHECK_COLLECTION`，但 contract/进度/UI 标注其会执行 full DB check + `vacuum/reindex/analyze`。

优先专用 operation，返回：before/after bytes、page/freelist、elapsed、skipped reason。执行前：

- 无 import/review/delete/render writer；
- disk free 满足 SQLite VACUUM 临时空间预算；
- Collection 句柄按 rslib 要求关闭/重开；
- 失败后原数据库仍可打开并通过 quick check。

### 12.3 Catalog 与 CourseDatabase

- catalog 多连接 WAL 模式下先让 worker/main reader 释放或切换共享句柄；
- `PRAGMA wal_checkpoint(TRUNCATE)` 后再 VACUUM；
- CourseDatabase VACUUM 不得在 transaction 内执行；
- 维护期间 CourseProvider/DAO 写入经 maintenance gate 排队或 fail busy；
- compact 完成后重新打开句柄并验证 schema/user_version；
- remote backup snapshot 与 compact 不并行。

### 12.4 触发策略

候选默认阈值（须用设备性能实测确认后固化）：

- 最后一个 Official source 删除：安排一次完整 maintenance；
- `freelist_bytes >= 16 MiB` 且 `freelist/page_count >= 20%`：安排 compact；
- 未达阈值：记录 logical free，不立即 VACUUM；
- 用户在存储页明确点“优化”：忽略比例阈值，但仍检查空间/锁；
- 不在 UI 主 isolate 同步执行；
- 低电量/空间不足时可推迟，但状态必须可见。

阈值不是放宽验收的借口；最终以 logical counts、freelist 和 physical bytes 三者共同判断。

### 12.5 Maintenance job

Catalog 新增 `anki_maintenance_jobs`：

```text
job_id PK
profile_id
source_id nullable
kind: media_gc | metadata_prune | checkpoint_release | compact_collection | compact_catalog | compact_course
state: pending | running | retry_wait | completed | failed | quarantined
input_generation
attempt_count
before_bytes
after_bytes
reclaimed_bytes
created/heartbeat/completed
last_error_code
```

同 kind/profile 幂等合并，防止每删一张卡排一个重复 VACUUM。

### 12.6 S7 验收

- logical delete 不等待长 VACUUM 才隐藏课程；
- maintenance 最终可收敛且有 receipt；
- 空间不足、文件锁、强杀测试不损坏数据库；
- active course 在 compact 后可正常 browse/render/review；
- storage 页面显示“可回收”“待优化”“已释放”而非只显示总大小。

---

## 13. S8 — 存量 census、修复中心与一次性迁移

### 13.1 Census 分类

升级 `OfficialAnkiStartupCensus`，至少识别：

| 类别 | 典型证据 | 默认动作 |
|---|---|---|
| clean active | Collection/catalog/projection/authority cardinality 一致 | 正常使用 |
| unfinished resumable | attempt cursor/IDs 完整 | 自动 resume |
| preview pending | source indexed、无 projection、mapping 待确认 | 显示继续/放弃 |
| publish pending | projection/identity 完整、authority staging | 自动 commit active |
| rollback pending | discard intent/checkpoint | 自动 rollback |
| cleanup pending | pending_cleanup + owner snapshot | 自动 hard-delete resume |
| active projection missing | authority official、Collection 完整 | projection-only rebuild |
| orphan mapping | 无 source refs、Collection use=0 | maintenance prune |
| orphan empty metadata | candidate notetype/deck use=0 | maintenance prune |
| unused media | media check unused >0 | media GC（按策略/确认） |
| stale checkpoint | resolved attempt + known internal checkpoint | release |
| ambiguous collection owner | Collection 数据无法关联 source | quarantine |
| authority/projection ghost | projection rows有、authority 非 active且无 attempt | reconstruct/quarantine |

### 13.2 Repair executor

当前 reconciler 只给 `autoAction`；新增白名单 executor：

- `resumeImport`；
- `resumeProjection`；
- `commitAuthority`；
- `restoreCheckpoint`；
- `retryCleanup`；
- `enqueueMaintenance`；
- `quarantine`。

所有 action 前重新读取 evidence hash；hash 改变则放弃旧决定并重算，禁止按 stale census 执行破坏性操作。

### 13.3 用户可见修复中心

存储页或课程管理页展示：

- 待完成导入；
- 待清理牌组；
- 隔离数据；
- 内部 checkpoint/正式 backup 分项；
- Collection DB、catalog、CourseDB、media 的实际字节；
- unused media 和 SQLite freelist 可回收字节；
- 每个 maintenance job 状态和最后错误；
- “继续导入”“放弃并清理”“重试清理”“优化数据库”“导出诊断”。

不再把整个 profile 作为唯一 `ownerId` 后只给一个总数；Official source 和 profile 共享资产必须分层显示。

### 13.4 一次性 migration 顺序

```text
M0 additive schema migration
M1 只读 census + artifact
M2 backfill source notetype/deck associations（只读 Collection）
M3 classify attempts/source states；不自动破坏 ambiguous 数据
M4 自动恢复白名单 safe cases
M5 prune provable orphan mapping/metadata
M6 checkpoint inventory/retention
M7 media dry-run → safe GC
M8 compact threshold assessment
M9 写 migration receipt/version
```

M0–M9 任一步失败保留 cursor，下一启动续跑；不得因 migration 失败重建/清空用户数据库。

### 13.5 S8 验收

- 构造每个 census 类别的 fixture；
- safe action 自动收敛，ambiguous 一律 quarantine；
- evidence hash CAS 防 stale action；
- migration 强杀逐步恢复；
- 老版本 staging/active-without-authority 不再永久隐身；
- 用户可定位占用来自卡片、媒体、checkpoint 还是 freelist。

---

## 14. Schema、contract 与代码落点

### 14.1 Official catalog v10 → v11（候选）

Additive migration，禁止先 drop/rename 老列：

1. `anki_import_attempts` 新增列：
   - `user_intent TEXT NOT NULL DEFAULT 'undecided'`；
   - `native_commit_state TEXT NOT NULL DEFAULT 'unknown'`；
   - `pre_import_generation INTEGER`；
   - `committed_generation INTEGER`；
   - `projection_generation TEXT`；
   - `cleanup_phase TEXT`；
   - `checkpoint_bytes INTEGER`（若 checkpoint table 已存则不重复，二选一）；
2. 新表 `anki_source_notetypes`；
3. 新表 `anki_source_decks`；
4. 新表 `anki_checkpoint_files`；
5. 新表 `anki_maintenance_jobs`；
6. 必要索引：attempt state/intent、maintenance state/profile、notetype/deck reverse lookup；
7. migration 在 transaction 内完成，filesystem backfill 不放 schema transaction；
8. future schema 继续 fail-closed。

施工前先复核字段是否已由并行波次加入，避免重复 schema。

### 14.2 CourseDatabase v22 → v23（候选）

尽量不新增平行 authority：

- 复用 `anki_course_sources` 单一 visibility；
- identity + authority active 改成同一个 CourseDatabase transaction；
- 如现有 `course_scope_repair_journal` 能承载 receipt，优先复用；否则只增加最小 recovery receipt 字段/表；
- 不新增第二个 `visible` bool；
- migration 后 built-in course 和 legacy pending 数据不变。

### 14.3 Contract 1.10 → 下一个可用 minor

候选变更：

- descriptor 增 `notetypeId`，或新增 source metadata batch op（二选一）；
- `GC_UNUSED_MEDIA`；
- metadata prune；
- compact collection；
- 可选 checkpoint diff；
- delete response 增 verification-friendly count/generation（保持旧字段兼容）。

全链路清单：

1. Rust OP table/handler/dispatch/capabilities；
2. Dart operation table/engine interface/FFI；
3. worker handlers/session/session-engine；
4. fake engine；
5. `contract/VERSION` 与 `operations.md` append-only；
6. request/response DTO/golden fixtures；
7. capability integrity tests；
8. fixture generator regen；
9. Android `.so` rebuild + APK 内能力核验。

### 14.4 主要 Dart 落点

- `application/anki_import/anki_import_controller.dart`：只保留 UI state adapter；
- `application/anki_official/import/official_anki_import_orchestrator.dart`：attempt phase/receipt；
- 新/现有 application coordinator：durable saga、cancel、resume；
- `official_anki_official_first_service.dart`：source-scoped preview/publish；
- `unified_anki_import_orchestrator.dart`：identity+authority 单事务、异常不吞；
- `official_anki_recovery_service.dart`：生产启动 executor；
- `official_anki_startup_census.dart`：分类 + evidence CAS；
- `anki_deck_manager.dart`：structured uninstall + verification + maintenance enqueue；
- `official_anki_source_dao.dart` / `official_anki_database.dart`：schema/association/checkpoint/job；
- `official_anki_projection_service/store.dart`：source scope 与幂等 publish；
- `course_catalog.dart` / course management / storage diagnostics：pending/quarantine 可见；
- `main.dart` 或启动 service：恢复顺序，不堆 unawaited 互相竞争任务。

### 14.5 主要 Rust 落点

- `bridge/src/import.rs`：专用 checkpoint create/restore/diff；
- `bridge/src/ops.rs`：delete verification-friendly response、metadata prune、maintenance；
- `bridge/src/projection.rs` / `query.rs`：descriptor notetype/source metadata；
- `bridge/src/engine.rs`：operation table/dispatch/generation/maintenance gate；
- vendored rslib media service：优先调用公开 service，不复制解析器；
- contract tables/fixtures/generator。

---

## 15. 施工波次、依赖与 commit 纪律

### 15.1 顺序

```text
S0 失败复现 + audit
  ↓
S1 controller/control-plane + authority fail-closed
  ↓
S2 durable startup recovery + checkpoint restore
  ↓
S3 verified hard uninstall
  ├─→ S4 source-scoped metadata/mapping
  ├─→ S5 media GC
  └─→ S6 checkpoint retention
          ↓
        S7 physical compact
          ↓
        S8 存量 migration + repair center + release matrix
```

S4/S5/S6 可在 S3 ownership snapshot 契约冻结后并行开发，但不能并行修改同一 contract table/版本文件；由一个集成 commit 分配 operation IDs 和 minor。

### 15.2 建议独立 commits

1. `test(anki): reproduce abandoned import and storage leaks`；
2. `refactor(anki): move import ownership out of wizard lifecycle`；
3. `fix(anki): persist cancel intent and block false completion`；
4. `fix(anki): recover unfinished official imports at startup`；
5. `fix(anki): make source uninstall verified and resumable`；
6. `feat(anki): scope deck and notetype metadata to source`；
7. `feat(anki): garbage collect unreferenced official media`；
8. `fix(anki): bound rollback checkpoint retention`；
9. `feat(storage): compact official databases through maintenance jobs`；
10. `feat(storage): expose official repair and reclaim status`；
11. `fix(anki): reconcile legacy staging and orphan metadata`；
12. `docs(anki): record lifecycle/storage remediation receipt`。

实际提交遵循仓库 commit 格式；不得把 native contract、schema migration、UI 重构和大规模格式化塞进一个不可回滚 commit。

### 15.3 兼容与发布顺序

1. additive readers 先兼容旧 schema/state；
2. 写入新 journal，但旧 UI 仍可只读；
3. 新 native `.so` 和 Dart contract 同版本发布，不允许半升级；
4. 启用 recovery executor；
5. 启用 verified delete；
6. 启用 source-scoped preview；
7. media/checkpoint/compact maintenance 先 dry-run 收据，再执行；
8. 最后处理 legacy unknown backup/quarantine 用户操作；
9. 完整升级安装/强杀矩阵通过前保持生产 NO-GO。

---

## 16. 测试、性能与 Go/No-Go 门禁

### 16.1 Dart 定向门禁

至少覆盖：

```text
test/views/anki/anki_import_controller_test.dart
test/views/anki/anki_import_official_first_test.dart
test/application/anki_official/official_anki_import_orchestrator_test.dart
test/application/anki_official/official_anki_recovery_test.dart
test/application/anki_official/official_anki_cleanup_surfaces_test.dart
test/application/anki_official/official_anki_projection_test.dart
test/application/anki_official/official_anki_projection_ordering_test.dart
test/application/maintenance/storage_inventory_service_test.dart
```

新增 file-backed/fault/maintenance suites，不能全靠 `FakeOfficialAnkiEngine`。

### 16.2 Native 门禁

在工具链主机执行项目约定命令，至少证明：

- bridge 全量 Rust tests；
- APKG fixture import/delete/reopen；
- media GC shared/static/Unicode；
- checkpoint create/restore/independent open；
- delete/search/projection generation；
- compact 前后 integrity；
- operation/capability/fixture exact parity；
- fixture regeneration diff 审核；
- Android arm64 `.so` rebuild。

### 16.3 Flutter 全量门禁

- `flutter analyze`：0 新增问题；
- `flutter test`：0 新增失败；
- 既存 Windows 环境失败必须按 `test/BASELINE.md` 逐项对照，不得笼统豁免；
- 测试数变化更新 `test/BASELINE.md`；
- import、course management、storage diagnostics 的 light/dark/text-scale widget/golden 按现有基线执行。

### 16.4 量化正确性门禁

| 指标 | GO 条件 |
|---|---|
| abandoned import | 0 个永久不可见且无 pending/quarantine 入口的 source |
| source active | Collection/catalog/projection/identity/authority cardinality 全等 |
| source delete | exclusive Collection card remaining = 0；source app rows = 0/retired receipt |
| stale preview | 删除 A 后导入 B，A-only deck/notetype/mapping 展示 = 0 |
| mapping | 无引用、use_count=0 的 orphan mapping = 0 |
| media | active refs missing = 0；已确认 unused files 在 GC 后 = 0 |
| checkpoint | resolved attempt checkpoint = 0；每 in-flight attempt ≤1 |
| maintenance | pending job 可重启收敛，无重复同 kind/profile active writer |
| false success | authority/identity 注入失败时 completed UI = 0 |

### 16.5 量化空间门禁

固定同一设备、同一 fixture、清晰记录 before/after：

1. 导入 10 MiB 独占媒体 source，再删除并跑 maintenance；最终增量不得包含该 10 MiB 媒体；
2. 连续 20 次导入/删除后：
   - resolved rollback checkpoint bytes = 0；
   - unused media bytes = 0；
   - active/source/card/projection count 回到基线；
   - DB 剩余增量只能是明确记录的 schema/SQLite 最小页误差，不得随循环近似线性增长；
3. 连续导入 A/B/C 时，内部完整 `.anki2` checkpoint 数不得随已完成 import 数增长；
4. compact 后 `freelist_bytes` 低于触发阈值，或有明确 `skipped_insufficient_space` receipt；
5. storage diagnostics 的 reclaimed bytes 与文件系统扫描误差在已解释范围内。

### 16.6 Android 真机强杀矩阵

每个场景至少在 debug/release 各跑一轮，release 结果才计生产门禁：

| 场景 | 强杀点 | 重启期望 |
|---|---|---|
| import | native 前 | 清 staging/可重试 |
| import | native 后 receipt 前 | restore/quarantine，不无主 |
| index | 中批 cursor | resume |
| preview | 用户未确认 | pending import 可见 |
| projection | transaction 中 | 原子回滚/重建 |
| publish | authority 前 | 幂等 active commit |
| cancel | native busy | rollback pending→rolled_back |
| uninstall | collection delete 后 | verify + app cleanup resume |
| media GC | trash 中 | rerun，无 active missing |
| checkpoint release | file/meta 间 | sweep 收敛 |
| compact | vacuum 中/空间不足 | DB 可打开，job pending/failed 可重试 |

### 16.7 NO-GO 条件

任一成立即 NO-GO：

- 存在不可发现的 staging/unfinished source；
- cancel/back 可留下无 journal 的 Collection 数据；
- authority 失败仍显示完成；
- owner rows 在 Collection deletion verification 前被删除；
- media GC 误删 active 引用；
- checkpoint retention 可无界增长；
- migration 会自动删除 ambiguous/legacy unknown 数据；
- compact 后数据库无法 reopen/check；
- native contract/fixture/Android `.so` 未同版本验证；
- 仅用 fake/widget test 代替真机强杀和物理字节证据。

---

## 17. 风险、缓解与明确不做

### 17.1 风险表

| 风险 | 等级 | 缓解 |
|---|---|---|
| restore 旧 checkpoint 覆盖后续复习记录 | 极高 | §7.3 generation + exclusive lease 六条件；不满足即 quarantine |
| incomplete index 导致只删部分 source cards | 极高 | D5 Collection absence verification；索引不完整先 reconstruct |
| media GC 误删共享/模板静态资源 | 极高 | 复用 rslib 全 Collection media checker；shared/static fixture 硬门禁 |
| authority 和 identity 再次半提交 | 高 | CourseDatabase 单事务 + 读回 cardinality；异常禁止 done |
| pending_cleanup sibling 永久保护 shared cards | 高 | retaining-owner 状态白名单 + generation snapshot + 串行 delete |
| VACUUM 空间翻倍导致磁盘耗尽 | 高 | 预估临时空间、阈值、skip receipt；逻辑删除与 compact 分离 |
| catalog WAL 多连接阻止 compact | 中 | maintenance lease、关闭/重开共享句柄、checkpoint(TRUNCATE) |
| 清 orphan mapping 丢失用户确认 | 中 | 仅 source refs=0 且 Collection use=0；fingerprint 审核 |
| 老 backups 类型不明 | 中 | `legacy_unknown` 首版只报告/用户确认，不自动全删 |
| 启动恢复拖慢首屏 | 中 | 只把 P0 functional recovery 放启动闸；media/compact 后台；展示进度 |
| 新 state 与旧 enum/DB 行不兼容 | 中 | additive parser/migration，未知 state quarantine，不 fallback active |
| contract 并行波次抢版本/operation ID | 中 | 合入前重读单表，顺延 minor/ID，fixture exact parity |
| 用户把暂停误认为删除 | 低 | 文案/菜单明确 Suspend；hard delete 只在 source uninstall |

### 17.2 明确不做

- 不建设 AnkiWeb、Anki 账号或云同步；
- 不改 Official scheduler 算法、review history 或 revlog 语义；
- 不把 modified APKG 按文件名静默覆盖旧 source；
- 不新增完整单卡编辑器/hard-delete 产品面；
- 不按文件名前缀、导入目录名或 UI 展示名猜媒体所有权；
- 不为释放几 KB 强删 stock notetype/Default deck；
- 不自动删除 `legacy_unknown` backup/quarantine 数据；
- 不把整个 Official profile 目录直接递归删除来代替 source cleanup；
- 不在本计划顺手做 renderer、课程题型、scheduler UX 重构；
- 不把“下次 import 会 VACUUM”当删除回收方案。

---

## 18. 施工清单与收据模板

### 18.1 Checklist

#### S0 复现

- [ ] 三类问题在旧实现上稳定复现
- [ ] audit snapshot/bytes receipt
- [ ] fault points 与失败测试落地

#### S1 导入控制权

- [ ] application-owned saga coordinator
- [ ] durable cancel/discard intent
- [ ] PopScope/退出确认
- [ ] authority 异常不吞
- [ ] identity+authority 单事务
- [ ] pending import 产品入口

#### S2 Recovery

- [ ] startup recovery 生产接线
- [ ] recovery lease
- [ ] recovery matrix 全覆盖
- [ ] checkpoint restore 安全条件
- [ ] ambiguous quarantine

#### S3 Delete

- [ ] structured uninstall result
- [ ] durable ownership snapshot
- [ ] shared owner 状态规则
- [ ] Collection absence verification
- [ ] incomplete index fail-closed
- [ ] D0–D10 fault recovery

#### S4 Metadata

- [ ] source notetype association
- [ ] source deck association
- [ ] source-scoped preview/project
- [ ] mapping ref cleanup
- [ ] safe empty metadata prune

#### S5 Media

- [ ] native media GC contract
- [ ] shared/static/Unicode tests
- [ ] trash interruption recovery
- [ ] reclaimed bytes receipt

#### S6 Checkpoint

- [ ] rollback checkpoint 与正式 backup 分离
- [ ] checkpoint metadata/state
- [ ] success/cancel release
- [ ] legacy backup inventory
- [ ] bounded retention

#### S7 Compact

- [ ] Collection maintenance
- [ ] catalog WAL checkpoint/VACUUM
- [ ] CourseDB maintenance
- [ ] threshold/disk-space guard
- [ ] maintenance jobs 与重试

#### S8 Migration/UX

- [ ] census categories
- [ ] evidence CAS executor
- [ ] one-time backfill/repair
- [ ] repair/storage center
- [ ] Android release 强杀矩阵

### 18.2 Commit receipt

| 包 | commit | 改动摘要 | 定向测试 | 全量结果 | 偏差/未完成 |
|---|---|---|---|---|---|
| S0 | working tree | `OfficialAnkiStorageAudit` + fault points | lifecycle_storage + recovery | **1742 passed / 21 failed**（`--exclude-tags golden`，log `doc41-flutter-test.log`；21 项逐条见下表） | 失败先行与修复同工作树 |
| S1 | working tree | saga 脱离页面；cancel/discard 持久化；PopScope；authority 单事务 fail-closed；pending import store | lifecycle_storage + import tests | 同上全量 | UI 待完成导入区尚未挂课程页 |
| S2 | working tree | `main.dart` 接线 `recoverUnfinished`；checkpoint restore vs quarantine | recovery_test | 同上全量 | SessionEngine 新增 batch/backup RPC；无真机强杀 |
| S3 | working tree | `OfficialAnkiUninstallSaga` 读回验证后再删 owner | cleanup_surfaces + lifecycle A/B | 同上全量 | — |
| S4 | working tree | `anki_source_notetypes/decks` + source-scoped preview | lifecycle source-scope | 同上全量 | native prune 已编入 1.11 `.so`；真机 prune 未跑 |
| S5 | working tree | fake+engine `gcUnusedMedia`；native op 37 | lifecycle media GC | 同上全量 | native GC 已编入 1.11 `.so`；真机 GC 未跑 |
| native `.so` | working tree | `cargo ndk -t arm64-v8a --platform 24` → `jniLibs/arm64-v8a/libturna_anki.so` | `verify_symbols.sh` pass | 未跑 `host-test.sh` / 真机矩阵 | rustc 1.97.1、cargo-ndk 4.1.2、NDK 28.2.13676358、protoc 31.1；SHA-256 `C2808E58…D55530` |
| S6 | working tree | `checkpoints/<attempt>.anki2` + metadata；成功删除后 release | lifecycle checkpoint bound | 同上全量 | 存量 `backups/bk-*` 仅 inventory |
| S7 | working tree | maintenance jobs + compact/VACUUM 阈值 | lifecycle maintenance | 同上全量 | CourseDB VACUUM 仍 skip |
| S8 | working tree | catalog v11；repair executor whitelist；census 仍分类 | census_repair | 同上全量 | 修复中心 UI 未独立成页 |

全量 21 失败（本次 log 实摘，非「上次减一」）：

| # | 测试 | log 证据 | 归类 |
|---|---|---|---|
| 1 | composition single-flights | PathAccessException errno 32 删 `turna-comp-single-*` | Windows 预存 |
| 2–9 | media_resolver ×8 | PathNotFoundException `question?.png` errno 123 | Windows 预存（`?` 非法文件名） |
| 10 | reviewer_behavior showAnswer multi-tag | Expected `/q1.mp3` Actual `\\q1.mp3` | Windows 预存 |
| 11 | reviewer_ui_av DOM/renderComplete | Expected `/b.mp3` Actual `\\b.mp3` | Windows 预存 |
| 12 | status_map STATUS_* | Expected ≥30 Actual 29 | 预存（本轮未增 STATUS） |
| 13 | review_dashboard due/new/overdue | Expected overdue 0 Actual 1 | 预存 |
| 14 | review_dashboard daily activity | Null is not a subtype of String `dailyActivityBetween` | 预存 |
| 15 | review_progress deleted source | Null cast `activityBuckets` | 预存 |
| 16 | review_history_dao 100k buckets | 同上 `activityBuckets` | 预存 |
| 17 | review_history_dao SQL filters | 同上 `activityBuckets` | 预存 |
| 18 | lesson_flow answer all | Expected true Actual false | 预存 |
| 19 | backup_snapshot complete snapshot | PathAccessException errno 32 删 `turna_snapshot*` | Windows 预存 |
| 20 | round2 golden 200% light | golden TestFailure | 预存 host drift |
| 21 | round2 golden 200% dark | golden TestFailure | 预存 host drift |

`p5f_official_first_flow_projects_course_and_publishes` 不在此 21 项中。

### 18.3 数据收据

| 指标 | Before | After | 命令/工具 | Artifact |
|---|---:|---:|---|---|
| active/staging/pending/quarantine sources | catalog active 过早 | import 后 staging + preview_ready | lifecycle_storage_test | host |
| Collection cards/notes | 删除不验证 | exclusive remaining=0 才 retire | uninstall saga + cleanup_surfaces | host |
| source card associations | 随 source 删 | 先 D5 再删 | same | host |
| projection/placement/presentation | 未改语义 | identity+authority 同事务 | official_first_projection_anchor_test | host |
| orphan mappings | 只增不减 | pruneOrphanMappings | metadata dao | host |
| unused media count/bytes | 10MiB exclusive | 0 after GC；shared kept | Fake gcUnusedMedia | host fake |
| rollback checkpoint count/bytes | 每 import 一份 | 5 轮后 ready=0 | lifecycle checkpoint cycle | host |
| collection file/freelist bytes | 未测真机 | 未测 | native compact 未跑 | **unverifiable** |
| catalog file/WAL/freelist bytes | — | compactSqliteFile 实现 | maintenance runner | 无设备收据 |
| course DB file/WAL/freelist bytes | — | compact_course skip | S7 | 未落地 VACUUM |
| maintenance pending/failed | 无表 | jobs merge by kind | lifecycle maintenance | host |

### 18.4 准确状态句

施工前及任一部分波次完成但 §16 未全过时，只能写：

> Official Anki 生命周期与存储回收修复施工中：已完成的波次和 host 证据见 doc 41 收据；导入强杀恢复、删除后媒体/checkpoint/SQLite 字节回收及 Android release 矩阵未全部验收前，生产状态保持 NO-GO，不得宣称“删除已彻底释放空间”或“迁移完成”。

全部门禁通过后，仍需把真实 commit、测试、设备、字节指标、artifact 路径填入本节，并同步 [README](./README.md)、[doc 34](./34-official-anki-production-cutover-and-ohos-retirement-plan.md)、[34 收据](./34-cutover-receipt.md)、`test/BASELINE.md` 和项目指南的准确状态口径。
