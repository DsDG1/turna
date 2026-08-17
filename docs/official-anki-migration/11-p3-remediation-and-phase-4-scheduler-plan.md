# P3 阻断修补 + Phase 4 官方 Scheduler 实施计划

> 文档代号：P3R-P4
> 状态：计划冻结；`P3 REMEDIATION REQUIRED / P4 ENTRY NO-GO / PRODUCTION NO-GO`
> 制定日期：2026-08-17
> 当前分支：`spike/official-anki-core-android`
> 审计基线：`cc1484b30739bceeba07fe1a3be98b8b0e11018d` + 当前 dirty worktree
> 上游 Anki pin：`967aa0d578fc75181e292e95326f9b58698da25c`
> 当前 contract：`1.2`
> P4 目标 contract：`1.3`（候选，冻结后不得重排 operation ID）
> 首发平台：Android arm64
> 输入文档：`p3fix.md`、`10-phase-3-fix-result-report.md`、`09-p2-entry-remediation-and-phase-3-plan.md`、`00-overall-migration-plan.md`
> 明确排除：License/法律签字、AnkiWeb Sync、Phase 5 Legacy 删除、OHOS/iOS/桌面发布
> 生产原则：P3R 和 P4 硬门禁完成前，projection/course-entry/scheduler flags 全部默认关闭

## 1. 执行摘要

当前工作树已经具备官方 Collection、导入、原卡渲染、课程投影 Host 骨架，以及一组尚未正式发布的
Scheduler Rust spike。但它还不能被视为完整的 Phase 3，也不能直接进入 Phase 4 生产切流。

2026-08-17 复核得到以下事实：

- Flutter 官方 Anki、schema 和 ShowWord 相关测试共 147 项通过。
- Rust `cargo test --lib` 在指定仓库内 `protoc` 后 60 项通过。
- JS card-frame protocol 通过。
- Android JVM 单测 `BUILD SUCCESSFUL`。
- contract 1.2 Android `.so` 和 debug APK 哈希与 P3FIX 结果报告一致。
- Device A、connected instrumentation、5k/RSS、release、第二设备和 clean CI 没有通过证据。
- P3 投影 service 和 Mapping Wizard 只在测试中实例化，生产 UI 没有生成课程入口。
- canonicalLink 打开 Reviewer 后不提交课程 Interaction，会阻断课程推进。
- 同 source 单 writer 对相同 owner 不成立，正常的 `needs_mapping → generate` 会留下多个 active job。
- Lesson 512 KiB 检查只检查 chunk，最终又合并成一个可能超限的 JSON。
- mapping version/status/JSON 存在不一致，选择题正确答案固定在第一个位置。
- Scheduler 11～16 号操作只存在 Rust/spike 层，稳定 contract、Dart worker、正式 UI 和设备证据均未建立。

因此采用两段式施工：

```text
P3R：关闭现有课程投影的生产阻断
  ↓ P3R Technical Acceptance Gate
P4：正式化官方 Scheduler contract、session、UI 和数据所有权
  ↓ P4 Technical Acceptance Gate
受控内部渠道 / Beta
```

P4 的 Scheduler 在架构上不读取课程投影，也不依赖 Mapping。但本计划要求先通过 P3R 门禁，再接入
生产 Scheduler UI，避免同时扩张两个尚未验收的用户链路。P4 Host contract 可在 P3R 后半段并行开发，
不得提前打开生产 flag。

## 2. 当前决策与完成边界

### 2.1 当前决策

```text
P0/P1 TECHNICAL: CONDITIONAL GO
P2 TECHNICAL ACCEPTANCE: NO-GO
P3 HOST CONSTRUCTION: PARTIAL GO
P3 TECHNICAL ACCEPTANCE: NO-GO
P3 PRODUCTION: NO-GO
P4 HOST SPIKE: EXISTS, NOT A STABLE CONTRACT
P4 ENTRY: NO-GO
P4 PRODUCTION: NO-GO
```

“Rust 中已经能 Answer/Undo”不等于“Phase 4 已实现”。P4 完成必须同时覆盖：

1. stable contract 和 typed DTO。
2. worker isolate 串行所有 Collection 读写。
3. 正式 Reviewer session 状态机。
4. Again/Hard/Good/Easy、真实耗时、Undo/Redo、Bury/Suspend、Counts/Congrats。
5. official Card 永不写 Turna SRS；Turna 派生练习永不写 Official Scheduler。
6. restart、跨日、filtered deck、daily limit 和设备差分测试。
7. release APK 与至少两台不同 Android/WebView 设备证据。

### 2.2 文档完成不等于技术完成

本文件是施工合同，不是结果报告。任务只有在以下材料同时存在时才可勾选：

- 对应源码和 migration。
- 自动化测试名称与通过数量。
- 实际执行命令和退出码。
- Android 任务必须附设备型号/API/WebView 版本。
- 性能任务必须附原始时间、RSS、UI heartbeat 数据。
- 结果报告必须给出真实 GO/NO-GO，不以代码行数替代验收。

## 3. 目标与非目标

### 3.1 P3R 目标

- 用户能够从 official source 进入 Mapping Wizard，保存、跳过并显式生成课程。
- App 冷启动能够发现已经 active 的 official projection。
- 同 source 严格只有一个 active writer，取消、异常和重启后状态可解释。
- canonicalLink 打开 Official Reviewer 后能够完成或显式退出当前课程项。
- mapping JSON、关系列、schema fingerprint 和 version 保持原子一致。
- 单 item 和最终 Lesson JSON 容量限制真实有效。
- 选择题顺序确定性但不可永远暴露第一项为正确答案。
- CourseProvider 只读取一个原子可见性事实源，不跨两个数据库拼接“半 active”状态。
- Device A 上完成 P2/P3 联合链路与 5k 性能门禁。

### 3.2 P4 目标

- 官方 Anki Card 的正式复习完全由 pinned `rslib` Scheduler 决定。
- Dart 只持有 opaque answer token、展示 DTO 和用户输入，不重算 SchedulingStates/FSRS。
- 正面/背面继续使用 Phase 2 Official Reviewer 渲染能力。
- 回答成功后由官方 Collection 写 Card、revlog、FSRS/memory state。
- Undo/Redo 使用官方 Collection 操作，不删除 Turna 历史模拟。
- 支持 deck counts、congrats、bury/suspend，并定义 filtered deck 行为。
- App 重启、进程被杀、跨日或 deck 切换后，过期 token 一律 fail closed 并重新取队列。
- 首页可聚合 official due count 和 Turna due count，但两个事实源绝不合并存储。

### 3.3 非目标

- 不实现 AnkiWeb Collection/Media Sync。
- 不迁移或删除 Legacy Anki 表与代码。
- 不把 Turna 自有课程迁入官方 Collection。
- 不让 P3 派生练习调用 Official Scheduler。
- 不把 official Card 回答同步写入 Turna `srs_states`。
- 不在 Dart 中实现 FSRS、fuzz、daily limit 或 filtered deck 规则。
- 不直接暴露上游 Protobuf 或 SQLite schema 给 Dart。
- 不以 WebView JavaScript 调用原生 Scheduler。
- 不在每次正常回答前创建完整 Collection backup；正常回答由官方 Undo/Redo 负责。

## 4. 不可变架构与所有权

### 4.1 数据所有权

| 数据 | 唯一权威 | 允许的 Turna 数据 |
|---|---|---|
| official Card/Note/Notetype/Deck | Official Collection | source/card ID 引用 |
| official queue/FSRS/revlog | Official Collection Scheduler | 只读展示 DTO、非权威诊断计数 |
| official 原卡 HTML/AV | Official renderer + media | 当前帧内存缓存 |
| P3 字段 mapping/placement | Official catalog | 用户确认配置 |
| P3 课程树和 Interaction | CourseDatabase 派生缓存 | 可删除、可重建 |
| Turna 原生词汇/语法 SRS | Turna SRS | 原有状态 |
| P3 派生练习得分 | Turna 课程统计 | 不改变 official due |
| P4 UI session | 内存状态机 | 不持久化 SchedulingStates |

### 4.2 三条互斥路径

```text
Official preview/canonicalLink
  → Official renderer
  → 无评分按钮
  → Official Scheduler writes = 0

Official formal review
  → Official queue token
  → Official renderer
  → Again/Hard/Good/Easy
  → Official Scheduler writes = 1 per confirmed answer

Turna derived exercise
  → Flutter Interaction renderer
  → Turna 课程统计
  → Official Scheduler writes = 0
```

canonicalLink 仍是“查看原卡”，不得因为 P4 上线而隐式变成一次正式复习。正式复习只能从清楚标记的
Official Review 入口开始。

### 4.3 线程和进程边界

- Flutter UI isolate 不执行 Collection I/O。
- 所有 official Collection 操作通过一个 worker isolate/Engine owner 串行执行。
- WebView 只显示 renderer 结果，不拥有 FFI 或 Scheduler bridge。
- UI 不缓存可跨 session 使用的 answer token。
- Import、projection read 和 formal review 不得同时争用同一个 Collection writer。

## 5. 阶段依赖和硬门禁

```text
P3R-000 基线冻结
  ├─ P3R-010～013 生产接线/课程推进
  ├─ P3R-020～023 job/发布一致性
  └─ P3R-030～032 mapping/payload/容量
              ↓
        P3R-040 联合端到端
              ↓
        P3R-050 Device A/5k/release
              ↓
        P3R TECHNICAL ACCEPTANCE
              ↓
P4-000 contract 冻结
  ├─ P4-010～013 Native/Dart boundary
  ├─ P4-020～024 session/UI/actions
  └─ P4-030～032 durability/ownership
              ↓
        P4-040 differential/fixture
              ↓
        P4-050 Device A/B/release
              ↓
        P4 TECHNICAL ACCEPTANCE
```

P4 Host contract 工作最早可在 P3R-020/030 通过单测后并行开始；P4 production route、flag 或真实用户
Scheduler 写入必须等待 P3R-050 通过。

## 6. P3R 数据库修订

### 6.1 Official catalog v5（候选）

目标：让 job 单写者和 mapping 一致性成为数据库不变量，而不是调用顺序约定。

```sql
CREATE UNIQUE INDEX IF NOT EXISTS anki_projection_one_active_writer
ON anki_projection_jobs(source_id)
WHERE state IN (
  'created', 'scanning_source', 'scanning_schema', 'needs_mapping',
  'projecting', 'publishing', 'retry_wait', 'cancel_requested'
);
```

迁移前必须：

1. 查询同 source 多个非终态 job。
2. 保留 heartbeat 最新且 owner/state 可解释的一条。
3. 其余标记 `abandoned`，写稳定 reason `migration_duplicate_writer`。
4. 再建立唯一索引。
5. migration 必须在 transaction 内完成并有重复 job fixture。

`needs_mapping` 是可恢复的非终态 job。用户点击“生成课程”时调用 `resumeJob(jobId, ownerToken)`，不得创建
第二个 job。App 重启且 heartbeat 过期时，旧 job 先进入 `abandoned`，新 owner 再从 0 创建 job。

### 6.2 CourseDatabase v17（候选）

增加 CourseDatabase 内的投影可见性 manifest：

```sql
CREATE TABLE official_anki_projection_manifest (
  source_id TEXT PRIMARY KEY NOT NULL,
  active_generation TEXT NOT NULL,
  source_fingerprint TEXT NOT NULL,
  projection_version INTEGER NOT NULL,
  section_count INTEGER NOT NULL,
  lesson_count INTEGER NOT NULL,
  item_count INTEGER NOT NULL,
  published_at_millis INTEGER NOT NULL
);
```

Course tree、lesson content、projection index 和 manifest 必须在同一个 CourseDatabase transaction 内替换。
CourseProvider 以 manifest 为唯一可见性事实源；catalog 的 projection state 只做 job/recovery/诊断镜像，
不得再与 Course index 临时拼接出 active 状态。

发布顺序：

```text
构建完整 projection plan
→ CourseDatabase transaction:
     验证 source ownership
     替换 source tree/index/content
     写 manifest active_generation/fingerprint
→ commit
→ best-effort 镜像 catalog job/source state
→ Provider reload
```

若进程在 Course commit 后、catalog 镜像前死亡，冷启动以 Course manifest 恢复可见课程，并把 catalog
诊断状态对账到 manifest。不得把两个独立 SQLite transaction 描述为“跨数据库原子提交”。

## 7. P3R 施工任务

### P3R-000：冻结基线并修正文档事实

工作：

- 保存当前 dirty worktree 文件清单和目标 diff，避免混入非 Anki 修改。
- 把 `p3fix.md` 的未勾选验收项与结果报告逐项对账。
- 将“Host construction complete”拆成 complete/partial/not-wired。
- 记录 `.so`、APK、APK 内 `.so` 哈希和 build 命令。
- 建立 `artifacts/p3r-p4/`，保存 commands、test logs、device metadata、metrics 和 decision。

验收：

- 文档不再同时出现“已完成单 writer”和“验收项未勾选”的冲突。
- 每个已完成项有命令、commit/diff 和证据路径。
- 未跑设备项保持明确 NO-GO。

### P3R-010：建立生产 composition 和 source 管理入口

新增正式 composition：

```text
OfficialAnkiSourceManagementPage
  → list official sources
  → schema scan
  → Mapping Wizard
  → save/skip mapping
  → explicit Generate Course
  → projection progress/cancel/retry
  → CourseProvider.reloadCourse()
```

要求：

- `OfficialAnkiCourseProjectionService` 由 production composition factory 创建，不由 widget 拼装数据库路径。
- sourceId/profileId/Engine/catalog/CourseDatabase 来自同一个 profile scope。
- Mapping 保存不自动生成课程。
- Generate 按钮必须携带现有 `needs_mapping` job ID 或显式创建新 job。
- UI 展示 job state、processed/total、稳定错误码和可操作恢复动作。
- 页面退出不自动取消；用户明确取消才写 `cancel_requested`。
- production route 有 flag/capability gate，失败时不 fallback Legacy。

测试：

- production composition 测试不得使用 test-only hook。
- import → schema → mapping → generate → reload 的 integration test。
- kill/recreate page 后 job 和 mapping 仍可恢复。

### P3R-011：修复冷启动 catalog/CourseProvider 接线

当前 catalog hook 只在 `requireImporter()` 后设置。改为应用 profile 初始化时建立只读 catalog/course locator，
不要求用户先打开导入页面。

要求：

- App cold start 在 CourseProvider 首次 `load()` 前完成 official profile locator 初始化。
- locator 只打开 catalog，不隐式启动 import 或 native Collection writer。
- flags 关闭时不显示 official section，但不得删除 manifest/tree。
- flags 重新开启或 projection 发布后，调用明确的 Provider reload/invalidate API。
- 多次 load/reload 不泄漏 SQLite handle。

测试矩阵：

- cold start + existing active manifest。
- cold start + catalog missing。
- flag off/on。
- Course DB 被重建但 catalog mapping 保留。
- active source 删除后 reload。

### P3R-012：修复 canonicalLink 的完成语义

`OfficialAnkiCanonicalLinkView` 接收明确回调：

```dart
Future<void> onOpenAndAcknowledge(OfficialAnkiCanonicalRef ref)
```

首版语义：

- 点击按钮成功 push Official Reviewer。
- Reviewer 正常返回后显示“已查看原卡”，用户点击继续或自动调用一次 `onSubmit(true)`。
- Reviewer 初始化失败、capability 缺失或路由失败时不提交，显示可重试/跳过策略。
- 重复 rebuild、返回和按钮双击不得重复提交。
- canonical preview 不显示 Again/Hard/Good/Easy，不写 Scheduler。

验收测试必须从 LessonViewModel 开始，验证：

```text
canonical item visible
→ open reviewer
→ return
→ submitted exactly once
→ lesson advances
→ official scheduler write counter remains 0
```

### P3R-013：补齐课程生成入口的用户状态

为 source 页面定义状态：

```text
not_projected
scanning
needs_mapping
ready_to_generate
generating
active
cancelled
retryable_error
fatal_error
```

- `needs_mapping` 必须列出未确认/needsReview Notetype。
- active 页面显示 fingerprint、Card/item/lesson 数和上次生成时间。
- reimport 后显示“需要重建”或“mapping 需要复核”，不静默覆盖。
- 删除 projection 只删除派生课程，不删除 Collection、mapping、placement。

### P3R-020：落实数据库级单 writer 和 job resume

Repository API 收敛为：

```dart
createJob(...)
resumeJob(jobId, ownerToken)
requestCancel(jobId, ownerToken)
heartbeat(jobId, ownerToken, ...)
markActive/Failed/Cancelled/Abandoned(...)
claimStaleJob(...)
```

禁止：

- 只按 sourceId 取消“最新”job。
- 相同 owner 绕过 active writer 检查。
- check-then-insert 而没有 transaction/unique index。
- 普通异常离开后仍保持 `projecting/publishing`。

job 状态测试：

- same owner 并发创建。
- different owner 并发创建。
- needsMapping 原 job resume。
- stale heartbeat claim。
- cancel 当前 job 后创建新 job。
- 100 次 needsMapping/generate 后非终态 job 数始终 <= 1。

### P3R-021：统一异常、取消和重试出口

`projectSource()` 顶层使用 `try/catch/finally` 保证：

- `OfficialAnkiException` 映射稳定 error code。
- `StateError`、JSON/parser、SQLite 和未知异常映射 `INTERNAL_ERROR`，debugDetails 只进诊断日志。
- 所有失败都将当前 job 标记 `failed` 或 `retry_wait`。
- `_currentJobId` 在终态后清空。
- cancel 使用 jobId + owner token，只能取消本 owner 当前 job。
- retryable 只表示允许用户重试；若没有自动 retry scheduler，不得宣称自动重试已实现。

不得向 UI 暴露 raw Note、模板 HTML、数据库路径或原生 panic 文本。

### P3R-022：建立单一可见性 manifest 和对账

- 实现 CourseDatabase v17 manifest migration。
- `replaceOfficialProjection()` 在一个 transaction 写 tree/index/content/manifest。
- Provider 只加载 manifest 存在且 fingerprint 与 index 一致的 source。
- catalog 状态与 manifest 不一致时进入 reconciliation，不删除已提交课程。
- 删除 source projection 时 tree/index/content/manifest 同 transaction 删除。
- fault injection 覆盖每个 insert、manifest 前、manifest 后和 catalog mirror 前后。

### P3R-023：限制内存并明确 rebuild-from-0

首版仍允许安全全量重建，但必须满足 5k 门禁：

- card-set fingerprint 使用 incremental sink，不构造完整 ID 字符串。
- source ID page 始终 <= 500。
- projection rows 不无限驻留；按 lesson bucket staging，或明确测得 5k 峰值 <= 120 MB。
- 不实现 cursor resume 时，UI/报告只写“restart 后从 0 重建”。
- job cursor 只用于进度诊断，不冒充持久 checkpoint。

若 5k RSS 不达标，则实现 bounded derived staging；不得通过提高门槛掩盖问题。

### P3R-030：修复 mapping 原子一致性和版本

定义 canonical mapping JSON。版本比较必须覆盖：

- notetypeId。
- schemaFingerprint。
- role → field index/name。
- direction。
- enabledKinds。
- single-field mode。
- userConfirmed/skip 状态中影响生成的部分。

规则：

- 保存相同 canonical mapping 不增加 version。
- direction、enabledKinds 或 role 变化必须增加 version。
- schema 改变时，在同一 transaction 更新 `mapping_json`、status 列、schema fingerprint、version 和 timestamp。
- `needsReview` 不发布新树，旧 manifest 保持 active。
- `skipNotetype()` 延续当前 version 并按真实变化递增，不写死 1。
- UI 永远从 canonical JSON + 校验后的关系列加载，不信任互相矛盾的双份状态。

### P3R-031：修复题目质量和容量限制

选择题：

- 默认要求 1 个正确项 + 3 个唯一、非空、bounded 干扰项。
- 不足时不生成 multipleChoice/listenPick，回落 flip 或 canonicalLink。
- 使用 `sourceFingerprint + cardId + kind + algorithmVersion` 作为确定性 shuffle seed。
- `correctIndex` 由 shuffle 后位置计算，不固定为 0。
- 同一 fingerprint 重建顺序稳定；内容或 algorithm version 变化才改变。

容量：

- 单 item 最终 UTF-8 JSON <= 32 KiB。
- 单 Lesson 最终 UTF-8 JSON <= 512 KiB。
- split 必须在 projector 层生成新的 deterministic lesson ID/part，不能把多个合格 chunk 再合并回同一 JSON。
- 超限记录 bounded projection issue；不得抛普通 `StateError` 留下 active job。
- 单个无法派生的 Card 可生成 bounded canonicalLink；不能伪造截断后的正确答案。

### P3R-032：补齐 P3 测试盲区

必须新增失败先行测试：

- production 中能找到 ProjectionService/Mapping Wizard route。
- canonicalLink 返回后 LessonViewModel 前进且仅提交一次。
- same-owner active writer 被数据库拒绝或 resume 原 job。
- schema change 后 JSON/列/fingerprint/version 一致。
- enabledKinds/direction 改变增加 mapping version。
- 20 个接近 32 KiB item 最终 Lesson 仍 <= 512 KiB 并 deterministic split。
- 任意非 OfficialAnkiException 后 job 为终态。
- 100 张选择题 correctIndex 不恒为 0，重建结果稳定。
- cold start 不需要先打开 import page 即可加载 active official section。
- Course commit/catalog mirror crash window可对账。

### P3R-040：端到端联合验收

Host/integration 路径：

```text
import official source
→ close/reopen app services
→ scan schemas
→ save/skip mappings
→ generate course
→ provider reload
→ section/unit/lesson visible
→ flip/MC/listen/type renderer round-trip
→ canonicalLink open/return/advance
→ reimport
→ needsReview/rebuild
→ delete projection
→ mapping/locked placement preserved
```

全链路断言：

- Scheduler writes = 0。
- Legacy official-path calls = 0。
- 同 source 非终态 job <= 1。
- Course manifest/index/content fingerprint 一致。
- 所有媒体仅通过 validated official media origin 读取。

### P3R-050：Device A、性能和 release 门禁

必须执行：

- P2 instrumented WebView 10 个用例。
- Device A debug import/render/flip/typed/media/MathJax。
- Device A 5k projection：<= 60 s。
- UI isolate 不出现 >= 500 ms stall。
- 峰值 RSS 增量 <= 120 MB，完成后回落。
- cancel latency、restart rebuild、delete/rebuild、100 次 job residue。
- release APK 同链路。
- 第二台不同 API/WebView 设备至少执行 P2/P3 smoke。
- clean CI runner 运行 Rust/Dart/Flutter/Kotlin/Android build。

只有本任务全部通过，才能写：

```text
P3 TECHNICAL ACCEPTANCE GO
P4 PRODUCTION IMPLEMENTATION ENTRY GO
```

## 8. P4 Contract 1.3 设计

### 8.1 现有 Scheduler spike 的处理

Rust 当前已有 11～16 的实验实现：

| ID | 当前 Rust 名称 | 当前状态 | P4 行动 |
|---:|---|---|---|
| 11 | SET_CURRENT_DECK | spike | 正式化 camelCase contract 和校验 |
| 12 | GET_REVIEW_QUEUE | spike | typed queue DTO、bounded fetch、token lifecycle |
| 13 | DESCRIBE_NEXT_STATES | spike | typed label DTO 或并入 queue，保持兼容 |
| 14 | ANSWER_CARD | spike | 真实 elapsed、单飞、错误恢复 |
| 15 | GET_UNDO_STATUS | spike | stable DTO |
| 16 | UNDO | spike | reload queue、失效旧 token |

这些编号已经预留，不得改作其他用途。当前 `contract/operations.md` 没有发布它们，稳定 Dart
`OfficialAnkiOperation` 也没有对应定义，因此 P4 必须完成正式 contract 发布，而不是继续从 spike models
按数字调用。

### 8.2 追加 operation 编号

17～26 已使用，新增操作从 27 开始追加：

| ID | operation | 用途 |
|---:|---|---|
| 27 | REDO | 官方 Redo |
| 28 | BURY_OR_SUSPEND_CARDS | bury card/siblings、suspend/unsuspend |
| 29 | COUNTS_FOR_DECK_TODAY | 首页/Deck 当日计数 |
| 30 | CONGRATS_INFO | 完成页和 remaining limits |

operation 名称和 ID 一旦进入 contract fixture 即 append-only。若 pinned rslib 无法稳定支持某操作，保留
capability 缺失并 fail closed，不用 Dart 猜测实现。

### 8.3 稳定 DTO

请求/响应统一 camelCase。候选 queue DTO：

```json
{
  "sessionId": "opaque-session",
  "queueEpoch": 7,
  "newCount": 10,
  "learningCount": 2,
  "reviewCount": 30,
  "cards": [
    {
      "cardId": 123,
      "noteId": 99,
      "deckId": 1,
      "templateOrdinal": 0,
      "queueKind": "review",
      "answerToken": "opaque-token",
      "labels": {
        "again": "1m",
        "hard": "6d",
        "good": "15d",
        "easy": "1mo"
      }
    }
  ]
}
```

`answerToken` 必须是 opaque string。Dart 不得看到：

- SchedulingStates/current/new state protobuf。
- FSRS memory state。
- Scheduler context/custom data。
- revlog row payload。
- Collection schema 或 config blob。

答题请求：

```json
{
  "sessionId": "opaque-session",
  "queueEpoch": 7,
  "answerToken": "opaque-token",
  "cardId": 123,
  "rating": "good",
  "answeredAtMillis": 1786965000000,
  "millisecondsTaken": 8421
}
```

Native 使用官方当前时间语义并校验 elapsed：非负、有合理上限、溢出失败。不得继续把
`millisecondsTaken` 固定为 0。

### 8.4 token 和 queue epoch

首版采用正确性优先策略：

- 每次 `GET_REVIEW_QUEUE` 创建新的 session/queue epoch。
- Answer 成功、Undo、Redo、deck switch、import、reopen、close 都使旧 epoch/token 失效。
- 回答一张卡后重新取官方 queue，不继续使用回答前批量计算的其他 token。
- token 单次消费；重复点击返回稳定 `SCHEDULING_CONTEXT_STALE`，不得重复写 revlog。
- Answer native 写成功但响应丢失时，通过 card/revlog/undo status reconciliation 判断结果，UI 不自动重答。

### 8.5 稳定错误码

稳定 Dart error enum 增加：

```text
QUEUE_EMPTY
SCHEDULING_CONTEXT_STALE
ANSWER_FAILED
UNDO_UNAVAILABLE
REDO_UNAVAILABLE
DECK_NOT_FOUND
SCHEDULER_BUSY
SCHEDULER_CAPABILITY_MISSING
```

错误响应只返回稳定 messageKey、recoverable 和 bounded debugDetails。不得把 SQL、Note 字段或模板内容
放入错误消息。

## 9. P4 施工任务

### P4-000：冻结 Phase 4 entry baseline

- 确认 P3R-050 结果为 GO。
- 保存当前 Collection fixture backup 和哈希。
- 记录 contract 1.2 fixtures、operation 表和现有 Scheduler spike diff。
- 对 11～16 每个操作做“保留/重写/删除 spike wrapper”的明确决定。
- 更新总体方案：P4 不依赖课程投影数据，但生产入口依赖 P3R 技术验收。

### P4-010：正式发布 contract 1.3 Scheduler operations

- 更新 `contract/VERSION` 为 1.3。
- 在 `operations.md` 发布 11～16 和 27～30。
- 为每个 request/response 添加 golden fixture。
- `ENGINE_INFO.capabilities` 精确报告实际支持项。
- 旧 1.2 Dart 遇到 1.3 native 可继续使用既有能力。
- 新 Dart 遇到不含 Scheduler capability 的旧 native 必须 fail closed。
- Android `.so`、debug/release APK 和 source pin 重新构建并记录哈希。

### P4-011：重写 Native Scheduler session boundary

- 把 spike 的 snake_case/裸整数 token 改为 stable serde DTO。
- answer token 绑定 engine handle、sessionId、queueEpoch、cardId 和一次性消费状态。
- queue fetchLimit 限制 1～100；正式 UI 首版每次只消费第一张。
- Answer 使用真实 `millisecondsTaken`。
- Answer 成功后清空旧 queue tokens、增加 epoch。
- Answer 失败时区分“未写入”和“可能已写入需对账”。
- Undo/Redo/deck switch/import/reopen 全部 invalidates tokens。
- 所有 panic 留在 FFI boundary 内。

### P4-012：实现 Native Redo、Bury/Suspend、Counts/Congrats

动作 DTO 必须是枚举，不接受任意 SQL-like 字符串：

```text
bury_card
bury_siblings
unbury_deck
suspend_cards
unsuspend_cards
```

要求：

- Card IDs 去重、数量 bounded、全部为正数。
- source/deck/session scope 明确。
- mutation 成功后失效 queue epoch。
- Counts/Congrats 直接调用 pinned rslib，不从 Card queue 字段手算。
- filtered deck 不支持的动作返回 capability/invalid-state，不静默修改普通 deck。

### P4-013：Native differential 和事务测试

对相同初始 Collection fixture，比较 bridge 与直接 rslib 调用：

- queue card order/kind/count。
- Again/Hard/Good/Easy 后 Card queue/due/interval/reps/lapses。
- revlog count 和 rating。
- Undo/Redo 前后 Card 与 revlog。
- bury/suspend。
- daily limits、filtered deck、learning/relearning。
- FSRS on/off（若当前 pinned backend 支持）。

比较字段应使用官方公共 API；确需测试 SQL 时只放 Rust test 内，不进入 contract。

### P4-020：扩展 Dart Engine、worker 和 typed DTO

为稳定接口增加：

```dart
Future<OfficialReviewQueue> getReviewQueue(...);
Future<OfficialAnswerResult> answerCard(...);
Future<OfficialUndoStatus> getUndoStatus();
Future<OfficialMutationResult> undo();
Future<OfficialMutationResult> redo();
Future<OfficialDeckCounts> countsForDeckToday(...);
Future<OfficialCongratsInfo> congratsInfo(...);
Future<void> buryOrSuspendCards(...);
```

所有实现层必须齐全：interface、FFI transport、worker command、session facade、fake、contract fixture 和错误
映射。production code 不得引用 `official_anki_spike_models.dart`。

### P4-021：实现 OfficialReviewSession 状态机

状态：

```text
idle
→ opening
→ loadingQueue
→ showingQuestion
→ showingAnswer
→ committingAnswer
→ refreshingQueue
→ completed

任意非终态
  ├─ recoverableError → retry/reload queue
  ├─ staleContext → discard token → reload queue
  └─ fatalError → controlled error page
```

不变量：

- 同时只有一个 in-flight Scheduler mutation。
- 未显示答案前不启用评分按钮。
- 每个 token 最多提交一次。
- double tap、back gesture、App lifecycle pause 不产生双 revlog。
- UI dispose 不关闭其他 official source 共用的 worker。
- source import/projection 与 formal review 的 Collection access 通过同一协调器互斥。

### P4-022：实现正式复习 UI

页面顺序：

```text
选择 official deck
→ 显示 new/learning/review counts
→ question frame + AV
→ Show Answer
→ answer frame + typed comparison（如有）
→ Again/Hard/Good/Easy + 官方 interval labels
→ native commit
→ 下一张或 Congrats
```

要求：

- 继续使用 P2 sandboxed Reviewer，不新增 WebView native bridge。
- interval labels 完全使用 native response。
- 按钮禁用覆盖 commit 全过程。
- Answer 成功后才记录非权威 Turna analytics/XP；analytics 失败不得回滚官方答案。
- Answer 失败不假装成功、不自动 fallback Turna SRS。
- accessibility、横竖屏、字体缩放、深色模式有 widget/device 测试。

### P4-023：Undo/Redo、Bury/Suspend 和完成页

- Undo/Redo 操作后重新请求 queue 和当前卡，不复用旧 HTML/token。
- Bury card/siblings、Suspend 有确认和明确作用域。
- suspended Card 从当前 session 消失。
- Congrats 使用官方返回，显示今日完成/仍有学习卡/受 limit 限制等状态。
- UI 不根据本地 list 为空自行断言“今日完成”。

### P4-024：首页和课程入口边界

- 首页可并列显示 `Turna due` 与 `Official Anki due`。
- 总数展示可以相加，但点击后进入各自独立 route。
- P3 canonicalLink 始终是 preview，不出现评分按钮。
- P3 derived interaction 得分不改变 official counts。
- formal Official Review 不写 Course lesson progress，除非另有非权威事件记录且字段明确。

### P4-030：持久化、重启和跨日语义

测试：

- question 状态杀进程：重启重新取 queue。
- answer frame 杀进程但未点击：无 revlog。
- commit 前杀进程：无写入或可明确判定。
- native 已写、response 丢失：对账后不重复 answer。
- Answer 后立即杀进程：重启 queue/due/revlog 与官方一致。
- 跨午夜、时区变更、夏令时（测试时钟可控）。
- deck switch、filtered deck、daily limits。
- backend reopen/Collection lock。

禁止持久化 answer token 或 SchedulingStates 来“恢复到原按钮”。重启恢复方式始终是重新打开 Collection 并
重新请求官方 queue。

### P4-031：禁止双写和副作用审计

增加 debug/test counters：

```text
officialSchedulerAnswers
officialSchedulerUndo
officialSchedulerRedo
turnaSrsWritesFromOfficialPath
legacyCallsFromOfficialPath
courseProjectionWritesDuringReview
```

门禁：

- 每次确认评分 exactly one official answer。
- `turnaSrsWritesFromOfficialPath = 0`。
- `legacyCallsFromOfficialPath = 0`。
- `courseProjectionWritesDuringReview = 0`。
- preview/canonicalLink/derived exercise 的 official Scheduler answers = 0。

静态检索不能替代 runtime counter；runtime counter 也不能替代数据库前后差分。

### P4-032：备份、升级和回滚策略

- contract/backend 升级前创建官方 backup/checkpoint。
- 正常 review 不逐题创建完整 backup。
- 关闭 Scheduler flag 只停止新 formal session，不撤销已经合法提交的官方回答。
- flag 关闭后 official Collection/revlog 保留，P2 preview 仍按各自 flags 决定是否可用。
- backend downgrade 不直接覆盖仍打开的 Collection。
- 回滚 UI/contract adapter 时保留对已写官方 scheduling 数据的兼容读取。

### P4-040：联合自动化和 differential suite

必须覆盖：

| 类别 | 用例 |
|---|---|
| Queue | new、learning、review、relearning、空队列 |
| Ratings | Again、Hard、Good、Easy |
| Context | duplicate token、stale epoch、wrong card、deck switch |
| Time | real elapsed、0、上限、跨日、时区 |
| History | revlog、Undo、Redo、restart |
| Actions | bury card、bury siblings、suspend、unsuspend |
| Limits | daily new/review、filtered deck、Congrats |
| Renderer | question、answer、AV、typed、MathJax |
| Ownership | official-only writes、Turna SRS zero writes |
| Lifecycle | background、dispose、worker crash、Collection lock |

同一 fixture 必须记录：初始 Collection hash、backend commit、操作序列、最终 Card 公共状态和 revlog 摘要。

### P4-050：设备、性能、release 和发布门禁

Device A：

- debug/release 各完成至少 100 张混合队列 review。
- Again/Hard/Good/Easy、Undo/Redo、bury/suspend。
- 音频、TTS、typed、MathJax、自定义字体。
- App background/foreground、进程杀死重启、旋转和低内存。
- 连续 100 张无 >= 500 ms UI stall。
- queue fetch、首帧 render、answer commit p50/p95。
- 复习前后 RSS 和完成后回落。

Device B：

- 不同 Android API/WebView 版本。
- 至少完整 smoke + 20 张 review + Undo + restart。

CI：

- Rust fmt/clippy/test + differential fixture。
- Dart scoped analyze + contract tests。
- Flutter official/session/widget/integration tests。
- Kotlin JVM + connected instrumentation。
- debug/release APK build、native hash/capability 探针。
- clean checkout 可复算。

## 10. Feature flags 和发布顺序

新增：

```text
TURNA_OFFICIAL_ANKI_SCHEDULER=false
```

候选 gate：

```dart
allowsOfficialScheduler =
  engine && import && catalogReady && runtimeCapable && platformReady &&
  renderer && scheduler;
```

Scheduler 不要求 `projection` 或 `courseEntry` flag；它使用 official source/deck route。组合矩阵：

| Renderer | Projection | Course Entry | Scheduler | 行为 |
|---:|---:|---:|---:|---|
| 0 | * | * | 1 | fail closed，不显示 formal review |
| 1 | 0 | 0 | 0 | 仅 P2 preview |
| 1 | 1 | 0 | 0 | 可后台生成，不显示课程 |
| 1 | 1 | 1 | 0 | P3 课程 + canonical preview，无评分 |
| 1 | 0/1 | 0/1 | 1 | 独立 Official Review route |

发布顺序：

1. 内部开发：P3R flags 手动开启，Scheduler false。
2. P3R 技术验收：P3 flags 可在测试渠道开启，Scheduler false。
3. P4 Host：Scheduler capability 编译存在，但 UI flag false。
4. P4 Device/Beta：白名单 source/profile，用户明确进入 formal review。
5. P4 Stable 候选：设备/CI/遥测门禁通过后再讨论默认开启。

任何阶段都不自动 fallback Legacy Scheduler 或 Turna SRS。

## 11. 性能与容量门禁

| 指标 | P3R/P4 门禁 |
|---|---:|
| projection ID page | <= 500 |
| projection native batch | <= 500 |
| single derived item JSON | <= 32 KiB |
| final Lesson JSON | <= 512 KiB |
| 5k projection | <= 60 s |
| projection RSS 增量 | <= 120 MB |
| review queue fetchLimit | 1～100 |
| queue response | <= 8 MiB，目标远低于上限 |
| question/answer render response | <= 8 MiB |
| answer double-submit | 0 |
| answer commit UI stall | 无 >= 500 ms stall |
| 100-card session leaked handles | 0 |
| preview/derived scheduler writes | 0 |
| formal review Turna SRS writes | 0 |

记录 p50/p95/max，不只记录单次最好值。

## 12. 测试与证据目录

建议：

```text
docs/official-anki-migration/artifacts/p3r-p4/
  baseline.txt
  commands.txt
  artifact-manifest.txt
  p3r-host-tests.txt
  p3r-device-a.txt
  p3r-performance.json
  p4-contract-tests.txt
  p4-differential.json
  p4-device-a.txt
  p4-device-b.txt
  p4-performance.json
  scheduler-write-audit.json
  release-probe.txt
  final-decision.txt
```

每份设备证据至少包含：

- 日期、git commit、dirty 状态。
- backend pin、contract、APK/native hash。
- 设备型号、ABI、Android API、WebView 版本。
- flags。
- fixture/source hash。
- 命令、退出码和原始指标。

## 13. 候选验证命令

以下为候选命令；实施时必须把真实退出码和数量写入结果报告：

```bash
PROTOC=/absolute/path/to/native/turna_anki_core/tools/protoc/bin/protoc \
  cargo fmt --manifest-path native/turna_anki_core/Cargo.toml -- --check

PROTOC=/absolute/path/to/native/turna_anki_core/tools/protoc/bin/protoc \
  cargo clippy --manifest-path native/turna_anki_core/Cargo.toml --all-targets -- -D warnings

PROTOC=/absolute/path/to/native/turna_anki_core/tools/protoc/bin/protoc \
  cargo test --manifest-path native/turna_anki_core/Cargo.toml --lib

flutter analyze --no-pub lib/application/anki_official lib/views/anki_official \
  test/application/anki_official

flutter test --no-pub test/application/anki_official \
  test/data/schema_migration_test.dart \
  test/views/lesson/renderers/show_word_test.dart

cd android
./gradlew :app:testDebugUnitTest
./gradlew :app:connectedDebugAndroidTest

flutter build apk --debug
flutter build apk --release
```

不得把缺少 `protoc`、无设备、依赖下载失败或 sandbox 权限失败记作产品代码通过或失败；必须单独标注
环境阻断并在正确环境重跑。

## 14. 完成检查表

### 14.1 P3R 技术完成

- [ ] production source management 能进入 Mapping Wizard 和显式 Generate。
- [ ] cold start 不依赖先打开 import page。
- [ ] canonicalLink 返回后课程仅提交一次并继续。
- [ ] 同 source 数据库级单 active writer。
- [ ] same-owner needsMapping 使用原 job resume。
- [ ] 任意异常后 job 状态可解释且非泄漏 active。
- [ ] Course manifest/tree/index/content 单事务一致。
- [ ] catalog/manifest crash window 可对账。
- [ ] mapping JSON/列/schema/version 原子一致。
- [ ] direction/enabledKinds 变化增加 version。
- [ ] correctIndex 不恒为 0 且 deterministic。
- [ ] 最终 Lesson JSON <= 512 KiB。
- [ ] Device A P2/P3 instrumentation 和 5k/RSS 通过。
- [ ] release 与第二设备 smoke 通过。
- [ ] Scheduler writes = 0；Legacy official calls = 0。
- [ ] P3R 结果报告给出真实 GO/NO-GO。

### 14.2 P4 Contract/Native 完成

- [ ] contract 1.3 正式发布 11～16、27～30。
- [ ] operation IDs append-only，golden fixtures 齐全。
- [ ] Engine capabilities 与实际实现一致。
- [ ] token 绑定 session/epoch/card 且单次消费。
- [ ] Answer 使用真实 elapsed。
- [ ] Answer/Undo/Redo/deck switch 后旧 token stale。
- [ ] bury/suspend/counts/congrats 使用官方 API。
- [ ] Rust differential suite 全绿。
- [ ] Android native/APK 重建并记录哈希。

### 14.3 P4 Dart/UI 完成

- [ ] stable Dart contract 不引用 spike models。
- [ ] FFI/worker/session/fake 全部实现 Scheduler API。
- [ ] OfficialReviewSession 单飞状态机成立。
- [ ] question/answer/四档/interval labels 完整。
- [ ] Undo/Redo、bury/suspend、Congrats 完整。
- [ ] canonical preview 与 formal review 路由明确分离。
- [ ] stale token、response lost、restart fail closed。
- [ ] formal review 不写 Turna SRS。
- [ ] preview/derived exercise 不写 Official Scheduler。

### 14.4 P4 发布完成

- [ ] Device A debug/release 100-card session 通过。
- [ ] Device B smoke/20-card/Undo/restart 通过。
- [ ] daily limits、filtered deck、跨日/时区通过。
- [ ] answer/revlog/Undo/Redo 与官方差分一致。
- [ ] 性能、RSS、UI stall 达标。
- [ ] clean CI 可复算。
- [ ] scheduler flag 默认 false。
- [ ] P4 结果报告和 artifact manifest 完整。

## 15. 风险登记

| 风险 | 概率 | 影响 | 缓解/门禁 |
|---|---:|---:|---|
| P3 UI 仍只有测试接线 | 高 | 高 | P3R-010 production integration |
| 多 active job 导致重复发布 | 高 | 高 | catalog v5 partial unique index |
| canonicalLink 卡住 lesson | 高 | 高 | P3R-012 VM 端到端测试 |
| Lesson 最终 JSON 超限 | 中 | 高 | projector-level deterministic split |
| mapping 双份状态漂移 | 高 | 中 | canonical JSON + transaction |
| Scheduler token 重复提交 | 中 | 极高 | single-use token + UI single-flight |
| native 写成功但响应丢失 | 中 | 极高 | revlog/undo reconciliation |
| official 和 Turna SRS 双写 | 中 | 极高 | route ownership + runtime counters |
| 回答后旧批量 token 失真 | 中 | 高 | 每次 mutation 后重取 queue |
| elapsed 一直为 0 破坏统计 | 高 | 中 | monotonic UI timer + native validation |
| filtered deck/daily limit 被 Dart 重算 | 中 | 高 | official Counts/Congrats only |
| WebView 获得 Scheduler bridge | 低 | 极高 | no JS/native bridge architecture |
| 设备无证据却提前开 flag | 高 | 极高 | P3R-050/P4-050 hard gate |
| dirty worktree 无法复算 | 高 | 高 | 基线清单、主题提交、clean CI |

## 16. 回滚

### 16.1 P3R 回滚

```text
TURNA_OFFICIAL_ANKI_PROJECTION=false
TURNA_OFFICIAL_ANKI_COURSE_ENTRY=false
```

- 隐藏 official 派生课程入口。
- 保留 Collection、mapping、placement 和 manifest，等待修复后重建。
- 不删除用户确认 mapping。
- 不 fallback Legacy official renderer/importer。

### 16.2 P4 回滚

```text
TURNA_OFFICIAL_ANKI_SCHEDULER=false
```

- 阻止创建新的 formal review session。
- 已合法写入的官方 Card/revlog 保留，不自动 Undo。
- P2 preview 和 P3 derived course 按各自 flags 工作。
- 不把 official due 状态复制回 Turna SRS。
- 若 backend/contract 升级导致 Collection 不可打开，使用升级前官方 backup，不能覆盖仍打开文件。

## 17. 建议提交切分

1. `docs(anki): freeze p3 remediation and p4 scheduler entry plan`
2. `fix(anki): enforce one active projection writer per source`
3. `fix(anki): terminalize projection failures and scope cancellation by job`
4. `feat(anki): add atomic official projection manifest`
5. `feat(anki): wire production mapping and course generation flow`
6. `fix(anki): initialize official course entry on cold start`
7. `fix(anki): complete canonical course interaction after reviewer return`
8. `fix(anki): canonicalize mapping version and schema review state`
9. `fix(anki): split bounded lessons and shuffle derived options`
10. `test(anki): close p3 production and capacity blind spots`
11. `docs(anki): publish p3 remediation result and entry decision`
12. `feat(anki): publish scheduler contract 1.3 operations`
13. `fix(anki): make scheduler tokens epoch-bound and single-use`
14. `feat(anki): add official redo bury suspend counts and congrats`
15. `feat(anki): expose typed scheduler APIs through worker isolate`
16. `feat(anki): implement official review session state machine`
17. `feat(anki): build official scheduler review and action UI`
18. `test(anki): add scheduler differential and lifecycle suites`
19. `test(anki): record scheduler device release and performance evidence`
20. `docs(anki): publish phase 4 result and decision`

不得把非 Anki analyzer 债务、依赖镜像漂移或其他用户修改混进这些提交。

## 18. 工期建议

| 工作包 | 预计工程日 | 前置 |
|---|---:|---|
| P3R production wiring/cold start/canonical | 3～5 | P3R-000 |
| P3R job/manifest/reconciliation | 3～5 | P3R-000 |
| P3R mapping/payload/tests | 2～4 | P3R-000 |
| P3R devices/performance/release | 2～4 | 前述 P3R |
| P4 contract/native | 4～7 | P3R Host stable |
| P4 Dart/session/UI | 5～8 | P4 contract |
| P4 actions/durability/differential | 4～7 | P4 native/session |
| P4 devices/release/CI/report | 3～5 | P4 feature complete |

合计约 **26～45 工程日**。不含 License、上游 pin 升级、AnkiWeb Sync、Phase 5 Legacy 清理及等待实体
设备/CI 的排队时间。若 differential tests 暴露 pinned rslib 行为差异，应增加工期，不降低门禁。

## 19. 最终完成定义

P3R 完成：用户可以从 production source 页面确认 mapping、生成并使用课程；课程入口冷启动稳定；job、
容量、mapping、canonicalLink 和发布可见性无已知阻断；Device A/第二设备/release/CI 有证据。

P4 完成：用户从明确的 Official Review route 获取官方队列，使用官方渲染正反面，提交
Again/Hard/Good/Easy，执行 Undo/Redo/Bury/Suspend，并在重启、跨日、filtered deck 和 daily limit 下与
pinned rslib 一致；整个路径不写 Turna SRS，也不让 preview/derived course 写官方 Scheduler。

在全部硬门禁通过前，唯一允许的结论是：

```text
P3 REMEDIATION CONSTRUCTION GO
P3 TECHNICAL ACCEPTANCE NO-GO
P4 HOST PREPARATION ALLOWED
P4 PRODUCTION ENTRY NO-GO
P4 PRODUCTION NO-GO
```
