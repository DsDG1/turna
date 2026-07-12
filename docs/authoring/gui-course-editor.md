# GUI 课程开发工具设计

> 本文件描述如何在**不破坏 JSON-first 契约**的前提下，为 Varnamala 构建一个本地
> GUI 课程编辑器。契约本体见 [`course-layout.md`](./course-layout.md)；本文不重复
> 契约，只规定 GUI 与现有 CLI 工具链的协作方式。
>
> `CLAUDE.md` 把 "External GUI editor" 列为 Removed —— 那条决定针对的是「把 GUI
> 当作内容真理源、替代 JSON」的方向。本文档定义的 GUI 不是内容真理源，而是
> `assets/courses/<lang>/` 下 JSON 文件的一个**受约束表单前端**，后端复用
> [`tool/course_cli.py`](../../tool/course_cli.py)。JSON 仍是唯一真理源。

---

## 1. 定位与边界

GUI 是什么：

- 一个本地桌面程序，打开 `assets/courses/<lang>/` 目录，以表单/树形视图编辑其中的
  `index.json`、`sections/*.json`、`vocab.json`、`expressions.json`、
  `grammar_points.json`。
- 所有读写都落到这些 JSON 文件，与人工编辑完全等价。

GUI 明确**不做**（对齐 `course-layout.md` 的 Forbidden 清单）：

| 禁止 | 原因 |
|------|------|
| 写 app 的 SQLite 缓存 | SQLite 是派生缓存，非真理源（ADR 0002） |
| 把多 section 合并成一个大 JSON | 违反 L0/L1/L2 分层，破坏加载模型 |
| 自动重编号 / 改 lesson id | id 不可变，改动会孤立 `completedLessonIds` 与 `LessonWordLink` |
| 引入新 `runtimeType` 值 | 每个 `runtimeType` 必须有 Dart `Interaction` case |
| 绕过 `validate`/`lint` 直接保存 | 校验是 Python+Dart 双源契约，GUI 不另立标准 |
| 超过 scale ceiling 仍允许保存 | 上限在 `course_validator.dart` 与 `course_cli.py` 双处定义 |

一句话：**GUI 产出的 JSON 必须能被现有 `course_cli.py validate` + `lint` 和
`flutter test`（Dart 校验器）全部通过，否则不许保存。**

---

## 2. 架构：薄前端 + CLI 后端

核心原则：**GUI 不重复实现校验/归一化逻辑**。所有规则集中在 `tool/course_cli.py`
（Python 侧）与 `lib/courses/course_validator.dart`（Dart 侧，由 `flutter test`
守护）。GUI 通过子进程或同进程 import 调用 CLI，保证 Python/Dart 不漂移。

### 2.1 复用点（带函数名）

| 能力 | 调用 | 用途 |
|------|------|------|
| 结构校验 | `course_cli.py validate --format json` | 保存前/后校验，JSON 供 UI 解析 |
| 内容质量 | `course_cli.py lint [--strict]` | 空 tag、悬空引用、未引用资源等告警 |
| 批量导出 | `course_cli.py export-csv --type {vocab,expressions,grammar_points} --output ...` | 表格批量编辑入口 |
| 批量导入 | `course_cli.py import-csv --type ... --input ... [--dry-run]` | 表格编辑回写 |
| 听力资产清单 | `course_cli.py audio-manifest --output ...` | 听力 MP3 覆盖核对 |
| 版本对比 | `course_cli.py diff --before ... --after ...` | 发布前后 id 集变更核对 |
| 读写归一化 | `course_cli.py` 的 `load_*` / `save_json` / `normalize_section` | 同进程直接 import |
| 模板骨架 | `docs/authoring/templates/lesson-{intro,practice,mastery}.json` | 新建 lesson = clone 模板 |

### 2.2 调用契约

`validate --format json` 返回（见 `cmd_validate`）：

```json
{
  "ok": false,
  "errorCount": 1,
  "problems": [
    { "level": "error", "message": "...", "path": "section:section4/unit:u-1" }
  ]
}
```

GUI 职责：解析 `problems[]`，把 `path`（形如 `section:<sid>` / `section:<sid>/unit:<uid>`）
映射回树形视图的高亮节点，并把 `message` 挂到对应 detail 面板。`ok == false` 时
**禁用保存按钮**。

---

## 3. 数据模型映射（GUI 视图 ↔ JSON）

Schema 完整定义见 [`course-layout.md`](./course-layout.md)，此处只给 GUI 视图骨架，
不复述字段。

### 3.1 三栏树（Section → Unit → Lesson）

```
┌─ Section index.json
│   └─ Unit (sections/*.json::units[])
│       └─ Lesson (units[]::lessons[])
│           ├─ content.stages[]          # legacy/review/mastery 用
│           ├─ content.subLessons[]       # intro/practice 用
│           ├─ content.listeningPhases[]  # listening 用
│           └─ content.readingPassage     # reading 用
└─ Resources
    ├─ vocab.json::words[]
    ├─ expressions.json::expressions[]
    └─ grammar_points.json::grammarPoints[]
```

左侧树 + 右侧 detail。detail 按 lesson 的 `template` 字段**切换可用字段**：

| `template` | 必须存在的 content 形态 | 其它形态在 UI 中禁用/隐藏 |
|------------|------------------------|--------------------------|
| `intro` / `practice` | `subLessons[]` | stages / listeningPhases |
| `listening` | `listeningPhases[]` | subLessons / stages（readingPassage 可选） |
| `reading` | `readingPassage` | — |
| `mastery` | 单一 `stages[]`（且 `len==1`） | subLessons / listeningPhases |
| `legacy` / `review` | `stages[]` 或 `subLessons[]` 或 `listeningPhases[]` 至少其一 | — |

这些约束直接对应 `course_cli.py::_validate_lesson` 的分支，**GUI 只暴露契约允许的
形态**，让非法结构在 UI 层就构造不出来。

flat `questions`（旧式）仅作**只读**展示，并标注「seed 时归一化为单 stage」——
新内容只写 canonical 形态。

### 3.2 Resources 编辑器

vocab / expressions / grammar_points 走 **CSV 进出**：

1. GUI 调 `export-csv` 生成临时 CSV → 在表格组件里编辑。
2. 编辑完调 `import-csv --dry-run` 预检，再 `import-csv` 落盘。

这样批量增改、外部翻译协作、diff 都复用 CLI 既有路径，不引入第二套数据流。

---

## 4. 核心工作流

```
打开课程目录
   ↓ load index + sections + resources（同进程 import course_cli 的 load_*）
编辑（受约束表单，按 template 切换字段）
   ↓ 实时本地校验：validate --format json（debounced）
保存
   ↓ 1. 内存快照当前 JSON（或 git stash 作为回滚点）
   ↓ 2. 写 JSON 文件
   ↓ 3. validate → 失败回滚 + 报错
   ↓ 4. lint → 告警展示，但不阻断（除非 --strict）
发布清单（对齐 course-layout.md 的 Export checklist）
   ↓ 5. 若 index 改动：bump index.json version
   ↓    若 expressions.json 改动：bump 其 version
   ↓ 6. 可选：python3 tool/export_content_inventory.py
   ↓ 7. diff --before <git HEAD 的课程目录快照> --after <当前> 复核变更
提交
```

版本号 bump：GUI 提供「标记本次为内容发布」按钮，自动检测哪些文件相对上次发布有改动
并相应 bump `version`，避免作者忘记 bump 导致用户不触发重种子（ADR 0002）。

---

## 5. 约束与护栏

| 护栏 | 实现方式 |
|------|----------|
| **id 全局唯一** | 新建时生成，保存前用 `validate` 的 "Duplicate id" 检查兜底 |
| **id 不可变** | UI 的 id 字段只读；rename 按钮只改 `name`，标题旁注明「id 永不随重命名改变」 |
| **scale ceiling** | 复用 `course_cli.py::MAX_UNITS_PER_SECTION=60`、`MAX_LESSONS_PER_UNIT=40`；新增 unit/lesson 时达上限禁用「新增」按钮并提示 |
| **引用完整性** | `showWord.wordId` / `expressionId`、`grammarPointId`、`exampleExpressionIds` 全部用**下拉框**从已加载资源里选，不允许手输自由文本（杜绝悬空引用） |
| **tags 白名单** | 多选下拉，选项 = `course_cli.py::ALLOWED_TAGS`（15 个），未知 tag 直接不可选 |
| **template↔content 一致** | 见 §3.1，UI 层不让非法组合出现 |
| **听力资产** | `audioAsset` 仅在 listening lesson 内允许；非 listening 引用 audioAsset 是 `lint` 的 error，UI 在保存时拦截 |

---

## 6. 技术选型建议（非约束）

两个现实候选：

### (a) Python + PySide6 / Tkinter —— 推荐

- 与 `course_cli.py` 同语言，**直接 `import course_cli`** 调用 `load_*` /
  `validate` 内部函数，零子进程开销、零 JSON 序列化往返。
- 校验逻辑单一来源，Python/Dart 漂移风险最低。
- 打包简单（pyinstaller 单文件），作者本地即可运行。
- 只读 `lib/courses/course_validator.dart` 作为「Dart 侧等价校验」对照，由
  `flutter test` 守护一致性，不在 GUI 里复制 Dart 规则。

### (b) Flutter desktop

- 复用项目 Dart 模型与 `course_validator.dart`，跨端一致；但要把
  `course_cli.py` 的 CSV/diff/audio-manifest 能力在 Dart 侧重写一份，违背
  「单一来源」原则，**不推荐**除非将来要让编辑器进 app 本体。

### 为何不放进 app 本体

app 是面向学习者的离线学习包，编辑器是作者工具——受众、发布周期、依赖体积都不同。
分开可让学习者包保持精简，编辑器单独演进。

---

## 7. 验收与对齐

GUI 必须满足的退出标准：

1. **校验对齐**：GUI 写出的课程目录 100% 通过
   `python3 tool/course_cli.py validate` + `lint`，且 `flutter test`（含
   `course_validator.dart` 用例）全绿。
2. **Round-trip 测试**：GUI 写出的 section 与等价手写 section 在
   `course_cli.py validate` 下结果一致——参照现有
   `test/courses/seeder_round_trip_test.dart` 与 `test/tool/course_cli_validate_test.py`
   的模式新增一个 GUI→CLI round-trip 用例（输入固定 fixture JSON，经 GUI 写出，
   再经 CLI 校验）。
3. **契约不漂移**：任何 GUI 引入的新字段/新 `runtimeType` 必须先在
   `course-layout.md` + `course_cli.py` + `course_validator.dart` 三处同步落地，
   GUI 才能暴露——禁止 GUI 先行、契约后补。

---

## 参考

- 契约：[`docs/authoring/course-layout.md`](./course-layout.md)
- 后端工具链：[`tool/course_cli.py`](../../tool/course_cli.py)
- Dart 校验器：[`lib/courses/course_validator.dart`](../../lib/courses/course_validator.dart)
- 模板：[`docs/authoring/templates/`](./templates/)（intro / practice / mastery）
- 测试范式：`test/courses/seeder_round_trip_test.dart`、`test/tool/course_cli_validate_test.py`
- 版本与重种子：ADR 0002；L0/L1/L2 加载分层：ADR 0019