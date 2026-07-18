# bookplan2 — 教材导入功能下一阶段规划

> 本规划基于教材导入已落地的基础实现，**不考虑真实 PDF 导入/OCR 内容**（即仍只支持 `.md/.txt` 和文本原生 `.pdf`）。重点在于：把当前"能跑通"的功能升级为**可维护、可验证、可复用、体验完整**的生产级特性。

---

## 一、当前基线

已实现：
- `TextbookImportDialog` 单对话框 6 步时间线
- `markdown_chopper` / `knowledge_extractor` / `knowledge_schema` / `textbook_to_course` 后端流水线
- `app.py` 工具栏入口 + `_import_section_dict` 共享导入收尾
- 文本文件读取 + `attachment_extractor` 文本 PDF 降级解析
- **Phase 1 完成**：拆分为 `TextbookImportController` + `TextbookImportView`，引入 `ImportStepResult`，修复 GUI 测试挂起
- **Phase 2 完成**：`TextbookProject` + `TextbookProjectStore` + `TextbookLibraryDialog`，支持关闭后恢复继续

主要短板：
- 抽取结果缺少质量评分、重复检测、与现有课程的碰撞提示
- 没有持久化配置/模板，老师每次都要重新配语言、重审章
- 知识点Review仅支持简单编辑，缺少批量操作、AI 辅助修复、试学验证
- 错误处理粗放：LLM 失败只有重试，没有人工接管或兜底方案
- 与现有 AI 生成功能割裂：教材导入和 AI 生成没有共享 Prompt 库/资源去重

---

## 二、目标

把教材导入从"一次性 Demo 功能"升级为课程团队**日常可用的工作流**：

1. **稳**：任何一步失败都有明确反馈和人工接管路径，不崩、不丢数据。
2. **快**：常见课本/教案能一次导入，减少反复调 Prompt 和审校成本。
3. **准**：抽取结果与现有课程资源去重、自洽，导入前可试学验证。
4. **可维护**：后端模块职责清晰、单测覆盖率高、GUI 测试可运行。

---

## 三、需要大量添加的功能

### 3.1 数据层：课本项目持久化

**新增 `TextbookProject` 模型**（`src/backend/textbook_project.py`）

- 保存一次导入的完整上下文：
  - 源文件路径/校验和（不存大文件本身，只存引用）
  - 解析后的原始 Markdown
  - 章节切分结果 + 勾选状态
  - 每章抽取的 `KnowledgePoints`（含 LLM 原始输出快照）
  - 审校后的修改记录
  - 导入映射：哪些 section 被导入/合并到了哪个 course
- 落盘位置：`tool/gui/var/textbooks/{project_id}/project.json`
- 支持：新建/打开最近/复制项目/删除项目

**新增 `TextbookLibraryDialog`**

- 列出历史课本项目
- 显示状态标签："已解析" / "已抽取" / "已审校" / "已导入"
- 双击继续上次未完成的导入

### 3.2 抽取层：多策略 + 质量评估

**新增 `ExtractionStrategy` 枚举 + 策略注册表**

```python
class ExtractionStrategy(Enum):
    STANDARD = "standard"      # 当前：一次性抽 words/expressions/grammarPoints
    TWO_PASS = "two_pass"      # 先抽词汇，再基于词汇抽表达和语法
    VOCAB_ONLY = "vocab_only"  # 只抽词汇，后续用 lesson_content 生成表达/语法
```

- 老师在设置里可选策略
- 每种策略有独立 Prompt 和后置校验规则

**新增 `ExtractionQualityReport`**

每次抽取后给出结构化评分：

| 维度 | 说明 |
|---|---|
| `coverage` | 章节中明显是知识点的术语有多少被覆盖 |
| `duplicate_rate` | 与现有 course 资源重复比例 |
| `consistency` | 词汇 ↔ 表达 ↔ 语法点之间的引用自洽性 |
| `lang_check` | 源语言/目标语言混杂、空字段等低级错误 |

- 低分项在 Review 页左侧用红黄标记
- 提供"一键修复"：对空字段、重复项调用 `ai_fixer`

**新增 `KnowledgeMerger`**

- 合并同一课本多章节抽取结果时，全局去重（基于 term + translation hash）
- 与现有 course 的 `vocab.json` / `expressions.json` / `grammar_points.json` 交叉比对
- 对潜在重复给出"替换/合并/保留"建议

### 3.3 审校层：强化 Review 体验

**重构 `_ReviewTable` 为独立模块 `src/widgets/resource_review_table.py`**

- 支持列排序、按 tag 过滤、正则搜索
- 批量勾选/反选/删除
- 内联 AI 辅助：选中行后右键"改写翻译"、"生成例句"、"合并到现有词条"

**新增 `ReviewDiffPanel`**

- 对比"AI 原始输出" vs "老师当前编辑"
- 对改过的行高亮，支持撤销到 AI 版本

**新增 `PreviewLessonPanel`（嵌入审校页）**

- 对当前章节用 `build_intro_lesson` 实时生成一课
- 老师可点击"试学"，在简化版 `LessonPreviewDialog` 中做一遍 showWord/translate/fillBlank
- 发现题型不合适时，可切到" lesson 模板"选择：intro / review / listening / mixed

### 3.4 导入层：更精细的合并控制

**扩展 `_import_section_dict`**

- 当前：同 id 直接走 `plan_section_merge` + `AiMergePreviewDialog`
- 新增选项：
  - `skip_existing`: 已有同 id section 时跳过
  - `force_replace`: 不预览，直接覆盖
  - `append_as_new`: 用新 id 导入为独立 section
- 这些选项在 Review 页以"导入策略"单选框呈现

**新增 `BulkImportPreviewPanel`**

- 多章节导入前一次性展示：
  - 每个 chapter 将生成哪个 section id
  - 与现有 section 的冲突关系
  - 预估新增/更新/删除的资源数量
- 老师确认后才真正执行 undo 命令

### 3.5 AI 层：与现有 AI 能力打通

**复用 `ai_prompt_library.py`**

- 把 `knowledge_prompt.py` 里的 extraction/correction prompt 迁移进 Prompt 库
- 支持按语言对（Turkish/Chinese、Spanish/English 等）加载不同 Prompt 模板

**接入 `ai_presets.py`**

- 不同教材类型（语法书、对话书、阅读材料）使用不同 preset
- preset 控制：temperature、max_tokens、策略、lesson 模板

**接入 `ai_usage.py`**

- 精确记录教材导入每步 token 消耗
- 在 UI 底部显示本章/本项目预估/实际成本

### 3.6 测试层：补齐 GUI 与集成测试

**新增 `tests/test_textbook_e2e.py`**

- 用 `pytest-qt` + 可控的 `AiRequestWorker` mock 跑完整 6 步流程
- 不依赖 offscreen 平台挂起的问题

**新增 `tests/test_textbook_project.py`**

- 覆盖项目保存/打开/继续流程

**新增 `tests/test_knowledge_merger.py`**

- 覆盖去重、与现有 course 碰撞检测

**新增 `tests/test_extraction_quality.py`**

- 覆盖质量报告计算、红黄标记规则

---

## 四、需要做的优化

### 4.1 架构优化

| 当前问题 | 优化方向 |
|---|---|
| `textbook_import_dialog.py` 550 行，UI/逻辑/状态混一起 | 拆出 `TextbookImportController`（纯逻辑）+ `TextbookImportView`（UI） |
| 知识点抽取串行，慢 | 支持章节间并发（配置化并发数，默认 1，可调到 3） |
| cancel 只中断当前 worker | 增加全局 cancel token，解析/抽取/导入全阶段可一致中止 |
| 错误信息直接 append 到 log | 结构化 `ImportStepResult`：success/warning/error + 可恢复操作建议 |

### 4.2 性能优化

- **Markdown 长文本截断**：`knowledge_extractor` 已做简单截断，但缺少按语义段落截断；改为按标题层级切块，保证每块上下文完整。
- **Review 表格大数据**：章节很多/词汇很多时 `QTableWidget` 会卡；改用 `QAbstractTableModel` + 按需加载。
- **图片/资源引用**：如果 Markdown 里有图片路径，提供预览，避免老师只看到 `[image]` 占位。

### 4.3 错误处理与可恢复性

- **解析失败**：给出"用外部工具转成 .md 再试"、"检查编码"、"查看原始字节"三个操作建议。
- **LLM 抽取失败**：
  - 第一次失败：自动重试（已有）
  - 第二次失败：进入"手动修复模式"，把原始 Markdown 和错误信息交给老师，提供"缩小范围重抽"、"仅抽词汇"、"跳过本章"三个选项
- **导入校验失败**：
  - 把 `validate_section_json` 的错误列表映射到具体行/资源
  - 在 Review 表里定位到出错词条，老师改完即可重新校验

### 4.4 UX 优化

- **步骤导航可点击**：已完成步骤允许回退修改。
- **进度估算**：抽取阶段显示"第 N/M 章，预计剩余 XX 秒"。
- **空状态优化**：没有切到章节时，提示"标题层级不足，尝试把 `#` 改成 `##`"并提供"智能升级标题"按钮。
- **导入成功反馈**：显示新增 section 在课程树中的位置，提供"定位到课程树"按钮。

### 4.5 可观测性

- 所有关键操作都走 `telemetry.record_event`：
  - `textbook.project.create`
  - `textbook.parse.success/failure`
  - `textbook.extract.chapter.success/failure/cancel`
  - `textbook.review.edit`
  - `textbook.import.section.import/merge/skip`
- 增加一个只读 `OperationsLogWidget`，显示本次会话的所有操作和耗时。

---

## 五、实施阶段建议

### Phase 1：重构与稳定（2 周）✅ 已完成

- 拆 `TextbookImportController` + `TextbookImportView`
- 引入 `ImportStepResult` 统一错误处理
- 修复 offscreen GUI 测试挂起问题
- 输出：`tests/test_textbook_e2e.py` 能跑通完整流程

### Phase 2：持久化与历史（1.5 周）✅ 已完成

- 实现 `TextbookProject` 模型和落盘
- 实现 `TextbookLibraryDialog`
- 输出：老师能关闭对话框后重新打开继续

### Phase 3：质量与审校（2 周）✅ 已完成

- 实现 `ExtractionQualityReport`（`src/backend/extraction_quality.py`）
- 重构 Review 表格为 `ResourceReviewTable`（`src/widgets/resource_review_table.py`）
- 接入 `ai_fixer` 做一键修复
- 抽取失败支持重试 / 仅抽词汇 / 跳过
- 输出：审校页有红黄质量标记、批量操作、章节级恢复按钮

### Phase 4：合并与导入策略（1.5 周）✅ 已完成

- 扩展 `_import_section_dict`
- 实现 `BulkImportPreviewPanel`
- 接入 `KnowledgeMerger`
- 输出：多章节导入前的冲突预览可用

### Phase 5：AI 能力打通与优化（2 周）✅ 已完成

- Prompt 库：`knowledge_prompt.py` 新增 `KnowledgePromptLibrary`（按语言对注册/加载模板，默认模板不变）
- 教材类型预设：`textbook_presets.py`（general/grammar/dialogue/reading，控制 temperature/strategy/max_tokens/max_chapter_chars/lesson_template）
- 接入 `ai_usage`：控制器连接 worker `usage_ready`，累积 per-chapter + 项目用量，UI 底部显示估算成本（复用 `ai_presets.PRICING`）
- 并发抽取：控制器 `max_concurrent`（默认 1，可调到 3），active-worker 池
- 语义切块：`_truncate_markdown` 按段落边界截断
- `extract_knowledge_points` 透传 `max_tokens`/`max_chapter_chars`；`build_section_from_chapter` 支持 `lesson_template`（intro/practice/review）
- 输出：不同教材类型有不同 preset，token 消耗可见

### Phase 6：收尾（1 周）✅ 已完成（测试覆盖 + 用户文档 + Review 页性能）

- 补齐测试覆盖：`test_attachment_extractor.py`（15）、`build_section_from_chapter` 的 `level` 参数、`textbook_presets` 契约断言
- 写用户操作文档 `docs/authoring/textbook-import.md`
- Review 页性能：`ResourceReviewTable._refresh_table` 不再每次 `resizeColumnsToContents`（移到 `set_rows` 一次性），50×50 全量刷新 < 0.1s；新增 `ReviewTablePerfTest`
- 代码审查 + 合并到主分支（留给用户）

**总估算：约 10 周（1 人全职）**

---

## 六、验证清单

- [x] `test_textbook_e2e.py` 完整流程通过
- [x] `test_textbook_project.py` 项目保存/继续通过
- [x] `test_knowledge_merger.py` 去重/碰撞检测通过
- [x] `test_extraction_quality.py` 质量报告通过
- [x] 关闭对话框后能重新打开项目并回到上次步骤
- [x] 50 章、每章 50 词的教材 Review 页不卡
- [x] LLM 失败时三种手动修复选项可用
- [x] 导入前冲突预览能正确显示重复 section
- [x] telemetry 事件全部按规划发出
- [x] `grep -r "import.*mineru\|magic_pdf" tool/gui/` 仍无命中（保持 AGPL 隔离）

---

## 七、风险与决策

| 风险 | 缓解措施 |
|---|---|
| GUI 测试继续挂起 | 用 `pytest-qt` + mock worker，绕过真实事件循环阻塞点 |
| LLM 输出不稳定导致审校体验差 | 引入质量评分 + 一键修复 + 手动修复模式 |
| 大量历史项目文件堆积 | 项目只存引用和提取结果，源文件仍由用户保管；提供批量清理 |
| 与现有 AI 功能代码耦合过深 | Prompt/Usage/Preset 复用，不侵入现有生成逻辑 |
| Review 页功能膨胀 | 用独立 widget 模块 + controller 分层，避免一个文件过千行 |

---

## 八、不做的边界

- **不做 OCR / MinerU 集成**：仍保持文本原生 PDF / Markdown / TXT 输入。
- **不做自动发布**：导入后仍需老师手动 `save()` 和走发布流程。
- **不做多语言自动检测**：语言对仍由老师或 preset 指定。
- **不做云端同步**：项目文件只存本地。
