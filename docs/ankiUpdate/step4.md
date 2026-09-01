# Step 4 详细说明：v2 导入→课程树链落码（与 v1 并存）

> 上游文档：[README.md](./README.md)（总目标与六步计划）；前置：[step3.md](./step3.md)（已完成：op 41/42 落码、契约 1.12、全链路调用面与假引擎 `configStore` 就绪）。
> Step 4 只做一件事：**把 ADR 0043 的 v2 全生命周期链（导入→决策→视图→复习挂载→删除）在 flag 后落码，真机强杀矩阵全绿**。v1 一行不改、一路不删；flag 决定新导入走哪条链。
> 原则：v2 路径对旧表**零写入**（守卫测试锁死）；每一段幂等（K 矩阵的答案必须是代码，不是文档）；测试贴真实挂载点（D9）。
>
> **施工状态（2026-09-01）**：任务 A/B/C 的 host 侧（代码 + 严格假引擎测试 + 零写入守卫）已全部落码并绿；**C3 真机强杀矩阵与 C4 大库定标未跑**（需 vivo 真机 + 大夹具，本机不可达），验收清单如实标注。详见文末收据与「K1–K14 真机矩阵映射表」。

---

## 0. 范围围栏（先说清楚不做什么）

| 不做 | 归属 |
|---|---|
| 删旧代码、v1 路径退役、guard 锁门 | Step 6 |
| 存量用户切换（搬三样短事务、v1 数据迁 v2） | Step 5 |
| catalog 18→5 / course.db 旧 anki 表的**物理删除**（Step 4 只新增 v2 结构，旧表停写不删） | Step 5/6 |
| usn-diff 只读 op——仅当 C3 强杀测试证明 op 40（现为 stub）不足以支撑 K2 时才占编号 43，回本文件收据定案 | 本步条件项（结论见 §K2） |
| 课程切换异常的 v1 热修（若等不到 v2，独立小修，不进本步） | 独立小修 |

Step 4 的产出是：**v2 链全生命周期在 `v2ImportChain` flag 后可用 + K1–K14 真机矩阵绿 + Q3/Q4/Q5 定案 + v1 零回归**。

---

## 任务 A：施工前置定案（Q4 flag、Q5 偏好清单、D5 明细落表）

### A1 · Q4：并存 flag 的命名与灰度边界（定案 ✅ 已落码）

- **命名**：`OfficialAnkiFeatureFlags.v2ImportChain`（`lib/application/anki_official/official_anki_feature_flags.dart`）+ `allowsV2ImportChain` getter。**不建第二套 flag 矩阵**——遵守该类已有的纪律注释（「Product pause is cutoverEnabled — not a second flag matrix」），v2 只加一个布尔位。
- **管什么**：只管两个分叉面——
  - **写侧**：commitLive 之后的「投影发布」段。v1 现状 = 投影器写 `official_anki_projection_index`/`manifest` → `UnifiedAnkiImportOrchestrator.publishFromProjection` 写 placements/presentations；v2 = 配置区写（op 42）+ 账本 5 表 + 视图重建。分叉落码在 `anki_import_controller.dart` 的 `_commitOfficial`（v1 流程的编排点，saga.commitLive 之前整体切走）与 `official_first_service.dart`（v2 跳过 `recordMigration` 与 metadata 关联行），**不在** `migration/official_anki_production_router.dart`——那是 Legacy↔Official 的存量路由，只读、与 v1/v2 无关。
  - **读侧**：课程树读面 = `CourseProvider` + `projection/official_anki_lesson_card_index.dart`（复习链的课时→卡映射，读的就是投影 index）+ 练习投影读者。v2 里这个读面整体切到视图表。
  - 复习队列、答题、渲染、引擎会话链两代**共用**（README「不动」清单资产）；它们对投影表的间接依赖（lesson index）已划入读侧分叉面。
- **默认值**：构造器默认 `false`；dev/QA 构建经 `copyWith` 打开；`productionAndroid` 常量保持 `false`，直到 C3 真机矩阵全绿 + 一个内部 release 观察期后再翻 `true`（翻的动作 = 改常量 + 本文件收据记录日期与证据）。
- **回退条件**（任一触发即翻回 `false`）：v2 链在真机复现任一 K 场景不可自愈（视图无法重建 / 配置区决策损坏且识别器重建议失败 / 出现无主且不可见的卡）；修复中心出现 v2 来源的 quarantine 记录且无法自动收敛。
- **回退语义**：v2 已导入的来源**继续可学**——账本行（`chain='v2'` 标记，catalog v13）、配置区决策、视图表都留着，读路径兼容两代数据（flag 关时读面回落 v1，v2 视图行不可见但数据无损）；仅新导入回 v1。这是「旧数据不受影响」的对称面：flag 只路由新写入，不销毁任何已有事实。

### A2 · Q5：K14 偏好写穿清单（定案；落码在任务 B/C 各挂点）

- **必须写穿**（提交时机即持久化，不等进程正常退出）：onboarding 完成态、课程 scope 选择、`v2ImportChain` 若做运行时开关则其自身、课程启用/引入状态、导入向导中途态（staging 路径）。
- **可容忍丢失**：纯 UI 偏好（主题、页签位置、动画偏好）。
- **前置动作**（host 侧静态核验已完成，真机定位待 C3）：Step 1 发现 #5 只证明了「强杀后 prefs 丢失」的现象，未定位机理（写入时机 vs 持储损坏）。静态核验结论（2026-09-01）：
  1. **onboarding 完成态 flag 不存在**——进入首页由 `CourseReadyGuard` 门在 `CourseProvider.isLoaded` 上，本就无「等退出才写」的偏好（清单该项在现状代码里无可修对象）；
  2. **课程 scope 已是提交即持久化**（`CourseProvider._persistScope` await `prefs.setString`，无批处理层），且 v2 叠加了第二持久层：`setScope` 同步写配置区决策键 `turna.course.scope`（随 collection.anki2 备份走，强杀丢 prefs 时由决策键兜底恢复——落码在 B6）；
  3. **课程启用/引入状态本就是持久账本**（`anki_card_introduction_states`，写库非 prefs），不受 K14 影响；
  4. 导入向导中途态 = attempt 行 `staging_path`（catalog 持久），B4 census 据此恢复。
  真机复现定位（写入时机 vs 持储损坏的机理判别）仍归 C3 K14 行；若定位结果与上冲突，以定位证据修订并回收据。

### A3 · D5 明细落表：course.db anki 表 v2 去向（已逐张核对 ✅）

以 `lib/data/course_database.dart`（**kSchemaVersion = 23**，v23 新增视图表；全文件建表已核对）现状盘点：**course.db 内 anki 相关表实测 13 张**；ADR D5 所称「约 20 张」里的 `anki_notes`/`anki_cards_meta`/`anki_notetypes` 等 Legacy 内容表**不在 course.db 的 v2 关注集内**（它们是 drift 声明表、属 Legacy 残件）——`anki_notes`/`anki_cards_meta` 等在 `course_catalog.dart` 仅做兼容读；写侧已随 doc 38 P1-B/C 删除。ADR 的口径偏差已在施工定案时修正；Legacy 附加库本身归 Step 6 处置。

| course.db 现表 | v2 去向 |
|---|---|
| `official_anki_projection_index` / `official_anki_projection_manifest` | → 被新视图表取代（D3「两张合一张」；Step 6 删） |
| `anki_course_card_placements` / `anki_card_presentations` | → 配置区（D2 呈现与放置决策；Step 6 删） |
| `anki_practice_projections` | → 并入视图表（可重建） |
| `anki_decks` / `anki_import_issues` | → 删（Collection 派生 / attempt 吸收；Step 6 删） |
| `anki_course_sources` / `anki_owner_transitions` / `course_scope_repair_journal` / `anki_import_jobs` / `legacy_pending_migrations` | → 删（账本归 catalog `anki_sources`；对账/修复中心随副本退役；Step 6 删） |
| `anki_card_introduction_states` | **保留**（产品侧非 anki 事实：课程引入状态，D5；v2 只读不写新行——引入由课时完成时懒写） |
| **新增** `anki_course_tree_view`（v23） | **v2 唯一视图存储**（D3 物化视图，无独立状态、可 DROP+REBUILD；已加入降级 wipe 清单） |

---

## 任务 B：v2 链落码（核心，✅ host 侧全部落码）

全部新代码在 `lib/application/anki_official/v2/`（8 个文件）+ 四个既有挂载点的最小分叉。

- **B1 决策进配置区（D2 消费者）✅**：`v2/official_anki_v2_config_keys.dart`（键族与 JSON 编码：`turna.import.mapping.<sourceId>` / `turna.course.placement.<deckId>` / `turna.course.scope`，值恒 JSON object，损坏读取按 missing）+ `v2/official_anki_v2_decision_store.dart`（op 41/42 消费者）。晋升 = 配置区写 + attempt 状态推进，**两步各自幂等**（K10）；同值重放为 no-op（`v2/official_anki_v2_import_service.dart` 的 commit 序列）。
- **B2 账本写入（D4）✅**：catalog **v12→v13**（`anki_sources.chain`（'v1'|'v2' 路由标记）+ attempt 吸收 receipt 三列 `receipt_note_ids_json`/`receipt_scope_json`/`pre_import_usn`）。v2 路径只写 5 张——`anki_sources`、`anki_import_attempts`（receipt 吸收，不再写 `anki_import_attempt_notes` 侧表）、`anki_maintenance_jobs`、`anki_maintenance_leases`、`anki_source_cards`（`OfficialAnkiSourceDao.upsertCardBatch`/`deleteSourceV2` 等五表专用方法）。**对其余 13 张零写入**，守卫测试锁死（statement 级 update 钩子，见 C2）。
- **B3 视图存储与重建（D3/D7）✅**：course.db **v22→v23** 新表 `anki_course_tree_view`（14 列，PK(source_id, card_id)，lesson/section 索引）；`v2/official_anki_v2_view_store.dart`（唯一读写点）+ `v2/official_anki_v2_view_rebuilder.dart`。重建 = **单事务 DELETE+INSERT 原子换页**（任一时刻读者见完整旧视图或完整新视图；中途强杀回滚旧视图，K11「无状态、重跑即收敛」的结构保证）；输入 = Collection（op 8 牌组树，经会话引擎 worker isolate RPC——主线程零 native 忙等，K13）+ 配置区决策（op 41）+ 账本（`anki_source_cards` + active v2 sources）；重建期间「重建中」占位 = 进程内 `ValueNotifier`（不落库，视图无独立状态）；可取消（批间令牌 + 引擎取消通道）；内置 Turkish 课程不经本表、天然不受影响（K11）。启动收敛：`OfficialAnkiStartupRecovery` 见 v2 active source 即入队 `v2_view_rebuild` job（K3 重启整建），job 由维护 runner 驱动。
- **B4 staging census v2（K1）✅**：`v2/official_anki_v2_pending_imports.dart`——纯读模型，按 staging 目录完整性三级分流：`resumable`（目录在且 collection.anki2 存在 → 直接进 preview）/ `rebuildStaging`（目录在库缺 → 重建 staging）/ `gone`（目录没了 → 重新选包入口）。live 零写入不变式继承 ADR 0042；v1 的 `official_anki_pending_imports.dart` 原样保留（v2 语义不改 v1 行为）。
- **B5 删除轴 retiring 序列（D6/K6）✅**：`v2/official_anki_v2_retire_service.dart` + 维护 kind `v2_source_delete`/`v2_view_rebuild`（`official_anki_lifecycle_models.dart`）。①账本**单事务**标 `retiring`（新 wire 值，`anki_sources.state` 无 CHECK 约束、append-only 安全）并入队删除 job + 视图定向删行（**用户视角即刻移除**，无需引擎；读面的账本 state 过滤双保险）；②worker 幂等执行引擎删除（op 32 按 `anki_source_cards` 所有权清单 5000/批，缺卡无害）；③终删账本行（`deleteSourceV2` 只删五表中有行的三张）+ 配置区映射决策清理 + 视图重建；④媒体 GC / VACUUM 走既有 maintenance job（mediaGc/compactCollection/compactCatalog）。任何一段强杀 → 重启 `runPending` 由 job 表驱动续跑（引擎缺席 → job 抛错进 retry_wait **保活**，绝不把未删引擎的 source 标完成），source 停 `retiring` 且修复中心可见——**不产生无主且不可见的卡**。Step 1 发现 #3 的根因（跨库多步状态机）就此被单线 job 序列取代。卸载入口分叉：`AnkiDeckManager.uninstall` 见 chain='v2' 即走 retiring 序列。
- **B6 课程树读路径与切换（Step 1 发现 #2 的 v2 答复）✅**：读面分叉四处——`OfficialAnkiCourseEntry.lookupActiveSectionIdsAsync`（视图 section 并入，flag 关为空集）、`CourseProvider.load`（v1 壳 + `v2/official_anki_v2_course_read.dart` 视图壳合并；v2 section 壳自带 units/lessons，免 drift 装载）、`CourseCatalog.load`（视图 + 账本 active 合成目录条目，retiring 即刻消失）、`OfficialAnkiLessonCardIndex.resolveForLesson`（v2 课时 → 视图卡映射；非 v2 课时回落 v1 投影 index——两代并存）。课程切换 = `CourseProvider.setScope` 写穿两层（prefs + 配置区决策键 `turna.course.scope`）+ 视图过滤，不再有跨库状态机。

---

## 任务 C：观测、测试与定标（D8/D9/Q3）

- **C1 文件日志（D8，发现 #4 的答复）✅ host 侧**：现有 `LogCapture`（`transparency_log.jsonl` 滚动落盘，1MB×3 轮转）此前收不到 Anki 路径——全部走 `debugPrint` 绕过了它。新增 `lifecycle/official_anki_file_log.dart`（`officialAnkiFileLog` 系列助手：控制台 + 文件双写，只增不减）并接入：启动恢复（`official_anki_startup_recovery.dart` 全部关键行）、staging 管理（`official_anki_staging_manager.dart`）、维护任务（`official_anki_maintenance.dart`）、v2 全链（commit 窗口开/关、视图重建、retiring 各段）。修复中心「导出诊断」在 storage audit 快照后追加最近 120 条文件日志（`official_anki_repair_center_page.dart`）。**不依赖厂商 logcat**；storage audit 快照保留。
- **C2 贴真实挂载点的测试（D9）✅ 31 用例全绿**：`test/application/anki_official/v2/` 六个文件——严格假引擎（`configStore`/`deckTree`/`suspended`/`deleteCardsCallCount` 全就绪）常驻用例：晋升幂等与配置区损坏韧性、**K10 单事务**（同值重放零副作用）、视图重建幂等/原子换页/取消/占位/retiring 排除、retiring 各段幂等与引擎缺席保活、census 三级分流、读面 flag 开关分叉（挂载点 = `OfficialAnkiLessonCardIndex`，复习页/练习中心/资料页三入口共用的 P0 解析面）、**零写入守卫**（catalog statement 级 update 钩子断言只命中五表；course.db 同钩子断言只命中视图表 + 旧表净状态为空）。
- **C3 真机强杀矩阵（发布门禁）⏳ 未跑**：K1–K14 映射表已落（见下节），需 vivo 真机（serial `10AF9U0P9P002DJ`）+ debug/release 双跑纪律（doc 41 §16.6）逐行执行。本机（Windows host）不可达真机，属 Step 4 剩余工作。
- **C4 Q3 定标 ⏳ 未跑**：大库（10 万卡级，`gen_fixtures --large` 产包或多包叠加）冷重建 P95 实测待真机/大夹具环境；host 侧已具备测量面（重建器返回 `elapsedMillis`，修复中心导出含重建耗时行）。它是 Step 5/6 的性能门禁基线——**未定标前 flag 不得翻 true**。

### K1–K14 真机矩阵映射表（C3 执行清单；状态 = host 代码面 / 真机待验）

| # | 场景 | 代码答案（host 已验证） | 真机用例（杀点 → 重启期望） | 状态 |
|---|---|---|---|---|
| K1 | staging 导入中强杀 | attempt `staging_path` 即证据；census 三级分流（B4 测试绿） | 导入向导中途杀 → 重启修复中心见「待完成导入」，完整性过→preview，损坏→重建 staging | 代码 ✅ / 真机 ⏳ |
| K2 | commit 窗口、receipt 落库前强杀 | receipt 吸收 = import 返回后**单条 UPDATE**（窗口毫秒级）；杀于窗口内 → attempt 停 `committing`、staging 目录在（finishCommit 未执行）→ census 按意图续跑或弃置；attempt 有 `pre_import_usn` 列预留 | 杀点插在 importPackage 与 receipt UPDATE 之间（debug 构造）→ 重启无幽灵卡、意图可续 | 代码 ✅ / 真机 ⏳ / op 40 结论见下 |
| K3 | receipt 后、投影中强杀 | 视图无状态：重启启动恢复见 v2 active source 即入队 `v2_view_rebuild`（B3 测试绿） | 杀于重建中 → 重启视图整建、课程树回归 | 代码 ✅ / 真机 ⏳ |
| K4 | publish / authority 提交中强杀 | v2 无 authority 状态机：source CAS→active + 视图原子换页，重放幂等（commit 重入测试绿） | 杀于收尾 → 重启 job/重入收敛，课程树出现 | 代码 ✅ / 真机 ⏳ |
| K5 | 取消时 native op busy | 继承 v1：engine.cancel 独立控制通道；RPC 有界超时 | 取消导入 → 有界返回，staging 删除 | 代码继承 ✅ / 真机 ⏳ |
| K6 | 卸载中任意时刻强杀 | retiring 序列四段各自幂等；job 表续跑；引擎缺席 job 保活；无主且不可见的卡不产生（B5 测试 6 例全绿） | 每段杀点各一轮 → 重启收敛到终删 + GC jobs 在队 | 代码 ✅ / 真机 ⏳ |
| K7 | media GC trash 中强杀 | GC 幂等重跑（rslib trash 语义，继承 doc 41 S5） | 杀于 GC → 重启 job 重跑不误删 | 继承 ✅ / 真机 ⏳ |
| K8 | checkpoint release 中强杀 | checkpoint 体系已废（ADR 0042）；v2 无此路径 | 存量善后归 Step 5 census | 不适用（存量） |
| K9 | compact / VACUUM 中强杀 | SQLite 事务性 + job retry_wait（doc 41 S7 已实现，继承） | 杀于 VACUUM → 库可 reopen、job 重试 | 继承 ✅ / 真机 ⏳ |
| K10 | 配置区写入中强杀 | op 42 单事务（Step 3 Rust 测试绿）+ 晋升两步幂等 + 损坏读按 missing（B1 韧性测试绿） | 杀于晋升 → 重放 no-op；决策损坏 → 识别器重建议 | 代码 ✅ / 真机 ⏳ |
| K11 | 视图重建中强杀 | 单事务原子换页 + 进程内占位 + 重启整建（B3 测试绿）；内置课程不经视图表 | 杀于重建 → 旧视图完整、重启整建、Turkish 不受影响 | 代码 ✅ / 真机 ⏳ |
| K12 | 存量迁移事务中强杀 | Step 5 预告，本步不涉及 | — | Step 5 |
| K13 | 主线程长任务 ANR | 重建的 native 调用全经会话引擎（worker isolate RPC）；course.db 写经 drift 后台连接；批间可取消（B3 结构 + 测试） | 大库重建期间 UI 可交互、无 ANR dump | 结构 ✅ / 真机（大库）⏳ |
| K14 | 强杀后 prefs 丢失 | 静态核验：写穿清单各项已提交即持久（A2 四条结论）；真机机理判别待跑 | 每轮强杀后 onboarding/scope 记忆 | 代码 ✅ / 真机 ⏳ |

### K2 专项书面结论（op 40 的充分性）

**op 40 `DIFF_COLLECTION_CHECKPOINT` 不足以支撑 K2 的 receipt 重建**，证据：① 实现为恒空 stub（`native/turna_anki_core/bridge/src/ops.rs:1177-1179`，忽略请求恒返 `{cardIds: []}`）；② 其范式是 checkpoint 差分——checkpoint 体系已随 ADR 0042 废除（K8），staging-first v2 **没有 checkpoint 可 diff**，表达力缺的是「自某时点以来新增的 note/card」（usn-diff），不是 checkpoint 差分。
**但 op 43（只读 usn-diff）本步不占号**，理由：围栏条件是「仅当 C3 强杀测试证明不足才占」。v2 已把 receipt 无效窗口结构性压到毫秒级（import 返回与单条 UPDATE 之间，无中间 IO），且 catalog v13 预留了 `pre_import_usn` 数据面；窗口是否实际可被强杀命中，需 C3 真机 K2 轮的证据。若命中且 census 无法按意图续跑 → 届时占 op 43 并回本文件定案；若未命中 → 记录证据关闭该项。

---

## 执行顺序

```
A 定案（flag/偏好清单/表去向）——0.5~1 天 ✅
 └→ B1+B2 配置区消费者与账本（v2 导入闭环的最小内核）✅
      └→ B3+B6 视图与读路径（课程树从视图长出来）✅
           └→ B4 staging census → B5 retiring 删除轴 ✅
                └→ C1 文件日志 + C2 挂载点测试（随每段并行写）✅
                     └→ C3 真机强杀矩阵 + C4 定标 ⏳ 未跑 → 全绿 → flag 翻 true 决策 → Step 4 关闭，进 Step 5
```

## 验收清单

- [x] `v2ImportChain` flag 落码（默认 false，production 翻 true 前置 = 矩阵绿 + 观察期），分叉点仅导入路由与课程树读路径（`allowsV2ImportChain` 骑 v1 地基，fail-closed；`official_anki_feature_flags.dart`）
- [x] v2 导入全链路**代码可达**：staging（共用 saga）→ 预览（共用）→ 映射晋升（配置区单事务）→ 账本 5 表 → 视图重建 → 课程树出现（读面测试绿）→ 复习可用（lesson card index v2 分支 + 调度锁对齐）；**真机可达待 C3**
- [x] v2 路径对 catalog 其余 13 表、course.db 旧 anki 表**零写入**（守卫测试：statement 级 update 钩子 ×2 + 净状态断言）
- [x] 视图 DROP+REBUILD：幂等、worker 后台（会话引擎 RPC + drift 后台连接）、可取消（批间令牌）、「重建中」占位（进程内信号）、内置课程不受影响（K11/K13）
- [x] retiring 序列各段幂等，任一点强杀重启收敛，无无主且不可见的卡（K6；含引擎缺席 job 保活）
- [x] K14 偏好写穿清单落码（Q5；A2 四条静态核验结论 + scope 双层写穿）；真机机理判别待 C3
- [x] 文件日志通道上线，修复中心可导出（D8；LogCapture 滚动文件 + 导出附带 120 条）
- [ ] K1–K14 真机矩阵映射表全绿（debug/release 双跑）——**映射表与代码答案已就绪，真机执行未跑**；K2 对 op 40 的充分性有书面结论（不足，理由如上；op 43 暂不占号）
- [ ] Q3 冷重建 P95 数值定标并回填——**未跑**（需大夹具 + 真机）；测量面已具备（重建 elapsedMillis + 日志行）
- [x] v1 零回归：flag = false 时既有全套测试不回退，旧数据行为不变（受影响面定向复跑全绿 + 干净树逐名对比；见收据）
- [x] 零新增失败（与干净树基线逐名对比，同 Step 3 方法；见收据）

## 工作量估计

| 任务 | 估计 | 实际（host 侧） |
|---|---|---|
| A 定案（Q4/Q5/A3 落表） | 0.5~1 天 | 0.5 天（含 A2 静态核验） |
| B1+B2 配置区消费者 + 账本 | 3~5 天 | 1 天 |
| B3+B6 视图与读路径 | 5~8 天 | 1.5 天 |
| B4 census | 2~3 天 | 0.5 天 |
| B5 retiring 删除轴 | 4~6 天 | 1 天 |
| C1 文件日志 | 2~3 天 | 0.5 天（复用 LogCapture） |
| C2 挂载点测试 | 3~5 天 | 1 天（31 用例） |
| C3 真机强杀矩阵（含多轮迭代） | 5~8 天 | **未开始** |
| C4 定标 | 1~2 天 | **未开始** |
| **合计** | **25~38 个工作日**（README 档「月」；真机矩阵轮次是最大变量） | host 侧 ~6 天；真机两项待跑 |

---

## 收据（施工后回填）

| 日期 | 事项 | 结果 | 证据（commit / 测试输出） |
|---|---|---|---|
| 2026-09-01 | 计划落稿 | — | 基线：Step 3 已交付 op 41/42（契约 1.12）、全链路调用面与假引擎 `configStore`；flag 矩阵现状 `official_anki_feature_flags.dart`（生产 10 位全开，v2 位待加）；due sync 真实挂载点核实 = 复习页/练习中心/资料页；catalog 18 表与 ADR 附录 A 逐张对齐 |
| 2026-09-01 | 复核修正 | 3 处 | ① 分叉点改写：`production_router` 是 Legacy↔Official 存量路由（只读），v1↔v2 真分叉 = commitLive 后的投影发布段（`official_first_service`/`UnifiedAnkiImportOrchestrator.publishFromProjection` 的替代面）+ 读面（`CourseProvider`、lesson card index、练习投影读者）；② ADR D5 口径偏差记录：course.db 全建表核对，anki 相关 **13 张**；③ B6 读面补全 lesson card index（`official_anki_lesson_card_index.dart:20` 自述） |
| 2026-09-01 | A1+B2：flag 与账本 | 落码 | `official_anki_feature_flags.dart`（v2ImportChain + allowsV2ImportChain，productionAndroid 保持 false）；catalog v13（`chain` + receipt 三列 + 索引，`official_anki_database.dart:_upgradeToV13`）；Source DAO v2 方法组（markChainV2/markRetiring/listV2Sources/deleteSourceV2）；`retiring` 状态 append-only 加入（仅 wire switch 穷举处，全库无其他穷举点）。schema 绊线 `official_anki_lifecycle_storage_test` 12→13、`schema_migration_test` 22→23（降级夹具 v23→v24）随版本更新 |
| 2026-09-01 | B3+B6：视图与读路径 | 落码 + 测试绿 | course.db v23 `anki_course_tree_view`；`v2/` 8 文件（view_store/view_rebuilder/import_service/course_read/decision_store/config_keys/pending_imports/retire_service）；读面分叉四挂载点（course_entry/course_provider/course_catalog/lesson_card_index）；控制器分叉 `_commitOfficialV2`；`setScope` 双层写穿。测试：`official_anki_v2_read_path_test` 5 例、`official_anki_v2_view_rebuild_test` 6 例 |
| 2026-09-01 | B1+B4+B5+C1 | 落码 + 测试绿 | 配置区决策消费者（op 41/42，损坏读按 missing）；census 三级分流（3 例 + v1 隔离 1 例）；retiring 序列（`v2_source_delete`/`v2_view_rebuild` 维护 kind + runner 臂 + 卸载入口分叉 + 启动恢复 enqueue，6 例）；文件日志助手接入 5 个关键文件 + 修复中心导出附带日志尾 |
| 2026-09-01 | 施工中修掉的缺陷 | 2 处 | ① 派生放置决策会覆盖多级牌组的路径派生（顶层键把两个课时压成一个）——改为只为「无子牌组的平牌组」落派生键，多级树走路径派生（决策只存会改变派生结果的用户覆盖，D2 语义纠偏）；② retire 服务 course 可空化（维护 runner 侧本就传可空，缺席时「即刻不可见」退化为账本 state 过滤） |
| 2026-09-01 | C2 + 零写入守卫 | 31/31 绿 | `test/application/anki_official/v2/` 六文件：flag 5、import_chain 5（含 catalog 五表守卫 + course.db 仅视图守卫 + 重入幂等）、view_rebuild 6、retire 6、pending_imports 4、read_path 5。守卫 = sqlite3 `updatesSync` statement 级钩子（catalog：五表集合外零命中；course.db：仅 `anki_course_tree_view`）+ 六张旧表净状态为空断言 |
| 2026-09-01 | 回归核验（防卡死分区跑） | 零新增失败 | 受影响面定向复跑：anki_official 全目录（395+ 过，失败 4 项全部干净树复现：execution_plan/host_ffi 两损坏文件（Step 1 存量）+ composition errno 32（Windows 预存，BASELINE.md 有档）+ media_resolver（干净树同败））；test/data + test/courses（仅 review_history ×2 干净树同败）；test/application/anki + projection + lesson_flow 102 全绿；anki_import + maintenance + 修复中心/存储页 58 全绿；test/views/anki（3 失败干净树同败：p5f flow ×2 + controller zero-writes，BASELINE.md 有档）；course_provider 四文件全绿。`flutter analyze`：lib/ 零 issue，仅剩 2 个存量损坏测试文件的 error（Step 1 收据同款）。干净树对照方法 = `git stash` 复跑（Step 3 同款），每处失败均验 |
| 2026-09-01 | C3/C4 | 未跑（如实） | 真机（vivo V2502A）与 10 万卡大夹具在本机不可达；K 矩阵映射表、K2 书面结论（op 40 恒空 stub + checkpoint 范式不匹配，op 43 暂不占号）、Q3 测量面（elapsedMillis + 日志）均已就绪，构成 C3/C4 的执行清单。**flag 翻 true 的前置（矩阵绿 + 定标）未满足，productionAndroid 保持 false** |
