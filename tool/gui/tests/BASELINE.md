# GUI Python 测试基线

> 记录 `tool/gui/tests/` 下的用例数与关键覆盖项，便于每轮变更后快速对比回归。
>
> **本文件的结构**：顶部「当前基线」是唯一权威的当前数字，**只增不删**（按日期倒序追加）；
> 其余条目是历史施工流水的**数值索引**，其中的数字反映当时的快照。
> 查当前值请只看顶部，不要翻历史条目。

## 当前基线

- **2026-10-30（教材/纲领适配 + MiniMax TTS 参数 + AI 模型名对齐）**：
  **209 模块 / 2977 例**（发现器 `countTestCases`；上一条目 206 / 2925，+3 模块 +52 例 =
  `test_markdown_auto_split` 16 + `test_document_profile` 10 + `test_syllabus_brief` 18 +
  既有模块新增 8）。
  - 新增 `backend/document_profile.py`（文档类型启发式 + 可选 AI 复核）、
    `backend/syllabus_brief.py`（纲领 → CoursePlanSpec 取值）、
    `application/audio_options.py`（UI 侧 TTS 选项表，避免 dialogs 直连 backend）；
    `markdown_chopper` 增 `split_chapters_auto` / `heading_style` / `plain_unit_titles`。
  - 导入管线改为自动切章（编号 / `Ünite` 单元词 / 加粗行 / 单 `#` 书名 + 阶梯），
    载入后自动识别文档类型并在教师未手动选预设时切换（置信度 ≥ 0.45），
    新 `syllabus` 预设带 `prompt_addendum`（纲领专用抽取规则）。
  - 规划窗口新增「载入教学纲领…」：`.md/.txt/.pdf/.docx` → 主题/等级/章节/课时/词预算/
    can-do/约束；AI 失败回落启发式；单元数是 `section_count` 的权威。
  - MiniMax：`language_boost`（按课程语言推导，默认 Turkish）、`text_normalization_mode`
    （默认 quality）、`emotion`、`sample_rate`/`bitrate`、模型白名单；GUI 音色表补多语音色。
  - AI 模型名与 App 同源：DeepSeek `deepseek-v4.1-flash|pro`、MiMo `mimo-v2.6-pro|v2.6`；
    旧 id/provider 走迁移表（转 custom + 保留 Base URL）。
  - 顺手修好两条既有门禁红项：`course_plan_window` 的两处 `QMessageBox.question` 改走
    `ui_guard.safe_question`；`course_health_panel` 两处 lambda 槽改具名方法
    （`test_ui_guard` / `test_signal_lifecycle` 恢复绿）。
  - 门禁：`app_dialogs` 13、`broad_except` 873、`widgets_dialogs` 4 未变；
    **`ui_backend` 166 → 167 已重钉**（`tool/guard_limits.json`）：唯一新增是
    `dialogs/textbook_import_controller.py` 直接 import `backend/document_profile`
    —— 与该文件已有的 `textbook_presets` / `knowledge_extractor` 同型，
    不额外造 application 包装层。重钉理由记在此处，数字只此一处可改。

- **2026-10-21（P0-2 / P0-3 整门课程大纲 + 逐节生成导入）**：
  **206 模块 / 2925 例**（发现器 `countTestCases`；上一条目 205 / 2896，+1 模块 +29 例 =
  `test_course_plan` 29 例）。
  - 新增 `backend/ai/course_plan.py`（规划 prompt / 本地归一化 / 结构校验 / 逐节 spec 映射）、
    `backend/course_plan_store.py`（`tool/var/course_plans` 原子写 + `drafts/`）、
    `application/course_plan_service.py`、`application/course_plan_controller.py`、
    `widgets/course_plan_window.py`。
  - 应用菜单「整门课程规划…」：表单 → LLM 大纲 → 双 tab 审阅（大纲 / 全局词表）→ 保存。
    section 与词 id 全部本地确定性分配；新词唯一、复习词只允许来自前面章节；
    校验失败回灌错误重试一次。大纲不写课程 JSON。
  - 逐节生成：`plan_section_to_spec` 注入 grounded pool + 前序 `course_resources`，
    走 `facade.generate_course`；草稿存 `drafts/<section_id>.json`；支持 token 预算、
    自动连续下一节、草稿 JSON 预览。
  - 导入：`SectionImportService.import_section(strategy=append_as_new)`，id 冲突自动改写；
    保留校验 / 合并预览 / Undo；导入后仍需保存课程。
  - 门禁：`app_dialogs` 13、`ui_backend` 166、`broad_except` 873 均未变
    （窗口放 `widgets/` 而非 `dialogs/`，UI 经 application service 取数）。

- **2026-10-21（P0-1 课程体检）**：
  **205 模块 / 2896 例**（发现器 `countTestCases`；上一条目 204 / 2885，+1 模块 +11 例 =
  `test_course_health` 11 例）。
  - 新增 `backend/course_health.py`（Finding / RepairStep / audit / plan，Qt-free）、
    `application/course_health_service.py`（UI 与 backend 的接缝）、
    `widgets/course_health_panel.py`（总览内嵌只读面板）。
  - 总览头部新增「课程体检」：扫描空课、词汇螺旋、阅读/听力缺口、低质节、语法覆盖、
    前置依赖与资源冲突，输出按「结构 → 听力 → 质量 → 资源」排序的修复工作单。
    执行仍走既有 `dispatch_experience_action`，每条动作保留自己的预览/确认/Undo。
  - 门禁：`app_dialogs` 13 未变（做成面板而非新对话框，避免棘轮 +1）；
    `ui_backend` 166 未变（面板只 import application 服务）；`broad_except` 873 未变
    （新增捕获均为 `_DATA_ERRORS` / `_UI_ERRORS` 窄类型，不计宽泛捕获）。

- **2026-10-20（tool/gui 全量改进：门禁修复 + 运行时阻塞 + 功能空洞接线）**：
  按当轮审查结论逐项施工（该评审文档已随仓库文档精简删除，见 Git 历史）。
  **204 模块 / 2885 例**（发现器 `countTestCases`；上一条目 201 / 2875，+3 模块 +10 例 =
  `test_theme_parity` 3 例、`test_icon_names` 2 例、`test_ai_request_worker_keepalive` 3 例、
  `test_shell_views` 的 Ctrl+F 两条）。`full` **204/204**（110.7 s）。

  **门禁修复**：
  - `ui_backend` 171 → **166**（基线同步下调）：新增 `application/media_service.py` 与
    `application/delivery_service.py` 两个门面，UI 层不再直连 `backend.course_media` /
    `backend.course_delivery`。
  - `import_cycles` 2 → **0**（基线同步下调）：两处模块级环用 PEP 562 惰性再导出断开
    （`backend/experience/suggestions/__init__.py` 导出 `local_suggestions`、
    `dialogs/git_library/__init__.py` 导出 `GitLibraryDialog`）。
  - **新增两条棘轮**并写进 `guard_limits.json`：`max_app_dialogs_imports: 13`
    （application→dialogs 已知债务，此前只有零容忍形态且三处门禁都没启用，等于无上限）、
    `max_widgets_dialogs_imports: 4`（widgets→dialogs 反向耦合，此前完全无门禁）。
    契约 §10 / §15 已同步说明。
  - `broad_except` 854 → **873**（基线同步上调）：**20 处完全静默的宽泛捕获全部补了
    `logger.debug(..., exc_info=True)`**，静默吞异常归零。

  **运行时阻塞修复**：
  - `ai_request_worker._LIVE_WORKERS` 泄漏：两个 hub 的 disconnect 列表原本含 `finished`
    （= 保活释放所挂的信号）→ worker 永久滞留。改为**不断开 `finished`**，
    并加 `AiRequestWorker._sweep_finished_workers()` 兜底清扫。
  - `close_controller` 关闭路径**同步保存** → 改异步（`_start_close_save`，
    保存完成后 `host.close()` 自行关窗；保存中二次关闭被拒绝并提示）。
  - `close_controller` 关闭时**只 join 了 1 个 worker** → 新增
    `_cancel_in_flight_workers()`，对共享清单 `IN_FLIGHT_WORKER_ATTRS`（9 个）
    逐个 cancel + 有界 wait(2000)。
  - `audio_controller` 的**同步 `adapter.save()`** → 改走 worker，保存成功后才启动 TTS。
  - `telemetry.usage_summary()` **每次全量重解析日志** → 改增量（inode + 字节偏移游标，
    跨 UTC 日或文件轮转时重算）；`sync_usage_today` 加 30 s 节流（节流状态挂在 host 上，
    策略检查路径走 `force=True`）；日志加体积上限（8 MB × 3 备份）。
  - 附件提取**在 GUI 线程做 PDF 全文提取 + base64** → 新增
    `application/attachment_service.py`，`design_panel` 与 `generator_chat_coordinator` 改走 worker。
  - `_QUALITY_CACHE`（`context_bus.py`）**无上限模块级 dict** → 改 LRU（上限 256），
    并在 `clear_experience_session` 里清。

  **功能空洞接线**（backlog 第 6/8/9/11/12/14 条）：
  - 第 6 条 教材提取自动保存失败**静默** → controller 加 `on_status` 回调，
    dialog 侧接状态灯与日志。
  - 第 8 条 ExperienceTimeline **整链未接**（Dock「最近」恒空、⌘K 历史重放恒空）→
    MainWindow 实例化 timeline，`record_experience_event` 写入并刷新 Dock，
    `timeline_clicked` 接上派发。
  - 第 9 条 AuthorMemory **写入零调用**、ProjectMemory **只写不读** →
    课程加载记语言偏好、chip 改题记作者风格、命令面板显示「常用」技能行。
  - 第 11 条 `experience_defer_json` / `experience_save_brief` **Settings 无字段**
    → 永不落盘、功能恒关。补齐字段 + 存/取。
  - 第 12 条 死代码批次：删 `save_host.run_async_direct_save`、
    `ai_runtime.empty_ai_runtime`、`goal_controller.run_sandbox_for_host`、
    `shell_views.current_view`、`course_media.media_ref_for_filename`、
    `goal_generate.extract_lesson_from_section`，以及三个零引用的模块。

### 棘轮基线（与 `tool/gui/tool/guard_limits.json` 一致）

| 指标 | `guard_limits.json` 键 | 当前基线 | 语义 |
|---|---|---|---|
| 静默 `except: pass` | `max_except_pass` | **0** | 只减不增 |
| 静默 `except: continue` | `max_except_continue` | **0** | 只减不增 |
| 宽泛 except | `max_broad_except` | **873** | 只减不增 |
| 内联硬编码 hex | `max_hardcoded_style_hex` | **0** | 只减不增 |
| UI → backend 导入语句 | `max_ui_backend_imports` | **166** | 只减不增 |
| 模块级 import 环 | `max_import_cycles` | **0** | 只减不增 |
| application → dialogs | `max_app_dialogs_imports` | **13** | 只减不增 |
| widgets → dialogs | `max_widgets_dialogs_imports` | **4** | 只减不增 |

### 用例数基线

| 批次 | 模块 | 例数 |
|---|---|---|
| 2026-10-20（当前） | **204** | **2885** |
| 上一条目（2026-10-20） | 201 | 2875 |
| 2026-09-28 施工质量复审返工 | 200 | 2860 |
| 2026-09-28 逻辑审查修复计划 | 200 | 2858 |
| 2026-09-28 审计遗留收口 | 199 | 2851 |
| 2026-09-28 批次四 | 199 | 2806 |
| 2026-09-28 批次三 | 195 | 2724 |
| 2026-09-28 批次二 | 193 | 2673 |
| 2026-09-28 批次一 | 192 | 2654 |
| 2026-09-28 工坊重设计验货 | 192 | 2633 |
| 2026-09-27 工坊重设计收口 | 192 | 2628 |
| 2026-09-27 AI 遗留退役 | 191 | — |
| 2026-09-27 整改批次 | 191 | 2555 |
| 2026-09-22（只清 lint） | — | 2541 |
| 2026-09-20 P1 Toast 批次 1 | — | 2541 |
| 2026-09-20 P0 异步批次 | — | 2537 |
| 2026-09-19 编辑视图减负 | — | 2531 |
| 2026-09-19 小屏适配 | — | 2521 |
| 2026-09-19 WheelGuard | — | 2514 |
| 2026-09-19 设置对话框重构 | — | 2508 |
| 2026-09-19 GUI 焕新 W1–W3 | — | 2505 |
| 2026-09 改良清单施工 | — | 2382 |
| 2026-09-08 测试去重第四轮 | — | 2371 |
| 2026-09-07 噱头清理第三步 | — | 2499 |
| 2026-09-07 噱头清理第二步 | — | 2481 |
| 2026-09-07 噱头清理第一步 | — | 2485 |
| 2026-09-06 测试去重第一步 | — | 2520 |
| 2026-09-06 测试去重第二步 | — | 2492 |
| 2026-08-05 之前 | — | 1276（skipped=2） |

---

## 历史条目（数值索引）

按日期倒序。每条只记该批次的**数值事实**；过程叙述见 git 历史。

- **2026-10-20（上一条目）**：**201 模块 / 2875 例**（上一条目 200 / 2860，+15）；`ci`（L0+L1）48 模块全过；新模块因课程读写链碰到 Qt，留在 L2，随 `full` 一起跑绿。
- **2026-09-28（施工质量复审返工：三路独立审查 33 项发现全部处置，200 模块全绿）**：1 项 P1、8 项 P2、十余项 P3 全部处置。**200 模块 / 2860 例**；`full` 200/200（93.2 s）；ruff 全过；guard 全链 exit 0 且计数零漂移（broad_except=854 / ui_backend=168）。
- **2026-09-28（逻辑审查修复计划施工：批次 A/B 全量 + C/D/E 主体）**：按仓库外《Turna GUI 逻辑审查与修复计划（2026-09-28）》施工。**200 模块 / 2858 例**；`full` **200/200 全过**（83.8 s，含新增回归模块 `test_logic_review_2026_09_28` 7 例）；ruff 全过；`make guard-gui` 全链 exit 0。broad_except 重钉 **854**（846 + 本轮防御式兜底净增），ui_backend 168 不变；`count_broad_except` 复用 `_is_broad_except`（`linkedGrammarPointIds` 对齐 overview_stats）；回归测试 7 例。
- **2026-09-28（审计遗留三项的收口批次）**：**199 模块 / 2851 例**（较上轮 2841 ⇒ **+10**）；`full` **198/198 全过**；ruff 全过；L0 gate 5/5 exit 0。同口径复核批次前基线 `eb99db50`：broad_except=812 / ui_backend=163 / host_drift=8 / except_pass=9。host_drift 4 → **0**；except_pass 3 → **0**。批次自身引入的 `host._open_worker` / `host._last_saved_at` 纳入协议；`main_window_shell.cancel_in_flight_ai_jobs` 与 `publish_dialog._restore_version_snapshot` 两处补日志。
- **2026-09-28（批次四）**：`python -m unittest` 逐模块收集 **199 模块 / 2806 例 / 0 失败**（上批 2724 例 ⇒ **+34**，无新增模块）。broad_except **846 > 816**（净增 +34，分散 20 个文件，前三：course_lifecycle +8）；ui_backend **168 > 163**（净增 +5：experience_tab 重置熔断器、vocab_table 等）。
- **2026-09-28（批次三）**：**195 模块 / 2724 例 / 0 失败**（上批 2673 例）；ruff 全过；L0 gate **5/5 exit 0**。依据 `Turna_GUI_修复计划_2026-09-28` 批次三，18 条全部修复并按问题新增 3 例。
- **2026-09-28（批次二）**：**193 模块 / 2673 例 / 0 失败**（上批 2654 例）；ruff 全过；L0 gate **5/5 exit 0**。新增 `test_auto_apply_scope.py` 9 例（严格/offer 双解析、消费解绑、auto 无模态、文案）。
- **2026-09-28（GUI 易用性修复 批次一）**：**192 模块 / 2654 例 / 0 失败**（上批 2633 例 ⇒ **+21**）。`full` **192/192，74 s**；`ruff` 全过；L0 gate（E1+E2 冒烟）**5/5 exit 0**。依据 `Turna_GUI_修复计划_2026-09-28`（37 条）做批次一。
- **2026-09-28（工坊重设计验货修复批：T4 折叠失效 + 摘页空白回归）**：**192 模块 / 2633 例 / 0 加载错误**（上批 2628 例 ⇒ **+5**）。`full` **192/192，78 s**；`affected` 24/24；`ruff` 全过；边界门禁 **exit 0**（计数不变）。新增回归断言 `test_ripped_pages_are_not_explicitly_hidden`、`test_collapsed_groups_actually_fold`、`test_window_can_hold_the_980x640_default`、`test_draft_chat_is_the_growing_surface`（760 高时聊天 > 两个折叠组之和且 > 150 px）。窗口地板 777×1016 → **888×618**，`resize(980,640)` 生效。
- **2026-09-27（工坊重设计收口：§5 快赢 + T1–T5 全部落地）**：**192 模块 / 2628 例 / 0 加载错误**（上批 2573 例 ⇒ **+55**）。`full` **192/192，77 s**；`gate` 33/33 + E2 5/5；`ruff` 全过；边界门禁 **exit 0**。边界门禁计数收口：`broad_except` 816 → **810**，`app_dialogs=13` / `cycles=2` / `ui_backend=163` / `host_drift=0` 其余不变。新增 `tests/test_ai_orbit.py`（16 例）与 `tests/test_workshop_canvas.py`（26 例，替换 `test_unified_workspace.py` 的 14 例）。窗口新壳 **1100×720 → 980×640**；大纲树 220→400、摘要 140→220。
- **2026-09-27（tool/gui 侧 AI 遗留退役）**：删除 `src/backend/experience/json_path_skill.py`（417 行）+ `tests/test_json_path_skill.py`（134 行 / 5 例）⇒ **192 → 191 模块**；连带 `broad_except` **816 → 811**（被删模块含 5 处宽泛 except），其余计数器不变（`app_dialogs=13` / `cycles=2` / `ui_backend=163`）。backend 15 个 `ai_*` 模块 + `ai/` 子包全部在役，不动。退役记录见 `docs/ai_refactor_contract.md` §18。
- **2026-09-27（右键菜单泄漏 + Ctrl+D 歧义）**：`test_course_tree` 33 → **39 例**（+6，`CourseTreeContextMenuLeakTest`）。
- **2026-09-27（核查补批）**：`python -m unittest` 收集 **192 模块 / 2573 例 / 0 加载错误**。分档实测：L1 pure **49**（+1）；`full` **192/192，~75 s**（`-j 4`）。新增 `tests/test_check_ai_boundaries.py`（18 例）：对 `check_ai_boundaries.py` 全部 11 条门禁规则逐条注入探针的负向矩阵。
- **2026-09-27（整改批次）**：`python -m unittest` 收集 **191 模块 / 2555 例 / 0 加载错误**。分档实测：`ci`（L0 gate + L1 fast）**48/48，~11 s**；`full` **191/191，~73 s**（`-j 4`）。较 2026-09-22 的 2541 净增 14 例：新增 `tests/test_error_report_redaction.py`（7 例）、`tests/test_git_secret_redaction.py`（7 例）；`test_user_action_filter.UserActionFilterTest` 由 3 例扩到 7 例。同期修复两个**整模块挂起**的模块：`test_shell_views`（41 例 / 19.9 s）、`test_app`（41 例 / 36.6 s）—— 根因与修复见 `docs/ai_refactor_contract.md` §14。`ci` 档的 L1 集合由 113 个模块**修正为 48 个**（修正 65 个假阳性，0 误伤）。`-j/--jobs` 默认由 1 改为 0（=自动并行）。
- **2026-09-22**：`ruff check tool/gui`（src + tests）为 0，已接入 `make lint-gui` 与 CI。用例数为 **2541**（该批只清 lint，不增删测试）。
- **2026-09-20 P1 Toast 批次 1（确认类模态框 → Toast，28 处）**：用例数 2537 → 2541（+4，`test_shell_views.NotifyToastResolutionTest`）；ruff 7 文件归零。动机：141 处 `QMessageBox.information/warning`（不含 question）里约一半是单行结果告知。存量未迁移模态（含 question）共 **185 处** grep 计数（information/warning/critical **142** 含 **28** 处 toast-fallback 行，纯模态 **114** + question **43**）。ToastHost 三级 host 解析（显式属性 / 经 `window()` 上溯 / 可见独立窗口懒建）；severity 约定：完成类=success、指引/空结果=info、警示=warning（duration 6000ms）。
- **2026-09-20 P0 异步批次（发布对话框 + 总览校验移出 UI 线程）**：用例数 2531 → 2537（+6：`test_publish_dialog` 新增 `PublishDialogAsyncTest` 3 例，`test_course_overview` 新增异步校验 3 例）。受影响 4 模块逐进程全绿（`test_publish_dialog` 7 / `test_course_overview` 15 / `test_resources_controller`+`test_shell_views` 合并进程 56）；ruff 4 文件归零；顺带清掉 `test_course_overview` 既有 E741×2（tests 历史债 **141→139**）。全量用例（上次记录）2499 collected；已知基线问题 `test_textbook_controller.LoadFileAsyncTest.test_stale_load_result_is_ignored`（单跑与模块级均通过）。命令：`QT_QPA_PLATFORM=offscreen python -m unittest discover -s tests -p "test_*.py"`。记录勘误 ×2：① 2026-09-07 基线头所写「2 个 defer_resurface 永久 skip」经核实不存在；② 2026-09-06 adversarial 瘦身条目所写「保留 10 例独有覆盖」中 D14×4 与 D27 共 5 例与常规测试重复，已删除。
- **2026-09-19 编辑视图减负（属性折叠 + 分段视图切换）**：用例数 2521 → 2531（+5，`test_w3_editor` 新增 `DetailPanelW4CollapseTest` 5 例）；受影响 8 模块逐进程全绿；`ci` 层 1436/1436。
- **2026-09-19 小屏适配（FlowLayout + 屏幕钳制 + 按钮防裁）**：用例数 2514 → 2521（+7，`test_ui_fit.py` 新建：FlowLayout 2 / ScreenClamp 3 / 对话框最小宽回归 2）；受影响 5 模块 + `test_operations_log` 共 88 例全绿；`ci` 层 1436/1436；offscreen 800×800 探针。`textbook_library_dialog` 最小宽 844→232；设置对话框最小宽 894→540；1180×860 窗 Show 后被钳到 796×796。
- **2026-09-19 全局禁用滚轮调参（WheelGuard）**：用例数 2508 → 2514（+6，`test_wheel_guard.py` 新建，L2 重 Qt 模块）；模块 6/6 绿；`ci` 层 1436/1436；ruff 新文件归零。
- **2026-09-19 设置对话框重构（左导航两栏 + 全页滚动）**：用例数 2505 → 2508（+3，`test_settings_dialog.py` 13→16：新增 `SettingsNavLayoutTest` 3 例）；`affected` 1 模块 16/16 绿；`ci` 层 1436/1436 绿；L2 `tests.test_app` 绿。
- **2026-09-19 GUI 焕新 W1–W3（壳层多视图 + 图标系统 + 编辑视图深化）**：用例数 2382 → 2505（+123，其中焕新三波 +101：`test_ui_kit` 27 / `test_shell_views` 37（含 `ActivityBadgeTest` 7）/ `test_w3_editor` 37）。提交 `04ca6d2e`（[gui-w1]）→ `0b2d6191`（[gui-w2][gui-w3]）→ `e0c632f2`（lint 清扫）。验证：`run_gui_tests.py ci`（E1 gate 33/33 + E2 gate 5/5 + L1 fast 113/113）；受影响模块 `test_shell_views`+`test_memory_wiring`+`test_textbook_skill` 55 例全绿。遗留：`tests/` 存量 **141 处**历史 lint 未清；W4/W5 未开工。
- **2026-09 改良清单施工（半成品接线 + 工程化落地）**：用例数 2371 → 2382（+11，`test_memory_wiring.py` 新建）。验证：定向模块 66+147 例全绿；**287 模块** walk_packages 导入零失败；`check_ai_boundaries` host_drift=0、style_hex=0；`ruff check src/` 由 **3778** 降至 **94**（余为 E741/SIM102/F841 等需人工项）。内联 hex 样式清零（P1-7）**29 处**审计项全清，`style_hex=0`。`--fix` 清理 304 处；存量 94 项需人工判断。
- **2026-09-08 测试去重第四轮（死链清理 + 恒真断言 + 重复对）**：用例数 2499 → 2371（**-128**；死代码陪跑 -104、恒真/回声断言 -13、重复对 -11）。删 11 个测试文件约 1300 行 + 2 个死 src 模块。验证：`run_gui_tests.py ci`（E1+E2 gate 5/5 + L1 fast 111 纯模块 **1420 例** 0 失败）；L2 qtish **71 模块** 4 路并行（`run_modules_parallel`）**95s** 全绿（`test_app` 94s 为最长尾）。矩阵现存 5 例（D3/D5D9/D11/D18/D28）全部独有。
- **2026-09-07 噱头清理第三步（体验 OS tab / Immersive 活过来）**：用例数 2481 → 2499（+18：ExperienceSettingsTest 5 + ExperienceTabTest 6 + test_experience_demote 4 + test_fill_nokey_guard 3）。
- **2026-09-07 噱头清理第二步（Sovereign 档移除）**：用例数 2485 → 2481（-4：SovereignModeTests 3 例 + immersive C 集等价对照 1 例）。侵入度阶梯收敛为 observer/copilot/active/immersive 四档（presence_level 0–3）。
- **2026-09-07 噱头清理第一步（孤儿模块删除）**：用例数 2492（上次记录）→ 2485（实测）。删除 3 个零生产调用者模块约 **710 行** + 2 个陪跑测试文件（-8 例），其中 3 例 AmbientHeartbeatService 心跳门控测试迁入新文件 `test_ambient_heartbeat.py`。
- **2026-09-06 测试去重第一步（零覆盖损失清理）**：用例数 2574 → 2520（-54，其中 **35 例**本就整文件 skip 永不执行）。删除 11 个测试文件约 **1300 行** + 2 个死 src 模块。验证：受影响模块定向 164 例 OK。
- **2026-09-06 测试去重第二步（adversarial_matrix 瘦身）**：用例数 2520 → 2492（-28）；`test_adversarial_matrix.py` **778 → 296 行**。验证：矩阵 + 15 个 counterpart 模块 **237 例** OK；`run_gui_tests.py ci`（L0 gate + L1 fast）**1514 例** 0 失败。
- **2026-08-05 之前的历史基线**：主题专项 `python -m unittest tests.test_theme` → **29 passed**；全量用例（上次记录）**1276 passed（skipped=2）**；命令 `QT_QPA_PLATFORM=offscreen python -m unittest discover -s tests -p "test_*.py"`。
- **2026-07-21 课程工坊布局压缩（L1–L2）**：用例数保持 **1276**。
- **2026-07-21 aiEnhance 感知增强（第四–六枪 U0–U4）**：用例数 1252 → 1276（+24）。
- **2026-07-21 aiEnhance 第三枪 批次③（Phase 4 教材抽取增强）**：用例数 1218 → 1252（+34）；落地 P4-1/2/3/4/6（P4-5 原文 span 定位为可选项，本批不做）；新增 `tests/test_chapter_windows.py` 7 用例。
- **2026-07-21 aiEnhance 第三枪 批次②（Phase 5 智能工作流 Agent）**：用例数 1203 → 1218（+15）；落地 P5-1..6；新增 `test_ai_pipeline` 10 例、`test_design_controller.DesignControllerPipelineTest` 5 例。
- **2026-07-21 aiEnhance 第三枪 批次①（cache + 双模型 + strict_schema + 抽取统一 loop）**：用例数 1121 → 1203（+82）；新增 `test_ai_cache` 25 例、`test_settings.SettingsAdvancedAiTest` 9 例、`test_ai_generator.TestAiApiConfigAdvanced` 8 例、`TestGenerateWithValidateLoopCache` 8 例、`TestDualModelRouting` 5 例、`TestBuildResponseFormat` 7 例、`TestJsonSchemaRejectionHeuristic` 4 例、`TestRequestChatAutoFallback` 3 例、`ExtractKnowledgePointsLoopTest` 8 例、`SettingsDialogAdvancedAiTest` 4 例、`test_telemetry` +1。
- **2026-07-21 aiEnhance 第二枪（质量分 + 编辑效率 + 分阶段生成）**：用例数 1101 → 1121（+20）；新增 `test_content_quality` 9 用例、`test_ai_phased` 10 例。
- **2026-07-21 aiEnhance 第一枪（Phase0 + 稳定性 + pedagogy）**：用例数 1075 → 1101（+26）；新增 `test_ai_bench` 9、`test_ai_pedagogy` 9、`test_ai_generator` 扩展 loop/fill/path +8。
- **2026-07-21 tool/gui 性能与缺陷全量整改（分批 A–F）**：用例数 1068 → 1075（+7）；清理 `assets/courses/turkish/.varnamala-backup/` 运行时产物并加 `.gitignore`。
- **2026-07-20 主题系统重设计：Peacock 品牌对齐 + 高对比度 + 渐变深度**：用例数 1043 → 1068（+25）；`test_theme.py` 25（4 套调色板键集一致 / accent 为孔雀青非蓝 / 高对比度纯黑白 / `palette_for` 回退 / 徽标与资源类型色 / `valid_themes` 不可变）；4 套调色板 43 个语义 token/套；Phase 4 整改 **18 个文件、~46 处**硬编码 hex。
- **2026-07-20 课程总览增强 + 纯函数抽离（P5）**：用例数 1009 → 1043（+34）；新增 `test_overview_stats.py` 26（纯函数）；`test_course_overview.py` 4 → 12。
- **2026-07-20 资源库 / Git 资源库丰富（ADR 0021-0026）**：用例数 961 → 1009（+48）；新增依赖 `keyring>=24.0`；新增 ADR `docs/decisions/0021-0026`。
- **2026-07-20 代码审查修复（9 项缺陷）**：用例数 952 → 961（+9）；新增测试 `test_app` 草稿导入持久化 ×2、`test_ai_fix_dialog_guard` ×3、`test_design_panel` ×3、`test_git_library` ×1。
- **2026-07-20 测试精简：共享 helper 去重**：用例数 **952 不变**、断言行为不变；抽出 4 个共享 helper 模块（`tests/_qtapp.py` 30 文件 / `tests/_course_samples.py` 5 文件 / `tests/_qsettings_mock.py` 2 文件 / `tests/_course_fixture.py` 11 文件 + 12）；净减约 **379 行**（16111 → 15732）；验证 `unittest discover` **952 passed**；`pytest tests/ --ignore=tests/test_app.py` **920 passed**。
- **2026-07-20 课程工坊 P4：文档对齐统一画布**：文档-only（用例数不变）。
- **2026-07-20 课程工坊 P3：功能增强**：用例数 938 → 952（+14）。
- **2026-07-20 课程工坊 P2：性能与卡顿**：用例数 931 → 938（+7）；气泡池 `rows_changed` 60ms debounce；design autosave 2s 节流。
- **2026-07-20 课程工坊 P1：交互流畅度**：用例数 922 → 931（+9）。
- **2026-07-20 课程工坊 P0：统一画布 + 轻量 checklist**：用例数 917 → 922（+5）；气泡池上限 200。
- **2026-07-19 tool-gui 使用逻辑改进（AI 冲突确认 + 工坊目标选择 + 越树移动）**：用例数 888 → 917（+29）；新增 `test_app.AiEditConflictTest` 7、`test_import_target_dialog` 5、`test_app.WorkshopImportTargetTest` 2、`test_course_tree.CourseTreeCrossTreeMoveTest` 9、`test_commands_and_ai_edit.ReparentCommandsTest` 2。
- **2026-07-19 代码精简 T4（不改功能）**：用例数不变（**888 passed, skipped=2**）；净减约 **69 行**；4 个基类合并 13 个命令。
- **2026-07-19 代码精简 T3（不改功能）**：用例数不变（**888 passed, skipped=2**）；净减约 **112 行**。
- **2026-07-19 代码精简 T1+T2（不改功能）**：用例数不变（**888 passed, skipped=2**）；净减约 **110 行**。
- **2026-07-19 upgradeplus1 第二阶段优化（不改功能）**：用例数不变。
- **2026-07-18 性能/缺陷/体积优化轮（不改功能）**：用例数不变。
- **2026-07-18 教师模式重构（三面合一 + 编辑器外壳统一 + 发布合并）**：用例数不变。
- **2026-07-18 三入口合一 + 工坊 UI 大改（merge overhaul A–D）新增覆盖**：用例数不变。
- **2026-07-16 教材导入 Phase 6（收尾）新增覆盖**：用例数不变；`test_resource_review_table.py` `ReviewTablePerfTest` 50×50=2500 行 set_rows、单章过滤 <0.5s、全量刷新 <1.5s、搜索刷新 <0.5s。
- **2026-07-16 教材导入 Phase 5（AI 能力打通与优化）新增覆盖**：用例数不变。
- **2026-07-16 教材导入 Phase 4（合并与导入策略）新增覆盖**：用例数不变。
- **2026-07-16 操作日志（Operation Log）新增覆盖**：用例数不变。
- **2026-07-15 三项可用性改动新增覆盖**：用例数不变。
- **P4 + P6 新增覆盖**：用例数不变。

---

## 已知环境限制

- `test_app.py` 会实例化 `MainWindow`，在 headless/offscreen 环境下可能崩溃；请在本地图形环境运行。
- 部分 GUI widget 测试依赖 `QT_QPA_PLATFORM=offscreen`，在本机普通环境下可直接运行。
- 单进程顺序 `discover` 全量在本机长时间不终止（CPU 匀速爬升疑似计时器空转）；`run_gui_tests.py full` 已改为对全部 test_*.py 模块走 `run_modules_parallel` 每模块独立子进程，`full -j N` 控制并发数。
