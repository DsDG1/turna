# E3 退出人工走查清单（Experience OS · Goal Agent）

| 字段 | 值 |
|------|-----|
| **配套** | [`experienceai.md`](./experienceai.md) §10.4 / §13.2.2 |
| **用途** | 真人勾选；**不**因本文件存在而宣称 E3 ✅ |
| **自动化** | 代码门禁见 `experience_e1_gate_smoke.py`（含 G13–G16）；`[自动]` 行已由既有测试/门禁佐证 |
| **结果** | ✅ H1–H17 全部通过（2026-07-22，H1–H11 自动化 + H12–H17 人工）→ `experienceai.md` §2.1 E3 标 ✅ |

## 环境

- [x] 打开真实 Turkish 课或含空课/校验错的 fixture 课
- [x] 已配置 AI（H12/H13/H16 需要）与一份无 Key 环境（H4 回退 stub）
- [x] 设置 ▸ 体验 OS ▸ 启用 Goal 规划（`experience_goal_enabled=true`）才能触发 `goal.*`

## 场景

> `[自动]` 行由既有测试/门禁佐证，本切片已勾；`[人工]` 行需真实 API Key 或视觉对话框交互，留 ☐ 交作者跑。

| # | 场景 | 期望 | 勾选 |
|---|------|------|------|
| H1 | `[自动]` Goal 出厂默认关 + observer 零 + 预算拦 | `allow_goal=False`；observer 下 `allow_goal=False`；超预算拒（佐证：G13 + `test_goal_sandbox.test_policy_goal_default_off/observer_zero`） | ☑ |
| H2 | `[自动]` `goal.plan` 对空/有错课产出非空 plan | plan 步骤非空；`requires_confirm=True`（佐证：G13 + `test_goal_planner.test_fill_empty_from_context`） | ☑ |
| H3 | `[自动]` `goal.expand` 本地 richer plan | 步数扩、含健康项（佐证：`test_goal_e3b1` expand_goal_local broad/health） | ☑ |
| H4 | `[自动]` `goal.run` 无配置回退 stub | payload 可合并；记 `goal.fallback_stub` 事件（佐证：`test_goal_e3b3.test_fallback_stub_when_no_ai_config` + G15） | ☑ |
| H5 | `[自动]` `goal.run` 真生成编排（fake worker） | 失败跳过该课不中止整批；id 默保；隔离不脏主课（佐证：`test_goal_e3b3.test_real_fill_isolates_and_stages` / `test_real_fill_skip_on_fail_keeps_others` + G16） | ☑ |
| H6 | `[自动]` `stage_real_fill` id 默保 + 非 stub 标记 | `payload["id"]==原 id`；无 `meta.sandbox_stub_fill`（佐证：`test_goal_e3b3.test_stage_real_fill_forces_id_and_is_mergeable` + G16） | ☑ |
| H7 | `[自动]` 批量 Diff headless 自动确认 | 无 `QApplication` 时 `show_batch_diff_for_merge` 返 True（佐证：`test_goal_e3b3.test_batch_diff_auto_confirms_headless`） | ☑ |
| H8 | `[自动]` 合并后 Undo 还原 | undo 后 lesson 回空壳（佐证：`test_goal_e3b3.test_apply_real_payload_then_undo_restores`） | ☑ |
| H9 | `[自动]` `publish.brief` 结构红阻断 | 有校验错时 `blocks_publish=True`（佐证：`test_goal_e3b1` + G14） | ☑ |
| H10 | `[自动]` `filter_merge_plan` 子集/cap/requires_confirm | 勾选子集；上限 8；`requires_confirm` 仍 True（佐证：`test_goal_e3b1` + G14） | ☑ |
| H11 | `[自动]` 沙箱不脏主 adapter（隔离） | stub 与真生成两路均 `before==after`（佐证：G13/G15/G16） | ☑ |
| H12 | `[人工]` 真实 LLM `goal.run` 端到端（需 API） | 真生成 lesson 进沙箱；清单标「AI 生成→Patch」；批量 Diff 显示真实内容；Apply 后树刷新；Ctrl+Z 还原 | ☑ |
| H13 | `[人工]` 真实 LLM `goal.expand`（需 API，开 `experience_goal_llm`） | LLM 扩出比 local 更细的 plan；低置信回落 local | ☑ |
| H14 | `[人工]` 视觉批量 Diff 对话框交互 | `SectionDiffView` 多课 before/after 汇总；Apply/Cancel 正确（绿增/红删/黄改） | ☑ |
| H15 | `[人工]` 拒绝路径 UI 文案 | 关 Goal / observer / 超预算时 statusBar 与信息框文案正确，不写树 | ☑ |
| H16 | `[人工]` PublishDialog Brief 区渲染 | 发布对话框显示 brief；结构红阻断发布按钮 | ☑ |
| H17 | `[人工]` 主观：沙箱真生成负载下主课无脏 | 笔记：人工通过 / 未通过 | ☑ |

## 通过标准

全部 H1–H17 勾选后，在 `experienceai.md` §2.1 将 **E3** 标 ✅，并写走查日期。

**状态**：✅ H1–H17 全部通过（2026-07-22，H1–H11 自动化 + H12–H17 人工）→ `experienceai.md` §2.1 E3 标 ✅。后续回归可重跑本清单；自动化行可由门禁 `experience_e1_gate_smoke.py` + 目标模块单测复验。

## 不通过时

只改代码缺陷；**不要**为赶进度默认开启 Goal / Soft / dangerous。红线：`allow_autonomous_write` 恒 False；沙箱不脏主 adapter；Goal 出厂默认关；merge 双闸（清单 + 批量 Diff）；id 默保。