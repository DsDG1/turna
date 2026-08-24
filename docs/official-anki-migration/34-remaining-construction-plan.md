# 34 验收返工与剩余施工计划

> 文档代号：ANKI-CUTOVER-REMEDIATION
> 日期：2026-08-24
> 状态：**验收 NO-GO；等待返工**
> 父计划：[34 Official 生产收口与 OHOS 退役](./34-official-anki-production-cutover-and-ohos-retirement-plan.md)
> 验收回执：[34-cutover-receipt.md](./34-cutover-receipt.md)
> W9 HOLD：[34-w9-legacy-deletion-hold.md](./34-w9-legacy-deletion-hold.md)
> OHOS 决策：[ADR 0041](../decisions/0041-ohos-product-eol.md)
>
> 本文件是 34 的唯一活跃返工入口，替代此前的“34 剩余施工计划”口径。准确状态始终是：**Official Anki 迁移中**。在本文最终门禁全部通过以前，不得写“迁移完成”“正式切流完成”或“OHOS 用户数据出口完成”。

---

## 1. 本轮验收结论

整体结论：**拒收，不允许发布，不允许开始 W9 Legacy 物理删除。**

可以分项保留的成果：

- Android 新 apkg 的 Official-first / fail-closed 路径已经建立；
- OHOS product target、桥接、picker 和补丁目录已经从主分支移除；
- arm64 release APK 可以完成构建并包含 libturna_anki.so；
- W9 物理删除 HOLD 文档有效，继续保持；
- 一组 Official import、due、review path、migration saga 和 OHOS guard 定向测试通过。

不能验收的产品闭环：

- Official Anki 课程被错误混入语言正课，多个 Official 来源会折叠成一个伪课程；
- 正式复习仍会把 Official HTML 降级成纯文本，并可能在 Scheduler 重排后 stale；
- “复习全部”只复习第一个 Official 来源；
- Formal Due 不是完整的六集合、缺失 placement 时还会放宽；
- W8 freeze 和 owner switch 不是生产级迁移；
- Browser / Stats 页面没有可靠产品入口和 sourceId 路由；
- OHOS 主工程虽已删除，但旧用户数据出口没有交付或豁免；
- 导入、projection、course entry 和 owner 可形成半完成状态；
- 全量测试新增 schema 9 的备份/恢复回归，工作树和 native 子模块不可复现。

### 1.1 验收基线

| 门禁 | 本轮结果 | 返工后的要求 |
|---|---:|---:|
| 定向 Official/OHOS 测试 | 27 通过 | 保持通过并增加本文场景 |
| Golden | 4 通过 | 保持通过 |
| 全量非 Golden | 1736 通过、5 失败 | 全绿；至少不得有新增失败 |
| 新增回归 | backup/restore schema 8 → 9 两项 | 必须修复 |
| flutter analyze | 无 error；133 warning/info，非零退出 | touched files 零问题；发布门禁最终零退出 |
| git diff --check | 失败 | 必须通过 |
| Android arm64 release | 通过，55.7 MB | 从干净、锁定的 native commit 重建 |
| Native submodule | dirty | 必须干净并记录 commit/hash |

本轮 APK SHA-256 仅作为验收快照，不是发布收据：

    4e0e2a1fa76a3fb8d1af8410f2eb87aaa59636a9e5e34803b9130f4b70f54d8e

---

## 2. 目标架构和不可破坏约束

### 2.1 所有权

1. Official Collection 是卡片、模板、媒体、队列和调度的唯一事实源。
2. CourseDatabase 只存可重建的课程投影、课程可见性和产品侧 placement。
3. 同一来源任意时刻只能有一个 scheduler writer。
4. Legacy 只能用于存量迁移、导出和明确的兼容读取；Android 新导入不得写 Legacy。
5. W9 前不删除 Legacy schema 和恢复能力。

### 2.2 课程层级

正确层级必须固定为：

    Course
    ├── 内置语言正课
    │   └── Section → Unit → Lesson
    └── 一个 Anki import/source
        └── Anki 顶层牌组作为 Section → 子牌组/分组作为 Unit → Lesson

不得再出现：

- Official Section 混入内置语言正课；
- 从 sectionId 猜一个截断的 sourceId；
- 多个 Official source 因共同的 src- 前缀合成一个课程；
- 当前 courseScope 在 courseEntries 中找不到；
- 用模糊前缀执行卸载。

### 2.3 正式复习

1. 页面当前卡必须由 Official Scheduler 的实时 current 决定。
2. 评分、Undo、Redo、Bury、Suspend 只写 Official engine。
3. Official HTML、CSS、媒体、MathJax、JS 和 typed answer 不得 strip 后冒充保真。
4. “复习全部”必须覆盖所有显示在计数中的来源；否则改成明确的“复习此牌组”。
5. count、卡序和实际可评分卡必须来自同一个 session/repository。

### 2.4 OHOS

1. 不恢复主分支的 ohos/ product target。
2. “停止支持 OHOS”和“旧用户已完成数据出口”是两个独立验收项。
3. 数据出口必须有真实可到达入口，或者有可审计的无外部用户豁免。

---

## 3. 施工依赖和优先级

    R0 口径与基线止血
     ├── R1 课程 scope / 导航 P0
     ├── R2 实时正式复习 P0
     ├── R3 精确 Due P0
     └── R4 W8 owner 迁移 P0
              │
              ├── R5 Browser / Stats / Media P1
              ├── R6 导入原子性与向导收口 P1
              └── R7 OHOS 数据出口 P1
                       │
                       └── R8 发布、真机和文档复验

R1、R2、R3 可并行施工，但合并前必须共同验证“课程选择 → due → review”端到端。R4 未完成前不得迁移真实 Legacy 来源。R8 未完成前不得发布。

---

## R0 — 验收口径与基线止血

目标：先阻止错误的完成勾选、不可复现构建和新增测试回归继续扩散。

### R0-1. 锁定施工快照

- 把主工程和 native/turna_anki_core/anki 分别收敛到可审计 commit。
- native 子模块禁止携带未提交 rslib 修改和无关目录。
- 记录 pubspec.lock、Flutter/Dart、Gradle、NDK、Rust、Anki upstream commit。
- release so 必须由记录的 native commit 构建，不接受来源不明的预编译文件。

### R0-2. 修复 schema 9 回归

- 备份 snapshot 和 restore applier 不得硬编码 catalog schema 8。
- 明确 migration package、backup manifest 和 Official catalog schema 的兼容矩阵。
- 旧 schema 8 备份升级到 9；未来 schema 必须 fail-closed 并给用户可理解错误。
- 更新 test/BASELINE.md，写入真实全量命令和真实失败数，不使用“estimate”。

### R0-3. 撤销错误完成口径

以下项目保持未完成，直到对应波次复验：

- OHOS 用户数据出口；
- 可用且独立的 Official course entry；
- 正式复习保真与实时队列；
- 六集合 exact due；
- Browser / Stats / Media 的 Official 产品闭环。

### R0 完成定义

- [ ] native submodule 和主工程都可由 commit 重建；
- [ ] schema 9 backup/restore 测试通过；
- [ ] test/BASELINE.md 与实际全量结果一致；
- [ ] 主计划、remaining、receipt 不再互相矛盾；
- [ ] git diff --check 通过。

---

## R1 — 修复 Anki 课程 scope、层级和课程选择

优先级：**P0 产品阻断**。这不是视觉小问题；当前 sourceId 截断还会破坏切换、排序和卸载。

### R1-1. 删除 sectionId 猜 sourceId 的主路径

当前 CourseProvider._importIdFromSectionId 使用 split('-').first。Official sourceId 是 src-加随机 ID，因此会被截成 src。

改法：

- 引入明确的 CourseScope 值对象：
  - builtin language；
  - legacyAnki(importId)；
  - officialAnki(sourceId)。
- Official course entry 从 official_anki_projection_manifest / catalog 的 source_id 和 display_name 生成。
- Section 只引用 course/source，不再承担反向解析的唯一事实源。
- 必须保留字符串兼容时，使用最后一个 -s 边界或 LegacyAnkiIdentifiers 的完整解析；不得 split first。
- courseEntries 的 key、courseOrder、courseScope、review target、uninstall target 使用同一个完整 sourceId。

### R1-2. 内置语言课严格排除所有 Anki Section

CourseProvider._applyScopeFilter 在 builtin scope 下必须：

- 排除 level=Anki；
- 排除 level=OfficialAnki；
- 或通过统一 isAnkiSection 判定排除两者。

OfficialAnkiCourseEntry.filterShells 只负责“该投影是否 active”，不得顺便把 Official Section 塞进 builtin scope。

### R1-3. 一个 source 一个课程

- 一个 Official source 对应一个 CourseEntry。
- source 内顶层 deck 才是多个 Sections。
- 两个 source 即使 display name 相同，也必须是两个可区分课程。
- scope 过滤用 exact source ownership helper，不使用可能覆盖其他来源的模糊前缀。
- CourseEntry 显示 source displayName；Section 显示 top deck name。

### R1-4. 修正导入后的导航语义

当前 import commit 在完成页出现前就 setCourseScope，新课程会在用户选择前抢占正课。

改为：

- import/publish 成功：刷新 course entries，但保持原 active course；
- “立即学习”：切到新 Official course 后回 Learn；
- “查看牌组”：进入课程管理并高亮新课程；
- “完成”：返回原课程；
- reimport 当前活动来源时只刷新，不重复切换或清空选择。

### R1-5. 恢复可发现的课程选择

- 顶栏显示当前课程名称，不只显示无文字的地球图标。
- 点击名称/切换按钮进入课程管理。
- 课程管理必须始终有且只有一个 active 项。
- 新导入课程出现后给短暂提示，不把用户自动传送进 Section。

### R1-6. 修复已有错误偏好

需要提供无损偏好修复：

- courseScope=anki:src 且仅有一个 Official source：迁移到完整 sourceId；
- 有多个 Official source：回到 builtin，并提示用户重新选择；不得任选第一个；
- courseOrder 中截断或失效的 anki:src 重建成完整来源列表；
- 不删除 Official Collection、投影或学习记录；
- 修复必须幂等。

### R1-7. 卸载必须精确

- CourseManagementPage 传完整 sourceId。
- AnkiDeckManager 不得把 src 当成一个 Official source。
- 删除前展示 display name、sourceId 短标识和卡片数。
- 删除一个 source 不得影响同样以 src- 开头的其他 source。

### R1 测试

- [ ] builtin scope 同时隐藏 Legacy 和 Official Sections；
- [ ] src-随机 ID 在 section、scope、entry、uninstall 中完整 round-trip；
- [ ] 两个 Official source 生成两个课程；
- [ ] 选 source A 只显示 A 的 Sections；
- [ ] import“完成”保持原课程；
- [ ] “立即学习”才切换；
- [ ] 重启后 active 和 courseOrder 保持；
- [ ] anki:src 旧偏好迁移在单源、多源情况下均正确；
- [ ] 卸载 A 后 B 完整保留。

### R1 完成定义

- 用户永远不会在语言正课中看到 Anki Section；
- 课程管理永远能表示当前 active scope；
- 多个 Official import 不折叠；
- 导入、切换和卸载均使用完整 sourceId。

---

## R2 — 正式复习改为保真、实时、跨来源

优先级：**P0 调度正确性阻断**。

### R2-1. 移除 HTML → stripHtml → Flip 的生产降级

OfficialFormalReviewProductionLoader 不得把 engine.renderCard 的结果统一 stripHtml 后创建普通 FlipCardPresentation。

改法：

- Basic/Cloze/复杂模板都保存 Official rendered question/answer；
- 复杂模板使用 FidelityCardPresentation / AnkiHtmlCard；
- 媒体 URL 走 Official media resolver；
- typed answer、MathJax、CSS、body class 和模板 JS 沿用 Official reviewer contract；
- 文本 fallback 只允许在明确 unsupported/recoverable error surface 中使用，并显示降级状态；
- reviewContentFor 必须能从真实 presentation 类型读取内容。

### R2-2. 用 Scheduler current 驱动页面

当前页面一次性预装 queue.cards，但 answer 后 OfficialReviewSession 会刷新队列，StudySessionController 仍按旧数组前进。

改为 live adapter：

1. session 打开后读取 current；
2. 为 current cardId 即时 render / resolve presentation；
3. answer 使用 current 的 scheduling context；
4. answer 完成后刷新 session；
5. 下一张再次读取 current，而不是固定 index 加一；
6. 学习卡重排、重新插入、跨日边界均由 Scheduler 决定。

StudySessionController 可以保留用于 Legacy/practice，但 Official formal 模式不得依赖固定 StudyItem 列表。

### R2-3. 修复“复习全部”

当前 AnkiReviewScreen 只取 firstDueOfficialSectionId；Play Hub/Profile 也只把“存在 Official 来源”当布尔 owner。

产品规则：

- “复习此牌组”：只打开选定 source/deck；
- “复习全部”：按 source 建立 session coordinator，依次消费所有来源；
- Legacy 与 Official 混合期必须按卡片/来源选择 ledger，不得按整个按钮选一个 owner；
- 计数中包含的来源必须都可被消费；
- 一个来源失败时显示来源级错误，并允许继续其他来源，不能静默丢卡。

### R2-4. 补齐复习动作

- Undo、Redo、Bury、Suspend 都接 Official engine；
- 动作后刷新 live current 和 Formal Due repository；
- filtered deck / unsupported action 显式不可用；
- action single-flight，防双击和页面销毁后回写。

### R2 测试

- [ ] Official HTML/CSS/媒体/MathJax 不被 strip；
- [ ] typed answer 正反面一致；
- [ ] answer 后 Scheduler 重排到非原数组下一张仍可继续；
- [ ] learning card 重新插入；
- [ ] scheduling context 永远与 current cardId 一致；
- [ ] 两个 Official source 的 Review All 都被消费；
- [ ] Legacy + Official 混合 Review All 分别写正确 ledger；
- [ ] Undo/Redo/Bury/Suspend 改变真实 queue 和 due；
- [ ] 退出、后台、进程恢复不重复评分。

### R2 完成定义

- 正式复习不再依赖固定预装队列；
- 保真卡使用 Official renderer；
- Review All 名称、计数和实际消费集合一致；
- 所有调度 mutation 只有 Official engine 一条路径。

---

## R3 — Formal Due 六集合与共享状态

优先级：**P0 数字与队列一致性阻断**。

目标公式：

    formalDue = schedulerDue
                ∩ activePlacement
                ∩ introduced
                − suspended
                − buried
                − retired

### R3-1. placement 缺失必须 fail-closed

- activePlacementCardIdsByImport 缺失时返回 unknown/empty，不得回退 schedulerDue。
- UI 区分 0、加载中、不可用和错误；不可用时显示短横线或说明。
- 不得继续使用 count 近似 card IDs。

### R3-2. 补齐 suspended、buried、retired

- production sync 为六个集合都提供真实 reader。
- retired 定义必须与 projection/tombstone/uninstall 状态一致。
- suspend/bury mutation 后同一 repository 立即刷新。

### R3-3. 统一 repository

- 移除 HomeDue 的 static 全局 map，改为可观察 repository。
- Home、Play Hub、Profile、review assembler、review coordinator 读同一快照。
- snapshot 带 generation/source fingerprint，防旧异步结果覆盖新结果。
- rollback 保存并恢复六个集合及 source 状态。

### R3 测试

- [ ] 六集合公式逐项；
- [ ] placement missing fail-closed；
- [ ] suspended/buried/retired 各减少准确 cardId；
- [ ] refresh 失败恢复完整旧快照；
- [ ] stale generation 不覆盖新结果；
- [ ] Home/Hub/Profile count 与 formal review 消费数一致；
- [ ] 多来源隔离。

---

## R4 — W8 Legacy → Official 真迁移

优先级：**P0 数据所有权阻断**。

### R4-1. 建立完整 Legacy writer 矩阵

freeze 不能只拦 answer。至少盘点并统一保护：

- TurnaReviewLedger.ensureWord / answer；
- AnkiDeckManager.recordCardReviewed；
- AnkiNoteDao.setCardState；
- replaceDeckIndex；
- replaceImportIssues；
- replacePracticeProjections；
- upsertNotetype / upsertNote；
- batch upsert；
- clearBuriedBefore；
- deleteByImport 和其他清理入口。

每个 mutator 必须声明 write intent：

- normalLegacyWrite：frozen 后拒绝；
- migrationRead：永远只读；
- migrationCleanup：只允许持有一次性 migration token 的 Saga；
- rollbackRestore：只允许处于 rollback state。

不得用散落注释代替守卫。

### R4-2. 不再伪称跨数据库原子事务

当前 migration catalog 与 CourseDatabase 是两个 SQLite 所有权域，不能把两个独立连接的顺序写称为“一条 SQLite 原子事务”。

推荐方案：

- 把生产路由唯一读取的 owner marker 和 cutover state 放进 CourseDatabase；
- 在同一 CourseDatabase 事务中更新 owner marker、backend_kind 和 cutover generation；
- Official catalog 的 legacy_anki_migrations 只做可恢复 journal/mirror，不再决定生产 owner；
- post-commit 镜像失败可重放，但不得让路由回到 Legacy；
- 若不迁移权威表，则实现明确的 prepare/commit 两阶段协议，默认 frozen/no-writer，证明不会 dual-active。

禁止：

- 先 setRecordedKind 再 transition；
- callback 名为 atomic 但跨库；
- 任一中间态允许两个 writer。

### R4-3. 完成生产 driver

- startup census 只发现和记 journal；
- 用户查看来源、差异、卡数、调度策略；
- 用户确认后 begin；
- freeze → backup → import → validate → projection → owner commit → observe；
- 任一步可 crash/resume；
- rollback 在 owner commit 前恢复 Legacy；commit 后走 forward recovery，不静默双写。

### R4-4. 调度迁移策略

- lossless native migration 能力存在才允许“保留调度”；
- 无法保留时必须明确提供 reset / reschedule / export-only，并要求确认；
- 不得把 Turna FSRS 字段近似塞入 Official scheduler 后宣称无损。

### R4 测试

- [ ] freeze 后全部 Legacy mutator 被拒；
- [ ] migration cleanup token 只在正确 state 有效；
- [ ] 每个阶段注入 crash 后可 resume；
- [ ] owner commit 任意失败都不会 dual-active；
- [ ] router、course backend 和 journal 最终一致；
- [ ] 启动不自动 cutover；
- [ ] 用户未确认策略不能切 owner；
- [ ] 真实 Drift + Official catalog host fixture 跑完整 Saga。

### R4 完成定义

- freeze 是行为，不是注释；
- 生产 owner 只有一个权威读取点；
- 跨库过程被诚实建模为可恢复协议；
- 真实用户迁移仍需单独真机/备份授权，不由 host 测试代替。

---

## R5 — Browser、Stats、Media 和产品入口

优先级：P1 产品可用性。

### R5-1. 正式接线

- Official section 的 Browse / Stats 按钮不得为 null。
- Course management、review screen 和 source management 使用同一 source resolver。
- 路由收到 Legacy importId 时，先通过 production router 解析 owner，再把完整 Official sourceId 传给 Official 服务。
- Official owner 查询失败时显示错误，不回退 Legacy NoteStore 伪造结果。

### R5-2. Browser 语义

- query、deck、tag、flag、marked、suspended、buried 筛选在 Official engine 路径全部生效。
- 搜索结果可打开 Official rendered card。
- suspend/bury 等 mutation 后更新 R3 repository。
- 无 engine 时只允许明确的 catalog read-only 能力，不冒充完整 Browser。

### R5-3. Stats 语义

- 总卡、新卡、学习中、复习中、suspended/buried；
- 今日完成与 revlog；
- forecast；
- retention 指标必须来自 Official 数据；无法计算就标 unavailable；
- 不得在 Official source 上回退 Turna MemoryCurveProvider。

### R5-4. Media

- 纯 Official fidelity 卡只通过 Official media resolver。
- 禁止为了显示媒体读取 Legacy AnkiNoteDao。
- 缺失、非法路径、Range、MIME 和大媒体失败要有回归测试。

### R5 测试

- [ ] migrated legacy importId 正确路由到 Official sourceId；
- [ ] Browse/Stats 产品按钮可达；
- [ ] Official path 不读取 Legacy DAO/provider；
- [ ] 全部 Browser filter 生效；
- [ ] stats forecast/retention 正确或明确 unavailable；
- [ ] media 只走 Official resolver。

---

## R6 — 导入原子性、再导入和向导收口

优先级：P1 数据完整性与维护性。

### R6-1. visibility commit last

Official Collection、catalog 和 CourseDatabase 无法组成单个数据库事务，因此使用可恢复 Saga：

1. source state=staging；
2. Official import；
3. mapping 确认；
4. projection staging；
5. 校验 section/card/source fingerprint；
6. 写 course visibility manifest；
7. 最后切 source active 和 owner；
8. 刷新 course entries。

active source 不得早于可用 projection/course entry。用户取消或 projection 失败时，不得留下可见的半成品来源。

### R6-2. recovery / reconciler

- 启动识别 imported-no-projection、projection-no-active-source、owner mismatch、stale staging。
- 为每种状态提供确定的 resume/rollback。
- reconciler 不只分类，还要有受控 executor。
- 清理不得删除用户已经开始复习的 active source。

### R6-3. reimport

- same hash：no-op；
- replace：保留 sourceId，更新 collection/projection，明确调度保留策略；
- append：新 sourceId；
- replace/append 都不得产生 Legacy rows；
- force replace 的删除必须在新版本验证成功之后。

### R6-4. 缩小向导

AnkiImportPage 只保留：

- step UI；
- 文件选择；
- mapping/确认；
- 进度与错误；
- 完成页动作。

解析、collision strategy、reimport、publish、recovery 放到 application Saga。目标不是机械拆 widget，而是让 UI 不持有所有权和事务规则。

### R6-5. sample 和 colpkg

- sample 使用真实小型 apkg 走 Official-first，或永久删除生产 sample 入口；
- colpkg 在 Official 后端未实现前继续明确拒绝；
- 禁止 sample/colpkg 静默落 Legacy。

### R6 测试

- [ ] 每个 Saga 阶段失败后零可见半成品或可恢复；
- [ ] mapping cancel 不激活 source；
- [ ] same/replace/append；
- [ ] import 完成动作遵守 R1 导航语义；
- [ ] 新导入零 Legacy NoteStore；
- [ ] real apkg fixture；
- [ ] 大牌组、磁盘不足、强杀。

---

## R7 — OHOS 数据出口的诚实收口

优先级：P1 数据安全；主分支 OHOS 删除本身已分项通过。

### R7-1. 先做用户事实决策

二选一并形成签字证据：

1. 无外部 OHOS 用户：记录查询口径、时间、负责人和书面豁免；
2. 存在或无法排除用户：必须交付 sunset export。

只有 exporter class 存在不等于用户能够导出。

### R7-2. sunset export 不回灌主分支

如果需要 sunset：

- 从最后一个 OHOS release tag 建独立维护分支；
- 增加设置页“导出 Turna 迁移包”入口；
- 真机验证生成 turna-migration-v1；
- 发布说明写明最后版本、停止支持日期和 Android 导入路径；
- 主分支继续保持无 ohos/。

### R7-3. Android 导入 turna-migration-v1

- 设置页独立入口，不混同普通 JSON backup；
- zip staging；
- 校验 manifest version、SHA256SUMS、路径穿越、容量；
- 非 Anki 数据事务恢复；
- Legacy Anki 行进入 legacyPendingMigration，不激活 Legacy scheduler；
- 后续由 R4 用户确认后迁移；
- API key/密钥继续排除。

### R7 测试

- [ ] export → Android import 往返；
- [ ] checksum 篡改、zip slip、缺文件、版本过新、磁盘不足；
- [ ] 失败后零半恢复；
- [ ] Anki 行只进入 pending；
- [ ] sunset 真机证据或正式豁免二选一。

---

## R8 — 发布门禁、内部路由、文档和复验

### R8-1. 内部页面门控

- OfficialAnkiReviewRoute、internal page、migration lab 在 release 中移除或由 diagnostics route guard 保护。
- 直接 deep link 不得绕过 guard。
- diagnostics 构建必须显式 opt-in。

### R8-2. 代码质量

- flutter analyze 最终零退出；
- git diff --check 通过；
- 修复 touched files 的 warning/info；
- 移除无效 non-null assertion、死分支和残留 OHOS 活跃文案；
- import screen 拆分后避免新 god object。

### R8-3. 自动化门禁

必须运行：

    flutter analyze
    flutter test --exclude-tags golden
    flutter test test/golden/course_tree_golden_test.dart
    flutter test test/golden/play_hub_golden_test.dart
    flutter build apk --release --split-per-abi --target-platform android-arm64
    git diff --check

全量测试中的既有三个失败也应修复或由项目负责人书面拆出；Anki 发布收据不得隐藏它们：

- wetland palette contract；
- AI config dispose flush；
- dark mode CourseTree provider。

### R8-4. APK 可复现性

- 干净 native commit 构建 libturna_anki.so；
- APK 只包含声明支持的 arm64-v8a；
- 记录 APK、so、source archive SHA-256；
- AGPL/source distribution 收据与 native commit 对齐；
- 不接受工作树变化中的临时 APK 作为发布物。

### R8-5. release 真机矩阵

至少覆盖：

- 冷启动直接导入 Basic、Cloze、复杂模板；
- 两个 Official 来源切换；
- 语言正课与 Anki 课程相互切换；
- Review All 跨来源；
- Again 学习卡重排；
- Undo/Redo/Bury/Suspend；
- Browser/Stats/Media；
- reimport same/replace/append；
- backup/restore；
- 强杀恢复；
- uninstall 精确来源；
- 从旧 courseScope 偏好升级；
- migration package import；
- 无网络和磁盘不足。

---

## 4. 建议 PR 切分

每个 PR 必须可独立回滚；不要把所有返工压成一个巨型提交。

1. fix(anki): restore truthful acceptance status and schema 9 backup tests
2. fix(anki): introduce typed course scope and full Official source ids
3. fix(anki): isolate builtin language tree from Anki courses
4. fix(anki): keep import navigation stable and restore visible course switcher
5. fix(anki): exact-source course deletion and legacy preference repair
6. fix(anki): preserve Official rendered fidelity in formal review
7. refactor(anki): drive formal review from live scheduler current
8. fix(anki): coordinate Review All across sources and ledgers
9. fix(anki): six-set observable formal due repository
10. fix(anki): enforce complete Legacy writer freeze
11. refactor(anki): authoritative owner commit and recoverable W8 protocol
12. feat(anki): wire Official browser stats media product routes
13. refactor(anki): import visibility commit last and recovery executor
14. refactor(anki): split import wizard and implement Official reimport
15. feat(migration): import turna-migration-v1 on Android
16. chore(anki): gate diagnostics routes and close release evidence

生成代码、routing.gr.dart、golden、lockfile 和 native artifact 必须跟随引发它们变化的 PR。

---

## 5. 工作量粗估

按一名熟悉仓库的工程师估算，不包含正式 release 观察期：

| 波次 | 规模 | 粗略人日 |
|---|---:|---:|
| R0 基线止血 | S–M | 1–2 |
| R1 course scope / 导航 | M–L | 3–5 |
| R2 实时保真正式复习 | XL | 7–12 |
| R3 六集合 Due | M–L | 3–5 |
| R4 W8 真迁移 | XL | 8–15 |
| R5 Browser/Stats/Media | L | 5–8 |
| R6 导入 Saga/再导入/拆向导 | XL | 6–10 |
| R7 OHOS 数据出口 | L | 4–8；需要 sunset 分支另加 3–6 |
| R8 发布复验 | M–L | 3–6 |

合计约 40–71 人日；如果需要补 native lossless schedule migration 或重新发布 OHOS sunset，则另行估算。

---

## 6. 明确不做

- 不恢复主分支 ohos/；
- 不在观察期前删除 Legacy importer/scheduler/schema；
- 不建设 AnkiWeb；
- 不通过再次增加自由组合 feature flags 解决 owner 问题；
- 不把 Official HTML 转纯文本后称为 fidelity；
- 不用 count 近似替代 due card IDs；
- 不让启动 census 自动迁移真实用户；
- 不伪造真机、用户数量、release 观察或 OHOS sunset 证据。

---

## 7. 最终 Definition of Done

以下全部完成后，才能进入正式切流验收：

### 课程与导入

- [ ] 语言正课不出现任何 Anki Section；
- [ ] 一个 Official source 对应一个可见课程；
- [ ] 完整 sourceId 贯穿 entry、scope、review、stats 和 uninstall；
- [ ] 导入完成不抢占当前课程，用户动作决定导航；
- [ ] import/publish 失败不留下可见半成品；
- [ ] same/replace/append reimport 通过。

### 正式复习与 Due

- [ ] Official rendered fidelity 未被 strip；
- [ ] 页面由 Scheduler current 实时驱动；
- [ ] Review All 覆盖所有计数来源；
- [ ] Undo/Redo/Bury/Suspend 写 Official engine；
- [ ] 六集合 Due 完整且 placement missing fail-closed；
- [ ] Home/Hub/Profile count 与实际 queue 一致。

### 迁移与 OHOS

- [ ] freeze 后全部 Legacy writer 被阻断；
- [ ] owner commit 无 dual-active 中间态；
- [ ] W8 可 crash/resume/rollback；
- [ ] OHOS sunset export + Android import 完成，或有书面无用户豁免；
- [ ] 主分支保持无 OHOS product target。

### Parity 与发布

- [ ] Browser/Stats/Media 对 Official 来源可达且不回退 Legacy；
- [ ] internal routes 在 release 不可绕过；
- [ ] flutter analyze、全量测试、golden、diff check 全绿；
- [ ] 从干净 native commit 重建 arm64 release APK；
- [ ] release 真机矩阵通过并保存原始日志/hash；
- [ ] 主计划、receipt、README 与实际证据一致。

### 继续 HOLD

即使上述返工通过，以下仍按 [34-w9-legacy-deletion-hold.md](./34-w9-legacy-deletion-hold.md) 执行：

- Legacy 新写入连续一个正式版本为 0；
- 存量用户来源完成处置；
- W9 分波物理删除；
- schema drop 和旧恢复包兼容观察。

在 HOLD 完成以前，状态仍只能写：

> Official Anki 已进入 Android 生产候选，Legacy 仍处于停止新写与观察期；OHOS product target 已退役。

不得写“迁移全部完成”。
