# tool/gui 改进点审查（2026-10-20）

> 范围：`tool/gui/`（PySide6 创作者桌面工具，~40k 行 Python，280 个非 `__init__` 模块，
> 201 个测试模块 / 2875 例）。
> 方法：静态扫描 + 实际运行门禁脚本 + 定点代码核查。**每条都有可复现证据**。
> 结论先行：工程底子扎实（分层契约 + ratchet + 2875 例测试 + 原子保存 + 凭据 keyring），
> 但**门禁当前是红的**，且存在若干「规模已越界但无人拦」的问题。

---

## 修复状态（2026-10-20 当日施工完毕）

**全部条目已处理**。施工后：`guard-gui` exit 0、ruff 全过、
`full` **204/204**（204 模块 / 2885 例，110.7 s）。
逐条结果见 [`../../tool/gui/tests/BASELINE.md`](../../tool/gui/tests/BASELINE.md) 当日条目。

**两条误报，订正如下**（施工过程中发现，原文有误）：

| 原条目 | 订正 |
|---|---|
| **P1-3「OCR 在主线程同步逐页渲染」** | **误报。** `src/application/experience_handlers/multimodal.py:193` 已经走 `host._make_ai_worker(ocr_records, ...)`，OCR 本就在 worker 上。**真正**在 GUI 线程做全文提取 + base64 的是**附件添加**路径（`dialogs/ai/design_panel.py` 与 `dialogs/ai/generator_chat_coordinator.py`），已改为 worker（新增 `application/attachment_service.py`）。 |
| **P3-3「快捷键覆盖薄（只有 19 处）」** | **误报。** 19 处只是 `QShortcut` 的数量；`QAction` 上的快捷键（Undo / Redo / Ctrl+S / Ctrl+K / Ctrl+, / 降档）另有 6 处，合计覆盖完整。**真正缺的是 README 没有完整快捷键表**（Undo/Redo 从未出现在表里）—— 已补全表格，并顺带实现了缺失的 `Ctrl+F`（聚焦课程树过滤框）。 |

另有一条措辞订正：P0-2 原写「契约承诺但没接」。契约 §10 原文是
「剩余 13 处…属已知债务，**暂 warn 不 fail**」——即**有意**留 warn，
但它没有配套的数字上限，导致该数字事实上无约束。已改为**上限形态**的
`--max-app-dialogs-imports 13`（只减不增），并在契约里写清改动理由。

---

## 0. 一句话结论

**最该先做的三件事**：

1. **修门禁**：`make guard-gui` 现在 exit 1（`ui_backend` 171 > 基线 168），CI 同样会红。
   → 见 P0-1。
2. **接上被文档承诺、实际没接的棘轮**：`--fail-app-dialogs` 在契约里写着是棘轮，
   但 Makefile 与两个 CI workflow 都没启用它，`app_dialogs` 已涨到 13 且无上限。
   → 见 P0-2。
3. **修 4 处真会卡/真会崩的运行时问题**：worker 引用泄漏、telemetry 全量重解析、
   OCR 同步阻塞、关闭路径同步保存。→ 见 P1 组。

---

## P0 组：门禁本身有问题（必须先修）

### P0-1 `make guard-gui` 当前就是红的，CI 也会红

**证据**（实跑，非推测）：

```bash
cd tool/gui
python tool/check_ai_boundaries.py --fail-private --fail-dialogs-app \
  --fail-backend-app --fail-backend-ui --fail-backend-qt \
  --fail-dialogs-pipeline --fail-undeclared-host-access --fail-course-cli-binding
# REAL_EXIT=1
```

唯一失败项：

```
UI layer → src.backend import statements: 171     (基线 max_ui_backend_imports = 168)
```

**排他性验证**：把基线临时抬到 171 → `EXIT=0`；其余 ratchet 项全部在限内
（`broad_except=854`=基线、`except_pass=0`、`except_continue=0`、`style_hex=0`、
`cycles=2`=基线、`course_cli=0`）。**已还原基线，git diff 为空。**

**漂移来源**：基线最后一次更新是 `1794e329`（2026-09-29）。此后 3 个 commit 碰了 `tool/gui/`，
其中 `src/backend/course_delivery.py`（新增 608 行）被 `src/widgets/publish_dialog.py:460`
直接 import → UI 层直连 backend +1，累计到 171。

**问题本质**：`tool/gui/tool/guard_limits.json` 的重钉流程写在文件注释里
（"measure, update here, record the change in tests/BASELINE.md"），
但**没有任何自动化会提醒基线漂移**。基线是 2026-09-29 手工钉的，此后 3 个提交没人跑过门禁。

**建议**：
- 立即二选一：① 把 `src/widgets/publish_dialog.py` 对 `course_delivery` 的直连改为
  经 application 门面（推荐，符合契约意图）；② 抬基线到 171 并在 `tests/BASELINE.md` 记原因。
- **加一条 CI 守卫**：检查 `guard_limits.json` 的 mtime/内容哈希是否比上次 CI 跑的旧，
  或者更直接——把 ratchet 改成**「只许降不许升」**（超出即失败），这样任何新增 UI→backend
  直连都会在 PR 阶段被拦，而不是等数字漂了 3 个提交才发现。

### P0-2 `--fail-app-dialogs` 是死选项：契约承诺的棘轮没人执行

**证据**：

- `tool/gui/docs/ai_refactor_contract.md:261` 明确写着：
  > **app/application → dialogs 棘轮**：`--fail-app-dialogs` —— application 层 …
- 但 `Makefile` 的 `guard-gui` 目标、`flutter_ci.yml`、`gui_release.yml` **三处都没有这个参数**
  （其余 8 个 `--fail-*` 三处齐全，已逐个核对）。
- 实际计数：`application/app → dialogs imports: 13`，其中包括
  `src/application/workshop_controller.py:16` → `src.dialogs.workshop_window`、
  `src/application/resources_controller.py:102` → `src.dialogs.git_library_dialog`、
  `src/application/audio_controller.py:26` → `src.dialogs.generate_audio_dialog`。

**问题**：这条边界的方向是**反向依赖**（application 层依赖 UI 层），是分层里最该收敛的一种。
它既没有基线数字，也没人执行 —— 契约写了等于没写。

**建议**：① 给它一个基线数字（如 `max_app_dialogs_imports: 13`）并加进 `guard_limits.json`；
② 在三处补上 `--fail-app-dialogs`；③ 或明确改契约文档，写「application→dialogs 允许，
但新增需登记」——**别让文档说有、门禁没管**。

### P0-3 门禁有 2 处循环 import 挂账

```
CYCLE backend/experience/suggestions -> backend/experience/suggestions/ambient
CYCLE dialogs/git_library -> dialogs/git_library_dialog
```

基线 `max_import_cycles: 2` 正好卡在当前值。**这意味着任何一处新增循环都会红，
但现有两处已在基线内**——棘轮允许存量脏东西存在。`suggestions` 那处是包内自环
（`__init__` ↔ 子模块），影响小；`git_library` ↔ `git_library_dialog` 是真正的分层问题。

**建议**：`git_library` 那处收敛（`git_library_dialog` 拆出非 UI 的命令层），
然后把 `max_import_cycles` 降到 1。

---

## P1 组：真会卡 / 真会崩的运行时问题

### P1-1 worker 引用泄漏：`_LIVE_WORKERS` 可能永不释放

**证据**（`src/application/ai_request_worker.py`）：

```python
_LIVE_WORKERS: set[AiRequestWorker] = set()   # :48

def start(self, *args, **kwargs) -> None:
    _LIVE_WORKERS.add(self)                    # :90
    self.finished.connect(self._release_keepalive)   # :91  ← 释放挂在这个信号上
    super().start(*args, **kwargs)

def _release_keepalive(self) -> None:
    _LIVE_WORKERS.discard(self)                # :95
```

而 `src/dialogs/ai/generator_worker_hub.py:152-158` 的 `disconnect_worker_signals`
用**无参** `sig.disconnect()` 一次性断开所有信号，列表里**包含 `finished`**：

```python
for sig_name in ("result_ready", "error_occurred", "completed", "chunk_ready",
                  "usage_ready", "finished"):
    sig = getattr(worker, sig_name, None)
    sig.disconnect()          # ← 无参断开，断掉 finished
```

**后果链**：worker 被断开 → `finished` 不再触发 → `_release_keepalive` 不再执行 →
**worker 永久留在 `_LIVE_WORKERS` 集合里**。`src/dialogs/git_library/git_worker_hub.py:53`
也断 `finished`，同样问题。

- **内存泄漏**：每次生成/重试都漏一个 QThread 对象。
- **更严重的**：`_LIVE_WORKERS` 的存在意义是「防止最后一个引用被 GC 时 QThread 仍在运行
  导致进程 abort」（注释在 `:44-47`）。泄漏在这里**反而是保护**——但这意味着
  **取消/关闭时的清理路径根本不存在**，QThread 永远不会被 join。
- **影响面**：所有走 `GeneratorWorkerHub` / `GitWorkerHub` 的 AI 生成与 git 操作。

**建议**：
- `_release_keepalive` 改挂 `destroyed`（对象级信号，不受外部 disconnect 影响），
  或在 `disconnect_worker_signals` 里**排除 `finished`**。
- 加一条断言型测试：跑 N 次生成后 `len(_LIVE_WORKERS) == 0`。

### P1-2 telemetry 每次刷新全量重解析日志文件

**证据**（`src/infrastructure/telemetry.py`）：

```python
with self._log_file.open("r", encoding="utf-8") as f:
    lines = f.readlines()      # ← 全文件读进内存
for line in lines:
    record = json.loads(line)  # ← 每行重新 json 解析
```

`usage_summary()` 每次调用都重新读 + 重新解析整个日志。而
`src/application/experience_window_bridge.py` 的 `refresh_experience()` 在**每次交互刷新**时
调用 `sync_usage_today(host)` → `usage_summary()`。

**后果**：会话越长越慢；日志只有 `TimedRotatingFileHandler` 按天轮转（`:326-330`），
**没有体积上限**（见 P1-7），单文件可以涨到几百 MB → 每次刷新都把几百 MB 读进内存再逐行
JSON 解析。**这是最典型的「用久了就卡」根因。**

**建议**：
- `Telemetry` 维护增量游标（记录已解析到第几行 / 文件 inode+size），只解析新增部分。
- 或给 `usage_summary` 加 TTL 缓存（如 5 s）+ 文件大小上限。
- **必须先做**：加 `maxBytes` / `backupCount`（见 P1-7），否则增量优化也救不了历史大文件。

### P1-3 OCR 在主线程同步逐页渲染

**证据**（`src/backend/experience/ocr_skill.py`）：

```python
doc = fitz.open(str(path))       # :147
for page in doc:                 # :149  ← 主线程逐页
```

扫描版 PDF 的 OCR 要渲染每页 + 调 `pytesseract`，**全程在主线程**，无 worker 包装。

**后果**：导入一本扫描教材时窗口完全无响应（几十秒到几分钟），用户会以为程序死了。

**建议**：把 OCR 拆成 worker（现有 `AiRequestWorker` 模式可直接复用：QThread + 信号回传进度）。

### P1-4 关闭路径同步保存 + `wait(5000)`

**证据**：`src/application/save_host.py:95` `on_save()` → `execute_save()`；
`docs/long_term_backlog.md` 第 2 条已记账：
> 关闭路径保存异步化 —— `application/close_controller.py`（同步 `execute_save` + `wait(5000)`，T18 已限界）

**后果**：关窗时最长卡 5 秒。大课程（几百章节）同步 `adapter.save()` 本身就要几百 ms 到数秒。

**建议**：按 backlog 第 2 条的设计要求做——先做「保存完成前拒绝二次关闭」，
再把关闭路径改成异步。

---

## P2 组：架构与规模问题

### P2-1 UI 层直连 backend 达 171 处（dialogs 93 / widgets 55 / teacher 23）

**证据**：`tool/check_ai_boundaries.py` 的 `scan_ui_backend_imports()` 统计，
其中约四分之三是**函数内 lazy import**（代码注释自己说「three quarters of the existing edges
are of that kind」）——即为了绕开循环依赖而放在函数体内，等于把结构问题藏起来。

**典型**：`src/dialogs/textbook_import_controller.py:27-37` 一口气 import 10 个 backend 模块。

**影响**：UI 与业务逻辑耦合 → 无法单独测 UI、无法复用业务层、backend 改签名会同时炸一片 UI。
ratchet 已经在管（171 > 168 已红），但**只卡总量、不卡增量结构**。

**建议**：按 `dialogs/` 分域推进（教材导入、AI、git 三块各自收敛），每块收敛完把基线往下钉一格。

### P2-2 UI 层之间横向耦合无门禁

**证据**：

```
widgets → dialogs:   4 处
dialogs → widgets:  21 处
teacher → widgets/dialogs: 16 处
```

`check_ai_boundaries.py` 只管「UI → backend」，**不管 UI 内部横向依赖**。
`dialogs → widgets` 21 处是合理的（对话框复用组件），但 `widgets → dialogs` 4 处是反向耦合，
`teacher → dialogs` 也有（`src/teacher/question_cards.py:635` 借 `backend.anki_import._strip_html`
——backlog 第 3 条已记账，属「宣称的能力与实现不符」）。

**建议**：给 `widgets → dialogs` 加一条 ratchet（当前 4，基线 4，只许降）。

### P2-3 死代码批次（backlog 第 12 条）尚未开始

`docs/long_term_backlog.md` 第 12 条列了一整批零生产调用的东西：
`save_host.run_async_direct_save` / `save_host.on_save` / `ai_stream.iter_sse`、
palette 死条目 `quality.campaign_worst_n` / `unit.regenerate` / `section.edit` / `unit.edit`、
死设置 `ai_config_file_path` / `autoload` / `autosave`、
三阶段 stepper 死 UI（`workshop_window.py:570`）。

我独立复扫了一遍**零调用公开函数**，全仓仅 5 个：
`application/ai_runtime.py:39 empty_ai_runtime`、
`application/goal_controller.py:126 run_sandbox_for_host`、
`application/shell_views.py:510 current_view`、
`backend/course_media.py:56 media_ref_for_filename`、
`backend/experience/goal_generate.py:92 extract_lesson_from_section`。

**建议**：backlog 第 12 条做掉。它是**纯收益**（删了不会坏，因为没人调用），
且能顺手让 P2-1 的棘轮往下钉。

### P2-4 backlog 里的 9 条「有意延后」其实是功能未完成，不是可选优化

逐条看 `docs/long_term_backlog.md`，有几条其实是**功能链路没接通**，用户侧表现为「界面有个入口，
点了没反应」：

| # | 条目 | 用户侧症状 |
|---|---|---|
| 8 | ExperienceTimeline 整链接线或退役 | Dock「最近」恒空；⌘K 历史重放恒空 |
| 9 | AuthorMemory 写入 / ProjectMemory 读取接线 | 画像恒空；项目记忆无消费方 |
| 11 | defer/save-brief 状态持久化 | 写入但不落盘，功能实际不可达 |
| 13 | ReviewPanel 清待补裸 worker 接入 hub | 取消注入失败，无 `_closing` 守卫 |
| 14 | 取消语义收尾：单槽 worker hub 化 | 并发覆盖单槽仍不可取消 |
| 6 | 提取自动保存 status_hook 接线 | 提取失败**静默**（不进状态栏） |

**建议**：这些应该从「长期台账」升级为**产品待办**——它们不是「有空再做」的技术债，
是用户能感知的功能空洞。每条要么接线，要么删入口，要么在 UI 上明确标注「实验性」。

### P2-5 `_QUALITY_CACHE` 是无上限模块级 dict

**证据**：`src/backend/experience/context_bus.py:589`

```python
_QUALITY_CACHE: dict[str, tuple[...]] = {}
```

键是 section id，无淘汰、无上限、无失效策略（`:466` 读、`:509` 写）。
长会话 + 大量章节 → 只增不减。

**建议**：改 `OrderedDict` + LRU 上限（参照 `src/backend/ai_cache.py` 的
`maxsize=128` + `popitem(last=False)` 写法，AI 缓存那块做得是对的，可直接抄）。

---

## P3 组：产品与体验

### P3-1 调色板双端没有一致性门禁

**证据**：`AGENTS.md:122` 规定「调色板真源 `lib/core/theme.dart` ↔ `tool/gui/src/theme_tokens.py`」，
`tool/gui/src/theme_tokens.py:26-28` 也注明「mirrors lib/core/theme.dart — ADR 0033」。

我逐值比对结果：

- 8 个品牌色（`19324A` `1F727E` `2F7F8E` `145A64` `4A95A8` `78C7B8` `B85C3F` `EAD9B8`）
  **两侧完全一致** ✅
- Dart 侧共 61 色、Python 侧 66 色，**差集 33 色**（含 `FF1C2730` textPrimary、
  `FF52616B` textSecondary、`FF9CA3AF` textHint、`FF3498DB`、`FF9B59B6` 等）
  —— Python 侧有 Dart 没有的，但**没有任何测试锁住这个同步**。

**风险**：下次改 Flutter 主题色，Python 侧不会跟着改，且**门禁不会报**。

**建议**：加一个跨语言一致性测试（Dart 侧读 `lib/core/theme.dart` 解析 hex，
Python 侧读 `theme_tokens.py`，比对品牌色子集；或反过来由 Python 侧测试读 Dart 文件）。
`tool/gui/tests/test_theme.py` 已有雏形，扩一下即可。

### P3-2 i18n 名存实亡：280 处硬编码中文 vs 15 处接入

**证据**：

- `src/i18n/labels.py` 只做**字段名映射**（`field_label("frontHtml")` → 「正面 HTML」）。
- 全仓 UI 文案硬编码中文 **280 处**（`setText` / `setToolTip` / `setPlaceholderText` /
  `setWindowTitle` / `setLabelText` 带中文的调用），集中在
  `dialogs/ai/generator_panels.py`(18)、`dialogs/ai_lesson_helper_dialog.py`(10)、
  `widgets/experience_dock.py`(9)、`widgets/preview_host.py`(9) 等。
- `src/i18n/labels.py` 在 `src/` 外部只被引用 **15 处**，全部集中在 `src/teacher/`。

**判断**：这个工具是**中文单语内部工具**，i18n 本就不是需求。**真正的问题不是「没做 i18n」，
而是「有一个叫 i18n 的模块，让人误以为文案集中管理」**——新人改文案会去改 `labels.py`，
结果漏掉 280 处硬编码。

**建议**：要么把 `src/i18n/` 改名（如 `src/labels/`）去掉误导，
要么在 `labels.py` docstring 里写明「仅覆盖领域字段名，UI 文案是中文硬编码的，
不打算做全量 i18n」。

### P3-3 快捷键覆盖薄

**证据**：全仓 `QShortcut` / `QKeySequence` 只有 **19 处**（集中在 `shell_views.py`、
`workshop_window.py`、`ai_orbit.py`、`preview_host.py` 四个文件）。
`src/teacher/keyboard.py` 只有 48 行、只有 `[` / `]` 两个键的辅助逻辑。

**判断**：对「课程编辑器」这种高频工具，撤销/重做/保存/切换视图/搜索这五类操作应该有全局快捷键。
`src/teacher/keyboard.py` 的注释还明确说「Shortcuts must not steal keys from QLineEdit…」，
说明作者意识到了冲突问题，但覆盖面没做起来。

**建议**：至少补齐 `Ctrl+Z` / `Ctrl+Shift+Z` / `Ctrl+S` / `Ctrl+K`（命令面板）/ `Ctrl+F`，
并在 `README.md` 的「导航与视图」章节列一张完整快捷键表。

### P3-4 依赖声明与实际使用不一致（发布版会缺件）

**证据**：`pyproject.toml` 的 `dependencies` 只有 4 项（PySide6 / PyPDF2 / python-docx / keyring），
`ocr` / `voice` 是 optional extras。而 `src/` 里实际 import 了
`pytesseract`(2) / `PIL`(2) / `fitz`(1) / `pyaudio`(1)。

`turna_gui.spec` 的 `hiddenimports` **不含** `pytesseract` / `PIL` / `fitz` / `speech_recognition` / `pyaudio`，
而 `gui_release.yml` 只 `pip install "./tool/gui[dev]"`——**没装 ocr / voice extras**。

**后果**：发布版 exe 里 OCR 和语音功能**静默不可用**。这正是 backlog 第 17 条
（「版本链闭环：tag 回写 pyproject + extras 进包」）记录的问题。

**建议**：① `gui_release.yml` 改 `pip install "./tool/gui[dev,ocr,voice]"`；
② `turna_gui.spec` 的 `hiddenimports` 补上这 5 个模块；
③ 加一条「发布版冒烟」——装完 exe 后断言 `ocr_available()` 为真。

### P3-5 GUI 版本号恒为 0.0.0

**证据**：`pyproject.toml` 的 `version = "0.0.0"`，注释自己写着
> It is still 0.0.0 — the release process must set it before shipping.

`gui_release.yml` 打 `gui-v*` tag 时**不回写版本**（backlog 第 17 条）。

**后果**：用户报 bug 时 exe 版本号是 0.0.0，无法定位是哪个构建。

**建议**：tag 里解析版本号回写 `pyproject.toml`，或让 exe 直接读 git describe。

---

## P4 组：小而确定

| # | 问题 | 证据 | 建议 |
|---|---|---|---|
| P4-1 | `operations.log` 无体积上限 | `src/infrastructure/operations_log.py` 只是 `Telemetry` 的单例壳，写入路径无 `maxBytes` | 与 P1-2 一起加 `RotatingFileHandler(maxBytes=…, backupCount=…)` |
| P4-2 | 多进程共写轮转日志，Windows 午夜轮转会失败 | `telemetry.py:326` `TimedRotatingFileHandler`，GUI 多开时同写一个文件 | 换按 PID 分文件，或加 `delay` + 独占打开 |
| P4-3 | telemetry 初始化有副作用 | backlog 第 18 条：opt-out 仍建文件 | 延迟到首次真正记录时才建 |
| P4-4 | `.doc` 提取永不成功 | backlog 第 16 条 | `python-docx` 只吃 `.docx`；要 `.doc` 得靠外部转换器，或明确在 UI 上禁用 `.doc` |
| P4-5 | `chevron-right` 图标不存在 | backlog 第 16 条 | 图标名无存在性校验 → 加一条测试遍历所有图标名 |
| P4-6 | `usability_smoke.py` 的 docstring 指向不存在的清单 | `tests/usability_smoke.py:16` 引用 `docs/authoring/teacher-usability-checklist.md`，全仓不存在（仓库根 `docs/authoring/` 下只有 7 个别的文件） | 补文件或改引用 |
| P4-7 | 静默吞异常 20 处 | AST 扫描：854 个 `except Exception` 中 834 个有日志，**20 个完全静默**，集中在 `application/credential_store.py`(3)、`dialogs/git_library/memo.py`(2)、`repo_browser.py`(2) 等 | 逐个补 `logger.debug`（`credential_store` 那 3 处是 keyring 探测，可保留但要留日志） |

---

## 做得好的地方（别在重构里弄坏）

- **原子保存**：`src/backend/course_io.py` 的 `write_files_to_dir` + 备份 + `os.replace` 语义，
  且备份会跳过点目录（避免「每次备份体积翻倍」的历史 bug 已有回归测试锁定）。
- **凭据存储**：`src/application/credential_store.py` 优先 OS keyring，
  不可用时**明确警告**用户「将回退到 QSettings（base64 混淆，非加密）」——降级路径对用户透明。
- **git token 不泄漏到明文 URL**：`src/backend/git_library.py:389` 的注释记录了
  「B13: token 曾以明文出现在 http:// URL 里」的修复。
- **错误报告脱敏**：`61cea8ce fix(gui): redact absolute paths before an error report leaves the machine`。
- **AI 请求全在 worker**：`dialogs/ai_error_analyzer.py:209`、`dialogs/ai_fix_dialog.py:212`
  都走 `AiRequestWorker`，主线程无同步网络调用（我逐个核过）。
- **类型标注覆盖 98.4%**（4015 个函数中 3950 个有返回标注），远高于同类 Python 工程。
- **ratchet 机制设计正确**（问题在执行，不在设计）：`except_pass=0` / `except_continue=0` /
  `style_hex=0` 三项**零容忍**且长期保持为 0。

---

## 建议的施工顺序

| 批次 | 内容 | 依据 |
|---|---|---|
| **第 1 批（半天）** | 修 P0-1（门禁红）、P0-2（接上 `--fail-app-dialogs`）、P1-1（worker 泄漏） | 这三条是「门禁失效」与「资源泄漏」，其他修复的验证都依赖门禁是绿的 |
| **第 2 批（1–2 天）** | P1-2 + P4-1 + P4-2（telemetry 增量解析 + 日志上限）、P2-5（缓存上限） | 都是「用久了就卡/就涨」的同类问题，可合并做 |
| **第 3 批（1 天）** | P0-3（收敛 git_library 循环）、P2-2（加 widgets→dialogs 棘轮）、P3-1（主题一致性测试） | 门禁覆盖面补齐，让后续收敛有强制手段 |
| **第 4 批（按产品决策）** | P2-4 的 6 条功能空洞：每条**接线 / 删入口 / 标注实验性**三选一 | 需要产品判断，不宜技术单方面决定 |
| **第 5 批（清理）** | P2-3（backlog 第 12 条死代码批次）、P3-2（i18n 去误导）、P4-4~P4-7 | 纯收益，可随时做 |
| **独立发布链** | P3-4（extras 进包）、P3-5（版本号闭环） | 动 CI 与打包，不与其他批次耦合 |

---

## 核查方法（可复现）

```bash
cd tool/gui

# 1) 门禁当前状态（会 exit 1）
python tool/check_ai_boundaries.py --fail-private --fail-dialogs-app \
  --fail-backend-app --fail-backend-ui --fail-backend-qt \
  --fail-dialogs-pipeline --fail-undeclared-host-access --fail-course-cli-binding

# 2) 逐条 ratchet 计数
python tool/check_ai_boundaries.py --verbose | tail -30

# 3) 静默吞异常扫描（AST）
#    854 个 except Exception → 834 有日志 → 20 完全静默

# 4) 硬编码中文文案扫描
#    setText/setToolTip/setPlaceholderText/setWindowTitle/setLabelText 带中文 → 280 处

# 5) 零调用公开函数扫描 → 5 个
```

> 注：`ruff` 未安装在本机 managed Python（`No module named ruff`），本次未跑 lint；
> 其余结论均来自实际执行的门禁脚本 + AST/文本扫描 + 定点代码阅读。
