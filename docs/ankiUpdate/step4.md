# Step 4 详细说明：v2 导入→课程树链落码（与 v1 并存）

> 上游文档：[README.md](./README.md)（总目标与六步计划）；前置：[step3.md](./step3.md)（已完成：op 41/42 落码、契约 1.12、全链路调用面与假引擎 `configStore` 就绪）。
> Step 4 只做一件事：**把 ADR 0043 的 v2 全生命周期链（导入→决策→视图→复习挂载→删除）在 flag 后落码，真机强杀矩阵全绿**。v1 一行不改、一路不删；flag 决定新导入走哪条链。
> 原则：v2 路径对旧表**零写入**（守卫测试锁死）；每一段幂等（K 矩阵的答案必须是代码，不是文档）；测试贴真实挂载点（D9）。

---

## 0. 范围围栏（先说清楚不做什么）

| 不做 | 归属 |
|---|---|
| 删旧代码、v1 路径退役、guard 锁门 | Step 6 |
| 存量用户切换（搬三样短事务、v1 数据迁 v2） | Step 5 |
| catalog 18→5 / course.db 旧 anki 表的**物理删除**（Step 4 只新增 v2 结构，旧表停写不删） | Step 5/6 |
| usn-diff 只读 op——仅当 C3 强杀测试证明 op 40（现为 stub）不足以支撑 K2 时才占编号 43，回本文件收据定案 | 本步条件项 |
| 课程切换异常的 v1 热修（若等不到 v2，独立小修，不进本步） | 独立小修 |

Step 4 的产出是：**v2 链全生命周期在 `v2ImportChain` flag 后可用 + K1–K14 真机矩阵绿 + Q3/Q4/Q5 定案 + v1 零回归**。

---

## 任务 A：施工前置定案（Q4 flag、Q5 偏好清单、D5 明细落表）

### A1 · Q4：并存 flag 的命名与灰度边界（定案）

- **命名**：`OfficialAnkiFeatureFlags.v2ImportChain`（`lib/application/anki_official/official_anki_feature_flags.dart`）+ `allowsV2ImportChain` getter。**不建第二套 flag 矩阵**——遵守该类已有的纪律注释（「Product pause is cutoverEnabled — not a second flag matrix」），v2 只加一个布尔位。
- **管什么**：只管两个分叉面——
  - **写侧**：commitLive 之后的「投影发布」段。v1 现状 = 投影器写 `official_anki_projection_index`/`manifest` → `UnifiedAnkiImportOrchestrator.publishFromProjection` 写 placements/presentations；v2 = 配置区写（op 42）+ 账本 5 表 + 视图重建。分叉在官方导入服务/编排器的发布步（`import/official_anki_official_first_service.dart` 一带），**不在** `migration/official_anki_production_router.dart`——那是 Legacy↔Official 的存量路由，只读、与 v1/v2 无关。
  - **读侧**：课程树读面 = `CourseProvider` + `projection/official_anki_lesson_card_index.dart`（复习链的课时→卡映射，读的就是投影 index）+ 练习投影读者。v2 里这个读面整体切到视图表。
  - 复习队列、答题、渲染、引擎会话链两代**共用**（README「不动」清单资产）；它们对投影表的间接依赖（lesson index）已划入读侧分叉面。
- **默认值**：构造器默认 `false`；dev/QA 构建经 `copyWith` 打开；`productionAndroid` 常量保持 `false`，直到 C3 真机矩阵全绿 + 一个内部 release 观察期后再翻 `true`（翻的动作 = 改常量 + 本文件收据记录日期与证据）。
- **回退条件**（任一触发即翻回 `false`）：v2 链在真机复现任一 K 场景不可自愈（视图无法重建 / 配置区决策损坏且识别器重建议失败 / 出现无主且不可见的卡）；修复中心出现 v2 来源的 quarantine 记录且无法自动收敛。
- **回退语义**：v2 已导入的来源**继续可学**——账本行、配置区决策、视图表都留着，读路径兼容两代数据；仅新导入回 v1。这是「旧数据不受影响」的对称面：flag 只路由新写入，不销毁任何已有事实。

### A2 · Q5：K14 偏好写穿清单（定案，落码在任务 D）

- **必须写穿**（提交时机即持久化，不等进程正常退出）：onboarding 完成态、课程 scope 选择、`v2ImportChain` 若做运行时开关则其自身、课程启用/引入状态、导入向导中途态（staging 路径）。
- **可容忍丢失**：纯 UI 偏好（主题、页签位置、动画偏好）。
- **前置动作**：Step 1 发现 #5 只证明了「强杀后 prefs 丢失」的现象，未定位机理（写入时机 vs 持储损坏）。本任务先用真机复现定位，再按清单逐项改写穿时机；清单本身若与定位结果冲突，以定位证据修订并回收据。

### A3 · D5 明细落表：course.db anki 表 v2 去向（初步盘点，任务 B 落表时逐张定案回填）

以 `lib/data/course_database.dart`（`kSchemaVersion = 22`，全文件 1349 行、32 张 CREATE TABLE 已全量核对）现状盘点：**course.db 内 anki 相关表实测 13 张**；ADR D5 所称「约 20 张」里的 `anki_notes`/`anki_cards_meta`/`anki_notetypes` 等 Legacy 内容表**不在 course.db**——它们在 Legacy 附加库（`course_catalog.dart:130` 仅做兼容读且自带「表可能不存在」容错，写侧已随 doc 38 P1-B/C 删除）。ADR 的口径偏差在施工定案时一并修正；Legacy 附加库本身归 Step 6 处置。

| course.db 现表 | v2 去向 |
|---|---|
| `official_anki_projection_index` / `official_anki_projection_manifest` | → 被新视图表取代（D3「两张合一张」；Step 6 删） |
| `anki_course_card_placements` / `anki_card_presentations` | → 配置区（D2 呈现与放置决策；Step 6 删） |
| `anki_practice_projections` | → 并入视图表（可重建） |
| `anki_decks` / `anki_import_issues` | → 删（Collection 派生 / attempt 吸收；Step 6 删） |
| `anki_course_sources` / `anki_owner_transitions` / `course_scope_repair_journal` / `anki_import_jobs` / `legacy_pending_migrations` | → 删（账本归 catalog `anki_sources`；对账/修复中心随副本退役；Step 6 删） |
| `anki_card_introduction_states` | **保留**（产品侧非 anki 事实：课程引入状态，D5） |
| **新增** `anki_course_tree_view` | **v2 唯一视图存储**（D3 物化视图，无独立状态、可 DROP+REBUILD） |

---

## 任务 B：v2 链落码（核心）

- **B1 决策进配置区（D2 消费者）**：字段映射晋升、牌组→课程放置决策写 op 42（`turna.import.mapping.<sourceId>` / `turna.course.placement.<deckId>`，均为 JSON object）。晋升 = 配置区写 + attempt 状态推进，**两步各自幂等**（K10）；同值重放为 no-op。
- **B2 账本写入（D4）**：v2 路径只写 catalog 5 张——`anki_sources`、`anki_import_attempts`（吸收 receipt：pre-import usn、scope、note ids）、`anki_maintenance_jobs`、`anki_maintenance_leases`、`anki_source_cards`（Q6 定案：所有权索引，B5 删除原语的输入）。**对其余 13 张零写入**，守卫测试锁死。
- **B3 视图存储与重建（D3/D7）**：course.db 新表 `anki_course_tree_view`；重建 = DROP+REBUILD，输入 = Collection（现有只读 op 8/18/19/20/24/26）+ 配置区决策 + 账本行；跑在 worker isolate（复用 `official_anki_worker.dart` 的串行队列与取消通道），主线程零 native 忙等（K13）；重建期间课程树显示「重建中」占位，内置 Turkish 课程不受影响（K11，继承 doc 41 §7.1「恢复失败不阻塞启动」）。
- **B4 staging census v2（K1）**：staging 目录即证据；重启发现未完成导入 → 「待完成导入」入口（完整性校验过 → 直接进 preview，否则重建 staging；live 零写入不变式继承 ADR 0042）。参考 `lifecycle/official_anki_pending_imports.dart` 现状，v2 语义不改 v1 行为。
- **B5 删除轴 retiring 序列（D6/K6）**：①账本单事务标 `retiring`（用户视角即刻移除，课程树/复习立即不可见）并入队删除 job；②worker 幂等执行引擎删除（op 31/32 按 `anki_source_cards` 所有权清单，缺卡无害）；③终删账本行 + 视图重建；④媒体 GC / VACUUM 走 maintenance job（沿用 doc 41 S5/S7）。任何一段强杀 → 重启 job 表驱动续跑，source 停 `retiring` 且修复中心可见——**不产生无主且不可见的卡**。Step 1 发现 #3（pending_cleanup 永不完成）的根因（跨库多步状态机）就此被单线 job 序列取代。
- **B6 课程树读路径与切换（Step 1 发现 #2 的 v2 答复）**：读面整体切视图表——`CourseProvider`（课程树）+ `projection/official_anki_lesson_card_index.dart`（复习链课时→卡映射，v1 读投影 index）+ 练习投影读者；课程切换 = 改一个配置区决策键 + 视图切换（D2/D3），不再有跨库状态机。

## 任务 C：观测、测试与定标（D8/D9/Q3）

- **C1 文件日志（D8，发现 #4 的答复）**：滚动文件日志覆盖启动恢复、commit 窗口、维护任务、视图重建、retiring 序列；修复中心「导出诊断」可带出；**不依赖厂商 logcat**。storage audit 快照保留。
- **C2 贴真实挂载点的测试（D9）**：入口测试挂真实触发点——复习页（`views/anki/anki_review_screen.dart`）、练习中心（`views/play/play_hub_screen.dart`）、资料页（`views/profile/widgets/profile_quick_actions.dart`）。严格假引擎（`configStore` 已随 Step 3 就绪）常驻用例：晋升幂等、K10 单事务、视图重建幂等、retiring 各段幂等、v2 对旧表零写入。
- **C3 真机强杀矩阵（发布门禁）**：K1–K14 逐条映射真机用例（每行：场景、杀点、重启期望），debug/release 双跑纪律（doc 41 §16.6）。**K2 专项**：验证 op 40（现为 stub）对 receipt 重建的表达力——不足则回本文件定案是否占 op 43（只读 usn-diff），充足则记录证据关闭该项。
- **C4 Q3 定标**：大库（10 万卡级，`gen_fixtures --large` 产包或多包叠加）冷重建 P95 实测，数值回填收据——它是 Step 5/6 的性能门禁基线，也是 ADR「视图重建慢 → 重建增量门禁」风险的量化答案。

---

## 执行顺序

```
A 定案（flag/偏好清单/表去向）——0.5~1 天
 └→ B1+B2 配置区消费者与账本（v2 导入闭环的最小内核）
      └→ B3+B6 视图与读路径（课程树从视图长出来）
           └→ B4 staging census → B5 retiring 删除轴
                └→ C1 文件日志 + C2 挂载点测试（随每段并行写）
                     └→ C3 真机强杀矩阵 + C4 定标 → 全绿 → flag 翻 true 决策 → Step 4 关闭，进 Step 5
```

## 验收清单

- [ ] `v2ImportChain` flag 落码（默认 false，production 翻 true 前置 = 矩阵绿 + 观察期），分叉点仅导入路由与课程树读路径
- [ ] v2 导入全链路真机可达：staging → 预览 → 映射晋升（配置区单事务）→ 账本 5 表 → 视图重建 → 课程树出现 → 复习可用
- [ ] v2 路径对 catalog 其余 13 表、course.db 旧 anki 表**零写入**（守卫测试）
- [ ] 视图 DROP+REBUILD：幂等、worker 后台、可取消、「重建中」占位、内置课程不受影响（K11/K13）
- [ ] retiring 序列各段幂等，任一点强杀重启收敛，无无主且不可见的卡（K6）
- [ ] K14 偏好写穿清单落码（Q5）
- [ ] 文件日志通道上线，修复中心可导出（D8）
- [ ] K1–K14 真机矩阵映射表全绿（debug/release 双跑）；K2 对 op 40 的充分性有书面结论
- [ ] Q3 冷重建 P95 数值定标并回填
- [ ] v1 零回归：flag = false 时既有全套测试不回退，旧数据行为不变
- [ ] 零新增失败（与干净树基线逐名对比，同 Step 3 方法）

## 工作量估计

| 任务 | 估计 |
|---|---|
| A 定案（Q4/Q5/A3 落表） | 0.5~1 天 |
| B1+B2 配置区消费者 + 账本 | 3~5 天 |
| B3+B6 视图与读路径 | 5~8 天 |
| B4 census | 2~3 天 |
| B5 retiring 删除轴 | 4~6 天 |
| C1 文件日志 | 2~3 天 |
| C2 挂载点测试 | 3~5 天 |
| C3 真机强杀矩阵（含多轮迭代） | 5~8 天 |
| C4 定标 | 1~2 天 |
| **合计** | **25~38 个工作日**（README 档「月」；真机矩阵轮次是最大变量） |

---

## 收据（施工后回填）

| 日期 | 事项 | 结果 | 证据（commit / 测试输出） |
|---|---|---|---|
| 2026-09-01 | 计划落稿 | — | 基线：Step 3 已交付 op 41/42（契约 1.12）、全链路调用面与假引擎 `configStore`；flag 矩阵现状 `official_anki_feature_flags.dart`（生产 10 位全开，v2 位待加）；due sync 真实挂载点核实 = 复习页/练习中心/资料页；catalog 18 表与 ADR 附录 A 逐张对齐 |
| 2026-09-01 | 复核修正 | 3 处 | ① 分叉点改写：`production_router` 是 Legacy↔Official 存量路由（只读），v1↔v2 真分叉 = commitLive 后的投影发布段（`official_first_service`/`UnifiedAnkiImportOrchestrator.publishFromProjection` 的替代面）+ 读面（`CourseProvider`、lesson card index、练习投影读者）；② ADR D5 口径偏差记录：course.db 全 32 张建表核对，anki 相关 **13 张**；`anki_notes`/`anki_cards_meta`/`anki_notetypes` 在 Legacy 附加库（`course_catalog.dart:130` 兼容读容错「表可能不存在」，写侧已随 doc 38 P1-B/C 删），不在 course.db，施工定案时修正 ADR 口径；③ B6 读面补全 lesson card index（复习链课时→卡映射读投影 index，`official_anki_lesson_card_index.dart:20` 自述） |
