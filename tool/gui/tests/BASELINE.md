# GUI Python 测试基线

> 记录 `tool/gui/tests/` 下的用例数与关键覆盖项，便于每轮变更后快速对比回归。
>
> **本文件的结构**：顶部「当前基线」是唯一权威的当前数字，**只增不删**（按日期倒序追加）；
> 其余 640+ 行是逐日施工流水，**只作为历史记录**，其中的数字反映当时的快照。
> 查当前值请只看顶部，不要翻历史条目。

 ## 当前基线

- **2026-09-29（课程交给 App：描述符、turnapack、等级壳、媒体路径）**：
  创作者工具补上内置课登记与 `.turnapack` 导出、章节 CEFR 下拉（正文与 index 壳一起写）、
  先修保存时同步壳、题目与资源表的媒体选文件（只复制进 `media/`，教师预览不播放）。
  **201 模块 / 2875 例**（发现器 `countTestCases`；上一条目 200 / 2860，+15 =
  `test_course_delivery` 14 + 元数据等级 1）。`full` **201/201**（84.9 s）。
  媒体按钮用具名槽 `_on_pick_media`，避免匿名 `connect(lambda)`。ruff `src`+`tests` 全过。
  `ci`（L0+L1）48 模块全过；新模块因课程读写链碰到 Qt，留在 L2，随 `full` 一起跑绿。

- **2026-09-28（施工质量复审返工：三路独立审查 33 项发现全部处置，200 模块全绿）**：
  对上一条目的施工做三路独立审查（backend / 应用与 UI / 测试与工具链），确认无 P0，
  1 项 P1、8 项 P2、十余项 P3，本轮全部处置。**200 模块 / 2860 例**；`full` 200/200
  （93.2 s）；ruff 全过；guard 全链 exit 0 且计数零漂移（broad_except=854 /
  ui_backend=168）。返工明细：
  - **P1（回归修复）**：`load_via_session` 在 open worker 里调 `session.open_course`，
    经 host 属性代理提前改写 `session.course_dir`，使 `bind_loaded_course` 读到的
    "旧目录"已是新路径 → **File▸Open 静默跳过 `prepare_course_switch`**（切课清理/
    指标冲账全丢），且跨线程 clear QUndoStack。修：worker 侧只做 `adapter.load`，
    session 重绑归主线程 `bind_loaded_course`（补 `last_imported_section_id` 重置）；
    新增 `B1WorkerLoaderIsPureTest` 锁定。
  - **P2 修复**：①push 等待保存改挂 `result_ready/error_occurred`（保存**失败**不再
    照常推送旧树）+ `finished` 兜底防按钮锁死 + connect 后复查竞态；②save 暂存目录
    建在课程目录内会**污染每个备份**（备份体积翻倍、还原带回 `.turna-save-*`）——
    `backup_json_files` 跳过全部点目录，新增 `test_backup_skips_dot_directories`
    回归 + 真课程端到端探针；③断路器 HALF_OPEN 试探名额从 `can_auto_dispatch`
    （纯检查，burst 拒绝不该吃名额）移到 `record_dispatch`（真实派发），探针验证
    三态语义；④validate_loop 裸 str 防卫漏了缓存命中分支——抽
    `_validator_problems` helper 两处共用；⑤affected 档 `\bstem\b` 过配
    （`main`→199 模块）——收紧为"import 行 或 引号内 `./stem` 前缀"双模式；
    ⑥`guard_limits.json` 键名打错原会静默解除该项检查——缺键/多键直接 exit 1，
    `--help` 不再被缺文件连坐；⑦批量重生 `_finish_batch` 补齐与单路径同款 C3 修法
    （guard 持有穿过人审、verify 移到接受后 push 前）；⑧B2 回归测试的 Windows 路径
    断言改 `str(Path)` 可移植（否则 ubuntu CI 必红）。
  - **P3 清理**：4 个测试文件的 `RegistryTray` import 移到 sys.path 引导后（恢复
    直跑能力）；8 处失去用途的 `JobRegistry` 函数级 import 与 1 处 `GenerateResult`
    import 删除；runner 超时消息 f-string 化；`lesson_is_empty` docstring 同步新
    语义；`course_adapter.load` duration payload 改用尝试目录（与 record_error 对账）；
    契约文档 §15 残留手抄 163 改指向 guard_limits（叙述性数字标注历史快照）；
    design_panel 测试 PhaseC 死键换真实形状。
  - **复审确认无需改动**（抽查样本）：regenerate 单路径 try/finally 全 return 触发、
    批量 guard key 两端一致；dispatch 非自动清 token 对挂起 offer 幂等无害；三个新
    QUndoCommand 无悬挂引用；settings 五处接线齐全；tray 替换零残留；BASELINE 全部
    数字复现。**复审新记台账**：#19 git 重载路径的脏保存覆盖（交互设计项）、#20
    HALF_OPEN 试探 TTL 复用 reset_timeout（有界无害）。

- **2026-09-28（逻辑审查修复计划施工：批次 A/B 全量 + C/D/E 主体，200 模块全绿）**：
  按仓库外《Turna GUI 逻辑审查与修复计划（2026-09-28）》完成施工。**200 模块 / 2858 例**；
  `full` **200/200 全过**（83.8 s，含新增回归模块 `test_logic_review_2026_09_28`，7 例）；
  ci 档（L0 gate + L1 fast）48/48（`test_course_release` 因 B3 引入 `course_io→telemetry`
  传递 Qt 依赖被导入图分类器正确移入 L2 档，L1 纯档 49→48 属预期迁移非丢测）；
  ruff 全过；`make guard-gui` 全链 exit 0。分批明细：
  - **批次 A（A1–A10 全部）**：JobTray API 断裂 20 处机械替换（解锁词性对齐/批量润色/
    补全待补/多模态/截图解释/语音 6 组技能）；跨盘保存 `mkdtemp(dir=course_dir)` + except
    分支不再回滚内存、新增 `_repair_course_dir_after_failure`（含 prune，兼修 B6）；
    `_refresh_validate_after_ai` 四处补 `success_message` + **修正 4 个测试 fake 的无参签名**
    （正是这些 fake 掩盖了 TypeError）+ 回归断言；content_quality f-string 未定义
    `{field}`→`fname`；intent_router「基于附件填充」移到宽词「填充」之前；幽灵设置三件套
    **接线**（`experience_screenshot_explain`/`experience_voice_palette`/
    `experience_preview_fix_suggest` 补 Settings 字段+持久化+设置页复选框）；配套修
    `run_item_chip` 缺参（undo_stack 经父链解析，缺则本地栈）与 `_chip_modal_fallback`
    遞弃 kwargs（改走 `instruction_edit.setPlainText`）；ai.usage reader 兼容平铺/嵌套
    两种形状（测试改真实形状+锁旧形状兼容）；`record_error` 优先 `exc.__traceback__`；
    **门禁基线单一真源** `tool/gui/tool/guard_limits.json`（checker 自动读，Makefile/两
    workflow/契约文档停止手抄；文件损坏直接失败），broad_except 重钉 **854**（846+本轮
    防御式兜底净增），ui_backend 168 不变；`count_broad_except` 复用 `_is_broad_except`
    （堵 `except (Exception, X)` 绕过，实测计数不变）。
  - **批次 B（B1–B6 全部）**：`CourseAdapter.load` 失败回滚 `course_dir` + `open_course`
    先载入后改状态 + 两条打开路径统一走 `load_via_session`（File▸Open 此前绕过 session）；
    git pull/rebase/stash-pop/切分支成功后若克隆=当前课程经 `open_requested` 强制重载、
    push 前等待 `_save_worker`；发布门槛改验**内存模型**（staged 临时目录），发布/音频
    直存后补 `setClean + _mark_saved`；批量 APPEND_AS_NEW 复用深拷贝+`rewrite_ids_deterministic`
    （预改名使 `resolve_action` 落入无重写的 append 分支——这是冲突真因）；
    `resource_refs` 补扫 `readingPassage.linkedWordIds/linkedExpressionIds` 与课级
    `linkedGrammarPointIds`（对齐 overview_stats）。回归测试 7 例
    （`test_logic_review_2026_09_28`：打开失败/会话失败/克隆重载×3/发布 setClean/批量嵌套 id）。
  - **批次 C（C1–C7、C9–C13）**：断路器——异步 handler 不再在 dispatch 即记成功
    （探 `_experience_worker.isRunning()`），fill/resources 六个回调补
    `record_async_outcome`，HALF_OPEN 落实单试探（`_half_open_probe_at`）；auto-apply
    token——fill/resources 全部"无 offer 结束点"（早退/拒绝/_on_err/链尾）+
    dispatch 非自动路径无条件清 + 同步 handler 完成后无 pending offer 即清；
    批量重生入 ConflictGuard（`{action}:batch`）+ `_regen_on_ok` 守卫保持到人审、
    verify 移到接受后 push 前 + resources 三 LLM handler 补 `is_busy_ai` 前置；
    `_on_node_selected` 接 `apply_tree_selection`（FocusRing/pin/Copilot 不再读陈旧选择）；
    **DesignController 三分派收敛到 `facade.generate_course`**（新 `_on_generate_result`
    统一分发；facade 停止 re-export legacy `request_course`；13 个测试改真实形状）；
    `coerce_problem_messages` 缺 message 生成占位 + 裸 str 不再按字符拆分；
    DesignController 终态分支补 `_disconnect_worker`；预览 busy-Esc 真取消
    （`cancel_in_flight_ai_jobs`）+ chip 取消不再弹"失败"；**C10/C11 高危路径 undo 化**：
    `SwitchLessonTemplateCommand`（切课型，LessonEditor 接受 undo_stack 并三处接线）/
    `ReplaceLessonContentCommand`（词汇生成整课覆盖）/ `SetListeningPhaseTypeCommand`
    （听力阶段切型，含删题确认）；`lesson_is_empty` 扫全部容器（legacy 课不再误判空）；
    content_quality READING hints 对齐 `readingTrueFalse/readingShortAnswer`、删
    不存在的 `matchWords`。
  - **批次 D/E**：D4 `_apply_undo_limit` 落地实现（两处直调改走它）；D1–D3/D5–D9
    "接线或退役"决策记入 `docs/long_term_backlog.md` #8–#12；C8/C16/E6 同记 #13–#16。
    E1：affected 档——git rename 行双侧解析、字符串 patch 目标纳入匹配（原仅 import）、
    共享 fixture（`tests/_*.py`）改动大声告警；E2：runner 每模块 300s 硬超时 + 串行重试
    一次。**顺带发现并修复 HEAD 上 `gen_module_tree --check` 本就红**（前次会话删文件未
    重生成树，guard-gui 因此必红），已 `--write` 重生成（backend 114→113、experience
    55→54、ui 9→10 为真实计数）。
  - **遗留**：`test_experience_fill_stubs_batch` 的 ClassVar 样本字典被 handler 原地
    改写（模块内二跑会假败，runner 每模块独立子进程故 full 不受影响）——预存隔离债，
    未在本轮修；broad_except 854 中本轮净增约 8 处均为"永不抛"防御兜底。

- **2026-09-28（施工核验发现的回归修复：full 档卡死 + 4.16 记账落库）**：
  对四批修复做施工效果核验时发现，**上一条目记录后 HEAD 上 `run_gui_tests.py full`
  根本无法跑完**。回归链：收口批次的 `909ea261` 把 design_panel 的 OCR 询问从
  `QMessageBox.question` 改为 `safe_question`，配套的 22 处测试重指向落在
  `75e1c8ab`，但**漏了 `test_experience_ocr.py`**——它仍 patch 调用方命名空间的
  `QMessageBox.question`（正是上一条目自己记录过的教训：函数内导入必须 patch
  `src.application.ui_guard`）。离屏下 `safe_question` 返回 `default_yes=False`，
  流程落到 `_add_attachment_paths` 尾部的**裸 `QMessageBox.warning`**——离屏模态
  永阻塞，该模块挂起、runner 无超时机制、full 永不结束（机器上遗留了两对此前进程
  卡死时留下的僵尸 python，已清理）。**勘误**：上一条目的「full 198/198 全过」实为
  卡死模块被丢弃后的计数，模块实有 199 个；2851 例的统计数倒是对的（含未跑完的那 1 例）。
  修复（两处）：
  - `design_panel.py` 附件无法读取的警告改走 `safe_warning`（离屏→状态栏兜底；
    真机 toast 优先，符合 P1 Toast 批次的迁移原则，design_panel 本就在其后备名单上）；
  - `DesignPanelScannedPdfOfferTest` 两处 patch 重指向 `src.application.ui_guard`
    （`safe_question`→True / `safe_warning`），并删去测试内随之无用的 QMessageBox 导入。
  验证：`tests.test_experience_ocr` 38/38（1.7 s，原先无限挂起）；**`full` 199/199，48 s**；
  ruff 全过。另：修复计划 §4.16 的七项长期项台账落库 `docs/long_term_backlog.md`
  （已挂 docs 索引，`check_docs_index` 0 孤儿）——此前该记账只存在于仓库外的计划文档里。
  交互式冒烟（真 UI）仍待人工。
- **同一核验还发现 `make guard-gui` 自接线起就是红的**（门禁由最后一个提交 `77c1d7fe`
  于 18:54 接线，四项棘轮超标；同口径复核批次前基线 `eb99db50`：broad_except=812 /
  ui_backend=163 / host_drift=8 / except_pass=9，用当前版 checker 实测）。本轮修零两项：
  - **host_drift 4 → 0**：批次自身引入的 `host._open_worker` / `host._last_saved_at` /
    `host._show_load_error`（course_lifecycle 的异步打开 + bind_loaded_course）按既有
    模式补 ExperienceHost 协议申报——是补台账，不是清债；
  - **except_pass 3 → 0**：`main_window_shell.cancel_in_flight_ai_jobs` 的状态栏提示、
    `publish_dialog._restore_version_snapshot` 的版本还原/报告重建两处，按棘轮声明的
    目标（logged handler）改为 `logger.debug(..., exc_info=True)`。
  **未修、待决策两项**（修复批次净增的技术债，见下方明细，需另开批次清理或按契约
  程序上调棘轮数字）：
  - broad_except **846 > 816**：批次净增 +34，分散 20 个文件（前三：course_lifecycle +8、
    save_host +5、ui_guard +4，都是批次改动最重的文件，属「Never raises」防御式兜底）；
  - ui_backend **168 > 163**：批次净增 +5（experience_tab 重置熔断器、vocab_table 与
    resource_editor×2 的共享引用助手、preview_host 的 undo 集成——都是批次功能自身的
    UI→backend 直连，reroute 需逐点改 facade）。

- **2026-09-28（审计遗留三项的收口批次）**：把上轮审计列出但超出当时计划范围的
  三项全部处理完，另补上一个残缺提交引发的隐私泄漏。**199 模块 / 2851 例**
  （较上轮 2841 ⇒ +10）；`full` **198/198 全过**；ruff 全过；L0 gate 5/5 exit 0。分 6 个提交：
  - **裸 `QMessageBox.question` 从 36 处降到 0**（业务侧）。这是审计 MAJOR 5：
    原计划 4.14 只点了课程树的 2 处，实际扫出 36 处，横跨 12 个文件；它们无视沉浸式
    auto-confirm 档，等于把 4.8 关掉的模态门又打开。
    - 其中 **10 处是三态**（含两处最危险的未保存退出确认：关窗 / 切换课程目录），
      两态的 `safe_question` 无法表达「保存 / 丢弃 / 取消」，故新增
      **`safe_question3`**（返回 `YES`/`NO`/`CANCEL`）到 ui_guard。
      `auto_choice` 强制在**每个调用点显式指定**，因为正确答案并不一致：
      未保存提示用 `YES`（无人值守时拦下关窗会卡死运行，而保存能保住工作），
      破坏性 git 操作（删分支 / 删备忘 / reset --hard / 强推 / 丢弃合并）一律 `CANCEL`
      （「什么都不做」是唯一安全的无人值守答案）；拉取冲突保留其三个真实结局
      （rebase / stash 后拉取 / 放弃）。
    - 其余 25 处两态按各自**原有的默认按钮**推导 `default_yes`，语义逐条不变：
      删教师条目/阶段/子课、丢弃合并、放弃 AI 改写、清除作者画像、清操作日志、
      教材库导入与覆盖、工坊阶段切换、设计审阅与预览采纳、Goal 合并清单，
      以及资源编辑器的删除 / 批量删除 / 替换引用（后两处在 T16 之后仍是裸框）。
      资源包导入是本模块最后一处三态，现也走 `safe_question3`，该文件再无裸确认。
    - **防回归**：`test_ui_guard.py` 新增一条仓库级断言——除 `ui_guard.py` 外，
      任何模块出现 `QMessageBox.question(` 即失败；另有一条断言 ui_guard 自身恰好
      持有那 2 处实现。
  - **7 个测试文件的 22 处 patch 重定向**：原先 patch 的是调用模块的
    `QMessageBox` 类属性，而守卫是在**函数内**导入的（`from … import safe_question`
    写在语句前），因此 patch 调用方命名空间根本拦不住——必须 patch
    `src.application.ui_guard`。这一点在改写过程中真实卡住过一次，记在此处以免重犯。
  - **3.2 打开与保存的并发防护**（审计列为最高价值压测项，现按代码层面收口）：
    课程打开在 worker 上跑 `adapter.load()`，会整体重设 `adapter.sections`，
    而工具栏/菜单在此期间仍可用——此刻触发的保存会把半加载的课程写盘并与之竞态。
    `execute_save` 现在在**单一保存漏斗入口**拒绝（返回 `ok=False` + 状态栏提示），
    `open_course_flow` 另行置灰 `save_action` 让状态先于点击可见。
  - **硬编码颜色补完**（审计「未能验证」项）：`experience_dock.py` 的 AI 额度文本原用
    `#dc2626`（除浅色外各主题下都是暗底暗字，且不属于任何主题的 error 色）；
    `result_preview.py` 三处钉死 `#E74C3C` / `#FF9F43`。现统一读 `current_palette()`
    并取 `error_text` / `warning_text`，暗色主题因此拿到各自的可读变体。
  - **错误上报的路径脱敏（补上一个残缺提交，并修掉一处真实的隐私泄漏）**：
    `tests/test_error_report_redaction.py` 曾报 `ImportError: _redact_paths`。追查
    下来是**一个残缺提交**：另一条流的 `8ce10491`（09-28 10:32）把该测试纳入版本树
    （提交信息自述「was never committed before」），但只改了
    `generator_worker_hub.py` 与测试两个文件，**没有提交配套实现**——`_redact_paths`
    全历史从未存在，只活在未提交的工作区里；该 WIP 于 16:21 被丢弃后测试转红。
    更要紧的是这暴露了一个**当下正在生效的隐私问题**：`_build_prompt()` 把完整
    traceback + 80 行 telemetry + 操作上下文原样发给模型端，而 traceback 基本就是
    `File "D:/Users/<name>/..."` 帧——等于把用户名与课程所在目录送出机。UI 提示原本
    写的是「日志中可能包含文件路径，请确认后再继续」，把这个风险甩给用户肉眼把关。
    现按测试契约实现 `_redact_paths`（绝对路径压到文件名，URL 与无路径文本不动），
    并接在 `_build_prompt()` 的**三个分支**上：traceback、上下文值、telemetry 行
    （旧日志早于本轮遥测脱敏，磁盘上的历史行不保证干净）。脱敏只作用于发送内容，
    屏幕上的原文不变；UI 提示同步改为如实说明「文件路径会在发送前脱敏」。
    新增 2 例锁住「脱敏接在出口」——只有函数存在而没人调用，正是本条的起因。
  - **备注（重要，非本批次引入）**：`tests/test_error_report_redaction.py` 报
    `ImportError: cannot import name '_redact_paths'`。HEAD 版
    `src/dialogs/ai_error_analyzer.py` 来自 09-14 的 `874fc294`（提交信息自述
    「半成品接线 + 死代码清理」），该版本本就没有 `_redact_paths`；此前能通过是靠
    09-27 另一条流**未提交的工作区版本**，该 WIP 于今日 16:21 被丢弃后测试转红。
    本批次的提交从未涉及这两个文件，故未擅自代为修复（需按该重构的原意补回或调整测试）。
  - 交互式冒烟（真 UI）仍待人工；新增两项值得手点：沉浸式/auto 档下切档与删除不再弹框、
    打开课程期间保存被拒且动作置灰。

- **2026-09-28（批次三/四 独立审计后的加固批次）**：对 33 个提交的 `25d11b42~1..a069e755`
  做独立只读审计，判定 **FAIL**（两处招牌承诺不成立），已逐条修复并分条提交。
  收集 **199 模块 / 2840 例 / 0 失败**（较批次四 2806 ⇒ **+34**，无新增模块）。
  `full` 199/199（77 s）；ruff 全过；L0 gate 5/5。已修：
  - **3.18 回滚会留下无法撤销的孤儿 section（审计 MAJOR 1）**：`ImportAiSectionCommand.redo()`
    先 append section 再合并资源，故合并失败时 section 已进课程；而 `_push_or_collect`
    只在 redo 成功后才把命令放进 collector，回滚循环看不到它——UI 报「已整体回滚」
    但课程里多了一个 Ctrl+Z 也删不掉的 section。三处修复：命令**先登记再应用**；
    资源快照改在 `finally` 记录（部分合并也能回滚）；单节路径（直接 push）在 redo 抛错时
    自行回滚并把命令标记为惰性——因为 `QUndoStack.push` 是**先登记再调 redo 且失败后
    不移除**，残留条目否则会让 Ctrl+Y **复活**一个已报失败的导入。
  - **3.11 托盘取消够不到教师 AI 芯片（审计 MAJOR 4）**：芯片以 `kind="ai"` 注册任务
    （故飞��启用「取消」），但 worker 挂在 owner 控件上，取消函数只看宿主三个属性，
    于是「AI 改题中…」按取消会回「没有可取消的 AI 任务」。芯片现将 worker 镜像到顶层
    窗口，取消函数纳入该槽位。
  - **3.8 批量删除不做引用检测（审计 MAJOR 2）**：单行删除报引用、批量删除不报，
    选 20 个被 40 课时引用的词条只得到一句「validate 会校验」。批量路径现用新增的
    `merge_resource_reports()` 聚合并走同一份 `delete_confirm_text`；同时把该文件里
    仅剩的单行删除与「替换引用」两处裸框改走 `safe_question`（资源包导入的三态框保留，
    已在源码注明原因）。
  - **4.12 脱敏漏了嵌套 dict 与 URL 凭据（审计 MAJOR 3）**：`payload["metrics"]["path"]`
    原样落盘；含 `/` 的 URL 被 `_looks_like_path` 抢先命中，query 里的 API key 从未检查。
    现递归 dict，远程 URL 走专属分支只遮蔽凭据型 query 值。
  - **4.12 另补四处泄漏（自查）**：含空格的路径（Windows 常态）、
    `file://` URL、句中路径（异常消息）、短路径把用户名留在末两级里
    （`/home/<user>/x.json` → 现丢弃 home/Users 根下的用户目录段）。
  - **3.14 普通模式对齐流被整个丢弃（审计 MINOR 6，本批次自引入的回归）**：为不污染
    JSON 编辑器而 `return`，结果聊天框的「对齐中…」没有任何输出。现按 target 分流：
    alignment 进流式聊天框（长文本先走计数），只有 explain 在普通模式仍丢弃。
  - **4.9 提取覆盖单槽位（审计 MINOR 7）**：暂存改按 `(语言, 语言)` 分键的 dict，
    否则换语言对会静默丢弃上一条；删除不存在的覆盖会谎报「已暂存删除」；删除后不再把
    字段重置为内置默认（否则下一次保存会把默认当自定义覆盖写进去）。
  - **4.8 战役建议 id 恒定（审计 MINOR 8）**：`scope={}` 使 `proposal_id_for` 得到常量
    id——角标永不重亮，且一次「稍后」就把整个会话的战役永久归档。现携带 `weak_count`
    （条目数）与首要 section。
  - **T12 重置按钮的裸框（审计 MINOR 9）**：改为 toast 优先、`QMessageBox` 兜底。
  - **NIT 11**：`_record_window_duration` 曾以 `record_event(duration_s=…)` 调用，而该
    函数无此形参——TypeError 被外层 except 吞掉，窗口时长遥测**从未记录过**。
    改用 `record_duration()`（毫秒）；实测 1.5s 窗口现写入 `duration_ms 1500.0`。
  - **文档同步**：`docs/a3-companion-ambient-design.md` 七处仍写 `dismiss_count >= 3`，
    与 T10 改成的 `MAX_DISMISS = 4` 矛盾，已一并订正（含原本就写错的退避公式
    `2^min(dismiss_count, 3)` → 代码实为 `2^min(dismiss_count - 1, 3)`）。
  - **审计判定为 CORRECT 的部分**（已实测，非仅阅读）：4.1 选中分发不变量（12 种操作后
    面板与树选中始终一致，无重复通知）、3.18 复合 undo 往返算术、3.11 不会取消保存
    worker、3.15 取消判定与实际抛出点一致、4.5 退避算术与持久化兼容、4.13 删除 EN 表后
    未知 locale 仍回落 zh、4.11 两个调色板都确有对应键、3.17 skip 默认值端到端生效、
    3.9 编码链顺序、4.9 SSH/提取切分无残留读取方、3.2 重入保护。
  - **仍未处理（超出原计划范围，需另开批次）**：
    ① 全项目仍有 **36 处裸 `QMessageBox.question`**（线性流 3、教师模板 3、
    教材库/工坊/蓝图各 2、以及 `close_controller.py` 与 `course_lifecycle.py`
    的**未保存退出确认**——最危险的两个），当前 30 处走 `safe_question`；
    这些在沉浸式 auto 档仍会弹模态，等于把 4.8 关掉的门又打开。
    ② 仍有硬编码颜色：`experience_dock.py:68` 的 `#dc2626`、
    `result_preview.py:212-216,425` 的 `#E74C3C`/`#FF9F43`，与 4.11 同类但不在教师面。
    ③ 3.2 的课程加载虽已移入 worker，但只禁用中央区——工具栏保存与关闭路径仍可用，
    `execute_save` 可能与后台 `adapter.load()` 并发（无稳定复现，属设计风险，建议压测）。

- **2026-09-28（GUI 易用性修复 批次四：一致性 / 文案 / 隐私，4.1–4.15）**：
  `python -m unittest` 逐模块收集 **199 模块 / 2806 例 / 0 失败**（上批 2724 例 ⇒
  **+82**，新增 `test_attachment_preview.py`、`test_teacher_header_palette.py`、
  `test_i18n_labels.py`、`test_ai_error_messages.py` 四个模块）。分档实测见下方各档统计；
  `ruff` 全过；L0 gate 5/5 exit 0。依据 `Turna_GUI_修复计划_2026-09-28` 批次四，
  4.1–4.15 全部修复并按问题粒度分条提交（4.16 为长期项记账，本轮不做）：
  - **T1 课程树 ↑/↓ 不更新详情面板**：`node_selected` 只由 `itemClicked` 发出，而方向键
    不触发该信号，详情面板因此停留在上一个节点。改为在 `currentItemChanged` 上按节点
    ref 变化分发；`select_*` 保留无条件通知（「定位此节点」依赖它）并自持分发，
    保证只发一次；重建后若落到不同节点（选中课时被删、回落到父节点）仍会通知。
  - **T2 「教师过滤」名不副实 + 提示刷屏**：侧栏按钮实为全局教师模式开关，tooltip 改为
    「教师模式（详情面板切换出题视图）」；模式提示按消息缓存 10s 去重（按消息而非「上一条」，
    快速 on→off→on 也只解释一次），仍为 toast 非模态。
  - **T3 侧栏搜索一次输入过滤两遍**：同时接了 `textChanged` 与防抖信号，改为只保留防抖。
  - **T5 附件预览「引用方式」死单选**：`inline`/`standalone` 的取值全项目无人读取，
    删除单选组（及随之孤立的 `_reference_mode`），改为一行说明「附件将随当前消息一并发送」。
  - **T10 「稍后」三方语义打架 + 60min 档死代码**：`MAX_DISMISS` 由 3 改 4（原先第 3 次
    「稍后」直接归档，注释承诺的 15/30/60 升档永远到不了 60）；tooltip 改为真实升档说明；
    折叠行 ✕ 改走新 `discarded` 信号 + `on_ambient_discarded`（立即归档、**不消耗 defer 次数**，
    此前与「稍后」同信号，点 4 次 ✕ 就被永久归档）；延后后的状态栏文案改为「已稍后，稍后将
    再次提醒」，升档归档另给「多次稍后，本条已归档」。
  - **T11 Copilot 角标只按 action_id 记已读**：换 section 不再亮角标。改用
    `proposal_id_for()`（action_id + scope 指纹，与 ambient 提案同源）作 seen key。
  - **T12 熔断器 opaque 模式完全静默**：熔断后无任何提示，与「没有建议」无法区分。
    opaque 模式改给中性一行「AI 自动应用已暂停（稍后自动恢复）」且不泄漏熔断内部状态；
    设置 ▸ 体验 OS 增加「重置熔断器」按钮（接到已有的 `reset_circuit_breaker()`）。
  - **#10 切 Active 档弹模态战役队列**：模式开关直接 `exec()` 战役对话框。改为非模态——
    作为建议入队 Copilot + 状态栏给出条目数与 Ctrl+K / 战役 入口；用户真去点建议时
    `handle_quality_campaign` 行为不变。
  - **T17 设置「取消」不还原**（经确认按「accept 时持久化」执行）：
    ① SSH 密钥路径原在 `_sync_to_settings` 里即时落盘（打开设置点「取消」也会改掉下次用的凭据）
    → 移入 `_apply()`；② 提取 Prompt「保存覆盖」原自己写文件（同一屏两套取消语义）
    → 改为对话框内暂存、accept 时由 `commit_extraction_pending()` 写入，
    「取消」与窗口关闭都经 `discard_pending_changes()` 丢弃。**有意不改** Git 远程目录与令牌：
    每条都有独立子对话框与其自身 OK，且删除路径本就写着「此操作不可撤销」，
    把它们暂存到设置的「取消」后面会与该文案自相矛盾并丢失已确认的工作。
  - **T13 Ctrl+D 克隆非 Lesson 节点静默**：README 曾宣称「克隆当前选中的节点」。
    Section/Unit 上现在给 toast 说明仅支持课时，README 同步更正。
  - **T20 教师头部硬编码深色**：浅色主题下深色面包屑不可读、徽标配色与全局不符。
    改为每次调用读取 `current_palette()`（面包屑 `text_secondary`，徽标 `text_on_accent` on `accent`），
    随主题切换生效。
  - **T21 遥测记绝对路径且无开关**：本地日志原样记录课程绝对路径。在唯一写入点统一
    `scrub_payload()`（按字符串判根目录，不依赖 `Path.is_absolute()`——它在 Windows 上对
    `/opt/x` 返回 False 会漏网），路径压到末两级、home 前缀折叠为 `~`；
    新增 `telemetry_enabled`（设置 ▸ 外观 ▸ 隐私，默认 True 以免升级即静默关闭）。
  - **T22 i18n EN 死表 + 教师卡片文案漂移**：`FIELD_LABELS_EN` 等三张英文表无任何设置项、
    CLI 或调用点可达，全部删除（保留 `locale` 形参作为将来接线的落点）；
    reorder-sentence 卡片的两个标题原是内联中文字面量，改为 `field_label()` 统一取词。
  - **T20(b) 课程树删除确认走裸 QMessageBox**：5 处确认（Lesson/Unit/Section、批量删除、
    批量套预设）改走 `ui_guard.safe_question`（headless 不阻塞、沉浸档 auto_confirm_scope
    生效），均 `default_yes=False`；被引用 Section 的提示框保留原样（它是失败告知，不是问题）。
  - **#11 provider 错误直抛原文**：401 原本显示为 `HTTP 401: {"error":...}`。
    新增 `describe_http_error()` / `describe_network_error()`，先说原因与该改什么
    （401→检查 Key、429→额度/重试、DNS/SSL/超时各自点名），provider 原文降为短尾巴保留；
    `parse_json_obj()` 同样给出行列号与常见原因。
  - 备注：交互式冒烟（真 UI）仍待人工——方向键换节点详情跟随、树搜索单次触发、
    「稍后」与 ✕ 分流、设置取消不落盘、熔断器提示与重置、浅色主题教师头部可读性、
    遥测日志中无绝对路径、Ctrl+D 非课时有提示。

- **2026-09-28（GUI 易用性修复 批次三：阻塞与边界态，18 条）**：
  `python -m unittest` 逐模块收集 **195 模块 / 2724 例 / 0 失败**（上批 2673 例 ⇒
  **+51**，新增 `test_teacher_preview_flow.py`、`test_ai_merge_preview_dialog.py`
  两个模块）。分档实测：`full` **195/195，77 s**；`ruff` 全过；L0 gate **5/5
  exit 0**。依据 `Turna_GUI_修复计划_2026-09-28` 批次三，18 条全部修复并按问题
  粒度分条提交（`3.1` 先于 `3.10`/`3.11`，与依赖顺序一致）：
  - **#15 设置「测试连接」主线程阻塞 15 秒**：探测改走 `AiRequestWorker`，按钮先置灰
    并改文案「测试中…」再返回，成功/失败都经 worker 信号恢复；超时读 `ai_timeout`。
    新增 3 例。
  - **#16 打开课程主线程读盘 + 工坊角标每次上下文变化读盘**：`open_course_flow` 的
    load 移入 worker（冻结中央区 +「打开中…」）；角标加 30s 结果缓存，仅在保存成功
    （`save_host._after_success`）与教材导入完成（`workshop_controller`）定点失效，
    工坊窗口可见时绕过缓存。附带把 `sync_save_state_label` 的裸 `except: pass`
    改为 `logger.debug`（纯装饰性失败，不该静默）。新增 2 + 若干例。
  - **T18 关闭路径保存同步 + `wait()` 无超时**：`wait(5000)`，超时 `safe_warning`
    并 `event.ignore()` 保留窗口；同步 `execute_save` 保留（关窗需确定性），前置
    「正在保存…」。新增超时分支用例。
  - **#17/#18/#19 + T15 教师模式边界态组**：判断题缺 answer 时预览与编辑器判定统一为
    `bool(item.get("answer", False))`（编辑器补黄色提示，不新增第三态）；试做预览包
    `QScrollArea`（640×720，480×400 下限）；未选择/空参考答案分别提示「请先选择答案」
    与「未提供参考答案，无法判定」；删除末项修正 `correctIndex` 并同步
    `correctIndices`、恰好 2 项时禁用并给 tooltip。新增 `test_teacher_preview_flow.py`
    7 例 + `test_question_cards.py` T15 用例。
  - **T16 教师词库删除无确认无引用检测**：抽出共享
    `resource_refs.delete_confirm_text`，`vocab_table` 与 `resource_editor` 两处同用；
    `default_yes=False`。新增 5 例（拒绝保留、确认文案带引用、接受删除、零引用文案、
    默认安全）。
  - **#20 CSV 只认纯 UTF-8**：修在共享 `_read_csv`（utf-8-sig → gbk → locale 链），
    全部失败走 problems 通道而非抛异常；新增 `api.read_csv_file_with_problems` 供 GUI
    经既有 problems 列表渲染，CLI 与 GUI 一并受益。新增 GBK / BOM fixture 各一。
  - **T13 PreviewHost Enter/Esc 误触**：三个 QShortcut 改
    `WidgetWithChildrenShortcut`（PySide6 用属性赋值，无 `setShortcutContext`）；去掉
    offer 抢焦点，改为点击条内时聚焦。
  - **T14 AI 任务不可取消 + 单飞死路**：启用 JobTray 已预留的 `job_cancel_requested`
    信号（仅 AI 类任务 enable），`main_window_shell.cancel_in_flight_ai_jobs` 协作式
    取消 experience/palette/diagnose worker（**save worker 明确排除**）；8 处单飞提示
    补「（可在任务托盘取消）」。新增 2 例；`test_adversarial_matrix` 的 D11 契约由
    「取消恒禁用」改写为新不变量「取消只对 AI 开放、绝不 `.kill()`/`.terminate()`」，
    并清理 `job_tray.py` 中已过时的 no-op 说明。
  - **#21 发布失败不回滚版本 bump**：`_do_publish` 前快照 version/expressionsVersion，
    失败回调还原并刷新报告，重试只 +1。新增 2 例。
  - **#22 音频对话框打开前静默保存**：`adapter.save()` 移到 `exec()==Accepted` 之后、
    收集条目之前，期间状态栏「正在保存课程…」，失败仍走现有取消提示。
  - **T3+T4 请求中可切模式、流式写错编辑器**：`set_busy` 统一禁用 `mode_combo`（两条
    lane 都空才恢复）；`on_chunk_rendered` 对非 JSON target 不再写 `json_edit`，wish
    的 JSON 流补「生成中… 已接收约 N 字符」计数。新增 8 例（含两条 lane 交叉态）。
  - **T6 wish 取消被当失败弹 Critical**：判定抽成共享 `ai_cancelled(message)`
    （放 worker_hub），`ai_lesson_helper_dialog` 命中即显示「已取消」并返回。
  - **T7 文件解析失败连弹两个错误框**：改在对话框侧按 **result 对象身份** 去重（step
    通道 + on_done 各触发一次展示），而非删掉 on_done（它还负责恢复 pick 按钮）；
    不同 result 仍各弹一次，重选文件仍可再次看到恢复选项。新增 3 例。
  - **T8 合并冲突看不到两边内容、默认「覆盖」吞手工编辑**：`MergeAction` 增加
    `existing` 字段，预览显示两侧摘要（现有课时/交互项数，tooltip 列出标题）；
    replaced 默认不勾；批量面板「处理」默认改「跳过」、「合并」改名「合并（覆盖同名
    单元）」；重新勾选 unit 会把子课时恢复为 replace。新增 7 例。
  - **T9 批量导入 = N 条 undo、无进度**：新增 `CompositeImportCommand`（跳过首次
    redo，构建期已应用），`import_bulk` 只 push 一条，单节抛异常则整批回滚并如实
    重分类计数，导入循环发「导入中 (i/N)」。新增 5 例（含 undo 深度 == 1、
    undo/redo 往返、单节批次不受影响、中途失败回滚且计数诚实）。
  - 另修一处批次三验证中发现的崩溃：`_ButtonSizePolicyFilter` 未 parent 导致窗口销毁
    后 Qt 向已释放指针派发 Polish 事件（access violation），改为 parent 到窗口
    （独立 commit，不属于任何编号条目）。
  - 本轮 `ruff` 顺带清掉 3 处遗留告警（`test_teacher_preview_flow.py` 两处 `l`
    歧义命名、`test_question_cards.py` 未使用变量——后者补上了测试名承诺的 back 编辑
    断言）。
  - 备注：交互式冒烟（真 UI）仍待人工——测试连接不卡 UI / 20 题预览可滚动可提交 /
    GBK 词表可导入 / 发布失败重试不叠版本 / 托盘取消真取消。

- **2026-09-28（GUI 易用性修复 批次二：承诺≠行为，7 条；2.7/2.9 已随批次一）**：
  `python -m unittest` 逐模块收集 **193 模块 / 2673 例 / 0 失败**（上批 2654 例 ⇒
  **+19**，新增 `test_auto_apply_scope.py`）。分档实测：`full` **193/193，74 s**；
  `ruff` 全过；L0 gate **5/5 exit 0**。依据 `Turna_GUI_修复计划_2026-09-28` 批次二：
  - **#6+#7 AutoApplyToken 泄漏 + 自动路径模态 Diff（链式，同 commit）**：
    `resolve_auto_apply_state` 的 host-token 分支收紧为「strip 上确有待应用动作」
    （`_host_preview_has_pending`）；新增 `resolve_auto_apply_for_offer` 供 offer
    落地时消费 token（异步 offer 仍自动应用）；`PreviewHost` 在 offer 自动应用/
    apply/discard/clear 时解绑 host token（token 跟随 offer 生命周期），自动应用
    期间以 `auto_confirm_scope` 包住 apply 链；fill 三处 worker 回调（空课填充/
    清待补/补全听力）auto 路径改走 `_offer_auto_preview`（PreviewHost strip），
    手动路径复用同一 apply/discard 闭包走 SectionDiffView；presence_drive 调度期
    文案改「AI 执行中…」不再谎称「已自动」，成功提示由 offer 完成时发出。
    新增 `test_auto_apply_scope.py` 9 例（严格/offer 双解析、消费解绑、auto 无模态、
    文案）。
  - **#8 清理资源建议统计全局、执行只处理当前节**：建议 action_id 从
    `resource.fill_stubs`（当前节）改为现成的全局批处理器 `resource.fill_stubs_batch`
    （v4.65 B1+B2，全局 stub 谓词 + FieldPatch + 确认 + Undo）——口径天然一致，
    无需新写循环。`test_experience_context` 断言随契约更新。
  - **#9 wish「重试解释」重跑完整课程生成**：抽出 `_start_wish_explain`，新增
    `on_wish_explain_retry`（入参是现有 `_draft_json`，引用不变）；retry 按钮改调
    它。新增 2 例（explain worker target + draft 身份不变 / 无草稿不发请求）。
  - **#10 批量合并整批取消仍部分导入**：整批取消（bulk resolver 返回 None）→
    **中止整个导入**（全部 section 返回 `cancelled`，零 undo push）；单冲突取消
    （单节 merge 对话框取消）→ `confirm_continue` 回调（safe_question，默认否）问
    是否继续其余 N 章，拒绝则余下全部取消；counts 新增 `cancelled`，workshop 汇总
    三分「完成 / 部分完成 / 已取消，未做任何更改」。旧
    `test_bulk_resolver_cancel_skips_all_merges` 断言的正是 bug 行为，改写为三条
    新契约用例（含 undo 深度断言）。
  - **#11 Ctrl+S 绕过 SavePipeline**：新增 `run_async_pipeline_save`（Soft 在 GUI
    线程先跑、慢链在 worker、`execute_save(prefetched=…)` 复用同一出口组合 outcome
    与 UI 钩子）；`_on_save`/`_save_course_async`/palette 全部接入；
    `run_async_direct_save` 降级为兼容 shim（无生产调用方）。新增 3 例（Soft 先于
    worker、palette reason 透传、保存后总览失效钩子）。
  - **#13 总览校验徽标缓存永不失效**：保存成功钩子（管线 `_after_success` 与
    direct shim）调 `CourseOverview.invalidate_validation_cache()`（仅曾拉取过才重
    取）；拉取期间徽标显示「校验: …」；`#validation` 旁常驻 ⟳（`#validate`）强制
    刷新链接。新增 3 例（保存后重取落地 / 未拉取过 no-op / ⟳ 常驻）。
  - 备注：手动冒烟（四种保存入口一致、Immersive 手动确认恢复、重试解释不重生成、
    整批取消零导入）留待人工；离屏回归已覆盖逻辑路径。批次三起 3.10
    （PreviewHost 快捷键作用域）接在 2.2 之后按链实施。

- **2026-09-28（GUI 易用性修复 批次一：P0 数据丢失/功能坏死，6 条）**：`python -m unittest`
  逐模块收集 **192 模块 / 2654 例 / 0 失败**（上批 2633 例 ⇒ **+21**）。分档实测：`full`
  **192/192，74 s**；`ruff` 全过；L0 gate（E1+E2 冒烟）**5/5 exit 0**。本批依据
  `Turna_GUI_修复计划_2026-09-28`（37 条）做批次一，每条修复均带同 commit 回归测试：
  - **#1+#14 切换课程静默丢稿**：新增 `course_lifecycle.open_course_flow` /
    `confirm_course_switch` 单一入口（dirty 三选一：保存并打开走
    `execute_save(REASON_COURSE_SWITCH)`、失败即中止；headless 沿用 close_controller
    的自动丢弃契约）；`open_repo_path` / `on_open` / `on_new_course`（含新建前置确认，
    先于 `init_new` 改写 adapter）全部接入；加载成功统一走 `bind_loaded_course`
    （补 `_last_saved_at = None`，状态栏不再显示上一门课的保存时间）。新增
    `ConfirmCourseSwitchTest` / `OpenCourseFlowTest` / `RepoSessionOpenPathsTest`
    （clean/dirty × 保存成败 × 取消 × 加载失败 + 三入口委托，含"确认先于新建对话框"
    顺序断言）。
  - **#2 工坊设计面板取消后永久卡死**：`DesignController.cancel()` 改**同步终态落地**
    （断信号 → worker.cancel → 立即复位 `_worker` + busy），不再依赖可能永不到来的
    终态回调；stale 守卫已验证可吞掉迟到信号。新增 `DesignControllerCancelTest`
    （取消后 `is_busy` 立即 False 且可再生成；迟到 result/error/progress 无污染）。
  - **#3 工坊内嵌向导导航全是死按钮**：`TextbookImportDialog` 嵌入模式下
    `_go_to_step` 改发 `step_switch_requested`（摘页后 `_stack` 为空，翻栈是 no-op）；
    `WorkshopCanvas` 以 `_STAGE_FOR_STEP` 把向导步骤翻译成画布阶段（素材/知识/导入）。
    顺手修同病：`ResourceReviewTable` 新增 `rows_replaced`（`set_rows` 必发），画布的
    "首条知识行自动跳知识阶段"从死路径（`rows_changed`）接到活信号。新增嵌入导航
    断言（`_goto_import_preview` / 返回审校 / 恢复选项 / STEP_EXTRACT / 自动跳转）。
  - **#4 编辑 Git 远程 OK 必抛 AttributeError**：`edit_remote_dialog` 内部变量
    `dlg = QDialog(dlg)` 遮蔽 SettingsDialog，尾部调错对象 → 改名 `edit_dlg`，表格刷新
    恢复。审计同文件其余 handler 与 `dialogs/git_library/` 无同款遮蔽。新增
    `GitRemoteEditTest`（OK 后 `update_remote` + `_populate_remotes_table` 各一次）。
  - **#5 审校表「删除选中」删全表且无确认**：改用 `selected_rows()`（与「AI 修复选中」
    同一"选中"语义）；无选中给行内临时提示（不弹框）；多选删除过 `safe_question`
    （"此操作不进撤销栈"）；按钮加 tooltip 澄清 勾选≠选中。旧 `test_batch_delete`
    断言的正是 bug 行为，已改写为四条新契约用例。
  - **#12/N1 AI 错误分析拿到 "NoneType: None"**：`show_load_error` 与
    `GeneratorWorkerHub.offer_error_analysis` 都在非 except 上下文调
    `traceback.format_exc()` → 改 `AiErrorAnalyzerDialog.analyze_exception(parent,
    message)`（对齐 `ai_lesson_helper_dialog` 的既有正确用法）。新增
    `ErrorAnalysisMessageTest` 断言分析器收到的是真实错误消息。
  - 备注：交互式冒烟（真 UI 手点五条验收路径）留待人工；离屏回归已全部覆盖逻辑路径。

- **2026-09-28（工坊重设计验货修复批：T4 折叠失效 + 摘页空白回归）**：`python -m unittest`
  收集 **192 模块 / 2633 例 / 0 加载错误**（上批 2628 例 ⇒ **+5**）。分档实测：`full`
  **192/192，78 s**；`affected` 24/24；`ruff` 全过；边界门禁 **exit 0**（计数不变）。
  本批是对 09-27 工坊重设计的**质量验货修复**——四阶段画布的三个运行时缺陷全部
  有离屏渲染 + 真实 Windows 平台双重复现：
  - **摘页手术留隐藏标志（真回归，最重）**：`QStackedLayout.removeWidget` 会把页留成
    **显式隐藏**，而布局跳过显式隐藏的控件——三个摘出页（素材/知识/导入）在真实屏幕
    上**整页空白**、几何冻结在栈时代的 640×480（`win.grab()` 会无视隐藏照常绘制，
    所以离屏截图与测试全没拦住；旧三栏把页塞进 QTabWidget，由 tab 机制代管显示，
    故旧代码无此问题）。修法：`_page_shell` 摘页后 `page.show()` 清标志。新增回归
    断言 `test_ripped_pages_are_not_explicitly_hidden`。
  - **折叠组不折叠（T4 目标落空）**：Qt 对未勾选的 checkable `QGroupBox` 只**禁用灰显**
    不收起——未勾选的高级组仍占 228/207 px，聊天只剩 70 px，窗口地板被顶到 777×1016。
    修法：`design_panel_build._wire_collapsible` 按勾选态显隐直接子控件（记住本来
    隐藏者）。新增断言钉**折叠效果而非勾选标志**（`test_collapsed_groups_actually_fold`
    / `..._expand_on_check`）。
  - **窗口地板超标（980×640 失效）**：三处最小宽/高驱动项——review 面板 7 按钮单行
    （~750 px）与质量维度 chips 单行（510 px）改 `FlowLayout` 换行；`_hint_label` 补
    `setWordWrap(True)`（单行中文长句最小宽 504 px）；轨道 chips 区从无钳制改为
    **36–72 px 可生长带**（T1 的"无钳制"测试改写为"growable band"契约）。窗口地板
    777×1016 → **888×618**，`resize(980,640)` 生效；新增
    `test_window_can_hold_the_980x640_default` 与 `test_draft_chat_is_the_growing_surface`
    （760 高时聊天 > 两个折叠组之和且 > 150 px）。
  - 顺带：`_CANVAS_DESC` 过期三栏文案改为四阶段描述（只存在于隐藏的 `_page_desc`，
    无用户可见影响）；`widgets/flow_layout.py`（旧）并入 `widgets/ui/flow_layout.py`
    （`spacing=` → `hspacing=/vspacing=`），调用方 workshop_canvas / teacher/shell_header
    / test_theme 全部迁移，旧文件删除。
  - **PySide6 踩坑记录（续）**：③ 显式隐藏的控件被所有布局跳过（不分配几何），
    摘页/摘控件后必须清隐藏标志；④ `QScrollArea` 无上限时会用巨大默认 sizeHint
    抢 stretch，带状区要同时给 min 与 max。

- **2026-09-27（工坊重设计收口：§5 快赢 + T1–T5 全部落地）**：`python -m unittest`
  收集 **192 模块 / 2628 例 / 0 加载错误**（上批 2573 例 ⇒ **+55**）。分档实测：`full`
  **192/192，77 s**；`gate` 33/33 + E2 5/5；`ruff` 全过；边界门禁 **exit 0**。
  边界门禁计数收口：`broad_except` 816 → **810**，`app_dialogs=13` / `cycles=2` /
  `ui_backend=163` / `host_drift=0` 其余不变。
  - **§5 快赢 ①②③④⑤⑦ 各自独立提交**（⑥「删除伴学 9 张表」属 App 侧另批，见
    `docs/official-anki-migration/`，不在 tool/gui 范围）。其中 ① 是**真 bug**：
    右键菜单每次开都泄漏一个 `QMenu`，并重复注册一个与 `keyPressEvent` 抢 Ctrl+D 的
    `QAction`（快捷键复制整个选中集，菜单项只复制右键命中的单个课时）。
  - **T1 轨道横排化**：`AiOrbitWidget` 参数压成一行，chips 走 `FlowLayout` 自动换行，
    **解除 36–48 px 高度钳制**，`orbit_zone` 取消 `minHeight(160)`，核心钮 110×110 →
    72 px 圆钮与按钮并排；信号与所有控件名（`topic_edit` 等）保持不变。
  - **T2 四阶段画布**：新增 `src/widgets/workshop_canvas.py`（`WorkshopCanvas`）替换
    `unified_workspace.py`（git 识别为改名）。素材 / 知识 / 草稿 / 导入各占整幅；气泡
    池 reconcile、生成链、聚焦摘要、逐项目 UI 状态全部平移。UI 状态由
    `left_tab/right_tab/splitter` 改为 `stage`（**旧键废弃不迁移**：tab 下标在新布局
    里没有对应页面）。首次抽出知识点自动切「知识」，`draft_ready` 自动切「导入」。
  - **T3 窗口新壳**：阶段灯升级为**真导航**（点击切阶段，当前阶段主色加粗；「导入」灯
    在已有导入章节时仍走定位），替掉 `focus_left_tab/focus_right_tab` 的 duck 调用；标题
    并入阶段栏；底栏删「关闭」；边距 12→8；**1100×720 → 980×640**。顺带修既有缺陷：
    摘页后 `TextbookImportDialog` 的 `dragEnterEvent/dropEvent` 收不到拖放，现由素材页
    `eventFilter` 转发。
  - **T4 聊天主角化**：草稿阶段对话整幅；池摘要换 `ElidedLabel`（单行省略，UI 套件新增
    `ui/labels.py`）；聊天输入 2 行起步、聚焦长 1 行（`QLineEdit` 不换行，故上限取 3 行
    而非方案里的 5 行）；对话头新增「查看大纲 →」（新 `outline_requested` 信号，画布接
    去切阶段）与「展开」（复用 `ChatExpandWindow`，渲染/流式/发送三者同步）。大纲树
    220→400、摘要 140→220、问题 chips 去掉 560 px 宽上限。
  - **测试面**：新增 `tests/test_ai_orbit.py`（16 例）与 `tests/test_workshop_canvas.py`
    （26 例，替换 `test_unified_workspace.py` 的 14 例）。
  - **两处 PySide6 踩坑记录**（都稳定复现，别再踩）：① 冲刷 `DeferredDelete` 事件做泄漏
    断言会连带销毁**前面用例**遗留的待删对象 → `0xC0000005` 访问违例；改记 `deleteLater()`
    是否被调用，完全确定且不碰事件队列。② `QWidget` 没有 `enabledChanged` 信号，禁用态
    联动要走 `changeEvent` + `EnabledChange`。
  - **门禁补正**：`src/` 内**禁止匿名 lambda 信号连接**（`test_signal_lifecycle`）。T2/T3
    各引入一处（`stage_changed`、气泡池弹层按钮），已改为具名方法
    `_on_canvas_stage_changed` / `_on_pool_popup_add_all`。

- **2026-09-27（tool/gui 侧 AI 遗留退役）**：删除 `src/backend/experience/json_path_skill.py`
  （417 行）+ `tests/test_json_path_skill.py`（134 行 / 5 例）⇒ **192 -> 191 模块**。
  - 该模块（JsonEditor 光标 JSONPath 解释器）**生产零调用**：全仓 `src/` 与 `tool/`
    内无任何引用，唯一引用方是它自己的测试。测试替不存在的调用路径兜底，是最坏的
    一种「有覆盖」——让死代码看起来是活的。
  - 连带效果：边界门禁 `broad_except` **816 -> 811**（被删模块含 5 处宽泛 except），
    其余计数器不变（`app_dialogs=13` / `cycles=2` / `ui_backend=163`）。全库例数待本轮
    收口时以 full 档实测回填。
  - 退役记录写入 `tool/gui/docs/ai_refactor_contract.md` §18；同时确认 backend 15 个
    `ai_*` 模块 + `ai/` 子包**全部在役，不动**（facade 收口的实现细节 + 插件化
    suggestions，不是遗留）。

- **2026-09-27（右键菜单泄漏 + Ctrl+D 歧义）**：`test_course_tree` 33 -> **39 例**（+6，
  `CourseTreeContextMenuLeakTest`）。全库例数待本轮收口时以 full 档实测回填。
  - 缺陷：`course_tree._on_context_menu` 每次右键新建 `QMenu(self)` 但从不
    `deleteLater()`，空菜单路径同样泄漏；同时每次新建一个带 `Ctrl+D` 的 QAction
    挂到树上，**与 `keyPressEvent` 已有的 Ctrl+D 处理重复注册**（多选时行为还不一致：
    菜单项只复制右键命中的单个课时，快捷键复制整个选中集）。
  - 修法：菜单体包进 `try/finally` 并 `menu.deleteLater()`（含空菜单早退路径）；
    「复制 Lesson」改为与 `detail_panel` 同一写法的 `menu.addAction(text, slot)`，
    **不带快捷键**，slot 复用 `_selected_lesson_ids()` 语义；删除
    `_on_act_dup_lesson_triggered` 与随之无用的 `QAction` import。
  - 测试要点：子菜单工厂用 `QMenu` 子类 stub 掉阻塞的 `exec()`；**不要**用
    `sendPostedEvents(None, DeferredDelete)` 冲刷销毁来断言泄漏——它会连带销毁
    前面用例遗留的待删菜单，PySide6 下稳定 0xC0000005 访问违例（同类崩溃连跑三次
    才定位）。改为记录 `deleteLater()` 是否被调用，断言完全确定、不碰事件队列。

- **2026-09-27（核查补批）**：`python -m unittest` 收集 **192 模块 / 2573 例 / 0 加载错误**。
  分档实测：L1 pure **49**（+1）；`full` **192/192，~75 s**（`-j 4`）。
  - 新增 `tests/test_check_ai_boundaries.py`（18 例）：对 `check_ai_boundaries.py`
    全部 11 条门禁规则逐条注入探针的负向矩阵。起因：复核发现
    `scan_backend_qt_imports()` 在整改施工中被误改为复用 backend→UI 正则，
    `--fail-backend-qt` 对任何输入都报 0（施工引入的回归，已修复并验证
    探针在→exit 1 / 干净树→exit 0）。
  - 同批修正：`docs/README.md` 里指向不存在的 `gen_docs_index.py` 的断链改为
    如实描述 `check_docs_index.py` 校验器；`run_gui_tests.py` docstring 中
    「ci 档 = PR 默认」的口径改为「快速本地回路」（三个门禁入口实跑 full）。

- **2026-09-27（整改批次）**：`python -m unittest` 收集 **191 模块 / 2555 例 / 0 加载错误**。
  分档实测：`ci`（L0 gate + L1 fast）**48/48，~11 s**；`full` **191/191，~73 s**（`-j 4`）。
  较 2026-09-22 的 2541 净增 14 例：
  - 新增 `tests/test_error_report_redaction.py`（7 例，错误报告外发前路径脱敏）；
  - 新增 `tests/test_git_secret_redaction.py`（7 例，git 诊断信息里的 URL 凭据脱敏）；
  - `test_user_action_filter.UserActionFilterTest` 由 3 例扩到 7 例（输入改记指纹、
    指纹稳定性、opt-in 记录原文、空输入不记录；并修掉 `target` 标签泄漏正文的路径）。
  - 同期修复两个**整模块挂起**的模块：`test_shell_views`（41 例 / 19.9 s）、
    `test_app`（41 例 / 36.6 s）—— 根因与修复见 `docs/ai_refactor_contract.md` §14。
  - `ci` 档的 L1 集合由 113 个模块**修正为 48 个**（分档判定由文本正则改为真实
    import 图，修正 65 个「实际 import Qt 却被判为纯逻辑」的假阳性，0 误伤）。
  - `-j/--jobs` 默认由 1 改为 0（=自动并行），原先只在 `-j>1` 才生效的「最慢优先」
    调度不再是死代码；`-j 1` 仍可显式选择旧的单进程路径。
- 日期：2026-09-22；`ruff check tool/gui`（src + tests）为 0，并已接入 `make lint-gui` 与 CI。用例数为 **2541**（该批只清 lint，不增删测试）。
- 日期：2026-09-20（P0 异步批次 + P1 Toast 批次 1，见下两节）；`python -m unittest` 收集 **2541 例 / 0 加载错误**（2537 + `test_shell_views` 新增 `NotifyToastResolutionTest` 4 例）

## 2026-09-20 P1 Toast 批次 1（确认类模态框 → Toast，28 处）

用例数 2537 -> 2541（+4，`test_shell_views.NotifyToastResolutionTest`）。验证：受影响模块逐进程全绿（shell_views 解析测试 + resource_editor + ai_fix_controller + publish_dialog 合并 25 例；review_panel + settings_dialog 合并 27 例；`test_shell_views` 全量与 `ci` 门禁另跑）；ruff 7 文件归零。

| 项 | 变更 |
|---|---|
| 动机 | 141 处 `QMessageBox.information/warning`（不含 question）里约一半是单行结果告知——每次「已导出/已保存/无需修正」都弹模态框打断操作流；ToastHost 建好后仅 2 处采用 |
| 基础设施 | `shell_views.notify_toast` 升级三级 host 解析：① `host.toast_host` 显式属性（壳层）；② 嵌入控件经 `window()` 上溯（中央栈内视图→MainWindow）；③ **可见**独立窗口/对话框懒建 ToastHost 并缓存回 `toast_host`。懒建仅 `isWindow() and isVisible()`——测试驱动未 show 控件永远走 fallback 弹回 QMessageBox，存量断言零破坏 |
| 迁移原则 | 单行结果告知 → `notify_toast` + **调用方模块内** QMessageBox fallback（部分测试 patch 模块命名空间整 QMessageBox 符号，集中 helper 会绕过补丁）；question 决策 / 多行详情 / critical / 成功即关窗 → 保留模态 |
| 迁移点位 | resource_editor 5（批量删除未选中/CSV 合并/CSV 导出/查重无果/资源包导出）· ai_fix_controller 5（找不到节点×2 warning 6s/无需修正/无法定位批次/已分 N 批）· review_panel 10（任务进行中×2/已应用补全/未加载课程×2/无同 id/无需修复/质量已较好/无可恢复草稿/质量维度分数）· git_library_tab 4（选中远程/令牌已存/已删/无令牌）· extraction_prompt_tab 3（覆盖已存/无覆盖/已删回落）· publish_dialog 1（报告已导出；发布成功随后 accept 会随窗销毁故保留模态） |
| severity 约定 | 完成类=success、指引/空结果=info、警示=warning（duration 6000ms） |
| 存量 | 未迁移模态（含 question）共 185 处 grep 计数（information/warning/critical 142 含 28 处 toast-fallback 行，纯模态 114 + question 43）；下批候选：teacher 窗口系（preview_window/vocab_table/item_ai_chip/template_editors/linear_flow）、generator_flows/design_panel/audio_controller warning 系、git_library 对话框（sync/lan_share/memo）、textbook_library、ai_edit_controller |

## 2026-09-20 P0 异步批次（发布对话框 + 总览校验移出 UI 线程）
- 全量用例（上次记录）：2499 collected；基线已知 `test_textbook_controller.LoadFileAsyncTest.test_stale_load_result_is_ignored` 曾在全量单进程 discover 下确定性失败——**单跑与模块级运行均通过**（2026-09 复核，疑似顺序敏感的上下文污染，根因未定位；全量单进程 discover 本身在本机还会疑似空转不终止，见下），命令：
  ```bash
  QT_QPA_PLATFORM=offscreen python -m unittest discover -s tests -p "test_*.py"
  ```
- 记录勘误 ×2（历史条目原文保留）：① 2026-09-07 基线头所写「2 个 defer_resurface 永久 skip」经核实不存在（该文件 4 例无任何 skip 标记）；② 2026-09-06 adversarial 瘦身条目所写「保留 10 例独有覆盖」中 D14×4 与 D27 共 5 例实为与常规测试逐字或更强重复，已于本轮删除。
- 文档勘误：历史条目中的 `tool/gui/aiEnhance.md` 已退役删除，现行 AI 能力文档为 `docs/ai_configuration_and_features_report.md`（历史条目的章节号 §8/§13 指当时文件，不再有效）。

## 2026-09-20 P0 异步批次（发布对话框 + 总览校验移出 UI 线程）

用例数 2531 -> 2537（+6：`test_publish_dialog` 新增 `PublishDialogAsyncTest` 3 例，`test_course_overview` 新增异步校验 3 例）。验证：受影响 4 模块逐进程全绿（`test_publish_dialog` 7 / `test_course_overview` 15 / `test_resources_controller`+`test_shell_views` 合并进程 56）；ruff 4 文件归零；顺带清掉 `test_course_overview` 既有 E741×2（tests 历史债 141→139）。

| 项 | 变更 |
|---|---|
| 动机 | 三处重活在 UI 线程同步执行，大课程下整窗冻结数秒：①打开发布对话框即跑完整 `release_report()`（变更检测+版本+音频清单+diff+validate+lint CLI）；②发布点击同步 `apply_version_bump + save()`；③总览「刷新校验/校验角标」链接同步跑 validate+lint CLI（且 `refresh_with_validation`+`_emit_validation` 连跑两次 CLI） |
| 发布对话框 | `PublishDialog` 新增 `load_async=True`（默认）：构造即渲染加载态（「正在生成发布报告…」，发布/导出禁用），`release_report` 交 `AiRequestWorker`；`result_ready` 后渲染+按校验结果启用按钮，`error_occurred` 显示失败且按钮保持禁用。`load_async=False` 保留同步路径（测试确定性渲染） |
| 发布动作 | `_on_publish` 改 `{apply_version_bump(plan); save()}` 闭包交 worker；期间 `_publishing=True`：三按钮禁用、发布键文案「发布中…」、`reject()` 被吞（Esc/✕/取消不再撕开对话框——保存线程运行中关闭会让主窗口读到半 bump 模型）。失败恢复按钮+原 critical 提示，成功原提示+accept，语义与同步版一致 |
| 总览校验 | 抽 `_collect_validation_problems()`（validate+lint → dict 列表，只读磁盘不碰内存模型，线程安全）；`#validate`/`#validation` 链接改 `_fetch_validation_async()`：busy 提示「校验中…」→ worker 结果缓存进 `_validation_problems` + `dataclasses.replace` 更新 `_stats` 计数 + 重建统计行 + emit。`#validation` 命中缓存同步 emit（零 CLI）；`refresh()` 复用缓存计数防闪烁；删无调用方的 `refresh_with_validation()`；worker 运行中防重复点击 |
| 数据安全 | 对话框模态期间主窗口输入被阻塞 → 内存模型无并发修改（同 `run_async_direct_save` 冻结中央区的保证）；worker 无父对象靠 `_LIVE_WORKERS` 保活，对话框先销毁时 Qt 自动断连 |
| API | `_emit_validation()` 同步语义保留（测试直调）；`_load_report` 拆出 `_render_report`；`PublishDialog` 存 `cancel_btn` 引用 |

## 2026-09-19 编辑视图减负（属性折叠 + 分段视图切换）

用例数 2521 -> 2531（+5：`test_w3_editor` 新增 `DetailPanelW4CollapseTest` 5 例，契约测试改属性清单）。验证：受影响 8 模块逐进程全绿（合并单进程命中基线已注明的空转问题，与本次无关）；`ci` 层 1436/1436；离屏截图走查三态（课时收起/课时展开/Section）结构正常。

| 项 | 变更 |
|---|---|
| 动机 | 编辑页「树 + 属性 + 内容」三区用**双层 Splitter** 叠加（外层树\|详情、内层属性\|内容），属性表单永久占约 1/4 宽度且拖动两根分隔条易错乱；蓝图/高级编辑切换按钮的选中态在 QSS 里无样式（用户看不出当前视图） |
| 属性折叠 | `detail_panel` 编辑 tab 弃内层 Splitter：属性表单移入可折叠条 `meta_toggle`（chevron 图标 + hover 样式，`#MetaCollapseHeader`）之下，展开时占满整行。**课时默认收起（内容为主）、Section/Unit 默认展开（只有属性可编辑）**；用户手动选择按类别记忆（`edit/meta_collapsed_lesson` / `edit/meta_collapsed_node`） |
| 分段控件 | 蓝图/高级编辑按钮挂 `#LessonViewToggle`（:checked = accent 填充），选中态可见；顺带修复「点击已激活按钮会双双熄灭」——`_set_lesson_view` 早退前重申选中态 |
| F2 联动 | `app.py` F2 重命名改走 `DetailPanel.reveal_metadata()`（先展开折叠条再聚焦名称框），折叠状态下不再盲聚焦 |
| API | `MetadataForm(title="属性")` 新增可选参（DetailPanel 传空走折叠头）；`detail.splitter` 移除（W3 契约测试同步更新），`form`/`content_host`/`content_layout` 保留 |

## 2026-09-19 小屏适配（FlowLayout + 屏幕钳制 + 按钮防裁）

用例数 2514 -> 2521（+7，`test_ui_fit.py` 新建：FlowLayout 2 / ScreenClamp 3 / 对话框最小宽回归 2）。验证：受影响 5 模块 + `test_operations_log` 共 88 例全绿；`ci` 层 1436/1436；离屏探针（800×800 屏）复验数字见下。

| 项 | 变更 |
|---|---|
| 动机 | 两类高频体验问题：①对话框超出屏幕（固定 `resize` 按大桌面设计，如 section_ai 1180×860，小笔记本 / 150% 缩放必超）；②按钮文字被裁（一行多按钮的 `QHBoxLayout` 不可换行，最小宽=各按钮之和，窗口不够宽时按钮被压到 sizeHint 以下） |
| FlowLayout | 新建 `src/widgets/ui/flow_layout.py`（Qt 官方流式布局参考实现）：条目保持自身 sizeHint，放不下换行；`minimumSize` = 最宽单条目而非总和。多按钮行 / 过滤行的替代容器 |
| 屏幕钳制 | 新建 `src/infrastructure/screen_fit.py`：QApplication 级过滤器，顶层 QDialog/QMainWindow `Show` 时按 `screen().availableGeometry()` 钳制尺寸（预留窗口边框，frame 完整入屏）并在发生钳制时居中；已入屏的窗口不动、最大化/全屏跳过。`main.py` + `--gallery` 接线 `install_screen_clamp(app)` |
| 定点修复 ① | `textbook_library_dialog`：顶部说明 QLabel 补 `setWordWrap(True)`（单行长 CJK 文本此前把最小宽抬到 844px）；底部 6 按钮行 QHBoxLayout→FlowLayout。最小宽 844→232，嵌入 WorkshopWindow 窄宽度下零裁字 |
| 定点修复 ② | 设置「操作日志」过滤行（combo + 搜索 + 3 按钮）HBoxLayout→FlowLayout（搜索框 `setMinimumWidth(200)` 替代 stretch）。设置对话框最小宽 894→540 |
| 探针复验 | offscreen 800×800：textbook_lib @560px 宽无任何按钮低于 sizeHint；模拟 1180×860 窗 Show 后被钳到 796×796 且 frame 完整在屏内 |
| 已知边界 | 钳制无法低于布局最小尺寸（Qt 硬约束）——最小宽失控的场景仍需 FlowLayout / wordWrap 类布局修复配对使用 |

## 2026-09-19 全局禁用滚轮调参（WheelGuard）

用例数 2508 -> 2514（+6，`test_wheel_guard.py` 新建，L2 重 Qt 模块）。验证：模块 6/6 绿（含反向 sanity：卸下 guard 后同事件确会改值）；`ci` 层 1436/1436 绿；ruff 新文件归零。

| 项 | 变更 |
|---|---|
| 动机 | Qt 默认悬停滚轮即可改 `QSpinBox`/`QComboBox` 值——设置页改为可滚动后，滚页面极易误改超时/温度/端口/撤销上限等参数 |
| 实现 | 新建 `src/infrastructure/wheel_guard.py`（与 `UserActionFilter` 同居）：QApplication 级事件过滤器，拦截 `QAbstractSpinBox`/`QComboBox`/`QAbstractSlider`（显式排除 `QScrollBar`，否则滚动全灭）的 Wheel 事件并消费；若所在处有 `QAbstractScrollArea` 祖先则把滚动量换算（notch × `styleHints().wheelScrollLines()` × singleStep）转发到其竖向滚动条，滚轮悬停在数值件上=滚页面 |
| 接线 | `main.py` `install_wheel_guard(app)`（紧随 UserActionFilter）；`--gallery` 入口同样安装 |
| 保留的调值途径 | 键盘方向键/直接输入/spin 按钮/下拉选择；打开的下拉列表内部滚动不拦（watched 是内部 QListView，非 combo 本体） |
| 测试 | spin/double-spin/combo 悬停滚轮值不变；悬停 spinbox 时外层滚动条移动；viewport 直滚不受影响；卸下 guard 后默认行为恢复（事件构造有效性自证） |

## 2026-09-19 设置对话框重构（左导航两栏 + 全页滚动）

用例数 2505 -> 2508（+3，`test_settings_dialog.py` 13→16：新增 `SettingsNavLayoutTest` 3 例）。验证：`run_gui_tests.py affected` 1 模块 16/16 绿；`ci` 层（L0 gate + L1 fast）1436/1436 绿；L2 `tests.test_app`（重 Qt 全量）绿。

| 项 | 变更 |
|---|---|
| 壳层 | `settings_dialog.py` 弃平铺 8-tab `QTabWidget`，改**左侧 Lucide 图标分类导航（QListWidget，176px）+ 右侧 QStackedWidget**；页面注册表 `_SETTINGS_PAGES`（key/label/icon）与构建器 zip(strict=True) 对齐 |
| 滚动修复（本轮主诉求） | `_make_tab()` 统一改为 `QScrollArea(widgetResizable)` 包裹内容 → 外观/AI 配置/AI 用量/编辑器/体验 OS/Git 库 六个表单页超长（150% 缩放、高级组展开、Git 库五组表单）时滚动而非裁切；操作日志（expanding QTextBrowser）与提取 Prompt（内部已有滚动）维持自管视口不二次包裹 |
| 尺寸自适应 | 固定 `resize(720, 620)` 改为 `min(880×680, 屏幕 82%/85%)` + `setMinimumSize(600, 440)`，小屏/高缩放不再超屏 |
| 页面记忆 | 当前分类写 `settings/last_page`（QSettings，`contextlib.suppress` 包裹），重开回落默认「外观」 |
| 信号治理合规 | `currentRowChanged` 连具名槽 `_on_nav_row_changed`（非 lambda）；导航图标选中态随行重着色（`_refresh_nav_icons`，accent role） |
| API 变更 | `dlg.tabs` → `dlg.nav` + `dlg.pages`；其余 widget 属性名/`_load_values`/`_sync_to_settings`/`_apply` 全部不变（仅测试改引用） |

## 2026-09-19 GUI 焕新 W1–W3（壳层多视图 + 图标系统 + 编辑视图深化）

用例数 2382 -> 2505（+123，其中焕新三波 +101：`test_ui_kit` 27 / `test_shell_views` 37（含 `ActivityBadgeTest` 7）/ `test_w3_editor` 37）。设计计划：`Turna-GUI-焕新设计计划.md`（桌面）；提交 `04ca6d2e`（[gui-w1]）→ `0b2d6191`（[gui-w2][gui-w3]）→ `e0c632f2`（lint 清扫）。

| 波次 | 变更 |
|---|---|
| W1 地基 | `theme_tokens` 扩容（SPACING/RADIUS/TYPE/ELEVATION + DENSITIES 密度阶梯 + 4 主题 `bg_chrome`）；`src/icons/` vendored Lucide SVG ×52（DPR 渲染/着色/缓存）；`widgets/ui/` UI Kit 十组件 + `--gallery` 画廊；`theme_styles/shell.py` 新组件 QSS |
| W2 壳层 | ActivityBar 导航轨 + CentralStack 四视图（欢迎/编辑/总览/资源）+ 右 Copilot Dock；三孤儿接线（ExperienceDock/Ctrl+J、PreviewHost strip、Ctrl+K 命令面板）；快捷键组 `Ctrl+1~4/B/J/K/S/,`；布局 QSettings 持久化；状态栏保存态指示 + 密度/主题快捷切换 |
| W3 编辑视图 | `TreeSidebar`（搜索过滤保祖先 + 迷你工具条）；树节点 Lucide 图标 + accent 拖拽指示线；`DetailPanel` ViewHeader + 编辑\|预览\|JSON 三 tab；`ReplaceNodeDataCommand`（id 不可变） |
| 验货修复（随 W2/W3 波入库） | ① 信号治理：`.connect(lambda)` 15+5 处清零（`functools.partial`/具名槽 + `_c` 吸收参），`test_signal_lifecycle` 复绿——该治理扫描为静态扫描、不在 `affected` 档依赖图内，**UI 波次验收须跑 `full` 或至少显式含该模块**；② 角标数据管线：`sync_activity_badges` 三路接线（总览=校验错误数 danger / 工坊=未完成导入项目数 / Copilot=未读建议，dock 可见即已读，复用 `_shown_suggestion_keys`）；③ SIM105×8 清零（`contextlib.suppress`）+ UP042×3 枚举迁移 StrEnum（已核无 `str(成员)` 依赖），`ruff check src/` 归零 |

验证：`run_gui_tests.py ci`（E1 gate 33/33 + E2 gate 5/5 + L1 fast 113/113）；受影响模块 `test_shell_views`+`test_memory_wiring`+`test_textbook_skill` 55 例全绿（含一次晚绑定回归被抓回：`welcome_view` 的 `on_open_recent` lambda 是刻意晚绑定，勿改为方法引用直传）。遗留：`tests/` 存量 141 处历史 lint（E741 等，HEAD 前已存在）未清；`--gallery` 四主题与主流程**人工走查**仍待做；W4/W5 未开工。

## 2026-09 改良清单施工（半成品接线 + 工程化落地）

用例数 2371 -> 2382（+11，`test_memory_wiring.py` 新建）。按 `turna-gui-改良清单` 施工：

| 项 | 变更 |
|---|---|
| ExperienceMemory 接线（P0-1） | `MainWindow` 实例化 `ExperienceMemory()`；`course_lifecycle` 绑定课程；`experience_window_bridge` 同步 recent intents/author profile；`experience_dispatch` 记录已接受意图；`persist_project/author` 两个既有设置键真正生效 |
| `/ocr` 开关（P0-2） | `Settings.experience_ocr_enabled`（`experience/ocr_enabled`，默认关）+ 体验 OS tab checkbox；OCR 仅本地（pytesseract + 系统 Tesseract），产物为 AttachmentRecord，不入课程树/遥测 |
| 附件信号链补全 | `AttachmentBar → DesignPanel → WorkshopWindow → MainWindow → workshop_controller → ExperienceShell.set_attachments`；`WorkshopWindow` 新增 `attachments_changed`/`ocr_requested` 信号与 `attachment_records`/`add_attachment_record`/`set_ocr_enabled` 透传 |
| 孤儿心跳清理（P0-3） | 删 `_ambient_heartbeat` 死字段与 `on_ambient_heartbeat`/`pause_heartbeat_until_idle` 零调用者函数；`JobTray.ai_busy_changed` 接入 `_on_job_tray_ai_busy_changed`（`_presence_ai_busy` 此前为死写）；`host_drift` 归 0 |
| `_sync_usage_today` 补实现 | mixin 空调用补委托 → telemetry 日用量推入 `ExperienceShell`（M-08 日预算数据源此前悬空） |
| 内联 hex 样式清零（P1-7） | 29 处审计项全清：真硬编码迁移 `current_palette()`/token；`pal.get(k,'#hex')` 回退色收进 helper；新增 `text_on_accent` 语义 token；`check_ai_boundaries.py` 审计口径修正为「`.get()` 回退不算违规」；`style_hex=0` |
| ruff 落地（P2-10） | `pyproject.toml` 新增 ruff dev 依赖与规则配置（py311/行宽 100）；按代码库惯例 ignore E402/I001/F401（sys.path 引导、monkeypatch 再导出缝）与 RUF001/2/3（CJK 标点）；`--fix` 清理 304 处（noqa/引号注解/尾空白等），存量 94 项需人工判断 |
| pyproject 元数据（P2-11） | `version=0.0.0`（内部工具，发布版本归 PyInstaller 流程）；`packages=[]`（原 `["src"]` 会装出名为 `src` 的顶层包）；新增 `ocr` extras（pytesseract） |
| QSettings 常量（P2-13） | 26 处 `QSettings("Turna","CourseEditor")` 字面量改走 `settings.ORG_NAME`/`APP_NAME`；`main.py` 去重复 `import logging` + `sys.excepthook` 模态框加重入防护 |
| 巨型函数拆分（P1-9） | `run_pipeline` 各 step 抽为模块函数（`_step_plan`/`_step_outline`/`_step_generate`/`_step_validate`/`_step_quality`/`_resume_into` 等），编排与状态机保留原函数；`run_item_chip` 抽 `_chip_modal_fallback`/`_resource_id_sets`/`_worker_instruction_with_memory`；公共 API 不变 |
| 兼容薄层（P2-14） | `dialogs/ai_generator_dialog.py` 删除（零 import 者，测试早已直指 `section_ai_dialog`）；`backend/ai_generator.py` 与 `context_bus.local_suggestions` 保留（`test_ai_generator` 50+ 处 patch 经此缝，属文档化兼容设计） |
| 测试修正 | `test_theme.py` 路径 `lib/views/theme.dart` → `lib/core/theme.dart`（存量 bug）；`test_memory_wiring.py` 新建 11 例覆盖 memory 实例化/同步/附件转发/OCR 设置持久化 |

验证：`run_gui_tests.py` 定向模块 66+147 例全绿；287 模块 walk_packages 导入零失败；`check_ai_boundaries` host_drift=0、style_hex=0；`ruff check src/` 由 3778 降至 94（余为 E741/SIM102/F841 等需人工项）。

## 2026-09-08 测试去重第四轮（死链清理 + 恒真断言 + 重复对）

用例数 2499 -> 2371（-128）。三个来源：死代码陪跑（-104）、恒真/回声断言（-13）、重复对（-11）。

| 类别 | 删除 | 依据 |
|---|---|---|
| 死模块陪跑（4 文件 28 例 + 3 个 src 死模块） | `test_semantic_search`（13）/ `test_ai_config_file`（5）/ `test_ambient_heartbeat`（3）/ `test_lesson_heat`（7） | src 全仓零引用逐一 grep 查证：`backend/semantic_search.py` 无任何生产 import；`backend/ai_config_file.py` 的 save/load/validate 无调用者（settings.py:450 `_load_ai_config_file_settings` 是读 QSettings 的同名巧合，不经该模块）；`AmbientHeartbeatService` 无创建者（生产心跳走 `ambient_controller.on_ambient_heartbeat`，上轮已注明"预留未接线"）；lesson_heat 死链终于 `win.set_lesson_error_counts`——该方法在任何窗口类上都不存在，AttributeError 被 try/except 吞掉 |
| heat 死链 src 清理 | `overview_stats.py` 的 HEAT_*/LessonHeat/heat_tint_hex/lesson_heat + `overview_controller.py` 的 lesson_error_counts_from_problems/sync_overview_heat_errors 及调用点 + `experience_host.py` 孤儿协议字段 `_ambient_heartbeat` | 同上；`test_overview_controller` 删 LessonErrorCountsTest/SyncHeatTest（-3），OpenOverviewTest 保留 |
| memory/attachments 半成品（仅删测试，src 保留待接线） | `test_experience_memory`（25）/ `test_memory_persist`（10）/ `test_experience_attachments` 5 个机类（-22，保留 ContractRoutingTest）/ `test_experience_ocr` DockOcrSuggestion+ShellOcrEnabledHint（-6）/ `test_item_chip_metrics.LessonStyleChipTest`（-4）/ `test_course_lifecycle` memory fixture 与断言 | `ExperienceMemory` 生产零实例化、`ExperienceShell.set_attachments/set_recent_intents/set_author_profile` 零调用者 → ctx.attachments 恒空、clear_author 恒走"不可用"分支。**产品取舍**：src 半成品（含设置旗标 experience_memory_persist_*、dock 展示分支、chip 探针）保留，后续若接线需重写这批测试 |
| adversarial_matrix 漏网重复 | D14RedactionClosedScopeTest（4 例）+ D27AmbientNoFocusStealTest（1 例） | D14 三项有更强对照（test_experience_ocr BuildSuggestionTest 精确 dict / test_experience_voice / test_experience_batch_polish），attachment 子项对照已随半成品删除（快照机生产不可达）；D27 与 `test_experience_ambient_batch.test_no_setfocus_source_contract` 逐字相同。矩阵现存 5 例（D3/D5D9/D11/D18/D28）全部独有，覆盖表已同步 |
| 恒真/回声断言（13 例 + 2 行） | save_pipeline `test_close_reasons_constant`（常量自含）、operations_log `test_record_action_redacts_explicitly`（喂什么读什么）、preview_fix_suggest `test_instruction_constant_stable`（长文案抄写）、theme ValidThemesTest×2（测 frozenset 语义）、schema_constants×3（测 StrEnum 语言语义，wire-format/JSON 序列化契约保留）、ai_generator_dialog `test_worker_does_not_inject_into_plain_callable`（零断言且 worker 吞异常永不可能失败）、ai_generator `test_strict_schema_marks_are_process_local...`（集合推导按构造排除下划线键后断言）、experience_actions `test_dangerous_set_closed_and_matches_derived`（与 actions.py:235 同表达式重算）、experience_metrics `test_exception_safe_provider_via_shell_snapshot`（inc 100 次断言 len>0）、job_tray `test_cancel_signal_exists`（信号无 emit/connect）；experience_demote 连写两遍的断言、batch_regenerate cap 常量回声各删一行 | 逐条核对，均无信息量 |
| ai_generator 重复类 | TestAttachmentExtractor（8 例）+ `test_build_prompt_includes_draft`（造了 draft 未传入，名实不符） | `test_attachment_extractor.py` 全部更强（UTF-8/PDF/DOCX/截断/MIME）；prompt 结构已由 TestBuildPrompt 覆盖 |
| settings 四重模式去重 | `test_persists_advanced_ai_fields` + `test_persists_git_fields`（-2） | 写侧 key 字面量由「loads（锁读侧字面量）+ round_trip（锁往返一致性）」联合覆盖：写错 key 必使 round_trip 失败、双侧同改必使 loads 失败。注意 `test_persists_new_ai_fields`/`test_persists_experience_fields` 无 round_trip 对照，保留；TTS 组 persists 即 api_key_never_persisted 安全断言，保留 |
| focus 快路径重复对 | `test_experience_shell.test_invalidate_focus_does_not_call_build_experience_context`（-1，断言并入 perf 版） | 与 `test_experience_perf.test_focus_only_under_budget_and_skips_build` 同 monkeypatch 同断言，perf 版另有时延预算；ctx.selection.id 内容断言已并入 |
| 文案修正 | `test_experience_align_pos` skipTest 文案 | 「Flutter pos_tag.dart not yet created (C step pending)」陈旧——该文件早已存在，skip 永不触发 |
| 附带修复（非本批引入） | `test_resources_controller` 模块头加 `import src.dialogs.git_library` | 存量潜在 bug：`patch("src.dialogs.git_library_dialog.GitLibraryDialog")` 在子模块未被导入时无法解析；顺序 discover 被先前模块掩盖，隔离/并行跑（`affected -j` / 分段验证）必炸。包优先导入可破 dialog↔package 循环 |

验证：`run_gui_tests.py ci`（E1+E2 gate 5/5 + L1 fast 111 纯模块 1420 例 0 失败）；L2 qtish 71 模块 4 路并行（`run_modules_parallel`）95s 全绿（其中 test_app 94s 为最长尾）；受影响模块定向全绿；全测试目录 grep 对已删符号零残留。注意：单进程顺序 `discover` 全量在本机长时间不终止（CPU 匀速爬升疑似计时器空转，与 2026-09-06 记录的「负载下 GitAsyncTest 卡死」同性质），本轮起 L2 验证采用并行分段方式。

（2026-10 补记：`run_gui_tests.py full` 已由单进程 `unittest discover` 改为对全部 test_*.py 模块走 `run_modules_parallel` 每模块独立子进程，规避上述空转问题并顺带隔离模块间 Qt 状态；`full -j N` 控制并发数。）

## 2026-09-07 噱头清理第三步（体验 OS tab / Immersive 活过来）

用例数 2481 -> 2499（+18：ExperienceSettingsTest 5 + ExperienceTabTest 6 + test_experience_demote 4 + test_fill_nokey_guard 3）。`experience_mode` 此前无任何 UI 入口（Active/Immersive 不可达），本批补齐入口与安全阀：

| 文件 | 变更 |
|---|---|
| `src/dialogs/settings/experience_tab.py`（新） | 模式四档下拉 + Immersive 子开关（full_auto/opaque）+ Goal/LLM 意图/危险技能/日配额开关 |
| `settings_dialog.py` | 新 tab（index 5「体验 OS」，共 8 tab）；`_load_values`/`_sync_to_settings`/`_apply` 补 7 个 experience 字段（`_apply` 白名单此前不含任何 experience_\*，同时补齐 advanced AI 字段搬运缺口）；进 Immersive 时 `safe_question` 风险确认，拒绝回滚下拉（headless 默认拒绝） |
| `main_window_shell.py` + `experience_skills_mixin.py` + `app.py` | `Ctrl+Shift+D` 降档快捷键（`build_experience_actions`）+ `_on_demote_experience` 处理器（demote + 落盘 + 状态栏 + 刷新） |
| `experience_handlers/fill.py` | `lesson.fill_empty` 无 Key 从回退 NodeAiEditDialog 模态改为状态栏降级；`resource.fill_stubs` 起线程前加 `is_complete` 预检（防异步失败弹窗） |
| `settings.py` | loader 加 mode 合法集校验（非法/遗留值回落 copilot） |
| `experience_dispatch.py` | 危险技能拒绝文案指向 设置 ▸ 体验 OS（该 tab 现已存在） |
| docs | `E_INTRUSIVE_WALKTHROUGH.md` 重写（事件驱动触发、无 Key 降级、SectionDiffView 仍确认的已知取舍） |

已知取舍（后续项）：SectionDiffView 未集成 auto-apply token（fill_empty/fill_stubs 生成后仍人工确认）；ExperienceDock 指标行不含 auto 计数、`format_audit_lines` 无展示端点；`AmbientHeartbeatService` 保持预留未接线。

## 2026-09-07 噱头清理第二步（Sovereign 档移除）

用例数 2485 -> 2481（-4：SovereignModeTests 3 例 + immersive C 集等价对照 1 例）。侵入度阶梯收敛为 observer/copilot/active/immersive 四档（presence_level 0–3）。删除依据：档位无任何 UI 入口不可达，且进入确认（confirm_sovereign_enter）与降档冷却守护均为零调用者——手动改 QSettings 可静默激活，属 foot-gun。

| 文件 | 变更 |
|---|---|
| `backend/experience/policy.py` | 删 SOVEREIGN 常量/档位映射/sovereign_mode_enabled 字段/标志读取与分支；旧持久化值 "sovereign" 经 normalize 回落 copilot |
| `application/presence_mode.py` | 删 sovereign 生命周期函数（enter 确认/冷却锁/mark）、警告文案与 demote 内冷却块；保留 demote_to_copilot（Immersive 复用）、should_confirm_immersive_enter、campaign 函数 |
| `application/settings.py` | 删 experience_sovereign_enabled 四处（字段/save/clone/load） |
| `application/experience_host.py`、`src/app.py` | 删 _sovereign_entered_at / _last_demote_blocked_s 协议与初始化 |
| tests | test_policy 删 SovereignModeTests、修 four_modes 断言；test_immersive_p3p6 删 sovereign C 集对照例 |
| docs | sovereign 提案移入 docs/archive/ 加废弃头注；E_INTRUSIVE_WALKTHROUGH 删 sovereign 步骤 |

## 2026-09-07 噱头清理第一步（孤儿模块删除）

用例数 2492（上次记录）-> 2485（实测）。删除 3 个零生产调用者模块约 710 行 + 2 个陪跑测试文件（-8 例），其中 3 例 AmbientHeartbeatService 心跳门控测试迁入新文件 `test_ambient_heartbeat.py`：

| 类别 | 删除 | 依据 |
|---|---|---|
| 死模块（src 零 import，spec/conftest/动态导入全查证） | `src/application/presence_visual_host.py` / `src/widgets/gaze_cursor_overlay.py` / `src/backend/experience/regret_suppression.py` | AI 副光标/输入锁定遮罩/反悔抑制引擎从未接线；所读设置旗标（experience_gaze_cursor 等）从未在 Settings 定义 |
| 陪跑测试 | `test_sovereign_and_ambient.py`（5 例，其中 3 例心跳迁移）、`test_direct_commit_and_regret.py`（3 例） | 仅测上述死模块 |

连带修改：`experience_host.py` 删 `_gaze_overlay` 协议字段；`app.py` 删 `_gaze_overlay` 初始化。

## 2026-09-06 测试去重第一步（零覆盖损失清理）

用例数 2574 -> 2520（-54，其中 35 例本就整文件 skip 永不执行）。删除 11 个测试文件约 1300 行 + 2 个死 src 模块：

| 类别 | 删除 | 依据 |
|---|---|---|
| 全 skip 占位（6 文件 35 例） | `test_observer_mode` / `test_experience_ambient_live` / `test_vocab_spiral` / `test_ai_widget_bindings` / `test_blueprint_form_ai` / `test_ai_fix_dialog_preview` | 被测 API 已退役或从未实现（T-08/T-09/R-06/v4.67 占位）；活覆盖在 test_policy / test_ambient_heartbeat / test_experience_spiral_vocab 等 |
| 测死代码（2 文件 6 例） | `test_e4_multimodal_engine_phase4` / `test_spiral_vocab_generator_phase3` | `E4MultimodalEngine`、`SpiralVocabGenerator` 全仓无引用，模块一并删除；真实链路由 test_experience_spiral_vocab 覆盖 |
| 委托层重复（1 文件 4 例） | `test_course_exchange` | course_adapter.py:570-590 全委托，test_course_adapter 逐对更强 |
| 一次性阶段门（2 文件 10 例） | `test_skill_contracts_q03` / `test_o13_save_guards` | 与 test_experience_actions/test_item_similar/test_node_edit_skill/test_job_registry 等三重重复；o13 唯一独有用例 `test_soft_error_then_validation_failure_still_fails` 迁入 `test_save_pipeline.SavePipelineTest` |

连带修改：`test_adversarial_matrix.py` 删除 `test_o13_module_cross_references_matrix` 元测试并更新覆盖表 D1/D4/D6/D10 行（去掉对已删文件的引用）；删除死模块 `src/backend/experience/e4_multimodal_engine.py`、`spiral_vocab_generator.py`。

验证：受影响模块定向 164 例 OK；全量分两段完成（负载下 GitAsyncTest 卡死一次，单文件复跑 0.4s OK；两处 FAIL 中 publish 链路用例单跑通过、stale 用例为基线既有问题）。

## 2026-09-06 测试去重第二步（adversarial_matrix 瘦身）

用例数 2520 -> 2492（-28）；`test_adversarial_matrix.py` 778 -> 296 行。删除与持续性测试逐条重复的 18 个类 28 例（D1/D2/D12/D13/D15/D16/D17/D19/D20/D21/D22/D23/D24/D26/D29/D30/D31/D33 + 弱断言 `test_actions_registry_non_empty`），删除前逐对核实 counterpart（test_experience_patch / test_experience_actions / test_experience_batch_polish / test_experience_align_pos / test_memory_persist / test_item_similar / test_experience_outline_shells / test_experience_defer_resurface / test_defer_store / test_immersive_p3p6 / test_save_host / test_policy / test_goal_sandbox）。保留 10 例独有覆盖：D3（mute 经 QSettings 重启组合）、D5/D9（SOFT_RULE_IDS hygiene-only 闭集方向）、D11（job_tray cancel 源码契约）、D14（4 例泄漏封闭：OCR scope/voice 三键/attachment 无 body/polish scope 形状）、D18（clear_experience_session 关 OCR hint，lifecycle 测试未覆盖）、D27（AmbientBanner 无 setFocus）、D28（accept 走 dispatch 漏斗）。docstring 覆盖表改为纯索引 + *direct* 标注，无测试文件文本依赖。

验证：矩阵 + 15 个 counterpart 模块 237 例 OK；`run_gui_tests.py ci`（L0 gate + L1 fast）1514 例 0 失败。

## 2026-08-05 之前的历史基线

- 日期：2026-08-05（Turna wetland palette ADR 0033：`BRAND_CLAY`/`BRAND_SAND` 常量 + Flutter 核心 hex 对照含 clay/sand/tealDark；`tests.test_theme` 29 OK）
- 主题专项：`python -m unittest tests.test_theme` → 29 passed
- 全量用例（上次记录）：1276 passed（skipped=2），命令：
  ```bash
  QT_QPA_PLATFORM=offscreen python -m unittest discover -s tests -p "test_*.py"
  ```

## 2026-07-21 课程工坊布局压缩（L1–L2）

用例数保持 1276。去重中栏/右栏双参数、DesignPanel 改「对话与高级」、JSON/高级默认折叠、空白项目收窄左栏、生成后落结构大纲。

| 项 | 内容 |
|---|------|
| `widgets/ai_orbit.py` | 紧凑参数条（含生成模式）为唯一主参；核心按钮 110px；「对话与高级…」 |
| `dialogs/ai/design_panel.py` | 主参隐藏镜像；聊天为主；高级/JSON 可折叠；「按对话再生成」 |
| `widgets/unified_workspace.py` | 右栏默认大纲；空白左栏收窄；`apply_orbit_params` 同步；tab 文案「对话与高级」 |
| README | 五条路径与右栏说明更新 |

## 2026-07-21 aiEnhance 感知增强（第四–六枪 U0–U4）

用例数 1252 -> 1276（+24）。落地 `tool/gui/aiEnhance.md` 感知路线：生成摘要卡、可点质量维、校验多选批量修、共享预设、清待补、结构保护加强、作用域解析、ReadyImport 决策条、总览质量层、四步灯可点、分课并行 fill。

| 项 | 内容 |
|---|------|
| `backend/ai_summary.py` | `GenerationSummary` / `build_generation_summary` / `format_summary_card` / `format_ai_status_line` |
| `backend/ai_fix_batch.py` | `group_problems_for_fix` 按节点分批 |
| `backend/ai_presets_ui.py` | 全局 `EDIT_PRESETS` + 教师预设 |
| `backend/ai_scope.py` | 自然语言作用域解析（课序/MCQ/单元） |
| `backend/content_quality.py` | `issues_for_dimension` / `build_quality_fix_hint_for_dimension` |
| `dialogs/ai/review_panel.py` | 摘要卡、可点维修复、清待补、决策条、作用域提示 |
| `widgets/validation_report.py` | ExtendedSelection + batch 信号 |
| `app.py` | 批量修调度；section 级结构删除确认 |
| `backend/ai_phased.py` | `max_parallel` 分课并行 splice |
| `backend/ai_pipeline.py` | 透传 `max_parallel_lessons` |
| `dialogs/workshop_window.py` | 四步灯可点 + 生成完成 CTA |
| `widgets/course_overview.py` + `overview_stats.py` | section 质量均值/badge |
| 测试 | `test_ai_summary` / `test_ai_fix_batch` / `test_ai_scope` / `test_validation_report` + 既有面板适配 |

详见 `tool/gui/aiEnhance.md` §8 / §13。

## 2026-07-21 aiEnhance 第三枪 批次③（Phase 4 教材抽取增强）

用例数 1218 -> 1252（+34）。落地 `tool/gui/aiEnhance.md` Phase 4 的 P4-1/2/3/4/6（P4-5 原文 span 定位为可选项，本批不做）：超长章滑窗抽取 + 重叠去重、失败自动级联、内置语言对抽取模板、质量驱动定向重抽、OCR 文档化。

| 项 | 内容 |
|---|------|
| `backend/markdown_chopper.py` | 新增 `split_chapter_windows(chapter, max_chars, overlap_chars)`：段落边界切窗、`{slug}#w{n}` 派生 slug、相邻窗重叠尾部段落、短章/不可分章单窗返回（行为零变化） |
| `backend/knowledge_extractor.py` | 抽出 `_run_extraction_loop` 公共闭环；新增 `extract_knowledge_points_windowed`（短章/关闭时委托原函数；长章顺序逐窗、单窗失败容错、全失败 raise、`AiCancelled` 即传、usage 累加）、`merge_window_knowledge`（复用 `knowledge_merger.resource_key` 去重 + `coerce_knowledge_points` 按 `ch-{slug}-` 重建 id）、`reextract_knowledge_targeted`（P4-4，复用统一 loop） |
| `backend/knowledge_prompt.py` | `BUILTIN_PAIR_TEMPLATES` 内置语言对包（内存 register > persisted > 内置包 > 默认），首发 tr↔zh 规则块（元音和谐/敬语、term 禁混中文、翻译简体中文，纯文案）；新增 `build_targeted_reextract_messages`（当前抽取 + issue 列表回灌，要求完整修正版 JSON） |
| `backend/textbook_presets.py` | `TextbookPreset` 加 `window_chars`（默认 8000，reading 10000，0 关闭滑窗）/ `overlap_chars`（默认 500） |
| `dialogs/textbook_import_controller.py` | `_launch_worker` 改走 `extract_knowledge_points_windowed` 并透传窗参数；信号接线抽为 `_connect_and_start`；`_on_extract_error` 自动级联 standard→vocab_only（`_attempted_strategies` 防循环、日志「自动降级」、vocab_only 再失败建议跳过/人工）；新增 `reextract_chapter_targeted` + `_on_reextract_ready/_on_reextract_error`（成功替换并重算质量分，失败保留原结果）；`auto_cascade` 构造参数（默认开） |
| `dialogs/textbook_import_dialog.py` | 读 QSettings `textbook/auto_cascade` 传入 controller；审校页新增「按质量重抽」按钮（有知识且有 quality issue 时可见） |
| `tests/test_chapter_windows.py`（**新建**） | 7 用例：短章单窗、禁用、段落边界切分、slug/title 派生、重叠/零重叠、单段超窗兜底 |
| `tests/test_knowledge_extractor.py` | +18：合并去重/id 确定性、滑窗合并/id 前缀/单窗容错/全失败 raise/取消即传/usage 累计、tr↔zh 内置包命中与优先级、targeted prompt 内容、reextract 成功/失败路径 |
| `tests/test_textbook_controller.py` | +9：自动级联成功/再失败/开关关闭/防循环、窗参数透传、定向重抽无知识/无 issue 跳过/成功替换重算/失败保留原结果 |
| `tests/test_textbook_recovery.py` | `test_retry_chapter_after_failure` 显式 `auto_cascade=False` 保持「手动重试」原意图（级联为其前置消费第二个 worker） |
| `README.md` | 教材抽取「滑窗 / 自动级联 / 按质量重抽」用户可见说明 + 语言对覆盖机制 + OCR 可选依赖小节（P4-6） |

详见 `tool/gui/aiEnhance.md` §8 / §13。

## 2026-07-21 aiEnhance 第三枪 批次②（Phase 5 智能工作流 Agent）

用例数 1203 -> 1218（+15）。落地 `tool/gui/aiEnhance.md` Phase 5（P5-1..6）：精修流水线状态机 + 工坊 checklist UI + 中间态持久化续跑；导入仍人工确认，无自动写盘。

| 项 | 内容 |
|---|------|
| `backend/ai_pipeline.py`（**新建**） | `PipelineStep`/`PipelineState`/`run_pipeline`：Plan→Extract?→Outline→Generate→Validate→QualityScore→Fix(loop)→Explain→ReadyImport；fast 模式薄包装 `request_course_with_retry`+validate+quality；refine 复用 `ai_phased.request_outline`/`fill_lessons_from_outline`；`on_progress`/`cancel_check`（优雅取消留部分态）/`usage_callback` 累计 `usage_total`；Fix 先规则修复（`_normalize_resources`/`_auto_fix_resources`/可选 `fill_needs_review`），LLM 只处理剩余 error，`structural_diff` 检删 id 即回滚；`resume_state` 续跑；Extract 步暂恒 skipped（待批次③） |
| `dialogs/ai/worker.py` | `AiRequestWorker` 加 `progress_ready` 信号；target 接受 `on_progress` 时自动注入（Qt 线程 marshal） |
| `dialogs/ai/design_controller.py` | 精修模式（phased/refine）改走 `run_pipeline`（快速模式 `request_course` 不变）；`_on_pipeline_progress` 逐步更新 + 取消时 finalize（worker 取消丢结果由 progress 兜底）；中间态持久化 `project.design["pipeline"]`（outline/skipped/usage/cancelled），重开项目续跑；`pipeline_skip_fix`/`pipeline_skip_explain` 参数；`generation_mode` 默认值从 `ai_pipeline_default_mode` 种子 |
| `dialogs/ai/design_panel.py` | 步骤 checklist（七步 ○/…/✓/—/✗ 着色）；「跳过修复」「跳过解释」checkbox（仅精修可用，随项目参数持久化）；生成模式 tooltip 更新 |
| Settings | 复用批次① `ai/pipeline_default_mode` 等键，无新增键 |
| 测试 | `test_ai_pipeline`（10：fast/refine 状态转移、跳过、取消×2、usage 累计、Fix 只喂剩余 error、删 id 回滚、loop 上限、resume）；`test_design_controller.DesignControllerPipelineTest`（5：dispatch/skip 映射/取消快照续跑/失败弹错/progress finalize） |

详见 `tool/gui/aiEnhance.md` §8 / §13。

## 2026-07-21 aiEnhance 第三枪 批次①（基础设施：cache + 双模型 + strict_schema + 抽取统一 loop）

用例数 1121 -> 1203（+82）。落地 `tool/gui/aiEnhance.md` 第三枪批次①主干：进程内 LRU 响应缓存、双模型分流、`json_schema` 严格模式 + auto 回退、教材抽取走统一 `generate_with_validate_loop`、Settings 高级区 UI、telemetry `ai.cache.stats` 事件。

| 项 | 内容 |
|---|------|
| `application/settings.py` | 新增 7 个高级 AI 键：`ai_model_chat`/`ai_model_json`（空回退主模型）/`ai_strict_schema`(auto\|on\|off)/`ai_cache_enabled`/`ai_fill_needs_review`/`ai_max_parallel_lessons`(1..8)/`ai_pipeline_default_mode`(fast\|refine)；QSettings round-trip + clamp + enum 校验 + 旧 settings 兼容 |
| `backend/ai_generator.py` `AiApiConfig` | 加 `model_chat`/`model_json`/`strict_schema`/`_json_schema_supported`(进程级 probe)；`select_model("chat"\|"json")` 双模型分流；`effective_strict_schema()` 解析 auto->on/off；`mark_json_schema_supported/unsupported()` |
| `backend/ai_cache.py`（**新建**） | `AiCache`：内存 LRU(128) + 可选 disk；`key=sha256(model\|messages\|response_format)`；`get/put/clear/clear_disk/stats`；线程安全 Lock；**不含 key**；`AiCacheStats` 快照；`get_default_cache`/`set_default_cache` 进程级单例 |
| `generate_with_validate_loop` | 加 `cache`/`model`/`max_tokens` 参数；首次查 cache 命中则跳过 LLM 但仍跑 validator 防脏；成功写回；retry 不查；`cache=None` 时 fallback 到 `get_default_cache()` |
| `request_chat` | 加 `model` 参数（覆盖 `config.model`）；HTTP 400 + schema 相关错误 + `strict_schema="auto"` 时自动标记 `_json_schema_supported=False` 并用 `json_object` 重试一次 |
| `build_response_format(config, *, schema_name, use_schema)` | 新建：on->`json_schema`（strict closed schema）；off->`json_object`；auto->`effective_strict_schema()` |
| `_build_section_json_schema` | 新建：8 字段 closed schema（id/name/description/prerequisiteSectionIds/words/expressions/grammarPoints/units），`additionalProperties:false`，全部 `required` |
| `_looks_like_json_schema_rejection` | 新建：HTTP 400 + body 含 schema/response_format/unsupported/unknown field 判定 |
| 双模型分流接入 | `request_alignment_reply`/`explain_course` 走 `model_chat`；`request_course_with_retry`/`generate_from_chat`/`generate_edit`/`request_lesson_transform`/`request_item_transform`/`request_correction`/`fill_needs_review_resources`/`ai_phased.request_outline` 走 `model_json`；`_chat_json` 转发 `model` |
| `backend/knowledge_extractor.py` | 重写：删除内联 retry 循环；改走 `generate_with_validate_loop`（P1-3 收尾）；`_make_parse_fn` + `_make_validator` 闭包；`response_format={"type":"json_object"}`（不走 section schema）；`max_tokens` 透传；`model=config.select_model("json")` |
| `backend/knowledge_prompt.py` | `build_correction_prompt` 保留（不再被 extractor 直接调用，但测试覆盖） |
| `dialogs/settings_dialog.py` | AI tab 加「高级」可折叠 QGroupBox：model_chat/model_json QLineEdit + strict_schema QComboBox + cache/fill_needs_review QCheckBox + max_parallel_lessons QSpinBox(1..8) + pipeline_default_mode QComboBox；`_load_values`/`_sync_to_settings` 接线 |
| `dialogs/ai_generator_dialog.py` | 新建 `_record_cache_stats()`：每次 `ai.generate` 后记录 `ai.cache.stats` 事件（hits/misses/entries/disk_writes/disk_errors，不含 key） |
| `app.py` | `_apply_ai_cache()`：启动 + 设置变更时按 `ai_cache_enabled` 安装/清除 `set_default_cache(AiCache(maxsize=128, enabled=True))` |
| `app.current_ai_config()` | 注入 `model_chat`/`model_json`/`strict_schema` |
| 测试 | `test_ai_cache`（25）、`test_settings.SettingsAdvancedAiTest`（9）、`test_ai_generator.TestAiApiConfigAdvanced`（8）、`TestGenerateWithValidateLoopCache`（8）、`TestDualModelRouting`（5）、`TestBuildResponseFormat`（7）、`TestJsonSchemaRejectionHeuristic`（4）、`TestRequestChatAutoFallback`（3）、`test_knowledge_extractor.ExtractKnowledgePointsLoopTest`（8）、`test_settings_dialog.SettingsDialogAdvancedAiTest`（4）、`test_telemetry`（+1） |

详见 `tool/gui/aiEnhance.md` §8 / §13。

## 2026-07-21 aiEnhance 第二枪（质量分 + 编辑效率 + 分阶段生成）

用例数 1101 -> 1121（+20）。落地 `tool/gui/aiEnhance.md` 第二枪主干：

| 项 | 内容 |
|---|------|
| `backend/content_quality.py` | 六维规则质量分：coverage / balance / distractor / level_fit / audio_ready / resource_hygiene；`score_section` + `to_problem_dicts` + `build_quality_fix_hint`；hygiene 复用 `ai_bench` |
| `tests/test_content_quality.py` | 9 用例（goldens：clean / placeholders / dangling / mcq dup / listening / grounded） |
| Review 质量 chips（P2-5） | `review_panel` 展示均值 + 维度分 + badge 着色；不阻断保存/导入 |
| 按质量分修复（P2-6） | 「按质量分修复」→ 低分维度 issues + `AiFixDialog(initial_hint=…)` → merge 确认 |
| 局部重生成指令（P3-6/P3-4） | Review 右键重生成弹出指令对话框 + 预设条（干扰项/transcript/敬语/复现/难度） |
| `backend/ai_phased.py` | 大纲 prompt/校验/shell；`fill_lessons_from_outline` 锁 id/template；`request_course(mode=fast\|phased)` |
| 工坊生成模式（P2-10） | DesignPanel「快速 / 精修」；`DesignController.generation_mode` → `request_course` |
| `AiFixDialog` | 支持 `initial_hint` / `window_title` |
| 测试 | `test_ai_phased`（10）、`test_content_quality`（9）、review/design 适配 |

详见 `tool/gui/aiEnhance.md` §8 / §13。

## 2026-07-21 aiEnhance 第一枪（Phase0 + 稳定性 + pedagogy）

用例数 1075 -> 1101（+26）。落地 `tool/gui/aiEnhance.md` 第一枪：度量底座、统一校验闭环、资源顺序/Grounded 收紧、可选 needs-review 二趟补全、教学法 prompt 块。

| 项 | 内容 |
|---|------|
| `backend/ai_bench.py` | 纯函数卫生探针：placeholder / needs-review / dangling refs / MCQ 重复选项 / grounded coverage；`score_section_hygiene` + `format_hygiene_line` |
| `tests/ai_goldens/` | 6 个静态 section fixture + README（clean / placeholders / dangling / grounded pool / listening / mcq dup） |
| `backend/ai_pedagogy.py` | CEFR 软约束、课型梯度、干扰项规则、Turkish 语言包；`pedagogy_prompt_block` |
| `generate_with_validate_loop` | 从 `request_course_with_retry` 抽出公共 loop；error 回灌带 path；首次可 stream、retry 不 stream |
| 调用方接入 | `request_course_with_retry` 走 loop；`generate_from_chat` / `generate_edit` 可选 validator+max_retries（默认 0=单次）；`request_lesson_transform` 默认 max_retries=1 |
| `fill_needs_review_resources` | 可选二趟补全 `[待补]`/needs-review（默认关，`fill_needs_review=True` opt-in） |
| Prompt | 资源数组强制输出顺序 words→expressions→grammarPoints→units；Grounded 要求池外完整字段+`new`；`build_prompt` 注入 pedagogy |
| Fixture | `copy_turkish_course` 排除 `.varnamala-backup`，避免本地编辑残留污染 save-atomicity |
| 测试 | `test_ai_bench`（9）、`test_ai_pedagogy`（9）、`test_ai_generator` 扩展 loop/fill/path（+8 量级） |

详见 `tool/gui/aiEnhance.md` §8 / §11 / §13。

## 2026-07-21 tool/gui 性能与缺陷全量整改（分批 A–F）

用例数 1068 -> 1075（+7）。对 `tool/` 与 `tool/gui/` 全量代码做了一轮性能热点 + 缺陷修复，按风险/收益分 6 批提交，每批后跑全量回归。同时清理了误入仓库的 `assets/courses/turkish/.varnamala-backup/` 运行时产物并加 `.gitignore`，消除了 `test_save_atomicity` 长期 flaky。

| 批次 | 项 | 内容 |
|---|---|---|
| A 性能热点 | `regenerate_unit_in_section` | 函数顶部深拷贝 `existing_section` 一次，循环内就地按索引替换；抽出 `_splice_lesson_in_place`。旧实现每个 lesson 调 `_splice_lesson`（每次 `copy.deepcopy` 整个 section），单元重建为 O(L·N)。（P1） |
| A | `CourseAdapter` id 索引 | 新增 `_unit_index`/`_lesson_index`（懒重建 + `invalidate_node_index`）；`find_unit`/`find_lesson` 走索引，命中时用 `is` 校验节点仍挂在 `self.sections` 上，失败回退全扫。`load`/`_restore_from`/`save` 后失效。命令热路径（Move/Reparent/BulkMove）从 O(tree) 降到 O(1)。（P3） |
| A | `app._jump_to_node` unit 分支 | 新增 `CourseTreeWidget.select_unit` 复用 `_id_index`，替换 O(sections·units) QTreeWidget 遍历。（P4） |
| A | `_state_hash` 改 sha256 | 旧实现用 Python 内置 `hash()`（进程间随机盐），跨会话比较产生假阳性「已变更」。改 `hashlib.sha256` 稳定可复现，缓存默认值从 `-1` 改 `""`。（P5/B14） |
| B 严重缺陷 | `export_content_inventory.render_markdown` | 依赖模块全局 `refs`，非 `main` 调用即 NameError；改为参数 `refs` 并在 `main` 显式传入。（B1） |
| B | `git_library._read_body` chunked 解析 | 空行 `continue` 在关闭的 socket 上死循环；加 `empty_streak`（≤8）与 `max_iterations`（1e6）双兜底。（B7） |
| B | `sync_resources_with_git` 包装格式 | git 资源文件实为 `{"version":1,"language":..,"words":[..]}` 对象；旧代码 `isinstance(list)` 恒为 False，把 git 侧当空集再写回裸 list，**破坏协作者仓库的 wrapper/版本/语言元数据**。改为识别 wrapper、保留 `version`/`language`、原子 tmp+`os.replace` 写回。新增 3 个往返测试（wrapped/legacy/双向）。（B10） |
| B | git token URL-scoped | 旧 `_extra_args_for_https` 注入全局 `http.extraheader`，对 `http://` 与重定向目标泄漏 Bearer。改为仅 `https://`、`http.<scheme>://<host>/.extraheader` URL-scoped；新增 6 个单测覆盖 no-token/https/http/git@/scope/malformed。（B13） |
| B | `split_course.py` vocab 重新包装 | 旧 `shutil.copyfile` 直接拷贝旧格式 `kannada_vocab.json`（可能是裸 list），loader 读 `data.get("words",[])` 会静默返回空。改为识别裸 list/dict、重新包装成 `{"version":1,"language":..,"words":[..]}` 并原子写。（B17/P8） |
| B | `course_cli.load_sections` 缺键兜底 | `entry["file"]` 缺键即 KeyError 崩溃；改 `.get` 跳过损坏条目。（M17） |
| C 信号/线程安全 | AI worker 关闭期信号 | `AiGeneratorDialog.reject/accept/closeEvent` 设 `_closing=True`、`_disconnect_worker_signals` 断开所有 worker 信号；所有 worker 槽首检 `self._closing` 早退。防止对话框销毁后 worker emit 命中已删除 QObject。（B6） |
| C | `_run_git_async` 取消旧 worker | 启动新 git worker 前 `cancel()` + 断开旧 worker 信号，避免并发 git 操作在共享 clone 上竞争索引。（B5） |
| C | `_on_start_share` 端口泄漏 | `thread.start()` 失败时旧代码置 `git_server_thread=None` 但已绑定的 socket 未关闭；异常分支显式 `thread.server.server_close()`。（B15） |
| C | `_read_streaming` 非 SSE 取消 | 非 SSE 分支原 `"".join(line_iter)` 无 `cancel_check` 轮询，慢响应时取消挂起；改为逐行读取间轮询取消。（B18） |
| D 非原子写 | `course_cli.save_json` | 改 tmp + `flush` + `os.fsync` + `os.replace`，崩溃不再留下截断的 JSON。（P7/B24） |
| D | `export_content_inventory`/`split_course`/`_edit_or_delete_memo`/`sync_resources_with_git` | 全部统一 tmp + `os.replace` 原子写。（P8/B19） |
| D | `_backup_json_files` 保留策略 | 新增 `_prune_old_backups(keep=20)`，按时间戳名排序裁剪最旧；`.varnamala-backup` 不再无界增长。（M11） |
| D | `build_release.copy_tree` | `rmtree` + `copytree` 改 `dirs_exist_ok=True`，中断不再丢失整个目录。（M18） |
| E 次要清理 | `generate_audio` 相对路径 | `Path("assets/courses/turkish")` 改 `Path(__file__).resolve().parent.parent / ...`，任意 cwd 可运行。（M7） |
| E | `worker.is_valid_http_url` regex | 模块级 `re.compile` 缓存。（M3） |
| E | `telemetry._write` 首次失败 stderr | 永久写失败的日志不再完全静默；首次失败 stderr 提醒一次。（M10） |
| E | B3 表格 item null 守卫 | `_on_remote_double_click`/`_on_del_saved_remote`/`_on_history_context_menu` 对 `QTableWidget.item(row,c)` 返回 None 加守卫，避免 `.text()` AttributeError。（B3） |
| E | B4/B9 错误可见化 | `_refresh_branches`/`_refresh_file_tree`/`_refresh_history` 的 `except Exception: pass` 改为 `status_label.setText` 显示失败原因；`textbook_import_controller._autosave` 改 `telemetry.record_error` + 可选 status hook。（B4/B9） |
| F UI 性能 | `_find_line_for_path` | `splitlines()` 全列表 + 子串扫描改 `text.find` + `count("\n",0,idx)`，O(total_lines) → O(match_offset)。（P9） |
| F | `git_library_dialog._poll_server_logs` | 日志轮询定时器原整个对话框生命周期 1s/tick；改为仅在 LAN tab 可见且 server 运行时启动，`_on_tab_changed`/`_on_start_share`/`_on_stop_share` 协同启停。（P2） |
| 仓库清理 | `assets/courses/turkish/.varnamala-backup/` | 该目录是 GUI 运行时产物，被误提交到 git，导致 `test_save_atomicity` 长期 flaky（复制课程时把旧 backup 一起带进 tmp，计数+1）。`git rm -r` 并加 `.gitignore`。 |

## 2026-07-20 主题系统重设计：Peacock 品牌对齐 + 高对比度 + 渐变深度

用例数 1043 -> 1068（+25）。将 GUI 配色从 Tailwind 蓝切换为孔雀蓝绿系，与 Flutter 端 `VarnamalaTheme` 统一；新增高对比度主题变体；QSS 引入渐变与品牌深度；全量 widget 硬编码颜色改为 theme-aware。

| 项 | 内容 |
|---|------|
| 新模块 `theme_tokens.py` | 4 套调色板（dark / light / high-contrast-dark / high-contrast-light），43 个语义 token/套；纯函数 `palette_for` / `is_high_contrast` / `is_dark` / `resolve_theme`；模板徽标 `TEMPLATE_BADGES`（listening 改为孔雀青 `#1F727E`）与资源类型色 `RESOURCE_TYPE_COLORS`（word 改为孔雀青）。无 Qt 依赖，可单测。 |
| `theme.py` 重写 | accent 从 `#3B82F6` 蓝系改为 `#1F727E` 孔雀青系（accent_hover `#359CBB`、accent_pressed `#145A64`）；QSS 引入 `qlineargradient`：工具栏品牌渐变、主按钮渐变、进度条 chunk 渐变、Tab 选中孔雀下划线、滑块手柄发光环、hover 统一为 `accent_subtle`；高对比度变体：2px 边框 + 2.5px 焦点环 + 纯黑/白表面；新增 `apply_shadow()` 辅助函数（`QGraphicsDropShadowEffect`）。保留 `current_palette()` / `ai_color()` / `apply_theme()` API。 |
| `settings.py` | `theme` 字段允许集扩展为 `{dark, light, high-contrast-dark, high-contrast-light}`；无效值仍回退 `dark`。 |
| `settings_dialog.py` | 主题下拉新增「高对比度-深」「高对比度-浅」两项。 |
| `chat_view.py` | `DEFAULT_PALETTE` 与新 dark 调色板同步。 |
| Phase 5 精选色板 | `lesson_content.py` `TEMPLATE_COLORS` 改从 `theme_tokens.TEMPLATE_BADGES` 导入（listening `#3B82F6`→`#1F727E`）；`knowledge_bubble.py` + `resource_review_table.py` 资源类型色改用 `resource_type_color()`（word `#3B82F6`→`#1F727E`）。 |
| Phase 4 widget 硬编码颜色全量整改 | 18 个文件、~46 处 `setStyleSheet` 硬编码 hex 改为 `current_palette()` token 查找：teacher/{preview_window,template_editors,linear_flow,sublesson_flow}.py（`#FFFFFF`/`#E8EAF0` 标题、`#1F232C`/`#232833` 卡片背景、`#9CA3AF` 面包屑→palette token）；widgets/{validation_report,result_preview,publish_dialog,lesson_editor,bulk_import_preview_panel}.py（`#E74C3C`/`#27AE60`/`#FF9F43`/`#9CA3AF`/`#46D1BF`/`#145A64`→error/success/warning/text_secondary/ai_accent/accent_pressed token）；dialogs/{git_library_dialog,ai_generator_dialog,ai_fix_dialog,ai_error_analyzer,functional_lesson_wizard}.py + dialogs/ai/result_window.py（`#3B82F6`→info、`#6B7280`→text_secondary、`#1F2937`/`#10B981` 日志终端→bg_input/success、`#F9FAFB`/`#374151` 留言板→bg_input/text）。 |
| Phase 6 深度效果 | `theme.py` 新增 `apply_shadow(widget, color_key, blur_radius, dy, alpha)` 辅助函数（`QGraphicsDropShadowEffect`，QSS 不支持 box-shadow 的替代方案）；`ai_orbit.py` AI 核心按钮应用孔雀发光阴影（`color_key="glow"`, `blur_radius=24`, `alpha=0.3`）。 |
| 测试 | `test_theme.py`（25）：4 套调色板键集一致 / accent 为孔雀青非蓝 / 高对比度纯黑白 / `palette_for` 回退 / 徽标与资源类型色 / `valid_themes` 不可变。 |

## 2026-07-20 课程总览增强 + 纯函数抽离（P5）

用例数 1009 -> 1043（+34）。总览窗口从纯结构展示升级为可搜索/可过滤/可导出/可校验跳转的富统计面板，兑现 README:182 承诺的"词汇覆盖率 / 语法点分布密度 / 各 Section 题型构成比例"。

| 项 | 内容 |
|---|------|
| 纯函数模块 | 新增 `backend/overview_stats.py`：`iter_lesson_interactions` / `iter_lesson_refs` / `lesson_is_empty` / `compute_overview_stats` / `format_stats_line` / `format_interaction_line` / `filter_lessons` / `export_markdown`。无 Qt 依赖，可单测。 |
| 富统计行 | Sections · Units · Lessons · 空课时数 · 校验错警数（可点）· 词汇/表达/语法覆盖率（N/M, P%）· 课型分布 |
| 题型构成 | 每个 Section 卡片头部一行：`选择题 12 · 填空题 8 · 听音选词 6`（按 `INTERACTION_LABELS` 中文化） |
| 空课时标记 | 主内容键为空的 lesson 芯片灰边 + `（空）` 后缀 + tooltip 说明；直接服务于 Sections 2–8 占位状态 |
| 搜索框 | `QLineEdit` 按 name/id 过滤课时（大小写无关，AND 于课型过滤） |
| 课型过滤 | 顶部 template 徽标可点切（互斥），仅显示该 template 的 chips；「清除」一键复位 |
| 导出 Markdown | 把当前可见结构（含过滤态）导出剪贴板，便于贴入 ADR / `content_inventory_current.md` |
| 校验跳转 | stats 行校验数可点 -> 发 `validation_requested` -> 主窗口复用已有 `_show_validation_report` |
| 重构 | `_TEMPLATE_COLORS` 移到 `lesson_content.py`（与 `TEMPLATE_LABELS` 同居），`course_tree.py` 改从 `lesson_content` 导入，去掉 widget→widget 反向依赖；`_LessonChip` 样式按 template 缓存；`_build_section_card` + `_build_unit_row` 合并为 `_render_section` |
| 测试 | `test_overview_stats.py`（26）：纯函数，无需 QApp，覆盖 interactions/refs/empty/coverage/filter/markdown；`test_course_overview.py`（4 -> 12）：coverage 文本、搜索过滤、无匹配空提示、template 过滤、clear 复位、空芯片标记、Markdown 剪贴板、validation_requested 信号 |


## 2026-07-20 资源库 / Git 资源库丰富（ADR 0021-0026）

用例数 961 -> 1009（+48）。全量丰富资源库 / Git 资源库功能，覆盖 A-J 主题：
- `credential_store`（新）：keyring get/set/delete、QSettings 回退、URL host 提取、SSH key 往返、keyring 状态诊断。
- `git_remote_catalog`（新）：SavedRemote dataclass 往返、CRUD、按 name 去重、rename、find_by_url、mark_synced、按 name 排序。
- `settings`：git 库字段（clone_root/git_bin/default_lang/lan_port/lan_bind/lan_token/git_timeout/assets_root）默认值/加载/持久化/round-trip/clone/clamp。
- `git_library`：分支 list/create/switch/delete、remote list/add/remove、diff_working_vs_head、list_files/read_file_at_ref/log_since、has_conflicts、stash/pop、config 注入（git_bin/timeout/token/ssh_key）、LAN token 鉴权 401、LAN read_only 403、LAN IP 白名单 403。
- `course_adapter`：export_resource_pack/import_resource_pack(merge+replace)、detect_duplicates(含真实 Turkish 跨表重复)、sync_resources_with_git(双向 merge + 写回)。
- `settings_dialog`：「Git 库」tab 索引修正（操作日志 tab 移至 index 6）。
- 新增依赖：`keyring>=24.0`。
- 新增 ADR：`docs/decisions/0021-0026`。
- 修复：`GitStatus` @dataclass 装饰器空行、`_set_clone_dir_pending` 死代码。

## 2026-07-20 代码审查修复（9 项缺陷）

用例数 952 -> 961（+9）。修复 LAN Git 协作 / 工坊草稿导入 / AI 修复对话框 / 设计面板流式优化中的缺陷：
- `git_library`：do_POST 支持 `Transfer-Encoding: chunked`（修 LAN push 空包体）；`GitHTTPServer` 改 `ThreadingHTTPServer` + 两个 RPC `subprocess.run` 加超时（504）；`get_history` 改 0x1f 分隔符（修作者名含 `|` 错列）；新增 `pull_rebase`。
- `app.py`：`_import_draft_into_section` / `_import_draft_into_unit` 调 `record_imported_sections`（修导入状态不持久化 → 重开项目丢失「已导入」标记与定位）。
- `ai_fix_dialog`：`_on_result`/`_on_error`/`_on_completed` 加 worker 身份守卫（修取消后旧 worker 迟到信号覆盖新 worker 状态）。
- `git_library_dialog`：`_on_start_share` 接 `aboutToQuit` 退出时停服；`_refresh_server_ui` 清理 QHBoxLayout 及子控件（修刷新泄漏）；`_on_send_memo` 先 `pull_rebase` 再 commit+push（降低非快进拒绝）。
- `design_panel`：`_on_busy_changed` 匹配 `重生课时…`/`重生育元…`（修单元重生成未走流式摘要 → O(n²) 卡顿）。
- 新增测试：`test_app` 草稿导入持久化 ×2、`test_ai_fix_dialog_guard` 身份守卫 ×3、`test_design_panel` 重生阶段 ×3、`test_git_library` 分隔符 ×1。

## 2026-07-20 测试精简：共享 helper 去重（用例数不变 952）

代码体积/磁盘成本精简，**用例数 952 不变、断言行为不变**。抽出 4 个共享 helper
模块，消除跨文件字面重复；不迁 pytest、不引入 conftest，保持 unittest 单层平铺。

| 模块 | 替代了什么 | 涉及文件数 |
|------|-----------|-----------|
| `tests/_qtapp.py` (`qt_app`/`_App`/`_TestApp`) | 30 文件各自 `_App`/`_TestApp` 单例类 + 内联 `QApplication.instance() or QApplication([])` | 30 |
| `tests/_course_samples.py` (`sample_section`/`sample_section_from_chapter`) | 5 文件 `_section()`（design_controller/panel/review_panel + bulk_merge/section_import） | 5 |
| `tests/_qsettings_mock.py` (`make_qsettings`) | 2 文件字面一致的 `_make_qsettings()` | 2 |
| `tests/_course_fixture.py` (`copy_turkish_course`/`real_adapter_with_course`) | 11 文件 `shutil.copytree(turkish)` + 2 文件 `_real_adapter_with_course()` | 12 |

- 净减约 **379 行**（16111 → 15732，含新增 4 helper 模块）。
- 清理本地 `tests/__pycache__`（已 gitignore，不入仓库）。
- `_sample_md()`（10 文件同名不同义）、`_make_qsettings` 另 2 份（接口集不同）未合并——保留本地。
- 验证：`unittest discover` 952 passed；`pytest tests/ --ignore=tests/test_app.py` 920 passed。

## 2026-07-20 课程工坊 P4：文档对齐统一画布

文档-only（用例数不变）。将作者/开发者文档从「六阶段侧栏」改为 **项目库 + 创意画布**：

| 文档 | 更新要点 |
|------|----------|
| `tool/gui/README.md` | 工坊全流程、ASCII 布局、目录锚点、模块树（unified_workspace / orbit / grounded_stats） |
| `docs/authoring/textbook-import.md` | §3 画布位置表、§3.1 Grounded/Orbit/大纲、§10 相关文件 |
| `docs/authoring/gui-beginner-guide.md` | §5 小白路径：左中右栏、Ctrl+Enter、结构大纲优先 |
| `docs/authoring/teacher-usability-checklist.md` | A2–A4 对齐画布操作 |
| `docs/authoring/gui-beginner-guide.html` | 同步关键段落（与 md 一致） |

## 2026-07-20 课程工坊 P3：功能增强

用例数 938 -> 952（+14）。

| 项 | 内容 |
|---|---|
| 聚焦摘要 | `grounded_stats` + Orbit `focus_summary`（全池 / 聚焦气泡） |
| 覆盖率 | 审校页展示池内命中 % / 池外 / `new` 标记 |
| 局部重生成 | 大纲树右键课时/单元 → `regenerate_lesson/unit`；生成前 checkpoint |
| 恢复草稿 | 审校「恢复上一版草稿」 |
| 导入闭环 | 导入成功后询问是否教师模式 + 定位首课（隐藏窗口跳过弹窗） |
| 测试 | grounded_stats、local regen、coverage、focus summary、offer teacher |

## 2026-07-20 课程工坊 P2：性能与卡顿

用例数 931 -> 938（+7）。

| 项 | 内容 |
|---|---|
| 气泡池 | 按 `type:id` 增量 reconcile，保留 widget 实例；`rows_changed` 60ms debounce |
| 流式 JSON | 生成中缓冲 &gt;8KB 只更新摘要标签，完成后一次 `set_json` |
| design autosave | 2s 节流；生成中跳过定时写；`flush_autosave` 供中断/完成 |
| 审校表 | 全选/批量一次 `rows_changed`；`set_all_checked` API |
| 生成路径 | 仍走 `AiRequestWorker`（无同步回归） |
| 测试 | bubble identity/debounce；stream skip setPlainText；select_all emit once |

## 2026-07-20 课程工坊 P1：交互流畅度

用例数 922 -> 931（+9）。在 P0 统一画布之上：

| 项 | 内容 |
|---|---|
| 空状态 | 顶栏可关 banner（QSettings `workshop/canvas_tips_dismissed`）；blank 左 tab 标「可选」+ 默认气泡池/设计 |
| 默认焦点 | 教材无章节→素材 tab；有知识→审校；有草稿→右栏大纲；提取后首次有行自动切审校 |
| UI 状态 | per-project `workshop/ui/{id}/{left_tab,right_tab,splitter}`；关窗/换项目保存 |
| 延迟销毁 | teardown 用 `QTimer.singleShot(0, deleteLater)` 减闪白 |
| 审校 | 空文案画布用语；`humanize_problem` chips + 点击定位树；refresh 静默校验；AI 修复前 `SectionDiffView(confirm=True)` |
| 快捷键 | Esc 确认后取消 busy；Orbit Ctrl+Enter 生成；「将选中词加入轨道」 |
| 测试 | workshop Esc/project_id；workspace save-restore/banner/add-orbit；review confirm fix + humanize chip |

## 2026-07-20 课程工坊 P0：统一画布 + 轻量 checklist（完成半迁移）

用例数 917 -> 922（+5）。完成「六阶段侧栏 → 统一创意画布」迁移收口：

- **`workshop_window.py`**：去掉 stub 六阶段导航；stack 仅 项目库 / 创意画布；头栏 checklist（素材·知识·草稿·导入）；合并重复 `_on_project_selected`；接线 import `busy/usage/autosave` 到底栏；提取中返回项目库需确认取消。
- **`unified_workspace.py`**：左栏 教材/审校/气泡池，中栏 AI Orbit，右栏默认「结构大纲」+「设计与草稿」（完整 DesignPanel，含聊天/模板/JSON）+「章节导入」；气泡池上限 200；Orbit 主题/悄悄话回写 controller。
- **`ai_orbit.py`**：主题输入 +「打开对话/附件/模板」按钮。
- **`knowledge_bubble.py`**：`OpenHandCursor` 兼容（无 GrabCursor 的 Qt 构建）。
- **测试**：重写 `test_workshop_window` 对齐新 IA；新增 `test_unified_workspace`（tabs / generate 参数 / chat 聚焦 / draft 切大纲 / blank 布局）。

## 2026-07-19 tool-gui 使用逻辑改进（AI 冲突确认 + 工坊目标选择 + 越树移动）

用例数 888 -> 917（+29）。三项改动：
- **AI 编辑 unit/lesson id 冲突三选一**：`_on_ai_edit` unit/lesson 分支容忍 AI 改 id、`_detect_ai_edit_conflicts` 检测冲突、`_ask_ai_edit_conflict_resolution` 弹覆盖/重命名追加/取消；重命名追加用 `clone_unit_with_fresh_ids`/`clone_lesson_with_fresh_ids` + `AppendUnitCommand`/`AppendLessonCommand`。新增 `test_app.AiEditConflictTest`（7）。
- **工坊导入目标选择**：`design_panel._on_import` 接入 `ImportTargetDialog`（新 section / 已有 section 加 unit / 已有 unit 加 lesson），目标编码进 strategy 字符串经 `sections_ready` 链传到 `_on_textbook_sections` 分发；`AppendUnitsToSectionCommand`/`AppendLessonsToUnitCommand`（含资源合并+回滚）。新增 `test_import_target_dialog`（5）+ `test_app.WorkshopImportTargetTest`（2）+ `test_commands_and_ai_edit` 2 个命令测试。
- **上下移动越树**：`_move_current` 到边界自动跨越（lesson 跨 unit/section、unit 跨 section），新增 `ReparentLessonCommand`/`ReparentUnitCommand`（snapshot+remove+insert）；`_update_move_buttons` 改按课程首/末判断；tooltip 去"仅同级"。新增 `test_course_tree.CourseTreeCrossTreeMoveTest`（9）+ `test_commands_and_ai_edit.ReparentCommandsTest`（2）+ `AppendUnitCommand`/`CloneUnitFreshIds` 测试。

## 2026-07-19 代码精简 T4（不改功能）

用例数不变（888 passed, skipped=2）。`commands.py` 三个 QUndoCommand 家族抽基类,undo 正确性由 40 处 redo/undo 测试覆盖。净减约 69 行。

| 基类 | 合并 | 覆盖项 |
|------|------|--------|
| `_UpdatePrereqsBase` | 3 个 `UpdateXxxPrereqsCommand` | `_captured` 幂等、self-id 过滤、`_find` 钩子 |
| `_UpdateMetaBase` | 3 个 `UpdateXxxMetaCommand` | `_sync_index` 钩子(Section 同步 index 条目,顺序 set->sync->emit 保留) |
| `_MoveInContainerCommand` | 4 个叶子 Move(Item/SubLesson/Stage/ListeningPhase) | `_move` 钩子委托 move_* 函数,容器统一 `self.container` |
| `_MoveNodeCommand` | MoveUnit/MoveLesson | `_list` 钩子返回 setdefault 列表;MoveSection 保留(3 参签名独特) |

## 2026-07-19 代码精简 T3（不改功能）

用例数不变（888 passed, skipped=2）。中风险重复抽 helper,行为等价,全量测试通过。净减约 112 行。

| 模块 | 文件 | 覆盖项 |
|------|------|--------|
| Qt 信号接线 | `ai_generator_dialog.py` | `_set_busy` 4 处 disconnect/connect 抽 `_reconnect` |
| 网络 kwargs | `ai_generator.py` | 7 处 `request_chat` 抽 `_chat_json`(response_format 默认 None 已核;健康检查 L959 不并入) |
| 错误弹窗 shell | `ai_error_analyzer.py` + `main`/`app`/`ai_fix_dialog`/`ai_lesson_helper_dialog`/`ai_generator_dialog` | 5 处"AI 分析原因" QMessageBox shell 抽 `offer_ai_analysis`(返回 bool;analyzer 调用留各处) |
| 右键菜单 | `course_tree.py` | `_on_context_menu` ~13 处 QAction+connect+addAction 折叠为 `menu.addAction(text, slot)`(带 setShortcut 的 `act_dup_lesson` 保留三行) |
| 节点校验 | `app.py` | 8 处 `validate_section_json` temp-包装抽 `_validate_node(kind, node, check_existing_ids=)`,两处三分支塌缩 |
| undo 删除 | `commands.py` | 5 处 del-by-id 循环抽 `_remove_by_id(lst, id)->int`(4 处存 self.index,1 处 undo 弃返回值) |

## 2026-07-19 代码精简 T1+T2（不改功能）

用例数不变（888 passed, skipped=2）。删除死代码/未用导入/未调用方法，并将重复代码抽为共享 helper；行为等价，全量测试通过。净减约 110 行。

| 模块 | 文件 | 覆盖项 |
|------|------|--------|
| 死代码 / 未用导入 | `theme.py` `ai_error_analyzer.py` `knowledge_extractor.py` `extraction_quality.py` `validation_report.py` `import_step_result.py` `resource_review_table.py` `ai_generator.py` `lesson_content.py` `ai_generator_dialog.py` | 未用 import、死变量链、重复方法 `_active_json_editor`、未调用工厂 `ImportStepResult.warning`/`ResourceReviewTable.add_row`、`if _emit(): pass` 空操作 |
| 冗长等价改写 | `lesson_content.py` `course_tree.py` `settings_dialog.py` `ai_generator_dialog.py` `textbook_import_dialog.py` | 集合推导、海象推导、三元、列表字面量、`_set_busy(False)` 上提 |
| 重复抽 helper | `ai_generator.py` `course_adapter.py` `textbook_import_dialog.py` `ai_generator_dialog.py` `app.py` `settings_dialog.py` `textbook_import_controller.py` | `_extract_content`/`_parse_json_obj`/`_draft_json_suffix`、`release_diff` sections 并入循环、`_populate_review` 三段合并、`_apply_prompt_fields`、`_active_main_window`、`_show_beta_warning_once`、`_make_tab`、`_confirm_clear`、`_ZERO_USAGE` 常量 |

## 2026-07-19 upgradeplus1 第二阶段优化（不改功能）

| 模块 | 文件 | 覆盖项 |
|------|------|--------|
| 教材加载异步化 | `test_textbook_controller.py` `LoadFileAsyncTest` / `test_textbook_view.py` / `test_textbook_e2e.py` | `_read_source_text` 纯函数、同步/异步入口行为一致、PDF 解析失败 recoverable、load_id 守卫丢弃过期结果 |
| 下拉框共享模型 | `test_option_models.py` / `test_question_cards.py` `SharedModelTest` | `build_options_model` placeholder + UserRole、`select_by_id` 定位/回退、两个 QuestionCard 共享同一 vocab/grammar model |
| 项目库 manifest | `test_textbook_project.py` `ProjectSummaryTest` / `test_textbook_library_dialog.py` | `index.json` 首次生成、save/delete 同步更新、mtime 自愈外部修改、损坏回退全量扫描 |
| Git 操作异步化 | `test_git_library_dialog.py` `GitLibraryDialogAsyncTest` | `_run_git_async` worker 包装、成功/失败回调与按钮态、过期 worker 结果被丢弃 |

## 2026-07-18 性能/缺陷/体积优化轮（不改功能）

| 模块 | 文件 | 覆盖项 |
|------|------|--------|
| schema 默认值隔离 | `test_lesson_content.py` | `default_interaction`/`normalize_item` 不共享可变默认值（跨条目污染回归） |
| append-as-new 嵌套 id | `test_section_import_service.py` | 导入时重写 unit/lesson id、源草稿不被原地修改 |
| 进程内校验一致性 | `test_backend_api.py` | `_validate_in_process`/`_lint_in_process` 与子进程结果逐项一致 |
| 流式渲染节流 | `test_design_panel.py` | 解释流 chunk 经 `_flush_stream_views()` 后渲染（节流不变量） |
| usage 守卫 | `test_design_controller.py` | 仅活动 worker 的 usage 计入（失效 worker 丢弃） |

## 2026-07-18 教师模式重构（三面合一 + 编辑器外壳统一 + 发布合并）

| 模块 | 文件 | 覆盖项 |
|------|------|--------|
| 主窗口教师模式 | `test_app.py` | 删除浮动 TeacherWindow；toggle on 内联渲染首课 SubLessonFlowWidget、保留已选课、toggle off 回专家视图且无 `_teacher_window` 属性 |
| 子课流高级编辑 | `test_linear_flow.py` | SubLessonFlowWidget 具"高级编辑"出口、toggle 切到 LessonEditor、toggle 回恢复教师视图与 QuestionCard |
| 课程树模式徽章 | `test_course_tree.py` | 专家模式裸 `lesson (tmpl)` 文本、教师模式友好课型名+`_TEMPLATE_COLORS` 着色、section/unit 类型列置空 |
| 发布对话框合并 | `test_publish_dialog.py` | 专家模式全清单（diff/bump checkbox/确认发布/原始错误 tooltip）、教师模式隐藏工程段+版本自动更新+人话化错误+禁用发布按钮 |
| 按钮文字全局不截断 | `test_button_sizing.py` | app 级过滤器把 QPushButton 水平 policy 置 Minimum（polish 时生效、幂等）、FlowLayout 窄宽 heightForWidth 变高（换行） |

## 2026-07-18 三入口合一 + 工坊 UI 大改（merge overhaul A–D）新增覆盖

| 模块 | 文件 | 覆盖项 |
|------|------|--------|
| 工坊窗口 | `test_workshop_window.py` | 6 阶段侧栏导航/完成态 ✓/门控、统一底栏信号上抛与取消路由、导航行可见性、空白项目直达设计、ui_stage 持久化与降级恢复、last_project_id 自动续作、busy 中断（生成自由切换/提取确认取消）、反复中断幂等 |
| 设计控制器 | `test_design_controller.py` | 附件 content pieces、explain 自动链与错误隔离、Settings(timeout/temperature/retry) 注入、genre 模板替换、图片附件序列化降级、解释恢复 |
| 设计面板 | `test_design_panel.py` | 附件添加/发送/清理（temp 文件无泄漏）、恢复原始输出、模板栏双向同步、genre 入参、解释流式渲染与内联错误 |
| 审校面板 | `test_review_panel.py` | 无草稿/有草稿刷新、编辑器真相（B1）、导入委托、无 adapter diff 提示 |
| 项目库 | `test_textbook_library_dialog.py` | 空白 AI 项目新建/取消/纯 AI 标记列 |
| 项目模型 | `test_textbook_project.py` | ui_stage 可选字段缺省与往返 |

## 2026-07-16 教材导入 Phase 6（收尾）新增覆盖

| 模块 | 文件 | 覆盖项 |
|------|------|--------|
| 附件提取 | `test_attachment_extractor.py` | 缺失文件/不支持扩展名/`.txt`/`.md` 文本/UTF-8 解码失败/`.png` base64 往返/`.pdf` 缺依赖+空页扫描降级+正常抽取/`.docx` 缺依赖/`summarize_attachment` 截断+图片+失败 |
| section level 参数 | `test_textbook_backend.py` | `build_section_from_chapter(level="B1")` 应用 + 默认 A1 |
| 预设契约 | `test_textbook_presets.py` | 全部预设 `lesson_template=intro`、`max_chapter_chars>0`、strategy 合法 |
| Review 页性能 | `test_resource_review_table.py` `ReviewTablePerfTest` | 50×50=2500 行 set_rows、单章过滤 <0.5s、全量刷新 <1.5s、搜索刷新 <0.5s、kept_rows 全量 |

## 2026-07-16 教材导入 Phase 5（AI 能力打通与优化）新增覆盖

| 模块 | 文件 | 覆盖项 |
|------|------|--------|
| 教材类型预设 | `test_textbook_presets.py` | 4 个内置预设（general/grammar/dialogue/reading）、grammar 低温、dialogue 高温、reading vocab_only、未知名回退 general、frozen dataclass |
| Prompt 库 + 语义截断 | `test_knowledge_extractor.py` | `KnowledgePromptLibrary` 按语言对注册/查询/大小写无关/clear、override 注入 messages、`max_chars` 透传、段落边界截断 vs 硬截断回退 |
| 预设参数透传 | `test_textbook_backend.py` | `build_section_from_chapter` 的 `lesson_template`（intro/practice/review + 未知回退 intro） |
| 控制器并发/用量/预设 | `test_textbook_controller.py` `ConcurrencyAndUsageTest` | 并发 2 多 worker 在飞、串行 1 次一个、per-chapter+项目用量累积 + `on_usage_update`、preset 参数（strategy/temperature/max_chars/max_tokens）透传 worker、cancel 取消全部在飞 worker |
| 导入页选项 UI | `test_textbook_view.py` `ExtractionOptionsTest` | 4 个教材类型下拉 + 默认 general、切类型改 controller.preset、并发 spinbox 设 controller.max_concurrent、用量 label 显示项目总量 |

## 2026-07-16 教材导入 Phase 4（合并与导入策略）新增覆盖

| 模块 | 文件 | 覆盖项 |
|------|------|--------|
| 知识点合并 | `test_knowledge_merger.py` | `resource_key` 标点/大小写归一、项目内重复（词/语法按 title）检测、与现有课程碰撞检测、course 碰撞优先于 intra-project、`apply` 改写 id、幂等、空 course id 仅记录不改写 |
| 导入策略 | `test_import_strategy.py` | `resolve_action` 无碰撞一律 append / 碰撞时 merge(默认)/skip/replace/append_new、`unique_section_id` 后缀、`plan_bulk_import` 顺序分配 append_new 唯一 id、skip 不消费 id |
| 导入策略接线 | `test_textbook_import_helper.py` `ImportStrategyTest` | skip 跳过已存在、force_replace 覆盖（AiEditSectionCommand）、append_new 生成唯一 id、默认策略保持 AI 生成器行为 |
| 控制器预览/合并 | `test_textbook_controller.py` `PreviewAndMergeTest` | `preview_import` 新章节 append / 课程碰撞标记 / append_new 目标 id / 空项目返回 [] / 只读不改写、`merge_knowledge` 项目内去重 + 幂等 |
| 批量预览面板 | `test_bulk_import_preview_panel.py` | 动作中文标签、append/merge/skip/replace/append_new 行渲染、append_new 显示 `源 -> 目标` id、新增/重复资源计数、汇总文案、`clear` |
| 导入页 UI | `test_textbook_view.py` `ImportPreviewPageTest` | 4 个策略单选 + 默认 merge、`_goto_import_preview` 填充面板、切策略刷新预览动作、确认导入带策略发信号 |

## 2026-07-16 操作日志（Operation Log）新增覆盖

| 模块 | 文件 | 覆盖项 |
|------|------|--------|
| 操作日志单例 | `test_operations_log.py` | `record_action` 写 `ui.*` 事件 + target、payload 合并、显式 `<redacted>`、`recent_events` 前缀过滤与顺序、`clear` 不影响 telemetry |
| 用户动作过滤器 | `test_user_action_filter.py` | 点击→`ui.click` 含 target、密码字段 `text` 与 target 均 `<redacted>`、过滤器永不抛异常且恒返回 False |
| 窗口运行时长 | `test_window_usage.py` | `WindowUsageMixin` show/close 记 `window.duration`、自定义 closeEvent 经 super 仍记录 |
| 设置对话框 | `test_settings_dialog.py` | 第 5 个 tab「操作日志」存在、刷新不抛异常、清空接线到 `operations.clear` |

## 2026-07-15 三项可用性改动新增覆盖

| 模块 | 文件 | 覆盖项 |
|------|------|--------|
| 课程树上下移 | `test_commands_and_ai_edit.py` | `MoveSection/Unit/LessonCommand` undo、边界 no-op、lesson 移动保持层级 |
| 课程树上下移 | `test_course_tree.py` | `_move_current` 同级重排、边界 no-op、移动后选中保持、↑/↓ 按钮启用态 |
| 教师模式弹窗 | `test_app.py` | toggle on 主动开窗、无选中默认首节课、toggle off 关窗、关窗自动 uncheck |
| AI 生成页 2 列 + JSON 独立窗口 | `test_ai_generator_dialog.py` | 普通/许愿 2 列 splitter、JSON 窗口 reparent + `_current_json` 一致、关对话框清理 JSON 窗口 |

## P4 + P6 新增覆盖

| 模块 | 文件 | 覆盖项 |
|------|------|--------|
| 供应商/价目 | `test_ai_presets.py` | 预设填充、自定义保护、价目命中与回退、成本估算 |
| Prompt 库 | `test_ai_prompt_library.py` | 模板保存/覆盖/删除、历史去重与上限、spec 应用 |
| Settings | `test_settings.py` | provider/timeout/temperature/reasoning 加载、保存、clone、clamp |
| AI 生成器 | `test_ai_generator.py` | genre 多 tag 检测与分配、`apply_genre_to_spec` 多 tag 行为、`verify_connection`、explain 失败抛异常 |
| AI 生成器对话框 | `test_ai_generator_dialog.py` | 编辑/修正模式不校验现有 id、offscreen 退出稳定 |
| 课程适配器 | `test_course_adapter.py` | `validate_section_json` 开关现有 id 校验、`plan_section_merge` 新增/覆盖/资源合并 |
| 命令层 | `test_commands_and_ai_edit.py` | `MergeAiSectionCommand` 替换 unit、追加 lesson、undo 还原 |
| Telemetry | `test_telemetry.py` | `usage_summary` 聚合、`clear` 清空 |
| 成本估算 | `test_ai_usage.py` | 未知模型 token-only 显示 |

## 已知环境限制

- `test_app.py` 会实例化 `MainWindow`，在 headless/offscreen 环境下可能崩溃；请在本地图形环境运行。
- 部分 GUI widget 测试依赖 `QT_QPA_PLATFORM=offscreen`，在本机普通环境下可直接运行。
