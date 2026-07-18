# upgradeplus1 — tool/gui 性能优化第二阶段计划

> 承接 2026-07-18 第一轮优化（缺陷修复 A1-A12 + 性能 B1-B7 + 体积 C1-C5，
> 基线 867 passed）。第一轮明确暂缓了四个需要 UI 状态改造的项，本计划逐一落地。
> 约束不变：**不改变功能**；校验单一来源仍是 `course_cli`；每步完成跑全量回归。

## 现状基线

- 测试：`cd tool/gui && QT_QPA_PLATFORM=offscreen .venv/bin/python -m unittest discover -s tests -p "test_*.py"`
  → **867 passed, skipped=2**（见 `tests/BASELINE.md`）。
- 已有可复用设施：
  - `src/dialogs/ai/worker.py` `AiRequestWorker`：QThread 包装 + 协作式 cancel +
    **保活注册表**（`_LIVE_WORKERS`，第一轮新增）——所有异步化的统一载体。
  - `design_controller._finish_worker` 的 `worker is self._worker` 失效守卫范式。
  - `textbook_import_controller._autosave(force=...)` 节流 + `flush_autosave()`。

---

## P1 教材文件加载 / PDF 解析移 worker 线程

### 现状与证据

- `TextbookImportController.load_file`（`textbook_import_controller.py:220`）同步执行：
  `.md/.txt` 走 `path.read_text`（大文件阻塞），`.pdf` 走 `extract_attachment(path)`
  （`:246`，PyPDF2 逐页提取，几百页教材冻结 UI 数十秒）。
- 调用点：`textbook_import_dialog.py:582`（选文件）、`:139`（打开既有项目时恢复解析）。
- 当前用户体验：点击「选择教材」后 UI 假死，无进度、不可取消。

### 方案

在控制器加异步入口，**解析在 worker 线程跑，状态变更全部回到 UI 线程**：

1. `TextbookImportController.load_file_async(path, *, on_done=None) -> ImportStepResult | None`
   - 同步部分（保持原返回语义）：文件不存在 / 后缀不支持 → 立即返回 error（不进 worker）。
   - 异步部分：worker target 是纯函数 `_read_source_text(path) -> str`
     （.md/.txt read_text；.pdf 走 `extract_attachment` 提取 text），**不触碰控制器状态**。
   - `result_ready`（UI 线程）→ `_apply_loaded_text(path, text, load_id)`：
     写 `self._md` / `_split_into_chapters()` / `_emit_step` / `_autosave(force=True)`，
     与现 `load_file` 成功路径完全一致的副作用。
   - `error_occurred` → 构造与现路径相同的 recoverable `ImportStepResult.error("parse", ...)`。
2. **失效守卫**：每次发起递增 `self._load_id`；结果回调里 `load_id != self._load_id` 直接丢弃
   （用户在一次加载未完成时又选了新文件）。同时保留 worker 保活注册表的崩溃保护。
3. **Busy UI**：对话框 `_load_file` 改走异步：发起后禁用「选择文件」按钮、
   显示「解析中…（可关闭，进度已自动保存）」；完成/失败后恢复。
   打开既有项目的恢复路径（`:139`）同样走异步，避免工坊打开时卡顿。
4. 取消语义：关闭对话框/切换项目时无需主动取消（解析是纯计算、无副作用、耗时有限）；
   迟到的结果由 load_id 守卫丢弃。复用现有 `interrupt_and_save` 流程，不新增取消按钮。

### 步骤

1. 抽 `_read_source_text(path)` 纯函数（从 `load_file` 提取，行为不变），`load_file` 改调它。
2. 加 `load_file_async` + `_apply_loaded_text` + `_load_id` 守卫。
3. 对话框 `_load_file` 与项目恢复路径切换为异步 + busy 态。
4. 测试：
   - fake worker 注入（沿用 `test_textbook_controller.py` 的 `_FakeWorker` 模式）：
     异步 .md 加载成功路径、PDF 解析失败 recoverable、load_id 失效结果丢弃。
   - 现 `LoadFileTest` 全量保持绿（`load_file` 同步入口保留，供测试与简单调用）。

### 风险与缓解

- **状态线程安全**：worker target 只做文件 I/O 与文本提取，不碰 `self._chapters` 等状态；
  所有状态变更集中在 UI 线程的 `_apply_loaded_text`。这是本项的核心纪律。
- **`load_file` 同步入口被第三方调用**：保留不动，异步是新增路径，兼容。

---

## P2 词汇/语法下拉框：每视图共享模型（替代逐卡片全量填充）

### 现状与证据

- 每个 `QuestionCard` 构建时各建一个 QComboBox 并逐项 `addItem`：
  `_word_combo`（`question_cards.py:211`）遍历 `adapter.vocab_options()` 全表、
  语法下拉（`:222`）同理；`interaction_forms.py:100/104`、`sublesson_flow.py:59` 同模式。
- 规模：40 个题目 × 1000 词条 ≈ 8 万 widget item，教师视图打开与每次结构重建都付出。
  且选项列表内容对同一视图内所有下拉**完全相同**。

### 方案

**一次构建、全视图共享 QStandardItemModel**：

1. 新工具函数（`src/widgets/option_models.py`）：
   `build_options_model(options, *, placeholder) -> QStandardItemModel`
   —— 首行占位项 `(未选择)`/data=""，其后每行 label + `Qt.UserRole` 存 id。
2. 视图层（`LinearFlowWidget` / `SubLessonFlowWidget` / `InteractionForm` 的宿主）
   在一次渲染 pass 开始时各建一份 word/grammar model，传入每个卡片；
   卡片 `_word_combo` 改为 `combo.setModel(shared_model)` + 按 id 定位当前项
   （`model.match` 或一次 id→row 字典）。
3. **刷新语义**：视图在任何结构/资源变化后本就整体重建（第一轮的 refresh 链），
   model 随 pass 重建即天然同步；不引入跨 pass 的失效协议（避免缓存正确性风险）。
4. 每项当前选择是 combo 的 view 状态，共享 model 不干扰。

### 步骤

1. `option_models.py` + 单测（行数、占位项、UserRole 往返）。
2. 改 `_word_combo`/语法下拉/`interaction_forms`/`sublesson_flow` 四处接共享 model；
   保留「未选择」空行语义与 `currentData()` 取值方式不变。
3. 测试：
   - 现有 `test_question_cards.py` / `test_template_editors.py` / `test_lesson_blueprint.py` 全绿；
   - 新增：两个 combo 共享同一 model 对象；切换 vocab 后重建视图选项更新。

### 风险与缓解

- **QComboBox.setModel 共享**：Qt 允许；视图销毁不 double-free（model 由视图持有，parent 到视图）。
- **选项超万条时下拉滚动性能**：本轮不处理（搜索式下拉属新功能，列为非目标）。

---

## P3 项目库列表轻量索引（manifest）

### 现状与证据

- `TextbookProjectStore.list_projects`（`textbook_project_store.py:97`）对每个项目目录
  `load_project` → 全量 `json.loads`（含整本教材 markdown 与全部章节知识点），
  仅为渲染项目库 5 列表格（`textbook_library_dialog.py` `_refresh_list`）。
  多个数 MB 项目时，打开工坊项目库明显卡顿。
- `save_project` 已是原子写（第一轮 A8），写路径集中。

### 方案

在项目根目录维护 **`index.json` 清单**，读取零全量解析、损坏自愈：

1. 清单结构：`{"version": 1, "projects": [{project_id, name, updated_at, current_step,
   language, source_language, has_source, imported}]}`——恰好覆盖列表页展示列；
   `imported` 的取值与现列表逻辑一致（实现时以 `textbook_library_dialog` 实际读取字段为准）。
2. 写路径：`save_project` / `delete_project` 同步更新清单（沿用原子写）。
3. 读路径：新增 `list_project_summaries() -> list[ProjectSummary]`（轻 dataclass）：
   - 清单存在且 version 匹配 → 直接返回；逐条比对 `project.json` mtime，
     比清单新的项目**单独全量重载并回写清单**（外部手动改文件也能自愈）。
   - 清单缺失/损坏 → 现全量扫描一次，重建清单。
4. `textbook_library_dialog._refresh_list` 改用 summaries；`list_projects` 保留
   （先 grep 全部调用方，仅列表页迁移，其余不动）。

### 步骤

1. `ProjectSummary` dataclass + 清单读写（原子）+ 自愈逻辑。
2. 对话框迁移到 summaries。
3. 测试（并入 `test_textbook_project.py` / `test_textbook_library_dialog.py`）：
   - 首次扫描生成清单；save/delete 后清单同步；
   - 手动改 project.json 后 summaries 反映新值且清单被回写；
   - 清单损坏回退全量扫描不丢项目。

### 风险与缓解

- **清单与真值不一致**：mtime 比对 + 回写保证最终一致；清单只服务列表展示，
  打开项目仍走 `load_project` 全量加载，功能不受影响。

---

## P4 Git 操作异步化（clone / pull / commit_and_push）

### 现状与证据

- `git_library_dialog.py`：`_on_connect`（`:183` clone）、`_on_pull`（`:207`）、
  `_on_push`（`:231`）在 UI 线程 `subprocess.run` 走网络，大仓库/慢网络长时间假死。
- `GitLibrary`（`src/backend/git_library.py`）方法是同步阻塞、抛 `RuntimeError` 报错——
  签名对 worker 化友好。`_refresh_state` 里的 `status()` 是本地快操作，保持同步。

### 方案

1. 对话框加 `_run_git_async(label, fn, *args, on_ok)`：
   `AiRequestWorker(fn, *args)` + busy 态（禁用操作按钮 + 状态文案）；
   `result_ready` → 恢复按钮、`_refresh_state()`、原成功提示；
   `error_occurred` → 原 `QMessageBox.critical` 失败提示（保持现有文案）。
2. **失效守卫**：`self._git_worker` 记录当前 worker，结果回调里
   `worker is not self._git_worker` 直接丢弃（连点/重复触发保护）。
3. 关闭安全：git 子进程不可标志取消——不新增取消；对话框关闭后 worker 由保活注册表
   托底（第一轮 A2），信号随对话框销毁自动断开，结果自然落空。操作在后台完成，语义可接受。

### 步骤

1. `_run_git_async` 帮助函数 + 三处 handler 迁移（clone/pull/commit_and_push）。
2. busy 态按钮禁用/恢复。
3. 测试（`test_git_library.py` 或新增对话框测试）：
   - fake git（注入假 `GitLibrary`）：成功/失败两条路径的回调与按钮态；
   - 过期 worker 结果被丢弃。

### 风险与缓解

- **推送中途关窗**：后台完成推送——与命令行直跑一致，可接受；
  对话框级状态（`_clone_dir`）只在结果回调里写，关闭后无人读。

---

## 总验证

1. 每项完成后：全量回归保持 **867 + 新增用例全绿**，更新 `tests/BASELINE.md`。
2. 手工烟测（本机图形环境）：
   - P1：选 100+ 页 PDF，UI 可动、可关窗；解析完成进章节页。
   - P2：1000+ 词条课程打开教师视图秒开；下拉选项与当前值正确。
   - P3：10 个项目（含数 MB markdown）项目库秒开；外部改 project.json 后列表自动修正。
   - P4：慢网络下 clone/pull/push 窗口不冻结，失败弹窗文案不变。
3. `python -m compileall tool/gui/src` + 未用 import AST 扫描保持清零。

## 非目标（本轮不做）

- 保存全程异步化（B3 后保存已是亚秒级，不值得引入线程竞争）。
- 下拉框搜索式交互（新功能，非优化）。
- 聊天历史/图片附件内存上限（低概率场景，另议）。
- `teacher_view_model.py` 接入或删除（设计决策，保持现状）。
- `ai_generator.py` 请求脚手架去重（触及 AI 请求路径，风险大于收益）。
