# Phase 4：合并与导入策略（bookplan2.md）

> 目标：把教材导入从"逐 section 弹合并预览"升级为"多章节一次性冲突预览 + 可选导入策略"。
> 验收（bookplan2 §六）：`test_knowledge_merger.py` 去重/碰撞检测通过；导入前冲突预览能正确显示重复 section。

## 现状回顾

- `TextbookImportController.build_sections()` 逐章 `build_section_from_chapter` -> `sections_ready` 信号 -> `MainWindow._on_textbook_sections` 逐个调 `_import_section_dict_result(section)`。
- `_import_section_dict_result`：id 冲突时弹 `AiMergePreviewDialog`（合并），否则 `ImportAiSectionCommand`（追加）。无 skip/force/append 选项。
- `extraction_quality.py` 已能检测项目内/课程级资源重复（仅标记，不去重、不出建议）。
- 资源级去重靠 `merge_section_resources` 按 id 跳过隐式完成；section 级冲突只走 merge。

## 设计要点

1. **策略**：4 种，默认 `merge`（保持现有行为，不破坏 `_on_ai_generate`）。
   - `merge`：id 冲突 -> AiMergePreviewDialog；否则追加。
   - `skip_existing`：id 冲突 -> 跳过；否则追加。
   - `force_replace`：id 冲突 -> 用 `AiEditSectionCommand` 整体覆盖（无预览）；否则追加。
   - `append_as_new`：始终追加；id 冲突时生成唯一新 id（`{sid}-2`,`-3`…）。
2. **决策与执行分离**：把"给定冲突状态+策略应执行什么动作"抽成纯函数 `resolve_action`，可单测；app.py 只负责按动作推命令。
3. **KnowledgeMerger**：纯 Python，做 (a) 项目内全局去重（按 normalized term+translation / title key，保留首次出现），(b) 与现有课程资源碰撞检测（id 命中/内容命中），(c) section-id 冲突判定。产出结构化 `KnowledgeMergePlan`。去重在导入确认后应用。
4. **BulkImportPreviewPanel**：只读表格，展示每章 section id、状态（新建/已存在）、新增/重复资源数、按策略推导的导入动作 + 汇总。
5. **信号传递**：保持 `sections_ready = Signal(list)` 不变；策略通过 `dlg.import_strategy` 属性读取，app.py 用 lambda 捕获 `dlg` 传入 `_on_textbook_sections(sections, strategy)`。e2e 测试的 `captured.extend` 不受影响。

## 改动清单

### 新增后端

**`src/backend/import_strategy.py`**（新）
- `ImportStrategy(str, Enum)`：`MERGE="merge"` / `SKIP_EXISTING="skip_existing"` / `FORCE_REPLACE="force_replace"` / `APPEND_AS_NEW="append_as_new"`。
- `resolve_action(exists_in_course: bool, strategy: str) -> str`：返回 `"append"|"merge"|"skip"|"replace"|"append_new"`（无冲突一律 `append`）。
- `unique_section_id(adapter, base_sid: str) -> str`：`{sid}-2` 递增直到不与 `adapter.sections`/`index["sections"]` 冲突；`adapter=None` 时直接返回 `base_sid`。

**`src/backend/knowledge_merger.py`**（新）
- 复用 `extraction_quality._resource_key` 的归一化思路，本模块内实现小工具 `_normalise`/`_resource_key`（避免跨模块依赖私有符号）。
- dataclass：`ResourceCollision(chapter_index, resource_type, entry, match_kind: "id"|"key", existing_id, suggested_action: "replace"|"merge"|"keep")`；`ChapterMergeResult(chapter_index, section_id, exists_in_course, deduped: KnowledgePoints, intra_project_dropped, new_counts, duplicate_counts, collisions)`；`KnowledgeMergePlan(strategy, chapters)` + `total_new()`/`total_duplicate()`/`conflict_count()`。
- `build_merge_plan(chapters: list[tuple[Chapter, KnowledgePoints|None]], *, adapter, strategy) -> KnowledgeMergePlan`：
  - 先按 chapter 顺序扁平化所有资源 -> 项目内按 key 去重（首次保留）-> 每章得到 `deduped` + `intra_project_dropped`。
  - 与 adapter 比对：id 命中 -> `match_kind="id"`，建议 `replace`；key 命中但 id 未命中 -> `"key"`，建议 `merge`；否则为新增。
  - `section_id` 用新抽出的 `section_id_for_chapter(chapter)`，保证与 `build_section_from_chapter` 完全一致；`exists_in_course` = 该 id 是否在 adapter 中。
  - `adapter=None` 时全部视为新建、无碰撞。

**`src/backend/textbook_to_course.py`**（改）
- 抽出 `section_id_for_chapter(chapter) -> str`（`f"ch-{chapter.slug}-{chapter.idx}"`），`build_section_from_chapter` 改用它，消除 id 漂移。

### Controller（`src/dialogs/textbook_import_controller.py`，改）
- `compute_merge_plan(adapter, strategy) -> KnowledgeMergePlan`：从 kept chapters 构造 `build_merge_plan`。
- `apply_merge_plan(plan)`：把每章 `knowledge` 替换为 `plan` 中对应 `deduped`（应用项目内去重）；触发 `compute_quality_report` + autosave。

### View（`src/dialogs/textbook_import_dialog.py`，改）
- 新增 `import_strategy` 属性（默认 `ImportStrategy.MERGE.value`）。
- `_build_import_page`：增加「导入策略」`QButtonGroup`（4 个 radio，label + 说明）+ `BulkImportPreviewPanel`；radio 切换 -> 更新 `import_strategy` 并 `_refresh_import_preview`。
- `_refresh_import_preview()`：调 `controller.compute_merge_plan(self.adapter, self.import_strategy)` 填充 panel（adapter=None 安全）。
- 在 `_on_step_changed` 进入 `STEP_IMPORT` 时调用 `_refresh_import_preview`。
- `_on_import`：`apply_review_rows` -> `compute_merge_plan` -> `apply_merge_plan`（去重）-> `build_sections`（emit）。

### 新增 widget（`src/widgets/bulk_import_preview.py`，新）
- `BulkImportPreviewPanel(QWidget)`：`QTableWidget` 列 [章节, Section ID, 状态, 新增(词/表达/语法), 重复, 动作] + 汇总 QLabel；`set_plan(plan, strategy)` 渲染。动作列由 `resolve_action(exists_in_course, strategy)` 推导。只读。

### app.py（改）
- `_on_textbook_import`：`dlg.sections_ready.connect(lambda s: self._on_textbook_sections(s, dlg.import_strategy))`。
- `_on_textbook_sections(self, sections, strategy=ImportStrategy.MERGE.value)`：调 `_import_section_dict_result(section, strategy=strategy)`；counts 增加 `"replaced"`；汇总文案加"覆盖 N 个"。
- `_import_section_dict_result(self, section, *, strategy=MERGE)`：校验后用 `resolve_action(exists, strategy)` 分支：
  - `append`：`ImportAiSectionCommand`（现有）。
  - `merge`：`plan_section_merge` + `AiMergePreviewDialog`（现有；取消 -> skipped）。
  - `skip`：直接返回 `outcome="skipped"`。
  - `replace`：`AiEditSectionCommand(adapter, sid, section, resource_section=section)`。
  - `append_new`：`unique_section_id` 改写 `section["id"]` 后 `ImportAiSectionCommand`。
  - outcome 取值：`imported`/`merged`/`skipped`/`replaced`/`blocked`。
- `_import_section_dict(self, section)` 包装保持默认 `MERGE`（`_on_ai_generate` 路径不变）。

### 命令层
- 复用现有 `ImportAiSectionCommand` / `MergeAiSectionCommand` / `AiEditSectionCommand`，不新增命令。

### 测试
- **新** `tests/test_knowledge_merger.py`：项目内去重（同词跨章被去重）、id 命中碰撞（建议 replace）、key 命中碰撞（建议 merge）、`exists_in_course` 判定、new/duplicate 计数、`adapter=None` 全新建。
- **新** `tests/test_import_strategy.py`：`resolve_action` 全矩阵；`unique_section_id` 递增与 adapter=None。
- **扩** `tests/test_textbook_import_helper.py`：`skip_existing` -> skipped；`force_replace` -> replaced 且 section 被整体替换；`append_as_new` -> imported 且新 id 不冲突；无冲突时三种策略都正常 append。
- **扩** `tests/test_textbook_controller.py`：`compute_merge_plan` 返回正确 section_id/冲突；`apply_merge_plan` 后项目内重复被去重。
- **扩** `tests/test_textbook_view.py`：切换 radio 更新 `import_strategy`；用一个含冲突 section 的真 adapter 验证 panel 显示"已存在"+动作列。
- 更新 `tests/BASELINE.md`（用例数 + Phase 4 覆盖表）。
- 更新 `tool/gui/bookplan2.md`：Phase 4 ✅ + §六两条 checklist 打勾。

## 运行与验证
```bash
cd tool/gui
QT_QPA_PLATFORM=offscreen python -m pytest tests/ --ignore=tests/test_app.py -q
# 纯后端单测可无 Qt：
python -m pytest tests/test_knowledge_merger.py tests/test_import_strategy.py tests/test_textbook_controller.py -q
python3 -m unittest discover -s tests -p "test_knowledge_merger.py"  # 备用
```
- 保持 `grep -r "import.*mineru\|magic_pdf" tool/gui/` 无命中。

## 非目标（Phase 4 不做）
- 不做资源级"替换/合并"的自动落库（`merge_section_resources` 仍按 id 跳过；Merger 的建议为 advisory，Phase 5+ 再接 ai_fixer/新命令）。
- 不持久化导入策略到 project.json（每次导入现场选择；`imported_section_ids` 现有逻辑不动）。
- 不做并发抽取/语义切块（Phase 5）。
