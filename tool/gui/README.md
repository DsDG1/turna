# Varnamala Course Editor GUI

基于 PySide6 的本地课程编辑器，配合 [`tool/course_cli.py`](../course_cli.py) 做
validate / lint / 发布工作流。GUI 是 `course_cli` 的图形前端，**校验单一来源**：
所有保存都走 `CourseAdapter.save()` -> `course_cli validate` + `lint`，失败回滚。

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

启动后点工具栏「打开」选择课程目录（如 `assets/courses/turkish/`）。

### 工具栏功能

| 按钮 | 功能 | 里程碑 |
|------|------|--------|
| 打开 | 选择并加载课程目录 | M1 |
| 新建课程目录 | 在仓库外任意目录一键初始化样例课程（默认中教英） | 新增 |
| 最近仓库 | 下拉菜单列出最近打开的 10 个课程仓库，按目录绝对路径去重 | 新增 |
| 保存 | 写盘 + validate + lint，失败回滚 | M1 |
| 向导建课 | 按模板选词生成 lesson | M5 |
| AI 生成课程（Beta） | 普通模式：按参数直接生成 JSON；许愿模式：对话式磨合后生成；支持课程类型选择与 [genre] 多模板批量生成 | 许愿模式 |
| 资源 | vocab / expressions / grammar_points 表格编辑 + CSV 导入导出 | M3 |
| 发布 | version bump + audio-manifest + diff + 清单报告 | M4 |

### 编辑能力

- **左侧树**：section / unit / lesson 三级，右键新增/删除
- **元数据**：name / description / prerequisite（多选勾选框，同层同类）
- **Lesson 内容**：6 种模板（intro/practice/review/mastery/listening/reading），
  12 种题型动态表单
- **AI 生成课程（Beta）**：
  - **普通模式**：填写主题、源语言、等级、单元数、课时、课程类型后直接生成 JSON，可编辑后导入。
  - **许愿模式**：像聊天一样和 AI 磨合课程需求，支持上传图片、PDF、Word、文本文件作为参考；AI 用通俗语言解释课程设计，点击「我感觉差不多了」后生成完整课程并导入课程树。
  - **课程类型选择**：下拉框可选 认识新词 / 巩固练习 / 复习 / 听力训练 / 阅读理解 / 综合测验 / 混合（对应 intro/practice/review/listening/reading/mastery/mixed 模板）。
  - **[genre] 多模板批量生成（Beta，默认关闭）**：勾选后，可在主题或额外指令中插入 `[intro]`、`[practice]`、`[listening]`、`[reading]`、`[mastery]` 等标签，AI 会按标签为对应单元/课时生成相应模板结构；未标注的部分回退到默认回退模板。开启时会显著增加 token 消耗。
  - **免责声明**：主窗口状态栏常驻显示「AI 生成内容仅供参考，请作者自行审核其准确性与适用性。」
  - **Beta 警告**：首次点击「AI 生成课程（Beta）」会弹出提示，说明本功能消耗大量 token 且建议模型支持 1M 上下文窗口。
- **资源表**：直接编辑内存，CSV 仅作运输工具；保存时写 JSON + 校验

---

## 测试

```bash
# 后端单元测试（沙箱可跑，无需 PySide6）
python -m unittest tool.gui.tests.test_course_adapter \
  tool.gui.tests.test_lesson_content tool.gui.tests.test_lesson_round_trip
# 期望：37 passed

# GUI -> CLI round-trip（M5.1，用 Turkish 课程做 fixture）
python test/tool/gui_round_trip_test.py -v
# 期望：5 passed

# CLI 回归
python -m unittest discover -s test -p "*_cli_test.py"
# 期望：7 passed
```

测试只覆盖后端逻辑（adapter / course_cli 纯函数），不导入 PySide6。
GUI 烟测需本机手动，清单见 [`guiplan.md`](./guiplan.md) §10.3。

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
│   ├── backend/
│   │   ├── course_adapter.py  # 封装 course_cli，save/validate/lint/发布/一键初始化
│   │   ├── lesson_content.py  # lesson 模板 / 题型 normalize
│   │   ├── ai_generator.py     # OpenAI 兼容后端 + prompt 构建
│   │   ├── ai_genre.py         # [genre] 标签 ↔ 模板映射
│   │   └── attachment_extractor.py # 附件转 OpenAI content
│   ├── dialogs/
│   │   ├── new_lesson_dialog.py
│   │   ├── ai_generator_dialog.py # AI 生成课程对话框（普通 + 许愿）
│   │   └── init_course_dialog.py # 一键初始化新课程仓库
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
2. 点击对话框右上角「API 设置」填写：
   - **Base URL**：如 `https://api.openai.com/v1`、`https://api.deepseek.com/v1`、本地 Ollama 地址等。
   - **API Key**：密钥仅在内存中，关闭程序后不保留。
   - **Model**：建议使用支持长上下文的模型（如 1M 上下文窗口）。

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
3. 点击「生成课程」，等待返回 JSON。
4. 在「生成结果」中检查/编辑 JSON，可点「校验 JSON」验证。
5. 点击「导入到课程」加入左侧课程树，记得保存。

### 4. 许愿模式

1. 在聊天框中用自然语言描述需求，可拖入图片/PDF/Word/文本文件作为参考。
2. AI 会用中文回复建议与澄清问题，反复磨合。
3. 满意后点击「我感觉差不多了」，AI 生成完整课程 JSON 并给出通俗解释。
4. 点击「导入到课程」加入课程树。

### 5. [genre] 多模板批量生成（Beta）

> 默认关闭，需主动勾选「启用 [genre] 多模板批量生成（Beta）」。

- 开启后，在主题或额外指令中插入 genre 标签，例如：`[intro] 旅行词汇 [listening] 餐饮对话`。
- AI 会按标签为对应单元/课时生成相应模板结构；未标注部分回退到默认回退模板。
- 可用标签：`[intro]`、`[practice]`、`[review]`、`[listening]`、`[reading]`、`[mastery]`、`[mixed]`。
- 关闭时所有课时强制使用单一模板，prompt 不注入 genre 映射表，节省 token。
- **注意**：开启后 prompt 显著变长，消耗大量 token，建议模型支持 1M 上下文。

### 6. 免责声明

主窗口状态栏常驻显示：

> AI 生成内容仅供参考，请作者自行审核其准确性与适用性。

---

## 一键初始化与最近仓库

### 新建课程目录

1. 点击工具栏「新建课程目录」。
2. 选择父目录（可在仓库外任意位置），填写课程显示名。
3. 默认目标语言 `en`、源语言 `Chinese`、3 个 Section、每单元 3 课时。
4. 点击「初始化」，会在父目录下创建以课程名命名的子目录，生成 `index.json`、`vocab.json`、`expressions.json`、`grammar_points.json` 与 `sections/*.json`。
5. 样例内容为中教英，非常随意，仅供参考。
6. 生成后自动加载到课程树，可直接编辑或保存。

### 最近仓库

- 工具栏「最近仓库」下拉菜单列出最近打开的 10 个课程仓库。
- 以目录绝对路径去重，新打开的仓库排到最前。
- 启动时若存在历史记录，会询问是否打开上次使用的仓库。
- 数据存储在 `QSettings("Varnamala", "CourseEditor")`，路径唯一防止冲突。
