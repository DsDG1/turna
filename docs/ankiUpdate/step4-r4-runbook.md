# Step 4 R4 执行手册：翻 `productionAndroid.v2ImportChain` + Step 4 关闭

> 上游：[ADR 0044](../decisions/0044-anki-v2-revival.md)（R4 = 最后一条执行线）；[step4.md](./step4.md)（Step 4 施工状态）；[step4-c3-runbook.md](./step4-c3-runbook.md)（C3 矩阵，R2 收口）。
> 完成纪律沿用 2026-09-02 修订：**翻没翻、过没过，只看操作者确认**；host 测试与文档留证不构成完成。

---

## 0. 门禁状态（翻 flag 前提）

| 前置 | 状态 |
|---|---|
| R1 重建 arm64 .so（op 41/42 入包） | ✅ 2026-09-02（SHA 收据见 step4.md） |
| R1.5 v2 卡索引段下沉 worker（K13 前置） | ✅ 2026-09-02（commit `cb6945c8`，K13 大库实机过） |
| R2 C3 真机强杀矩阵 | ✅ 2026-09-02（K4–K14 实机过；K1/K3 不考虑、K8 不适用、K12 归 Step 5） |
| R3 C4 大库冷重建定标 | ✅ 2026-09-02（操作者确认「通过」） |
| A1 回退条件（观察期判定基准） | 观察期内未出现：不可自愈的 K 场景复发 / 修复中心 v2 quarantine 滞留 |

R4 翻转于 **2026-09-02 执行（操作者「通过」）**。

---

## 1. 翻转动作清单（已执行，四处代码面）

1. **`lib/application/anki_official/official_anki_feature_flags.dart`**
   - `productionAndroid` 常量增加 `v2ImportChain: true`（翻的主体）；
   - **`fromEnvironment` 退役 v2 define**：不再读取 `TURNA_OFFICIAL_ANKI_V2_IMPORT_CHAIN`。陷阱记录：原先 `copyWith(v2ImportChain: define)` 在无 define 构建里读到 `false`，会把常量刚翻的 `true` **盖回 `false`**——只改常量则生产包等于白翻。define 的 C3 投喂使命已完成，直接移除（顺带更新类头 opt-in 清单与字段注释）。
2. **`test/application/anki_official/v2/official_anki_v2_flag_test.dart`** 按新语义翻转：生产位 true、回退态 `copyWith(v2ImportChain: false)` 不放行、v1 地基缺一 fail-closed；「define 双态接线」用例随 define 退役删除，替换为 **fromEnvironment 继承生产位**守卫（防盖写陷阱复发）。
3. **`test/.../v2/official_anki_v2_read_path_test.dart`** 「flag off」用例基线改 `productionAndroid.copyWith(v2ImportChain: false)`（回退态语义，v1 零回归的结构保证不变）。
4. **`test/.../v2/official_anki_v2_lesson_content_test.dart`** 「flag off: supply is inert」用例同款修正（原骑 `current` 默认值，翻开后被新基线打破）。

验证：v2 全目录 + 读挂载点 + official_first flags **56 例全绿**；受影响面其余失败（composition single-flights errno32、p5f flow ×2、controller zero-writes）逐名对上 BASELINE 在册 Windows 预存，**零新增**；`flutter analyze` 改动 4 文件 No issues found。

> C3 runbook 里的 `--dart-define=TURNA_OFFICIAL_ANKI_V2_IMPORT_CHAIN=true` 构建命令自本手册起为 **no-op**（define 已退役），历史章节保留不改。

## 2. 生效面（什么变了 / 什么没变）

**变了**：不带 define 的生产/常规构建，新导入的 commitLive 之后段走 v2（配置区写 + 账本 5 表 + 视图重建），课程树读面从 `anki_course_tree_view` 长出。分叉点不变：`anki_import_controller._commitOfficial`、`official_first_service`、B6 四读挂载点 + F6 课时正文。

**没变**：
- 存量 v1 来源（`chain='v1'`）原样可学——读路径两代并存（v2 课时走视图，非 v2 课时回落 v1 投影 index）；
- 内部构建此前导入的 v2 来源继续可学；
- 复习队列、答题、渲染、调度链共用面不动；
- Legacy↔Official 存量路由（`production_router`）与本 flag 无关。

## 3. 回退操作卡（A1 定案语义）

任一回退条件触发（K 场景真机复发且不可自愈 / 修复中心 v2 quarantine 无法自动收敛）：

1. `productionAndroid` 的 `v2ImportChain` 翻回 `false`（一行）；
2. 同步把 `official_anki_v2_flag_test.dart` 的生产位断言翻回 false、read_path / lesson_content 两个 flag-off 用例恢复直用 `productionAndroid` 基线；
3. 收据记入 step4.md（日期 + 触发场景）。

回退语义：**只把新导入路由回 v1**。已导入 v2 来源的账本行（`chain='v2'`）、配置区决策、视图表全部保留（数据无损），读路径回落 v1 后 v2 视图行不可见但可随时翻回恢复——这是「flag 只路由新写入，不销毁任何已有事实」的对称面。

## 4. 翻后观察清单（进行中，非门禁）

- 下一个生产 flag 构建包真机冒烟：新导入一包 → 课程树从视图长出、能进能学、来源管理卸载正常（操作者确认制）；
- 日常使用盯修复中心：v2 来源 quarantine 记录是否自动收敛、`view rebuild` 日志行耗时无异常增长；
- 任一 K 场景复发且不可自愈 → 走 §3 回退。

## 5. 收据

| 日期 | 事项 | 结果 | 证据 |
|---|---|---|---|
| 2026-09-02 | R4 翻转执行 | 完成（操作者「通过」） | §1 四处代码面；定向测试 56 绿 + BASELINE 在册 4 败零新增；analyze 4 文件零 issue。Step 4 随此关闭；Step 5（存量迁移）重新决策（ADR 0044 条 5）、Step 6 开工条件满足 |
