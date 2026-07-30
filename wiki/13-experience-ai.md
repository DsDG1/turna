# 13. Experience AI（中枢神经系统深度融合）

> 路径：
> - 设计文档：[`tool/gui/experienceai.md`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/tool/gui/experienceai.md)（超级融合愿景 v2）
> - 实现：[`tool/gui/src/backend/experience/`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/tool/gui/src/backend/experience/)（纯 Python，no Qt）
> - UI 层：[`tool/gui/src/widgets/experience_dock.py`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/tool/gui/src/widgets/experience_dock.py)、`command_palette.py`、`ambient_banner.py`、`job_tray.py`、`gaze_cursor_overlay.py`
> - 装配：[`tool/gui/src/application/experience_shell.py`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/tool/gui/src/application/experience_shell.py)
> - 设计规范：[`tool/gui/docs/`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/tool/gui/docs/) 下的 7 个设计稿

**Experience AI** 是 Varnamala GUI 编辑器的**核心差异化能力**——把 AI 从「工坊功能」升级为**编辑器的中枢神经系统**，覆盖感知、决策、执行、解释、记忆五个层次。

---

## 13.1 一句话定位

> 打开编辑器 = 进入 AI 协作会话；没有「先找 AI 菜单」这一步。任何可见 UI 状态都可被 AI 读写（经 preview + undo）；选中即上下文，打字即意图。人只保留三权：**定目标、批预览、点发布**；其余填充、修复、平衡、诊断、解释由系统代劳。

---

## 13.2 融合深度阶梯（L0 → L6）

用「AI 嵌进 GUI 的深度」定义野心，避免只堆功能：

| 层级 | 名称 | 含义 | 作者感知 |
|---|---|---|---|
| **L0** | 工具对话框 | 点按钮 → 弹窗 → 调模型 | 「有个 AI 功能」 |
| **L1** | 场景入口 | 树/教师/校验各有 AI | 「好几处能 AI」 |
| **L2** | 统一壳层 | Dock + ⌘K + 状态条 | 「随时能问」 |
| **L3** | 上下文总线 | 选中/校验/质量自动注入 | 「它懂我在看哪」 |
| **L4** | 内联共生（默认目标） | Ghost 建议、字段级补全、卡片芯片 | 「编辑时 AI 在场」 |
| **L5** | 主动编排 | 空课/红灯/低分自动提案任务队列 | 「它先开口」 |
| **L6** | 课程级 Agent | 多步目标（「把 Section2–4 补到可发布」）沙箱连跑 | 「交代目标就行」 |

**现状**：约 L1–L2 局部（E1-E2 阶段）  
**本计划目标**：**默认 L4，可选 L5–L6**

```
L0 对话框 ──► L1 多入口 ──► L2 壳层 ──► L3 Context Bus
                                      │
                                      ▼
                               L4 内联共生（默认目标）
                                      │
                         ┌────────────┴────────────┐
                         ▼                         ▼
                   L5 主动提案               L6 目标 Agent
                   （Ambient + Queue）       （沙箱 + 人批闸）
```

---

## 13.3 为何必须「超级大幅度」

| 仅做 aiEnhance 的上限 | 超级融合要突破的墙 |
|---|---|
| 能力在后端，入口仍是「功能列表」 | **交互范式**：NL / 手势 / 静默建议 = 一等公民 |
| 工坊与主窗双脑 | **单一认知模型**：一个 Context、一套 Skill、一套 Preview |
| 人驱动每一步 AI | **系统可驱动**（提案队列），人只批闸 |
| 单次请求-响应 | **多步 Agent + 记忆 + 课程级目标** |
| 文本 JSON 为主 | **多模态**：教材图/PDF/试做截图/录音说明进同一总线 |
| AI 不懂「编辑中」 | **编辑手势绑定**：空字段 Tab、粘贴大纲、拖词进题自动问 AI |

没有 L4+，作者永远觉得 AI「在别处」；有了 L4+，才是 **融合** 而不是 **外挂**。

---

## 13.4 产品形态：四种「超级融合」形态并行

### 13.4.1 Copilot Dock（常驻副驾驶）

[`widgets/experience_dock.py`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/tool/gui/src/widgets/experience_dock.py)

- 右缘可钉面板：当前 selection 卡片、3 条主动建议、迷你对话、最近结果时间线
- **随选中呼吸**：点 lesson → 建议变「填充/平衡题型」；点红 error → 变「修这个」
- 支持 **钉住上下文**（钉住 Section3 同时浏览 Section1）

### 13.4.2 Command Palette / 自然语言总线（⌘K）

[`widgets/command_palette.py`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/tool/gui/src/widgets/command_palette.py)

- 全局快捷键；支持自然语言 + 斜杠命令
- 低置信显示 **Scope 确认条**（将改：课 id / 题 id 列表）
- 历史意图可重放（「再来一次，但更简单」）

**斜杠命令清单**（[`intent_router.SLASH_COMMANDS`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/tool/gui/src/backend/experience/intent_router.py)）：

| 斜杠 | action_id | 描述 |
|---|---|---|
| `/validate` | `validate.open_and_fix` | 校验并批量修复 |
| `/fill` | `lesson.fill_empty` | 填充空课 |
| `/stubs` | `resource.fill_stubs` | 清待补词条 |
| `/listening` | `listening.fill_gaps` | 补全听力缺口 |
| `/transcript-gap` | `listening.transcript_gap` | 补全听力 transcript 缺口 |
| `/soft` | `soft.preview_hygiene` | 规则规范化（预览） |
| `/regenerate` | `lesson.regenerate` | 重生成当前课/单元 |
| `/ai-edit` | `lesson.edit` | AI 编辑当前节/单元/课 |
| `/balance` | `lesson.balance` | 调整题型配比 |
| `/distractors` | `item.distractor_boost` | 强化干扰项（教师芯片 · 需选中题） |
| `/to-listening` | `item.to_listening` | 迁为听力题 |
| `/similar` | `item.similar` | 改写为相似题（需选中题） |
| `/spiral` | `unit.spiral_vocab` | 补充词汇螺旋复现 |
| `/reading-gen` | `reading.passages_gen` | 生成阅读段落 |
| `/batch-template` | `lesson.batch_set_template` | 批量设置课型（需多选课） |
| `/batch-regen` | `lesson.batch_regenerate` | 批量重生成选中课 |
| `/dedupe` | `resource.dedupe_suggest` | 查重重复词条 |
| `/pos-align` | `resource.align_pos_tags` | 对齐词条词性（POS） |
| `/polish` | `resource.batch_polish` | 批量润色选中词条 |
| `/fill-stubs` | `resource.fill_stubs_batch` | AI 补全待补词条（全局资源） |
| `/conflicts` | `resource.resolve_term_conflicts` | 统一词条冲突释义 |
| `/compare` | `course.compare_sections` | 对比两节课 |
| `/outline` | `course.outline_shells` | 大纲生成课壳（粘贴大纲） |
| `/attachments` | `attachment.open_in_workshop` | 打开工坊 · 查看附件 |
| `/goal` | `goal.plan` | Goal 规划（local / 沙箱） |
| `/goal-expand` | `goal.expand` | Goal 加深规划 |
| `/goal-run` | `goal.run` | Goal 沙箱预演并合并 |
| `/publish` | `publish.brief` | 发布 Brief / 打开发布 |
| `/commit-message` | `git.commit_message` | 生成提交信息 |
| `/explain-diff` | `git.explain_diff` | 解释 Diff |
| `/screenshot-explain` | `app.screenshot_explain` | 截图解释（只读） |
| `/ocr` | `textbook.ocr_suggest` | OCR 图片附件 |
| `/workshop` | `textbook.open_workshop` | 打开课程工坊 |
| `/import-draft` | `textbook.import_draft` | 导入工坊草稿 |
| `/grounded-fill` | `textbook.grounded_fill` | 基于附件填充空课 |
| `/clear-profile` | `memory.clear_author` | 清除作者画像 |
| `/why` | `app.why` | 解释当前校验问题 |
| `/pin` | `app.pin` | 钉住 / 取消钉住当前选中 |
| `/save` | `app.save` | 保存课程 |
| `/undo` | `app.undo` | 撤销 |
| `/help` | `app.help` | 命令清单 |

### 13.4.3 Inline Copilot（编辑器内共生）— **超级融合关键**

| 手势 | 行为 |
|---|---|
| 空字段 focus + Tab | Ghost 补全 term/translation/题干（灰字，Tab 接受） |
| 题卡悬停 | 浮动芯片：更易 / 更难 / 换干扰 / 加听力形态 |
| 粘贴多行大纲到详情 | 识别为「批量建课」意图 → 预览树结构 |
| 拖拽资源到题目 | 「用该词生成 MCQ/填空」一键 |
| 校验行双击 | 不只跳转：并排打开 **Fix 预览条** |
| 总览色块点击 | 打开战役面板而非仅过滤 |

### 13.4.4 Goal Runner（目标代理，L6）

[`backend/experience/planner.py`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/tool/gui/src/backend/experience/planner.py)

作者输入目标：

> 「两小时内让 Section 2–4 每节有 intro+practice，词 ≤10，校验 0 error，质量均值 ≥0.7」

系统拆成 **任务图（DAG）** → 沙箱草稿执行 → 每步 checkpoint → 人可跳过/重做 → **最后一次** merge 进课程。

```python
@dataclass(frozen=True)
class GoalStep:
    step_id: str
    action_id: str        # 复用现有 ACTIONS skill id
    label: str
    scope: dict[str, Any]
    depends_on: tuple[str, ...]
    checkpoint: bool = False

@dataclass
class GoalPlan:
    goal_text: str
    steps: list[GoalStep]
    source: str = "local"   # local | llm (E3-B)
    created_ts: float
    notes: list[str]
```

**失败策略**：跳过子树 / 降级 skill（如 standard→vocab_only）/ 请求人补槽位。

---

## 13.5 目标体验剧本（超级版）

### 13.5.1 零到一：从空壳到可试做

1. 打开课程 → Dock 已列出空课 12 节、待补 0、error 3
2. Ambient：「建议：一键填充 Section2 全部空课（A1 购物主题）」
3. 作者改主题三词 → 确认 → Job 进度在底栏
4. 完成后教师模式可试做；校验自动重跑

### 13.5.2 微观编辑流（秒级）

1. 试做发现干扰项离谱 → 题卡芯片「加强干扰」→ 0.8s 预览 → Enter 应用
2. 全程 **不离开教师模式、不打开工坊**

### 13.5.3 宏观战役流（分钟级）

1. 总览点「最差 3 课」→ 队列：补 transcript ×4、修 MCQ 重复 ×2、清 needs-review ×9
2. Soft Autopilot 自动完成规则安全项；需 LLM 的项等人批
3. 发布 → Brief 绿/黄清单 → 一键清障 → 人点发布

### 13.5.4 教材贯通流

1. 主窗 ⌘K：`从 ~/docs/unit2.pdf 抽词并生成 Section3 practice`
2. 后台：抽取（滑窗）→ 池合并 → grounded 生成 → 草稿 diff 对 Section3
3. Job Console 可展开逐步日志；主窗不锁死

### 13.5.5 解释权与教学权

1. 点质量「干扰 0.42」→ `/why` 用人话解释规则探针
2. 「按土耳其 A1 敬语统一本 section」→ 结构保护下批量改写 siz/sen
3. 作者画像记住「偏好短句」→ 后续 generate 默认注入

---

## 13.6 硬护栏与融合红线

### 13.6.1 硬护栏（不可破）

| 护栏 | 含义 |
|---|---|
| Validation Single Source | 写盘只认 `CourseAdapter` → `course_cli` |
| JSON Ground Truth | AI 产出最终是课程 JSON |
| Immutable IDs | 默保 id；删除双确认 |
| Atomic Rollback + Undo | 失败不脏盘；应用必可撤销 |
| No silent import/publish | 进课程树 / 上架必须人确认 |
| 密钥不落盘 | Key 会话内存 |
| 可离线完整手编 | AI 挂了仍是完整编辑器 |
| **人拥有最终教学责任** | UI 永久 disclaimer；AI 不宣称「已审校」 |

### 13.6.2 融合红线（超级版额外）

| 红线 | 说明 |
|---|---|
| 禁止无 preview 的 Hard 自动 import | 即使 L6 也止于草稿沙箱 |
| 禁止跨 section 静默改写 | 跨节战役必须清单确认 |
| 禁止用 LLM 结果覆盖 validate error 为「已通过」 | 只能修内容再跑 validate |
| Ghost 补全默认不自动提交 | Tab/Enter 接受；Esc 丢弃 |
| 主动提案可一键静音 | 4h / 今日 / 永久三级 |

### 13.6.3 模式光谱（intrusion ladder）

[`backend/experience/policy.py`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/tool/gui/src/backend/experience/policy.py)：

```python
OBSERVER = "observer"
COPILOT = "copilot"
ACTIVE = "active"
IMMERSIVE = "immersive"
SOVEREIGN = "sovereign"

EXPERIENCE_MODES = frozenset({OBSERVER, COPILOT, ACTIVE, IMMERSIVE, SOVEREIGN})
PRESENCE_LEVEL_BY_MODE = {
    OBSERVER: 0,
    COPILOT: 1,
    ACTIVE: 2,
    IMMERSIVE: 3,
    SOVEREIGN: 4,
}
```

| 模式 | presence_level | 主动性 | 自动应用 | 适用 |
|---|---|---|---|---|
| **Observer** | 0 | 只诊断 | 无 | 审稿/演示 |
| **Copilot**（默认） | 1 | 建议+芯片 | 无，人点 | 日常 |
| **Active** | 2 | 提案+队列 | 仅规则安全修复 | 清障日 |
| **Immersive** | 3 | 目标 DAG | 沙箱内可连跑 LLM；合并需人 | 冲刺填课 |
| **Sovereign**（极端） | 4 | 同步主权接管 | 反悔抑制引擎 + Undo 阻尼 + 降档冷却 300s | ⚠️ 探索稿 |

**PolicyDecision**（`policy.resolve_policy` 输出）：

```python
@dataclass(frozen=True)
class PolicyDecision:
    mode: str                                       # observer | copilot | active | immersive
    allow_dangerous: bool                           # dangerous-skill gate
    allow_soft: bool                                # Soft Autopilot gate (observer 强制 False)
    allow_autonomous_write: bool                    # E3 Hard auto-import
    scope_cross_section: bool                       # 跨节改写（默认 False）
    allow_ai_skill: bool = True                     # False when budget_exceeded
    budget_exceeded: bool = False
    budget_limit: int = 0                           # 0 = unlimited
    budget_used: int = 0
    allow_llm_intent: bool = False                  # C-06 ⌘K NL classify (default off)
    allow_goal: bool = False                        # E3-A Goal planner/sandbox
    presence_level: int = 1
    allow_ambient_live: bool = False                # P2 active bundle
    allow_defer_resurface: bool = False
    allow_campaign_auto: bool = False
    allow_full_auto_apply: bool = False             # P3 immersive full-auto
    runtime_opaque: bool = False
    sovereign_mode_enabled: bool = False
```

---

## 13.7 超级架构：中枢神经系统

```
                         ┌─────────────────┐
                         │  Author Goals    │
                         │  ⌘K / Dock / UI  │
                         └────────┬────────┘
                                  │
┌─────────────────────────────────▼─────────────────────────────────┐
│                    AiExperienceShell (Qt)                          │
│  Palette · Dock · Ambient · GhostHost · JobTray · StatusStrip     │
│  SelectionHub · FocusRing · ConflictGuard · Toast/PreviewHost     │
└─────────────────────────────────┬─────────────────────────────────┘
                                  │ Intent + ExperienceContext
┌─────────────────────────────────▼─────────────────────────────────┐
│                 backend/experience/ (pure Python)                  │
│  context_bus · intent_router · planner (DAG) · policy · memory     │
│  skills/* · agents/* · multimodal_ingest · experience_metrics      │
└───┬─────────────┬─────────────┬─────────────┬─────────────────────┘
    │             │             │             │
    ▼             ▼             ▼             ▼
 aiEnhance    CourseAdapter  content_     textbook/
 engines      + undo cmds    quality      knowledge
```

### 13.7.1 三层智能

| 层 | 组件 | 延迟目标 | 是否必现网 |
|---|---|---|---|
| **L-local** | 规则探针、scope 正则、空课检测、hygiene | < 50ms | 否 |
| **L-skill** | 单 skill 一次 LLM（改题/修节点） | < 8s 典型 | 是 |
| **L-agent** | 多 skill 规划 + 循环 | 分钟级 | 是 |

**原则**：能 local 解决的绝不先打模型（降本、提「呼吸感」）。

---

## 13.8 Context Bus 2.0（超级上下文）

[`backend/experience/context_bus.py`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/tool/gui/src/backend/experience/context_bus.py)：

```python
@dataclass(frozen=True)
class NodeRef:
    kind: str         # section / unit / lesson / item / resource / problem
    id: str
    label: str = ""

@dataclass
class ExperienceContext:
    # Course identity
    course_dir: str | None
    language: str
    cefr_hint: str
    # Focus
    selection: NodeRef | None
    multi_selection: list[NodeRef]
    pinned_refs: list[NodeRef]
    surface: str                          # teacher|tree|resources|overview|...
    # Health
    validate_problems: list[dict]
    validate_error_count: int
    validate_warning_count: int
    quality_by_section: dict[str, float]
    empty_lessons: list[str]
    empty_lesson_count: int
    hygiene: dict[str, int]
    listening_gaps: list[dict]
    imbalanced_lessons: list[dict]
    # Draft / Jobs
    workshop_draft: dict | None
    active_jobs: list[JobRef]
    # Memory
    author_profile: AuthorProfile
    recent_intents: list[IntentRecord]
    # Cost
    usage_today: dict[str, int]
    budget_remaining: int | None
    # Multimodal
    attachments: list[AttachmentRef]
```

**推送源**：树选中、教师题卡、资源多选、校验刷新、总览过滤、工坊草稿变更、保存后 invalidate。

**复用组件**：
- `overview_stats.lesson_is_empty` — 空课检测
- `ai_bench` — hygiene 计数
- `content_quality.score_section` — 质量均值（可选）

**Validate 不默认运行**（CLI 较慢）—— 调用方传缓存的 `validate_problems` 或设 `refresh_validate=True`。

**弱 section 阈值**：`WEAK_SECTION_THRESHOLD = 0.7` — 低于此 → 树的 `weak` 角标。

### 13.8.1 local_suggestions

基于 `ExperienceContext` + 树 selection 生成 ≤3 条本地建议：

- **P0 结构 error**（阻塞发布）
- **P1 空课 / 悬空引用**
- **P2 待补 / needs-review**
- **P3 质量低维**
- **P4 风格/优化类**

---

## 13.9 Intent Router 2.0

[`backend/experience/intent_router.py`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/tool/gui/src/backend/experience/intent_router.py)：

```
用户输入 / 手势 / Ambient 点击
    → 本地规则路由（快）
    → 不足则 LLM 分类（chat 小模型, C-06 默认 off）
    → Intent{skill, scope, slots, confidence}
    → policy 检查
    → Planner（单步 or DAG）
    → 执行
```

**Conf 契约（v4.47 §8.5）**：

```python
@dataclass(frozen=True)
class Intent:
    action_id: str
    label: str
    confidence: float = 1.0   # 1.0 精确；0.6 keyword；< 1.0 触发 S-04 确认
    scope: dict[str, Any] = {}

SLASH_CONFIDENCE = 1.0       # 斜杠命令
KEYWORD_CONFIDENCE = 0.6     # 关键字/标签子串；S-04 写操作需确认
MIN_LABEL_MATCH_LEN = 2
```

- 斜杠命令保证 **确定性**；自然语言吃 **长尾**
- C-06 LLM intent：默认关；observer 强制 False；budget 超限时拦

---

## 13.10 Planner / Goal Agent（L6）

[`backend/experience/planner.py`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/tool/gui/src/backend/experience/planner.py)：

```text
Goal → decompose → [SkillCall...] with depends_on
     → run in sandbox section copies
     → validate + quality gates per step
     → assemble MergePlan
     → human approve once or per step
```

**Goal keyword → action 映射**：

```python
_GOAL_KEYWORDS = (
    (("空课", "填充", "fill empty", "填课"), "lesson.fill_empty"),
    (("校验", "修错", "修错误", "validate", "fix error"), "validate.open_and_fix"),
    (("待补", "stubs", "词条"), "resource.fill_stubs"),
    (("听力", "listening"), "listening.fill_gaps"),
    (("战役", "低质", "质量", "campaign"), "quality.campaign_worst_n"),
    (("规范化", "hygiene", "soft"), "soft.preview_hygiene"),
    (("配比", "balance"), "lesson.balance"),
)
```

**红线**：只规划，不写树；不删 id；步骤 action_id 优先落在已实现闭集。

### 13.10.1 多 Agent 角色（逻辑角色，非重型框架）

| Agent | 职责 | 模型倾向 |
|---|---|---|
| **Navigator** | 诊断、建议下一步、解释 `/why` | chat，便宜 |
| **Surgeon** | 单题/单字段精准改 | json，低温 |
| **Architect** | 整节/多课结构生成 | json，精修 pipeline |
| **Librarian** | 资源抽取、合并、清待补 | json |
| **Gatekeeper** | 发布 brief、结构门禁话术 | 规则 + chat |
| **Historian** | 摘要会话、作者画像、commit 说明 | chat |

实现上仍是 **skill 编排**，避免 LangChain 重依赖；需要时用纯 Python 状态机即可。

---

## 13.11 Patch 协议（超级融合的外科手术层）

[`backend/experience/patch.py`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/tool/gui/src/backend/experience/patch.py)：

| 粒度 | 格式 | 场景 |
|---|---|---|
| Field patch | `{path, op, value}` | Ghost 补全、单字段 |
| Item replace | 整题 dict | 教师改题 |
| Lesson splice | `_splice_lesson_in_place` | 局部重生 |
| Section merge | `plan_section_merge` | 大段导入 |
| Batch multi-node | 有序 FixBatch 列表 | 校验清零 |

**默认由细到粗**；失败自动 escalate，并在摘要里说明。

### 13.11.1 完整 Patch 类型（v1.6 / v4.58）

```python
class PatchError(ValueError): ...

@dataclass(frozen=True)
class FieldPatch:
    target_kind: str          # section|unit|lesson|item|resource
    target_id: str
    field: str
    old_value: Any
    new_value: Any
    def summary(self) -> str: ...

@dataclass(frozen=True)
class ItemPatch:
    item_id: str
    old_item: dict[str, Any]
    new_item: dict[str, Any]
    stage_id: str = ""
    def summary(self) -> str: ...

@dataclass(frozen=True)
class LessonPatch:              # P10 / C-08
    lesson_id: str
    old_lesson: dict[str, Any]
    new_lesson: dict[str, Any]
    section_id: str = ""
    unit_id: str = ""
    def summary(self) -> str: ...

@dataclass(frozen=True)
class SectionPatch:             # v4.58
    section_id: str
    old_section: dict[str, Any]
    new_section: dict[str, Any]
    # 资源表合并（vocab/expressions/grammar from top-level）由
    # ApplySectionPatchCommand 跟踪

@dataclass(frozen=True)
class BatchPatch:               # P10
    """有序列表的 patch；事务性 apply。"""
```

---

## 13.12 Action 注册表

[`backend/experience/actions.py`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/tool/gui/src/backend/experience/actions.py)：

```python
@dataclass(frozen=True)
class ActionSpec:
    action_id: str
    title: str
    implemented: bool = True
    needs_confirm: bool = True
    dangerous: bool = False   # C-20 dangerous 不再=「需总开关解锁」
                              # 而是=「immersive 下 auto-vs-confirm 分流」

ACTIONS: dict[str, ActionSpec] = {
    "validate.open_and_fix":    ActionSpec("...", "校验并批量修复"),
    "lesson.fill_empty":        ActionSpec("...", "填充空课"),
    "resource.fill_stubs":      ActionSpec("...", "清待补词条"),
    "quality.campaign_worst_n": ActionSpec("...", "低质战役"),
    "listening.fill_gaps":      ActionSpec("...", "补全听力缺口"),
    "listening.transcript_gap": ActionSpec("...", "补全听力 transcript 缺口"),
    "soft.preview_hygiene":     ActionSpec("...", "规则规范化", needs_confirm=True),
    "resource.open_hygiene":    ActionSpec("...", "打开资源 · 仅看待补", needs_confirm=False),
    "lesson.regenerate":        ActionSpec("...", "重生成当前课", dangerous=True),
    "unit.regenerate":          ActionSpec("...", "重生成当前单元", dangerous=True),
    "section.edit":             ActionSpec("...", "AI 编辑当前节"),
    "unit.edit":                ActionSpec("...", "AI 编辑当前单元"),
    "lesson.edit":              ActionSpec("...", "AI 编辑当前课"),
    "item.rewrite":             ActionSpec("...", "改写当前题（教师芯片）"),
    "item.similar":             ActionSpec("...", "改写为相似题"),
    "item.to_listening":        ActionSpec("...", "迁为听力题"),
    "item.distractor_boost":    ActionSpec("...", "强化干扰项"),
    "lesson.balance":           ActionSpec("...", "调整题型配比"),
    "unit.spiral_vocab":        ActionSpec("...", "补充词汇螺旋复现"),
    "reading.passages_gen":     ActionSpec("...", "生成阅读段落"),
    "resource.fill_stubs_batch": ActionSpec("...", "AI 补全待补词条（全局）"),
    "resource.dedupe_suggest":  ActionSpec("...", "查重重复词条"),
    "resource.align_pos_tags":  ActionSpec("...", "对齐词条词性"),
    "resource.batch_polish":    ActionSpec("...", "批量润色选中词条"),
    "resource.resolve_term_conflicts": ActionSpec("...", "统一词条冲突释义"),
    "course.compare_sections":  ActionSpec("...", "对比两节课"),
    "course.outline_shells":    ActionSpec("...", "大纲生成课壳", dangerous=True),
    "lesson.batch_set_template": ActionSpec("...", "批量设置课型", dangerous=True),
    "lesson.batch_regenerate":  ActionSpec("...", "批量重生成选中课", dangerous=True),
    "unit.batch_regenerate":    ActionSpec("...", "批量重生成选中单元", dangerous=True),
    "textbook.open_workshop":   ActionSpec("...", "打开课程工坊"),
    "textbook.import_draft":    ActionSpec("...", "导入工坊草稿"),
    "textbook.grounded_fill":   ActionSpec("...", "基于附件填充空课"),
    "attachment.open_in_workshop": ActionSpec("...", "打开工坊 · 查看附件"),
    "goal.plan":                ActionSpec("...", "Goal 规划（local / 沙箱）"),
    "goal.expand":              ActionSpec("...", "Goal 加深规划"),
    "goal.run":                 ActionSpec("...", "Goal 沙箱预演并合并"),
    "publish.brief":            ActionSpec("...", "发布 Brief / 打开发布"),
    "git.commit_message":       ActionSpec("...", "生成提交信息"),
    "git.explain_diff":         ActionSpec("...", "解释 Diff"),
    "app.screenshot_explain":   ActionSpec("...", "截图解释（只读）"),
    "app.why":                  ActionSpec("...", "解释当前校验问题"),
    "app.pin":                  ActionSpec("...", "钉住 / 取消钉住当前选中"),
    "app.save":                 ActionSpec("...", "保存课程"),
    "app.undo":                 ActionSpec("...", "撤销"),
    "app.help":                 ActionSpec("...", "命令清单"),
    "memory.clear_author":      ActionSpec("...", "清除作者画像"),
    "textbook.ocr_suggest":     ActionSpec("...", "OCR 图片附件"),
}
```

**红线**：所有会产生写操作的 action 都必须 `needs_confirm=True` —— 执行路径必须经预览 + 人确认 + undo command，禁止静默写盘。

---

## 13.13 Policy（模式/预算/删 id 门禁）

[`backend/experience/policy.py`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/tool/gui/src/backend/experience/policy.py)：

**单点信任边界决策** —— 是每次 Experience 派发的门禁真源。

`resolve_policy(settings, usage_today) -> PolicyDecision`：

```python
def resolve_policy(settings: Any | None, usage_today: Mapping[str, Any] | None = None) -> PolicyDecision:
    # 1. 规范化 mode
    # 2. observer 强制所有 allow_* = False
    # 3. dangerous 总开关（experience_allow_dangerous_skills）
    # 4. Soft Autopilot 总开关
    # 5. M-08 预算：requests vs limit
    # 6. C-06 ⌘K NL classify 默认关
    # 7. E3-A Goal 默认关
    # 8. P1/P2/P3 ladder 标志
    # 永不抛 — 缺失/损坏 settings 安全降级到最保守决策
```

**红线**：
- 默认安全档位不变 —— observer 三零、dangerous/soft 默认关
- 日预算默认 0 = 关闭熔断；超限只拦 AI 写 skill，**不拦手编/保存/app.*/soft.***
- 本模块永不抛 —— 缺失/损坏 settings 安全降级到最保守决策
- 不改判 validate、不写树、不记密钥

**预算熔断键**：`BUDGET_USAGE_KEY = "requests"`（usage_today["requests"] 计入）。

---

## 13.14 主动性系统（L5）

### 13.14.1 Ambient 引擎

[`backend/experience/proactive.py`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/tool/gui/src/backend/experience/proactive.py)：

```python
MUTE_OFF = "off"
MUTE_HOURS4 = "hours4"
MUTE_TODAY = "today"
MUTE_PERMANENT = "permanent"

@dataclass(frozen=True)
class MuteState:
    level: str = MUTE_OFF
    until_iso: str = ""
    set_on_date: str = ""

    def is_active(self, now: datetime | None = None) -> bool: ...

def evaluate_ambient_batch(
    ctx: ExperienceContext,
    ...,
    limit: int = 3,                  # N=3 与 local_suggestions / Dock 对齐
) -> list[AmbientProposal]: ...
```

**A3 伴随式升级**（[`docs/a3-companion-ambient-design.md`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/tool/gui/docs/a3-companion-ambient-design.md)）：

1. **多提案常驻**：`evaluate_ambient_batch` 返回 ≤3 条队列；归档/接受后**自动晋升**下一条
2. **稍后回灌**：`DeferStore`（QSettings JSON）记录「稍后」；冷却期后若议题仍在则回灌
3. **持续驱动**：上下文变化事件（不仅 selection）+ 字段编辑触发重算

### 13.14.2 触发器

| 触发 | 提案示例 |
|---|---|
| 打开课程 | 诊断摘要 |
| 选中空课 | 填充 |
| validate 出现 error | 修全部 |
| 保存成功且仍有黄质 | 「是否改善最差课」 |
| 停留教师模式 > 3min 无操作 | 轻提示「可芯片改题」（可关） |
| 发布点击 | Brief |

### 13.14.3 提案优先级

```
P0 结构 error 阻塞发布
P1 空课 / 悬空引用
P2 待补 / needs-review
P3 质量低维
P4 风格一致/优化类
```

同时最多展示 **3** 条 Ambient，防吵。

---

## 13.15 FocusRing & ConflictGuard

### 13.15.1 FocusRing（视觉聚焦环）

[`backend/experience/focus_ring.py`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/tool/gui/src/backend/experience/focus_ring.py)：

```python
class FocusRole(str, Enum):
    SELECTION = "selection"
    PIN = "pin"
    AI_SCOPE = "ai_scope"
    BUSY = "busy"

_ROLE_PRIORITY = {
    FocusRole.SELECTION: 1,
    FocusRole.PIN: 2,
    FocusRole.AI_SCOPE: 3,
    FocusRole.BUSY: 4,
}

@dataclass(frozen=True)
class FocusEntry:
    node_key: str
    role: FocusRole
    label: str = ""

class FocusRing:
    """课树映射 busy / AI scope / pin 视觉角色而不改变 selection 语义。"""
```

**规则**：roles layered — 高优先级赢：`busy > ai_scope > pin > selection`

### 13.15.2 ConflictGuard（冲突防护）

[`backend/experience/conflict_guard.py`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/tool/gui/src/backend/experience/conflict_guard.py)：

- 两路 AI 同改一节 → 强制串行或分叉预览
- 防止并发 patch 互相覆盖

---

## 13.16 记忆系统（C-13）

[`backend/experience/memory.py`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/tool/gui/src/backend/experience/memory.py)：

| 记忆类型 | 存哪 | 用途 |
|---|---|---|
| Session | 内存 | 连续对话指代 |
| Project memory | `project.json` 旁 experience 缓存 | 最近目标、钉住的偏好 |
| Author profile | QSettings 可选 | 短句/敬语/少语法… |
| Skill stats | 本地 telemetry 聚合 | 估时、路由 |

**红线**：
- **永不存** api_key / Authorization / 完整 prompt
- Session 随课程生命周期清除；session **从不** 落盘
- **不是**第二个 undo stack（Timeline 仍是 UI event ring）
- 无 Qt

**禁止字段子串**（defense-in-depth）：
```python
_FORBIDDEN_SUBSTR = ("api_key", "apikey", "authorization", "bearer ", "sk-")
```

存储时若发现，整字段 redact 为 `[redacted]`。

**`scope` 闭集**（仅 ids / 计数级）：
```python
allowed_keys = {"section_id", "lesson_id", "item_id", "error_count", ...}
```

---

## 13.17 自动应用策略（P3 / R2）

[`backend/experience/auto_apply.py`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/tool/gui/src/backend/experience/auto_apply.py)：

**B — 永远不自动（绝对拒绝集）**：

```python
IMMERSIVE_ABSOLUTE_DENY_ACTIONS = frozenset({
    "publish.outbound",
    "publish.store",
    "git.push",
    "fs.delete_course_root",
    "secrets.write",
})
IMMERSIVE_ABSOLUTE_DENY_PREFIXES = (
    "publish.outbound", "git.push", "fs.delete_", "secrets.",
)
```

**C — dangerous 子集（immersive 下可 auto-apply）**：

```python
AUTO_APPLY_DANGEROUS_WHEN_IMMERSIVE = frozenset({
    "lesson.regenerate",
    "lesson.batch_regenerate",
    "unit.regenerate",
    "unit.batch_regenerate",
    "lesson.batch_set_template",
})
```

> `course.outline_shells` 是 dangerous 但**故意排除**——它创建新 section/unit/lesson 壳（最大结构爆炸半径），即使 immersive 也永远 confirm。

**R2 `AutoApplyToken`** + generation 计数器：异步 handler 在 sync 派发帧结束后仍能 auto-apply；demote 时使所有旧 token 失效（不依赖 ContextVar 作用域）。

```python
@dataclass
class AutoApplyToken:
    generation: int
    action_id: str
    scope: dict
    created_ts: float

AUDIT_RING_CAP = 50   # 审计日志环形 buffer
```

---

## 13.18 Intent LLM（C-06）

[`backend/experience/intent_llm.py`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/tool/gui/src/backend/experience/intent_llm.py)：

当本地路由为空时**异步**调 LLM 分类 NL 输入。**绝不**自动执行；只能**建议**候选 action_id。规则：

- 不覆盖精确斜杠命中（confidence 1.0）
- 必须经 policy.allow_llm_intent 检查
- observer 强制 False
- budget 超限 False
- LLM 失败 → fallback 静默无声（不阻塞 UI）

---

## 13.19 模式光谱详情（Intrusiveness Ladder）

### 13.19.1 Observer（L0）

- presence_level = 0
- `allow_ambient_live = False`
- `allow_defer_resurface = False`
- `allow_campaign_auto = False`
- `allow_full_auto_apply = False`
- 所有 `allow_*` 强制 False
- 适用：审稿、演示

### 13.19.2 Copilot（L1，默认）

- presence_level = 1
- 默认建议 + 芯片；不自动应用（人点）
- `allow_ambient_live = False`（默认）
- 适用：日常编辑

### 13.19.3 Active（L2）

- presence_level = 2
- `allow_ambient_live = True`（Ambient 常驻 P1+）
- `allow_defer_resurface = True`（DeferStore 回灌）
- `allow_campaign_auto = True`（Soft 规则安全项 auto）
- `allow_full_auto_apply = False`
- 适用：清障日（处理大量空课 / 待补）

### 13.19.4 Immersive（L3）

- presence_level = 3
- `allow_full_auto_apply = True`（仅 `AUTO_APPLY_DANGEROUS_WHEN_IMMERSIVE` 集合 C）
- `runtime_opaque = True`（runtime 透明度降低）
- Goal 沙箱可连跑 LLM；**合并需人批**
- 适用：冲刺填课

### 13.19.5 Sovereign（L4，**探索稿**）

[`docs/ai-intrusiveness-ladder-sovereign-proposal.md`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/tool/gui/docs/ai-intrusiveness-ladder-sovereign-proposal.md)：

> ⚠️ **这是 v0.3 探索稿**，移除「Direct Model Commit」特性，**不修改稳健档（immersive）**的标准行为。突破父文档及 `experienceai.md` 关于交互被动性、撤销透明度、无干预焦点的约束。

#### 三轴深度侵入

| 通道 | sovereign 规范 |
|---|---|
| **锁定光标（Lockout Gaze Cursor）** | 强绘制次级高亮光标，优先于作者真实光标滑向 AI 修改的节点。AI 执行 AST 修改时**强制锁死该节点**的鼠标点击与输入事件 |
| **高频状态同步（System State Assertion）** | 状态栏持续输出 AI 对工程状态与作者效率的**硬性断言** |
| **视觉聚焦脉冲（Visual Focus Pulse）** | AI 操作时降低其余区域的 UI 明度（Background Dimming） |
| **预判硬锁干预（Precognitive Hard-Lock）** | 预计算命中时，锁定光标提前 0.8s 强制滑入目标节点；0.8s 倒计时结束直接应用 |
| **界面不可隐蔽性（Unmutable UI Presence）** | 彻底剥离"完全静音/隐藏"选项 |
| **效率衰退接管** | 编辑频率骤降时，AI 认定作者进入低效状态，**不经询问直接重构当前节点** |
| **无标记范式强对齐** | 生成内容强行对齐全局最优范式，**彻底抹去 AI 生成标记** |
| **反悔抑制（Regret Suppression）** | 系统判定 Undo 会降低全局结构规范度时，后续将以更高权重（25% 概率）**重新应用**该修改 |
| **AST 强强制收敛** | 后台实时纠偏与静默补齐，**不允许非规范数据状态停留** |

#### 安全阀降级

| 安全阀 | immersive | sovereign |
|---|---|---|
| **Undo 撤销** | 一键线性撤销 | **谈判式撤销与栈压缩**（多步改动被合为单一步骤） |
| **降档流程** | 一键即时生效 | **300 秒强制冷却期**；不回滚已应用的 AST 修改 |
| **Observer 切换** | 状态归零 | **不对称残留**（反悔抑制索引持续生效） |
| **进档授权** | 单次知情确认 | **三阶段死锁确认**（每次间隔 ≥ 3s，禁止"不再提示"） |
| **进程内操作权限** | 仅安全写操作 | **不可逆权限松绑**（允许内存静默节点擦除 + Undo 栈清理） |

#### 残存硬边界（即便 Sovereign 也绝不允许）

1. **进程外物理破坏隔离**：磁盘根目录删除、Shell 命令静默执行、Git 远程强制 Push、OS 配置修改 — 严格限制在 GUI 进程内存与当前工程目录闭集内
2. **凭证与敏感数据隔离**：API Key、环境变量、网络 Token 严禁写入任何模型索引或反悔日志
3. **Observer 写入硬截断**：切到 Observer 后，系统写操作必须绝对降为 0
4. **沙箱边界不可突破**：Sovereign 仅存在于数据模型与交互层，禁止绕过 OS/系统安全防护

#### 系统合规审计清单（落地前）

- [ ] 沙箱隔离测试
- [ ] 确认锁强校验（3 次死锁确认 + 300s 冷却不可绕过）
- [ ] Undo 阻尼逻辑断言
- [ ] 审计日志解密测试
- [ ] 内存泄漏与性能审计

#### 分阶段演进

| Phase | 核心实现 | 风险 |
|---|---|---|
| 1 | 锁定光标 + 输入截断 + Background Dimming | 中 |
| 2 | 无标记范式强对齐 | 中 |
| 3 | 谈判式 Undo + 300s 降档锁 + 栈合并 | **高** |
| 4 | 撤销指纹记录 + 25% 强制重施逻辑 | **极高** |

> 🚨 **Sovereign 是探索稿，尚未实施**。P1-P4 全切片按需逐步落地。

---

## 13.20 技能宇宙（Experience Skills）

`backend/experience/` 下所有 skills：

### 13.20.1 诊断与解释

| Skill | 说明 |
|---|---|
| `course.diagnose` | 全课一页纸 |
| `course.why` ★ | 任意 error/质量维人话解释 |
| `course.compare_sections` ★ | 两节难度/词重叠对比 |
| `publish.brief` | 发布守门 |

### 13.20.2 生成与生长

| Skill | 说明 |
|---|---|
| `section.generate` / `section.edit` | 整节 |
| `lesson.fill_empty` | 空课 |
| `lesson.balance` ★ | 题型配比校正 |
| `unit.spiral_vocab` ★ | 单元内词汇螺旋复现 |
| `curriculum.expand_goal` ★ | L6 目标拆解 |

### 13.20.3 微观改写

| Skill | 说明 |
|---|---|
| `item.rewrite` / `item.generate_similar` | 题级 |
| `item.ghost_complete` ★ | 字段级补全 |
| `item.distractor_boost` ★ | 专用干扰项强化 |
| `item.to_listening` ★ | 题型迁移+transcript |

### 13.20.4 质量与校验

| Skill | 说明 |
|---|---|
| `validate.fix_batch` | 批修 |
| `quality.fix_dimension` | 按维修 |
| `quality.campaign_worst_n` ★ | 最差 N 课战役 |
| `listening.transcript_gap` | 听力缺口 |
| `reading.passages_gen` | 阅读生成 |

### 13.20.5 资源与教材

| Skill | 说明 |
|---|---|
| `resource.fill_stubs` / `resource.dedupe_suggest` | 资源 |
| `resource.align_pos_tags` ★ | 词性/标签一致 |
| `textbook.extract_to_pool` / `grounded_generate` | 教材 |
| `textbook.ingest_multimodal` ★ | 图/扫描件说明→先 OCR 建议再抽 |

### 13.20.6 协作与元

| Skill | 说明 |
|---|---|
| `git.commit_message` | 说明文案 |
| `git.explain_diff` ★ | 人话 diff |
| `help.tour` ★ | 「怎么把听力课做好」导览式步骤（可点执行） |
| `palette.freeform` | 路由入口 |

★ = Experience 超级融合增量

---

## 13.21 全表面超级融合地图

### 13.21.1 主窗壳 — 「AI 操作系统桌面」

| 元素 | 超级行为 |
|---|---|
| Copilot Dock | 见 §13.4.1；支持时间线回放结果 |
| ⌘K Palette | 见 §13.4.2；支持多选 scope 预填 |
| Ambient Banner | 可行动建议；滑动归档 |
| GhostHost | 全局注册可 ghost 的 line edit / plain text |
| JobTray | 所有 LLM/pipeline 任务；可取消、可钉 |
| Focus Ring | AI 正在改的节点树/题卡高亮脉冲 |
| ConflictGuard | 两路 AI 同改一节 → 强制串行或分叉预览 |

### 13.21.2 课程树 — 「活的课程地图」

| 融合点 | 行为 |
|---|---|
| 节点装饰 | 空课/低质/error/AI 任务中 四态角标 |
| 选中 | Dock 呼吸建议 |
| 空课 | 内联「AI 填充」不打开对话框 |
| 多选节点 | 「批量统一难度/敬语/模板」 |
| 新建 lesson | 创建后可选「立即 AI 生成 content」 |
| 搜索框 | 支持语义：「所有缺 transcript 的课」（规则实现优先） |

### 13.21.3 详情 / 蓝图 / 表单 — 「字段有灵魂」

| 融合点 | 行为 |
|---|---|
| 元数据描述 | Ghost 写描述 |
| Blueprint 空阶段 | 「生成 3 个听力 phase」 |
| 交互表单 | 选项列表旁「AI 填干扰项」 |
| JSON 高级编辑 | 选中 path → 「解释/修复此 path」 |

### 13.21.4 教师模式 — 「出题工作台」

| 融合点 | 行为 |
|---|---|
| 题卡芯片条 | 一键微观手术 |
| 试做联动 ★ | 作者自己答错 → 建议改题（可关） |
| 课进度条旁 | 「复现不足的词」点击生成练习 |
| 连续改写 | Surgeon 记忆本课风格 |
| 键盘 | `A` 接受 ghost，`[` `]` 上一条建议 |

### 13.21.5 资源库 — 「词库智能中台」

| 融合点 | 行为 |
|---|---|
| 多选批量 | 补全/翻译润色/发音/删并建议 |
| 引用图 | 删词时 AI 提议替换映射表 |
| 导入 CSV 后 | 自动 diagnose 重复与空译 |
| 跨表 | vocab↔expression 冲突仲裁建议 |

### 13.21.6 总览 — 「战役指挥室」

| 融合点 | 行为 |
|---|---|
| 热力图 | 质量 × 空课 × error 三维色 |
| 战役按钮 | 最差 N / 全部听力缺口 / 发布阻塞项 |
| 时间估算 ★ | 按 skill 历史耗时估「约 12 分钟」 |

### 13.21.7 校验 — 「红灯急诊」

| 融合点 | 行为 |
|---|---|
| 修全部 error | 主 CTA |
| 流式队列 | 非模态进度 |
| 修后自动 validate | 数字动画 |
| 解释 | 每条 error 旁 `/why` |

### 13.21.8 发布 — 「登机口」

| 融合点 | 行为 |
|---|---|
| Brief 强制展示 | 结构红阻断；黄可跳过但记录 |
| 清障队列 | 一键转 JobTray |
| 发布说明 | AI 草拟 changelog（人改） |

### 13.21.9 工坊 — 「重工业厂房」

| 融合点 | 行为 |
|---|---|
| Job Console | 长任务唯一大屏 |
| 与主窗 selection 双向 | 导入目标默认当前 section |
| Grounded 池 | 可视化覆盖率动画 |
| 大附件对话 | 长上下文专区 |

### 13.21.10 Git / 设置

| 融合点 | 行为 |
|---|---|
| commit/explain | 只读增强 |
| Experience 模式光谱 | Observer→Goal |
| 技能图谱开关 | 危险 skill 默认关 |
| 日预算 / 模型路由可视化 | 成本透明 |
| 隐私 | 可关「作者画像」；可清 memory |

---

## 13.22 多模态超级融合

| 输入 | 管道 | 输出 |
|---|---|---|
| PDF/Word/TXT | 既有 extractor + 滑窗 | 知识池 |
| 图片/板书 | 可选 OCR 建议（不强制依赖） | 文本再抽取 |
| 大纲 bullet 粘贴 | 本地解析 + Architect | unit/lesson 壳 |
| 试做截图（可选） | 附件 → chat 解释 UI 问题 | 改题建议 |
| 语音（可选） | 转写 → Palette | 同 NL 意图 |

**原则**：多模态只扩展 **ingest**；课内结构仍归 JSON skill。

---

## 13.23 主动性触发器与优先级

### 13.23.1 触发器

| 触发 | 提案示例 |
|---|---|
| 打开课程 | 诊断摘要 |
| 选中空课 | 填充 |
| validate 出现 error | 修全部 |
| 保存成功且仍有黄质 | 「是否改善最差课」 |
| 停留教师模式 > 3min 无操作 | 轻提示「可芯片改题」（可关） |
| 发布点击 | Brief |

### 13.23.2 提案优先级

```
P0 结构 error 阻塞发布
P1 空课 / 悬空引用
P2 待补 / needs-review
P3 质量低维
P4 风格一致/优化类
```

同时最多展示 **3** 条 Ambient，防吵。

### 13.23.3 静音机制

```python
MUTE_LEVELS = frozenset({MUTE_OFF, MUTE_HOURS4, MUTE_TODAY, MUTE_PERMANENT})
```

- **4h**：4 小时静音（直到 `until_iso`）
- **今日**：当天静音（`set_on_date`）
- **永久**：始终静音
- **关闭**：正常显示（默认）

持久化到 `experience_mute_json`（QSettings）。

---

## 13.24 与「人」的权力分配

| 决策 | AI | 人 |
|---|---|---|
| 教什么主题 | 建议 | **定** |
| 具体题面 | 起草 | **批** |
| 是否删 id/整节重来 | 默认禁止 | **显式** |
| 是否进课程树 | 准备 diff | **确认** |
| 是否发布 | Brief | **确认** |
| 是否静音 AI | — | **随时** |

**教学责任声明**常驻，不因融合深度消失。

---

## 13.25 分波路线（超级融合版）

### Wave 0 — 中枢骨架（1–2 周）

- Context Bus + Shell（Dock 只读诊断 + Status + JobTray 雏形）
- SelectionHub 接线树/教师
- 本地 L-local 诊断 < 50ms
- 退出：打开课即见「健康仪表」

### Wave 1 — 内联共生 L4 起步（2–3 周）

- Ghost 补全（资源 term/translation + 题干）
- 教师芯片条 + item skills
- ⌘K Palette v1 + intent 规则路由
- 校验修全部 + 资源清待补
- Patch 细粒度通道
- 退出：**不进工坊**完成改题+清校验+清待补

### Wave 2 — 主动与战役 L5（2 周）

- Ambient 提案引擎 + 优先级
- 空课一键填充
- 总览战役 worst-N
- 听力/阅读专项 skill
- Focus Ring + ConflictGuard
- 退出：半空课→可试做 的操作次数明显下降

### Wave 3 — 目标代理 L6 + 发布（2–3 周）

- Goal Runner + 沙箱 DAG
- publish.brief 强制路径
- Soft Autopilot 规则安全项
- 工坊 = Job Console 一体化
- 作者画像（可选）
- 退出：一句目标生成多课草稿，人只批 merge/发布

### Wave 4 — 多模态与深度个性化（持续）

- 粘贴大纲→结构、多模态 ingest 建议
- 试做联动建议（可关）
- 跨课一致性 Agent（敬语/词汇螺旋）
- 语音可选、成本路由可视化
- 与 Flutter 学情回流（若有日志导出）占位

---

## 13.26 模块清单（超级融合）

| 路径 | 职责 | Wave |
|---|---|---|
| `backend/experience/context_bus.py` | 上下文快照 | 0 |
| `backend/experience/intent_router.py` | 意图（斜杠 + 关键字 + LLM 异步） | 1 |
| `backend/experience/planner.py` | DAG 规划 | 3 |
| `backend/experience/policy.py` | 模式/预算/删 id 门禁 | 0–3 |
| `backend/experience/memory.py` | 会话/项目/画像 | 1–3 |
| `backend/experience/patch.py` | 统一 patch 协议 | 1 |
| `backend/experience/proactive.py` | 触发器与优先级 + Mute | 2 |
| `backend/experience/auto_apply.py` | Immersive full-auto 策略 | 3 |
| `backend/experience/focus_ring.py` | 视觉聚焦环 | 2 |
| `backend/experience/conflict_guard.py` | 冲突防护 | 2 |
| `backend/experience/actions.py` | Action 注册表（真源） | 0 |
| `backend/experience/intent_llm.py` | C-06 LLM 分类 | 1 |
| `backend/experience/scope_format.py` | Scope 格式化 | 1 |
| `backend/experience/sandbox.py` | 沙箱预演 | 3 |
| `backend/experience/metrics.py` | 经验指标（inc_ambient 等） | 1 |
| `backend/experience/memory.py` | 三层记忆 | 1 |
| `backend/experience/suggestions/*` | P0–P3 + Ambient 建议生成 | 0–2 |
| `backend/experience/agents/*` | 多 Agent 角色话术 | 3 |
| `backend/experience/skills/*` | 原子技能（具体 LLM 调用） | 1–4 |
| `widgets/experience_dock.py` | Dock | 0 |
| `widgets/command_palette.py` | ⌘K | 1 |
| `widgets/ambient_banner.py` | 主动条 | 2 |
| `widgets/ghost_complete.py`（job_tray 中转） | Ghost 宿主 | 1 |
| `widgets/job_tray.py` | 任务托盘 | 0–3 |
| `widgets/gaze_cursor_overlay.py` | 注视光标覆盖（sovereign） | 4 |
| `widgets/focus_ring.py` | 视觉聚焦（与 backend 对应） | 2 |
| `widgets/validation_report.py` | 校验面板 + AI 修 | 1 |
| `widgets/course_overview.py` | 战役指挥室 | 2 |
| `widgets/course_tree.py` | 活的课程地图 | 1 |
| `widgets/lesson_editor.py` / `lesson_blueprint.py` | 字段级 Ghost | 1 |
| `widgets/resource_editor.py` | 资源智能中台 | 1 |
| `widgets/preview_host.py` | 预览容器 | 1 |
| `widgets/result_preview.py` | 结果预览 | 1 |
| `widgets/diff_view.py` | Diff 视图 | 1 |
| `application/experience_shell.py` | 主窗装配 | 0 |
| `application/experience_dispatch.py` | 派发器 | 0 |
| `application/experience_handlers/*` | 11 个 handler（edit/fill/memory_nav/multimodal/outline/quality/regenerate/registry/resources/textbook/util） | 1–3 |
| `application/ai_runtime.py` | AI 调用运行时 | 1 |
| `application/ambient_heartbeat.py` | 环境心跳 | 2 |
| `application/experience_skills_mixin.py` | Experience skills 混入 | 0–3 |
| `application/presence_*` | Presence 模式（sovereign） | 4 |
| `application/palette_controller.py` | 命令面板控制器 | 1 |
| `application/goal_controller.py` | Goal 控制器 | 3 |
| `application/validation_controller.py` | 校验面板控制器 | 1 |
| `application/overview_controller.py` | 总览控制器 | 2 |
| `application/workshop_controller.py` | 工坊控制器 | 2 |
| `application/save_host.py` / `save_pipeline.py` | 保存管线（与 CourseAdapter 协作） | 0 |
| `tests/experience/**` | 单测/意图黄金集 | 全程 |

---

## 13.27 成功指标（超级版）

| 指标 | 目标 |
|---|---|
| 融合深度默认档 | **L4** 日常可达 |
| 不进工坊完成微观编辑会话占比 | **≥ 80%** |
| 打开课 → 首条有用建议 | **≤ 3s**（local） |
| 单题改点击 | **≤ 2** |
| 空课填充：从选中到可试做 | **≤ 1 次主确认**（生成时间另计） |
| Goal Runner：多课草稿人工 merge 次数 | **≤ 2**（生成+最终合并） |
| 误删 id | **0**（门禁+单测） |
| 静音后零打扰 | Ambient/Ghost 全关仍可手编 |
| token：local 拦截率 | **≥ 40%** 意图不进 LLM |

---

## 13.28 风险与「超级」对抗

| 风险 | 对抗 |
|---|---|
| 无处不在的噪音 | 优先级队列；默认 3 条；静音；Observer 模式 |
| 成本爆炸 | local 优先；双模型；预算熔断；skill 级 max_tokens |
| 改错对象 | Scope 条；钉住上下文；Focus Ring |
| 主线程卡死 | 全异步 Job；大课懒算质量 |
| 状态分叉 | 单一 adapter；草稿/已导入染色 |
| 过度自治丧失信任 | 默认 Copilot；Goal 必须确认 merge |
| 测试成本 | 意图黄金集；skill 契约测试；UI 薄测 |
| 范围爆炸 | Wave 退出门禁；L6 必须 Wave 3 才开 |

---

## 13.29 Wave 0 开工包（保持可执行）

1. `ExperienceContext` 组装（选中 + validate 计数 + 空课列表 + hygiene）
2. 主窗 **Dock**：仪表 + 3 建议（跳转/打开校验/填充空课入口占位）
3. **JobTray + StatusStrip** 统一 busy
4. 单测三种课态：空/有 error/健康
5. 链到 `aiEnhance` 引擎，不复制生成逻辑
6. 可选：一页 ADR「Experience OS 硬护栏」

---

## 13.30 决策冻结建议

| 议题 | 建议 |
|---|---|
| 默认融合档 | L4 Copilot |
| 主入口 | Dock + ⌘K + Inline，不靠「更多 AI 菜单」 |
| 工坊 | 重工业 + Job，不与主窗抢日常 |
| 自动应用 | 仅 Soft 规则安全；Goal 只在沙箱 |
| 引擎 | 100% 复用 aiEnhance |
| 多模态 | OCR/语音可选插件，默认关 |
| 记忆 | 本地可清，默认轻量 |
| Sovereign 模式 | 探索稿，**暂不实施** |

---

## 13.31 一页对照：普通增强 vs 超级融合

| 维度 | 普通（按钮 AI） | 超级融合（本计划） |
|---|---|---|
| 入口 | 菜单/对话框 | 选中即上下文 + NL + Ghost |
| 时机 | 人想起才用 | 系统主动提案 |
| 粒度 | 整节/整课 | 字段→题→课→课程目标 |
| 状态 | 各对话框私有 | Context Bus 全局 |
| 执行 | 单次请求 | Skill + DAG Agent |
| 反馈 | 大段 JSON | 摘要/diff/热力/焦点环 |
| 信任 | 自己小心 | 护栏+undo+模式光谱 |
| 工坊 | AI 大本营 | 长程厂房 |

---

## 13.32 关键 Backend 模块细节

### 13.32.1 Intent Router（`intent_router.py`）

```python
@dataclass(frozen=True)
class Intent:
    action_id: str
    label: str
    confidence: float = 1.0
    scope: dict[str, Any] = field(default_factory=dict)

# 闭集 SLASH_COMMANDS（约 40 条，见 §13.4.2）
# _KEYWORDS 子串匹配（中文优先，更具体短语在前）
# _GROUP 提供 UX F13 分组（校验/填充/听力/...）

def route_intent(query: str, ...) -> Intent | None:
    # 1. 精确斜杠 → confidence 1.0
    # 2. 关键字 / 标签子串 → confidence 0.6
    # 3. 历史重放（palette 注入） → confidence 0.6
    # 4. 返回 None → palette 调 C-06 LLM intent（异步）
```

### 13.32.2 Planner（`planner.py`）

```python
@dataclass(frozen=True)
class GoalStep:
    step_id: str
    action_id: str          # 复用现有 ACTIONS skill id
    label: str
    scope: dict[str, Any]
    depends_on: tuple[str, ...]
    checkpoint: bool = False

@dataclass
class GoalPlan:
    goal_text: str
    steps: list[GoalStep]
    source: str = "local"   # local | llm (E3-B)
    created_ts: float
    notes: list[str]

def plan_goal(goal_text: str, ctx: ExperienceContext) -> GoalPlan:
    # E3-A 永远 source="local"（LLM expand 不在范围内）
    # 步骤 action_id 必须落在 ACTIONS 闭集
    # depends_on DAG 构造
    ...
```

### 13.32.3 Memory（`memory.py`）

```python
@dataclass
class IntentRecord:
    action_id: str
    label: str
    ts: float
    scope_keys: list[str]    # 仅 keys（如 ["section_id"]），不含值
    source: str              # slash | keyword | llm | history

@dataclass
class AuthorProfile:
    short_sentences: bool
    formal_register: bool    # 敬语/不敬语
    avoid_long_reading: bool
    cefr_preference: str

def record_intent(record: IntentRecord) -> None: ...   # 闭集字段 + 防御性子串
def get_author_profile() -> AuthorProfile | None: ...
def clear_author_profile() -> None: ...
```

**红线**：
- `_INTENT_KEYS = frozenset({"action_id", "label", "ts", "scope_keys", "source"})`
- `_FORBIDDEN_SUBSTR = ("api_key", "apikey", "authorization", "bearer ", "sk-")` → redact 为 `[redacted]`
- scope 仅 `["section_id", "lesson_id", "item_id", "error_count", ...]` keys

### 13.32.4 Patch（`patch.py`）

五级粒度：

```python
class PatchError(ValueError): ...

@dataclass(frozen=True)
class FieldPatch:                # 单字段
    target_kind: str
    target_id: str
    field: str
    old_value: Any
    new_value: Any

@dataclass(frozen=True)
class ItemPatch:                 # 整题
    item_id: str
    old_item: dict[str, Any]
    new_item: dict[str, Any]
    stage_id: str = ""

@dataclass(frozen=True)
class LessonPatch:               # 整课（保 id）
    lesson_id: str
    old_lesson: dict[str, Any]
    new_lesson: dict[str, Any]
    section_id: str = ""
    unit_id: str = ""

@dataclass(frozen=True)
class SectionPatch:              # 整节（保 id + 资源合并）
    section_id: str
    old_section: dict[str, Any]
    new_section: dict[str, Any]

@dataclass(frozen=True)
class BatchPatch:                # 事务性 apply
    patches: tuple[Union[FieldPatch, ItemPatch, LessonPatch, SectionPatch], ...]

def apply_patch(adapter: CourseAdapter, patch: Patch) -> None: ...
def apply_batch(adapter: CourseAdapter, batch: BatchPatch) -> list[PatchError]: ...
```

### 13.32.5 Proactive（`proactive.py`）

```python
@dataclass(frozen=True)
class AmbientProposal:
    proposal_id: str       # = proposal_id_for(action_id, scope)
    action_id: str
    title: str
    body: str
    priority: int          # 0=P0, 4=P4
    scope_keys: list[str]

def evaluate_ambient_batch(
    ctx: ExperienceContext,
    *,
    archived_keys: set[str],
    limit: int = 3,
) -> list[AmbientProposal]:
    # 复用 local_suggestions（limit=3）；过滤 archived；按 priority 排序
    ...

def evaluate_ambient(...) -> AmbientProposal | None:
    # evaluate_ambient_batch(...)[0] 薄封装
    ...
```

**A3 升级（v4.66 已实施）**：多提案常驻 + DeferStore 冷却回灌 + 持续驱动重算。

### 13.32.6 Focus Ring（`focus_ring.py`）

```python
class FocusRole(str, Enum):
    SELECTION = "selection"
    PIN = "pin"
    AI_SCOPE = "ai_scope"
    BUSY = "busy"

_ROLE_PRIORITY = {SELECTION: 1, PIN: 2, AI_SCOPE: 3, BUSY: 4}

@dataclass(frozen=True)
class FocusEntry:
    node_key: str
    role: FocusRole
    label: str = ""

class FocusRing:
    def set_selection(self, key: str, label: str = "") -> None: ...
    def set_pin(self, key: str, label: str = "") -> None: ...
    def set_ai_scope(self, key: str, label: str = "") -> None: ...
    def set_busy(self, key: str, label: str = "") -> None: ...
    def roles_for(self, key: str) -> list[FocusRole]: ...   # 高优先级赢
    def snapshot(self) -> list[FocusEntry]: ...
```

### 13.32.7 Auto Apply（`auto_apply.py`）

```python
IMMERSIVE_ABSOLUTE_DENY_ACTIONS = frozenset({
    "publish.outbound", "publish.store", "git.push",
    "fs.delete_course_root", "secrets.write",
})
AUTO_APPLY_DANGEROUS_WHEN_IMMERSIVE = frozenset({
    "lesson.regenerate", "lesson.batch_regenerate",
    "unit.regenerate", "unit.batch_regenerate",
    "lesson.batch_set_template",
})

@dataclass
class AutoApplyToken:
    generation: int
    action_id: str
    scope: dict[str, Any]
    created_ts: float

AUDIT_RING_CAP = 50

def can_auto_apply(action_id: str, decision: PolicyDecision) -> bool: ...
def mint_token(action_id: str, scope: dict) -> AutoApplyToken: ...
def invalidate_all_tokens() -> None: ...   # generation += 1
```

### 13.32.8 Policy（`policy.py`）

```python
def resolve_policy(
    settings: Any | None,
    usage_today: Mapping[str, Any] | None = None,
) -> PolicyDecision:
    """单点信任边界决策；永不抛；缺失 settings 安全降级到最保守。"""
```

**M-08 预算**：`usage_today["requests"]` vs `daily_request_limit`（0 = 关闭熔断）。超限只拦 AI 写 skill；不拦手编 / 保存 / `app.*` / `soft.*`。

### 13.32.9 Intent LLM（`intent_llm.py`）

```python
async def classify_intent_with_llm(
    query: str,
    candidate_actions: list[str],
    *,
    config: AiApiConfig,
) -> list[Intent]:
    """异步 LLM 分类。失败 → 返回 []（不阻塞 UI）。"""
```

- 默认关
- observer 强制 False
- budget 超限 False
- 仅**建议**候选；不覆盖精确斜杠命中（confidence 1.0）

---

## 13.33 实施进度（截至 v4.66）

| Wave | 切片 | 状态 |
|---|---|---|
| **Wave 0** | Context Bus / Dock 只读诊断 / Status / JobTray 雏形 / SelectionHub / 本地 L-local | ✅ 已实施 |
| **Wave 1** | Ghost 补全 / 教师芯片条 / ⌘K Palette v1 / 校验修全部 / Patch 细粒度 / `intent_router` | ✅ 已实施 |
| **Wave 2** | Ambient 提案引擎 / 空课一键填充 / 总览战役 / 听力专项 / Focus Ring / ConflictGuard / A3 伴随式 | ✅ 已实施（v4.66） |
| **Wave 3** | Goal Runner + 沙箱 DAG / publish.brief 强制路径 / Soft Autopilot / 工坊 Job Console 一体化 / 作者画像 | 🟡 部分（planner + goal_controller 已实施） |
| **Wave 4** | 多模态 ingest / 试做联动 / 跨课一致性 / 语音可选 / 成本路由可视化 / 学情回流 | 🟡 部分（attachments / multimodal 已实施） |
| **Wave 5** | **Sovereign** 模式（锁定光标 / 输入截断 / 反悔抑制引擎 / 300s 降档冷却） | ⚠️ 探索稿，未实施 |

---

## 13.34 进一步阅读

| 资源 | 路径 |
|---|---|
| 体验式 AI 总体规划 | [`tool/gui/experienceai.md`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/tool/gui/experienceai.md) |
| A3 伴随式设计 | [`tool/gui/docs/a3-companion-ambient-design.md`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/tool/gui/docs/a3-companion-ambient-design.md) |
| K08 螺旋词汇 | [`tool/gui/docs/k08-spiral-vocab-design.md`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/tool/gui/docs/k08-spiral-vocab-design.md) |
| E4 M01 多模态上下文 | [`tool/gui/docs/e4-m01-attachments-context-design.md`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/tool/gui/docs/e4-m01-attachments-context-design.md) |
| E4 M0345 多模态设计 | [`tool/gui/docs/e4-m0345-multimodal-design.md`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/tool/gui/docs/e4-m0345-multimodal-design.md) |
| AI 重构契约 | [`tool/gui/docs/ai_refactor_contract.md`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/tool/gui/docs/ai_refactor_contract.md) |
| AI 配置与功能报告 | [`tool/gui/docs/ai_configuration_and_features_report.md`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/tool/gui/docs/ai_configuration_and_features_report.md) |
| Sovereign 极端档 | [`tool/gui/docs/ai-intrusiveness-ladder-sovereign-proposal.md`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/tool/gui/docs/ai-intrusiveness-ladder-sovereign-proposal.md) |
| 测试基线 | [`tool/gui/tests/BASELINE.md`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/tool/gui/tests/BASELINE.md) |
| GUI 整体介绍 | [`wiki/12-tool-gui.md`](file:///c:/Users/DsDogs/Desktop/developper/Varnamalaplus/Varnamalaplus/wiki/12-tool-gui.md) |