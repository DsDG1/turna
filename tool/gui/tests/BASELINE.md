# GUI Python 测试基线

> 记录 `tool/gui/tests/` 下的用例数与关键覆盖项，便于每轮变更后快速对比回归。

## 当前基线

- 日期：2026-07-19
- 全量用例：888 passed（含 `test_app.py`；skipped=2），命令：
  ```bash
  QT_QPA_PLATFORM=offscreen python -m unittest discover -s tests -p "test_*.py"
  ```

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
