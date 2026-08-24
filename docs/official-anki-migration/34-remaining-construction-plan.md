# 34 Official Anki 一次性验收返工与生产收口实施计划

> 文档代号：ANKI-CUTOVER-ONE-SHOT
> 日期：2026-08-25
> 状态：**一次性交付施工规格；最终总验收前始终 NO-GO**
> 父计划：[34 Official 生产收口与 OHOS 退役](./34-official-anki-production-cutover-and-ohos-retirement-plan.md)
> 验收回执：[34-cutover-receipt.md](./34-cutover-receipt.md)
> W9 HOLD：[34-w9-legacy-deletion-hold.md](./34-w9-legacy-deletion-hold.md)
> OHOS 决策：[ADR 0041](../decisions/0041-ohos-product-eol.md)
>
> 本文件是 34 的唯一活跃返工入口，替代此前的“34 剩余施工计划”口径。目标不是逐波交付，而是用**一次连续施工活动**完成 R0–R8 的全部可编码工作，形成一个干净、可复现、可真机验收的 Android arm64 release candidate。R0–R8 只是工作包，不是允许中途宣告完成的阶段。在本文最终门禁全部通过以前，准确状态始终是 **Official Anki 迁移中 / NO-GO**，不得写“迁移完成”“正式切流完成”或“OHOS 用户数据出口完成”。

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

本轮（2026-08-25 一次性施工）host 门禁结果：

| 门禁 | 本轮结果 | 状态 |
|---|---:|---|
| 定向 Official/OHOS 测试 | 16 个新测试文件 + 既有定向全部通过（见 cutover-once/targeted-tests.txt） | ✅ |
| Golden | 4 通过（course_tree + play_hub light/dark） | ✅ |
| 全量非 Golden | 1825 通过、0 失败（含修复 3 个既有基线失败与 2 处 schema 字面量回归） | ✅ |
| schema 9 backup/restore 回归 | 已修复（测试改读常量） | ✅ |
| flutter analyze | 0 error；88 warning/info（原 133） | ✅（error 门禁） |
| git diff --check | 通过 | ✅ |
| Android arm64 release | 通过，55.8 MB（`app-arm64-v8a-release.apk`） | ✅ |
| Native submodule | pin `967aa0d57` + 3 补丁 verify_pin 通过；`build.sh` 从锁定 commit 重建 so（符号校验 pass） | ✅ |
| release 真机矩阵 | 未执行（无设备会话） | ❌ 未勾 |
| OHOS 外部事实（sunset/豁免） | 未发生 | ❌ 未勾（§17.7 HOLD） |

本轮 APK SHA-256（候选快照，非发布收据；真机矩阵未跑）：

    39bd48a9911b0b469a054a1ecdd22aaa4f312eae81e5a30ea5d858d15f849d54

证据目录：[archive/artifacts/cutover-once/](./archive/artifacts/cutover-once/)（baseline / toolchain / revisions / analyze / targeted / full / golden / diff-check / native build / apk+so hash）。

原 2026-08-24 验收轮的拒收结论（sourceId 截断、保真降级、Review All 单来源、六集合缺失、W8 非生产级、Browser/Stats 断链、schema 9 回归、脏 native 树）已由本轮 R0–R8 施工逐项关闭，明细见文末「一次性施工状态（2026-08-25）」。

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

## 3. 一次性施工依赖图

这里的并行只表示实现时可以交错修改，不表示可以分批发布或提前验收。

    S0 施工快照 + red tests + schema 决策
     │
     ├── S1 CourseScope / source identity / DB v21
     │     ├── R1 课程层级、课程选择、偏好修复、精确卸载
     │     └── R6 import visibility saga、reimport、向导
     │
     ├── S2 Live review contracts
     │     ├── R2 fidelity + scheduler current + Review All
     │     └── R3 六集合 Due repository
     │
     ├── S3 Owner transition contracts
     │     └── R4 write fence + authoritative cutover + recovery
     │
     └── S4 Product parity / EOL
           ├── R5 Browser / Stats / Media
           └── R7 Android migration package / OHOS evidence
                    │
                    └── S5 R8 全量集成、真机矩阵、单一 RC、总收据

硬依赖：

1. CourseScope codec 和 CourseDatabase v21 必须先定稿，R1/R4/R6/R7 不得各自发明 source key。
2. live review contract 必须先定稿，R2/R3/R5 不得分别缓存 current、due 和 suspended 状态。
3. authoritative owner transition 必须先定稿，router、writer guard、census 和 uninstall 只认一个 owner 事实源。
4. 所有工作包必须在同一个集成工作树完成；任何一个 P0/P1 未关闭，都不生成“部分完成”收据。
5. R4 未通过故障注入前，不对真实 Legacy 来源执行 cutover。
6. R8 全部通过前不发布、不打 production tag、不删除 Legacy。

---

## 4. “一次性做完”的执行契约

### 4.1 一次性交付的定义

本计划中的“一次性”指：

- 一次连续施工目标；
- 一个集成分支或工作树；
- 一套统一数据模型；
- 一次最终全量回归；
- 一个 Android arm64 release candidate；
- 一份最终 cutover receipt。

它不表示把所有代码压成一个不可审查的 commit，也不表示跳过测试。允许在同一工作树内建立内部检查点，但不允许把 R1、R2、R3 等分别当成可发布版本。

### 4.2 本次必须交付

一次施工结束时必须同时具备：

1. 完整 CourseScope/source identity；
2. 不混入语言正课的 Official course entry；
3. import visibility commit-last 和 reimport；
4. Official fidelity + live Scheduler current 正式复习；
5. 多来源 Review All；
6. 六集合 Formal Due repository；
7. 全 Legacy mutator write fence；
8. 单一权威 owner transition 和 crash recovery；
9. Official Browser/Stats/Media 产品入口；
10. Android turna-migration-v1 importer；
11. release diagnostics route guard；
12. 全绿静态检查、全量测试、golden、release build 和真机证据。

只完成其中一部分时，施工状态仍是 NO-GO。

### 4.3 外部门禁与一次性代码施工的边界

下列事项不能靠一次代码修改伪造：

- 是否存在外部 OHOS 用户；
- OHOS sunset 包是否真的发布；
- 一个正式版本内 Legacy 新写入是否为零；
- 存量真实用户是否全部完成处置；
- 真机安装和人工产品验收结果。

本次代码施工必须把这些事项所需的能力、日志、导入器和证据模板一次性准备好；外部事实没有发生时，最终状态只能是 production candidate，不得勾 W9。

### 4.4 中途失败处理

- 编译或测试失败：在当前施工活动内修复并继续，不能把失败转写成 baseline 后结束。
- 发现新架构冲突：更新本文“决策锁”，采用一个方案后继续，不新建平行实现。
- 发现数据损失风险：立即停止 mutation，只允许只读诊断；补 recovery test 后继续。
- 设备不可用：完成所有 host/build 门禁，保留真机项未勾；不得用 widget test 替代设备证据。
- 外部 OHOS 用户事实未知：Android importer 仍必须完成；sunset/豁免项保持未勾。

### 4.5 禁止的“假一次性”

- 用 feature flag 同时保留新旧两套生产路径；
- 新建第二套 CourseProvider、Due cache、review page 或 migration saga；
- 把旧失败加入 BASELINE 后宣布全绿；
- 只让单元测试通过，生产路由仍指向旧实现；
- 修改文档勾选，但没有对应命令、日志、hash 或真机证据；
- 为赶一次性交付直接删除 Legacy schema 或恢复路径。

---

## 5. 本次锁死的架构决策

施工开始后，除非出现可证明的数据安全阻断，以下决策不再重新讨论。

### D1. CourseScope 使用显式类型和版本化 codec

领域类型至少包含：

    BuiltinCourseScope(languageCode)
    LegacyAnkiCourseScope(importId)
    OfficialAnkiCourseScope(profileId, sourceId)

持久化 wire key 使用无歧义格式：

    course-scope:v1:builtin:<languageCode>
    course-scope:v1:legacy:<importId>
    course-scope:v1:official:<profileId>:<sourceId>

codec 必须对动态 segment 做 percent-encoding（或等价长度编码），不得假设 profileId/sourceId 永远不含冒号。

兼容读取旧值：

    空字符串                     → 当前 builtin language
    anki:<legacyImportId>        → 查询 anki_course_sources/Legacy import 后解析
    anki:<fullOfficialSourceId>  → 查询 anki_course_sources/catalog 后解析
    anki:src                     → 歧义旧错误值，进入 R1 repair

如果同一个旧 key 同时命中 Legacy 和 Official，必须视为歧义并回到 builtin，不能靠字符串形状猜 owner。

业务代码不得再用 startsWith/split first 判断 owner。字符串匹配只能存在于 codec 和一次性偏好迁移器。

### D2. Course entry 来自 anki_course_sources

- anki_course_sources 是课程目录的事实源；
- official_anki_projection_manifest 只表示某一 source 的 projection generation 可读；
- Sections/Units/Lessons 是投影内容，不承担课程身份；
- Official catalog 提供 display name、source hash 和 collection/card facts；
- 一个 profileId + sourceId 只能对应一个 course_id；
- course_id 必须稳定，reimport replace 不得改变。

### D3. Owner 权威放在 CourseDatabase

- anki_course_sources.backend_kind 是生产路由唯一 owner marker；
- CourseDatabase 内的 transition/write-fence 与 backend_kind 在同一事务提交；
- Official catalog 的 legacy_anki_migrations 是可恢复 journal/mirror，不再决定生产路由；
- mirror 落后可以重放，但不得让 owner 回退；
- 不使用跨两个 SQLite connection 的 callback 冒充原子事务。

### D4. Official formal review 是 live session

- 不把 Official queue 复制成固定 StudyItem 数组；
- UI 每次只消费一个 FormalReviewCardSnapshot；
- snapshot 包含 sourceId、cardId、render generation、answer token/scheduling context；
- answer 成功后旧 snapshot 立即失效；
- next 永远重新读取 Scheduler current；
- presentation 由 Official rendered HTML 驱动，课程投影 presentation 不能替代正式复习。

### D5. Review All 使用顺序 source coordinator

- 启动时冻结“本次参与的 source 列表”，不冻结每个 source 的卡序；
- coordinator 每次只打开一个 source session；
- source 当前 queue 为空后切下一个；
- 单个 source 失败可以记录并继续，但最终结果必须显示失败来源；
- Legacy/Official 混合期由 source owner 选择 ledger；
- 总计数来自同一 FormalDueSnapshot。

### D6. Formal Due 只有一个 repository

- 六集合和 loading/error/generation 全部放在 OfficialFormalDueRepository；
- Home、Hub、Profile、Review All 和 Stats 只读该 repository；
- mutation 后由 repository refresh，不允许 UI 自己减一；
- 缺 placement、engine、retired evidence 时是 unknown/unavailable，不猜零、不猜 schedulerDue。

### D7. Import 和 projection 使用 commit-last Saga

- Official collection import 可以先发生，但 source 保持 staging；
- projection staging 验证完成后才提交 manifest；
- anki_course_sources active、owner 和可见性最后提交；
- CourseProvider 在最终提交后一次刷新；
- cancel/crash 只能留下可识别 staging，不能留下用户可见半课程。

### D8. OHOS 主分支保持删除

- 主分支不恢复 ohos/；
- Android importer 本次无条件完成；
- 如需 OHOS sunset，只在最后 OHOS release tag 的维护分支增加导出 UI；
- 无真实 sunset 或书面豁免时，用户数据出口项保持未完成。

---

## 6. 数据库和持久化改动规格

### 6.1 CourseDatabase v21

把 schemaVersion 从 20 升到 21，并在升级与 fresh-create 路径同时创建：

1. anki_course_sources 新列：
   - owner_generation INTEGER NOT NULL DEFAULT 0；
   - write_fence TEXT NOT NULL DEFAULT open；
   - active_projection_generation TEXT；
   - last_transition_id TEXT；
   - 复用现有 state 作为唯一 visibility state，不再增加第二个可见性状态列；
2. 新表 anki_owner_transitions：
   - transition_id TEXT PRIMARY KEY；
   - profile_id TEXT NOT NULL；
   - legacy_import_id TEXT；
   - official_source_id TEXT NOT NULL；
   - course_id TEXT NOT NULL；
   - from_backend TEXT NOT NULL；
   - to_backend TEXT NOT NULL；
   - phase TEXT NOT NULL；
   - generation INTEGER NOT NULL；
   - policy TEXT NOT NULL；
   - created_at / updated_at；
   - last_error_code；
3. partial unique index：同一 course_id 同时只能有一条 preparing/frozen/committing transition；
4. course scope repair journal，或在 course_meta 中记录 course_scope_codec_version=1；
5. backup/restore manifest 纳入新列、新表和 codec version。

允许的 write_fence：

    open          Legacy writer 仍按 owner 工作
    frozen        所有普通 Legacy mutation 拒绝
    officialOnly  只允许 Official writer；Legacy 仅 migration cleanup token

现有 anki_course_sources.state 允许的可见性值：

    staging
    active
    repairing
    pendingCleanup
    retired

### 6.2 Owner transition 状态机

    discovered
      → awaitingUserPolicy
      → backingUp
      → importingOfficial
      → verifyingIdentity
      → projectionStaging
      → cutoverReady
      → frozen
      → committing
      → observing
      → complete

失败分支：

    commit 前失败  → rollbackPending → legacy/open
    commit 中失败  → recoveringForward → officialOnly
    commit 后失败  → recoveringForward → observing

不允许：

    frozen → open（没有成功 rollback receipt）
    officialOnly → legacy（没有显式 disaster recovery）
    任意 phase → dualWriter

### 6.3 Import visibility 状态机

    selected
      → importingCollection
      → awaitingMapping
      → projectionStaging
      → validatingProjection
      → committingVisibility
      → active

异常：

    selected/importing/awaitingMapping/projectionStaging
      → cancelled 或 recoverable

active 只能在以下条件同时为真时写入：

- Official source active；
- source hash/fingerprint 可读；
- projection manifest generation 与 index 一致；
- anki_course_sources 使用完整 sourceId；
- 至少一个有效 Section，或产品明确显示 empty source；
- owner/backend_kind=official；
- CourseScope 可编码并能 round-trip。

### 6.4 偏好迁移必须在 DB/Provider 可用后执行

启动顺序：

1. 打开 CourseDatabase v21；
2. 读取 anki_course_sources；
3. 执行旧 courseScope/courseOrder repair；
4. 持久化 codec version；
5. 初始化 CourseProvider；
6. 加载当前课程。

禁止在 source catalog 尚未打开时把 anki:src 随机绑定到第一个来源。

---

## 7. 逐文件施工地图

表中“新增”是建议位置；可以在保持职责清晰的前提下调整文件名，但不得省略责任。

| 工作面 | 主要文件 | 一次性改动 |
|---|---|---|
| Scope domain | 新增 lib/domain/course/course_scope.dart | typed scope、codec、equality、旧值解析结果 |
| Scope repair | 新增 lib/application/course_scope_migration.dart | courseScope/courseOrder 幂等修复与 journal |
| Course provider | lib/application/course_provider.dart | 不再从 sectionId 猜 source；目录读 anki_course_sources；builtin 严格排除 Anki |
| Course repository | lib/data/course_repository.dart | source/course 查询、v21 owner/visibility transaction |
| Course DB | lib/data/course_database.dart | schema v21、transition/fence/visibility、backup coverage |
| Course UI | lib/views/courses/course_management_page.dart | 唯一 active、完整 sourceId、精确删除、新导入高亮 |
| Home switcher | lib/views/home/components/stat_app_bar.dart | 显示当前课程名和明确切换入口 |
| Import navigation | lib/views/anki/anki_import_screen.dart | commit 不抢 scope；三个完成动作分流 |
| Uninstall | lib/application/anki/anki_deck_manager.dart | exact source delete、shared-note validation、pending cleanup |
| Import Saga | lib/application/anki_official/import/official_anki_official_first_service.dart | staging → visibility commit-last → recovery |
| Import planner | lib/application/anki_official/import/anki_import_execution_plan.dart | 单一 plan；无 Legacy fallback |
| Projection store | lib/application/anki_official/projection/official_anki_projection_store.dart | generation staging/validate/commit；不早写 visible manifest |
| Course entry | lib/application/anki_official/projection/official_anki_course_entry.dart | 读 course source + active manifest，不用 section prefix 建目录 |
| Reconciler | lib/application/anki_official/migration/official_anki_source_reconciler.dart | 从 classifier 升级为可控 repair executor |
| Formal loader | lib/application/anki/official_formal_review_production_loader.dart | 不 strip HTML；只建立 live source session |
| Review content | lib/application/anki/anki_review_content.dart | fidelity content/presentation 正确分派 |
| Live review | 新增 lib/application/anki_official/review/official_formal_review_coordinator.dart | source coordinator、snapshot generation、next/current |
| Study host | lib/application/anki/anki_study_session_host.dart | Official formal 走 live contract；practice 保持现有语义 |
| Study controller | lib/application/anki/study_session_controller.dart | 不再推进 Official 固定数组；Legacy/practice 保持 |
| Review screen | lib/views/anki/anki_review_screen.dart | Review deck / Review All 语义分开；不取 first source |
| Review page | lib/views/anki/anki_review_session_page.dart | snapshot 驱动、fidelity、Undo/Redo/Bury/Suspend |
| Hub/Profile | lib/views/play/play_hub_screen.dart；lib/views/profile/widgets/profile_quick_actions.dart | count 与 source coordinator 使用同一 snapshot |
| Due repository | 新增 lib/application/anki_official/engine/official_formal_due_repository.dart | 六集合、generation、rollback、observable state |
| Due sync | lib/application/anki_official/engine/official_anki_home_due_sync.dart | 所有 reader；无数据 fail-closed |
| 旧 Due facade | lib/application/anki_official/engine/official_anki_home_due.dart | 迁移调用后删除 static maps 或降为薄 facade |
| Review session | lib/application/anki_official/engine/official_anki_review_session.dart | current snapshot、token invalidation、mutation refresh |
| Writer guard | lib/domain/review/turna_review_ledger.dart；lib/data/anki_note_dao.dart | 全 mutator fence + write intent/token |
| Migration Saga | lib/application/anki_official/migration/official_legacy_source_migration_saga.dart | freeze 行为、transition、forward recovery |
| Migration DAO | lib/application/anki_official/migration/official_anki_migration_dao.dart | 只做 Official journal mirror，不冒充 owner transaction |
| Production router | lib/application/anki_official/migration/official_anki_production_router.dart | owner 只读 CourseDatabase 权威记录 |
| Migration driver | lib/application/anki_official/migration/official_legacy_migration_driver.dart | 用户确认、完整 Saga、resume/rollback |
| Browser service | lib/application/anki_official/browser/ | 解析完整 sourceId、全部 filter、mutation refresh |
| Browser UI | lib/views/anki/anki_card_browser_page.dart | Official product route；失败不回 Legacy |
| Stats service | lib/application/anki_official/stats/ | scheduler/revlog/forecast/retention |
| Stats UI | lib/views/anki/anki_deck_stats_page.dart | unavailable 与真实 0 区分 |
| Media | lib/views/anki/anki_html_card_view.dart 及 Official media resolver | 禁止 Official fidelity 读取 Legacy DAO |
| Migration export/import | lib/application/migration/ | turna-migration-v1 validator、staging、Android importer |
| Settings | lib/views/settings/pages/data_backup_settings_page.dart | 独立迁移包导入入口、结果/失败说明 |
| Routes | lib/routing/routing.dart；lib/routing/routing.gr.dart | release diagnostics guard、deep-link guard |
| Composition | lib/service/locator.dart；lib/main.dart | 新 repository/Saga 单例、正确启动顺序 |
| Tests | test/application、test/views、test/golden | 本文全部 red/green/集成/guard 场景 |
| Evidence | docs/official-anki-migration/archive/artifacts/cutover-once/ | 最终命令、hash、设备日志；施工结束时才生成 |

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

## 8. 单一集成交付中的内部检查点

这些检查点只用于控制风险和便于回滚，不是 PR 发布计划。默认在同一个 integration branch / 工作树连续完成；只有 OS-25 总验收通过后才形成一个面向主分支的最终交付。

| 检查点 | 内容 | 最低自检 | 是否允许发布 |
|---|---|---|---|
| C0 | 基线、red tests、DB v21/codec skeleton | schema migration + codec tests | 否 |
| C1 | CourseScope、课程目录、偏好修复、精确卸载 | R1 targeted tests | 否 |
| C2 | import commit-last、reimport、向导导航 | R6 targeted tests | 否 |
| C3 | fidelity、live current、Review All、动作 | R2 targeted tests | 否 |
| C4 | 六集合 Due repository 和所有首页消费者 | R3 targeted tests | 否 |
| C5 | write fence、owner transition、W8 driver | fault-injection matrix | 否 |
| C6 | Browser/Stats/Media、迁移包、route guard | R5/R7/R8 targeted tests | 否 |
| C7 | 全量 tests/analyze/golden/build | 全部自动化命令通过 | 否 |
| C8 | release 真机、hash、最终收据 | OS-25 清单全勾 | **唯一可交付点** |

每个检查点都可以有本地 commit，但：

- 不单独打 release tag；
- 不更新主计划为部分 GO；
- 不翻 production flag；
- 不删除兼容代码；
- 不把失败写入 baseline 规避；
- 下一个检查点发现前一检查点设计错误时，直接回改同一集成变更。

---

## 9. 一次性施工任务账本

执行者必须从 OS-00 连续推进到 OS-25。除数据安全阻断或缺真实设备外，不以“后续再做”结束。

| ID | 任务 | 依赖 | 必须产出 |
|---|---|---|---|
| OS-00 | 记录 git status、主工程 commit、native commit、toolchain、现有测试结果 | 无 | baseline receipt；不覆盖用户改动 |
| OS-01 | 先写所有已知缺口的 red tests | OS-00 | 新测试在旧实现上按预期失败 |
| OS-02 | CourseDatabase v21、owner transition、fence、visibility、backup schema | OS-01 | fresh/create/20→21/restore tests |
| OS-03 | CourseScope type/codec 与旧偏好 repair | OS-02 | codec v1；单源/多源/损坏值迁移 |
| OS-04 | CourseProvider 改读 anki_course_sources；builtin 隔离 | OS-03 | 正课零 Anki Section；一个 source 一个 entry |
| OS-05 | 课程管理、顶部切换器、导入完成导航 | OS-04 | 唯一 active；完成/查看/学习三分流 |
| OS-06 | exact-source uninstall 与 pending cleanup | OS-04 | 删除 A 不影响 B；共享 note 安全检查 |
| OS-07 | import source/projection staging 和 visibility commit-last | OS-02/OS-04 | crash/cancel 不出现可见半源 |
| OS-08 | same-hash/replace/append reimport | OS-07 | stable course_id/sourceId 规则和调度策略 |
| OS-09 | 抽离 import screen application state | OS-07/OS-08 | UI 只保留 step/mapping/progress/actions |
| OS-10 | FormalReviewCardSnapshot/live session contract | OS-01 | generation/token/current 明确 |
| OS-11 | Official renderer fidelity 接入 shared host | OS-10 | HTML/CSS/media/typed/MathJax 不被 strip |
| OS-12 | Scheduler current 驱动 next/answer | OS-10/OS-11 | reorder/reinsert 测试通过 |
| OS-13 | Review All source coordinator 和混合 owner | OS-12/OS-03 | 多来源全部消费；来源失败可见 |
| OS-14 | Undo/Redo/Bury/Suspend + single-flight | OS-12 | mutation 后 queue/due 同步 |
| OS-15 | OfficialFormalDueRepository 六集合 | OS-02/OS-10 | generation、unknown、rollback、observable |
| OS-16 | Home/Hub/Profile/Review/Stats 统一读 Due repository | OS-15/OS-13 | 计数和实际消费一致 |
| OS-17 | 全 Legacy mutator write intent/fence | OS-02 | writer matrix 全覆盖，普通写无漏口 |
| OS-18 | authority owner transaction + catalog journal mirror | OS-17 | 无 dual-active；mirror 可重放 |
| OS-19 | W8 full driver、用户策略、resume/rollback/forward recovery | OS-18/OS-07 | 完整 fixture Saga 和故障注入 |
| OS-20 | Browser 全 filter、route、mutation | OS-03/OS-14/OS-16 | Official 不回退 Legacy |
| OS-21 | Stats/forecast/retention 与 Official media | OS-16/OS-20 | 真 0 与 unavailable 区分 |
| OS-22 | Android turna-migration-v1 importer | OS-02/OS-19 | staging、checksum、安全校验、pending migration |
| OS-23 | diagnostics/deep-link route guard、Composition 启动顺序 | OS-03/OS-15/OS-19 | release 不能直达 internal pages |
| OS-24 | 修复全量测试、analyze、diff、golden、native/build | OS-00–23 | 自动化门禁全绿、干净 APK/hash |
| OS-25 | release 真机矩阵、证据归档、最终文档同步 | OS-24 | 唯一 RC 和最终 cutover receipt |

### 9.1 OS-01 必须先建立的 red tests

建议新增或扩展：

- test/application/course_provider_official_scope_test.dart；
- test/application/course_scope_codec_migration_test.dart；
- test/views/courses/course_management_official_scope_test.dart；
- test/views/anki/anki_import_navigation_contract_test.dart；
- test/application/anki/anki_exact_source_uninstall_test.dart；
- test/application/anki_official/official_first_visibility_saga_test.dart；
- test/application/anki_official/official_reimport_contract_test.dart；
- test/application/anki_official/official_formal_review_fidelity_test.dart；
- test/application/anki_official/official_live_formal_review_test.dart；
- test/application/anki_official/official_review_all_coordinator_test.dart；
- test/application/anki_official/official_formal_due_repository_test.dart；
- test/application/anki_official/official_owner_transition_test.dart；
- test/application/anki_official/official_legacy_write_fence_matrix_test.dart；
- test/application/anki_official/official_browser_stats_product_route_test.dart；
- test/application/migration/turna_migration_import_test.dart；
- test/routing/official_diagnostics_release_guard_test.dart。

若仓库已有等价测试文件，扩展现有文件，避免重复测试套件；但必须覆盖这些行为。

### 9.2 任务完成标记规则

某个 OS 任务只有同时满足以下条件才可标完成：

1. 生产调用点已切到新实现；
2. 旧平行调用点已删除或明确只用于 Legacy/HOLD；
3. 单元/集成/架构 guard 通过；
4. recovery/error path 有测试；
5. 文档没有提前勾最终 DoD；
6. 没有新增 analyze 问题；
7. 不依赖下一任务替它修正确性。

---

## 10. 故障注入与恢复矩阵

一次性收口不能只测 happy path。

| 场景 | 注入点 | 重启/恢复后的唯一允许结果 |
|---|---|---|
| 新导入 | collection import 前 | 无 source、无 course entry |
| 新导入 | collection import 后、projection 前 | staging source；不可见；可 resume/cancel |
| 新导入 | projection index 中途 | staging generation 不可见；旧 active generation 不变 |
| 新导入 | manifest 后、course active 前 | reconciler forward commit 或安全 rollback |
| 新导入 | course active commit 中 | 同事务全成或全不成 |
| reimport replace | 删除旧 collection 前 | 旧 source 仍 active |
| reimport replace | 新版本验证失败 | 旧 active generation/调度保留 |
| review | render 中 | recoverable error；不得评分 |
| review | showAnswer 后、answer 前 | snapshot/token 保持一次有效 |
| review | answer RPC 成功、UI 回调丢失 | refresh current；不得重复 mutation |
| review | source A 失败 | Review All 显示 A 失败并继续 B；总结果非成功 |
| due | 六集合任一 reader 失败 | unavailable/stale snapshot；不猜 count |
| due | 旧 refresh 晚返回 | generation 检查丢弃旧结果 |
| W8 | backup 前 | Legacy/open，Official 非 owner |
| W8 | freeze 后、commit 前 | frozen；resume 或有收据 rollback |
| W8 | owner commit 中 | CourseDB 事务全成或全不成 |
| W8 | CourseDB commit 后、catalog mirror 前 | officialOnly；forward recovery mirror |
| W8 | projection smoke 失败 | Official owner 不回退；进入 recoveringForward |
| uninstall | collection note 删除失败 | pendingCleanup；目录不假装已完成 |
| uninstall | projection 清理失败 | pendingCleanup 可重试；其他 source 不受影响 |
| migration zip | checksum/zip-slip/版本失败 | 零写入 |
| migration zip | 非 Anki 数据应用中断 | staging rollback；零半恢复 |
| migration zip | Anki 行写入后 | legacyPendingMigration；Legacy scheduler 不激活 |

每个注入点必须有确定的 state、error code 和用户安全文案，不能只 catch 后打印日志。

---

## 11. 测试和验证总矩阵

### 11.1 领域/数据库

- CourseScope codec 正反序列化和旧值迁移；
- CourseDatabase 20→21、fresh create、downgrade/reseed；
- Official catalog schema 8→9 兼容，以及 CourseDatabase 20→21 backup/restore；
- owner transition CAS、unique active transition；
- write fence/token；
- projection generation commit；
- migration zip transaction。

### 11.2 应用层

- import plan 全组合且零 Legacy fallback；
- source/course identity 完整 round-trip；
- live current、answer token、reorder/reinsert；
- Review All 多来源和混合 owner；
- 六集合 Due；
- W8 full Saga；
- Browser filter；
- Stats/forecast；
- reconciler repair executor；
- uninstall/pending cleanup。

### 11.3 Widget/UI

- 顶部显示当前课程名称；
- 课程管理唯一 active；
- Official 不出现在语言正课；
- 导入完成三按钮语义；
- Fidelity question/answer；
- Review All 来源进度和错误；
- Undo/Redo/Bury/Suspend；
- unavailable due/stats；
- diagnostics deep link 被挡；
- 大字体、暗色、返回栈。

### 11.4 架构 guard

- Official application 不 import Legacy writers/views；
- CourseProvider 不出现 Official sourceId split first；
- production review 不调用 stripHtml 构造 fidelity；
- Official formal review 不实例化 Legacy assembler；
- Due consumer 不读 static HomeDue maps；
- router 不读 legacy_anki_migrations 决定 owner；
- release route 必须有 diagnostics guard；
- 主分支不存在 ohos/ 和 OHOS fork patch；
- Android release ABI 只有 arm64-v8a。

### 11.5 最终命令顺序

必须按顺序执行；失败即修复后从该层和受影响的后续层重跑：

    dart format --output=none --set-exit-if-changed lib test
    flutter pub run build_runner build --delete-conflicting-outputs
    flutter analyze
    flutter test test/application/course_provider_official_scope_test.dart
    flutter test test/application/course_scope_codec_migration_test.dart
    flutter test test/application/anki/anki_exact_source_uninstall_test.dart
    flutter test test/application/anki_official/official_live_formal_review_test.dart
    flutter test test/application/anki_official/official_formal_review_fidelity_test.dart
    flutter test test/application/anki_official/official_review_all_coordinator_test.dart
    flutter test test/application/anki_official/official_formal_due_repository_test.dart
    flutter test test/application/anki_official/official_owner_transition_test.dart
    flutter test test/application/anki_official/official_legacy_write_fence_matrix_test.dart
    flutter test test/application/migration/turna_migration_import_test.dart
    flutter test test/routing/official_diagnostics_release_guard_test.dart
    flutter test --exclude-tags golden --reporter compact
    flutter test test/golden/course_tree_golden_test.dart
    flutter test test/golden/play_hub_golden_test.dart
    git diff --check
    flutter build apk --release --split-per-abi --target-platform android-arm64

在运行上述验证前，先对显式 touched Dart 文件执行会写入的 dart format。若建议测试文件最终合并进其他文件，命令清单必须在施工结束时改成真实路径，禁止保留不存在的候选命令。

### 11.6 全量测试政策

- 目标是全绿，不接受“Anki 无新增失败但仓库仍红”作为最终一次性交付；
- 当前 Official catalog schema 9 两项新增失败必须修；
- wetland palette、AI config dispose、dark mode provider 三个既有失败一并关闭；
- test/BASELINE.md 只能记录外部不可控缺陷，不能记录本次可修复失败；
- flaky 必须通过重复运行定位，不能简单 rerun 到绿；
- 任意故障注入测试必须串行可复现。

---

## 12. 真机一次性验收脚本

使用同一个最终 release APK、同一个 APK hash、一个干净安装设备和一个升级安装设备。

### 12.1 干净安装

1. 冷启动，确认 internal routes 不可见；
2. 打开语言正课，确认零 Anki Section；
3. 导入 Basic source A，完成页点“完成”，仍停留语言正课；
4. 课程管理看到 source A，选中后只显示 A Sections；
5. 导入 Cloze/复杂模板 source B，点“查看牌组”，高亮 B；
6. 切换 A/B/语言正课，当前课程名和内容始终一致；
7. Review deck 验证 fidelity、Again/Hard/Good/Easy；
8. Again 后验证学习卡重新插入，不 stale；
9. Undo、Redo、Bury、Suspend；
10. Review All 同时消费 A/B；
11. Browser filters、Stats/forecast、Media；
12. same/replace/append reimport；
13. 精确卸载 A，确认 B 和语言正课完整；
14. backup/restore 后重复切换和 review；
15. 强杀恢复 import、review、uninstall。

### 12.2 升级安装

准备包含以下旧状态的安装：

- courseScope 为空；
- Legacy anki:<importId>；
- 正确的旧 Official anki:<fullSourceId>；
- 错误的 anki:src；
- courseOrder 含失效/重复/截断项；
- 一个 cleanLegacy W8 fixture；
- catalog schema 8/9。

升级后验证：

- 偏好 repair 幂等；
- 多源歧义不随机选择；
- Legacy 数据仍在；
- 用户确认前不切 owner；
- W8 crash/resume；
- 备份恢复不降 schema；
- 不产生 Legacy 新写。

### 12.3 迁移包

- 合法 turna-migration-v1；
- checksum 篡改；
- zip slip；
- 缺媒体；
- 版本过新；
- 空间不足；
- 强杀恢复；
- Anki 行进入 pending，不进入 Legacy review queue。

---

## 13. 最终证据包

最终一次性交付必须生成：

    docs/official-anki-migration/archive/artifacts/cutover-once/
      baseline.txt
      toolchain.txt
      main-git-revision.txt
      native-git-revision.txt
      analyze.txt
      targeted-tests.txt
      full-tests.txt
      golden-tests.txt
      diff-check.txt
      android-arm64-build.txt
      apk-sha256.txt
      so-sha256.txt
      source-archive-sha256.txt
      device-clean-install.txt
      device-upgrade-install.txt
      device-migration-package.txt
      final-receipt.md

证据规则：

- 日志来自最终 commit，不拼接旧构建结果；
- 每个文件写命令、开始/结束时间、exit code；
- APK/so/source archive hash 相互关联；
- 真机记录写设备型号、Android 版本、ABI、安装方式；
- 失败后重建必须替换整套受影响证据；
- 不提交用户数据、牌组内容、API key 或绝对隐私路径。

---

## 14. 回滚和发布策略

### 14.1 发布前

- production 仍 NO-GO；
- 不修改商店版本；
- 不删除 Legacy；
- 发现 blocker 直接修同一集成变更。

### 14.2 RC 真机失败

- 不回退到 Legacy 新写；
- 禁用/暂停 Official import 只能显示不可用，不能 fallback；
- 已是 Official owner 的来源保持 Official，并显示修复错误；
- 使用 transition/reconciler forward recovery；
- 保留失败 APK/hash/日志，不覆写成通过。

### 14.3 发布后灾难恢复

本次必须准备但不自动触发：

- source 级 backup；
- owner transition receipt；
- Official collection repair/reopen；
- projection rebuild；
- pending cleanup retry；
- migration package re-import；
- 明确的人工授权入口。

灾难恢复不得把有 Official mutation 的来源静默切回 Legacy scheduler。

---

## 15. 工作量与“一次性”解释

按一名熟悉仓库的工程师估算，不包含正式 release 观察期：

| 工作面 | 规模 | 粗略人日 |
|---|---:|---:|
| 基线、red tests、DB v21 | M | 2–4 |
| CourseScope/课程目录/导航/卸载 | L | 4–7 |
| import Saga/reimport/向导 | XL | 6–10 |
| live fidelity review/Review All | XL | 8–14 |
| 六集合 Due | L | 3–6 |
| W8 fence/owner/recovery | XL | 9–16 |
| Browser/Stats/Media | L | 5–8 |
| migration package/OHOS evidence | L | 4–8 |
| 全量修复、构建、真机、证据 | L | 4–8 |

合计约 45–81 人日；需要 native lossless scheduling migration 或 OHOS sunset 维护分支时另加。

“一次性做完”表示一个不可拆分的验收目标，不表示工作量消失。即使内部多人并行或有多个检查点，最终只交付一个全部通过的 RC。

---

## 16. 明确不做

- 不恢复主分支 ohos/；
- 不在观察期前删除 Legacy importer/scheduler/schema；
- 不建设 AnkiWeb；
- 不增加自由组合 feature flags 解决 owner 问题；
- 不把 Official HTML 转纯文本后称为 fidelity；
- 不用 count 近似替代 due card IDs；
- 不让启动 census 自动迁移真实用户；
- 不对无法无损映射的 Legacy schedule 静默近似；
- 不伪造真机、用户数量、release 观察或 OHOS sunset 证据；
- 不以任何中间检查点替代 OS-25 总验收。

---

## 17. 一次性交付 Definition of Done

以下所有“代码/自动化”项必须在同一次施工中完成；“外部事实”项可以保持 HOLD，但必须明确阻止“迁移全部完成”的表述。

### 17.1 代码和数据模型

- [ ] CourseDatabase v21 fresh/create/upgrade/backup/restore 全通过；
- [ ] CourseScope v1 codec 取代散落字符串解析；
- [ ] 旧 courseScope/courseOrder repair 幂等；
- [ ] anki_course_sources 是课程目录与 owner 权威；
- [ ] transition/write fence/visibility 同库提交；
- [ ] Official catalog journal 可重放但不决定生产 owner。

### 17.2 课程与导入

- [ ] 语言正课不出现任何 Legacy/Official Anki Section；
- [ ] 一个 Official source 对应一个可见 CourseEntry；
- [ ] 完整 profileId/sourceId 贯穿 entry、scope、review、stats、backup 和 uninstall；
- [ ] 当前 scope 始终对应唯一 active course card；
- [ ] 导入“完成/查看牌组/立即学习”语义正确；
- [ ] import/publish/cancel/强杀不留下可见半成品；
- [ ] same-hash/replace/append reimport 通过；
- [ ] 删除 source A 不影响 B，不因共享 note 误删；
- [ ] import screen 不再持有 owner/transaction 规则。

### 17.3 正式复习与 Due

- [ ] Official rendered HTML/CSS/media/MathJax/typed answer 未被 strip；
- [ ] 页面由 Scheduler current 实时驱动；
- [ ] answer token/generation 防重复和 stale；
- [ ] Again 重排与 learning reinsert 通过；
- [ ] Review All 覆盖 snapshot 中全部来源；
- [ ] Legacy/Official 混合 owner 选择正确 ledger；
- [ ] Undo/Redo/Bury/Suspend 写 Official engine；
- [ ] 六集合 Due 完整且 placement/engine/evidence 缺失 fail-closed；
- [ ] Home/Hub/Profile/Review/Stats 读同一 repository；
- [ ] 所有 count 与实际可复习集合一致。

### 17.4 Legacy 迁移

- [ ] 所有 Legacy mutator 声明 write intent；
- [ ] frozen 后普通 Legacy writer 全部拒绝；
- [ ] migration cleanup/rollback token 有严格 phase；
- [ ] owner commit 不存在 dual-active；
- [ ] catalog mirror 失败走 forward recovery；
- [ ] W8 用户未确认策略不能切 owner；
- [ ] 每个 phase crash/resume/rollback 测试通过；
- [ ] startup census 只发现，不自动迁移。

### 17.5 Parity、迁移包和路由

- [ ] Browser/Stats/Media 对 Official 来源可达且不回退 Legacy；
- [ ] Browser 全 filter 生效；
- [ ] Stats 真 0、unavailable、forecast、retention 语义正确；
- [ ] Android turna-migration-v1 安全导入完成；
- [ ] 导入的 Anki 行只进入 legacyPendingMigration；
- [ ] internal/diagnostics route 在 release 不能 deep-link 绕过；
- [ ] 主分支保持无 OHOS product target/fork patch。

### 17.6 自动化和产物

- [ ] flutter analyze 零退出；
- [ ] 定向测试全绿；
- [ ] 全量非 Golden 全绿；
- [ ] Golden 全绿；
- [ ] git diff --check 通过；
- [ ] native submodule 干净且 commit 已记录；
- [ ] arm64 release APK 从最终 commit 重建；
- [ ] APK/so/source archive hash 已归档；
- [ ] clean-install 和 upgrade-install 真机矩阵通过；
- [ ] 主计划、receipt、README 与最终证据一致。

### 17.7 外部事实 HOLD

- [ ] 已确认无外部 OHOS 用户并获得书面豁免，或 sunset export 已真实发布并验证；
- [ ] 存量真实用户来源全部完成处置；
- [ ] Legacy 新写入连续一个正式版本为 0；
- [ ] W9 分波物理删除和 schema drop 已另行验收。

如果 17.1–17.6 全部通过、17.7 尚未全部通过，唯一允许的状态是：

> Official Anki Android 一次性代码收口已形成生产候选；OHOS product target 已退役；Legacy 保持停止新写和观察期，W9 继续 HOLD。

只有 17.7 也全部通过，才能写“自研 Anki 已完成退役迁移”。


---

## 18. 一次性施工状态（2026-08-25，OS-00–OS-24 host 收口）

> 状态：**host/自动化门禁全绿；真机矩阵与外部事实未验收；整体仍为 Official Anki 迁移中 / NO-GO**（§17.6 剩真机证据项，§17.7 全部 HOLD）。允许的表述：一次性代码收口已形成生产候选，尚未真机验收。

### 18.1 OS 任务账本勾选（host 证据口径）

| ID | 状态 | 证据 |
|---|---|---|
| OS-00 | ✅ | cutover-once/baseline.txt + toolchain.txt + revisions |
| OS-01 | ✅ | 16 个新测试文件（§9.1 清单全量落地或等价扩展），红→绿随实现推进 |
| OS-02 | ✅ | v21 DDL（owner 列/transitions/in-flight 索引/repair journal/legacy_pending_migrations）；schema_migration_test v20→v21、fresh、v22 降级 |
| OS-03 | ✅ | CourseScope codec v1 + 启动幂等偏好修复（locator 顺序：DB open→repair→fence 加载→Provider） |
| OS-04 | ✅ | CourseCatalog（authority 优先 + manifest 兜底）；builtin 双重排除 Legacy/Official section |
| OS-05 | ✅ | 课程管理唯一 active + 精确删除对话框（shortId+卡片数）+ highlightWire；顶栏课程名切换器 |
| OS-06 | ✅ | 卸载传完整 sourceId；`anki_exact_source_uninstall_test`（-s 边界、兄弟隔离） |
| OS-07 | ✅ | official-first 导入：authority staging 起始、`publishFromProjection` 后 commit-last active（§6.3） |
| OS-08 | ✅(host) | reimport 走既有 catalog hash 幂等 + authority upsert 稳定 course_id；真机 reimport 矩阵未跑 |
| OS-09 | ✅(host) | 向导完成页三动作分流（完成保持原课程/立即学习/查看牌组高亮）；导入提交不再抢 scope |
| OS-10 | ✅ | `FormalReviewCardSnapshot`（generation/inQueue/answerToken）+ live session contract |
| OS-11 | ✅ | fidelity-first 渲染（markup→Fidelity，纯文本才 Flip）；`official_formal_review_fidelity_test` |
| OS-12 | ✅ | `OfficialFormalReviewLiveQueue`：answer 后按 Scheduler 实时队列原地重建 items；Again 重插、快照失效测试 |
| OS-13 | ✅(host) | Review All 聚合全部 Official 来源（并集 allowed + openDueDeck + per-source 失败上报）；真机跨源矩阵未跑 |
| OS-14 | ✅ | Redo/Bury/Suspend 头部动作接真实 ledger；mutation 后 live 队列刷新；answerAndConfirm 单飞既有 |
| OS-15 | ✅ | `OfficialFormalDueRepository` 六集合（known/unknown/unavailable、generation、rollback、retired 真实 reader） |
| OS-16 | ✅ | `OfficialAnkiHomeDue` 降为薄 facade；officialDue 派生不可写；HomeDue 静态 map 删除 |
| OS-17 | ✅ | `LegacyWriteFence`：AnkiNoteDao 全 14 mutator + ledger undo；cleanup token 一次性、rollback 严格 phase |
| OS-18 | ✅ | 权威 owner 事务（commitOwnership 同库原子）；catalog 为 journal mirror；无 dual-active 测试 |
| OS-19 | ✅(host) | saga freeze=真实 fence CAS、权威先行切换；driver resume/rollback 入口；真实用户迁移仍需单独授权 |
| OS-20 | ✅ | Browser/Stats 官方来源按钮可达（完整 sourceId 路由，既有 Official 分支） |
| OS-21 | ✅(host) | Stats 语义既有（unavailable 与 0 区分）；media 走 Official resolver 既有；真机验证未跑 |
| OS-22 | ✅ | `TurnaMigrationImporter`（magic/zip-slip/checksum/容量 fail-closed、事务、Legacy 行只入 pending）+ 设置页独立入口 |
| OS-23 | ✅ | `DiagnosticsReleaseGuard`（6 内部路由 release+深链阻断；diagnostics dart-define opt-in）+ locator 启动顺序 |
| OS-24 | ✅ | analyze 0 error（88 w/i）；全量 1825/0；golden 4/4；diff-check 0；native 重建+verify；arm64 APK 55.8MB |
| OS-25 | ◐ | 证据已归档（cutover-once/）；**真机矩阵未执行**（无设备会话），final-receipt 未生成 |

### 18.2 与 §17 DoD 的对齐

- 17.1–17.6 自动化项：全部通过（见 18.1 与 §1.1 表）。
- 17.6 真机两项（clean/upgrade 安装矩阵、真机 hash 收据）：**未执行**——按 §4.4 设备不可用政策保留未勾，不以 widget test 替代。
- 17.7 外部事实四项：全部保持 HOLD（OHOS 用户事实未知、存量用户处置未发生、Legacy 零新写观察期未开始、W9 未另行验收）。

### 18.3 诚实边界（本轮明确未做/未验）

1. 真机矩阵（§12 全部场景）与升级安装（§12.2 旧偏好态矩阵）——待设备会话。
2. 混合 Legacy+Official 的 Review All 聚合仅覆盖 Official 来源并集；Legacy 来源仍按单一牌组入口复习（D5 混合期语义，待 R4 真实迁移收敛后消除）。
3. W8 真实用户 cutover 未执行（§4.3 外部事实）；census/reconciler 未对真实库跑批。
4. OHOS sunset / 豁免证据未产生（R7-1 二选一未决）。
5. final-receipt.md 未生成（真机证据缺失，拒绝拼装半套收据）。
6. §9.1 建议清单中 `course_management_official_scope_test` / `anki_import_navigation_contract_test` / `official_first_visibility_saga_test` / `official_reimport_contract_test` / `official_browser_stats_product_route_test` 五个建议文件名未独立落地：对应行为分别由 provider/catalog 层测试（course_provider_official_scope、exact_source_uninstall）、既有 saga/orchestrator 测试（official_anki_import_orchestrator、official_legacy_source_migration_saga）与真机矩阵项覆盖其 host 侧；导入完成页三动作与 Browser/Stats 入口的 widget 级断言待真机矩阵补足（§18.3-1 同批）。
