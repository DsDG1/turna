# Step 5 详细说明：存量用户切换（一次短事务，Anki 库原样保留）

> 上游文档：[README.md](./README.md)（总目标与六步计划）；前置：[step4.md](./step4.md)（已完成 host 侧：v2 链在 `v2ImportChain` flag 后可用、零写入守卫、K 矩阵代码答案；**未完成：C3 真机矩阵、C4 定标——本步开工的硬前置**）。
> Step 5 只做一件事：**让 flag 翻 true 之前已经用 v1 链导入过的存量用户，把「需要搬的家当」搬进 v2 结构——一次短事务、可重跑、Anki 库一个字节不动**。新导入自 Step 4 起已走 v2；本步处理后，读面/删除轴/维护轴对存量来源与新建来源行为一致，为 Step 6 删旧代码扫清数据面。
> 原则：迁移 = 搬**决策与标记**，不搬卡片事实（卡片事实本来就在 Collection，D1）；杀进程回滚、重跑幂等（K12）；每迁移一个 source，旧表面立即停写（只停不删，删除归 Step 6）。

---

## 0. 范围围栏（先说清楚不做什么）

| 不做 | 归属 |
|---|---|
| 删任何旧表、旧代码路径、NoteStore 退役 | Step 6 |
| 真机强杀矩阵 K1–K14 首跑、大库 P95 定标 | **Step 4 收尾（本步开工前置）** |
| v2 新导入链（已落码） | Step 4 已完成 |
| doc 42 §7 之外的 pre-0042 存量异常态（checkpoint 残件、authority 非 active 旧行）善后 | 本步任务 A（census 收口），物理清理仍归 Step 6 |
| Legacy（非 Official）导入数据的迁移 | 不迁——Legacy 链已退役（doc 38），其残件随 Step 6 处置 |

Step 5 的产出是：**迁移 census + 三样短事务落码 + 全量 v1→v2 收敛（含真机升级实测）+ 一个 release 观察期的灰度启动 + 旧表全面停写（验收 = 停写守卫测试绿）**。

---

## 1. 前置门禁（不满足不开工）

1. Step 4 C3 真机矩阵 K1–K14 全绿（debug/release 双跑），K2 结论按证据定案（op 43 占号或关闭）；
2. Step 4 C4 冷重建 P95 定标回填（10 万卡级），低于门禁值（建议初值：P95 < 5s，超了先做增量门禁再谈切换）；
3. `v2ImportChain` 已按 A1 灰度边界翻 true 并稳定观察一个内部 release（新导入走 v2 无回归）。

---

## 2. 迁移什么：三样家当（K12 的「搬三样」逐项落码）

对一个 v1 来源（catalog `anki_sources.chain='v1'` 且 state='active'）：

| # | 家当 | 从 | 到 | 幂等性 |
|---|---|---|---|---|
| ① | **映射决策** | catalog `anki_projection_mappings`（profile 级 notetype 行） | Collection 配置区 `turna.import.mapping.<sourceId>`（op 42 单事务；JSON 含 confirmed/skipped/suggestions 快照，Step 4 已定义编码） | 同值重写 no-op；已存在且同 schema 跳过 |
| ② | **账本标记收敛** | `anki_sources.chain='v1'` | `chain='v2'`（catalog v13 列，Step 4 已加）+ attempt 行 receipt 回填（`receipt_note_ids_json` 从 `anki_source_cards.note_id` 派生，删侧已够用） | UPDATE 天然幂等；重跑跳过已迁移行 |
| ③ | **视图重建标志** | （无） | 入队 `v2_view_rebuild` job（Step 4 维护 kind 已落码）——重建时该 source 的 `anki_source_cards` 所有权清单 + Collection 牌组树 + 配置区决策合成视图行 | 重建本身幂等（K3/K11 已验） |

**放置决策（v1 的 `anki_course_placement_overrides`）不逐行搬**：v1 投影已把牌组放进了课程树，迁移后 v2 视图按 deck 路径派生；仅当 census 发现某 source 存在用户 override 行时，才为其顶层牌组合成 `turna.course.placement.<deckId>` 决策（override 的语义就是「改派生」，正好是配置区决策的本职）。多数 source override 为空 = 零写入。

**短事务边界**：①②同一 catalog 事务（`BEGIN…COMMIT`，杀于此回滚、重跑重来）；③是 job 入队（也在事务内），执行异步（worker）。「最坏情况重跑迁移」= 每个source 的迁移不依赖前一个完成（无全局序），census 驱动逐个收敛。

## 3. 任务分解

### 任务 A：迁移 census（含 doc 42 §7 善后收口）

- 枚举迁移对象：`chain='v1'` 且 state='active' 的 sources；逐个产出迁移判定（可迁 / 需善后 / 跳过）。
- **善后判定**（收口 doc 42 §7 的存量实例，v2 不为其保留常驻代码路径）：
  - `pending_cleanup` / `needs_reconciliation` 等非 active 残留 → 先走 v1 修复执行器收敛到 active 或 retired，再迁或弃；
  - pre-0042 checkpoint 残件（`anki_checkpoint_files`）→ sweep 清单化，随迁移事务标记 released；
  - 「catalog active + authority 非 active（旧版）」行 → 以账本为准修正 authority 镜像（v1 语义内修复，不是 v2 逻辑）。
- 产出修复中心可见的「待迁移 N 个来源 / 已迁移 M / 需人工 K」清单（复用 Step 4 文件日志通道）。

### 任务 B：三样短事务落码

- `lib/application/anki_official/v2/official_anki_v2_migration_service.dart`（新）：
  - `migrateSource(sourceId)`：census 判定 → 事务（①映射决策合成+写配置区（引擎在场，op 42）→ ②chain 标记+receipt 回填 → ③入队视图重建）；
  - `migrateAll(profileId)`：census 驱动逐个 `migrateSource`，单个失败不阻塞其余（记录、修复中心可见）；
  - 全程接入 Step 4 文件日志（每 source 一行收尾记录）。
- 启动接线：`OfficialAnkiStartupRecovery` 在维护 job 检查之后追加「有 v1 active source 且 flag 开 → 迁移 census + 逐个短事务」（有活才开引擎的纪律不变）。
- **停写面**（迁移完成的 source 生效）：v1 投影器/placements/presentations/authority 写路径对其不再触碰——落码为投影与发布入口的 `chain` 检查（v1 分支遇 chain='v2' 直接走 v2 面），配守卫测试。

### 任务 C：观测、测试与发布

- **C1 迁移测试**（严格假引擎）：三样各自幂等；事务中杀（fault injection）→ 重跑收敛；映射决策同值重放 no-op；override 存在/不存在两分支的放置决策合成；census 三判定。
- **C2 停写守卫**：迁移后对已迁移 source 跑 v1 投影入口 → 断言旧表面零写入（Step 4 守卫测试同款 update 钩子）。
- **C3 真机升级实测**：带 v1 存量数据的安装包 → 升级到含 Step 4/5 的版本 → 冷启动迁移自动完成 → 课程树/复习/删除与迁移前不可区分（学习进度、引入状态、scope 记忆逐一比对）；强杀迁移窗口（K12 真机轮）。
- **C4 灰度与观察**：迁移随 flag 走（flag 关 = 不迁、不破坏）；一个 release 观察期（修复中心零 v2 quarantine、零「待迁移」滞留）→ Step 5 关闭条件。

---

## 执行顺序

```
前置门禁检查（Step 4 C3/C4 收尾 + flag 灰度稳定）
 └→ A census（含善后收口）
      └→ B 三样短事务 + 启动接线 + 停写面
           └→ C1/C2 测试（假引擎 + 停写守卫）
                └→ C3 真机升级实测（含 K12 强杀轮）
                     └→ C4 一个 release 观察 → 全绿 → Step 5 关闭，进 Step 6（删旧代码）
```

## 验收清单

- [ ] 前置门禁三项全满足（Step 4 C3/C4 收据 + flag 灰度记录）
- [ ] census 三判定落码，修复中心可见待迁移/已迁移/需人工清单；doc 42 §7 存量善后在 census 中收口
- [ ] 三样短事务：同 source 重跑幂等；事务中强杀回滚可重跑（K12，fault injection 测试 + 真机轮）
- [ ] Anki 库原样保留：迁移前后 `collection.anki2` 字节级不变（真机实测收据）
- [ ] 迁移完成的 source：v1 旧表面零写入（停写守卫测试绿）
- [ ] 真机升级实测：学习进度/引入状态/scope 记忆迁移前后不可区分；课程树从视图长出且与 v1 投影一致（逐 section 比对）
- [ ] 一个 release 观察期：修复中心零 v2 quarantine、零待迁移滞留
- [ ] v1 零回归（flag 关时迁移完全不发生）、零新增失败（与干净树逐名对比）

## 工作量估计

| 任务 | 估计 |
|---|---|
| A census + 善后收口 | 2~3 天 |
| B 三样短事务 + 接线 + 停写面 | 3~5 天 |
| C1/C2 测试 | 2~3 天 |
| C3 真机升级实测（含 K12 轮） | 3~5 天 |
| C4 观察期 | 1 个 release 周期 |
| **合计** | **10~16 个工作日 + 一个 release 观察**（README 档「周」） |

---

## 收据（施工后回填）

| 日期 | 事项 | 结果 | 证据（commit / 测试输出） |
|---|---|---|---|
| 2026-09-01 | 设计落稿 | — | 基于 Step 4 实际落码面（catalog v13 `chain`/receipt 列、配置区键族、`v2_view_rebuild` job、文件日志通道均已存在）；K12 短事务边界与 ADR D2/D3/D4 附录 A 对齐；override 不逐行搬的裁断依据 = D2「决策只存会改变派生结果的覆盖」（Step 4 施工中同款语义纠偏先例） |
