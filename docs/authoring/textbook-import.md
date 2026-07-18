# 教材导入（Textbook Import）使用指南

> 本文件面向课程作者,说明如何用 GUI 的「导入教材」功能把一本 Markdown / 文本 PDF
> 教材半自动地转成 `assets/courses/<lang>/` 下的 section。功能规划与边界见
> [`tool/gui/bookplan2.md`](../../tool/gui/bookplan2.md);课程 JSON 契约本体见
> [`course-layout.md`](./course-layout.md),本文不重复契约。
>
> 导入是**半自动**的:LLM 抽取的知识点仅供参考,作者必须在审校页核对后才能导入。
> 所有最终产物仍是 JSON,与人工编辑等价,可被 `course_cli.py validate` + `lint` 守护。

---

## 1. 定位与边界

「导入教材」是什么:

- 一个本地 GUI 流水线,把 `.md` / `.txt` / 文本原生 `.pdf` / `.doc(x)` 教材逐章切分,
  用 LLM 抽取词汇 / 表达 / 语法点,作者审校后生成可导入的 section。
- 产物落到 `assets/courses/<lang>/` 的 JSON,与人工编辑完全等价;导入走 undo 命令栈,
  作者仍需手动 `save()` 走发布流程。

明确**不做**(对齐 bookplan2 §八):

| 禁止 | 原因 |
|------|------|
| OCR / MinerU / 扫描件识别 | 保持 AGPL 隔离;只支持文本原生 PDF |
| 自动发布 | 导入后仍需作者手动保存 + 走 `course_cli` 发布 |
| 多语言自动检测 | 语言对由作者或教材类型预设指定 |
| 云端同步 | 项目文件只存本地 `tool/gui/var/textbooks/` |

一句话:**导入产出的 JSON 必须能被 `course_cli.py validate` + `lint` 通过,否则作者应回审校页修正。**

---

## 2. 支持的输入

| 类型 | 扩展名 | 说明 |
|------|--------|------|
| Markdown / 纯文本 | `.md` `.txt` `.csv` `.json` 等 | UTF-8 文本,按 `#{1..3}` 标题切章 |
| PDF | `.pdf` | **文本原生**;扫描件/图片 PDF 会被降级提示「未提取到文本」 |
| Word | `.doc` `.docx` | 需 `pip install python-docx`;缺失则给出依赖提示 |
| 图片 | `.png` `.jpg` `.jpeg` `.gif` `.webp` | 转 base64 `image_url`(供 AI 对话附件) |

文本读取与降级由 [`attachment_extractor.extract_attachment`](../../tool/gui/src/backend/attachment_extractor.py)
统一处理;Markdown 切章由 [`markdown_chopper.split_chapters`](../../tool/gui/src/backend/markdown_chopper.py)
按 `##`(默认 `min_level=2`)切分。

---

## 3. 三阶段流程

入口：工具栏「**课程工坊**」（唯一入口，merge overhaul 起）：非 modal 工作台，项目库与
导入流水线同窗，六阶段（项目/素材/知识/设计/审校/导入）侧栏导航可点击回跳；
全程自动保存，随时关闭可续作（重开自动回到上次项目与阶段）。
旧的「导入教材(Beta)」modal 入口已移除，教材导入即工坊的素材→知识→导入阶段。

（页面历经两次重组：「② 解析课本」独立页面已移除，解析预览并入素材页；随后素材（选文件+章节勾选）、
知识（提取日志+审校）、导入三页定型。）

| 阶段 | 操作 | 关键代码 |
|------|------|----------|
| ① 素材 | 拖入/选择文件，内联预览前 2000 字；勾选章节，选**教材类型**与**并发数** | `TextbookImportController.load_file` + `set_chapter_kept` + `textbook_presets` |
| ② 知识 | 上半提取日志（用量/成本），下半审校：红黄质量标记、批量删、AI 修复、重试/仅抽词汇/跳过 | `knowledge_extractor.extract_knowledge_points` + `ResourceReviewTable` + `extraction_quality` |
| ③ 导入 | 选**导入策略**，预览冲突，确认导入 | `BulkImportPreviewPanel` + `SectionImportService` |

关闭对话框后,项目自动保存到 `tool/gui/var/textbooks/{project_id}/project.json`（v2 格式，
含 resource_pool 快照与 import_map），可从「项目库」页重新打开继续(见 §8)。

---

## 3.1 设计阶段（课程工坊专属，Phase 3）

知识页点「**AI 设计课程 →**」进入设计阶段：AI 以**资源池为词表**（grounded）编排课程——
从池中按原 id 选词复制进 section，只负责单元/课时/模板/题目编排，不凭空造词
（确需池外新词会打 `"new"` tag；资源池为空时退回自由生成）。

- 左栏：主题/级别/单元数/模板/编排意图 + 许愿式对话（可多轮讨论后再「生成课程 ▶」）。
- 右栏：草稿 JSON（可手改，导入以编辑器内容为准）+ 校验/试做/导入到课程。
- 草稿、对话记录、参数全部持久化在项目 `design` 字段，关窗重开完整恢复。
- 知识页改动资源池后再回设计页，会提示"资源池已更新，建议重新生成"。
- 导入走与教材导入相同的 `SectionImportService` 管线（合并/冲突处理一致）。

关键代码：`src/dialogs/ai/design_controller.py`（纯逻辑）+ `src/dialogs/ai/design_panel.py`（视图）。

---

## 4. 导入策略(③)

当某章生成的 section id 已存在于当前课程时,策略决定如何处理:

| 策略 | 行为 | 适用场景 |
|------|------|----------|
| 合并预览(默认) | 单章冲突弹 `AiMergePreviewDialog` 逐项勾选;**多章冲突弹一次 `BulkMergeResolveDialog` 批量决策**（逐行 合并/跳过/细看） | 重新导入同一教材、想保留已有改动 |
| 跳过已存在 | 直接跳过该章,保留现有 section | 只想补新章节 |
| 覆盖已存在 | 用 `AiEditSectionCommand` 整体覆盖(无预览) | 确定要替换旧内容 |
| 作为新 section 追加 | 自动改 id(`{id}-2`...)导入为独立 section | 想并存新旧两版 |

策略由 [`import_strategy.ImportStrategy`](../../tool/gui/src/backend/import_strategy.py)
定义;执行走 [`SectionImportService`](../../tool/gui/src/application/section_import_service.py)
（自 `app.py` 抽出,AI 生成/教材导入/课程工坊共用）,
默认 `merge` 以保持 AI 生成器既有行为。预览面板(`BulkImportPreviewPanel`)展示每章将
生成的 section id、动作、新增/重复资源数与冲突。

---

## 5. 教材类型预设(①)

不同教材内容类型用不同抽取参数。预设由
[`textbook_presets.BUILTIN_TEXTBOOK_PRESETS`](../../tool/gui/src/backend/textbook_presets.py)
定义:

| 预设 | temperature | strategy | max_chapter_chars | lesson_template | 适用 |
|------|-------------|----------|-------------------|-----------------|------|
| general(通用) | 0.3 | standard | 8000 | intro | 大多数课本,均衡抽取 |
| grammar(语法书) | 0.15 | standard | 8000 | intro | 侧重语法点,规则更确定 |
| dialogue(对话书) | 0.5 | standard | 8000 | intro | 侧重日常表达与口语 |
| reading(阅读材料) | 0.3 | vocab_only | 10000 | intro | 仅抽词汇,忽略隐式语法 |

预设控制 `extract_knowledge_points` 的 `temperature` / `strategy` / `max_tokens` /
`max_chapter_chars`,以及 `build_section_from_chapter` 的 `lesson_template`
(目前仅 `intro` 有意义;`practice`/`review` 亦可,未知值回退 `intro`)。

---

## 6. 知识点去重与合并

LLM 抽取时每章用独立 id 前缀 `ch-{slug}-`,因此**同一术语在两章会得到不同 id**。
若直接导入,`merge_section_resources`(按 id 去重)会把它当成两个词,造成重复词条。

[`knowledge_merger`](../../tool/gui/src/backend/knowledge_merger.py) 在导入前自动处理:

- **项目内重复**:跨章同 key(term+translation,或语法点 title)的条目,把后续出现的
  id 改写为首次出现的 id → 全局只入一次。
- **与现有课程碰撞**:项目条目 key 已存在于课程词库时,把项目条目 id 对齐到课程已有
  id → `merge_section_resources` 跳过,不产生重复。

该过程幂等;预览面板的「重复」列即来自 `knowledge_merger.analyze`(只读)。

---

## 7. 用量与成本

抽取阶段每章 LLM 调用的 token 用量会被累积,对话框底部显示**项目总量**:

```
项目用量:≈ 12.3k tokens · ¥0.04(估算)
```

成本基于 [`ai_presets.PRICING`](../../tool/gui/src/backend/ai_presets.py) 本地价目表
**估算**,非账单来源;未知/本地模型(如 Ollama)只显示 token,不显示误导性价格。
格式化由 [`ai_usage.format_usage_line`](../../tool/gui/src/backend/ai_usage.py) 生成。

---

## 8. 项目持久化

每个导入会话是一个 `TextbookProject`,落盘到
`tool/gui/var/textbooks/{project_id}/project.json`,只存引用与抽取结果(不存源文件本体)。
状态标签:已解析 / 已抽取 / 已审校 / 已导入。

打开「导入教材」时先弹「教材库」对话框([`TextbookLibraryDialog`](../../tool/gui/src/dialogs/textbook_library_dialog.py)),
列出历史项目;双击可回到上次步骤继续。源文件仍由作者保管;若源文件路径变化,
[`TextbookProject.source_changed`](../../tool/gui/src/backend/textbook_project.py) 会提示。

---

## 9. 常见问题

| 问题 | 解决 |
|------|------|
| 解析后「未切到章节」 | 标题层级不足;把 `#` 改成 `##`(`min_level=2`) |
| PDF 提示「未提取到文本」 | 多为扫描件;用外部工具转成 `.md` 再导入 |
| 某章 LLM 抽取失败 | 审校页选「重试本章」→ 仍失败选「仅抽词汇」→ 或「跳过本章」 |
| 导入预览显示 section id 冲突 | 选「作为新 section 追加」会自动改 id,或「跳过已存在」 |
| 审校页红/黄标记 | 红色=错误(如 term 为空),黄色=警告(如与现有课程重复);可选中行点「AI 修复」 |
| 大教材(50+ 章)抽取慢 | ② 步把「并发」调到 2–3(默认 1 串行);token 并发消耗会升高 |

---

## 10. 相关文件

| 文件 | 作用 |
|------|------|
| `tool/gui/src/dialogs/workshop_window.py` | 课程工坊（非 modal 工作台，阶段导航可点击） |
| `tool/gui/src/dialogs/textbook_import_dialog.py` | 3 页流水线视图（素材/知识/导入）+ 策略/预设/用量接线 |
| `tool/gui/src/dialogs/textbook_import_controller.py` | 纯 Python 流水线控制器(并发/用量/预览) |
| `tool/gui/src/application/section_import_service.py` | 共享导入执行管线（单条+批量,UI 回调注入） |
| `tool/gui/src/widgets/bulk_merge_resolve_panel.py` | 多章冲突一次性批量合并决策 |
| `tool/gui/src/backend/knowledge_extractor.py` | 逐章 LLM 抽取 + 重试 |
| `tool/gui/src/backend/knowledge_prompt.py` | 抽取 prompt + 按语言对模板库（可持久化覆盖） + 段落截断 |
| `tool/gui/src/backend/knowledge_merger.py` | 项目内去重 + 课程碰撞对齐 |
| `tool/gui/src/backend/import_strategy.py` | 导入策略 + 批量导入规划 |
| `tool/gui/src/backend/textbook_presets.py` | 教材类型预设 |
| `tool/gui/src/backend/extraction_quality.py` | 质量评分(coverage/duplicate/consistency/lang) |
| `tool/gui/src/widgets/resource_review_table.py` | 审校表(搜索/过滤/批量/AI 修复) |
| `tool/gui/src/widgets/bulk_import_preview_panel.py` | 导入前冲突预览 |
| `tool/gui/bookplan2.md` | 功能规划与阶段记录 |