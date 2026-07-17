# Varnamala Course Editor GUI

基于 PySide6 的本地课程编辑器，配合 [`tool/course_cli.py`](../course_cli.py) 做
validate / lint / 发布工作流。GUI 是 `course_cli` 的图形前端，**校验单一来源**：
所有保存都走 `CourseAdapter.save()` -> `course_cli validate` + `lint`，失败回滚。

> **新手入门**：从零开始的图文步骤指南见 [`docs/authoring/gui-beginner-guide.md`](../../docs/authoring/gui-beginner-guide.md)（无需命令行或 JSON 经验即可使用）。
> 设计与里程碑见 [`guiplan.md`](./guiplan.md)。本 README 覆盖安装、运行、测试、打包。

---

## 安装

需要 Python 3.11+。

```bash
pip install PySide6 PyPDF2 python-docx
```

> TRAE 沙箱因 `WinError 5` 无法 pip 安装 PySide6，GUI 启动与打包请在本地终端进行。
> 后端逻辑（adapter / course_cli / ai_generator / attachment_extractor）无 PySide6 依赖，测试可在沙箱跑。

---

## 运行

在仓库根目录：

```bash
python -m tool.gui.src.main
```

启动后点击工具栏「打开」选择课程目录（如 `assets/courses/turkish/`）。

### 工具栏功能

| 按钮 | 功能 | 里程碑 |
|------|------|--------|
| 打开 | 选择并加载课程目录 | M1 |
| 新建课程目录 | 在仓库外任意目录一键初始化样例课程（默认中教英） | 新增 |
| 最近仓库 | 下拉菜单列出最近打开的 10 个课程仓库，按目录绝对路径去重 | 新增 |
| 保存 | 写盘 + validate + lint，失败回滚 | M1 |
| 向导建课 | 按模板选词生成 lesson | M5 |
| AI 生成课程（Beta） | 普通模式：按参数直接生成 JSON；许愿模式：对话式细化后生成；支持课程类型选择、[genre] 多模板批量生成、供应商预设、连接测试与用量面板 | 许愿模式 |
| 资源 | vocab / expressions / grammar_points 表格编辑 + CSV 导入导出 | M3 |
| 发布 | version bump + audio-manifest + diff + 清单报告 | M4 |
| 设置 | 主题、UI 字体缩放、AI 配置、撤销步数、自动保存、最近仓库历史 | 新增 |

### 设置

点击工具栏「设置」打开设置对话框，所有偏好项保存在 `QSettings("Varnamala", "CourseEditor")` 中，重启后生效：

- **外观**：切换深色/浅色主题；调整 UI 字体缩放（80%–150%，仅字体，整体窗口缩放由系统 DPI 控制）。
- **AI 配置**：选择供应商预设（DeepSeek / OpenAI / Moonshot / Ollama / 自定义），自动填充 Base URL 与默认模型；可启用 reasoning、调整请求超时（5–600 秒）、生成温度（0.0–2.0）与自动重试次数（0–5）。填写完成后可使用「测试连接」发送 1-token 请求立即验证。**API Key 仅在当前会话内存中保留，关闭编辑器后自动清空；Base URL、Model 等配置会持久化。**
- **AI 用量**：查看今日/累计 token、请求数、估算成本与成功率；可刷新、打开日志目录或清空本地记录。
- **编辑器行为**：
  - 自动保存：关闭窗口时若有未保存更改，自动保存而不再弹窗确认。
  - 撤销步数上限：10–500，修改后立即生效。
- **最近仓库历史**：查看、删除单条或清空全部历史。

### 编辑能力

- **左侧树**：section / unit / lesson 三级，右键新增/删除
- **元数据**：name / description / prerequisite（多选勾选框，同层同类）
- **Lesson 内容**：6 种模板（intro/practice/review/mastery/listening/reading），
  12 种题型动态表单
- **AI 生成课程（Beta）**：
  - **普通模式**：填写主题、源语言、等级、单元数、课时、课程类型后直接生成 JSON，可编辑后导入。
  - **许愿模式**：以对话形式与 AI 逐步细化课程需求，支持上传图片、PDF、Word、文本文件作为参考；AI 以中文解释课程设计思路，点击「我感觉差不多了」后生成完整课程并导入课程树。
  - **课程类型选择**：下拉框可选 认识新词 / 巩固练习 / 复习 / 听力训练 / 阅读理解 / 综合测验 / 混合（对应 intro/practice/review/listening/reading/mastery/mixed 模板）。
  - **[genre] 多模板批量生成（Beta，默认关闭）**：勾选后，可在主题或额外指令中插入 `[intro]`、`[practice]`、`[listening]`、`[reading]`、`[mastery]` 等标签，AI 会按标签为对应单元/课时生成相应模板结构；未标注的部分回退到默认回退模板。开启时会显著增加 token 消耗。
  - **免责声明**：主窗口状态栏常驻显示「AI 生成内容仅供参考，请作者自行审核其准确性与适用性。」
  - **Beta 警告**：首次点击「AI 生成课程（Beta）」会弹出提示，说明本功能消耗大量 token 且建议模型支持 1M 上下文窗口。
- **资源表**：直接编辑内存，CSV 仅作运输工具；保存时写 JSON + 校验

---

## 测试

```bash
cd tool/gui

# 后端逻辑 + GUI 逻辑测试（无需真实显示，offscreen 即可，无需 PySide6 显示服务器）
QT_QPA_PLATFORM=offscreen python -m pytest tests/ --ignore=tests/test_app.py -q
# 期望：405 passed（详见 tests/BASELINE.md）

# 完整 GUI 测试（需本机图形环境或可用 offscreen 的 PySide6）
python -m pytest tests/test_app.py -q

# GUI -> CLI round-trip（M5.1，用 Turkish 课程做 fixture）
python test/tool/gui_round_trip_test.py -v
# 期望：5 passed

# CLI 回归
python -m unittest discover -s test -p "*_cli_test.py"
# 期望：7 passed
```

后端逻辑测试（adapter / course_cli / ai_generator 纯函数）不导入 PySide6；完整 GUI 测试与烟测需要 PySide6。
GUI 烟测需本机手动，清单见 [`guiplan.md`](./guiplan.md) §10.3 与 [`docs/authoring/teacher-usability-checklist.md`](../docs/authoring/teacher-usability-checklist.md)。

---

## 打包（M5.2）

用 PyInstaller 生成单文件 exe：

```bash
pip install pyinstaller
python tool/gui/build_gui.py            # 产出 dist/varnamala-gui.exe
python tool/gui/build_gui.py --clean    # 先清 build/ dist/
python tool/gui/build_gui.py --onedir   # onedir 代替 onefile
```

spec 文件：[`varnamala_gui.spec`](./varnamala_gui.spec)。

**已知限制**：`course_cli.SOUNDS_DIR` 是相对路径 `assets/sounds`，仅 audio-manifest
发布步骤使用。打包版 exe 里该路径相对 CWD，audio-manifest 的 status 检查可能全部
报 missing，除非在仓库根目录运行。核心编辑 / validate / lint / version-bump 不依赖它。

> PyInstaller 同 PySide6 无法在 TRAE 沙箱安装，exe 产物请在本地验证。

---

## 架构

```
tool/gui/
├── src/
│   ├── main.py                # 入口
│   ├── app.py                 # MainWindow + 工具栏
│   ├── application/
│   │   ├── commands.py        # 撤销/重做命令
│   │   └── settings.py        # 用户偏好模型 + QSettings 持久化
│   ├── backend/
│   │   ├── course_adapter.py  # 封装 course_cli，save/validate/lint/发布/一键初始化
│   │   ├── lesson_content.py  # lesson 模板 / 题型 normalize
│   │   ├── ai_generator.py     # OpenAI 兼容后端 + prompt 构建
│   │   ├── ai_genre.py         # [genre] 标签 ↔ 模板映射
│   │   ├── ai_presets.py       # 供应商/模型预设与本地价目表
│   │   ├── ai_prompt_library.py # prompt 模板库与生成历史
│   │   ├── ai_stream.py        # SSE 流式解析
│   │   ├── ai_usage.py         # token/成本估算
│   │   └── attachment_extractor.py # 附件转 OpenAI content
│   ├── dialogs/
│   │   ├── new_lesson_dialog.py
│   │   ├── ai_generator_dialog.py # AI 生成课程对话框（普通 + 许愿）
│   │   ├── init_course_dialog.py # 一键初始化新课程仓库
│   │   └── settings_dialog.py # 设置面板
│   └── widgets/
│       ├── course_tree.py     # 左侧树
│       ├── detail_panel.py    # 右侧容器
│       ├── metadata_form.py   # section/unit/lesson 元数据 + prereq 多选
│       ├── lesson_editor.py   # lesson 内容编辑
│       ├── interaction_forms.py # 12 题型表单工厂
│       ├── resource_editor.py # 资源表 + CSV（M3）
│       └── publish_dialog.py  # 发布对话框（M4）
├── tests/                     # 后端单元测试
├── varnamala_gui.spec         # PyInstaller spec（M5.2）
├── build_gui.py               # 打包脚本（M5.2）
└── guiplan.md                 # 设计文档
```

### 关键约束（guiplan §4）

- **校验单一来源**：GUI 不另立校验标准，全部走 `course_cli validate` + `lint`
- **JSON 是唯一真理源**：内存编辑 -> save 写 JSON -> CLI 校验
- **id 不可变**：新增用 `short_id` 生成，不允许重命名 id
- **保存回滚**：validate 失败时 `_restore_snapshot` 恢复内存 + 重写文件

---

## AI 生成课程使用指南

### 1. 准备

1. 点击工具栏「AI 生成课程（Beta）」，首次会弹出 Beta 警告，确认后不再重复提示。
2. 点击工具栏「设置 → AI 配置」：
   - **供应商预设**：选择 DeepSeek / OpenAI / Moonshot / Ollama 可自动填入 Base URL 与默认模型；选「自定义」则保留手动填写的内容。
   - **Base URL / API Key / Model**：按需核对或手动填写。**API Key 仅在当前会话内存中保留，关闭编辑器后自动清空**，不会写入磁盘。
   - **reasoning / 超时 / 温度 / 重试**：DeepSeek 等支持 reasoning 的端点可开启 reasoning 字段；超时与温度影响所有 AI 请求；自动重试次数决定校验失败时最多自动发起几轮修正请求。
   - **测试连接**：点击后发送 1-token 最小请求，立即确认配置能否连通。
3. 在「设置 → AI 用量」中可查看今日/累计 token、请求数、估算成本与成功率。
4. 所有 AI 对话框（生成课程、编辑、改写题目/课程、错误分析）均共用这一份配置，不再各自提供 API 输入框。

### 2. 通用参数

| 字段 | 说明 |
|------|------|
| 生成模式 | 普通模式 / 许愿模式 |
| 目标语言 | 学习的语言，如 Turkish、English |
| 源语言 | 提示语与翻译来源，如 Chinese |
| 等级 | A1–C1 |
| 单元数 | 1–5 |
| 每单元课时 | 1–5 |
| 课程类型 | 认识新词/巩固练习/复习/听力训练/阅读理解/综合测验/混合 |
| 额外指令 | 可选的自由文本说明 |

### 3. 普通模式

1. 选择课程类型（不开启 genre 开关时，所有课时统一使用该模板）。
2. 在「主题」填写内容，如 `旅行词汇`。
3. 可通过「模板」下拉选择已保存的 prompt 模板，或在「历史」下拉找回最近使用过的生成 prompt。
4. 点击「生成课程」。生成过程中状态栏会显示阶段标签与本次 token/估算成本；若开启自动重试，校验失败时会自动将错误信息反馈给 AI 进行修正。
5. 生成结果区包含结构化预览树、JSON 编辑器（语法高亮、`Ctrl+Shift+F` 格式化、错误行红标）与「试做本课」按钮，确认无误后再导入。
6. 点击「导入到课程」加入左侧课程树。若目标 section 已存在，会弹出合并预览，列出新增与覆盖的 unit/lesson，可取消勾选后再确认；不存在则直接追加。确认后记得保存。

### 4. 许愿模式

1. 在聊天框中用自然语言描述需求。拖入图片/PDF/Word/文本文件后，会以 chip 形式显示附件；点击 chip 可预览提取内容，按 Delete 或点击 × 可移除。
2. 与普通模式相同，可使用「模板」/「历史」快速载入 prompt；开启 genre 开关后，可在消息中插入 `[intro]`、`[listening]` 等标签。
3. AI 以中文回复建议与澄清问题，可多轮对话逐步对齐需求。
4. 确认需求后点击「我感觉差不多了」，AI 生成完整课程 JSON 并给出设计说明。生成阶段「取消」按钮可立即中断 worker。
5. 若生成或解释失败，对话框会显示「AI 分析原因」，点击后由模型对错误进行二次分析。
6. 生成结果会写入 JSON 编辑器，可手动微调；点击「导入到课程」时以编辑器内容为准。若目标 section 已存在，会弹出合并预览，列出新增与覆盖的 unit/lesson，可取消勾选后再确认。
7. 导入后记得保存。

### 5. [genre] 多模板批量生成（Beta）

> 默认关闭，需主动勾选「启用 [genre] 多模板批量生成（Beta）」。

- 开启后，在主题或额外指令中插入 genre 标签，例如：`[intro] 旅行词汇 [listening] 餐饮对话`。
- AI 会按标签为对应单元/课时生成相应模板结构；未标注部分回退到默认回退模板。
- 可用标签：`[intro]`、`[practice]`、`[review]`、`[listening]`、`[reading]`、`[mastery]`、`[mixed]`。
- 关闭时所有课时强制使用单一模板，prompt 不注入 genre 映射表，节省 token。
- **注意**：开启后 prompt 显著变长，消耗大量 token，建议模型支持 1M 上下文。

### 6. Prompt 模板库与历史

- **保存为模板**：在当前参数/主题/额外指令下点击「保存为模板」，输入名称即可把完整 spec（目标语言、源语言、等级、单元数、课时、模板、genre 开关、extra）保存到本地 QSettings。
- **应用模板**：「模板」下拉列出所有已保存模板，选择后自动覆盖当前参数。
- **历史**：「历史」下拉保留最近 20 条不重复的生成 prompt，关闭窗口后仍可恢复上次使用的 prompt。
- 同名模板保存会覆盖；删除入口将在后续版本提供。

### 7. 附件预览与引用

- 许愿模式支持拖入图片、PDF、Word、文本文件。
- 附件以 chip 展示文件名与提取预览；点击 chip 弹出预览对话框：图片显示缩略图，文本/PDF/Word 显示提取的前 10 万字符。
- 在预览对话框中可切换引用方式：「作为当前消息附件」或「作为独立 user 消息」。
- 选中 chip 后按 Delete 可移除附件。

### 8. 用量面板

- 生成对话框右下角会显示本次请求的 token 数与估算成本。
- 在「设置 → AI 用量」中可查看今日/累计 token、请求次数、成功/失败数、估算成本与成功率。
- 成本按本地价目表估算，标注为「仅供参考，不作为计费依据」。

### 9. AI 失败分析与修正

- 任意 AI 请求失败（普通生成、许愿、改写题目/课程、AI 自动修正）都会提供「AI 分析原因」按钮，由模型对错误信息进行二次分析并给出可操作建议。
- AI 自动修正对话框成功后，点击「查看 diff」可对比修正前后的结构差异，确认后再决定「应用」或「放弃」。对 section 级别的修正，应用时会进入合并预览，按 id 合并到现有 section。
- 普通模式若生成后结构校验报错且自动重试仍未解决，可在 JSON 编辑器中手动修复，或重新生成。

### 10. 免责声明

主窗口状态栏常驻显示：

> AI 生成内容仅供参考，请作者自行审核其准确性与适用性。

---

## 一键初始化与最近仓库

### 新建课程目录

1. 点击工具栏「新建课程目录」。
2. 选择父目录（可在仓库外任意位置），填写课程显示名。
3. 默认目标语言 `en`、源语言 `Chinese`、3 个 Section、每单元 3 课时。
4. 点击「初始化」，会在父目录下创建以课程名命名的子目录，生成 `index.json`、`vocab.json`、`expressions.json`、`grammar_points.json` 与 `sections/*.json`。
5. 样例内容为中教英，用于演示数据结构，仅供参考。
6. 生成后自动加载到课程树，可直接编辑或保存。

### 最近仓库

- 工具栏「最近仓库」下拉菜单列出最近打开的 10 个课程仓库。
- 以目录绝对路径去重，新打开的仓库排在列表顶部。
- 启动时若存在历史记录，会询问是否打开上次使用的仓库。
- 数据存储在 `QSettings("Varnamala", "CourseEditor")`，路径唯一防止冲突。
