# K-08 词汇螺旋 —— 设计文档

| 字段 | 值 |
|------|-----|
| **文档编号** | `VAR-GUI-EXP-K08-DESIGN` |
| **版本** | v1.0（v4.37 已实施） |
| **日期** | 2026-07-22 |
| **上游规范** | `tool/gui/docs/archive/experienceai.md` v4.37（§2.4 P4 Skills、§8.3 action 表、§11.5 done、§16.3 K-08） |
| **状态** | ✅ 已实施（v4.37）；本文档留作契约存档 |
| **范围** | section 级「词汇螺旋缺口」本地评估 → Dock/⌘K 建议 → 人确认 → 复用 K-05 引擎追加复现题 |
| **非范围** | 跨 section 螺旋、词频目标值调参、自动改写已有题、新设置键、新门禁 G |

---

## 1. 背景与问题

`experienceai.md` §16 将 K-08 `unit.spiral_vocab` 列为「剩余 Skills」中的下一项，bak-v3 §6.8 仅给一行表（todo），无行为定义。本文档补齐语义并落地。

**问题**：一个词被 `showWord` 在某课引入后，若后续课（同 section 内更靠后的 lesson）再无任何非-`showWord` 练习复现它，违背螺旋上升学习曲线。该缺口完全可由本地结构判定（零 LLM）。

**代码先例**：K-07 `lesson.balance`（v4.16）已是「纯函数 local 判定 → 确认 → 复用 `_run_regen_flow` 重生成」的成熟骨架，本切片完整复刻其链路，新增螺旋评估器与一条建议。

## 2. 设计决定一：评估粒度（section 级）

**决定**：`evaluate_unit_spiral(section)` 在**单个 section** 内跨 unit/lesson 判定「引入后无后续复现」。

| 决策点 | 决定 | 理由 |
|--------|------|------|
| 粒度 | section 级 | 「后续课」语义只在同 section 内成立（词库 `section.words` 是 section 范围）；跨 section 词汇重叠属 K-03 `compare_sections` 域，不混入 |
| 引入定义 | 最早出现 `showWord` 引用某 word_id 的课（按 unit→lesson 序） | `showWord` 是「首次呈现」，唯一合适的引入信号 |
| 复现定义 | 引入课**之后**任一非-`showWord` 练习命中该词（显式 `wordId`/`wordIds`/`correctWordIds` 或 term echo 于 options/expected/source/prompt） | 复用 `content_quality._count_practice_hits_for_words` 的 term-echo 启发式，不复制统计逻辑 |
| 同课练习 | **不算**后续复现 | 同一课内的 MCQ 视为「首次呈现的一部分」而非螺旋回环；须严格「更靠后的课」 |
| 空课/无词 | 返回空缺口，永不抛 | 对齐 §14.5.2 失败安全默认 |

## 3. 设计决定二：数据契约（闭集）

`evaluate_unit_spiral(section) -> dict` 返回闭集报告：

```text
{
  "section_id": str,
  "total_introduced": int,      # 曾被 showWord 引入的词数
  "surfaced_count": int,       # 引入后后续有复现的词数
  "unsurfaced_count": int,     # 引入后无后续复现的词数
  "unsurfaced": [              # 缺口列表，按 intro 课序稳定排序
    {"word_id": str, "term": str, "intro_lesson_id": str, "section_id": str}
  ]
}
```

**红线**：`unsurfaced` 条目仅含 `{word_id, term, intro_lesson_id, section_id}`——**不含**题目原文、options/expected、prompt 任何片段（§14.5.3 redaction）。`term` 是词本身（Dock 展示/指令构造需要，等同 §14.5.3「validate level + 计数」级别，非隐私附件原文）。

**Context 注入**：`ExperienceContext.unsurfaced_words: list[dict]` 新字段，由 `_quality_by_section` 在评分循环内一并算出（复用 section 指纹缓存，缓存元组 5→6 维，向后兼容：长度 <6 的 stale 条目视为 miss 重新算）。

## 4. 设计决定三：感知建议（local_suggestions 落点）

**决定**：新增一条 P3 并列建议，仿 `imbalanced_lessons`（K-07）的写法。

| 项 | 内容 |
|----|------|
| 触发条件 | `ctx.unsurfaced_words` 非空 |
| 优先级 | **P3**（与 lesson.balance 同档；属「内容质量缺口」类，不配 P0/P1） |
| 标题 | `为 N 个未复现词补充螺旋题`（N = len） |
| action_id | **`unit.spiral_vocab`**（写树 action，`needs_confirm=True`，`dangerous=False`） |
| scope | `{"count": N, "section_id", "word_ids": [...][:20], "intro_lesson_ids": [...][:20]}`——闭集：仅 id/计数，**无 term/原文** |
| 入口 | Dock 建议 + ⌘K 斜杠候选 `/spiral`（路由黄金集同步 +1）+ 关键词「螺旋复现/词汇螺旋/未复现词/spiral」 |

## 5. 设计决定四：派发与执行（复用 _run_regen_flow）

`_experience_spiral_vocab(scope)` 镜像 `_experience_balance_lesson`（`experience_skills_mixin.py:1422`）：

```text
无 course_dir → statusBar（patch QMessageBox 的测试路径）
scope 无 section_id → 从 _current_node_ref 经 find_lesson/find_unit 回推 section
evaluate_unit_spiral 复算 → 健康(无 unsurfaced) → statusBar「螺旋健康」返回
is_busy_ai → info「有 AI 任务」
QMessageBox.question 确认（列前 12 个未复现词 + 引入课）
拒绝 → inc_suggestion("unit.spiral_vocab","rejected")
确认 → 构造 instruction（保持全部 id/词汇/主题；仅追加复现题，不改已有题）
       → _run_regen_flow(action_id="unit.spiral_vocab", kind="lesson",
                        node_id=<首个引入课 or section 末课>, section=section,
                        job_id=f"spiral-{sid}", job_label="补充词汇螺旋复现",
                        instruction=..., engine_kind="lesson")
```

`_run_regen_flow`（`experience_skills_mixin.py:1497`）**完全复用，不改**：`_deny_ai_write_if_blocked` → `conflict_guard.try_acquire` → `job_tray.start_job` → `AiRequestWorker` → `SectionDiffView` 人确认 → `MergeAiSectionCommand` 入 Undo → metrics + timeline + `_refresh_validate_after_ai`。失败不脏盘（§14.5.2）。

**目标课选择**：首个未复现词的引入课（在其之后追加复现最自然）；若取不到则取该 section 末课。均落在 section 内，`engine_kind="lesson"` 即可。

## 6. 与既有契约的一致性检查

### 6.1 设置键

**决定**：**不新增设置键**。K-08 是「确认后写」技能（非自动应用、非 LLM ghost、非 Soft autopilot），与 K-07 `lesson.balance` 同级——后者亦无独立开关。§6.4「新能力默认关」针对有静默侧效应的能力；经人确认闸的写操作不在列。Observer 模式下经 `can_dispatch` 拒绝（`needs_confirm=True` 写 action，observer 零 AI 写）。

### 6.2 policy.py

**决定**：**不加字段**。无危险 action、无新默认开关；`can_dispatch` 现有规则覆盖（`needs_confirm=True` + observer 零 AI 写 + M-08 预算闸）。

### 6.3 红线（对齐 §6.2 / §14.5）

| 红线 | 落地 |
|------|------|
| 写操作必预览+确认+Undo | `needs_confirm=True` + `SectionDiffView` + `MergeAiSectionCommand` |
| 保 id | instruction 明示「保持全部 id/词汇/主题不变」，仅追加复现题 |
| 无静默 Hard import | 经 `SectionDiffView` 人确认 → MergeAiSectionCommand |
| 不标 dangerous | `dangerous=False`，不入 `DANGEROUS_ACTION_IDS` |
| redaction | Context 字段/scope 闭集，无题目原文 |
| 失败安全 | 评估器永不抛；挂死路径走 statusBar 不模态（offscreen QMessageBox 经测试 patch） |

### 6.4 测试（已执行）

| 层 | 测试 | 数 |
|----|------|----|
| 评估器 | 空/无词/有复现/无复现/同课练习不算/term echo/跨 unit/闭集无原文 | 8 |
| Context | 建议仅在有缺口时产出 / scope 闭集 / 健康无建议 | 2 |
| 路由 | `/spiral` 精确 / 关键词 / 黄金集 +1 | 3 |
| 契约 | needs_confirm 非 dangerous | 1 |
| 派发 | 无 course_dir / 健康 / 确认跑 worker+instruction / 拒绝计 rejected / Guard busy / diff cancel / scope 回推 | 7 |
| **合计** | | **21** |

实测：1674 → **1695**（+21），全量 336s 绿（skipped=3），门禁 32/32 不变。

## 7. 风险与开放项

| 风险 | 缓解 |
|------|------|
| 评估器误判 term echo（短词误命中长 blob） | 复用既有 `_count_practice_hits_for_words` 启发式，与 K-07/coverage 同源，已有测试覆盖；term 须非空且 `in blob` |
| 目标课取不到末课 | section 内遍历 units→lessons 取最后一个有 id 的；空 section 退化为 `node_id=sid`，engine 自行处理 |
| 缓存元组扩维破坏旧条目 | `len(cached) >= 6` 守卫，stale 条目重算；缓存内存级，跨进程不共享 |
| 跨 section 螺旋诉求 | 本切片明确排除；属 K-03 域或远期，届时新切片 |

**开放项**（留远期，不在本切片）：

1. 词频目标值调参（「每个词应复现 ≥N 次」）——需课程设计基线，本切片只判「0 次」硬缺口；
2. 跨 section 螺旋——需全局词表与依赖图，超 K-08 范围；
3. 「在哪个后续课追加」的自动选址策略——当前取首个引入课，未来可按难度/CEFR 智能选址。

**实施记录（v4.37，2026-07-22）**：已按本设计落地。`content_quality.evaluate_unit_spiral`（纯函数，复用 `_iter_lessons`/`_word_ids`/term-echo）；`context_bus` `unsurfaced_words` 字段 + `_quality_by_section` 5→6 维缓存 + P3 建议；`actions.unit.spiral_vocab`（needs_confirm，非 dangerous）；`intent_router` `/spiral` + 关键词（黄金 66→67）；`experience_skills_mixin._experience_spiral_vocab` + 派发分支；`test_experience_spiral_vocab.py` 21 测（含闭集无原文锁定、挂死守卫、id 默保语义）。无新设置键、不动 policy.py、不开新门禁 G。