# 长期改进台账

> 出处：《Turna GUI 易用性/逻辑问题修复计划（2026-09-28）》§4.16 —— 四个修复批次（1.1–4.15）
> 全部完成后**有意不做**、按计划记账的长期项。本文件是这些项在仓库内的唯一台账：
> 计划文档本身在仓库外，不可作为施工依据。
>
> 动手前用符号名二次定位（行号会漂移）。每完成一项就把它从本表移除，
> 并在 `tests/BASELINE.md` 顶部记录对应批次的基线变化。

## 2026-10-20 已完成（从本表移除，摘要见 `tests/BASELINE.md` 当日条目）

原编号 2 / 6 / 8 / 9 / 11 / 17，以及原 12 / 14 / 16 / 18 的部分条目。

- **2 关闭路径保存异步化** —— `close_controller._start_close_save`：保存走 worker，
  完成后 `host.close()` 自行关窗；保存中二次关闭被拒绝并提示。
- **6 提取自动保存 status_hook 接线** —— controller 加 `on_status` 回调，
  dialog 侧接状态灯与日志（自动保存失败不再静默）。
- **8 ExperienceTimeline 整链接线** —— MainWindow 实例化 timeline；
  `record_experience_event` 写入并刷新 Dock；`timeline_clicked` 接上派发。
  Dock「最近」与 ⌘K 历史重放不再是恒空。
- **9 AuthorMemory 写入 / ProjectMemory 读取接线** —— 课程加载记语言偏好、
  chip 改题记作者风格；命令面板显示「常用」技能行。
- **11 defer/save-brief 状态持久化** —— `experience_defer_json` /
  `experience_save_brief` 补进 Settings（含存/取），功能不再恒关。
- **12 死代码清理批次（部分）** —— 删 `save_host.run_async_direct_save`、
  `ai_runtime.empty_ai_runtime`、`goal_controller.run_sandbox_for_host`、
  `shell_views.current_view`、`course_media.media_ref_for_filename`、
  `goal_generate.extract_lesson_from_section`，以及三个零引用的 `ai_config_file_*`
  设置（其 QSettings key 随删除变成孤儿，无害）。
  **原列表里的 `ai_stream.iter_sse` 与 `save_host.on_save` 复核后确认仍被测试调用，
  不是死代码；palette 死条目 `quality.campaign_worst_n` / `unit.regenerate` /
  `section.edit` / `unit.edit` 复核后确认仍在用，不删。**
- **14 取消语义（部分）** —— `cancel_in_flight_ai_jobs` 改走共享清单
  `AI_WORKER_ATTRS`（8 个属性，原只认 4 个）。**保存 worker 刻意不在取消清单内**
  （保存不是 AI 请求，打断会留下不一致状态），但它在关窗清单 `IN_FLIGHT_WORKER_ATTRS` 内。
  「单槽 worker hub 化」余项见下表 #14。
- **16 杂项 UI/健壮性（部分）** —— `chevron-right` 图标已补（Lucide 同源 SVG），
  并新增 `tests/test_icon_names.py`：所有 `icon("…")` 引用必须有对应 SVG。
- **17 版本链闭环（部分）** —— `gui_release.yml` 改装 `[dev,ocr,voice]`，
  `turna_gui.spec` 补 `pytesseract`/`PIL`/`fitz`/`speech_recognition`/`pyaudio` 的
  hiddenimports；`gui-v*` tag 回写 `pyproject.toml` 版本号，
  `build_gui.py` 加 `--version`。**tag 流程仍需在真机上验证一次。**
- **18 telemetry 初始化副作用 + 日志上限（部分）** —— 日志加体积上限
  （8 MB × 3 备份），`usage_summary` 改增量解析（inode + 字节偏移游标）。
  **「opt-out 仍建文件」与「多进程共写轮转日志」仍未处理。**

## 剩余事项

| # | 事项 | 现状锚点 | 说明 |
|---|---|---|---|
| 1 | 审校表编辑接入 undo | `widgets/resource_review_table.py`（编辑/删除不入 QUndoStack，删除已有确认但不可撤销） | 补测时注意与「删除选中不进撤销栈」的现有提示文案同步 |
| 3 | Anki 导入能力接入 UI 或删除宣称 | `backend/anki_import.py`（模块 docstring 宣称的 UI 集成不存在；生产仅 `teacher/question_cards.py` 借用 `_strip_html`） | 若删除，`_strip_html` 需先迁走 |
| 4 | 冲突预览着色死代码清理 | `widgets/bulk_import_preview_panel.py`（着色分支无数据可触发） | 删除前核实是否为将来 diff 视图预留 |
| 5 | 步骤术语三套并存收敛 | 库 6 步 / 画布 4 阶段（`widgets/workshop_canvas.py`）/ 向导 3 阶段（`dialogs/textbook_import_dialog.py`） | 纯内部概念，收敛属可读性投资，无行为收益 |
| 7 | textbook store 迁移 QStandardPaths | `dialogs/textbook_import/`（store 目录自管） | 迁移涉及存量数据路径兼容，需迁移逻辑而非改常量 |
| 10 | CourseSession 属性袋收敛 | `application/course_session.py`（五个信号零订阅；`select_node`/`set_teacher_mode`/`close_course` 无人调用） | D3：teacher_mode 实际由 MainWindow property 直管；收敛需先统一 owner |
| 12b | 死代码清理批次（余项） | `HANDLER_OPTIONAL_ACTIONS` 的 `help.tour`；三阶段 stepper 死 UI（`workshop_window.py:570`） | D6/D7/D8/D9 剩余项 |
| 13 | ReviewPanel 清待补裸 worker 接入 hub | `widgets/review_panel.py`（`_on_fill_needs_review` 闭包不收 kwargs → cancel_check 注入失败；无 `_closing` 守卫） | 审查 C8：需重构为 GeneratorWorkerHub 成员 |
| 14b | 取消语义收尾：单槽 worker hub 化 | 并发覆盖单槽仍不可取消 | 审查 C9 余项；改 worker hub（同 #13） |
| 15 | git/资源冲突路径指引补全 | pull 冲突 stash pop 失败只报"恢复改动失败"（`git_library/sync.py`）；resource 同 id 异内容永久分歧不提示（`course_exchange.py`）；expressions_version 无条件覆盖 | 审查 C16：交互文案与检测补全，非逻辑错误 |
| 16b | 杂项 UI/健壮性（余项） | 主题切换后 QIcon/JSON 高亮/阴影不刷新；TEMPLATE_LABELS 双表；`experience_shell` focus-only 重建漏传 `ocr_enabled`；`.doc` 提取永不成功；OCR 部分页静默丢失；`course_scaffold` 半成品目录堵死重试；`import_resource_pack` 无 id 条目静默丢弃 | 审查 E6：按需排期 |
| 18b | telemetry 初始化副作用 + 多进程轮转 | `telemetry.py`（opt-out 仍建文件；多进程共写轮转日志 Windows 午夜轮转会失败） | 审查 E5：延迟初始化 + 按 PID 分文件或独占打开 |
| 19 | git 重载路径的脏保存覆盖 | 2026-09-28 复审：pull/切分支后的强制重载（B2）在内存有未保存编辑时走标准三选提示，选「保存」会把拉取前的旧内存全量写回刚拉取的目录 | 根治需在 git 操作前查脏并指引 stash，属交互设计项；当前至少有显式确认 |
| 20 | 断路器 HALF_OPEN 试探 TTL 复用 reset_timeout | 复审：试探时间戳 60s 后过期，运行超过 60s 的长试探会允许第二个试探并发（单试探承诺对长任务不成立）；试探结果丢失时需等满 60s 才放行 | 有界无害；如需严格，可为试探挂存活信号 |
