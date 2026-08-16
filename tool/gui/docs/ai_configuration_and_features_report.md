# Turna GUI AI 配置架构与功能分析报告

> **文档目的**：对 Turna 课程编辑器 GUI 中的全部 AI 实际配置、接入服务、后台架构与前端功能模块进行全方位深度解析。报告以**功能视角（Feature-Centric Perspective）**切入，系统梳理每个 AI 功能的配置机制、工作原理、底层实现路径以及最终呈现的教学与编辑效果。

---

## 一、 概述与架构愿景

Turna GUI 采用了 **“Open → Save 全流程超级共生体”（Experience AI Co-pilot & Engine）** 架构设计。AI 在编辑器中并非孤立的对话框或单点工具，而是作为默认环境语言，贯穿从打开项目、教材导入、设计生成、实时编辑补全、校验修复到保存导出的全生命周期。

### 关键设计原则：
1. **双轨混合智能（Local-First Rule Engine + LLM Engine）**：优先使用零延迟、零消耗的本地规则/语义探针；在涉及复杂文本生成、跨节解构、错误诊治时无缝调度大语言模型。
2. **零磁盘凭据安全（Memory-Only Credential Safety）**：API Key 仅在内存中单次持有，严禁持久化到磁盘配置文件中；应用退出即销毁，从根本上杜绝凭据泄漏风险。
3. **强受控教学生成（Pedagogically Grounded Generation）**：结合 CEFR 难度梯度、闭集 POS 词性规范与目标语言范围锁定（Vocab Scope），大幅降低通用大模型的幻觉与超纲词问题。

---

## 二、 AI 基础服务与模型配置

AI 配置体系集中在 [settings.py](../src/application/settings.py)、[ai_presets.py](../src/backend/ai_presets.py) 与 [ai_generator.py](../src/backend/ai_generator.py) 中，提供了高度可定制的服务接入与模型路由机制。

### 2.1 厂商预设与开箱即用支持 (Provider Presets)

系统内置了 5 大主流 AI 服务提供商预设（位于 [ai_presets.py](../src/backend/ai_presets.py)）：

| 预设标识 (`ai_provider`) | 显示名称 | 默认 Base URL | 默认模型 (`ai_model`) | 推理链支持 (`supports_reasoning`) |
| :--- | :--- | :--- | :--- | :--- |
| `deepseek` | DeepSeek | `https://api.deepseek.com` | `deepseek-v4-pro` | ✅ True |
| `openai` | OpenAI | `https://api.openai.com/v1` | `gpt-4o` | ❌ False |
| `moonshot` | Moonshot AI | `https://api.moonshot.cn/v1` | `moonshot-v1-8k` | ❌ False |
| `ollama` | Ollama (本地) | `http://localhost:11434/v1` | `qwen2.5` | ❌ False |
| `custom` | 自定义 | 用户自由填写 | 用户自由填写 | 由用户勾选 |

### 2.2 专职模型分离路由 (Dual-Model Routing)

为平衡生成质量与调用成本，GUI 支持**双模型分离路由配置**：
* **结构化 JSON 生成模型 (`ai_model_json`)**：专门用于课程生成、章节解构、JSON Schema 校验修复与语法树转换。若为空，回退到主模型 `ai_model`。
* **对话与解释模型 (`ai_model_chat`)**：专门用于交互式对齐（Wish Mode 讨论）、意图理解与自然语言答疑。可配置为轻量、高速模型（如 `gpt-4o-mini` 或 `deepseek-chat`），大幅降低对话开销。

### 2.3 基础与高级网络参数配置

在 [Settings](../src/application/settings.py) 与 [AiApiConfig](../src/backend/ai_generator.py) 中，包含以下核心参数：

```python
# 核心网络与生成参数
ai_base_url: str = ""           # API 服务的 HTTP Endpoint
ai_api_key: str = ""            # 内存持有 Key（严禁写盘）
ai_model: str = ""              # 主模型标识
ai_timeout: float = 120.0       # 请求超时时间（5s - 600s）
ai_temperature: float = 0.7     # 采样随机度（0.0 - 2.0）
ai_retry_max: int = 1           # 格式/Schema 校验失败时的自动修正重试轮数 (0 - 5)
ai_supports_reasoning: bool     # 是否开启 DeepSeek reasoning_content/thinking 字段解析
ai_strict_schema: str = "auto"  # JSON 结构约束模式：auto | on | off（自动降级试探）
ai_cache_enabled: bool = False  # 基于 Prompt SHA256 的内存响应缓存开关
ai_max_parallel_lessons: int = 1 # 分阶段工坊生成时的最大并行 Worker 线程数 (1 - 8)
ai_pipeline_default_mode: str   # 默认生成模式：fast (单次全量) | refine (大纲+逐课)
```

### 2.4 零磁盘凭据安全机制

* **内存限定 (Memory-Only)**：`ai_api_key` 在 [Settings.load_from_qsettings](../src/application/settings.py#L132) 中被排除在持久化逻辑之外。
* **磁盘自动清理**：应用启动时若检测到历史版本残留的 `ai/api_key` 磁盘键值，会自动执行 `qsettings.remove("ai/api_key")`。
* **脱敏日志**：所有 [Telemetry](../src/infrastructure/telemetry.py) 与操作日志严格过滤 API Key 与 Authorization Header。

### 2.5 实时成本计算与预算控制 (Cost & Budget Control)

在 [ai_presets.py](../src/backend/ai_presets.py) 与 [ai_usage.py](../src/backend/ai_usage.py) 中，系统内置了主流模型的计费单价表（以 1M Tokens 为单位）：
* **DeepSeek-v4-pro**：输入 ¥2.0 / 输出 ¥8.0 (CNY)
* **GPT-4o**：输入 $2.5 / 输出 $10.0 (USD)
* **Moonshot-v1-8k**：输入 ¥1.2 / 输出 ¥1.2 (CNY)
* **Ollama 本地模型**：仅统计 Token 消耗量，显示为免费。
* **每日 API 预算限额 (`experience_daily_ai_budget`)**：可设置每日最大 AI 请求上限。超限时自动挂起 AI 写入动作，但不影响手动编辑与本地校验。

---

## 三、 以功能为视角的 AI 特性与效果详解

以下按照 GUI 的主要编辑与创作功能模块，逐一拆解实际生效的 AI 配置、工作原理及教学与生产效果。

```
+-----------------------------------------------------------------------------------+
|                            Turna GUI AI 功能全景                              |
+-----------------------------------------------------------------------------------+
|  1. 教材工坊 (Textbook Workshop)    --> 智能切块 + JSON Schema 资产提取               |
|  2. 分阶段生成 (Phased Pipeline)    --> 大纲规划 + 多线程并行 Lesson + 自动补全          |
|  3. AI 协同工坊 (Copilot Chat)     --> 双阶段对话对齐 + Prompt 模板 + 附件注入        |
|  4. 校验与一键修复 (AI Fixer)      --> CLI 诊断 + JSON Patch 生成 + 批量自动修正       |
|  5. 共生引擎 (Experience Engine)   --> Context Bus + Ghost 补全 + ⌘K 路由 + 沙箱预演   |
|  6. 多模态扩展 (Multimodal Skills) --> 截屏诊断 + 本地 OCR + 本地语音录入              |
|  7. 教学法管控 (Pedagogy & Scope)  --> 词汇表范围锁定 + 10 类闭集 POS + CEFR 难度梯度    |
+-----------------------------------------------------------------------------------+
```

---

### 1. 教材工坊与知识资产提取 (Textbook Workshop & Knowledge Extraction)

* **核心模块文件**：[textbook_import_dialog.py](../src/dialogs/textbook_import_dialog.py)、[knowledge_extractor.py](../src/backend/knowledge_extractor.py)、[knowledge_prompt.py](../src/backend/knowledge_prompt.py)、[markdown_chopper.py](../src/backend/markdown_chopper.py)。
* **功能描述**：
  允许用户导入原始 PDF/Markdown/TXT 格式的外部教材，AI 自动进行长文档智能切块，从中精炼并抽取出标准的课程语言资产（包含单词 Vocab、语法点 Grammar Points、常用表达 Expressions、文化背景 Cultural Context）。

* **实际配置与技术效果**：
  1. **Markdown 智能分块 (`markdown_chopper.py`)**：按 H1/H2 章节及 Token 阈值切分长文本，防止超出大模型 Prompt 窗口。
  2. **JSON Schema 约束提纯 (`knowledge_schema.py`)**：强制 AI 按照标准的语言资产结构返回。
  3. **合并预览与去重 (`ai_merge_preview_dialog.py`)**：提取结果在写入课程数据库前，会经过去重与知识合并器（`knowledge_merger.py`），用户可在 GUI 中预览差异并选择性合并。

* **效果亮点**：
  * 将传统人工整理教材的数天工作量缩短至分钟级。
  * 提取出的词汇自动带有标准化词性（POS）与例句，语法点附带结构说明。

---

### 2. 分阶段课程生成流水线 (Phased Course Generator & Pipeline)

* **核心模块文件**：[ai_generator_dialog.py](../src/dialogs/ai_generator_dialog.py)、[ai_pipeline.py](../src/backend/ai_pipeline.py)、[ai_phased.py](../src/backend/ai_phased.py)。
* **功能描述**：
  根据教师输入的课程主题或教学大纲，自动生成符合 Turna 规格的多 Unit/Lesson/Stage 完整课程 JSON。

* **实际配置与技术效果**：
  系统支持两种生成管线模式（可由 `ai_pipeline_default_mode` 控制）：
  * **Fast Mode（单次全量生成）**：适合小型 Section（如单课或简单单元），单次 Request 快速返回。
  * **Refine Mode（分阶段三步流水线）**：
    * **第一阶段 (Outline Phase)**：AI 先生成完整的 Section / Unit / Lesson 目录大纲及知识点分配表。
    * **第二阶段 (Parallel Generation Phase)**：根据配置的 `ai_max_parallel_lessons`（1-8 线程），并行并发生成各个 Lesson 的详细练习卡片与内容。
    * **第三阶段 (Quality Inspection & Auto-Fill)**：自动运行质量检查（`content_quality.py`），若配置了 `ai_fill_needs_review=True`，会自动发起二次 Pass 填补生成中留下的 `[待补]` 占位符。

* **效果亮点**：
  * **避免爆栈与超长输出截断**：将长课程拆解为独立 Lesson 并行生成，稳定支持 10 万字以上的重型课程生成。
  * **结构完整性保障**：配合 `ai_retry_max` 自动修复机制，确保返回的 JSON 100% 具备合法 schema。

---

### 3. 交互式 AI 协同工坊与 Prompt 引擎 (Copilot Interactive Chat & Prompt Bar)

* **核心模块文件**：[design_controller.py](../src/dialogs/ai/design_controller.py)、[design_panel.py](../src/dialogs/ai/design_panel.py)、[chat_view.py](../src/dialogs/ai/chat_view.py)、[review_panel.py](../src/dialogs/ai/review_panel.py)。
* **功能描述**：
  在工坊界面提供多轮交互式对话与生成对比面板，教师可以如同与资深教研专家对话一般，打磨课程结构。

* **实际配置与技术效果**：
  1. **双阶段对齐流程 (Two-Phase Alignment)**：
     * **Phase 1 Alignment**：AI 仅使用纯自然语言与教师探讨教学目标、难度、受众，**绝不直接输出 JSON 乱码**（由 `model_chat` 响应）。
     * **Phase 2 Generation**：确认设计方案后，一键触发生成，AI 切换为 JSON 模式（由 `model_json` 响应）输出最终课程代码。
  2. **内置 Prompt 模板库 (`prompt_template_bar.py`)**：预置了“添加听力练习”、“难度降级”、“增加文化背景”、“补充语法例句”等常用教研指令快捷键。
  3. **差异比对预览 (`review_panel.py`)**：AI 生成的新旧课程结构会以 Visual Diff / JSON Diff 方式高亮呈现，支持教师逐项采纳或一键拒绝。

* **效果亮点**：
  * 彻底消除了传统 AI 工具“一键盲盒生成”的不确定性，让教师始终掌控课程设计主导权。

---

### 4. 智能校验诊断与一键 AI 修复 (Validation Error Diagnostic & AI Fixer)

* **核心模块文件**：[ai_fix_dialog.py](../src/dialogs/ai_fix_dialog.py)、[ai_error_analyzer.py](../src/dialogs/ai_error_analyzer.py)、[ai_fixer.py](../src/backend/ai_fixer.py)、[ai_fix_batch.py](../src/backend/ai_fix_batch.py)。
* **功能描述**：
  当课程校验引擎 `course_cli` 检测到错误（如单元引用无效、缺少语音 TTS 标识、Tag 不合规、JSON 语法错乱）时，AI 能自动分析错误原因并生成修复方案。

* **实际配置与技术效果**：
  1. **上下文诊断精准定位**：`ai_error_analyzer` 提取具体的错误 Path 与 Problem Message，构建包含故障片段的精简 Prompt。
  2. **JSON Patch 原子修复**：AI 并不重新生成整个文件，而是返回轻量级的 [Patch 结构](../src/backend/experience/patch.py)，仅修改出错的局部节点。
  3. **批量自动纠错 (`ai_fix_batch.py`)**：支持一键扫描全课错误并自动循环调用 AI 修正。

* **效果亮点**：
  * 解决非技术背景教师“看不懂 CLI 报错信息”的痛点，秒级修复格式与引用失效错误。

---

### 5. Experience AI 全流程共生引擎 (Experience AI Co-pilot Engine)

* **核心模块文件**：`src/backend/experience/` 目录下全套组件。
* **功能描述**：
  使 AI 具备对编辑上下文的实时感知能力，提供内联补全、命令调色板、主动建议与沙箱预演功能。

* **实际配置与功能效果表**：

| 组件名称 | 核心文件 | 对应的配置开关 | 实际功能与运行效果 |
| :--- | :--- | :--- | :--- |
| **Context Bus** | [context_bus.py](../src/backend/experience/context_bus.py) | 无（核心总线） | 以 `<50ms` 的超低延迟，实时抓取用户当前光标所在的 Lesson、Section 结构、选中的词汇以及最近 10 次编辑历史，为所有 AI 功能提供上下文支持。 |
| **Ghost LLM** | [precognition.py](../src/backend/experience/precognition.py) | `ghost_llm_enabled` | 当本地规则补全未命中时，在文本框/表格单元格中静默触发 AI 补全（如自动填充单词翻译、选项译文、例句翻译），呈灰色虚影提示。 |
| **⌘K 意图路由** | [intent_router.py](../src/backend/experience/intent_router.py) | `experience_llm_intent` | 快捷键 ⌘K 唤起指令板。优先进行本地规则速配（如 `/listening` 快速添加听力题）；当规则落空时，调度 LLM 进行自然语言意图分类。 |
| **Soft Autopilot** | [soft_autopilot.py](../src/backend/experience/soft_autopilot.py) | `experience_soft_autopilot` | **软自动驾驶**：在文件保存前，自动执行无损的资源卫生清理（如整理未引用的孤立词汇、规范格式缩进），无需人类人工干预。 |
| **Goal Agent & 沙箱预演** | [planner.py](../src/backend/experience/planner.py)、[sandbox.py](../src/backend/experience/sandbox.py) | `experience_goal_enabled`<br>`experience_goal_llm` | 支持多步骤复杂目标（如“将 Section 3 重构为听力强化单元”）。AI 在**隔离内存沙箱**中预演修改步骤并生成预览，确同后再写入主树，杜绝误操作。 |
| **高危 Skill 防护** | [policy.py](../src/backend/experience/policy.py) | `experience_allow_dangerous_skills` | **安全总开关**：管控删 ID、跨节重写、硬导入与发布类动作。在 Observer 观察者模式下强制拦截所有危险指令。 |
| **Ambient 静音控制** | [proactive.py](../src/backend/experience/proactive.py) | `experience_mute_json`<br>`experience_mode` | 支持智能静音。教师可选择 `copilot`（主动助手）或 `observer`（被动观察者），并可设定静音时长与静音级别，防止主动弹窗打扰创作。 |

---

### 6. 多模态能力扩展 (Multimodal Skills)

* **核心模块文件**：[screenshot_skill.py](../src/backend/experience/screenshot_skill.py)、[ocr_skill.py](../src/backend/experience/ocr_skill.py)、[voice_skill.py](../src/backend/experience/voice_skill.py)。
* **功能描述与效果**：
  1. **主窗截图视效诊断 (`screenshot_explain`)**：
     * **配置开关**：`experience_screenshot_explain`（默认关闭，保护隐私与开销）。
     * **效果**：捕获 Qt 当前窗口画面，编码为 `image_url` 发送给视觉大模型（如 GPT-4o），针对当前 UI 显示异常或渲染布局提供直观的解说与排查建议。
  2. **本地零网络 OCR 附件抽取 (`ocr_skill`)**：
     * **配置开关**：`experience_ocr_enabled`（采用本地 `pytesseract` + `tesseract` 引擎，零 LLM 费用）。
     * **效果**：拖入扫描版图片/PDF 教材，本地即时提取文本并回流至 Context Bus，作为生成上下文。
  3. **本地语音指令调色板 (`voice_skill`)**：
     * **配置开关**：`experience_voice_palette`（基于本地 `SpeechRecognition` + `Sphinx` 离线识别）。
     * **效果**：按下语音按键直接说出教研指令（如“给当前课增加三道选择题”），自动转录为 ⌘K 命令。

---

### 7. 教学法约束与语言学范围管控 (Pedagogy & Scope Control)

* **核心模块文件**：[ai_scope.py](../src/backend/ai_scope.py)、[ai_pedagogy.py](../src/backend/ai_pedagogy.py)、[ai_genre.py](../src/backend/ai_genre.py)。
* **功能描述**：
  为通用大模型戴上“语言教学枷锁”，确保生成的课文与练习严格符合教学法要求。

* **实际配置与技术效果**：
  1. **目标语言词汇表锁定 (Vocab Scoping)**：在生成例句或阅读理解时，`ai_scope.py` 会将本课及历史已学词汇作为受控词表（Controlled Vocabulary）注入 Prompt，禁止 AI 使用超出学生当前词汇量的高深词汇。
  2. **10 类闭集 POS 词性规范 (POS Schema Alignment)**：严格限制词性标注落在固定的 10 类 POS 闭集中（名词、动词、形容词等），确保与 Flutter 移动学习端的 SQLite 数据库结构完全对齐。
  3. **题型 Genre 规范与模板化 (`ai_genre.py`)**：内置标准题型模板（如多项选择、填空、听力匹配、口语模仿），强制 AI 输出符合指定 Genre 的互动卡片。

* **效果亮点**：
  * 彻底解决了传统通用 AI 生成外语课文时“初级课程出现专八词汇”的超纲问题，保障了循序渐进的教学曲线。

---

### 8. AI 性能评测与安全护栏 (Benchmarking & Security Guards)

* **核心模块文件**：[ai_bench.py](../src/backend/ai_bench.py)、[telemetry.py](../src/infrastructure/telemetry.py)、[conflict_guard.py](../src/backend/experience/conflict_guard.py)。
* **功能描述**：
  提供离线 quality 探针与实时遥测审计，确保 AI 系统的稳定性、性能与安全性。

* **实际配置与技术效果**：
  1. **离线质量探针 (`ai_bench.py`)**：无须调用真实 API 即可计算生成 JSON 的占位符密度 (`[待补]` 数量)、资源覆盖率与语法规范得分。
  2. **并发冲突守护 (`conflict_guard.py`)**：当用户在界面上手工修改节点时，若 AI 异步生成任务恰好返回，自动进行节点级 Locking & Conflict detection，防止 AI 覆写人类最新编辑。

---

## 四、 总结与特点归纳

通过对 Turna GUI AI 配置与架构的深度梳理，该系统展现出以下四大核心特点：

```
+-----------------------------------------------------------------------------------+
|                         Turna GUI AI 体系四大核心特点                         |
+-----------------------------------------------------------------------------------+
|  1. 深度浸入与全流程感知  --> Context Bus <50ms 实时光标追踪，Open 到 Save 始终在场 |
|  2. 极致安全与隐私保护    --> Key 仅内存单次持有，高危 Skill 开关与日预算防暴刷   |
|  3. 教学法强受控解幻觉    --> 词汇表范围锁、闭集 POS、分阶段流水线与自动校验修复  |
|  4. 灵活的高级模型路由    --> 双模型 separation、自适应 JSON Schema 降级与成本透明 |
+-----------------------------------------------------------------------------------+
```

1. **深度浸入与全流程感知 (Seamless Co-pilot)**：
   不同于将 AI 作为独立 Sidebar 或 Popup 的传统做法，GUI 通过 **Context Bus** 将 AI 打造为编辑器的“中枢神经”，实现了光标感知、Ghost 虚影补全、保存前 Soft 自动驾驶与一键 Patch 修复。
2. **极致安全与隐私保护 (Defense-in-Depth)**：
   采用 API Key **内存单次持有**策略（磁盘零留存与自清理）、高危动作（删节点、发布）显式开关防护、沙箱预演机制以及每日 API 请求预算限制，全方位保障用户凭据安全与资产安全。
3. **教学法强受控解幻觉 (Pedagogically Grounded)**：
   引入词汇表范围锁定（Vocab Scope）、10 类闭集 POS 规范、CEFR 梯度控制与分阶段三步生成流水线，有效消解了大语言模型的乱码与超纲问题，使其真正具备专业语言教学的可用性。
4. **灵活的高级模型路由与成本透明 (Advanced Routing & Cost Awareness)**：
   支持按功能拆分 Chat 对话模型与 JSON 生成模型，内置 DeepSeek/OpenAI/Moonshot/Ollama 预设，配合实时的 Token 与 CNY/USD 成本测算，兼顾了生成质量与经济效益。
