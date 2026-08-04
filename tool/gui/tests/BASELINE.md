# GUI Python 测试基线

> 记录 `tool/gui/tests/` 下的用例数与关键覆盖项，便于每轮变更后快速对比回归。

 ## 当前基线

- 日期：2026-08-05（Turna wetland palette ADR 0033：`BRAND_CLAY`/`BRAND_SAND` 常量 + Flutter 核心 hex 对照含 clay/sand/tealDark；`tests.test_theme` 29 OK）
- 主题专项：`python -m unittest tests.test_theme` → 29 passed
- 全量用例（上次记录）：1276 passed（skipped=2），命令：
  ```bash
  QT_QPA_PLATFORM=offscreen python3 -m unittest discover -s tests -p "test_*.py"
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
