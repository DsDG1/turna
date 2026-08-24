# 34 — Official Anki 生产收口与 OHOS 退役计划

> 文档代号：ANKI-CUTOVER-OHOS-EOL
>
> 日期：2026-08-24
>
> 状态：**施工计划；OHOS 退役决策已定，代码施工尚未开始**
>
> 前置：[`31`](./31-anki-product-experience-plan.md)、[`32`](./32-official-anki-experience-parity-plan.md)、[`33`](./33-official-first-import-construction-plan.md)、[ADR 0037](../decisions/0037-anki-course-review-unification.md)
>
> 目标：停止产品级 OHOS 支持；Android Anki 全量切换到 Official Collection / Scheduler；清除 Legacy 与 Official 混合 owner；在完成用户数据迁移和一个正式版本观察后退役自研 Anki importer / scheduler。

---

## 0. 已定决策与范围

### 0.1 已定决策

1. **停止产品级 OHOS 支持。** 不再为 OHOS 构建、发布、适配、修复或新增功能。
2. **不建设 OHOS Official Anki Core。** 原计划中“OHOS 继续 Legacy”的路线作废。
3. **Android 是 Official Anki 唯一生产首发平台。** Android 新导入最终只能由 Official Collection 持有，正式复习只能写 Official Scheduler。
4. **剩余非 Android 平台不得成为 Legacy Anki 的保留理由。** 在没有 Official Core 的平台上，Anki 导入/正式复习应明确不可用或只读导出，不得继续创建新的 Legacy Anki 数据。
5. **不做 AnkiWeb。** 本计划只处理本地 Official Collection、课程投影、复习和本地/远程备份。
6. **不以 feature flag 推断历史 owner。** 每个来源的 owner 必须持久化，修复和迁移必须经过 census/reconciliation。
7. **不立即物理删除 Legacy。** 先停止新写入，再迁移已有数据，观察至少一个正式版本，最后分波删除。

### 0.2 “去掉 OHOS 支持”的具体含义

本计划按产品级 EOL 处理，而不只是删一个 Anki 平台分支：

- 删除仓库中的 `ohos/` 工程与 ArkTS 插件；
- 停止使用 OpenHarmony Flutter fork；
- 删除 OHOS 专用依赖覆盖、构建补丁和构建文档；
- 删除 HarmonyOS RDB、文件选择器、通知和 TTS 平台分支；
- 从活跃产品文档、能力矩阵、测试和发布流程中移除 OHOS；
- 为可能存在的 OHOS 用户提供最后的数据出口，或者用可审计证据证明无需发布 sunset 版本；
- 历史 CHANGELOG 和归档证据保留，不重写历史。

### 0.3 非目标

- 不同时下线 iOS、Web、Windows、macOS 或 Linux 整个应用；
- 不承诺本阶段为非 Android 平台建设 Official Anki；
- 不重写官方 Anki scheduler、模板引擎或 `.apkg` parser；
- 不把课程答题和正式 Anki 调度强行合并为一次提交；
- 不在迁移中静默重置用户复习进度；
- 不在没有备份和 reconciliation journal 的情况下批量改 owner。

---

## 1. 现状审计

### 1.1 已经存在、应复用的能力

- Official native engine、Collection session、导入 saga 和来源 catalog；
- Official scheduler queue、answer/confirm、Undo/Redo、Bury/Suspend；
- Official 课程 projection、mapping preview 和 presentation 分类；
- `CanonicalCardKey`、placement/presentation/introduction 和 ledger owner 模型；
- 共享 `StudySessionController`、`OfficialStudyLedger`、`TurnaStudyLedger`；
- Official 来源卸载 saga、`pending_cleanup` 和启动重试；
- Official Collection、catalog、projection 和媒体的本地/远程备份骨架。

这些能力不应重写。剩余工作的核心是把它们接到同一条生产路径，并删除互相矛盾的 Legacy fallback。

### 1.2 当前最高风险：默认导入会形成混合半状态

当前配置组合是：

- Android cutover 和 Official import/scheduler 默认开启；
- `officialFirstImport` 默认关闭；
- 文件选择后只有 `officialFirstImportEligible == true` 才走 Official-first；
- 其余情况仍由 Dart Legacy parser/assembler 写课程树和 NoteStore；
- `UnifiedAnkiImportOrchestrator` 又因 `officialCapable == true` 不写 Turna SRS，并把 identity backend 记为 Official；
- `legacyMirror` 默认关闭，因此 Official Collection 可能根本没有这副牌。

可能落出的状态是：

```text
Legacy anki_imports / NoteStore / course tree   有
Turna SRS                                      无
Official Collection                            无
Canonical owner                                official
正式复习                                       空、失败或错误路由
```

这是本计划的第一阻断，优先级高于 UI parity 和 Legacy 删除。

### 1.3 当前正式复习没有真正接入 Official queue

生产入口已统一进入 `AnkiReviewSessionRoute`，但共享页面仍使用：

- `AnkiReviewAssembler`；
- `SrsProvider`；
- `AnkiNoteDao`；
- 仅包含 `TurnaStudyLedger` 的 `StudyLedgerResolver`。

`AnkiOfficialReviewGate` 虽会打开 Official Collection，却在生产环境继续停留在上述 Legacy batch 页面。项目已有 `OfficialReviewSession`、`OfficialAnkiReviewLedger` 和 `OfficialStudyLedger`，但没有生产组装器把 Official queue 转成 `StudyItem`。

### 1.4 课程学习语义仍是隐式失败回退

课程内 Anki 卡当前以 `StudyMode.learn` 尝试写 ledger。Official 卡没有注入 Official ledger 时进入 `recoverableError`，随后回退普通课程提交；课程进度会继续，但 Official scheduler 不变。

第一阶段应明确把课程学习定义为 `practice + introduction`，而不是用一次可预期的错误来表达“不写 scheduler”。

### 1.5 首页 due、浏览器和统计仍有双事实源问题

- Official formal due 当前用 `min(schedulerDueCount, introducedCount)` 近似，不是 card-id 级集合交集；
- 首页 due 使用静态全局状态，无法可靠表达 loading/unavailable/stale；
- 卡片浏览器只读 Legacy `AnkiNoteDao`；
- 牌组统计只读 Turna `SrsProvider + ReviewHistoryDao`；
- 纯 Official-first 来源因此可能在浏览器和统计页显示为空。

### 1.6 OHOS 对仓库的实际耦合

当前不是只有一个 `ohos/` 目录：

| 耦合面 | 当前事实 | 退役动作 |
|---|---|---|
| 平台工程 | Git 跟踪 44 个 `ohos/` 文件，包含 AppScope、Ability、RDB/FilePicker 插件和测试 | 删除整个平台 target |
| Flutter SDK | 文档要求 OpenHarmony Flutter fork 3.35.8 | 改回官方 stable Flutter |
| 依赖 | `pubspec.yaml` 有 7 个 OHOS Git override，另有 `win32`/secure-storage 兼容 pin | 移除 override/pin，回到受支持的官方包 |
| 数据库 | `HarmonyOsRdbExecutor` + ArkTS `RdbPlugin` | 删除桥，统一 file-backed Drift/SQLite |
| 文件选择 | `OhosFilePicker` 同时承担 OHOS channel 和其他平台扩展名校验 | 先提取通用 picker，再删 OHOS channel |
| 通知 | 使用 fork 独有的 `OhosInitializationSettings`/`OhosNotificationDetails` | 切回官方 Android/iOS API |
| 构建 | `tool/apply_patches.sh` + 4 个 fork 补丁 | 删除补丁链和相关说明 |
| 文档/测试 | 多处仍以“OHOS 继续 Legacy”为约束 | 活跃文档改为 EOL；归档保留历史 |

### 1.7 文档状态已经与代码错位

迁移 README 声称 D5 已默认翻转，但 `31/32` 仍标记“未实施”，`33` 又记录部分 official-first 已完成。后续不得继续以 Phase 名称判断是否可发布，统一改用本计划的可执行门禁和验收项。

---

## 2. 目标架构与不可破坏的约束

### 2.1 目标数据流

```text
Android .apkg
    │
    ▼
Official import saga ──失败──> fail closed + 可重试；零 Turna 写入
    │
    ▼
Official Collection / Scheduler       唯一卡片与调度事实源
    │
    ├── catalog + source ownership
    ├── projection ──> course tree / placement / presentation
    ├── due card ids ──> formal eligibility intersection
    ├── review queue ──> shared StudySession host
    └── revlog/search ──> stats / browser

Course lesson
    └── practice + product effects + introduction
        └── 默认不写 Official scheduler
```

### 2.2 平台能力矩阵

| 平台 | 应用状态 | Anki 新导入 | Anki 正式复习 | Legacy 新写入 |
|---|---|---|---|---|
| Android | 主力支持 | Official-first | Official scheduler | 禁止 |
| iOS | 应用保留，Anki 暂不承诺 | 隐藏/明确不可用，直到 Official Core 可用 | 只读导出或不可用 | 禁止 |
| Web | 有限应用支持 | 不可用 | 不可用 | 禁止 |
| Windows/macOS/Linux 产品构建 | 维持现有产品策略 | 默认不可用；host FFI 测试不等于产品支持 | 默认不可用 | 禁止 |
| OHOS | EOL | 不构建 | 不构建 | 不存在 |

若以后为其他平台建设 Official Core，应作为独立计划加入；不得重新打开 Legacy 写入。

### 2.3 核心不变量

1. 同一卡片只有一个 `CanonicalCardKey`。
2. 同一来源只有一个持久化 owner。
3. Official owner 只能写 Official Collection/Scheduler。
4. Legacy owner 只允许出现在迁移读取、导出或隔离态，不允许创建新来源。
5. Official import 失败不回退 Legacy。
6. 已记录为 Official 的来源在 native library 缺失时 fail closed，不降级。
7. 一次用户答案最多产生一次 scheduler mutation。
8. product effects 通过幂等 `eventId` 写入，可撤销时必须有补偿。
9. formal due 必须是 card key 的集合交集，不能用计数近似。
10. owner 切换必须有备份、journal、校验和可恢复状态。

### 2.4 最终允许保留的 Legacy 内容

可以保留通用课程 UI、renderer、`StudyItem`、product effects 和 Canonical domain；必须退役的是自研 Anki 的：

- `.apkg/.colpkg` production parser；
- Legacy Anki NoteStore 作为活动事实源；
- Turna FSRS 对 Anki 卡的活动写路径；
- Legacy Anki review assembler；
- Legacy Anki browser/stats 数据读取路径；
- 仅为 OHOS 保留的导入、渲染和 scheduler 分支。

---

## 3. 总体波次与依赖

```text
W0 数据止血 / 单一执行模式
 ├──> W1 OHOS sunset 与数据出口 ──> W2 OHOS 工程/依赖删除 ──┐
 └──> W3 owner census + reconciler ──> W4 Official import ──> W5 Official review/due
                                                    ├───────> W6 课程语义
                                                    └───────> W7 浏览/统计/产品 parity

W2 + W3 + W4 + W5 + W6 + W7
 └──> W8 存量 Legacy 迁移 ──> 一个正式 release 观察 ──> W9 Legacy 物理删除
 └──> W10 文档与迁移项目收口
```

硬依赖：

- W0 完成前，不扩大 Official 生产流量；
- W2 不要求等待 W4/W5，可由平台线并行；
- W4 不得在 W3 没有 owner/reconciliation 保护时默认开启；
- W5 完成前，W4 只能内部/小流量试用，不能让用户导入后无正式复习；
- W8 完成并观察一个正式版本前，不进入 W9；
- OHOS 数据出口未完成或未书面豁免前，不发布“最后一个 OHOS 版本”之后的彻底 EOL。

---

## 4. W0 — 数据止血与原子执行模式

### 4.1 目标

立即消除“路由说 Official、实际写 Legacy、两边都没有完整账本”的组合。W0 不追求完成 Official UX，只保证任何新导入落入一个完整、可解释的状态。

### 4.2 任务

| ID | 任务 | 关键落点 |
|---|---|---|
| W0-01 | 新增 `AnkiProductMode`：`officialAndroid`、`ankiUnavailable`；Legacy 只保留迁移读取模式，不作为新导入产品模式 | capability matrix / production router |
| W0-02 | 新增一次计算的 `AnkiImportExecutionPlan`：`officialFirst`、`unsupported`、`failClosed`；过渡测试可保留显式 `legacyOnly`，生产不可选 | import facade / import screen |
| W0-03 | file pick、parse、preview、saga、projection、SRS、identity、summary 全部接收同一个 plan，不得各自读取 flags | `anki_import_screen.dart` 及 orchestrator |
| W0-04 | `UnifiedAnkiImportRequest.officialCapable` 改为实际 `owner/backend`，禁止用“能力”冒充“执行结果” | unified orchestrator |
| W0-05 | native `.so` 缺失、ABI 错误或 ABI contract 不匹配时 fail closed；删除“新来源降级 Legacy” | native availability / import facade |
| W0-06 | 现有 Official owner 即使 build flag 关闭也保持 Official；能力缺失只显示修复错误，不改 owner | source router |
| W0-07 | 增加组合矩阵测试，覆盖所有 flag/platform/native/extension 组合 | targeted tests |

### 4.3 临时发布策略

在 W4 + W5 形成纵向闭环前，只允许以下两种策略之一：

1. **内部构建启用 Official-first，正式构建暂停 Anki 新导入**；或
2. **若必须维持正式导入，完整回到显式 Legacy owner**，但仅作为短期止血版本，并设置停止日期。

推荐策略 1，因为策略 2 会继续增加待迁移存量。无论采用哪一种，都禁止当前混合模式。

### 4.4 验收

- 任意导入完成后，`actual writer == persisted owner == review route owner`；
- Official plan 的 `anki_imports`、Legacy NoteStore、Turna Anki SRS 新增量均为 0；
- Legacy 临时 plan 若保留，则 owner 必须为 Legacy 且 Turna SRS 完整存在；
- 缺 native library 的 Android release 测试返回 fail-closed，不创建任何来源；
- `.apkg`、`.colpkg`、sample、错误扩展名都得到明确且一致的 plan；
- 新增回归测试必须能在修复前复现当前半状态。

---

## 5. W1 — OHOS Sunset 与用户数据出口

### 5.1 为什么不能直接删目录

应用数据是 local-first，OHOS 的 `course.db` 又位于系统 RDB，不能直接复制 Android SQLite 文件。直接停止发布可能使课程进度、Legacy Anki、错题和设置永远留在设备中。

### 5.2 用户规模确认

在不上传个人学习内容的前提下，用以下任一证据判断是否需要 sunset release：

- 应用商店安装/活跃设备统计；
- 发布渠道下载记录；
- 已知测试设备和内部用户清单；
- 用户支持渠道记录。

只有在“没有外部 OHOS 用户”有书面证据时，才可豁免最后一版数据导出。没有证据等于不能豁免。

### 5.3 最后一版 OHOS 行为

若存在用户，发布一个只做退场的最终版本：

- 首页或设置展示 EOL 日期和停止支持说明；
- 禁止新建 Anki 导入，避免继续增加 Legacy 数据；
- 提供平台中立的完整导出包；
- 提供把导出包转移到 Android 的说明；
- 保留只读学习数据浏览和二次导出；
- 不承诺 Official Anki、远程调度同步或新功能。

### 5.4 平台中立迁移包

不能依赖复制 OHOS RDB 文件。定义逻辑导出格式，例如：

```text
turna-migration-v1.zip
  manifest.json
  profile.json
  settings.json
  course_progress.jsonl
  srs_states.jsonl
  review_history.jsonl
  mistakes.jsonl
  anki_sources.jsonl
  anki_notes.jsonl
  anki_cards.jsonl
  introductions.jsonl
  media_manifest.json
  media/<sha256>
  SHA256SUMS
```

要求：

- 每个表/对象带 schema version；
- 密钥和 API key 不导出；
- 媒体内容寻址并校验 SHA-256；
- Android 只导入到 staging，校验通过后再事务应用；
- Legacy Anki 数据导入 Android 后先进入 `legacyPendingMigration`，不能直接成为活动 scheduler；
- 导出可重复、可中断重试、不能改变源设备数据。

### 5.5 验收

- 真实 OHOS 设备完成导出；
- Android staging 能校验、预览和应用非 Anki 数据；
- Legacy Anki 来源进入待迁移态，未发生双写；
- 损坏包、缺媒体、版本过新、磁盘不足都有明确失败且不产生半恢复；
- EOL 文案和支持页面给出最后支持版本、日期和数据迁移路径。

---

## 6. W2 — 删除 OHOS 工程、依赖和运行时分支

W2 分三个独立、可回滚的 PR，避免“删除 dependency override 后代码引用 fork-only API，整个项目无法编译”。

### 6.1 W2-A：先解除共享 Dart 代码耦合

| ID | 动作 | 说明 |
|---|---|---|
| W2A-01 | 把 `OhosFilePicker` 中通用的扩展名校验提取为 `ValidatedFilePicker` 或等价通用服务 | 保留 Android/iOS 文件选择体验 |
| W2A-02 | 所有调用点改用通用 picker；删除 scan/manual-path 等 OHOS-only UI | Anki、教材导入、备份、内部页 |
| W2A-03 | `locator.dart` 删除 `HarmonyOsRdbExecutor` 分支，非 Web 统一 `NativeDatabase.createInBackground` | 保留现有 restore 顺序 |
| W2A-04 | 删除 `rdb_query_executor.dart` 及对应 import/测试 | 不保留死桥 |
| W2A-05 | 通知服务删除所有 `Ohos*` 类型，只保留官方 Android/Darwin 配置 | 必须和依赖切换联测 |
| W2A-06 | 删除 app fonts、TTS、splash、backup/settings 中 OHOS 特判 | 保留 Web/iOS/desktop 的真实分支 |
| W2A-07 | capability matrix 不再返回 `ohos -> legacy`；未知平台一律 `ankiUnavailable` | 禁止默认 fallback |

### 6.2 W2-B：切回官方 Flutter 与官方插件

| ID | 动作 |
|---|---|
| W2B-01 | 删除 `pubspec.yaml` 中 7 个 OHOS Git dependency override |
| W2B-02 | 删除只为 OHOS kernel 保留的 `win32`、`flutter_secure_storage_windows` pin；让解析器选择当前受支持版本 |
| W2B-03 | 运行官方 stable Flutter 的 `flutter pub get`，审计 `pubspec.lock` source 和版本变化 |
| W2B-04 | 对 shared_preferences、path_provider、url_launcher、package_info_plus、share_plus、file_picker、notifications 做 Android smoke/regression |
| W2B-05 | 删除 `tool/apply_patches.sh` 和 `tool/patches/` 中 4 个 OHOS fork 补丁 |
| W2B-06 | CI 固定官方 stable 或明确版本；不再接受 OHOS fork 生成的 golden 作为唯一基线 |

### 6.3 W2-C：删除平台 target 和活跃文档

| ID | 动作 |
|---|---|
| W2C-01 | 删除 Git 跟踪的整个 `ohos/` target，包括 AppScope、entry、ArkTS 插件、资源和 ohosTest |
| W2C-02 | 清理 `.gitignore` 中仅针对 DevEco/OHOS 的规则 |
| W2C-03 | README、CLAUDE、project guide 改为官方 Flutter/Android 构建说明 |
| W2C-04 | 重写 `docs/android-build-setup.md`，删除 fork SDK 和外部 pub cache 打补丁流程 |
| W2C-05 | 活跃 Anki 文档把“OHOS 继续 Legacy”改为“OHOS EOL”；历史 archive 保留并标注已被本计划取代 |
| W2C-06 | 删除 `p5d_ohos_import_stays_legacy` 等测试，替换为“unsupported platform never chooses Legacy writer” |

### 6.4 W2 验收门禁

```bash
test ! -d ohos
test ! -f tool/apply_patches.sh
test ! -d tool/patches
rg -n "openharmony|HarmonyOsRdbExecutor|OhosInitializationSettings|OhosNotification" \
  lib pubspec.yaml tool .github README.md CLAUDE.md docs/project-guide.md docs/android-build-setup.md
# 期望：活跃路径 0 命中；archive/CHANGELOG 可保留历史命中

flutter pub get
flutter analyze
flutter test --exclude-tags golden
flutter build apk --release
```

另需完成 Android 真机验证：首次启动、数据库 seed、文件选择、通知权限、备份/恢复、分享、URL 跳转和 Anki 文件导入。

---

## 7. W3 — 来源 Census、Reconciler 与数据状态机

### 7.1 目标

在默认启用 Official-first 前，先识别过去版本可能制造的所有半状态。Reconciler 只根据持久化证据决策，不根据当前 build flag 猜测。

### 7.2 标准状态

| 状态 | 判据摘要 | 自动动作 |
|---|---|---|
| `cleanOfficial` | catalog active、Collection 有卡、owner Official、projection/identity 完整、无 Turna SRS | 正常使用 |
| `cleanLegacy` | Legacy import/notes/SRS 完整、owner Legacy、无 Official active source | 排队迁移；停止新增 |
| `mirroredConsistent` | 两侧都有卡且 cardinality/identity 可核对 | 冻结写入，选择 owner 后清另一侧 |
| `ownerOfficialCollectionMissing` | owner Official，但 Collection/源缺失 | fail closed；从备份或原包修复 |
| `ownerOfficialProjectionMissing` | Collection 完整，projection/placement 缺失 | 从 Official Collection 重建 |
| `ownerLegacySrsMissing` | Legacy 课程/NoteStore 有，SRS 缺失 | 隔离；不得假装已迁移 |
| `ownerMismatch` | migration link、catalog、unification backend 不一致 | 隔离并生成 repair plan |
| `pendingCleanup` | Official 删除未完成 | 启动重试；不重新展示来源 |
| `legacyPendingMigration` | 来自旧 Android/OHOS 逻辑导入包 | 只读/导出，等待 W8 |
| `unknownQuarantined` | 证据不足或 cardinality 冲突 | 不自动改写，允许诊断导出 |

### 7.3 Reconciliation journal

每次修复至少记录：

- operation id；
- profile/source/import id；
- before state 和 evidence hash；
- intended owner；
- backup id；
- 当前 step；
- 已完成 mutations；
- last error；
- retry/rollback policy；
- 完成后的 cardinality 和 source fingerprint。

### 7.4 扫描与修复顺序

1. 只读扫描所有 `anki_imports`、migration links、official sources、projection manifests、unification rows 和 SRS 前缀；
2. 建立 source 候选映射，禁止仅靠 display name 合并；
3. 用 source hash、card/note IDs、cardinality 和 profile id 核对；
4. 输出 census，不写数据；
5. 对可自动修复的 projection/identity 缺失生成 plan；
6. 备份；
7. 单来源执行并落 journal；
8. 重启后恢复/重试；
9. 完成后重新扫描确认进入标准状态。

### 7.5 验收

- 构造上述每种状态的 fixture，启动扫描不会崩溃；
- 只读 census 绝不改变数据库或 Collection hash；
- projection 重建不改 scheduler/revlog；
- owner mismatch 不自动选择“看起来更多”的一侧；
- 强杀发生在任一步都能在下次启动继续或明确停在隔离态；
- census 结果可导出但不包含卡片正文和用户隐私，除非用户主动选择完整诊断包。

---

## 8. W4 — Official-first 导入纵向闭环

### 8.1 产品路径

```text
选择文件
  -> 验证 extension / readable / free space
  -> require Official importer + ABI contract
  -> Official import saga（pending）
  -> Collection 核验/cardinality/source hash
  -> schema/mapping preview
  -> projection + vocabulary/media index
  -> placement/presentation 发布
  -> source active + owner Official
  -> summary
  -> 课程或正式复习入口
```

### 8.2 任务

| ID | 任务 |
|---|---|
| W4-01 | Android Official-first 改为唯一生产导入 plan，去掉 opt-in 与独立 mirror 语义 |
| W4-02 | 把 saga/orchestration 从 3900+ 行 import screen 移到 application service；UI 只消费状态和命令 |
| W4-03 | Official plan 禁止调用 Dart `AnkiImporter.parse`、Legacy assembler、Legacy NoteStore 和 SRS migrator |
| W4-04 | summary、course scope、source management 使用 official `sourceId`，不伪造 Legacy `importId` |
| W4-05 | reimport/update 明确 `replace`、`append as new`、`no-op`；同 hash 不重复导入 |
| W4-06 | 取消/强杀/磁盘满/Collection locked 时保留可恢复 saga，不留下 active 半源 |
| W4-07 | mapping 未确认、notetype 不支持、projection 低置信时允许延后投影，但不能把 Collection 导入判成失败 |
| W4-08 | `.colpkg` 给出明确产品策略：在 Official backend 支持前显示“不支持”，不得静默走 Legacy |
| W4-09 | sample 使用真实小型 `.apkg` fixture；内存 sample 不能作为发布证据 |

### 8.3 Import 完成态不变量

一次成功 Official 导入必须同时满足：

- Official source state 为 `active`；
- Official Collection card/note 数与导入结果一致；
- projection manifest 可读取；
- 每张活动卡恰有一个 active placement 和 presentation；
- owner 为 Official；
- Legacy `anki_imports`、Anki NoteStore、Turna Anki SRS 无新增；
- 完成页显示真实来源、牌组、卡片数量和后续入口；
- 重启后仍能从 catalog 找到来源，不依赖内存 map。

### 8.4 测试矩阵

- basic、cloze、多个 notetype、多个 deck、subdeck；
- `collection.anki2`、`collection.anki21`、`collection.anki21b`；
- 大媒体包、Unicode/空格/特殊文件名；
- 重复导入、replace、append、取消、强杀、磁盘不足；
- mapping 缺失、低置信、不支持模板；
- 完成后立即进入课程、正式复习、来源管理和卸载；
- package 已写 Collection 但 projection 失败后的恢复；
- app upgrade 和 restore 后重新 reconciliation。

---

## 9. W5 — Official 正式复习与精确 Due

### 9.1 短期安全桥

若 W4 先于共享 host 完成，Official owner 暂时导航到现有 `OfficialAnkiReviewPage`。这只是可用性桥，不能作为统一完成态。禁止让 Official 来源停留在只会组装 Legacy batch 的页面。

### 9.2 最终共享 Host

| ID | 任务 |
|---|---|
| W5-01 | 新增 `OfficialStudyBatchAssembler`：Official queue + projection/presentation -> `StudyItem` |
| W5-02 | 每次共享 session 持有一个 live `OfficialReviewSession`，注入 `OfficialStudyLedger(OfficialAnkiReviewLedger(session))` |
| W5-03 | queue current card、页面 current item 和 commit expectedCardId 必须一致；stale context 进入恢复态 |
| W5-04 | 把 Undo/Redo、Bury/Suspend、filtered deck、congrats、queue refresh 迁到共享 host |
| W5-05 | Fidelity WebView 的 question/answer ACK 完成后才允许 scheduler mutation |
| W5-06 | Again/Good 或四档 UI 只影响 presentation，不改变 Official rating 合法性和唯一 writer |
| W5-07 | 移除生产入口对 `OfficialAnkiHomeDue.officialImportIds` 静态快照的 owner 推断，改查 source repository |

### 9.3 Formal due 精确集合

目标公式：

```text
formalDueCardKeys =
  officialSchedulerDueCardKeys
  ∩ activePlacementCardKeys
  ∩ introducedCardKeys
  - suspendedCardKeys
  - buriedCardKeys
  - retiredCardKeys
```

要求 Official backend 或 adapter 返回 due card IDs，而不只是 deck count。首页、牌组页和复习 assembler 使用同一 eligibility repository。

### 9.4 验收

- 首页显示 N，进入复习实际可答卡也是同一组 N；
- 回答 Again/Good 后 remaining/due 立即更新，重启后保持；
- 未在课程介绍的新卡不会提前进入 formal queue；
- imported revlog/reps 的旧卡按既定 introduction 规则进入；
- suspended/buried/retired 不被计数也不被组装；
- Undo 恢复 scheduler、due 和 product effects；
- Collection locked、stale context、commit unknown 均不重复 answer；
- “全部牌组”和单牌组 scope 都不会跨来源混卡。

---

## 10. W6 — 课程学习语义与 Introduction

### 10.1 第一阶段：课程是 Practice

课程内 Official 卡统一创建为：

```text
mode = StudyMode.practice
ledgerOwner = StudyLedgerOwner.none
writesLedger = false
marksIntroduced = true（由成功提交后的显式动作完成）
```

任务：

- 删除“以 `StudyMode.learn` 提交 Official ledger，失败后 fallback”的控制流；
- 只有题面成功展示并完成一次有效提交才写 introduction；
- `ShowWord` 仅展示时不自动打 scheduler grade；
- objective 题错可记 mistake，flip/fidelity 自评不自动视为错题；
- 同一卡同一课 introduction exactly-once；
- 中途退出保留已经提交的 introduction，未提交卡不变；
- 课程 undo 若允许，必须同时补偿 product effect 和 introduction，或明确 introduction 不可撤销并写产品规格。

### 10.2 第二阶段：可选的 Course Grade Bridge

默认继续关闭。只有满足以下条件才可另行启用：

- backend 有“安全回答指定 card”的正式 API，或能创建合法 queue context；
- 不依赖测试 `onAnswer` seam；
- 一个课程结果恰好映射一个 Official mutation；
- 错误/全对到 Again/Good 的映射经过产品确认；
- 不到期卡、已 suspended 卡和 filtered deck 卡有定义；
- 与 formal review 并发时有 single-flight/coordinator；
- Undo 和 commit-unknown 可恢复。

### 10.3 验收

- 完成课程不会偷偷改变 Official due；
- introduction 写入后，满足 scheduler due 的卡才进入正式复习；
- 课程重复进入不会重复奖励、错题或 introduction；
- Official 卡永不进入 Turna SRS；
- 内置课程和非 Anki 课程行为无回归。

---

## 11. W7 — Renderer、媒体、浏览器、统计和产品层 Parity

### 11.1 Presentation/Renderer

- projection 产出的 presentation 是课程和正式复习的唯一分类结果；
- basic/high-confidence 卡复用语言课 Flutter renderer；
- complex/fidelity 卡使用 Official template WebView；
- runtime 不重新分类，projection algorithm 升级通过显式 rebuild；
- `{{type:}}`、Cloze、RTL、MathJax、CSS、音频、视频均有明确兼容策略；
- presentation ACK 失败时不得提交 scheduler。

### 11.2 媒体

- Official media resolver 是 Official 来源唯一媒体入口；
- 覆盖图片、音频、TTS fallback、Unicode/IRI、Range、视频和缺文件；
- import/reimport/uninstall/restore 后 media index 一致；
- 清理只删除确认无引用的对象，不能用字符串前缀猜 owner。

### 11.3 卡片浏览器

新增 source-aware repository：

- Official 搜索/分页/详情从 Official Collection 读取；
- flag/suspend/bury 写 Official engine；
- Legacy 只读态从迁移仓库读取，不允许活动修改；
- 纯 Official-first 来源不依赖 `AnkiNoteDao`。

### 11.4 统计

- Official 统计从 scheduler/revlog 读取；
- due forecast、new/learning/review、interval、maturity 与 Official 语义一致；
- 不用 Turna FSRS 公式推算 Official 卡的“官方保持率”；若无法准确计算，UI 明确展示可证明指标；
- global dashboard 通过 source-aware aggregate 合并数字，不合并 writer。

### 11.5 产品 Effects

建立 scheduler-neutral 的 effect coordinator：

- analytics、gems、mistakes、AI explanation 只消费 `StudyEventReceipt`；
- `eventId/idempotencyKey` 防重复；
- undo 有补偿；
- self-rated fidelity card 不自动写 mistake；
- quota 只保留一套产品策略，不能同时受 Turna daily limit 和 Official deck limit 双重截断。

### 11.6 验收

- Basic/Cloze/复杂模板在课程和正式复习中使用同一 presentation；
- browser 能看到纯 Official 来源全部卡片并正确 suspend；
- stats 在答题后更新，重启后不归零；
- 所有 product effects 在重试和 Undo 场景 exactly-once；
- 大牌组滚动、搜索和 queue 组装满足性能预算，且没有把整副牌常驻内存。

---

## 12. W8 — Android 存量 Legacy 数据迁移

### 12.1 迁移原则

- 一次只迁一个 source；
- 迁移前必须有可恢复备份；
- 先建立 Official 副本并验证，再切 owner；
- owner 切换之前 Legacy 仍是唯一活动 writer；
- owner 切换之后禁止再写 Legacy；
- 不能精确迁移的调度数据必须显式告知用户，不能伪造 parity。

### 12.2 来源重建优先级

1. **原始 `.apkg` 仍可读取：** 用 Official importer 重新导入，source hash/card identity 核对；
2. **已有 Official mirror 且一致：** 核对 Collection/cardinality/revlog 后认领 Official；
3. **只有 Legacy NoteStore：** 使用隔离的 migration exporter 生成中间包，再交给 Official importer；该工具不得成为生产 `.apkg` parser；
4. **证据不足或正文缺失：** 保持只读隔离，允许导出，要求用户重新提供原包；不得自动丢弃。

### 12.3 调度进度迁移

Legacy Turna FSRS 与 Official Anki scheduler 不是同一状态机。必须先验证 Official native backend 是否提供受支持的批量迁移接口：

- card state/due/interval/ease/stability/difficulty 映射；
- revlog 写入或正式迁移 API；
- new/learning/relearning/review queue 状态；
- suspended/buried/leech；
- timezone/day-boundary。

若无法无损映射，默认不得静默切换。产品必须在以下策略中书面选择并提示用户：

- 保留原始包内 Anki 进度，忽略之后的 Turna-only 复习；
- 将卡重置为 New；
- 保留 Legacy 只读并要求用户重新导入最新版包。

推荐优先实现正式 migration API；“回放历史答案”不能作为默认方案，因为会改变排程上下文和时间语义。

### 12.4 单来源 Saga

```text
census cleanLegacy
  -> snapshot/backup
  -> create official pending source
  -> import/reconstruct cards
  -> migrate/choose scheduling policy
  -> build projection + identity
  -> compare cardinality/fingerprint/sample rendering
  -> freeze legacy writer
  -> atomically switch persisted owner
  -> smoke official due/review
  -> mark legacy shadow cleanup-after-release
```

### 12.5 验收

- migration 可在任一步强杀后继续；
- owner switch 是单一提交点；
- 切换前后卡片正文、媒体和 presentation 可抽样比对；
- due/revlog 差异在允许阈值内或有用户确认；
- 切换后所有正式答案只进入 Official scheduler；
- rollback 在 owner switch 前完整可用；switch 后回滚只恢复 UI/代码，不允许重新双写；
- 每个未迁移来源有原因码，不用一个全局“迁移失败”。

---

## 13. W9 — Legacy Anki 分波物理删除

进入条件：

- OHOS target 已删除；
- 所有生产平台禁止 Legacy 新写入；
- Android Official import/review/browser/stats/backup 已全量；
- census 中没有未知活动 Legacy writer；
- 已有存量迁移/导出路径；
- Official 版本稳定运行至少一个正式 release 周期；
- rollback drill、restore drill 和 uninstall drill 通过。

### 13.1 删除波次

| 波次 | 删除内容 | 保留内容 |
|---|---|---|
| W9-A | Legacy 新写入口、feature flags、platform fallback、background mirror | 只读 census/export/migration adapter |
| W9-B | Turna FSRS 对 Anki 的 writer、Legacy formal review assembler 和 quota writer | 通用 SRS、非 Anki review |
| W9-C | Dart production `.apkg/.colpkg` parser、Legacy import screen 分支、NoteStore 活动 repository | migration-only exporter，直到迁移窗口结束 |
| W9-D | Legacy browser/stats/source management 分支和死 DI registration | source-aware Official repository |
| W9-E | Schema tombstone：旧表先只读，再停止写，最后在新 major schema 中删除 | migration receipt、必要审计摘要 |

### 13.2 删除规则

- 每波先用 `rg` 和依赖图证明生产引用为 0；
- 每波独立 PR、独立回滚；
- 禁止因为类名含 `Anki` 就删除共享 presentation/domain；
- schema 不与 writer 删除同一 PR；
- 先停止写至少一个版本，再 drop 表；
- drop 前备份恢复必须能读取上一版本数据并完成升级；
- 历史 archive/test artifact 不因代码删除而抹除。

### 13.3 Forbidden-import/forbidden-write 门禁

CI 至少包含：

- `lib/application/anki_official/**` 不依赖 Legacy importer/scheduler/view；
- production route 不实例化 `AnkiImporter`；
- Official owner 不调用 `SrsProvider.ensureWord/updateReview`；
- new import 不写 Legacy `anki_imports`/NoteStore；
- unsupported platform 不返回 Legacy execution plan；
- 删除完成后活动代码中不存在 OHOS platform case。

---

## 14. W10 — 发布、灰度和文档收口

### 14.1 灰度门禁

| Gate | 流量/范围 | 必须证明 |
|---|---|---|
| G0 | Host/CI | 原子 plan、census、failure injection 全绿 |
| G1 | 内部 Android | 真实包导入→课程→due→复习→重启→卸载闭环 |
| G2 | 小规模 pilot | 多来源、多模板、大媒体；无 owner mismatch |
| G3 | 分阶段默认开启 | crash/失败率、pending saga、queue commit unknown 可接受 |
| G4 | Android 100% Official | Legacy 新写入计数恒为 0 |
| G5 | 一个正式版本观察后 | 允许进入 W9 物理删除 |

每一档归档：build id、Git commit、native backend commit/ABI、fixture hash、设备/ABI、步骤日志、Collection/catalog hash、失败清单和 GO/NO-GO 签字。

### 14.2 Android ABI 决策

当前 native 构建重点是 `arm64-v8a`。发布前必须二选一：

1. **明确只支持 arm64-v8a：** Gradle/商店能力与文档一致，其他 ABI 不安装；
2. **增加所需 ABI：** 至少为 CI/模拟器补 `x86_64`，并分别验证 `.so`、ABI version 和 release packaging。

禁止 APK 声称支持某 ABI，却在运行时因缺 `libturna_anki.so` 静默回 Legacy。

### 14.3 活跃文档收口

- 将本文件加入迁移 README，作为当前唯一施工入口；
- `31/32/33` 标注由本文件接管的条目；
- 新增/更新 OHOS EOL ADR，记录产品级退役决策；
- README/project-guide/构建说明移除 OHOS 当前支持声明；
- 保留 archive 和 CHANGELOG 历史，不把过去的 OHOS 事实改写掉；
- 用可执行验收表代替“Phase 已完成”但主链路未接通的表述。

---

## 15. 测试与证据矩阵

### 15.1 Host/单元测试

- execution plan 全组合矩阵；
- owner resolver 和 reconciler 状态矩阵；
- import saga 状态机和 idempotency；
- card-id formal due 交集；
- Official ledger current-card/stale-context；
- course practice/introduction exactly-once；
- product effects commit/undo 幂等；
- migration journal resume/rollback；
- source-aware browser/stats repository contract。

### 15.2 Fixture 集

至少覆盖：

- Basic、Reverse、Cloze、typed answer；
- 多 notetype、多 deck/subdeck；
- Anki 2.1/新 schema/anki21b；
- CSS/JS/MathJax/RTL；
- 图片、音频、视频、Unicode 文件名；
- imported revlog、learning/relearning/suspended/buried；
- 超大牌组和重复 card/note 关系；
- 恶意/损坏 zip、路径穿越、超大解压、缺媒体；
- 现有半状态和 OHOS 逻辑迁移包。

### 15.3 Android 真机闭环

每个 release candidate 至少验证：

1. 冷启动直接进入导入；
2. 真实 `.apkg` 导入与 mapping；
3. 完成页进入课程；
4. 课程答题只写 introduction；
5. 首页 due 与实际 queue 一致；
6. Again/Good、Undo、Bury、Suspend；
7. 重启和跨日；
8. browser/search/stats；
9. reimport/replace；
10. 导入、复习、删除中途强杀；
11. 本地和远程 backup/restore；
12. uninstall + pending cleanup retry；
13. release APK 的 ABI/`.so`/ABI contract。

### 15.4 建议验证命令

```bash
flutter pub get
flutter pub run build_runner build --delete-conflicting-outputs
flutter analyze
flutter test --exclude-tags golden
flutter test test/application/anki_official
flutter test test/application/review
android/gradlew -p android :app:testDebugUnitTest
flutter build apk --release

cd native/turna_anki_core
bash build-android/verify_pin.sh
bash build-android/host-test.sh
```

结果必须写入新的 artifact/receipt；不得仅引用旧 P5C/P5D 截图证明当前代码可用。

---

## 16. PR/提交建议

每个 PR 保持单一目的并可独立回滚：

1. `test(anki): reproduce mixed-owner default import state`
2. `refactor(anki): introduce atomic product and import execution plan`
3. `fix(anki): fail closed on missing official native runtime`
4. `feat(ohos-eol): add logical export and sunset surface`（若未豁免）
5. `refactor(platform): extract generic validated file picker`
6. `refactor(platform): remove OHOS runtime branches and fork-only APIs`
7. `build(platform): remove OHOS target, overrides and patch toolchain`
8. `feat(anki): add source census and reconciliation journal`
9. `feat(anki): make official-first import the Android production path`
10. `feat(anki): assemble official queue in shared study host`
11. `fix(anki): compute formal due by canonical card-key intersection`
12. `refactor(anki): make course learning explicit practice introduction`
13. `feat(anki): switch browser and stats to source-aware repositories`
14. `feat(anki): migrate legacy sources with resumable owner switch`
15. `chore(anki): disable all legacy production writes`
16. `chore(anki): remove legacy importer/scheduler in staged waves`
17. `docs(anki): close cutover and OHOS retirement`

生成文件、lockfile 和 golden 更新应跟随引发变化的 PR，不单独掩盖行为变更。

---

## 17. 风险清单与缓解

| 风险 | 后果 | 缓解 |
|---|---|---|
| 直接下线 OHOS 导致本地数据无法迁出 | 用户永久失去学习记录 | sunset export；无用户时书面豁免 |
| 移除 OHOS Git overrides 改变 Android 插件行为 | 启动、通知、文件选择、prefs 回归 | W2-A/W2-B 分离；官方包逐项 smoke |
| 当前混合 owner 已进入用户库 | 课程可见但无法复习，删除不完整 | W0 止血 + W3 census/reconciler |
| Official queue 与共享页面卡序不一致 | 回答错卡或 stale context | session-scoped assembler；expectedCardId；single-flight |
| Legacy FSRS 无法无损映射 Official scheduler | due/间隔变化 | native migration API；无法保证时用户确认，不静默切换 |
| due 继续按 count 近似 | 首页数字和实际复习不一致 | backend 提供 card IDs，统一 eligibility repository |
| 删除 note 影响同 note 的跨 deck cards | Official Collection 数据损失 | 删除前验证 source-note 独占/引用关系；事务和备份 |
| 只有 arm64 `.so` 但 APK 支持更多 ABI | 运行时缺库 | 明确 abiFilters 或补齐 ABI；绝不 fallback |
| 过早 drop Legacy schema | 老版本/恢复包无法升级 | stop-write → observe → tombstone → major schema drop |
| feature flags 继续自由组合 | 再次产生不可能状态 | 原子 product mode；CI 组合门禁；构建配置集中化 |

---

## 18. 粗略工作量与关键路径

以下仅用于排期，不是交付承诺；按一名熟悉当前代码的工程师估算：

| 工作流 | 相对规模 | 粗略人日 |
|---|---:|---:|
| W0 原子模式/止血 | M | 3–5 |
| W1 OHOS sunset/export | L | 5–10；无外部用户并获豁免时 1–2 |
| W2 OHOS 代码/构建删除 | M–L | 4–7 |
| W3 census/reconciler | L | 6–10 |
| W4 Official-first import | L | 6–10 |
| W5 shared review + exact due | XL | 8–14 |
| W6 course semantics | M | 3–5 |
| W7 parity surfaces | XL | 10–18 |
| W8 Legacy migration | XL | 8–15；若需 native schedule migration API 另加 8–15 |
| W9 Legacy staged deletion | L | 5–10，且受一个正式 release 观察期约束 |
| W10 release/docs/evidence | M | 3–5 |

不含等待观察期时，整体约 **53–94 人日**；若用户规模、存量数据和 scheduler migration API 明确后，应重新估算。关键路径是：

```text
W0 -> W3 -> W4 -> W5 -> W8 -> 正式版本观察 -> W9
```

W1/W2 可与 W3–W5 并行，但 W9 必须同时等 W2 和 W8 完成。

---

## 19. 最终 Definition of Done

只有以下全部成立，才能宣称“自研 Anki 已切到 Official，OHOS 已退役”：

- [ ] 仓库不再包含 OHOS product target、fork 依赖或构建补丁；
- [ ] 活跃文档不再宣称支持 OHOS；
- [ ] 现有 OHOS 用户完成数据出口，或有无外部用户的书面豁免；
- [ ] Android 新 `.apkg` 导入只写 Official Collection；
- [ ] 成功导入同时产生可用 projection、course entry 和持久化 Official owner；
- [ ] Official 导入失败不会写 Legacy 数据，也不会静默 fallback；
- [ ] 正式复习从 Official queue 组装，并由 OfficialStudyLedger 唯一提交；
- [ ] 首页 due 是 card-id 精确集合，数字与实际 queue 一致；
- [ ] 课程学习显式为 practice/introduction，默认不写 scheduler；
- [ ] browser、stats、media、product effects 对纯 Official 来源可用；
- [ ] backup/restore/reimport/uninstall/强杀恢复通过 release 真机验收；
- [ ] 所有历史来源已进入 cleanOfficial、已导出/只读隔离或有明确用户处理状态；
- [ ] Legacy 新写入连续一个正式版本为 0；
- [ ] Legacy importer/scheduler/schema 按 W9 分波删除；
- [ ] CI 有 owner、forbidden write、unsupported platform 和 native ABI 门禁；
- [ ] 迁移 README、ADR、构建说明和 release artifact 全部更新。

在上述条件未全部满足前，准确状态应写为“Official Anki 迁移中”，不能写“迁移完成”。
