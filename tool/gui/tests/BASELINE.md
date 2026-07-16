# GUI Python 测试基线

> 记录 `tool/gui/tests/` 下的用例数与关键覆盖项，便于每轮变更后快速对比回归。

## 当前基线

- 日期：2026-07-17
- 后端/可沙箱运行用例：733 passed（排除 `test_app.py`，该文件需在支持 Qt 显示的本机环境运行；含 `test_app.py` 共 752 passed）
- 运行命令：
  ```bash
  QT_QPA_PLATFORM=offscreen python -m pytest tests/ --ignore=tests/test_app.py -q
  # 或（无 pytest 时）：QT_QPA_PLATFORM=offscreen python -m unittest discover -s tests -p "test_*.py"
  ```

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
