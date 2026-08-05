# AI 伴学工具丰富计划

> **范围声明**：本计划只覆盖「学习者侧」AI 能力——课内辅导、深度讲解、复习诊断、词典/错题辅助、引擎体验与 AI Hub 伴学入口。  
> **明确排除**：许愿生成、教材导入、课程/课节一键生成、`AiLessonHelper` 课程编辑助手、GUI 工坊批量生成等**内容作者向**功能。  
> **现状基线**：`docs/project-guide.md` §7；引擎层 `lib/application/ai/engine/`；伴学实现主要在 `ai_hint_provider.dart`、`hint_genres.dart`、`srs_tutor_provider.dart`、课内 sheet / AI Hub。

---

## 1. 目标与原则

### 1.1 产品目标

把 AI 从「偶尔点一下的提示按钮」升级为贯穿学、练、复的**本地优先伴学助手**：

| 场景 | 现在 | 目标 |
|------|------|------|
| 课内做题 | 提示聊天 + 4 类深度讲解 | 流式回复、快捷追问、可收藏、可衔接错因 |
| 错题 / 弱词 | SRS 导师一键生成复习小节 | 诊断报告 + 可选生成；先懂再练 |
| 词典 / 任意词条 | 无 AI | 释义扩展、例句、近义辨析、记忆钩 |
| Anki 刷卡 | 仅 notetype 映射建议 | 复习中「这张卡讲一下」 |
| AI Hub | 入口与生成类功能混排 | **伴学区 / 创作区**清晰分离 |
| 引擎体验 | 可用但偏工程向 | 偏好、流式、用量、失败可恢复 |

### 1.2 设计原则

1. **不泄答案优先**：默认启发式辅导；仅在用户已提交或主动要求时进入「对答案/错因」模式（沿用 `AiQuestionContext.correctLabel` 不默认入 prompt 的策略）。
2. **引擎单一出入口**：所有新能力只走 `AiEngine.chat` / `requestJson` + 缓存 + 取消；禁止平行 HTTP。
3. **领域无关引擎 + 领域 prompt 在 provider**：新 genre / 新 provider 不污染 `engine/`。
4. **结构化优先于散文**：深度讲解继续 typed JSON + 容错 `fromJson`；聊天类可流式纯文本。
5. **本地优先**：API key 仅本机；对话/收藏默认同机持久化；无云端账号。
6. **可选依赖网络**：未配置 API 时入口可见但可配置/引导。
7. **与课程生成解耦**：伴学产物是「解释 / 笔记 / 练习建议 / 复习小节」，不把 section 树生成当作主路径（SRS 导师保留为可选支线）。

### 1.3 非目标（本轮不做）

- 许愿模式 / 教材导入 / 整课生成的产品化加深  
- 云端同步对话、多人协作、付费订阅网关  
- 口语发音评分硬件链路（可预留接口，不承诺端到端）  
- 用 AI 改写官方内置 Turkish 课程 JSON 包  

---

## 2. 现状盘点（伴学相关）

### 2.1 已具备

| 能力 | 关键代码 | 成熟度 |
|------|----------|--------|
| 统一引擎（双模型、流式、缓存、取消、预设） | `engine/*` | 高 |
| 课内提示聊天（不直接给答案） | `AiHintProvider` + `AiHintChatPage` | 中（无流式 UI、上下文偏薄） |
| 深度 4 genre | grammar / synonyms / decompose / whyWrong | 中（sheet 可用，入口分散） |
| 按错题 / 弱词生成复习小节 | `SrsTutorProvider` + `TutorLaunchSheet` | 中（直接生成课，缺「先诊断」） |
| AI Hub | Hero / Continue / Start | 中（与生成入口混在一起） |
| API 配置页 + 连通性探测 | `AiApiConfigPage` | 高 |
| Anki notetype AI 建议 | `AnkiNotetypeAI` | 中（导入时用，复习时无） |

### 2.2 主要缺口

1. **无题上下文的自由伴学对话**（词典页、复习页、Hub 直达）。  
2. **提示聊天未接 `onChunk` 流式**，体感慢。  
3. **学习者画像未注入 prompt**（CEFR、近期错题标签、偏好母语/讲解深度）。  
4. **深度讲解结果不可沉淀**（无收藏、无进笔记、无「再出 2 道同类」轻量练习）。  
5. **错题本 / 弱词页无一键 AI 解释**。  
6. **AI Hub 信息架构偏创作**，伴学价值被淹没。  
7. **最近任务仅内存环**，杀进程即失；Continue 对 hint 也无 route 回放。  
8. **回复语言 / 讲解深度 / 是否允许给答案** 无用户偏好。  
9. **用量与失败态**（超时、额度、模型不可用）体验不统一。  

---

## 3. 目标信息架构

### 3.1 AI Hub 重组（伴学优先）

```
AI 助手
├── Hero：引擎状态 + 配置（不变）
├── 继续：最近伴学任务（持久化子集）
├── 伴学（本计划主区）
│   ├── 自由问答（新）
│   ├── 深度讲解（可无当前题：手动贴句）
│   ├── 学习诊断（错题/弱词报告，新）
│   ├── 按错题复习 / 弱词复习（现有 SRS 导师，降权为「生成练习」）
│   └── 收藏的讲解（新）
└── 创作（现有，折叠或次级入口）
    ├── 许愿设计课程
    └── 教材导入
```

设置「AI 工具」文案建议改为侧重伴学（副标题不再默认强调「设计课程与教材导入」）；创作入口仍保留但视觉降权。

### 3.2 课内入口

保持右下角 AI 按钮，菜单分层：

1. **快速提示**（现有 chat）  
2. **深度讲解**（4 genre，whyWrong 仅答后可用）  
3. **追问建议 chips**（新：固定模板，不耗配置）  

### 3.3 横切入口

| 表面 | 动作 |
|------|------|
| 词典详情 / 搜索结果 | 讲这个词 / 近义 / 例句 / 记忆钩 |
| 错题列表 item | 为什么错 / 如何记 |
| 弱词页 | 辨析与用法 |
| SRS 复习卡面 | 轻量讲解（不打断评分手势主路径） |
| Anki 复习 | 本卡讲解（字段脱敏后送模型） |

---

## 4. 功能分期

### Phase A — 体验底座（约 1 周）

**目标**：现有伴学「更好用、更像助手」，不大改产品面。

| # | 项 | 说明 | 验收 |
|---|----|------|------|
| A1 | 流式提示聊天 | `AiHintProvider.explainQuestion` / `ask` 接 `onChunk`；气泡打字机 | 首 token 可见延迟明显下降；取消仍干净 |
| A2 | 讲解偏好 | 设置：回复语言（中/英/目标语）、深度（简/标准/细）、是否允许最终给答案 | 写入 prefs；system prompt 读取 |
| A3 | 快捷追问 chips | 如「举个例子」「更简单说」「对比近义词」「这是什么语法」 | 一点即发，不进入二级页 |
| A4 | 错误态统一 | 超时 / 401 / 网络 / 取消 映射到 `AppStrings` 友好文案 + 重试 | 不出现原始 exception 堆栈式文案 |
| A5 | 深度讲解可复制 + 分享文本 | 已有 copy 路径补齐四 genre | 一键复制结构化纯文本 |
| A6 | Hub 伴学/创作分区 | Start 区拆分；生成类移入「创作」折叠 | 首屏以伴学为主 |

**不动**：引擎协议、课程 schema、SRS 导师生成逻辑。

---

### Phase B — 上下文变聪明（约 1–1.5 周）

**目标**：同一引擎，prompt 带上「这个人最近在学什么」。

| # | 项 | 说明 | 验收 |
|---|----|------|------|
| B1 | `LearnerAiContext` 组装器 | 纯函数/小服务：目标语、CEFR（当前 section level）、近 7 日错题摘要（去重 top-N）、弱词 top-N、最近完成课 | 单测覆盖截断与空数据 |
| B2 | 注入 hint / depth / free-chat system prompt | 短摘要，token 预算可控（如 ≤800 字） | 关闭开关可禁用（隐私/省 token） |
| B3 | 题型感知提示策略 | MCQ / fillBlank / translate / reading 不同引导句 | 各至少 1 条 golden prompt 快照测试 |
| B4 | 答后模式 | 有 `userAnswer` 时允许更强纠错；无答案时禁止泄露 | 与现规则一致且可测 |
| B5 | 深度 genre 自动预填 | 从 `promptLabel` 抽句子；grammar 可用启发式空填或「请模型自判考点」 | 减少手动输入 |

**可选小增强**：whyWrong 结果一键「加入错题笔记字段」（本地）。

---

### Phase C — 新伴学表面（约 1.5–2 周）

**目标**：离开「当前题目」也能用 AI。

#### C1 自由伴学对话 `AiTutorChat`

- 入口：AI Hub、词典、Play Hub 快捷入口。  
- Provider：`AiTutorChatProvider`（独立于 `AiHintProvider` 的题上下文机）。  
- 模式 tabs（轻量 persona，非课程生成）：  
  - 答疑  
  - 造句批改（用户贴句 → 纠错 + 更地道说法）  
  - 情景对话（点餐/问路等角色扮演，**回合制聊天**，不生成课程 JSON）  
- 流式 + 取消 + 最近任务 `AiTaskKind.tutorChat`。

#### C2 词典 AI 扩展

- 在词典词条卡增加「AI 扩展」：释义扩展、3 例句、近义 1 组、记忆钩。  
- 走 `requestJson` + 小型 schema（仿 `hint_genres`）。  
- 缓存 key 含 `term + language + genre`，重复点开秒开。

#### C3 学习诊断报告（不生成课）

- 输入：错题 FIFO + 弱词 + 可选 SRS due。  
- 输出 typed：`weakAreas[]`、`priorityTips[]`、`exampleDrillIdeas[]`（文本建议，**不是** section JSON）。  
- UI：可滚动报告卡；次级 CTA「用这些点生成复习课」→ 复用现有 `SrsTutorProvider`（可选，明确标注为生成练习）。

#### C4 错题本 / 弱词一键讲解

- 列表 swipe 或 overflow：`AiHintProvider` 合成 `AiQuestionContext` 或直接 depth whyWrong / grammar。  
- 批量：一次最多 N 条摘要（防爆 token）。

#### C5 讲解收藏夹

- 本地表或 prefs JSON：`saved_explanations`（title, body, source, language, createdAt）。  
- 从 hint 气泡 / depth 卡 / 词典扩展「收藏」。  
- Hub「收藏的讲解」只读列表 + 搜索。

---

### Phase D — 复习与 Anki 伴学（约 1 周）

| # | 项 | 说明 |
|---|----|------|
| D1 | 课程 SRS 复习卡「讲讲这张」 | 展示面后的次要按钮；不阻塞评分 |
| D2 | Anki 复习 AI 讲解 | 用已映射字段拼 context；遵守 Anki 计划：AI 只建议/解释，不改答案键 |
| D3 | 复习后微总结 | 本 session 错了 k 张 → 3 条复习建议（可选，session 结束时一次调用） |

---

### Phase E — 平台与引擎打磨（可与 C/D 并行）

| # | 项 | 说明 |
|---|----|------|
| E1 | 最近任务持久化 | 伴学类 task 落盘（max 20）；创作类仍可仅内存 |
| E2 | 简易用量统计 | 本地累计 tokens/调用次数（若 API 返回 usage）；设置页展示，可清除 |
| E3 | 离线/未配置引导 | 统一 empty state：去配置 / 看新手指南 AI 节 |
| E4 | 预设扩展 | 按需增加兼容 OpenAI 的常用中转预设（仍 custom 可覆盖） |
| E5 | 安全 | 导出数据时 API key 永不进入导出包；设置文案对齐 |

---

## 5. 技术设计要点

### 5.1 模块落点

```
lib/application/ai/
  engine/                    # 不改公共契约；最多加 usage 回调
  learner_ai_context.dart    # 新：学习上下文组装
  ai_hint_provider.dart      # 增强：流式、偏好、chips
  hint_genres.dart           # 扩展：dictionary / diagnosis 等 typed 结果
  ai_tutor_chat_provider.dart# 新：自由对话
  ai_diagnosis_provider.dart # 新：诊断报告（非 section JSON）
  ai_saved_explanations.dart # 新：收藏
lib/views/ai/
  ai_hub_page.dart           # 分区
  ai_tutor_chat_page.dart    # 新
  ai_diagnosis_page.dart     # 新
  ai_saved_list_page.dart    # 新
  components/…               # 流式气泡、chips、错误条复用
```

### 5.2 Prompt 与解析

- 聊天：`chat` + 流式；system 用中文规则 + 可选 `LearnerAiContext` 块。  
- 结构化：`requestJson` 或现有 `_typedChat` 模式；一律容错 `fromJson`。  
- **禁止**在伴学 provider 中复用 `ai_prompt_builder.dart` 的课程 schema 大块（那是生成用）。

### 5.3 状态与生命周期

- `AiHintProvider`：继续单题会话；换题 `reset` + generation token（已有）。  
- 自由对话：独立 history；支持「新会话」。  
- 收藏与偏好：进程外持久化；recent tasks 至少伴学类持久化。

### 5.4 测试策略

| 层 | 内容 |
|----|------|
| 单元 | `LearnerAiContext` 截断；genre `fromJson` 容错；偏好拼 system prompt |
| Provider | fake `AiEngine`：流式分片顺序、取消、supersede generation |
| Widget | chips 发送、未配置 empty、Hub 分区可见性 |
| 回归 | 不跑通真实 LLM；课程生成相关测试保持绿且本计划不改其契约 |

### 5.5 与 SRS 导师的边界

| | 学习诊断 (C3) | SRS 导师 (现有) |
|--|---------------|-----------------|
| 产出 | 报告文本 / tips | section JSON → 可玩课程 |
| 是否写课程树 | 否 | 是 |
| 主 CTA | 读懂薄弱点 | 生成并开练 |
| 本计划态度 | **主推** | 保留为诊断页次级 CTA |

---

## 6. 里程碑与优先级

```
P0  Phase A（流式、偏好、chips、Hub 分区、错误态）
P0  Phase B1–B4（学习者上下文 + 题型策略）
P1  Phase C1–C2（自由对话 + 词典 AI）
P1  Phase C3–C5（诊断、错题一键讲、收藏）
P2  Phase D（SRS/Anki 复习伴学）
P2  Phase E（持久化、用量、引导）
```

建议发布切片：

1. **v伴学.1**：A + B → 体感与正确性  
2. **v伴学.2**：C1 + C2 → 新入口可感知  
3. **v伴学.3**：C3–C5 + D → 闭环  
4. **v伴学.4**：E 打磨  

---

## 7. 风险与对策

| 风险 | 对策 |
|------|------|
| Token / 费用上升 | 上下文截断、缓存、诊断限频、设置「注入学习数据」开关 |
| 模型胡编语法 | UI 标注「AI 可能有误」；结构化字段短而可扫；不自动改官方课 |
| 与生成功能耦合 | Hub 分区 + 禁止伴学引用 course schema prompt |
| 流式半截 JSON | 深度 genre 仍非流式 JSON；仅纯文本聊天流式 |
| 隐私 | 学习数据默认仅进 prompt、不上传他处；可关上下文注入 |

---

## 8. 成功指标（产品/工程）

- 课内 AI 从点击到首字 **流式可见**（有网、已配置）。  
- AI Hub 首屏 **≥70% 入口为伴学**（创作折叠后）。  
- 词典与错题本 **无需进入课程播放器** 即可完成一次有用讲解。  
- 伴学相关单测增量覆盖 provider 取消/流式/解析；`flutter analyze` 清洁。  
- 课程生成路径行为与测试 **零回归**（契约不变）。

---

## 9. 建议的首轮实现清单（可直接开工）

若只开一个迭代，推荐严格按序：

1. `AiHintProvider` 流式 + 取消 UX  
2. 讲解偏好（语言/深度/可否给答案）  
3. 快捷追问 chips  
4. `LearnerAiContext` + 注入 hint system prompt  
5. AI Hub 伴学/创作分区  
6. 词典「AI 扩展」最小 genre（例句 + 记忆钩）  

完成以上即可形成「更好用的课内助手 + 词典也能问」的可感知版本，且完全不触及课程生成。

---

## 10. 文档与后续

- 实现启动时：可增补 ADR（建议标题：`00xx-ai-learning-companion-scope.md`），写明与生成类 AI 的边界。  
- 更新 `docs/project-guide.md` §7.2–7.3 伴学清单。  
- 设置文案 / 新手指南 AI 节同步改「伴学」叙事。  
- 本文件随分期勾选进度（可在 PR 中维护 checklist）。

### 进度勾选

- [ ] Phase A  
- [ ] Phase B  
- [ ] Phase C  
- [ ] Phase D  
- [ ] Phase E  
- [ ] ADR + project-guide 同步  
```
