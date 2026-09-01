# ADR 0043 — Anki 底座 v2：单一事实源与可重建派生层

- 状态：**失败 / 未交付**（2026-09-01）。2026-08-31 评审曾标「已接受」，但六步计划未完成切生产：Step 4 真机门禁未过、`v2ImportChain` 生产仍为 false、Step 5/6 取消。结论与档案见 [ankiUpdate README](../ankiUpdate/README.md)。下文是失败当时的设计原文，不是现行架构。
- 日期：2026-08-31
- 关联：[重建计划 README](../ankiUpdate/README.md)（总目标与六步）；[step1.md](../ankiUpdate/step1.md)（真机实测收据与教训，已完成）；[doc 41](../official-anki-migration/41-official-anki-lifecycle-and-storage-remediation-plan.md)（中断场景与不变量来源）；[doc 42](../official-anki-migration/42-staging-first-official-import-lifecycle-plan.md)（staging-first，v2 继承）；[ADR 0036](./0036-official-anki-core-migration.md)、[ADR 0037](./0037-anki-course-review-unification.md)、[ADR 0042](./0042-staging-first-official-import.md)
- 当前源码基线：Official catalog schema 12、`CourseDatabase.kSchemaVersion = 22`、contract 1.11（ops 1–40，38 个在用）；四个 SQLite 存储 = `collection.anki2` + `collection.media.db2` + `official_catalog.sqlite`（18 张表）+ `course.db`（约 20 张 anki 表）

## 背景

1. **同一事实存了 2~4 份。** 课程树三份（catalog 投影状态 / course.db 投影索引 / Collection 本体）、字段映射与呈现决策两份、来源登记两份、卡片内容三份。为防止副本打架，系统长出整套「免疫系统」——对账 journal、启动普查 census、修复中心、写栅栏——占 anki 代码量大半，也是怪 bug 的温床（README §二的诊断）。
2. **补丁路线已被证伪。** doc 41 的 checkpoint restore + ambiguous commit 三态方案，其核心操作（独占 lease 下整文件替换 collection.anki2）与 UI 线程模型冲突，被 doc 42 的 staging-first 取代；doc 42 修好了导入轴，但删除/回收/对账轴的复杂度没有降——因为副本还在。
3. **Step 1（2026-08-31 真机）给的设计教训。** 生产导入链曾整体跑不通（staging 引擎未打开）、启动维护被整体跳过（engine-null 短路）——两处都是「接线缺陷 + 测试缝隙说谎」；同场暴露六项新发现（提交后 ANR、课程切换不生效、pending_cleanup 永不完成、厂商 logcat 静默、强杀后 prefs 丢失、due sync 挂载点与假设不符）。教训：**跨库一致性靠「证明」维持不住，要靠「不重复」消掉**；测试必须贴真实挂载点。

## 决策

### 架构（D1–D9）

- **D1 唯一事实源。** `collection.anki2` + `collection.media` 是卡片、笔记、模板、牌组结构、调度、revlog 的唯一事实源（继承 ADR 0036）。任何其他存储不得持有这些事实的长期副本。
- **D2 决策进配置区。** 字段映射、牌组→课程的呈现与放置决策，写入 Anki Collection 自带的配置区（Turna 命名空间），随 Anki 原生备份/导出走。需要桥新增读写 op（编号 41 起，Step 3 施工；schema 细节以 rslib config API spike 为准）。Step 3 候选 op 清单：`GET_CONFIG` / `SET_CONFIG`（**必须**，K10 的单事务语义由 op 内部保证）；只读 usn-diff 扩展（**可选**，仅当 op 40 `DIFF_COLLECTION_CHECKPOINT` 表达力不足 K2 的 receipt 重建时）。
- **D3 派生层可重建。** 课程树是一份**物化视图**：输入 = Collection + 配置区决策 + 目录账本，输出 = 视图存储（course.db 侧两张表合并为一张）。视图无独立状态，可随时 DROP+REBUILD，重建幂等、在后台 isolate 执行。
- **D4 目录账本 18→5。** catalog 保留 `anki_sources`、`anki_import_attempts`（吸收 receipt：pre-import usn、scope、note ids）、`anki_maintenance_jobs`、`anki_maintenance_leases`，以及 Q6 定案保留的 `anki_source_cards`（source→卡所有权索引，D6 删除原语的输入；deck 派生若在 Step 4 spike 证明可靠可随 Step 6 退役）。其余的去处见附录 A。
- **D5 course.db anki 表 20→约 5。** 保留：视图存储（1 张）、产品侧非 anki 事实（课程引入状态、复习统计挂钩、错题本关联）；卡片内容/索引副本（`anki_notes`/`anki_cards_meta`/`anki_notetypes` 等 Legacy 内容表）随 Step 6 退役。
- **D6 删除 = retiring 序列 + 引擎幂等删除 + 字节回收分层。** 卸载 source：①账本单事务把 source 标 `retiring`（用户视角即刻「已移除」，课程树/复习立即不可见）并入队删除 job；②worker 幂等执行引擎删除（`DELETE` 系 op 对缺卡幂等，rslib 语义已具备；目标卡清单来自 `anki_source_cards` 所有权索引，Q6 已定案保留）；③完成后账本行终删 + 视图重建（D3）；④媒体 GC / prune / VACUUM 走 maintenance job（沿用 doc 41 S5/S7，幂等可重试）。doc 41 S3 的「verify 先于 owner 终删」不变量保留——只是从「11 表级联 + 双登记同步写」变成「job 驱动的单线序列」；job 未跑完则 source 停在 `retiring` 并在修复中心可见，不产生无主且不可见的卡。
- **D7 长操作全部后台化 + 可取消。** 投影重建、媒体 GC、VACUUM、存量迁移一律 worker isolate，主线程只发 intent、收通知；取消通道复用现有 worker cancel。这是 Step 1 新发现 #1（提交后 ANR）的结构性答复。
- **D8 可观测不依赖厂商 logcat。** 关键路径（启动恢复、commit 窗口、维护任务、视图重建）写滚动文件日志，修复中心「导出诊断」可带出（Step 1 新发现 #4 的答复）；storage audit 快照保留。
- **D9 测试贴真实挂载点。** 入口测试以生产真实触发点为准（due sync 在复习页/练习中心/资料页，不在首页）；严格假引擎（顺序断言、状态机模拟）常驻测试基建；真机强杀矩阵是 Step 4 的发布门禁，fake/widget 测试不得替代（继承 doc 41 §16.7）。

### 中断场景矩阵（K1–K14，逐条作答）

归并自 doc 41 §7.2/§7.4/§16.6、doc 42 §5.5/§10.2、Step 1 新发现。**每行必须有一个不依赖猜测的答案**——这是本 ADR 评审的硬门槛。

| # | 场景（出处） | v2 答案 |
|---|---|---|
| K1 | staging 导入中强杀（42 §10.2） | staging 目录即证据（一次性资产）：重启 census 发现 → 「待完成导入」入口，继续（完整性校验过则直接进 preview，否则重建 staging）或删除。live 零写入不变式不变（继承 ADR 0042） |
| K2 | commit 窗口、receipt 落库前强杀（41 §16.6；42 §5.5） | attempt 已记 pre-import usn/generation；重启用只读 diff（usn > pre，复用 op 40 或 Step 3 新只读 op）重建 receipt → 按 user intent 续跑或 DELETE_CARDS 回滚；不可重建 → quarantine。绝不猜测（继承 42 §5.5，v2 不改——此设计已对） |
| K3 | receipt 后、投影中强杀（41 §16.6 projection transaction 中） | **v2 最大简化**：投影是无状态物化视图，重启直接整建（幂等），不存在 cursor / resumeIndexing / 状态机。重建后台执行，不阻塞启动与复习 |
| K4 | publish / authority 提交中强杀（41 §16.6） | authority commit 幂等：单事务 + 读回验证，重启重放。v2 里 authority 收敛为「视图标记 active」的单一写点 |
| K5 | 取消时 native op busy（41 §16.6） | 等 native 有界返回（RPC 上限）→ receipt 完整走 DELETE_CARDS 回滚；超时无 receipt → 按 K2 处理 |
| K6 | 卸载中任意时刻强杀（41 §16.6 uninstall collection delete 后） | retiring 序列（D6）逐段幂等：账本标 `retiring` 是单事务（杀于此 → 重启 job 表驱动续跑）；引擎删除幂等（杀于此 → 重跑，缺卡无害）；终删+视图重建幂等；GC/VACUUM 幂等。任何一段卡住 → source 停 `retiring`、修复中心可见，**不产生无主且不可见的卡**。Step 1 新发现 #3（pending_cleanup 永不完成）的根因——跨库多步状态机——被单线 job 序列取代 |
| K7 | media GC trash 中强杀（41 §16.6） | GC 幂等重跑（rslib trash 语义）；引用集来自当前 Collection，不误删 active |
| K8 | checkpoint release 中强杀（41 §16.6） | checkpoint 体系已废（ADR 0042）；存量 `backups/bk-*` 善后完成即场景消失，善后期间 sweep 收敛 |
| K9 | compact / VACUUM 中强杀（41 §16.6） | SQLite 事务性保证库可 reopen/check；job 状态 pending/failed 可重试（doc 41 S7 已实现） |
| K10 | 配置区写入中强杀（v2 新增场景） | 配置区写 = Collection 内单事务（op 内部），杀进程即回滚，无半写状态；映射晋升 = 配置区写 + attempt 状态推进，两步各自幂等 |
| K11 | 视图重建中强杀（v2 新增场景） | 视图无状态，重跑即收敛；重建期间课程树显示「重建中」占位，内置 Turkish 课程不受影响（恢复失败不阻塞启动，继承 doc 41 §7.1） |
| K12 | 存量迁移事务中强杀（Step 5 预告） | 迁移 = 一次短事务（搬三样：映射→配置区、账本行收敛、视图重建标志），杀进程回滚，重跑幂等；Anki 库原样保留，最坏情况重跑迁移 |
| K13 | 主线程长任务 ANR（Step 1 新发现 #1） | D7：投影/GC/VACUUM/迁移全部 worker isolate；主线程零 native 忙等。Step 1 的 ANR dump 证明现状违反此条，v2 以结构而非补丁答复 |
| K14 | 强杀后 prefs 丢失（Step 1 新发现 #5） | onboarding/scope 等关键偏好改「提交即持久化」（写穿时机修正），不依赖进程正常退出；随 Step 4 落码并进强杀矩阵 |

**归并说明**：doc 41 §7.2 的前五行（`preparing` / `backing_up` / `importing not_started` / `importing unknown`±checkpoint）与「catalog active + authority 非 active（旧版）」是 v1「先写 live 后预览」状态机的产物——ADR 0042 之后新导入不再产生这些状态；**存量实例**按 doc 42 §7 善后（可证明 restore → 可 diff 关联 → quarantine，绝不静默删），善后完成即场景消失（与 K8 的存量 checkpoint 同批）。此善后在 Step 5 迁移 census 中收口，v2 不为其保留任何常驻代码路径。

### 与 Step 1 其余新发现的对应

- **课程切换不生效（#2）**：v2 中课程 scope = 配置区决策 + 视图切换（D2/D3），切换只改一个决策键；若 Step 4 前需热修，独立小修不进本 ADR。
- **日志静默（#4）**：D8 文件日志通道。
- **测试缝隙（#6）**：D9。

## 后果

**交付结果（2026-09-01）：未发生。** 下列「正 / 成本 / 风险」是 2026-08-31 评审时的预期，不是已落地的生产后果。v2 未切生产；正项（副本退役、代码量下降、删除真回收）均未兑现。

- **正（未兑现）**：跨库对账代码（reconciliation journal、census 执行器、修复中心大部分、写栅栏）随副本一起退役，代码量 33k→约 15k 的主要来源；删除真回收（K6）；决策随 Anki 备份走（D2）；「删了还在」「越删越大」类问题的结构来源被移除。
- **成本**：依赖 Step 3 桥能力（配置区读写 op 41+、可能的一个只读 diff op）；配置区需要 Turna 命名空间纪律与版本字段；Step 4 期间 v1/v2 并存（flag 开关）的双版维护；视图重建性能需大库实测门禁。
- **风险与缓解**：rslib config API 无 semver（钉 commit + 独立 PR 升级，继承 ADR 0036 纪律）；视图重建慢 → 重建增量门禁 + 后台不阻塞（D7）；配置区损坏 → 决策可从最后一次投影反推重建（决策丢失 ≠ 数据丢失，映射可用识别器重建议）。
- **明确不做**：Turna 产品数据（成就、统计、错题）不进配置区；不重建 profile；不引入读时实时构建课程树（性能不可控）。

## 被否决的路线

1. **继续 v1 打补丁**（doc 41 原波次 + 修删除轴）——复杂度集中在跨库一致性证明，Step 1 与 doc 42 已双重证伪。
2. **全部塞进 Anki 库**——产品数据进配置区属滥用，备份体积与上游兼容风险不可控。
3. **读时实时构建课程树**（无物化）——首页/课程树性能不可控，低端机风险。
4. **另起 profile 重建**——违背「存量用户 Anki 库原样保留」（Step 5 前提）。

## 开放问题（已全部关闭，2026-08-31 评审）

- Q1：配置区 namespace 与 schema 细节——**已关闭**。spike 结论（详见 [step3.md](../ankiUpdate/step3.md) §任务 A）：rslib config 表存任意字符串 key + JSON BLOB；写走公开的 `Collection::set_config_json`（事务性，K10 语义由它成立）、删走 `remove_config`；读因 `get_config_optional` 为 `pub(crate)`，桥内以既有 `col.storage.db()` 只读 SQL 先例直读 config 表；SET 强制 `turna.` 前缀（写保护 Anki 自身配置），读不限。
- Q2：`anki_scheduler_mutations` 表去留——**已定案：删**。调度事实的唯一记录是 Collection 的 revlog/ops（D1）；audit 职责由 D8 文件日志承担，账本里留调度审计表正是 v2 要消灭的副本。删表发生在 Step 5/6 账本收敛，Step 3/4 不受影响。
- Q3：视图重建的量化门禁——**转 Step 4 前置项**（10 万卡库冷重建 P95 上限，数值 Step 4 定标，进 Step 4 施工文档）。
- Q4：Step 4 并存 flag 的命名与灰度边界——**转 Step 4 前置项**（默认值、回退条件，进 Step 4 施工文档）。
- Q5：K14 的偏好清单边界——**转 Step 4 前置项**（哪些必须写穿、哪些可容忍丢失，进 Step 4 施工文档）。
- Q6：source→卡所有权的存放——**已定案：账本保留 `anki_source_cards` 为第 5 张表**。理由：①现有删除原语（op 31 `DELETE_NOTES` / op 32 `DELETE_CARDS`）是 id 清单制，所有权索引正是其输入，deck 派生需 rslib 能力核验而 spike 未做，把它压在删除主路径上违背 K6「不依赖猜测」的门槛；②`source→卡所有权` 是 Turna 的导入事实（哪个包带进哪些卡），不是 D1 禁止的卡片/笔记/调度事实副本，属账本本职（`anki_sources` 从表）；③README「约 4 张」已含第 5 张弹性。若 Step 4 spike 证明 deck 派生可靠，可在 Step 6 把它随 Legacy 一起退役（索引可重建，语义与视图一致）。

## 附录 A：表收敛清单（catalog 18→5）

| 表 | 去处 |
|---|---|
| `anki_sources` / `anki_import_attempts` / `anki_maintenance_jobs` / `anki_maintenance_leases` | **保留**（D4；attempt 吸收 receipt） |
| `anki_import_attempt_notes` | 并入 attempt 行（receipt 字段） |
| `anki_projection_mappings`、`anki_course_placement_overrides` | → 配置区（D2） |
| `anki_projection_jobs`、`anki_source_projection_state`、`anki_source_reconciliation_journal` | 删（视图重建取代；对账退役） |
| `anki_source_notetypes`、`anki_source_decks` | 删（Collection 派生，视图时算） |
| `anki_source_cards` | **保留为第 5 张**（Q6 已定案：删除原语 id 清单制的输入；deck 派生证明可靠后可随 Step 6 退役） |
| `anki_checkpoint_files`、`anki_cleanup_receipts` | 删（checkpoint 已废；cleanup receipt 并进 maintenance jobs） |
| `legacy_anki_migrations`、`legacy_anki_card_map` | Step 6 删（Legacy 已退役） |
| `anki_scheduler_mutations` | 删（Q2 已定案：调度事实唯一记录在 Collection revlog，audit 由 D8 文件日志承担） |

course.db 侧 20→约 5 的明细随 Step 4 施工文档落表（原则见 D5；Legacy 内容表归 Step 6）。
