# 长期改进台账

> 出处：《Turna GUI 易用性/逻辑问题修复计划（2026-09-28）》§4.16 —— 四个修复批次（1.1–4.15）
> 全部完成后**有意不做**、按计划记账的长期项。本文件是这些项在仓库内的唯一台账：
> 计划文档本身在仓库外，不可作为施工依据。
>
> 动手前用符号名二次定位（行号会漂移）。每完成一项就把它从本表移除，
> 并在 `tests/BASELINE.md` 顶部记录对应批次的基线变化。

| # | 事项 | 现状锚点 | 说明 |
|---|---|---|---|
| 1 | 审校表编辑接入 undo | `widgets/resource_review_table.py`（编辑/删除不入 QUndoStack，删除已有确认但不可撤销） | 补测时注意与「删除选中不进撤销栈」的现有提示文案同步 |
| 2 | 关闭路径保存异步化 | `application/close_controller.py`（同步 `execute_save` + `wait(5000)`，T18 已限界） | 关窗需要确定性完成，异步化须先设计「保存完成前拒绝二次关闭」 |
| 3 | Anki 导入能力接入 UI 或删除宣称 | `backend/anki_import.py`（模块 docstring 宣称的 UI 集成不存在；生产仅 `teacher/question_cards.py` 借用 `_strip_html`） | 若删除，`_strip_html` 需先迁走 |
| 4 | 冲突预览着色死代码清理 | `widgets/bulk_import_preview_panel.py`（着色分支无数据可触发） | 删除前核实是否为将来 diff 视图预留 |
| 5 | 步骤术语三套并存收敛 | 库 6 步 / 画布 4 阶段（`widgets/workshop_canvas.py`）/ 向导 3 阶段（`dialogs/textbook_import_dialog.py`） | 纯内部概念，收敛属可读性投资，无行为收益 |
| 6 | 提取自动保存 status_hook 接线 | `dialogs/textbook_import/persistence.py` 的 `status_hook` 形参 ↔ `textbook_import_controller.py` 只读 `getattr(self, "_status_hook", None)`，该属性从未被赋值 | 接线后自动保存失败才能进状态栏，否则静默 |
| 7 | textbook store 迁移 QStandardPaths | `dialogs/textbook_import/`（store 目录自管） | 迁移涉及存量数据路径兼容，需迁移逻辑而非改常量 |
| 8 | ExperienceTimeline 整链接线或退役 | `backend/experience/timeline.py`（backend 123 行零实例化；Dock「最近」恒空；⌘K 历史重放恒空） | 2026-09-28 逻辑审查 D1：需产品决策。接线＝`_record_experience_event`→Timeline→Dock/⌘K；退役＝按 json_path_skill 先例整链删除 |
| 9 | AuthorMemory 写入 / ProjectMemory 读取接线 | `backend/experience/memory.py`（`add_style_hint`/`set_language_pref` 生产零调用；`recent_skills`/`preferred_templates` 只写不读） | D2：画像恒空 + 项目记忆无消费方。接线点在改题应用路径与 palette 入口 |
| 10 | CourseSession 属性袋收敛 | `application/course_session.py`（五个信号零订阅；`select_node`/`set_teacher_mode`/`close_course` 无人调用） | D3：teacher_mode 实际由 MainWindow property 直管；收敛需先统一 owner |
| 11 | defer/save-brief 状态持久化 | `experience_defer_json` / `experience_save_brief`（`ambient_controller.py`/`save_host.py` 写入但 Settings 无字段不落盘） | D5：补 Settings 字段或删功能；save-brief 链生产不可达 |
| 12 | 死代码清理批次 | `save_host.run_async_direct_save` / `save_host.on_save` / `ai_stream.iter_sse`（零生产调用）；`HANDLER_OPTIONAL_ACTIONS` 的 `help.tour`；palette 死条目 `quality.campaign_worst_n`/`unit.regenerate`/`section.edit`/`unit.edit`；死设置 `ai_config_file_path/autoload/autosave`；三阶段 stepper 死 UI（`workshop_window.py:570`）等 | D6/D7/D8/D9：逐项删除（删除 `ai_config_file_*` 需注明"key 落盘后门已随删除关闭"） |
| 13 | ReviewPanel 清待补裸 worker 接入 hub | `widgets/review_panel.py`（`_on_fill_needs_review` 闭包不收 kwargs → cancel_check 注入失败；无 `_closing` 守卫） | 审查 C8：需重构为 GeneratorWorkerHub 成员 |
| 14 | 取消语义收尾：单槽 worker hub 化 | `main_window_shell.cancel_in_flight_ai_jobs` 只认 4 个命名属性（`_experience_worker`/`_chip_ai_worker` 等） | 审查 C9 余项：并发覆盖单槽仍不可取消；改 worker hub（同 C8） |
| 15 | git/资源冲突路径指引补全 | pull 冲突 stash pop 失败只报"恢复改动失败"（`git_library/sync.py`）；resource 同 id 异内容永久分歧不提示（`course_exchange.py`）；expressions_version 无条件覆盖 | 审查 C16：交互文案与检测补全，非逻辑错误 |
| 16 | 杂项 UI/健壮性 | 主题切换后 QIcon/JSON 高亮/阴影不刷新；`chevron-right` 图标不存在；TEMPLATE_LABELS 双表；`experience_shell` focus-only 重建漏传 `ocr_enabled`；`.doc` 提取永不成功；OCR 部分页静默丢失；`course_scaffold` 半成品目录堵死重试；`import_resource_pack` 无 id 条目静默丢弃；图标名无存在性校验 | 审查 E6：按需排期 |
| 17 | 版本链闭环：tag 回写 pyproject + extras 进包 | `gui_release.yml`（`gui-v*` tag 不回写版本 → exe 恒 0.0.0；ocr/voice extras 不在 hiddenimports 且构建环境不装 → 发布版静默缺 OCR/语音） | 审查 E3：发布管线改动，需在打 tag 流程中验证 |
| 18 | telemetry 初始化副作用 + 日志上限 | `telemetry.py`（opt-out 仍建文件；`operations.log` 无上限；多进程共写轮转日志 Windows 午夜轮转会失败） | 审查 E5：延迟初始化 + maxBytes/backupCount |
| 19 | git 重载路径的脏保存覆盖 | 2026-09-28 复审：pull/切分支后的强制重载（B2）在内存有未保存编辑时走标准三选提示，选「保存」会把拉取前的旧内存全量写回刚拉取的目录 | 根治需在 git 操作前查脏并指引 stash，属交互设计项；当前至少有显式确认 |
| 20 | 断路器 HALF_OPEN 试探 TTL 复用 reset_timeout | 复审：试探时间戳 60s 后过期，运行超过 60s 的长试探会允许第二个试探并发（单试探承诺对长任务不成立）；试探结果丢失时需等满 60s 才放行 | 有界无害；如需严格，可为试探挂存活信号 |
