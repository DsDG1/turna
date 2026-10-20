# GUI AI 重构契约（M0 / M1）

> 改 AI 能力前读本文 + `src/backend/ai/`。边界扫描：`python3 tool/gui/tool/check_ai_boundaries.py`。
> 本文档只记契约（规则、阈值、路径、门禁指标）；历史施工流水在 git 历史里。

## 1. 红线（不得破坏）

| 红线 | 说明 |
|------|------|
| API Key 不落盘 | 仅内存；Settings 不序列化 `ai_api_key` |
| 写盘必经预览 + 确认 + Undo | Experience / merge / fix 路径 |
| id 默保 | splice / structural_diff / pipeline Fix 回滚删 id |
| 不自动 import 课程 | pipeline 停在 `READY_IMPORT` |
| Prompt 文本稳定 | 拆分不得改 prompt 字符串（cache key / 金测） |

## 1b. 生成入口（M2）

| 路径 | 用途 |
|------|------|
| `src.backend.ai.facade.generate_course` | 唯一对外生成入口（工坊 DesignController） |
| `mode=fast` | single-shot + validate retry |
| `mode=refine`（别名 `phased`） | 全流水线 `run_pipeline` |
| chat_history 非空 | `generate_from_chat` 分支 |
| `ai_phased.request_course` | 遗留 thin wrapper（outline→lesson，非完整 pipeline） |

## 1c. 配置注入（M3）

- `src.application.ai_runtime.AiRuntime` / `runtime_from_host`
- dialogs/ 禁止 `from src.app import current_ai_config|current_settings`
- backend/、application/ 禁止 `from src.app import …`：非 dialog 代码经 `src.application.runtime_context.current_settings|current_ai_config` 读取（MainWindow 启动时注册 provider，关闭时注销）
- 门禁：`--fail-dialogs-app --fail-backend-app`

## 1d. Experience 分发（M4 / M7）

- 入口：`src.application.experience_dispatch.dispatch_experience_action`
- 注册表 `experience_handlers.registry.HANDLERS` — 懒 `getattr(module, "handle_*")`，便于 mock
- 实现体 `experience_handlers/{fill,regenerate,quality,resources,multimodal,memory_nav}.py`
- Mixin `experience_skills_mixin` 仅 ambient/policy + 薄 `_experience_*` 包装（测试/树直接调用）
- 新增 skill = `ACTIONS` + `registry.HANDLERS` + `handle_*`（可选 host 包装）
- 测 mock `patch("…handlers.fill.handle_fill_empty")`；不要只 mock `host._experience_*` 期望 dispatch 命中。覆盖测 `tests/test_experience_dispatch.py`

## 1e. Suggestions 拆分（M6）

- 聚合 `src.backend.experience.suggestions.ambient.local_suggestions`
- 收集器 `p0_validate` / `p1_empty` / `p2_*` / `p3_*`
- 兼容 `context_bus.local_suggestions` re-export

## 1f. 节点 AI 编辑（M5）+ 遗留对话框（M8）

- 生产路径：树 AI 编辑 → `experience_handlers.edit.handle_node_edit` → `MainWindow._on_ai_edit` → `AiEditController.handle_ai_edit` → `NodeAiEditDialog`（`dialogs/ai/node_edit_dialog.py`；构造签名 `scope/scope_id/existing_section`）
- 共享引擎 `ai_generator_dialog.SectionAiDialog` 承载 normal/wish 生成与 edit_mode 引擎的唯一实现；`AiGeneratorDialog` 是其上的工坊生成专用壳（LEGACY 名称保留），公开签名不再接受 `edit_mode`
- 底层 `generate_edit` / `regenerate_*_in_section`（经 `GeneratorWorkerHub.make_edit_worker`）
- LEGACY `AiGeneratorDialog`（文件头标注）— 工坊生成 UI + 测试；禁止再扩 edit_mode

## 2. 包布局（M1 后真源）

```text
src/backend/ai/
  config.py           # AiApiConfig, AiCourseSpec, ChatMessage, SYSTEM_*
  client.py           # request_chat, verify_connection
  parse.py            # parse_completion, content_text
  prompts.py          # build_prompt / alignment / edit / response_format
  validate_loop.py    # generate_with_validate_loop, coerce_problem_messages
  resource_fix.py     # normalize_resources, auto_fix_resources
  section_ops.py      # fill_*, diff, splice, regenerate, transforms
  course_generate.py  # request_course_with_retry, generate_from_chat, explain, generate_edit
  __init__.py         # 稳定 re-export

src/backend/ai_generator.py   # 兼容薄层：旧 import / monkeypatch 路径
```

新代码优先 `from src.backend.ai import …`；旧路径 `from src.backend.ai_generator import …` 过渡期内保持可用。

## 3. 公开 API 白名单（目标态）

- 配置/类型：`AiApiConfig`, `AiCancelled`, `AiCourseSpec`, `ChatMessage`, `SYSTEM_AUTHORING`, `SYSTEM_EDITING`, `SYSTEM_CORRECTION`, `SYSTEM_AUTHORING_CHAT`, `SYSTEM_AUTHORING_EDIT`
- 网络：`request_chat`, `verify_connection`, `chat_json`
- 解析/资源：`parse_completion`, `content_text`, `normalize_resources`, `auto_fix_resources`, `iter_items`
- 生成闭环：`generate_with_validate_loop`, `coerce_problem_messages`, `build_response_format`, `build_prompt`, `build_alignment_prompt`, `build_edit_prompt`
- 课程级：`request_course_with_retry`, `generate_from_chat`, `request_alignment_reply`, `explain_course`, `generate_edit`, `detect_genre_from_spec`, `apply_genre_to_spec`
- 局部/修复：`fill_needs_review_resources`, `fill_listening_gaps`, `regenerate_lesson_in_section`, `regenerate_unit_in_section`, `request_lesson_transform`, `request_item_transform`, `request_correction`, `splice_lesson_in_place`, `structural_diff`, `full_section_diff`

## 4. 禁止事项

1. 包外 `from src.backend.ai_generator import _foo` 或 `from src.backend.ai.* import _foo`（包内可用 `_` 作实现细节；对外需公开名。兼容层 `ai_generator` 可 re-export 旧 `_` 别名供测试。）
2. dialogs/ 依赖 `from src.app import current_ai_config` — M3 目标清零（M1 不强制）。
3. 业务模块自写第二套 HTTP 客户端（必须走 `request_chat`）。
4. 为拆分而改 prompt 字面量。

## 5. 热点行数基线

单文件目标：AI core ≤900 行 —— 本契约唯一有效的行数阈值。各文件的「X → Y 行」是手工快照，实测已有 11/16 项漂移（如 `settings_dialog.py` 372→574、`src/app.py` 721→873），且 §1f/§11 引用的 `dialogs/ai_generator_dialog.py` 已不存在（现为 `dialogs/ai/section_ai_dialog.py`）。行数不作验收依据：拆分成果以符号名（类/方法是否保留、是否迁入新模块）判定，符合仓库根 `AGENTS.md`「引用用符号名不用行号」。

## 6. 里程碑状态（M0–M8）

M0 契约文档 + 边界扫描；M1 `backend/ai/` 拆包 + 薄 `ai_generator`；M2 `generate_course()` 单一 facade；M3 dialogs 配置 DI（`AiRuntime`）、禁止 `src.app`；M4 Experience handler 注册表 + dispatch；M5 树编辑 → `NodeAiEditDialog`、巨石标 LEGACY（`NodeAiEditDialog` 为生产入口，`AiGeneratorDialog` 公开签名去 edit_mode）；M6 suggestions collectors 拆分；M7 skill 体迁入 `experience_handlers/*`；M8 LEGACY 标注 + 契约收口。M0–M8 全部完成。

## 7. 测试门禁

> `make test-gui-ci` 目标不存在：`Makefile` 只有 `lint-gui` / `guard-gui` / `test-gui` / `ci`。分档真源是 `run_gui_tests.py` 的模块 docstring，不是 `tests/BASELINE.md`（该文件并无分档说明）。

```bash
make guard-gui                                          # 门禁（已接入 make / 两个 CI workflow，基线见 §9）
cd tool/gui && python3 run_gui_tests.py ci -j 4         # 日常：L0 gate + L1 fast（PR 默认档）
cd tool/gui && python3 run_gui_tests.py full -j 4       # 全量：逐模块子进程（发布前 / nightly）
cd tool/gui && python3 run_gui_tests.py affected -j 4   # 仅当前 git diff 影响的模块
python3 tool/gui/tool/check_ai_boundaries.py --fail-private  # 单边界快速自查
```

Windows / PowerShell 下无 Qt 环境时用 `$env:QT_QPA_PLATFORM = "offscreen"`（bash 才是 `QT_QPA_PLATFORM=offscreen` 前缀写法）。

## 8. Experience host 契约与债务棘轮

- host 协议化：handler/controller 的 host 参数统一注解为 `src.application.experience_host.ExperienceHost`（typing.Protocol，结构化匹配，MainWindow 无需改继承），协议声明 handler 层实际访问的全部 113 个成员（23 公开 + 90 内部契约）；backend 侧（`auto_apply.py` / `precognition.py`）刻意保留 `host: Any`，避免 backend → application 反向 import。
- 防漂移门禁 `--fail-undeclared-host-access`：已注解模块出现未声明的 `host._x` 访问即失败，新增耦合必须先写进协议；补齐 `_overview_widget` / `_save_shell_state` / `_mark_saved` / `_set_view` / `_view_pages` 五个成员后未声明访问归零，该选项已恢复启用。
- backend → UI 禁令 `--fail-backend-ui`：backend/ 禁止 import widgets/dialogs/teacher/theme/app（error_mapper、TEMPLATE_BADGES 已下沉 backend）。
- backend → Qt 禁令 `--fail-backend-qt`：backend/ 禁止 import PySide6。原 4 处 Qt 耦合已清：`credential_store` / `git_remote_catalog` / `ai_prompt_library` 迁往 `src/application/`（纯持久化 helper，调用方全在 dialogs/app 层）；`generate_audio_worker` 拆为纯逻辑 `generate_audio_client.run_tts_generation` + Qt 壳 `application/audio_worker.py`。

## 9. P2/P3 债务清理基线

| 目标 | 拆分结果（以符号名判定，不看行数） |
|---|---|
| MainWindow 瘦身 | closeEvent→`close_controller`；工坊/教材导入 7 方法→`workshop_controller`；总览 4→`overview_controller`；资源 3→`resources_controller`；校验报告→`validation_controller`；死代码（重复定义的 `_on_undo_index_changed` 等）已删；`_save_course_async` 保留在 app（与 `save_host.execute_save` 语义不同：后台直存 vs SavePipeline） |
| Mixin 收口 | `experience_skills_mixin` 只剩 policy/funnel + 薄包装，ambient 组 11 方法迁至 `application/ambient_controller.py`（模块函数 + ExperienceHost 注解）；协议新增 `_defer_store`/`_ambient_mute`/`_heartbeat_wait_idle`/`_ambient_heartbeat`/`_save_worker`；孤儿心跳定时器代码（无创建点、相关测试整类 skip）暂保留 |
| GitLibraryDialog 按域拆分 | 壳 + `dialogs/git_library/` 包（`git_worker_hub`/`sync`/`remotes`/`branches`/`repo_browser`/`lan_share`/`memo`，模块函数以 `dlg` 为上下文）；`textbook_library_dialog` 复用 `GitWorkerHub` 消除镜像 plumbing；全部 widget 属性名与方法名保留 |
| 顺延项 | `run_pipeline`/`run_item_chip` 巨型函数待拆；138 处内联 `setStyleSheet` 收口（硬编码 hex 9 处已清） |
| 吞异常清理 | 见 §13；棘轮 `--max-except-pass` —— 全 src 静默 `except: pass` 只减不增，全仓（含 dialogs/widgets/teacher 等 UI 层）已改为 `logger.debug/warning(..., exc_info=True)` |
| 循环依赖 | experience 三元环已切（actions 为纯叶子，`is_dangerous_skill_allowed` 真源在 policy）；`ai_error_analyzer` 改走已下沉的 `src/application/ai_request_worker.py`（原 `dialogs/ai/worker.py`） |

完整门禁命令（已接入 `make guard-gui`、`.github/workflows/flutter_ci.yml`、`.github/workflows/gui_release.yml`）：

```bash
python3 tool/gui/tool/check_ai_boundaries.py \
  --fail-private --fail-dialogs-app --fail-backend-app \
  --fail-backend-ui --fail-backend-qt --fail-dialogs-pipeline \
  --fail-undeclared-host-access \
  --fail-course-cli-binding
```

数字基线单一真源为 `tool/gui/tool/guard_limits.json`：checker 自动读取该文件作默认值，Makefile / 两个 workflow 不再手抄数字，CLI 数字旗标仅作一次性实验覆盖用；重钉程序为实测 → 改 json → 在 `tests/BASELINE.md` 记录，文件缺失/损坏时 checker 直接失败而非静默放行。

棘轮收紧历史：`--max-hardcoded-style-hex` 29 → 0；`--max-except-pass` 由文档声称的 0 校正为实测 11（清理后归零并锁定 0）；`--max-broad-except` 836→818→816；`--max-except-continue` 为新增项（AST 检测 body 仅为 `continue` 的宽泛 except 处理器，bare / `Exception` / `BaseException`；`except KeyError: continue` 等窄捕获属惯用写法不计入，存量 19 处 S112 已补 `logger.debug(..., exc_info=True)` 清零）。数字一律以 `guard_limits.json` 为准，语义「当前值，只减不增」。

## 10. 管线入口收拢与 app→dialogs 棘轮

- dialogs → 管线内部禁令 `--fail-dialogs-pipeline`：dialogs/ 禁止直接 import `backend.ai_pipeline` / `backend.ai_phased`，统一走 `src.backend.ai.facade`（PEP 562 模块级 `__getattr__` 惰性转发 `run_pipeline`/`PipelineState`/`PipelineStep`/`CHECKLIST_STEPS`/`STATUS_*`/`request_course`，保持原有循环导入规避设计）；当前基线 0。
- app/application → dialogs 棘轮 `--max-app-dialogs-imports N`：application 层不得 import dialogs 的基础设施（worker/helper），已清零并下沉 `src/application/ai_request_worker.py`（原 `dialogs/ai/worker.py`，29 个文件引用点同步）、`src/backend/quality_campaign.py`（原 dialogs 里的纯排序函数）；剩余 13 处为 controller / app.py 作为组合根启动对话框窗口的既定模式（InitCourseDialog/SettingsDialog/AiFixDialog/WorkshopWindow 等），属已知债务。原先只有「零容忍」形态 `--fail-app-dialogs`（有就失败），13 处债务无法清零，该选项在 Makefile 与两个 CI workflow 里从未启用 —— 契约写了、门禁没管，数字因此无上限；现改为上限形态 `--max-app-dialogs-imports 13`（基线写在 `guard_limits.json`），语义与其它棘轮一致：只减不增。`--fail-app-dialogs` 保留为「清零后启用」的形态，现阶段不启用。
- 私有符号外泄清零：`textbook_to_course._rewrite_ids_deterministic` 增加公开别名 `rewrite_ids_deterministic`；design_controller / section_import_service 改用公开名。

## 11. 巨型对话框/文件拆分

- `SectionAiDialog`：`ai_generator_dialog.py` 薄壳 + `dialogs/ai/generator_panels.py`（UI 构建）/ `generator_view_state.py`（模式切换、忙碌态、流渲染）/ `generator_flows.py`（生成、校验、导入流程，`AiRequestWorker` 函数内惰性导入保 `mock.patch` 兼容）；属性转发层保留，测试 patch 目标由 `ai_generator_dialog.X` 同步至 `generator_flows.X`。
- `SettingsDialog`：`settings_dialog.py` 薄壳 + `dialogs/settings/` 包 7 个 tab 模块（外观 / ai_tab / ai_usage_tab / extraction_prompt_tab / editor_tab / git_library_tab / operation_log_tab）；全部 widget 属性名与方法名保留。
- `commands.py`：`application/commands.py` → `commands/` 包（`item_commands` / `tree_commands` / `ai_commands` / `meta_commands` + `_base` 共享件），`__init__` 全量再导出，调用方与测试导入路径零改动。
- MainWindow：shell / repo_session_host / experience_window_bridge / save_host / section_import_service 五向拆分，方法名保留委托；`textbook_import_dialog` 拆为 constants.py + pages.py，DesignPanel 的 UI 构建迁 design_panel_build.py。

## 12. P2 深水区棘轮

- 宽泛异常棘轮 `--max-broad-except`（数值见 `guard_limits.json`）：全 src 宽泛 except 处数只减不增；不做批量收窄（行为风险 > 收益），新代码应捕获具体异常或至少 `logger.debug(..., exc_info=True)`。
- 内联样式棘轮 `--max-hardcoded-style-hex 0`：`setStyleSheet` 内嵌 hex 色且无 palette 回退的调用只减不增（暗/亮主题适配缺陷），新样式应走 `current_palette()` / theme token。
- 审查后保留：DesignController（分区清晰的内聚状态机，方法均短）、CourseAdapter（后端无 Qt 状态类，方法均短）—— 强拆只增加间接层。

## 13. 静默异常回归清理

接线当日实测 `except: pass` = 11，而 §9 曾记为「已全部清零」—— 根因是本棘轮长期未接入任何门禁，回归无人拦截；现已清理完成，实测归零并锁定 `--max-except-pass 0`。

先修工具，再清代码：`count_silent_except_pass()` 原先不区分捕获广度，`count_silent_except_continue()` 区分；二者已统一到共享的 `_is_broad_except()` 判定 —— 否则下表第 5 项这类合理的窄捕获会一直卡住棘轮无法归零。

1 `src/app.py` `sync_save_state_label`（`Exception`）→ `logger.debug(..., exc_info=True)` + 注明「仅影响状态栏文案」；
2 `src/application/shell_views.py` `_telemetry`（`Exception`）→ 补日志（telemetry 绝不阻断 UI 动作）；
3 同文件重建 resources tab（`Exception`）→ 补日志（tab 已被 Qt 回收）；
4 同文件切到 edit 视图（`Exception`）→ 补日志（host 形状变化的 trace）；
5 同文件窗口存活探测（`RuntimeError`）→ 窄捕获，保留 `pass`，补「为何安全」注释；
6 `src/application/overview_controller.py`（`Exception`）→ 补日志（仅降级为不切视图）；
7 `src/application/repo_session_host.py`（`Exception`）→ 补日志（repo 已加载，失败的只是外壳 chrome）；
8 `src/application/validation_controller.py`（`Exception`）→ 补日志（仅降级为不切视图）；
9 `src/application/workshop_controller.py`（`Exception`）→ 补日志（仅降级为不切视图）；
10 `src/icons/__init__.py` DPR 兜底（`Exception`）→ 补日志（headless 下 1.0 是正确回退）；
11 `src/widgets/course_tree.py` 拖拽指示器绘制（`Exception`）→ `pass` → `logger.debug`，保留原注释。

配套：`src/application/repo_session_host.py` 与 `src/widgets/course_tree.py` 原先没有 logger，已补 `logging.getLogger(__name__)`。

可观测性补丁：`src/main.py` 的 `basicConfig(level=INFO)` 是全仓唯一日志配置，而上述防御分支统一记在 `DEBUG`（约 400 个调用点）—— 「消灭静默异常」的成果在用户机器上一条都不落盘；现改为 `TURNA_GUI_LOG_LEVEL` 环境变量可配（默认仍为 `INFO`，非法值回退 `INFO` 并向 stderr 提示），排障时设 `TURNA_GUI_LOG_LEVEL=DEBUG` 即可看到全部防御日志。

清理过程中把 `user_action_filter` 里两处「探测 Qt 对象」用的 `except Exception` 收窄为 `except RuntimeError`（PySide6 对已析构 C++ 对象只抛这一种），使 `--max-broad-except` 从 818 进一步降到 816 并锁定。

## 14. `tests/test_shell_views.py` 与 `tests/test_app.py` 挂起 —— 根因与修复（2026-09-27，已修）

整改期间实测：这两个模块整模块运行时**100% CPU 自旋、不返回**。
`faulthandler` 抓栈落在 `theme.apply_theme → MainWindow.__init__ → build_main_window → setUp`。

**根因一：存活控件数无界增长。** 一个 `MainWindow` 拥有数百个子控件，而 Qt 的
polish / measure 成本正比于**进程中全部存活控件**，而非新建的那一个。
`setUp` 里建窗口的测试类从不销毁窗口，于是每建一个，下一个就更慢。
实测（连续建窗口，每次计时）：

| 累计控件数 | `setStyle` | `setStyleSheet` |
|---|---|---|
| 200 | 31 ms | 91 ms |
| 600 | 140 ms | 637 ms |
| 1200 | 676 ms | 2521 ms |

`apply_theme` 在 8 次构建内从 12 ms 涨到 3.7 s（**≈300 倍**）。
注意守卫 `setStyle` 之后热点**转移**到 `DetailPanel.__init__` —— 这正说明
问题是整体的控件规模，而非某一行代码。

**根因二：`apply_theme` 每次调用都重申进程级状态。**
`QApplication.setStyle` 与 `setStyleSheet` 都不是「幂等且廉价」的：每次都会
重新 polish 全部控件。而 `MainWindow.__init__` **每个窗口**都调一次 `apply_theme`
（为了套用用户保存的主题/字号），于是这两个进程级 setter 被反复触发。

**三处修复**：

1. **`src/theme.py`** —— 基础样式改为**按 QApplication 只断言一次**
   （模块级 `_STYLED_APP` 身份跟踪），样式表在内容未变时跳过重设。
   刻意**不**读 `app.style().objectName()` 来判断：装了样式表之后该回读不可靠
   （实测它持续报非 Fusion，导致守卫每次都判定「需要重设」）。
   这同时修掉生产侧的真实浪费：用户重复选择同一主题/字号原本会白付一次全量 polish。
2. **`tests/_mainwindow_fixture.py`** —— `build_main_window()` /
   `build_main_window_with_settings()` 新建前**回收上一个窗口**
   （`setParent(None)` + `deleteLater()` + 显式 flush `DeferredDelete`）。
   刻意**不用 `close()`**：`MainWindow.closeEvent` 会走保存 / shell 状态 /
   退出确认路径，那正是测试 mock 掉的东西。
   已核对无任何测试需要两个窗口同时存活（每个方法各建一个）。
3. **`tests/test_app.py`** —— 该模块有 11 个类在 `setUp` 建窗口却只有 1 个有
   `tearDown`，同样无界累积。已加同款回收 + `tearDownModule`。

**顺带修掉一个生产代码的潜伏崩溃（重要）**：
`_ButtonSizePolicyFilter` 在 `MainWindow.__init__` 里被装到 **QApplication** 上，
但**既无 parent 也从不移除**。窗口析构后 Python 回收该对象，Qt 却仍在过滤器
列表里派发 Polish 事件 → **0xC0000005 访问违例**（实测崩溃点在 `src/app.py`
的 `eventFilter`）。单窗口的桌面场景永远不触发，所以一直没暴露；一旦真的销毁
窗口（正是测试要做的）就必崩。已改为 `_ButtonSizePolicyFilter(self)` 由窗口持有，
窗口销毁时 Qt 自动注销。

**结果**：

| 模块 | 修复前 | 修复后 |
|---|---|---|
| `tests/test_shell_views.py` | 无限挂起（>240s，100% CPU） | **41 tests / 19.9 s / OK** |
| `tests/test_app.py` | 无限挂起（BASELINE 记为最慢 ~94s） | **41 tests / 36.6 s / OK** |

**顺带说明**：BASELINE 里「整模块 discover 会在计时器/信号串扰处挂起」的旧描述
指向的是同一现象（未回收窗口 + 反复重申进程级样式导致的资源累积），
不是定时器逻辑本身有问题。

## 15. UI→backend 旁路与 import 环

`application/` 门面层最大的现实问题：UI 层绕过它直连 backend。实测（AST 全量扫描，含函数体内的惰性 import）：UI 层（dialogs/widgets/teacher）import backend 的语句数见 `tool/gui/tool/guard_limits.json`（`max_ui_backend_imports`；下表其余数字为历史快照）：模块级约 121，涉及 UI 文件 66，去重后的 (模块, 符号) 边 172。按导入符号性质粗分（用于判断迁移难度，不是验收依据）：数据/标签表 26 个符号、类型与常量 43 个、函数 99 个、含「服务」字样的类 4 个（`GitLibrary` 等，23 处引用）。

模块级 import 环已清零（基线从 2 降到 0），两处环都用 PEP 562 模块级 `__getattr__` 惰性再导出断开，调用点无需改动：`backend/experience/suggestions/__init__` → `ambient` → 各 `p*` 收集器 → 回指包（包 `__init__` 改为惰性导出 `local_suggestions`）；`dialogs/git_library/__init__` → `git_library_dialog` → 包内各功能模块（包 `__init__` 改为惰性导出 `GitLibraryDialog`）。惰性再导出与 `src/backend/ai/facade.py` 已有的一致（契约第 2 节即用同一手法规避 `ai_pipeline` 的循环导入）。

`dialogs → widgets`（21 处，方向合理：对话框复用组件）不设棘轮；`widgets → dialogs` 是反向耦合（可复用组件伸手进具体对话框），当前 4 处：`bulk_merge_resolve_panel.py:72`、`course_tree.py:792`、`course_tree.py:814`、`workshop_canvas.py:34`。

`course_cli` 单网关已收口：`src/widgets/resource_editor.py` 原先 `from src.backend.api import course_cli`（重新导出 CLI 内部对象），已改为调用 `api.py` 已有的包装 `export_csv_rows()`，该规则基线直接为 0。

为什么用棘轮而不是立即清零（边数为历史快照）：163 条边中真正该改的是那 99 个「函数」类符号，但分散在 66 个文件里且多数是惰性导入，一次性改成 0 会让主干无法推进；先钉住基线保证只减不增，再按「数据 → 类型 → 函数」顺序逐块下沉到 `application/` 门面。CI 日志：该边列表有 163 行，默认只打印分层汇总 + 前 8 条，需要全量时加 `--verbose`。

## 16. 静态类型检查：实测基线与真实结论

全仓有 2464 处类型注解、12 个 `Protocol`（含 113 成员的 `ExperienceHost`），但零类型检查器配置；团队用正则手搓 `scan_undeclared_host_access()` 模拟类型检查器 —— 它漏掉的那 8 处漂移正说明这条路走不远。

实测（pyright 1.1.414，default 模式，`src/application/**`）：总诊断 1736（error 1736 / warning 0），按形态归类 `attr-access` 772、`argument` 566、`other` 336、`return-type` 61、`undefined` 1。抽样确认：绝大部分不是类型债，而是本项目刻意的鸭子类型约定的直接后果 —— 属性访问报错来自 `host: Any` 与「模块函数 + host 作上下文」的写法，参数个数报错来自函数体内惰性 import 与未声明的 Protocol 成员。唯一的 `reportUndefinedVariable` 是 `ai_request_worker.py` 的 `_LIVE_WORKERS: set[AiRequestWorker]` 写在类定义之前 —— 已核实非缺陷（该文件有 `from __future__ import annotations`，注解不求值，实际 import 正常），是误报。

结论：现在把 pyright 接成门禁是错的。把 1736 钉成棘轮，等于把一个设计决策（`host: Any` 规避 backend→application 反向 import，见 §8）记成了「债务」，得到一个不重写分层风格就永远不动的数字。

正确顺序是先决策、再上工具：先决定是否替换 `Any` 约定（一次有真实迁移成本的分层风格决策，涉及 55 个 application 模块与全部 experience handler）；决定要做，再分阶段接入 pyright：先 `src/application/**` basic 模式定基线，再扩 `backend/experience/**`，最后 dialogs/widgets（Qt 存根噪声大）；同步考虑逐步放开 `pyproject.toml` 全局关闭的 `F401`（配合 `__init__.py` re-export 白名单）—— 全局关闭会掩盖真实的未使用导入。

若只做一件事、不接工具也能拿到的收益：错误集中度即优先级 —— `shell_views.py` 181、`settings.py` 130、`experience_handlers/regenerate.py` 116、`resources.py` 96、`goal_controller.py` 93。

## 17. 收尾批次：C-6 / D-3 / D-6 / G-5

- C-6 文档归档倒挂：`docs/archive/experienceai.md`（已移至 `docs/experienceai.md`）是 4 篇在役设计文档（`a3-` / `e4-m01-` / `e4-m0345-` / `k08-`）的共同上位规范并被 3 个测试模块引用，却躺在归档区且无索引入口。已做：`experienceai.md` 移回 `docs/`（`git mv`，保留历史），4 篇设计文档路径引用同步更新；新增 `docs/README.md` 索引（区分「在役契约 / 在役设计」）与 `tool/check_docs_index.py`，接入 `make guard-gui` 与两个 workflow，校验「每个 docs 下的 md 都在索引里」。用校验器而非生成器：一句话用途是编辑性内容，生成器会冲掉；「没有孤儿文档」才是可机械断言的不变式。负向测试已验证（注入孤儿 → `exit 1`）。
- D-3 死代码收尾：`-j/--jobs` 默认由 1 改为 0（=自动，4 worker）。「最慢优先」调度只在 `-j>1` 生效，而 `cmd_ci` 默认 `jobs=1` ⇒ 默认路径上那段代码是死代码；`cmd_fast` / `cmd_affected` 的单进程 in-process 路径与 `cmd_full` 的逐模块子进程路径不一致，而 in-process 正是旧挂起的温床（根因已修，见 §14），故单进程路径保留但不再默认，`-j 1` 仍可显式选择。实测：`ci` 不带 `-j` 现在走并行，48/48，~10.5 s。
- D-6 基线数字校正：权威取数 191 模块 / 2555 例；同时在 `tests/BASELINE.md` 顶部加结构性说明 ——「当前基线」是唯一权威数字、只增不删，避免有人翻到旧条目把 2537/2541 当现状。
- G-5 打包与剩余安全项：
  - `turna_gui.spec` 的 `hiddenimports` 补上 `keyring` —— 它是硬依赖（Git 凭据走 keyring），但 `credential_store` 在函数体内 import，PyInstaller 静态分析看不到；漏了会让打包版静默降级到 base64-in-QSettings。同时补齐 `application/` / `backend/experience/` / `dialogs/ai/` / `infrastructure/` 这些经由 `src/backend/ai/facade.py` 的 PEP 562 惰性转发可达的表面；并订正原注释 ——「src/ 内无动态导入」的说法被该惰性转发证伪。
  - spec 此前根本没有 `version=`，打包出的 exe 对 Windows 和 bug 报告都不报版本；现从 `pyproject.toml` 读取（单一真源，不再抄第二份），`pyproject.toml` 里的 `0.0.0` 与「版本在 PyInstaller 里」那句失效注释一并更正。
  - git 凭据泄漏：`git_library._run` 把 `args` 与 git 的 stderr 原样拼进 `RuntimeError`，remote URL 形如 `https://user:ghp_xxx@host/...` 时令牌会进入异常消息 → QMessageBox + telemetry；新增 `_redact_secrets()` 统一脱敏（7 例新测试覆盖粘贴 URL、git 回显、仅 token、ssh 形式、多个 URL）。

## 18. tool/gui 侧 AI 遗留退役

App 侧「伴学持久化与离线推理簇」19 文件 / 1,834 行已整体退役（退役边界与仍存活的伴学功能见仓库根 `docs/project-guide.md` §7.4–§7.5）。本节记录 tool/gui 侧的对应处置。

backend 15 个 `ai_*` 模块 + `ai/` 子包：全部在役，不动。逐一做过入边检测：`ai_pipeline` / `ai_phased` 是被 facade 收口的实现细节（门禁规则 6 强制 dialogs 不得直连，当前 `dialogs_pipeline=0`），wish 模式两端（工坊 facade + App `ai_wish_provider`）都是活功能，suggestions p0–p3 由注册方聚合，属设计好的插件结构。「AI 实验遗留」在这半边已经拆完。

唯一真死代码：`src/backend/experience/json_path_skill.py`（417 行）已删。JsonEditor 光标 JSONPath 解释器，生产代码零调用 —— 全仓 `src/` 与 `tool/` 内无任何引用，唯一引用方是它自己的 `tests/test_json_path_skill.py`（134 行 / 5 例），后者一并删除。这与 App 侧 companion 是同款病：只被测试引用。测试替生产兜住一条不存在的调用路径，是最坏的一种「有覆盖」—— 它让死代码看起来是活的。删除前已复核引用图，删除后由 §7 测试门禁 + §1 红线扫描兜底。
