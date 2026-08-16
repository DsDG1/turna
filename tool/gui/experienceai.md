# Experience AI — 超级深度 AI 融合计划（全 GUI）

> **状态**：规划稿 v2（超级融合愿景）  
> **日期**：2026-07-21  
> **定位**：在 [`ai_configuration_and_features_report.md`](./docs/ai_configuration_and_features_report.md) 引擎能力之上，把 AI 从「工坊功能」升级为 **课程编辑器的中枢神经系统** —— 感知、决策、执行、解释、记忆五层贯通  
> **范围**：`tool/gui` 全部表面 + 编辑手势 + 数据生命周期 + 协作/发布边界  
> **层级关系**：
>
> | 文档 | 解决什么 |
> |------|----------|
> | `docs/ai_configuration_and_features_report.md` | 生成稳、质量分、流水线、可感知补丁 |
> | 布局压缩（工坊） | 参数不重复、一屏可用 |
> | **本文件 experienceai** | **AI 如何成为默认交互语言，而不是附加按钮** |

---

## 0. 超级野心（三句话）

1. **打开编辑器 = 进入 AI 协作会话**；没有「先找 AI 菜单」这一步。  
2. **任何可见 UI 状态都可被 AI 读写**（经 preview + undo）；选中即上下文，打字即意图。  
3. **人只保留三权**：定目标、批预览、点发布；其余填充、修复、平衡、诊断、解释由系统代劳。

激进 ≠ 失控。JSON 真相源、`course_cli` 写盘门禁、ID 不可默删、导入/发布需人确认 —— 这些是 **硬护栏**。超级融合的是 **深度、广度、主动性、多模态与多 Agent 编排**。

---

## 1. 融合深度阶梯（L0 → L6）

用「AI 嵌进 GUI 的深度」定义野心，避免只堆功能：

| 层级 | 名称 | 含义 | 作者感知 |
|------|------|------|----------|
| **L0** | 工具对话框 | 点按钮 → 弹窗 → 调模型 | 「有个 AI 功能」 |
| **L1** | 场景入口 | 树/教师/校验各有 AI | 「好几处能 AI」 |
| **L2** | 统一壳层 | Dock + ⌘K + 状态条 | 「随时能问」 |
| **L3** | 上下文总线 | 选中/校验/质量自动注入 | 「它懂我在看哪」 |
| **L4** | 内联共生 | Ghost 建议、字段级补全、卡片芯片 | 「编辑时 AI 在场」 |
| **L5** | 主动编排 | 空课/红灯/低分自动提案任务队列 | 「它先开口」 |
| **L6** | 课程级 Agent | 多步目标（「把 Section2–4 补到可发布」）沙箱连跑 | 「交代目标就行」 |

**现状约 L1–L2 局部**。本计划目标 **默认 L4，可选 L5–L6**。

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

## 2. 为何必须「超级大幅度」

| 仅做 aiEnhance 的上限 | 超级融合要突破的墙 |
|----------------------|-------------------|
| 能力在后端，入口仍是「功能列表」 | **交互范式**：NL / 手势 / 静默建议 = 一等公民 |
| 工坊与主窗双脑 | **单一认知模型**：一个 Context、一套 Skill、一套 Preview |
| 人驱动每一步 AI | **系统可驱动**（提案队列），人只批闸 |
| 单次请求-响应 | **多步 Agent + 记忆 + 课程级目标** |
| 文本 JSON 为主 | **多模态**：教材图/PDF/试做截图/录音说明进同一总线 |
| AI 不懂「编辑中」 | **编辑手势绑定**：空字段 Tab、粘贴大纲、拖词进题自动问 AI |

没有 L4+，作者永远觉得 AI「在别处」；有了 L4+，才是 **融合** 而不是 **外挂**。

---

## 3. 产品形态：四种「超级融合」形态并行

### 3.1 Copilot Dock（常驻副驾驶）

- 右缘可钉面板：当前 selection 卡片、3 条主动建议、迷你对话、最近结果时间线。  
- **随选中呼吸**：点 lesson → 建议变「填充/平衡题型」；点红 error → 变「修这个」。  
- 支持 **钉住上下文**（钉住 Section3 同时浏览 Section1）。

### 3.2 Command Palette / 自然语言总线（⌘K）

- 全局快捷键；支持自然语言 + 斜杠命令（`/fix` `/gen` `/fill` `/brief` `/why`）。  
- 低置信显示 **Scope 确认条**（将改：课 id / 题 id 列表）。  
- 历史意图可重放（「再来一次，但更简单」）。

### 3.3 Inline Copilot（编辑器内共生）— **超级融合关键**

| 手势 | 行为 |
|------|------|
| 空字段 focus + Tab | Ghost 补全 term/translation/题干（灰字，Tab 接受） |
| 题卡悬停 | 浮动芯片：更易 / 更难 / 换干扰 / 加听力形态 |
| 粘贴多行大纲到详情 | 识别为「批量建课」意图 → 预览树结构 |
| 拖拽资源到题目 | 「用该词生成 MCQ/填空」一键 |
| 校验行双击 | 不只跳转：并排打开 **Fix 预览条** |
| 总览色块点击 | 打开战役面板而非仅过滤 |

### 3.4 Goal Runner（目标代理，L6）

作者输入目标，例如：

> 「两小时内让 Section 2–4 每节有 intro+practice，词 ≤10，校验 0 error，质量均值 ≥0.7」

系统拆成 **任务图（DAG）** → 沙箱草稿执行 → 每步 checkpoint → 人可跳过/重做 → **最后一次** merge 进课程。

---

## 4. 目标体验剧本（超级版）

### 4.1 零到一：从空壳到可试做

1. 打开课程 → Dock 已列出空课 12 节、待补 0、error 3。  
2. Ambient：「建议：一键填充 Section2 全部空课（A1 购物主题）」。  
3. 作者改主题三词 → 确认 → Job 进度在底栏。  
4. 完成后教师模式可试做；校验自动重跑。

### 4.2 微观编辑流（秒级）

1. 试做发现干扰项离谱 → 题卡芯片「加强干扰」→ 0.8s 预览 → Enter 应用。  
2. 全程 **不离开教师模式、不打开工坊**。

### 4.3 宏观战役流（分钟级）

1. 总览点「最差 3 课」→ 队列：补 transcript ×4、修 MCQ 重复 ×2、清 needs-review ×9。  
2. Soft Autopilot 自动完成规则安全项；需 LLM 的项等人批。  
3. 发布 → Brief 绿/黄清单 → 一键清障 → 人点发布。

### 4.4 教材贯通流

1. 主窗 ⌘K：`从 ~/docs/unit2.pdf 抽词并生成 Section3 practice`。  
2. 后台：抽取（滑窗）→ 池合并 → grounded 生成 → 草稿 diff 对 Section3。  
3. Job Console 可展开逐步日志；主窗不锁死。

### 4.5 解释权与教学权

1. 点质量「干扰 0.42」→ `/why` 用人话解释规则探针。  
2. 「按土耳其 A1 敬语统一本 section」→ 结构保护下批量改写 siz/sen。  
3. 作者画像记住「偏好短句」→ 后续 generate 默认注入。

---

## 5. 硬护栏与融合红线

### 5.1 硬护栏（不可破）

| 护栏 | 含义 |
|------|------|
| Validation Single Source | 写盘只认 `CourseAdapter` → `course_cli` |
| JSON Ground Truth | AI 产出最终是课程 JSON |
| Immutable IDs | 默保 id；删除双确认 |
| Atomic Rollback + Undo | 失败不脏盘；应用必可撤销 |
| No silent import/publish | 进课程树 / 上架必须人确认 |
| 密钥不落盘 | Key 会话内存 |
| 可离线完整手编 | AI 挂了仍是完整编辑器 |
| **人拥有最终教学责任** | UI 永久 disclaimer；AI 不宣称「已审校」 |

### 5.2 融合红线（超级版额外）

| 红线 | 说明 |
|------|------|
| 禁止无 preview 的 Hard 自动 import | 即使 L6 也止于草稿沙箱 |
| 禁止跨 section 静默改写 | 跨节战役必须清单确认 |
| 禁止用 LLM 结果覆盖 validate error 为「已通过」 | 只能修内容再跑 validate |
| Ghost 补全默认不自动提交 | Tab/Enter 接受；Esc 丢弃 |
| 主动提案可一键静音 | 4h / 今日 / 永久三级 |

### 5.3 模式光谱

| 模式 | 主动性 | 自动应用 | 适用 |
|------|--------|----------|------|
| **Observer** | 只诊断 | 无 | 审稿/演示 |
| **Copilot**（默认） | 建议+芯片 | 无，人点 | 日常 |
| **Autopilot Soft** | 提案+队列 | 仅规则安全修复 | 清障日 |
| **Autopilot Goal** | 目标 DAG | 沙箱内可连跑 LLM；合并需人 | 冲刺填课 |
| **Voice**（可选） | 同 Copilot | 无 | 无障碍/演示 |

---

## 6. 超级架构：中枢神经系统

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

### 6.1 三层智能

| 层 | 组件 | 延迟目标 | 是否必现网 |
|----|------|----------|------------|
| **L-local** | 规则探针、scope 正则、空课检测、hygiene | &lt; 50ms | 否 |
| **L-skill** | 单 skill 一次 LLM（改题/修节点） | &lt; 8s 典型 | 是 |
| **L-agent** | 多 skill 规划 + 循环 | 分钟级 | 是 |

**原则**：能 local 解决的绝不先打模型（降本、提「呼吸感」）。

### 6.2 Context Bus 2.0（超级上下文）

```python
@dataclass
class ExperienceContext:
    # 课程
    course_dir: str | None
    language: str
    cefr_hint: str
    # 焦点
    selection: NodeRef | None
    multi_selection: list[NodeRef]
    pinned_refs: list[NodeRef]
    surface: str                    # teacher|tree|resources|overview|...
    # 健康
    validate_problems: list[dict]
    quality_by_section: dict[str, float]
    empty_lessons: list[str]
    hygiene: dict[str, int]
    # 草稿与任务
    workshop_draft: dict | None
    active_jobs: list[JobRef]
    # 记忆
    author_profile: AuthorProfile   # 短句/敬语/忌长阅读...
    recent_intents: list[IntentRecord]
    # 成本
    usage_today: dict[str, int]
    budget_remaining: int | None
    # 多模态暂存
    attachments: list[AttachmentRef]
```

**推送源**：树选中、教师题卡、资源多选、校验刷新、总览过滤、工坊草稿变更、保存后 invalidate。

### 6.3 Intent Router 2.0

```
用户输入 / 手势 / Ambient 点击
    → 本地规则路由（快）
    → 不足则 LLM 分类（chat 小模型）
    → Intent{skill, scope, slots, confidence}
    → policy 检查
    → Planner（单步 or DAG）
    → 执行
```

斜杠命令保证 **确定性**；自然语言吃 **长尾**。

### 6.4 Planner / Goal Agent（L6）

```text
Goal → decompose → [SkillCall...] with depends_on
     → run in sandbox section copies
     → validate + quality gates per step
     → assemble MergePlan
     → human approve once or per step
```

失败策略：跳过子树 / 降级 skill（如 standard→vocab_only）/ 请求人补槽位。

### 6.5 多 Agent 角色（逻辑角色，非重型框架）

| Agent | 职责 | 模型倾向 |
|-------|------|----------|
| **Navigator** | 诊断、建议下一步、解释 /why | chat，便宜 |
| **Surgeon** | 单题/单字段精准改 | json，低温 |
| **Architect** | 整节/多课结构生成 | json，精修 pipeline |
| **Librarian** | 资源抽取、合并、清待补 | json |
| **Gatekeeper** | 发布 brief、结构门禁话术 | 规则 + chat |
| **Historian** | 摘要会话、作者画像、commit 说明 | chat |

实现上仍是 **skill 编排**，避免 LangChain 重依赖；需要时用纯 Python 状态机即可。

### 6.6 Patch 协议（超级融合的外科手术层）

| 粒度 | 格式 | 场景 |
|------|------|------|
| Field patch | `{path, op, value}` | Ghost 补全、单字段 |
| Item replace | 整题 dict | 教师改题 |
| Lesson splice | `_splice_lesson_in_place` | 局部重生 |
| Section merge | plan_section_merge | 大段导入 |
| Batch multi-node | 有序 FixBatch 列表 | 校验清零 |

**默认由细到粗**；失败自动 escalate，并在摘要里说明。

---

## 7. 技能宇宙（扩展表）

在既有 skill 上 **超级加码**（标注 ★ 为超级融合增量）：

### 7.1 诊断与解释

| Skill | 说明 |
|-------|------|
| `course.diagnose` | 全课一页纸 |
| `course.why` ★ | 任意 error/质量维人话解释 |
| `course.compare_sections` ★ | 两节难度/词重叠对比 |
| `publish.brief` | 发布守门 |

### 7.2 生成与生长

| Skill | 说明 |
|-------|------|
| `section.generate` / `section.edit` | 整节 |
| `lesson.fill_empty` | 空课 |
| `lesson.balance` ★ | 题型配比校正 |
| `unit.spiral_vocab` ★ | 单元内词汇螺旋复现 |
| `curriculum.expand_goal` ★ | L6 目标拆解 |

### 7.3 微观改写

| Skill | 说明 |
|-------|------|
| `item.rewrite` / `item.generate_similar` | 题级 |
| `item.ghost_complete` ★ | 字段级补全 |
| `item.distractor_boost` ★ | 专用干扰项强化 |
| `item.to_listening` ★ | 题型迁移+transcript |

### 7.4 质量与校验

| Skill | 说明 |
|-------|------|
| `validate.fix_batch` | 批修 |
| `quality.fix_dimension` | 按维修 |
| `quality.campaign_worst_n` ★ | 最差 N 课战役 |
| `listening.transcript_gap` | 听力缺口 |
| `reading.passages_gen` | 阅读生成 |

### 7.5 资源与教材

| Skill | 说明 |
|-------|------|
| `resource.fill_stubs` / `resource.dedupe_suggest` | 资源 |
| `resource.align_pos_tags` ★ | 词性/标签一致 |
| `textbook.extract_to_pool` / `grounded_generate` | 教材 |
| `textbook.ingest_multimodal` ★ | 图/扫描件说明→先 OCR 建议再抽 |

### 7.6 协作与元

| Skill | 说明 |
|-------|------|
| `git.commit_message` | 说明文案 |
| `git.explain_diff` ★ | 人话 diff |
| `help.tour` ★ | 「怎么把听力课做好」导览式步骤（可点执行） |
| `palette.freeform` | 路由入口 |

---

## 8. 全表面超级融合地图

### 8.1 主窗壳 — 「AI 操作系统桌面」

| 元素 | 超级行为 |
|------|----------|
| Copilot Dock | 见 §3.1；支持时间线回放结果 |
| ⌘K Palette | 见 §3.2；支持多选 scope 预填 |
| Ambient Banner | 可行动建议；滑动归档 |
| GhostHost | 全局注册可 ghost 的 line edit / plain text |
| JobTray | 所有 LLM/pipeline 任务；可取消、可钉 |
| Focus Ring | AI 正在改的节点树/题卡高亮脉冲 |
| ConflictGuard | 两路 AI 同改一节 → 强制串行或分叉预览 |

### 8.2 课程树 — 「活的课程地图」

| 融合点 | 行为 |
|--------|------|
| 节点装饰 | 空课/低质/error/AI 任务中 四态角标 |
| 选中 | Dock 呼吸建议 |
| 空课 | 内联「AI 填充」不打开对话框 |
| 多选节点 | 「批量统一难度/敬语/模板」 |
| 新建 lesson | 创建后可选「立即 AI 生成 content」 |
| 搜索框 | 支持语义：「所有缺 transcript 的课」（规则实现优先） |

### 8.3 详情 / 蓝图 / 表单 — 「字段有灵魂」

| 融合点 | 行为 |
|--------|------|
| 元数据描述 | Ghost 写描述 |
| Blueprint 空阶段 | 「生成 3 个听力 phase」 |
| 交互表单 | 选项列表旁「AI 填干扰项」 |
| JSON 高级编辑 | 选中 path → 「解释/修复此 path」 |

### 8.4 教师模式 — 「出题工作台」

| 融合点 | 行为 |
|--------|------|
| 题卡芯片条 | 一键微观手术 |
| 试做联动 ★ | 作者自己答错 → 建议改题（可关） |
| 课进度条旁 | 「复现不足的词」点击生成练习 |
| 连续改写 | Surgeon 记忆本课风格 |
| 键盘 | `A` 接受 ghost，`[` `]` 上一条建议 |

### 8.5 资源库 — 「词库智能中台」

| 融合点 | 行为 |
|--------|------|
| 多选批量 | 补全/翻译润色/发音/删并建议 |
| 引用图 | 删词时 AI 提议替换映射表 |
| 导入 CSV 后 | 自动 diagnose 重复与空译 |
| 跨表 | vocab↔expression 冲突仲裁建议 |

### 8.6 总览 — 「战役指挥室」

| 融合点 | 行为 |
|--------|------|
| 热力图 | 质量 × 空课 × error 三维色 |
| 战役按钮 | 最差 N / 全部听力缺口 / 发布阻塞项 |
| 时间估算 ★ | 按 skill 历史耗时估「约 12 分钟」 |

### 8.7 校验 — 「红灯急诊」

| 融合点 | 行为 |
|--------|------|
| 修全部 error | 主 CTA |
| 流式队列 | 非模态进度 |
| 修后自动 validate | 数字动画 |
| 解释 | 每条 error 旁 `/why` |

### 8.8 发布 — 「登机口」

| 融合点 | 行为 |
|--------|------|
| Brief 强制展示 | 结构红阻断；黄可跳过但记录 |
| 清障队列 | 一键转 JobTray |
| 发布说明 | AI 草拟 changelog（人改） |

### 8.9 工坊 — 「重工业厂房」

| 融合点 | 行为 |
|--------|------|
| Job Console | 长任务唯一大屏 |
| 与主窗 selection 双向 | 导入目标默认当前 section |
| Grounded 池 | 可视化覆盖率动画 |
| 大附件对话 | 长上下文专区 |

### 8.10 Git / 设置

| 融合点 | 行为 |
|--------|------|
| commit/explain | 只读增强 |
| Experience 模式光谱 | Observer→Goal |
| 技能图谱开关 | 危险 skill 默认关 |
| 日预算 / 模型路由可视化 | 成本透明 |
| 隐私 | 可关「作者画像」；可清 memory |

---

## 9. 多模态超级融合

| 输入 | 管道 | 输出 |
|------|------|------|
| PDF/Word/TXT | 既有 extractor + 滑窗 | 知识池 |
| 图片/板书 | 可选 OCR 建议（不强制依赖） | 文本再抽取 |
| 大纲 bullet 粘贴 | 本地解析 + Architect | unit/lesson 壳 |
| 试做截图（可选） | 附件 → chat 解释 UI 问题 | 改题建议 |
| 语音（可选） | 转写 → Palette | 同 NL 意图 |

**原则**：多模态只扩展 **ingest**；课内结构仍归 JSON skill。

---

## 10. 记忆与个性化（本地）

| 记忆类型 | 存哪 | 用途 |
|----------|------|------|
| Session | 内存 | 连续对话指代 |
| Project memory | `project.json` 旁 experience 缓存 | 最近目标、钉住的偏好 |
| Author profile | QSettings 可选 | 短句/敬语/少语法… |
| Skill stats | 本地 telemetry 聚合 | 估时、路由 |

**不做**云端用户画像；**可一键清除**。

---

## 11. 主动性系统（L5）

### 11.1 触发器

| 触发 | 提案示例 |
|------|----------|
| 打开课程 | 诊断摘要 |
| 选中空课 | 填充 |
| validate 出现 error | 修全部 |
| 保存成功且仍有黄质 | 「是否改善最差课」 |
| 停留教师模式 &gt; 3min 无操作 | 轻提示「可芯片改题」（可关） |
| 发布点击 | Brief |

### 11.2 提案优先级

```
P0 结构 error 阻塞发布
P1 空课 / 悬空引用
P2 待补 / needs-review
P3 质量低维
P4 风格一致/优化类
```

同时最多展示 **3** 条 Ambient，防吵。

---

## 12. 与「人」的权力分配

| 决策 | AI | 人 |
|------|----|----|
| 教什么主题 | 建议 | **定** |
| 具体题面 | 起草 | **批** |
| 是否删 id/整节重来 | 默认禁止 | **显式** |
| 是否进课程树 | 准备 diff | **确认** |
| 是否发布 | Brief | **确认** |
| 是否静音 AI | — | **随时** |

**教学责任声明**常驻，不因融合深度消失。

---

## 13. 分波路线（超级融合版）

### Wave 0 — 中枢骨架（1–2 周）

- Context Bus + Shell（Dock 只读诊断 + Status + JobTray 雏形）  
- SelectionHub 接线树/教师  
- 本地 L-local 诊断 &lt;50ms  
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

## 14. 模块清单（超级融合）

| 路径 | 职责 | Wave |
|------|------|------|
| `backend/experience/context_bus.py` | 上下文快照 | 0 |
| `backend/experience/intent_router.py` | 意图 | 1 |
| `backend/experience/planner.py` | DAG 规划 | 3 |
| `backend/experience/policy.py` | 模式/预算/删 id | 0–3 |
| `backend/experience/memory.py` | 会话/项目/画像 | 1–3 |
| `backend/experience/patch.py` | 统一 patch 协议 | 1 |
| `backend/experience/proactive.py` | 触发器与优先级 | 2 |
| `backend/experience/skills/*` | 原子技能 | 1–4 |
| `backend/experience/agents/*` | 角色话术/默认模型 | 3 |
| `widgets/experience_dock.py` | Dock | 0 |
| `widgets/command_palette.py` | ⌘K | 1 |
| `widgets/ambient_banner.py` | 主动条 | 2 |
| `widgets/ghost_complete.py` | Ghost 宿主 | 1 |
| `widgets/job_tray.py` | 任务托盘 | 0–3 |
| `application/experience_shell.py` | 主窗装配 | 0 |
| 各 surface 接线 | tree/teacher/… | 1–3 |
| `tests/experience/**` | 单测/意图黄金集 | 全程 |

---

## 15. 成功指标（超级版）

| 指标 | 目标 |
|------|------|
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

## 16. 风险与「超级」对抗

| 风险 | 对抗 |
|------|------|
| 无处不在的噪音 | 优先级队列；默认 3 条；静音；Observer 模式 |
| 成本爆炸 | local 优先；双模型；预算熔断；skill 级 max_tokens |
| 改错对象 | Scope 条；钉住上下文；Focus Ring |
| 主线程卡死 | 全异步 Job；大课懒算质量 |
| 状态分叉 | 单一 adapter；草稿/已导入染色 |
| 过度自治丧失信任 | 默认 Copilot；Goal 必须确认 merge |
| 测试成本 | 意图黄金集；skill 契约测试；UI 薄测 |
| 范围爆炸 | Wave 退出门禁；L6 必须 Wave 3 才开 |

---

## 17. Wave 0 开工包（保持可执行）

1. `ExperienceContext` 组装（选中 + validate 计数 + 空课列表 + hygiene）  
2. 主窗 **Dock**：仪表 + 3 建议（跳转/打开校验/填充空课入口占位）  
3. **JobTray + StatusStrip** 统一 busy  
4. 单测三种课态：空/有 error/健康  
5. 链到 `aiEnhance` 引擎，不复制生成逻辑  
6. 可选：一页 ADR「Experience OS 硬护栏」

---

## 18. 决策冻结建议

| 议题 | 建议 |
|------|------|
| 默认融合档 | L4 Copilot |
| 主入口 | Dock + ⌘K + Inline，不靠「更多 AI 菜单」 |
| 工坊 | 重工业 + Job，不与主窗抢日常 |
| 自动应用 | 仅 Soft 规则安全；Goal 只在沙箱 |
| 引擎 | 100% 复用 aiEnhance |
| 多模态 | OCR/语音可选插件，默认关 |
| 记忆 | 本地可清，默认轻量 |

---

## 19. 一页对照：普通增强 vs 超级融合

| 维度 | 普通（按钮 AI） | 超级融合（本计划） |
|------|-----------------|-------------------|
| 入口 | 菜单/对话框 | 选中即上下文 + NL + Ghost |
| 时机 | 人想起才用 | 系统主动提案 |
| 粒度 | 整节/整课 | 字段→题→课→课程目标 |
| 状态 | 各对话框私有 | Context Bus 全局 |
| 执行 | 单次请求 | Skill + DAG Agent |
| 反馈 | 大段 JSON | 摘要/diff/热力/焦点环 |
| 信任 | 自己小心 | 护栏+undo+模式光谱 |
| 工坊 | AI 大本营 | 长程厂房 |

---

## 20. 变更记录

| 日期 | 说明 |
|------|------|
| 2026-07-21 | v1：Experience OS 初版 |
| 2026-07-21 | **v2 超级融合**：L0–L6 深度阶梯；Inline/Ghost/Goal Runner；三层智能与多 Agent 角色；Patch 协议；主动性系统；多模态；扩展技能宇宙与表面地图；指标与风险加强 |

---

## 21. 参考

| 资源 | 路径 |
|------|------|
| 引擎与感知 | `tool/gui/docs/ai_configuration_and_features_report.md` |
| GUI README | `tool/gui/README.md` |
| 测试基线 | `tool/gui/tests/BASELINE.md` |
| 课程契约 | `docs/authoring/course-layout.md` |
| 教师指南 | `docs/authoring/teacher-guide.md` |
| Git ADR | `docs/decisions/0021`–`0026` |
