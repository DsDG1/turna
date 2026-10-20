# Turna Course Editor GUI (语言课程图形编辑器)

`Turna GUI` 是基于 **PySide6** 开发的本地化二语习得（SLA）课程编辑器，是 CLI 工具 [`tool/course_cli.py`](../course_cli.py) 的图形前端：可视化设计、教材智能化提取、资源集中管理、交互审校、一键发布。

> 💡 **新手**：零代码教师指南见 [../../docs/authoring/teacher-guide.md](../../docs/authoring/teacher-guide.md)。
> 🛠️ **开发者**：本文涵盖安装运行、主界面、课程工坊、架构设计、测试与打包。

---

## 核心功能特性

- 🌳 **三级课程树**：`Section` → `Unit` → `Lesson`；拖拽排序、批量复制/移动、删除、预设套用。
- 🎨 **可视化蓝图与表单引擎**：按课时模板（`intro` / `practice` / `listening` / `reading` / `review` / `mastery`）生成动态属性表单与编排蓝图。
- 🤖 **课程工坊（四阶段画布）**：非模态 AI 协同窗口；项目库 + 素材/知识/草稿/导入，各阶段占满整幅（草稿阶段是对话主场）；教材提取、Grounded 生成、局部重生成、幂等导入。
- 📦 **语言资源独立建模**：词汇 (`vocab`)、固定表达 (`expressions`)、语法点 (`grammar_points`) 表格管理；CSV 导入导出、引用依赖检测。
- 🛡️ **单一校验源与保存回滚**：不另定义校验规则，完全对接 `course_cli validate & lint`；保存校验失败自动恢复内存与磁盘文件。
- 🎓 **教师预览与试做模式**：教师视图审查结构，对课时实时交互测试。
- 🚀 **发布工作流**：版本 Bump、音频 Manifest 挂载检查、Diff 比对、发布报告一键生成。

---

## 环境要求与安装运行

- **Python**：3.11 或更高。**系统**：Windows / macOS / Linux。

```bash
pip install PySide6 PyPDF2 python-docx
```

> ⚠️ **沙箱提示**：TRAE/VS Code 受限沙箱遇 `WinError 5` 装不上 PySide6 时，改用本机系统终端跑 GUI 与打包；后端核心无 PySide6 依赖，单元测试可在沙箱执行。

项目根目录执行 `python -m tool.gui.src.main`，启动后点 **「课程仓库 → 打开课程目录」** 选本地课程目录（如 `assets/courses/turkish/`）。

> 打开 / 新建 / 最近仓库切换时，若当前课程有未保存更改，先弹 **保存并打开 / 放弃更改 / 取消** 三选一；「保存并打开」走完整保存管线，保存失败则中止切换。

---

## 主界面与功能使用指南

单壳多视图布局（2026-09 焕新）：左侧 48px Activity Bar 导航轨，中央 QStackedWidget（欢迎/编辑/总览/资源），右侧 Copilot Dock，底部状态栏上方悬浮 PreviewHost strip（AI 待应用动作条）。

Activity Bar 角标：总览 = 校验错误数（红）、工坊 = 未完成导入的项目数、Copilot = 未读建议数（Dock 可见即已读）。

### 1. 导航与视图 (Activity Bar 与快捷键)

全局工具栏已取消，动作收编进 Activity Bar 与各视图头部。

| 入口 | 功能 | 快捷键 / 备注 |
|---|---|---|
| **应用菜单（≡）** | 打开/新建课程目录、最近仓库、发布、生成听力音频、命令面板、设置 | 顶部菜单按钮 |
| **编辑视图（📁）** | 侧栏课程树 + 详情面板（编辑/预览/JSON 三 tab） | `Ctrl+1` |
| **工坊（✨）** | 一站式 AI 协同创作（教材提取、AI 设计、审校到幂等导入） | `Ctrl+2`，非模态，可并行操作 |
| **总览（🗺）** | 全局鸟瞰：Sections/Units/Lessons/空课时/校验错警 + 词汇·表达·语法覆盖率 + 课型分布；每 Section 题型构成行；按名称/ID 搜索；课型徽标互斥过滤；空课时灰边标记；导出 Markdown；点校验数跳转校验面板 | `Ctrl+3`；角标红显校验错误数 |
| **资源（📚）** | 词汇/表达/语法点编辑表格；页内第二 tab 为 Git 资源库 | `Ctrl+4`；支持 CSV 一键导出/导入 |
| **Copilot（🤖）** | 右侧 AI 建议面板（ExperienceDock），待应用动作落在状态栏上方确认条 | `Ctrl+J` toggle |
| **教师模式（🎓）** | 教师审查视角，课时结构化呈现与实时交互试做 | Activity Bar 底部 |
| **设置（⚙）** | 主题、密度、字体缩放、AI 接口服务（Base URL / Model / Key）、撤销步数、用量监控 | `Ctrl+,` |
| **命令面板** | ⌘K 式派发：转到视图 / 执行动作 / 定位课程节点 | `Ctrl+K` |
| **侧栏开关** | 编辑视图侧栏（搜索 + 课程树）显隐 | `Ctrl+B` |
| **保存** | 写盘并触发 `course_cli validate` / `lint`，失败自动回滚；Ctrl+S / 菜单 / 命令面板 / 关闭四入口共用同一保存管线（含 Soft Autopilot 规则规范化与保存后黄标提示），大课程保存期间窗口可拖动 | `Ctrl+S` |
| **发布** | 版本 Bump、音效 Manifest 挂载检查、Diff 生成与报告导出 | 应用菜单内 |

布局持久化：上次视图、窗口状态、侧栏/Copilot 显隐经 QSettings 重启还原。

### 2. 课程树状导航 (Course Tree)

侧栏（编辑视图独有，`Ctrl+B` 收起）顶部搜索框按名称/ID/课型过滤（自动保留匹配节点祖先链）；树节点带 Lucide 图标与模板色徽标；拖拽时有 accent 色插入指示线。

- **右键菜单**：新增 Section / Unit / Lesson（弹模板选择）；**AI 编辑此节点**（快捷 AI 对话框）；**套用预设 (Presets)**（互动模式与梯度组合）；**批量操作**（`Ctrl` / `Shift` 多选后复制/移动/删除）。
- **快捷键**：`Ctrl+D` 克隆选中**课时 (Lesson)**（选中 Section / Unit 时提示暂不支持）；`Delete` 删除选中（带二次确认）；`F2` 快速重命名；`Ctrl+↑` / `Ctrl+↓` 排序。

| 快捷键 | 功能 | 作用域 |
|---|---|---|
| `Ctrl+1` / `2` / `3` / `4` | 切换 编辑 / 工坊 / 总览 / 资源 视图 | 全局 |
| `Ctrl+B` | 侧栏显隐 | 编辑视图 |
| `Ctrl+J` | Copilot 显隐 | 全局 |
| `Ctrl+K` | 命令面板 | 全局 |
| `Ctrl+S` | 保存（完整保存管线，含校验与回滚） | 全局 |
| `Ctrl+,` | 打开设置 | 全局 |
| `Ctrl+Z` / `Ctrl+Shift+Z` | 撤销 / 重做 | 全局 |
| `Ctrl+F` | 聚焦侧栏搜索框 | 编辑视图 |
| `[` / `]` | 在 Copilot 建议间上下移动 | 非输入框聚焦时 |
| `Esc` | 关闭对话框 / 取消 | 局部 |

> `Ctrl+Z` / `Ctrl+Shift+Z` 由工具栏 Undo / Redo 动作提供（`QAction` 标准快捷键），在树、编辑器、AI 面板都生效。

### 3. 课时编辑器与可视化蓝图 (Lesson Editor & Blueprint)

1. **属性折叠条**：ID / 名称 / 描述 / 同层前置依赖 (`prerequisiteLessonIds`) / 关联语法点收进可折叠「属性」横条；课时默认收起让版面给内容编辑，Section/Unit 默认展开；手动选择按节点类别记忆，F2 重命名自动展开并聚焦名称框。
2. **模板类型切换**：`intro` / `practice` / `listening` / `reading` / `review` / `mastery` 间切换，系统自动纠正数据规范。
3. **可视化蓝图 (Blueprint Editor)**：针对 `listening`、`reading`、`mastery` 等复杂功能课时提供流程蓝图，可拖拽或点击调整听力阶段 (`ListeningPhase`) 或阅读文章 (`ReadingPassage`) 段落顺序。
4. **14 种互动题型列表与表单**（清单真源 `backend/lesson_content.py` 的 `INTERACTION_TYPES`）：动态增删题型卡片并拖拽排序；每种题型按 Schema 展现专用输入框（词汇下拉关联、多选选项定义、填空文本匹配、音频路径挂载等）。

蓝图与「高级编辑」经一对分段按钮切换（选中态高亮）；功能课时默认蓝图、其余默认高级编辑。

### 4. 语言资源库管理 (Resource Editor)

点工具栏 **「资源库」** 进入全局资源编辑页：

- **三大资源表**：`vocab.json` (词汇)、`expressions.json` (常用表达)、`grammar_points.json` (语法点)。
- **表格列交互**：在线新增、删除行、原地双击编辑。
- **引用检索与安全删除**：删除词汇或语法点时自动扫描所有 Lesson 引用，存在引用则警示。
- **CSV 交换**：批量导出 CSV 供外部 Excel/Translators 编辑，编辑后一键导入覆盖或合并；自动识别 **UTF-8（含 BOM）/ GBK**（依次尝试，全失败报「无法识别编码」且不写入）。
- **跨表搜索**：顶部搜索栏同时过滤三个标签页（大小写不敏感子串匹配）。
- **批量删除**：多选行（Ctrl/Shift+点击）后一次删除。**查重**：检测 vocab 与 expressions 跨表重复词条。
- **资源包**：导出/导入单个 JSON 资源包（含全部三类资源），支持合并去重或完全替换。

### 4.1 Git 资源库 (Git Library)

点工具栏 **「资源库 ▸ Git 资源库」** 打开三标签页对话框。

**远程协作 / 同步**：已保存远程仓库列表（名称/URL/本地目录/语言，双击连接）；连接/克隆（远程 URL + 本地目录 + 语言代码，自动从设置填默认值）；分支管理（下拉选择 + 新建/切换/删除）；拉取冲突解决（`pull --ff-only` 失败时三选一：Rebase / Stash+Pull+Pop / 放弃）；推送前预览（工作树与 HEAD 的 diff stat）；历史右键菜单（reset --hard/soft 或 revert）；复制到 assets（`<repo>/assets/courses/<lang>/`，目标根目录可在设置中配置）；同步资源池（双向合并本地与 Git 侧 vocab/expressions/grammar_points）；仓库文件树（双击在编辑器中打开）。

**局域网协作共享**：HTTP Smart 服务器（Git Smart HTTP 协议，支持 clone/push over HTTP）；安全配置（绑定 0.0.0.0 / 127.0.0.1、访问令牌鉴权、只读模式禁 push、IP 白名单）；端口自动重试（占用则 +1，最多 10 次）；在线成员（实时显示协作者 IP，60s 超时剔除）；诊断日志（Git RPC 成功/失败信息）。

**团队留言板**：线程化回复（parent_id，缩进显示线程）；编辑/删除（按系统用户名验证权限）；分页（每页 20 条顶层留言）；搜索（按内容或用户名过滤）；自动同步（发送前 `pull --rebase` 再 `commit_and_push`，降低非快进拒绝）。

### 5. 课程总览与教师模式 (Overview & Teacher Mode)

- **全局总览图**：多行统计（Sections/Units/Lessons/空课时/校验错警 + 词汇·表达·语法覆盖率 N/M, P% + 课型分布）；每 Section 卡片头部展示题型构成（如「选择题 12 · 填空题 8 · 听音选词 6」）；空课时芯片灰边 + `（空）` 标记；顶部搜索框按名称/ID 过滤，课型徽标可点切互斥过滤；一键导出 Markdown（贴入 ADR/内容清单）；校验数可点跳转已有校验面板。统计计算抽到纯函数模块 `backend/overview_stats.py`（无 Qt，可单测）。
- **教师试做模式**：点工具栏 **「教师模式」** 后模拟学员在移动端的操作流程，在桌面端测试各种互动题型（单选点击、听音选词、句子重排等），验证答题逻辑与渲染效果。

### 6. 设置与偏好管理 (Settings)

`Ctrl+,` 唤起设置对话框（**左侧分类导航 + 右侧内容页**两栏）：外观 / AI 配置 / AI 用量 / 提取 Prompt / 编辑器 / 体验 OS / Git 库 / 操作日志 八个分类。表单页超出高度自动滚动（150% 字体缩放或窄屏不裁切）；上次分类经 `settings/last_page` 记忆。偏好存 `QSettings`。

- **外观风格**：深色 (Dark) / 浅色 (Light) 无缝切换；UI 字体缩放 80%–150%。
- **AI 接口配置**
  - **供应商预设**：一键填充 DeepSeek、OpenAI、Moonshot、Ollama 的标准 Base URL 与默认模型。
  - **安全保护**：API Key **仅存于当前会话内存**，关闭应用即销毁，绝不写盘；Base URL 与 Model 持久化。
  - **参数微调**：思考过程 (Reasoning)、请求超时 (5–600 秒)、生成温度 (0.0–2.0)、自动重试轮数 (0–5)。
  - **连接测试**：「测试连接」发送最小 1-token 请求验证配置。
  - **生成稳定性（aiEnhance 第一枪）**：生成走统一「生成 → 校验 → 回灌错误重试」闭环；prompt 强制资源先于 units、注入 CEFR/干扰项/土耳其语教学法约束；可选对 `[待补]`/needs-review 做第二趟补全（API 参数 `fill_needs_review`，默认关）。度量探针见 `backend/ai_bench.py` 与 `tests/ai_goldens/`。
  - **内容质量与精修（第二枪）**：审阅区展示规则质量分（复现/题型/干扰项/难度/听力/资源卫生），可「按质量分修复」；局部重生成支持自定义指令与预设条；生成模式可选 **快速（整节）** 或 **精修（大纲→分课）**（`backend/ai_phased.py`）。质量分**不阻断**保存/导入。
  - **高级 AI 选项（第三枪 批次①）**（AI 配置 tab 底部「高级」折叠区）：**双模型** `model_chat`（对齐对话 / 课程解释）与 `model_json`（课程 / 课时 / 题目 JSON 生成与修复），留空用主模型；**JSON Schema 严格度** `auto`（先试 `json_schema`，HTTP 400 自动回退 `json_object`）/ `on` / `off`；**响应缓存** 进程内 LRU(128)，键为 `(model, messages, response_format)` 的 SHA-256，不存 API Key，命中仍跑 validator 防脏；**其他** `fill_needs_review` 开关、`max_parallel_lessons`(1..8)、`pipeline_default_mode`(fast|refine)，命中/未命中经 `ai.cache.stats` telemetry 可见。
  - **精修流水线（第三枪 批次②）**：选 **精修（流水线）** 走 `backend/ai_pipeline.py` 状态机：Plan → 大纲 → 分课生成 → 校验 → 内容质量分 → 修复（先规则修复，LLM 只处理剩余 error，删除既有 id 则回滚）→ 通俗解释 → ReadyImport；右栏实时显示各步 checklist（pending/running/done/skipped/failed）；「跳过修复 / 跳过解释」可裁剪步骤；支持取消，取消后中间态随项目自动保存，重开项目可从大纲续跑。流水线**只到草稿为止**，导入仍走「校验 → 目标选择 → diff/merge 预览 → 人工确认」，绝不自动导入。
- **用量与成本分析**：今日与累计 Token 消耗、API 请求次数、按模型价格预估的消费金额。
- **编辑器行为**：全局撤销上限 (10–500 步)、窗口关闭时未保存更改的处理策略。
- **Git 库配置**：克隆根目录、Git 二进制路径、默认语言代码、操作超时、Assets 仓库根目录、LAN 默认端口/绑定地址/令牌、SSH 私钥路径、已保存远程仓库表（CRUD）、HTTPS 凭据管理（OS keyring 优先，QSettings 回退）。

> 🖱️ **全应用禁用「滚轮悬停调参」**：滚轮永不改数值框/下拉框值，悬停其上只滚动所在页面（`WheelGuard`，`src/infrastructure/wheel_guard.py`）；调值用键盘、上下箭头或下拉选择。
>
> 📐 **小屏适配**：对话框/子窗口显示时自动钳制进屏幕可用区域（超出才居中收回，已入屏不动，`src/infrastructure/screen_fit.py`）；多按钮行与过滤条用可换行 `FlowLayout`（`src/widgets/ui/flow_layout.py`），窄窗口下按钮换行而非裁字。

---

## 创作者五条主路径（AI 感知增强）

| 路径 | 怎么做 | 你应感到 |
|------|--------|----------|
| **A 空白→一节课** | 工坊空白项目 → 主题/等级 → 快速或精修生成 → 结构大纲看**生成摘要 + 质量维** → 导入 | 不用翻 JSON 也能决定导不导入 |
| **B 教材→课** | 从教材新建 → 抽章（状态灯可见滑窗/降级）→ 勾选入池 → Grounded 生成 → 导入 | 抽取失败有自动降级；可「按质量重抽」 |
| **C 改一处** | 教师模式题目「AI」/ 树右键 AI 编辑 / Review 局部重生成 | 预设指令统一；改题可确认 + Ctrl+Z |
| **D 校验清零** | 校验面板 **多选** 问题 →「AI 自动修正」按节点分批 merge | 不必逐条点修 |
| **E 导入后改进** | 总览看 section **质量分** → 回工坊/教师定向修 | 低分课有着色提示 |

工坊底栏显示 `json/chat 模型 · 缓存 · tokens`；精修模式有步骤 checklist；头栏 **素材·知识·草稿·导入** 可点击跳转。

## 课程工坊 (AI 创作中心) 全流程指南

核心 AI 协同创作模块：**非模态窗口**，可与主界面并排。信息架构为 **项目库 ↔ 四阶段画布**（不再使用可点击的六阶段侧栏）。头栏四个阶段灯既显示进度（`○/✓`），**也是真导航**（点击切阶段，当前阶段主色加粗）。各阶段占满整幅：素材与知识阶段顶多两列（大纲侧栏那种 55/45 分栏），草稿阶段是参数带 + 对话整幅，导入阶段是结构大纲 + 章节导入两列。窗口默认 980×640。

### 0. 双轨道项目类型

| 项目模式 | 建立方式 | 适用场景 |
|---|---|---|
| **教材项目** | 项目库「从教材新建…」，选 PDF/Word/TXT/图片 与语言对 | 自上而下提取知识点，Grounded 编排（AI 优先从池中选词） |
| **空白 AI 项目** | 项目库「空白 AI 项目」，填名称与语言对 | 无教材自由生成；素材/知识阶段标「(可选)」，打开即落在草稿阶段 |

> 💾 **自动保存与续作**：勾选、知识点、聊天、草稿、**当前阶段**均会保存（`workshop/ui/{project_id}/stage`；旧的 tab/splitter 键已废弃不迁移）。关窗可中断任务；空闲时 **Esc** 关闭窗口。重开恢复上次项目（`workshop/last_project_id`）并回到上次阶段。项目文件：`tool/gui/var/textbooks/{project_id}/project.json`。

### 1. 信息架构：项目库 + 四阶段画布

| 页 | 内容 |
|---|---|
| **项目库** | 新建/打开教材项目或空白 AI 项目；点项目名随时返回项目库 |
| **四阶段画布** | 素材 → 知识 → 草稿 → 导入，每阶段占满整幅；阶段灯可点击直达 |

阶段跳转：首次抽出知识点自动切「知识」；草稿生成完自动切「导入」；提取进行中离开素材/知识先弹确认（同意则中断提取）。对话区 **「查看大纲 →」** 直接跳「导入」。顶栏可关闭引导 banner（「知道了」后不再提示）按空白/教材/是否已有草稿给出下一步建议。

### 2. 素材阶段：教材与章节

**教材与章节**：拖入或选择文件，预览与切章；选教材类型预设与抽取并发数。（拖放事件由画布转发给导入对话框，摘页后拖放依然有效。）

### 3. 知识阶段：知识点审校 + 气泡池

1. **知识点审校（约 70% 宽）**：逐章 LLM 抽取词汇/表达/语法点；红黄质量标记、编辑、点选删除（与「AI 修复选中」同一「选中」语义，勾选≠选中；多选删除有确认）、AI 修复；失败章可重试 / 仅抽词汇 / 跳过。
   - **超长章滑窗抽取**：超过预设字数的章按段落边界切成带重叠的滑窗逐窗抽取，再按键（词+翻译 / 语法标题）去重合并，不再简单截断丢尾部；id 仍按 `ch-{slug}-` 确定性生成。预设 `window_chars`（0 可关闭）与 `overlap_chars` 控制窗长与重叠。
   - **失败自动级联**：`standard` 抽取失败自动降级为「仅词汇（vocab_only）」重试一次（日志有「自动降级」）；再失败才标记失败，建议跳过或人工重试。QSettings 键 `textbook/auto_cascade`（默认开）可关闭。
   - **按质量重抽**：审校页左侧对有质量问题的章提供「按质量重抽」，把具体问题（空翻译、覆盖率偏低、语言混入等）回灌给 AI 输出完整修正版并替换本章结果、重算质量分。
2. **气泡池（右侧约 30% 宽）**：展示已勾选知识点（上限约 200，可点「将选中词加入轨道」）。

**抽取语言对与 OCR（aiEnhance 批次③）**

- **内置语言对抽取模板**：Turkish ↔ Chinese 内置专门抽取规则块（元音和谐/敬语形式、term 禁止混入中文字符、翻译用简体中文），不改 JSON schema。其他语言对可在「设置 → 提取 Prompt」tab 持久化覆盖；优先级：内存 register > 持久化覆盖 > 内置语言对包 > 内置默认（机制见 `backend/knowledge_prompt.py` 的 `KnowledgePromptLibrary` 与 `backend/ai_prompt_library.py` 的 `save_extraction_override`）。
- **OCR（扫描件 PDF / 图片文字识别）**：**可选外部依赖**，默认关闭。开启：设置 ▸ 体验 OS ▸「OCR 图片附件转文本」，需系统安装 [Tesseract OCR](https://github.com/tesseract-ocr/tesseract) 及语言包（Python 侧 `pip install pytesseract`，PDF 走 PyMuPDF）。开启后工坊附件栏的图片/扫描件可本地识别为文本附件；结果只进附件栏，不写课程树、不走 API。也可自行用 `ocrmypdf input.pdf output.pdf` 预处理后再导入。

### 4. 草稿阶段：参数带 + 对话

1. **参数带（一行）**：主题、CEFR 等级、单元数、课时/单元、模板、生成模式、AI 悄悄话。
2. **聚焦 chips（自动换行）**：显示「将使用资源池：N 词 · M 表达 · K 语法」；拖入气泡后变为「聚焦：…」。行高不再被钳制，chips 随宽度换行铺开。
3. **生成**：点圆形「AI 核心」或 **Ctrl+Enter**。有资源池时 Grounded 选词；池外新词带 `new` tag。大草稿流式生成仅更新摘要，完成后一次写入 JSON。
4. **气泡池＋**（跨阶段拖不动时的替代路径）：弹层列出已勾选知识点，**非模态**，可拖气泡进轨道，也可一键全量加入。
5. **对话（整幅）**：许愿聊天、附件、Prompt 模板库、`[genre]`；模板与精修选项、JSON、解释框三个折叠组默认收起。输入框两行起步、聚焦再长一行。**展开**开大窗口继续这段对话（渲染/流式/发送与面板同步）；**查看大纲 →** 跳「导入」阶段。

### 5. 导入阶段：结构大纲 · 章节导入

| 区域 | 用途 |
|---|---|
| **结构大纲**（约 55% 宽，生成后自动切到） | 单元/课时树、人话校验 chips、池内覆盖率；**试做** / **diff** / **AI 修复**（应用前看 diff）/ **导入**；右键课时或单元可 **局部重生成**；可 **恢复上一版草稿** |
| **章节导入**（约 45% 宽） | 导入策略、冲突预览（与教材批量导入同源） |

### 6. 导入后闭环

「导入到课程」可选：新建 section / 并入已有 section（追加 unit）/ 并入已有 unit（追加 lesson）。策略含合并、跳过、覆盖、追加新 id 等。幂等：重复导入不制造废节点。

导入成功后主窗口可询问是否 **切换教师模式并定位**该章节（教师模式只换壳、不再把选择跳到首课）。工坊底栏 **定位到课程树** 亦可跳转；已导入章节后点「导入」阶段灯即为定位。导入后仍须在主窗口 **保存**。

### 7. 高级特性与快捷键

- **`[genre]` 多模板**、**Prompt 模板库 / 历史**、**多模态附件**、**AI 分析失败原因**（见设置与设计 tab）。
- **Esc**：有任务时确认后取消；空闲时关闭工坊窗口。**Ctrl+Enter**：从参数带生成。
- 性能：气泡池增量刷新 + debounce；design autosave 节流；校验仍只走 `CourseAdapter` / `course_cli`。

---

## 技术架构与四项设计约束

### 模块目录映射

<!-- module-tree:start -->

```
tool/gui/
├── src/
│   ├── app.py                  # MainWindow（宿主属性 + 委托方法）
│   ├── main.py                 # 程序主入口（--gallery 打开组件画廊）
│   ├── theme.py                # 主题应用（调色板 + 密度 + UI 缩放）
│   ├── theme_tokens.py         # 设计 token 单一真源（色/间距/圆角/字阶/层级/密度，Qt-free）
│   ├── application/            # 59 个 .py — 应用层：控制器 / 门面 / 命令 / 保存与校验管线
│   │   ├── commands/               # 6 个 .py — Undoable edit commands for the course editor (B2).
│   │   └── experience_handlers/    # 12 个 .py — Experience skill handlers (M7).
│   ├── backend/                # 115 个 .py — 后端：领域逻辑 + 数据 IO（Qt-free，禁 import UI）
│   │   ├── ai/                     # 10 个 .py — AI backend package (OpenAI-compatible course generation).
│   │   └── experience/             # 54 个 .py — Experience OS backend (Wave 0+): context bus, later intent/planne...
│   ├── dialogs/                # 59 个 .py — 对话框与独立子窗口
│   │   ├── ai/                     # 20 个 .py — AI course-generation dialog package.
│   │   ├── git_library/            # 8 个 .py — Git library dialog package — domain split of GitLibraryDialog.
│   │   ├── settings/               # 9 个 .py — Per-tab builder modules for :class:`SettingsDialog` (extracted).
│   │   └── textbook_import/        # 6 个 .py
│   ├── i18n/                   # 2 个 .py — 界面文案表（中文为主）
│   ├── icons/                  # 1 个 .py — vendored Lucide SVG + DPR 渲染/着色/缓存
│   │   └── svg/                    # 0 个 .py
│   ├── infrastructure/         # 7 个 .py — 横切设施：操作日志 / 遥测 / 滚轮防误触 / 屏幕适配
│   ├── teacher/                # 11 个 .py — 教师模式：线性流程 / 题目卡 / 词表 / 模板编辑
│   ├── theme_styles/           # 8 个 .py — 模块化 QSS（builder 组装）
│   ├── widgets/                # 40 个 .py — 可复用 UI 组件
│   │   └── ui/                     # 10 个 .py — Turna UI kit (GUI 焕新 W1).
├── tests/                  # unittest 自动化测试套件（分档见 run_gui_tests.py）
├── docs/                   # 契约与设计文档（ai_refactor_contract.md 为门禁契约）
└── tool/                   # 门禁与生成脚本（check_ai_boundaries.py / gen_module_tree.py）
```

<!-- module-tree:end -->

> 上面这棵树由 `tool/gui/tool/gen_module_tree.py` **从文件系统生成**，不要手工编辑。增删模块后重新生成：`python3 tool/gui/tool/gen_module_tree.py --write`；CI 用 `--check` 校验是否过期（已接入 `make guard-gui`）。手写清单曾把 `credential_store.py` / `git_remote_catalog.py` / `ai_prompt_library.py` 标在 `backend/`（实际已迁 `application/`）、列出已删除的 `ai_generator_dialog.py`，并整体漏掉 `i18n/` `infrastructure/` `teacher/` —— 故改为生成。

### 四项核心设计约束

1. **校验单一来源 (Validation Single Source)** — GUI **绝不自行定义二次校验规则**，写盘与保存一律调用 `CourseAdapter.save()`，底层执行 `course_cli validate` 与 `course_cli lint`；保证编辑器数据与终端运行及 Flutter 客户端渲染完全一致。
2. **JSON 为唯一真相源 (JSON as Ground Truth)** — 内存编辑状态在保存时全量写入 JSON 磁盘文件，格式符合版本控制规范（Git Diff 清晰可读），契合自动化脚本处理与移动端解析。
3. **ID 保持强不可变性 (Immutable IDs)** — 新增节点用 `short_id` 算法生成唯一 ID，不允许对现有节点 ID 重命名；ID 是 `wordId`、`grammarPointId` 等引用关系的唯一锚点，不可变保障引用长期稳定。
4. **保存失败自动回滚 (Atomic Rollback)** — 写盘保存并触发校验时若发现语法错误或结构非法，保存逻辑自动调用 `_restore_from` 恢复内存数据并写回历史状态，防止坏数据污染磁盘仓库。

---

## 版本发布与音频校验 (Publishing)

课程内容编辑完成准备上线时用工具栏 **「发布」**：版本 Bump → 扫描 `assets/sounds` 做 sound manifest 检查 → 校验全体 JSON 与资源文件完整性 → 渲染结果与 Checklist → 导出 Markdown 发布报告（汇总本次变更细节）。

1. **版本自动递增 (Version Bump)**：自动更新课程元数据版本号。
2. **音频清单检测 (Audio Sound Manifest)**：核对题目引用的音频路径在 `assets/sounds` 下是否存在，生成音频资源补全清单。
3. **差异与报告导出**：生成详细 Markdown 版本发布报告。

---

## 测试套件与打包构建

### 单元与集成测试

测试套件在 `tool/gui/tests/`（**纯 `unittest`，不依赖 pytest**）。分档真源是 [`run_gui_tests.py`](./run_gui_tests.py) 的模块 docstring —— 档位由测试模块是否（传递地）依赖 Qt 决定，不是手写名单。

```bash
cd tool/gui

# 门禁：分层 + 棘轮（与 CI / make guard-gui 同一组参数）
cd ../.. && make guard-gui && cd tool/gui

# 1. 日常 / PR 默认：L0 gate + L1 fast
python run_gui_tests.py ci -j 4

# 2. 全量：每个测试模块独立子进程（发布前 / nightly）
python run_gui_tests.py full -j 4

# 3. 只跑当前 git diff 影响的模块
python run_gui_tests.py affected -j 4

# 4. 查看分档结果 / 受影响模块
python run_gui_tests.py list-fast
python run_gui_tests.py list-affected
```

> **无图形环境**（CI 容器 / SSH 无 X11）先设 offscreen：PowerShell 用 `$env:QT_QPA_PLATFORM = "offscreen"`；bash 用 `QT_QPA_PLATFORM=offscreen python run_gui_tests.py ci`。

跨仓的相关测试（**不在** `run_gui_tests.py` 覆盖范围，需单独执行）：

```bash
cd ../..
python -m unittest discover -s test -p "*_test.py"   # 含 GUI→CLI round-trip
```

测试基准与施工流水记录见 [`tests/BASELINE.md`](./tests/BASELINE.md)；分层门禁的指标含义与基线来历见 [`docs/ai_refactor_contract.md`](./docs/ai_refactor_contract.md)。

### 设计文档索引

全部设计文档与契约清单见 **[`docs/README.md`](./docs/README.md)**：

- [`docs/experienceai.md`](./docs/experienceai.md) — Experience AI 上游规范（感知/决策/执行/解释/记忆五层），A3 / E4-M01 / E4-M0345 / K08 四篇设计的共同上位规范
- [`docs/ai_refactor_contract.md`](./docs/ai_refactor_contract.md) — 分层契约与门禁基线（`make guard-gui` 每条规则的出处）
- `docs/a3-companion-ambient-design.md`、`docs/e4-m01-attachments-context-design.md`、`docs/e4-m0345-multimodal-design.md`、`docs/k08-spiral-vocab-design.md` — 在役设计文档

> 新增文档后必须同步登记进 `docs/README.md`，否则 `make guard-gui`（`check_docs_index.py`）会失败 —— 避免再出现「规范躺在 archive 里、没有任何入口」的情况。
> 同一个脚本还校验正文里的文档指针是否指向真实文件（反引号包着的 `.md` 名与 Markdown 链接），避免出现「索引完美、正文全是死链」。

### PyInstaller 独立构建

```bash
# 安装 PyInstaller
pip install pyinstaller

# 默认构建 (在 dist/ 目录下生成 turna-gui 可执行文件)
python tool/gui/build_gui.py

# 清理构建缓存并重新构建
python tool/gui/build_gui.py --clean
```

打包配置见 [`turna_gui.spec`](./turna_gui.spec)。也可让 CI 出包：推 `gui-v*` tag（或手动触发 `.github/workflows/gui_release.yml` 的 workflow_dispatch），GitHub Actions 在 windows-latest 上跑 ci 档测试门禁 + PyInstaller 打包，把 `turna-gui.exe` 挂到对应 GitHub Release（workflow_dispatch 只产出 artifact，不建 Release）。

> 📌 **打包已知说明**：发布阶段的音效清单检测 (`sound-manifest`) 需要相对路径 `assets/sounds`。打包后的独立 exe 运行于非仓库根目录时音效检查可能提示路径缺失，但核心编辑、保存、校验与发布报告导出不受影响。推荐在仓库根目录环境下运行或打包。

---

## 附录：二语习得 (SLA) 语言学设计依据

数据结构与交互逻辑围绕二语习得 (Second Language Acquisition, SLA) 核心规律构建：

1. **6 大模板习得逻辑**：`intro`（新知引入 / 建立形式-意义映射，Nation 框架）、`practice`（受控操练 / 陈述性向程序性知识转化）、`listening`（听力解码 / 音位训练）、`reading`（语篇阅读 / 附带习得）、`review`（螺旋复习 / 抗遗忘）、`mastery`（综合精通 / 自动化产出）。
2. **题型与认知梯度**（教学阶梯 12 种；另有 `ankiCard` / `ankiHtmlCard` 仅供导入牌组再编排，不进入生成阶梯，合计 14 种）：**识别层**（低认知负荷，如 `showWord` / `multipleChoice` / `listenAndPick`）、**回忆层**（中认知负荷，如 `fillBlank` / `typeTheWord`）、**产出层**（高认知负荷，如 `translateSentence` / `reorderSentence`）；遵循**支架式教学** (Scaffolding)，建立课时内难度阶梯。
3. **听力三段式 (`debut` → `main` → `fin`)**：对应 Pre-listening / While-listening / Post-listening 框架，主音频支持叠加场景背景音训练环境噪音中的语音感知能力。
4. **资源独立解耦**：词汇 (`vocab`)、固定表达 (`expressions`)、语法点 (`grammar_points`) 独立建模与 ID 引用，实现跨课复用及语法点覆盖度统计。
