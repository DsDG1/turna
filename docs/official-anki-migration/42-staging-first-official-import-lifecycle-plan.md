# 42 — Staging-first Official 导入生命周期重设计计划

> 文档代号：ANKI-IMPORT-STAGING-FIRST-REDESIGN
>
> 日期：2026-08-31
>
> 状态：**P2 已施工**（2026-08-31）。P0 S-a/S-b/S-d 绿；S-c 仍红（P3）。catalog v12。本计划取代 [doc 41](./41-official-anki-lifecycle-and-storage-remediation-plan.md) 的「导入链路修复」部分（S1 控制权、S2 启动恢复的导入分支、S6 checkpoint 体系对新导入全部作废），保留 doc 41 的「删除与物理回收」部分（S3/S4/S5/S7/S8）作为独立存量善后。完成状态以本文 §10 门禁与 §12 收据为准。
>
> 前置阅读：[34](./34-official-anki-production-cutover-and-ohos-retirement-plan.md)、[41](./41-official-anki-lifecycle-and-storage-remediation-plan.md)、[37](./37-generic-card-recognizer-plan.md)、[ADR 0036](../decisions/0036-official-anki-core-migration.md)、[ADR 0037](../decisions/0037-anki-course-review-unification.md)、[ADR 0042](../decisions/0042-staging-first-official-import.md)。
>
> 铁律（继承 doc 41）：**先写可稳定复现的失败测试，再改行为**；每个施工包独立 commit、独立可回滚；不把「UI 消失」「逻辑行已删」「物理字节已回收」混为同一状态；不明确的数据进 quarantine，绝不静默删。

---

## 0. 一句话与最终目标

当前导入把 APKG **先写进 live Collection，再问用户要不要**。取消、返回、强杀因此都等价于「回滚一个已提交的跨库事务」，被迫引入 checkpoint restore、ambiguous commit 三态、无主卡普查这一整层复杂度（doc 41 §1.1/§4.4/§7.3），而 2026-08-31 实测它仍然以四个用户可见症状失败（§1）。

本计划反转设计轴：

> **导入先落 staging collection（一次性 profile 目录），预览与映射确认全部在 staging 上做；用户确认后才写 live Collection。取消 = 删 staging 目录。**

live Collection 只在 commit 窗口被触碰，窗口内只有**一个** native 写操作（`IMPORT_PACKAGE`），其后 receipt 完整落库才进入投影/发布。因此：

1. 预览阶段取消/退出/强杀：**live Collection 零写入**，staging 目录删除即可，无 checkpoint、无 restore、无无主卡；
2. commit 窗口强杀：receipt 要么完整（续跑投影/发布），要么可用 pre-import usn 重建（§5.5），只有两者皆失才 quarantine；
3. 「待完成导入」永远可发现（staging 目录本身就是实体存在，bytes 进存储诊断）；
4. mapping 只在 commit 时晋升到全局 `anki_projection_mappings`，预览阶段的确认不再污染全局。

## 1. 触发证据：四个症状与代码根因

按 2026-08-31 工作树核实；行号漂移以符号为准。

| # | 用户症状 | 根因（代码锚点） | 为什么补丁修不掉 |
|---|---|---|---|
| S-a | 解析/导入时点「取消」，数据仍落盘 | `AnkiImportController.cancel()` 只在 preview 存在时触发 discard；Parsing 阶段 `_officialPreview==null` 直接返回（`anki_import_controller.dart::cancel`） | 取消时 native import 可能已提交 live Collection，但此刻连「有没有提交」都没有 durable 记录——补丁只能再加一个猜测分支 |
| S-b | 「放弃并清理」卡住/闪退且最终没清理 | 对话框选 discard 后立即 pop 不等待（`anki_import_screen.dart::_confirmLeave` busy 分支）；rollback 的 `restoreBackup/deleteCards` 排在 worker FIFO 之后（`official_anki_worker.dart::_enqueue`）必须等当前导入整段完成；`_discardDurable` 全程 `unawaited` 无 catch，主 isolate 直写 catalog 与 worker 句柄争锁（busy_timeout 5s 后静默丢弃） | 「等导入完再整文件替换 collection.anki2」这个时序本身就是 doc 41 §7.3 承认只能在独占 lease 下安全执行的操作，UI 线程模型给不了这个 lease |
| S-c | 死循环卡「还有一类卡片需要看一眼样卡」 | preview 已按 source 作用域取 schema（`official_anki_official_first_service.dart::preparePreview` 传 `notetypeIds`），但 `projectSource()` 仍读全 Collection（`official_anki_projection_service.dart` 调用 `getProjectionSchemas` 不传 scope）；`_mergeAndPersistMappings` 对任何 `user_confirmed!=1` 的 notetype 返回 needsMapping。罪魁 notetype 不在 preview.schemas 里，**界面上永远渲染不出那一行**，无法确认 | preview/publish 读的不是同一份集合，补 UI 无意义；必须让 publish 收 source 作用域参数 |
| S-d | 「这样没问题」点不动/点了没效果 | `OfficialAnkiMappingPage` 保存按钮在 blocking 时硬禁用，而用户正因为 blocking 被引导进来，必须先在两个 Dropdown 里手工各选一次（`official_anki_mapping_page.dart` 底部 FilledButton `onPressed: blocking ? null : ...`）；确认回调只改 controller 状态，**不 pop、无反馈**（`anki_import_screen.dart::_openOfficialMapping`） | 该页原本是 diagnostics 页（`DiagnosticsReleaseGuard.guardedRouteNames` 含 `OfficialAnkiMappingRoute`，但 routing 未挂 guard），被直接塞进 release 主流程，交互语义错位 |

附带事实：`OfficialAnkiRepairExecutor`、`OfficialAnkiPendingImportStore`（doc 41 已写的修复执行器与待完成导入查询）在 lib 内**零生产引用**，只有测试引用；`main.dart` 启动仍是 4 个互不相识的 `unawaited` 任务并发触碰同一批文件，无 lease。测试侧：`test/views/anki/` 下没有「解析中取消」「mapping 保存可点性」「needsMapping 循环」任何用例——四个症状全部合法穿过 `flutter test`。

## 2. 被否决的路线

1. **按 doc 41 原波次继续**：S1/S2/S6 的本质是给「先写 live 再回滚」打补丁。即使全部按规格做完，复杂度集中在 commit-ambiguity 证明（§7.3 六条 restore 安全条件），而该产品路径没有新信息能消除 ambiguity——它来自设计轴本身。
2. **砍投影只留复习器**：symptom S-c 整类消失，但放弃 ADR 0037 的统一复习愿景。本计划不采用；若未来再评估，staging-first 与其不冲突。
3. **staging 与 live 双轨长期并存**：README 维护规则禁止保留被否决的并行实现作为默认路径；本计划直接切换，旧「先写 live 后预览」路径同波删除，存量善后走 §7。

## 3. 不变量

1. **live Collection 写窗口唯一**：一次导入只有一次 `IMPORT_PACKAGE` 作用于 live Collection，发生在用户确认之后；此前 live Collection 的 generation/usn 不得变化。
2. **staging 目录是一次性资产**：`official_anki/staging/<attemptId>/` 下一切（collection、media、catalog 副本）随时可整体删除；删除即完成 rollback，无残留语义。
3. **attempt ledger 是唯一持久化控制面**：wizard 页面 dispose 不得丢失任何进行中操作；所有状态推进写 ledger，UI 只读。
4. **mapping 两段生命周期**：staging 期确认存 attempt 本地；commit 成功才晋升 `anki_projection_mappings`（user_confirmed=1）；晋升时 fingerprint 不一致则强制 review（沿用 doc 41 §9.3-5）。
5. **preview 与 publish 同一份 frozen source scope**：scope = (notetypeIds, deckIds) 来自 live import receipt 的 source 关联；`_mergeAndPersistMappings` 只评估 scope 内 notetype；scope 外 notetype 永远不得触发 needsMapping。
6. **commit 失败不失忆**：live import 返回后 receipt（note ids / card descriptors / generation）必须在同一 catalog 事务落库，再开始投影；投影、identity、authority 的提交沿用 doc 41 §4.5 单事务（保留，不变）。
7. **恢复只凭证据**：pre-import usn/generation 不可读 → quarantine，绝不猜测删除（doc 41 §3.4 保留）。
8. **可观测**：staging 目录 bytes、commit 窗口时长、receipt 重建次数进 storage audit / diagnostics（复用 doc 41 S0 的 `OfficialAnkiStorageAudit`，保留）。

## 4. 状态机与提交边界

### 4.1 Attempt 生命周期（新）

```text
created                # 选好文件，ledger 落行，staging 目录已建
→ staging_importing    # staging worker IMPORT_PACKAGE（withScheduling=false）
→ preview_ready        # schema/sample 就绪，等用户
→ committing           # live IMPORT_PACKAGE（唯一 live 写窗口）
→ receipt_committed    # note ids + card descriptors + generation 同事务落库
→ projecting           # source-scoped projection
→ publishing           # identity+authority 单事务（doc 41 §4.5）
→ completed            # staging 目录已删，mapping 已晋升
```

旁路：

```text
created/staging_importing/preview_ready
  → cancel_requested → cancelled        # 杀 staging isolate + 删目录；live 零触碰
committing 中 cancel_requested          # 等 native 返回（有界），receipt 完整则 DELETE_CARDS 回滚
任一非终态进程强杀                       # 下次启动按 §5.5 矩阵恢复
证据不足                                 # quarantined（可见、可诊断、仅显式修复）
```

source 状态沿用 doc 41 §4.1（staging/active/rollback_pending→新流程不再产生/pending_cleanup/retired/quarantined），其中 `rollback_pending` 与 checkpoint 状态机只服务存量数据善后。

### 4.2 user intent（保留 doc 41 §4.3）

`user_intent ∈ {continue, discard, undecided}`，页面返回先落 intent 再执行。差异：staging 期的 discard 是 O(删目录)，不等 live worker。

### 4.3 提交边界

| 步骤 | 存储 | 事务 |
|---|---|---|
| staging import | staging collection | native 单 op，失败删目录重跑 |
| live import + receipt | live Collection + catalog | receipt 在同一 catalog 事务（doc 41 §4.4 committed 五要素） |
| projection | catalog + CourseDB | 沿用现有 full atomic rebuild |
| publish | CourseDB | identity+authority 单事务，authority 失败向上传播（doc 41 §4.5/§6.4 保留） |
| mapping 晋升 | catalog | 与 publish 读回验证同一批 |

## 5. 详细序列

### 5.1 Staging import

```text
AnkiImportController（瘦身后的 UI adapter）
  → OfficialAnkiImportSaga.start(path)
    → ledger: attempt(created, staging_path, user_intent=undecided)
    → staging worker spawn（第二 isolate，专属 staging paths）
    → IMPORT_PACKAGE(apkg, withScheduling=false)   # 只建内容，不建复习进度
    → ledger → preview_ready
  → preview = staging engine: getProjectionSchemas(全 staging)+ samples
```

- staging worker 与 live worker 是两个 isolate；staging 期间 live Collection 保持打开，复习不被打断（修复当前 `createBackup` close/reopen live collection 造成的全局停顿）。
- preview 卡片计数来自 staging；与 live 已有 source 重叠（同 GUID）时的去重差值在 commit 后按 live receipt 回报（「本次新增 X，已存在跳过 Y」）。

### 5.2 映射确认（交互重设计，修 S-c/S-d）

- preview 列表行点击进入样卡确认页（复用 `OfficialAnkiMappingPage` 外壳，交互换成）：样卡左右/上下两栏直接展示，「哪边是正面」为**二选一必选**；选完即非 blocking，保存按钮恒可点；保存 = 确认并 pop 回 preview，行变「已确认」。
- 「跳过这类卡片」与「确认」一样清 needsMapping 横幅（修复 `skipOfficialNotetype` 不清 `needsMapping` 的现存 bug）。
- 确认结果写 attempt 本地（staging-scope），**不写**全局 mapping 表。

### 5.3 Commit

```text
saga.commit(attemptId)
  → ledger → committing；记录 live pre-import usn/generation
  → live worker IMPORT_PACKAGE(apkg, withScheduling=true)
  → receipt 同事务落库（note ids / card descriptors / source notetype+deck 关联 / generation）
  → source-scoped projectSource(notetypeIds=receipt.scope)   # 签名变更，见 §9
  → identity+authority 单事务 + 读回验证
  → mapping 晋升（staging 确认 → 全局 user_confirmed=1）
  → 删 staging 目录；ledger → completed
```

- 与既有 source 重叠的卡由 rslib import 自身去重语义处理，shared-owner 规则（doc 41 §8.4）不变。
- authority 失败：不进入 done，attempt 停留 `receipt_committed/projecting`，重启后续跑（现有 attempt 恢复机制保留）。

### 5.4 Cancel / discard

| 时机 | 行为 |
|---|---|
| created/staging_importing/preview_ready | ledger 落 discard → staging session cancel → **杀 staging isolate**（其 SQLite 是一次性资产，WAL 回滚即可）→ 删目录 → cancelled。有界、秒级、不碰 live |
| committing | 落 discard intent；等 native op 有界返回：receipt 完整 → `DELETE_CARDS` 回滚（沿用现有幂等语义）；native 崩溃无 receipt → §5.5 |
| receipt_committed 及以后 | 同 doc 41 现有 pending_cleanup/uninstall 语义（投影未发布则先清投影） |

### 5.5 强杀恢复矩阵（取代 doc 41 §7.2 的导入分支）

| ledger 证据 | 启动动作 |
|---|---|
| created / staging_importing / preview_ready（无 discard） | 显示「待完成导入」入口：继续（staging 完整校验通过则直接进 preview，否则重建 staging）/ 放弃并清理 |
| 同上 + discard intent | 删 staging 目录 → cancelled |
| committing，receipt 未落库 | 读 pre-import usn/generation：可重建 receipt（search usn > pre，候选复用现有 `DIFF_COLLECTION_CHECKPOINT` 或新只读 op，§9.2）→ 按 intent 续跑或 DELETE_CARDS 回滚；**不可重建 → quarantined** |
| receipt_committed / projecting / publishing | 沿用现有 attempt 恢复（resumeIndexing / 幂等 publish） |
| 无 ledger 的 staging 目录残留 | census 发现 → bytes 进诊断 → 用户确认删除 |

不再有 checkpoint restore、不再有 `native_commit=unknown` 的 restore 分支；quarantine 是唯一兜底。

### 5.6 多 profile / 多 profile 切换

staging paths 带 attemptId 段，与 profile 切换隔离；profile 切换时进行中 staging attempt 一律按 discard 处理（目录删除），ledger 保留证据。

## 6. 与 doc 41 的范围交接

| doc 41 章节 | 处置 |
|---|---|
| S0 audit / 失败测试先行 | **保留**：`OfficialAnkiStorageAudit` 继续用；§8 的四条新门禁测试替代其导入侧用例 |
| S1 控制权 / §4.3 intent / §4.5 单事务 / §6.4 authority fail-closed | **保留语义**，在 staging 轴上重写实现；controller 退化为 UI adapter |
| S2 启动恢复 | **导入分支作废**，由 §5.5 替代；lease（§7.5）保留，commit/删除/维护仍须同一 coordinator |
| S3 verified hard uninstall | **保留不变**（删除链路与导入正交；`OfficialAnkiUninstallSaga` 已实现，接线进生产） |
| S4 source-scoped metadata/mapping | **保留并吸收**：§9.2 由本文不变量 5 收口；empty prune 不变 |
| S5 media GC | **保留不变**（staging 目录整体删除天然回收其媒体，live 侧媒体 GC 仍需要） |
| S6 checkpoint 体系 | **对新导入作废**：live import 前不再 `create_backup` 整份复制 collection；存量 `backups/bk-*.anki2` 的 inventory/retention（§11.4）保留作善后 |
| S7 compact | **保留不变** |
| S8 存量 census/repair center | **保留**：存量 staging/unfinished/无主数据按 doc 41 §7.4 一次性 census 修复；`OfficialAnkiRepairExecutor` 必须在本计划 P3 接进 `main.dart`，whitelist 删除 `restoreCheckpoint`（仅存量例外路径可调用） |

## 7. 存量数据

1. 现有 live Collection 中的 active source 不受影响。
2. 现有 unfinished/staging attempt（旧流程产生）按 doc 41 §7.4 优先级善后：可证明的 restore（旧 checkpoint 仍在）→ 可 diff 的关联 → quarantine。这是最后一次使用 restore 路径。
3. 迁移完成后，旧「先写 live 后预览」代码路径删除（`importThenPreview` 的 live 直连分支、`createBackup` 的 import 前置调用、rollbackAttempt 的 restore 分支改为仅存量 census 调用）。

## 8. 施工波次

```text
P0 失败测试先行（本计划唯一前置硬门禁）
  → P1 staging 基座：staging paths/第二 isolate/ledger 列/Saga.start+cancel
  → P2 wizard 与映射交互重写（§5.2）+ preview 走 staging
  → P3 commit saga + source-scoped publish + 启动接线（repair executor/pending imports/lease）
  → P4 旧路径删除 + 存量 census 收口 + 文档收据
```

- P0 不写进生产代码；P1 起每波独立 commit。
- 灰度策略：**直接切换**，不保留旧路径 flag——README 维护规则禁止双轨默认路径；风险由 P0/P4 门禁兜住。

## 9. 落点

### 9.1 Dart（无 contract 变更即可完成的范围）

- `application/anki_import/anki_import_controller.dart`：退化为 UI adapter（订阅 ledger、发 intent），删除 `_discardDurable`/preview 私有清理。
- 新 `application/anki_official/import/official_anki_staging_manager.dart`：staging paths、目录生命周期、staging isolate spawn/kill、完整性校验。
- `official_anki_import_orchestrator.dart`：拆 `startStaging / commitLive / discard`；live import 前不再 createBackup。
- `official_anki_official_first_service.dart`：preview 绑定 staging engine；commit 走新 saga。
- `official_anki_projection_service.dart`：`projectSource` 增加必传 `notetypeIds` scope 参数；`_mergeAndPersistMappings` 只评估 scope；修 `skipOfficialNotetype` 清 needsMapping。调用点：official-first service、legacy migration coordinator、source management 诊断页。
- `official_anki_composition.dart`：staging session 槽位（与 live session 并存）。
- `views/anki_official/official_anki_mapping_page.dart`：§5.2 交互重写；routing 决策——它成为正式导入页，移出 `DiagnosticsReleaseGuard.guardedRouteNames`（guard 集合与 routing 注释同步修正）。
- `views/anki/anki_import_screen.dart`：busy 状态统一取消语义；discard 有等待态与 receipt。
- `main.dart`：启动顺序按 doc 41 §7.1（lease → census → repair executor → CourseProvider），4 个并发 `unawaited` 收敛为一个恢复入口；`OfficialAnkiPendingImportStore` 接进课程管理/导入首页 UI。
- `storage_inventory_service.dart`：staging 目录分项（bytes、attempt 关联）。
- catalog schema v11 → v12（additive）：`anki_import_attempts` 增 `phase TEXT`、`staging_path TEXT`；不新增平行状态表。

### 9.2 Rust / contract（候选，均需 contract 评审后才动）

- receipt 重建：优先复用现有 search/diff 只读能力（usn > pre-import）；若表达能力不足，新增一个只读 op（编号从 contract 单表下一个未占用值分配，不预占）。
- `IMPORT_PACKAGE` 的 `withScheduling=false` 语义核验（staging 不需要 revlog/调度）：若现有参数不满足，记为 contract 变更项。
- 不改：ops.rs delete 语义、media GC、compact（doc 41 S3/S5/S7 照旧）。

## 10. 门禁

### 10.1 P0 失败测试（先红后绿，缺一波次不得开工）

| 测试 | 断言（对应症状） |
|---|---|
| wizard：staging_importing 中点取消 | live Collection generation 不变；catalog 无该 source 任何行；staging 目录已删（S-a） |
| wizard：preview 选「放弃并清理」 | 有界时间内完成；staging 目录删除 receipt；live 零写入；无 `unawaited` 静默异常（S-b） |
| projection：live Collection 存在外来未确认 notetype | source-scoped `projectSource` 不返回 needsMapping，投影成功（S-c） |
| mapping 页 widget | 未选正面前 save 可点（点击进入选择态）；选择后保存并 pop；preview 行「已确认」（S-d） |

其中至少两条跑真实文件型 SQLite（非全 fake engine）。

### 10.2 强杀矩阵（Android，继承 doc 41 §16.6 中仍成立的行）

| 强杀点 | 重启期望 |
|---|---|
| staging_importing 任意时刻 | staging 目录清理或「待完成导入」可见；live generation 不变 |
| committing receipt 前 | receipt 重建续跑或 quarantine；**不产生无主卡且不静默** |
| receipt_committed/projecting/publishing | 幂等续跑至 completed |
| discard 落库后任意时刻 | cancelled，staging 目录终态删除 |

### 10.3 量化门禁

| 指标 | GO 条件 |
|---|---|
| 预览期取消/强杀 | live Collection generation/usn 变化 = 0（全用例） |
| 弃导入残留 | staging bytes 在诊断可见且可一键清理；catalog 无不可见 source |
| needsMapping 循环 | scope 外 notetype 触发 needsMapping 次数 = 0 |
| commit 用时 | 同 fixture 相对旧链路增幅记录进收据（预期 ≈ 2× native import；超 3× 需复盘） |
| false success | authority 注入失败时 completed UI = 0（doc 41 §16.4 保留） |

### 10.4 NO-GO 条件

- 任何路径在 preview 前写 live Collection；
- discard 路径依赖等待 live worker FIFO；
- staging 目录无 owner（无 ledger 行且无诊断可见性）；
- mapping 确认在 commit 前写全局表。

## 11. 诚实的代价与风险

1. **大牌组导两次**：native import 执行两次（staging + live），时间与临时磁盘各加一份（staging ≈ apkg 展开 + media）。进度 UI 必须分两段如实显示。
2. **第二 isolate 常驻 staging 期**：native 内存多一份 collection；低端机需实测（P3 门禁）。
3. **preview 计数与 commit 计数可不同**（与既有 source 去重）：文案必须区分「待导入 X 张」与「实际新增 Y 张」。
4. **Windows 文件锁**：杀 isolate 后目录删除在 Windows 上可能需重试；首发目标 Android，但 host 实现须带重试（P1 实现，P0 测试覆盖重试路径）。
5. **receipt 重建依赖 usn 语义**：若 rslib 的 usn 覆盖不全（如 schema 变更），重建失败率上升——一律落 quarantine，不许降级为猜测。
6. **本计划不解决**：删除链路的物理回收（doc 41 S3–S7 照旧）、存量无主数据（§7）。这些不做完，生产验收仍 NO-GO。

## 12. 施工收据（施工后回填）

| 波次 | commit | 命令与指标 | 证据 |
|---|---|---|---|
| P0 | （未 commit） | `flutter test test/views/anki/anki_import_staging_first_p0_test.dart test/application/anki_official/official_anki_projection_scope_p0_test.dart test/views/anki_official/official_anki_mapping_page_test.dart` → **4 failed**（S-a catalog 残留 source；S-b live generation 1→2；S-c `needsMapping==true`；S-d `mapping-save.onPressed==null`）。S-a/S-c 为文件型 catalog SQLite。 | 用例：`anki_import_staging_first_p0_test`（S-a/S-b）、`official_anki_projection_scope_p0_test`（S-c）、`official_anki_mapping_page_test` P0 S-d。生产代码未改。 |
| P1 | （未 commit） | `flutter test test/views/anki/anki_import_staging_first_p0_test.dart test/application/anki_official/official_anki_staging_manager_test.dart` → **S-a/S-b + manager 3 passed**。S-c/S-d 仍红。catalog 11→12。 | `OfficialAnkiStagingManager` + `OfficialAnkiImportSaga.startStaging/cancelActive`；wizard parse/cancel 走 staging；live `importFile` 保留。wizard commit 仍假定 live 已有卡（P3）。 |
| P2 | （未 commit） | `flutter test test/views/anki_official/official_anki_mapping_page_test.dart test/application/anki_import/official_preview_mapping_intents_test.dart test/application/anki_official/official_anki_projection_scope_p0_test.dart` → **S-d + skip/needsMapping + mapping 回归 passed**；S-c 仍红。S-a/S-b 保持绿。 | 映射页二选一正面、save 恒可点并 pop；preview「已确认」；skip 清横幅；确认不写全局 mapping 表；`OfficialAnkiMappingRoute` 移出 diagnostics guard。 |
| P3 | （待填） | （待填） | （待填） |
| P4 | （待填） | （待填） | （待填） |
