# Test Baseline

Generated: 2026-08-05 (宝石装饰兑换第一步：`GemsProvider.spendGems` + `CosmeticProvider` 头像环三款（晨雾/芦苇/湖光）；设置→账户→装扮列表；Profile/账户头像 `AvatarWithRing`；导出 key + 账户重置清装扮。新增 `gems_spend_test` 4 + `cosmetic_provider_test` 6；账户设置 widget 测试补 CosmeticProvider。相关定向测试 **13 passed**。全量预计 **875** = 865+10。)

Previous: Generated: 2026-08-05 (Android 状态栏对齐：`colors.xml` + light/night/v27 styles；`TurnaTheme.systemUiOverlayFor` + 四套 AppBarTheme；`_AppShell` 随主题应用 SystemChrome；launch_background 雾色/深色 scaffold；wetland 契约 +7。`flutter test`：**865 passed / 0 failed**。)

Previous: Generated: 2026-08-05 (湿地鹤 palette polish：ADR 0033 角色边界；`primaryCtaDecoration` 挂 Splash/Check/Continue；`contrastRatio` 闸门；成就区 clay icon；完美 pill 细环；nodeGlow 用 brandReed；withOpacity→withValues；GUI secondary 深色 hover；golden failures gitignore；wetland contract 扩至 ~18 断言；renderer 测试跟进 InkWell CTA。`flutter test`：**858 passed / 0 failed**。)

Previous: Generated: 2026-08-05 (Turna「湿地鹤」ADR 0033 palette: scheme A lock `#1F727E`; delete `peacock*` aliases; clay productization on course-tree complete/perfect, profile XP accent, About brand strip, Play Hub weak-words secondary tint; GUI `BRAND_CLAY`/`BRAND_SAND` + fallbacks; play_hub light/dark goldens refreshed; new `test/views/wetland_palette_contract_test.dart` (+11). Unrelated compile fix: `ReviewRatingBar`/`ReviewEmptyState`/`ReviewCompletionState` AppStrings defaults via initializer list. `flutter analyze`: no errors. `flutter test`: **851 passed / 0 failed**. GUI `tests.test_theme`: 29 OK.)

Previous: Generated: 2026-08-01 (code-review 修复 8 项 Anki/SRS 工作树问题。(1) `anki_deck_assembler`：空 Default(id=1)+有卡子牌组+另一顶层牌组时不再丢弃 Default 致 `COUNT_RECONCILIATION_FAILED`——topLevelDecks 过滤加 `_deckTreeHasCards`（Default 或其任意子牌组有卡则保留为顶层 section，子牌组作为 descendants 被索引）。(2) wordId `-n<noteId>`->`-c<cardId>` 透视无 migration：schema v13->v14 加 `_rekeyLegacyAnkiWordIds`，用 `anki_cards_meta`(import_id,note_id)->word_id 把 `srs_states.word_id` 与 `review_events.card_id` 旧 `-n` 行重键为 `-c`；srs_states PK 冲突（pivot 后重导入）时删旧行而非碰撞。(5) `anki_review_assembler._indexLessonInteractions`：删死的 note-key 索引（`anki-<imp>-n<noteId>` 永不被 card-based 查询读）+ stale「mirror the fallback」注释 + 未用 `importId` 形参/局部。(8) `course_repository.lessonsContainingAny`：needle 加 `-c` ord 分隔符锚定，修 `c45`⊂`c450` 前缀碰撞（互动 id 恒为 `${wordId}-c${ord}` 故 `${wordId}-c` 必命中且不误匹配），doc 注释由 `-n` 改 card-level。(3) `anki_note_dao.upsertCardMetaBatch`：既有卡探针改分块 bound params（避免 5000 元素 literal IN）+ 状态 UPDATE 进同一 `batch`（`b.customStatement` bound params，单事务，null bind 为 NULL）替代 N 次 auto-commit `setCardState`。(4) `searchNotes`：删 per-row `_withState` N+1，改 `_applyStateBatch` 单分块查询（N+1->2）。(6) `anki_import_dao.getAll`：删 `_toRecord` per-row 重查 anki_imports，改单 lifecycle 批查询 + 抽 `_toRecordWithLifecycle`（typed row + 一次 lifecycle）。(7) `setDailyLimits`/`_readLimit`/`setCardState`/`clearBuriedBefore`/`flaggedCards`/`upsertCardMeta`/`_withState` 的 `_sqlLiteral` 字符串插值全改 bound params（`Variable.withString`/`withInt` + `customStatement(sql, args)`），删两处 `_sqlLiteral` 死定义。新测试：`schema_migration_test`「v13->v14 re-keys legacy note-based Anki word ids to card-level」+「v15->v14 downgrade wipes and recreates」（原 `_CourseDatabaseV14` 降级 mock 升 `_CourseDatabaseV15` 因真实 schema 已 v14，新增 `_CourseDatabaseV13`）；`anki_deck_assembler_test`「empty Default deck with card-carrying subdecks is kept (no orphaned cards)」回归。`flutter analyze`：0 error/0 warning on 改动文件（仅预存在 info：doc `<>` 与 `use_super_parameters`）。`flutter test`：800/0 green（+2）。)

Previous: Generated: 2026-07-31 (anki P0 完成度：导入预览可编辑 notetype 映射 + 样例卡预览 + 接入 AnkiNotetypeAI「AI 智能识别」按钮 + 删除 AnkiCardEnhancer 死代码。`lib/views/anki/anki_import_screen.dart` 预览步 notetype 映射卡改 `_NotetypeMappingRow`（`DropdownButtonFormField<NotetypeMappingType>` 9 项下拉覆盖 type，保留推断字段索引；override 经 `mappingOverrides` 端到端生效）+ 每行 `visibility` 预览按钮弹 `_NotetypeSampleDialog`（取该 mid 首张 note，按映射字段索引显示 front/back，`AnkiCardAdapter.stripHtmlPublic` 去标签）；预览页加「AI 智能识别」`OutlinedButton.icon`，`config.isComplete` 守卫，调 `AnkiNotetypeAI().identifyAll`，loading 态 `_isAiIdentifying`，未配置弹 `aiNotConfiguredTitle` 对话框。新增 `_mappingTypeLabel` 顶层函数 + `_PreviewField` widget。`lib/l10n/app_strings.dart` +17 串（ankiAiIdentify/Identifying/NotConfiguredMessage + 9 ankiMappingType* + ankiNotetypePreview/Fields/SampleFront/SampleBack + ankiMappingOverrideHint）。删 `lib/application/anki/anki_card_enhancer.dart`（全仓零调用、零测试、无 DI，仅 design doc §7.2 提及）。新测试 `anki_deck_assembler_test`「mappingOverrides are respected (swapped front/back field indices)」——交换 front/back 字段索引断言 MultipleChoice.prompt 从 'Question 0' 变 'Answer 0'，固化 override 端到端生效。`flutter analyze`：0 error/0 warning on 改动文件（仅 1 info `DropdownButtonFormField.value` deprecated，与既有 `textbook_import_page.dart` 用法一致，受控语义需要 value 故保留）。)

Previous: Generated: 2026-07-31 (anki deep-adaptation 阶段 1: NoteStore + card-level wordId. schema v8->v9 加 `anki_notetypes`/`anki_notes`/`anki_cards_meta` 三表 + `AnkiNoteDao`(CRUD/批次/级联删除)+ `AnkiNotetype.css` 字段。`anki_importer._parseNotetypes` 读 css;`anki_deck_assembler.assemble` 加可选 `AnkiNoteDao?` 写 NoteStore(notetypes 含 templates+css+allowJs、notes 原始 HTML、cards_meta card 级 wordId);`anki_import_screen` 传 noteDao。wordId 全链路 note 级 `n<noteId>` -> card 级 `c<cardId>`(决策 2,clean break,无 migration):`anki_srs_migrator`/`anki_card_adapter` 产出 + `importIdFromWordId`/`_extractImportId` 解析 + `detectNewNotes`/import_screen 碰撞检测改"任一 card 在 SRS 即算已导入" + 删死码 `_extractNoteId`。`anki_deck_manager.uninstallDeck` 加 NoteStore 级联删除 + 构造注入 `_noteDao`。修预存在 `anki_notetype_ai.dart` 漏分号语法错误(WIP bug)。新测试:`anki_note_dao_test`(4)、`schema_migration_test` v6->v9 + v10->v9 降级。修原红的 `anki_srs_migrator_test` revlog(wordId 格式不匹配)+ `anki_review_assembler_test`/`review_progress_provider_test` 改 c 格式。剩 1 个预存在失败:`anki_deck_assembler_test` "Front/Back"(预存在 adapter "embedded A/B/C options" WIP 改动导致,隔离测试证明与 wordId 改动无关)。)

Generated: 2026-07-29 (play_hub 半拟物彩色玻璃 + 轻微悬浮。`lib/views/play/play_hub_screen.dart` 加极光底层 `_AuroraBackground`（3 个 `RadialGradient` 光斑：左上 peacockTeal、右上 peacockCyan、底部中央 leagueAmethyst，浅深色 alpha 自动分支）+ 单层 `BackdropFilter(ImageFilter.blur(sigma 18))` + `RepaintBoundary` 隔离滚动；4 类卡片（_PlayHubCard / _FocusCard / _ReviewCell / _CountBadge）统一走新增私有 `_GlassCard` 容器，组合 4 层：基座（白霜/深色玻璃底 + 1px 描边 + 分层阴影）+ `ClipRRect` 圆角 + accent 着色渐变 + 顶部白色高光条。`PageController` 提升为 `_PlayHubScreenState` 的 `late final`，消除每次 build 重建；`PlayHubScreen` 由 `StatelessWidget` 改 `StatefulWidget`。`lib/views/theme.dart` 新增 6 个静态 helper：`glassSurface` / `glassHighlight` / `glassBorder` / `glassAccentFill` / `glassShadow` / `glassBadgeFill`，全部基于 `_isDark(context)` 自动切深浅。重新生成 `play_hub_light.png` / `play_hub_dark.png` 两个 golden 基线。无新增/删除测试。)

Previous: 2026-07-17 (tool-gui workshop2：主课程编辑器功能课向导 + 可视化蓝图 + 批量/快捷键 + 课程总览。P1 预设库 `backend/lesson_presets.py`（FUNCTIONAL_PRESETS：听力三阶段/阅读三类题/综合测验/认识新词三步/巩固练习 + `build_preset_lesson`/`apply_preset_to_lesson`）+ `clone_lesson_with_fresh_ids` + `CourseAdapter.duplicate_lesson` + 新命令 `DuplicateLessonCommand`/`BulkDelete/Duplicate/Move/ApplyPreset`；课程树 `ExtendedSelection` + `keyPressEvent`（Ctrl+D 复制 · Delete 删除 · F2 重命名 · Ctrl+↑/↓ 同级移动）+ 批量菜单（复制/移动/套用预设/删除）。P3 `widgets/lesson_blueprint.py`（LessonBlueprint 卡片流蓝图，只读预览 + 命令化就地编辑），`DetailPanel` 加「蓝图/高级编辑」切换，功能课型默认蓝图。P2 `dialogs/functional_lesson_wizard.py`（3 步向导：选类型+预设 -> 配置 -> 蓝图预览，`NewLessonDialog` 加「向导创建」入口 + 单元右键「功能课向导…」）。P4 `widgets/course_overview.py`（CourseOverviewWindow 非模态总览，Section/Unit/Lesson 芯片 + 课型 badge + 统计，点击定位）。P5 批量套用预设/批量移动。新增测试 `test_lesson_presets` 13、`test_commands_bulk` 12、`test_lesson_blueprint` 12、`test_functional_lesson_wizard` 6、`test_course_overview` 4、`test_course_tree` 增键盘+批量 7。)

Previous: 2026-07-16 (Flutter app i18n + 分层 Settings。Task 1：把 lib/ 内中文 UI 文案与 AI prompt 脚手架全部改英文（AI 回复仍按 source language；ai_prompt_builder/ai_course_service 加 "reply in source language" 指令保输出语言）。改 `interactionTypeLabel`、`ai_genre` 的 label/description/`templateLabels` 与 `genrePromptBlock`、`ai_resource_consistency` 校验信息、`ai_course_service` 异常信息与 prompt、`ai_hint_provider` 讲解 prompt。UI 文案：play_hub/ai_hint_chat/new_lesson/ai_hint_sheet/mistake_review/review_components/srs_review/grammar_review/mistake_review_assembler。Task 2：`SettingsPage` 由单页改 StatefulWidget + 页内状态导航（`_category`：null=分类列表，0..4=Account/Learning/Audio & Display/Data/About 子页），复用现有 tile 与 bottom sheet；`SettingsAppBar` 降为零高度 stub，避免双层 AppBar；不走 AutoRoute，"去设置" TabRouter 切 tab 行为不变。同步更新 `ai_genre_test`/`ai_prompt_builder_test`/`ai_hint_provider_test`/`play_hub_screen_test` 的中文断言，重新生成 play_hub light/dark golden。）

Previous: 2026-07-15 (tool-gui guiplan2 阶段 P3：结构化预览 + JSON 智能编辑 + diff。新增 `src/widgets/json_editor.py`（JsonEditor：QSyntaxHighlighter 高亮 + Ctrl+Shift+F 格式化 + 错误行红标跳转 + set_json/to_json）。`ResultPreviewWidget` 加 QTreeWidget 结构树（Section→Unit→Lesson→subLesson/stage/listeningPhase→item，点节点发 `node_activated(id)` → dialog 跳 JSON 行；`_on_validate` 后用 `error_mapper.parse_path` 把 error 标红到对应 unit/lesson 节点 + humanize_problem tooltip）。wish 模式加同款 `wish_json_edit`，`_current_json()` 改为按模式读编辑器（修 B1/C4，`_generated` 仅作恢复快照），`_on_reset` 按模式重置。新增 `src/widgets/diff_view.py`（SectionDiffView：`full_section_diff` 增删改三色树，"查看 diff" 按钮在编辑模式可见）。新增 `full_section_diff` 纯函数（复用 `_section_unit_ids` 等，added/removed/changed by json.dumps fingerprint）。`LessonPreviewDialog`/`_PreviewCard` 加可选 `vocab_override`，"试做" 按钮用生成 section 的 words 构造 override，未导入也能查译文。新增 `test_json_editor.py` 5 + `test_diff_view.py` 4 + `test_ai_generator_dialog.py` B1 回归 3。)

Previous: tool-gui guiplan2 阶段 P5：排版归一 + 主题统一。拆出 `src/dialogs/ai/` 包：`worker.py`（AiRequestWorker/_AttachmentRecord）、`chat_view.py`（ChatView + 纯渲染函数，无 PySide6 可单测）、`prompt_template_bar.py`（单一共享模板选择器，修 B8——`_build_template_selector` 原两次调用覆盖 combo/cards/genre_switch，改为单实例 + `_update_mode_ui` reparent）、`chat_expand_window.py`（真子窗口，几何存 QSettings，第二 ChatView 共享 _messages，替代 resize/hide-chrome hack）。修 wish 模式 `_current_spec` topic 取值（原读 normal-only 孤儿 topic_edit，改按模式取 last user message）。`theme.py` 加 `ai_*` palette 键 + `current_palette()`/`ai_color()`，dialog 内联 hex 全部走 `_pal()` 查询。许愿一屏化：3 段 QSplitter（chat / 折叠结果摘要 / 输入），结果默认折叠为「✓ 已生成 · N 单元 · M 课时 · K 词」，解释就绪自动展开。可访问性：Enter 发送 checkbox（默认 ON）、Tab 顺序、附件 × tooltip + Delete 提示。附带修复 P2 残留回归：`test_ai_generator_dialog.py` 三个普通模式用例的 patch 目标 `generate_from_chat` → `request_course_with_retry`。新增 `test_ai_chat_view.py` 11。全量 GUI 套件 offscreen 本机可跑。

Previous: tool-gui guiplan2 阶段 P2：校验自愈 + 局部重生成。修 C3（普通模式接通 `request_course_with_retry`，校验错自动回灌一轮）/C5（编辑模式 lesson/unit 级走局部重生成 `regenerate_lesson_in_section`/`regenerate_unit_in_section`，只重发该子树）/B5（retry validator 适配 Problem dict，`_coerce_problem_messages` 取 .message、过滤 warning）/B3（`structural_diff` + 删除确认弹框）/B4（`_auto_fix_resources` stub 译文回退 `[待补]` + `needs-review` tag）。新增 `Settings.ai_retry_max`（0-5，默认 1）+ `current_settings()` helper。新增 16 个后端测试）

Previous: tool-gui guiplan2 阶段 P1：AI 流式生成 + 真正可中断取消 + token/成本可见。新增 `ai_stream.py`（SSE 解析）/`ai_usage.py`（token 估算+价目表）；`request_chat` 增加 stream/on_chunk/usage_callback 参数，所有生成路径透传；`AiRequestWorker` 新增 chunk_ready/usage_ready 信号并自动注入回调；dialog 修复 B2（wish 解释阶段 worker 接线）/B6（流式取消行读取前轮询）/B7（_request_start 每轮重置、完成清 None，duration 安全 helper）；新增 usage_label 用量行；阶段文案语义化（生成中流式/校验中/解释中）。修 C1/C2

Previous: tool-gui Phase 1+2+3+4：稳定层加固 + 教师视图覆盖全部 6 种模板 + AI 改写与易用性提升 + 稳定性加固。Phase 1：backend/api.py 隔离 CLI 内部函数、CourseAdapter 原子保存/备份/回滚、CSV None 容错、全局异常处理与日志。Phase 2：SubLessonFlowWidget 模板感知视图、intro/practice/review 一键生成助手、lesson_content 统一生成函数与测试。Phase 3：教师视图接入 AI 一键生成/改写/扩展题目；新增撤销/重做、sub-lesson 拖拽排序、实时预览。Phase 4：修复 widget 生命周期隐患、listening/reading/mastery 教师视图全面走 undo stack、wizard/AI 导入资源可撤销、AI API 配置持久化、异常不再静默吞掉

## Results
- `flutter test`: **798 passed / 0 failed** - anki deep-adaptation 阶段 1-6 + P0
  (NoteStore + card-level wordId + fidelity HTML pipeline + WebView shell +
  AnkiRenderPolicy + review-session fidelity rendering + Lite mode + weak-word /
  daily-challenge glue + dark CSS + 智能去解密 pre-render cache + editable
  notetype mapping + AnkiNotetypeAI wiring + AnkiCardEnhancer dead-code removal)
  + 智能 TTS 自动语言检测 (LanguageDetector + per-course auto-read toggle +
  native-language fallback; Anki 卡片首次接入 TTS).
  The 2 historically env-sensitive tests (`anki_review_fidelity_test` calls
  `getApplicationDocumentsDirectory` via `StreamingSharedPreferences` with no
  path_provider mock; one `anki_note_dao_test` case flakes on concurrent
  `ensureSqliteLibForTestHost`) **passed in this run** but may still flake in
  other environments. P0 added 1 regression test (`mappingOverrides are
  respected`). 智能 TTS 轮新增 `language_detector_test` (29) +
  `settings_per_course_test` (7)，0 新失败。
- `flutter analyze`: 0 new warnings/errors on changed files
  (`lib/views/play/play_hub_screen.dart`, `lib/views/theme.dart`); pre-existing
  info-level lint in unrelated test files is untouched
- Python:
  - `python3 -m unittest discover -s test -p "*_cli_test.py"` — 7 passed
  - `tool/gui` suite (from repo root: `python3 -m unittest discover -s tool/gui/tests -p "test_*.py"`) — **804 passed** (workshop2：功能课向导+蓝图+总览+批量/快捷键；新增 test_lesson_presets/test_commands_bulk/test_lesson_blueprint/test_functional_lesson_wizard/test_course_overview + test_course_tree 键盘与批量用例)。全量 GUI 套件 offscreen 本机可跑（~39s）。
- `tool/course_cli.py --course-dir assets/courses/turkish validate` passes

## This round (2026-07-31, AI 导师 4 项改动)
1. **Prompt 中性化** (`lib/application/ai/ai_hint_provider.dart`): `_buildSystemPrompt` 与
   4 个深度讲解 genre 的 systemPrompt 由「a ${language} X tutor」改为通用「language-learning
   tutor; the learner is practicing ${language}」，目标语言仅作上下文而非身份，不再限于土耳其语；
   按用户选择保留「Reply in Chinese throughout / in plain Chinese」(匹配当前中文界面)。
2. **卡片化 UI 统一** (新 `lib/views/ai/components/ai_sheet_widgets.dart`): 抽出 `AiGroupCard` /
   `AiSurfaceCard` / `aiSheetInputDecoration` / `aiSheetPrimaryButtonStyle` /
   `aiSheetSecondaryButtonStyle`(提取自 `AiApiConfigSheet` 的 `_groupCard`/`_fieldDecoration`
   设计语言)。应用到 `ai_hint_sheet.dart` / `ai_depth_tutor_sheet.dart` / `ai_hint_chat_page.dart`
   (正文/加载/错误入卡片 + 双钮统一 + 输入栏 + `IconButton.filled` 发送钮)。
3. **AI key 持久化** (`ai_engine_config.dart` + `_holder.dart` + `locator.dart` + `main.dart`):
   `AiEngineConfig` 加 `toJson`/`fromJson`; `LocalStateKeys.aiEngineConfig` JSON 键;
   `AiEngineConfigHolder.loadPersisted()` (启动 postFrame 调用) + `updateConfig` 写回 (经 raw
   `StreamingSharedPreferences` 绕过 `printBefore` 避免密钥入日志; `getIt.isRegistered` 守卫使
   测试环境降级为纯内存)。`settingsAiApiConfigNotSaved` 文案与 sheet header 图标 (lock -> save) 同步。
4. **DeepSeek 默认 `deepseek-v4-flash`** (`ai_provider_preset.dart`): defaultModel
   `deepseek-v4-pro`->`deepseek-v4-flash`, supportedModels 置顶 flash; `settingsModelHint` 同步;
   `ai_engine_config_test.dart` 3 处断言更新。Python GUI (`tool/gui`) 不在范围内。

## This round (2026-08-01, 智能 TTS 自动语言检测 + Anki 卡片朗读 + 每课程自动朗读开关)
1. **LanguageDetector** (新 `lib/core/language_detector.dart`，纯逻辑): 按脚本检测返回
   BCP-47 基础码——Han->zh / Kana->ja / Hangul->ko / Cyrillic->ru / Arabic->ar /
   Thai->th / Devanagari->hi / Greek->el / Hebrew->he；含土耳其特有字符
   (ğ ı ş İ，注意 ç ö ü 不算因法德共用)->target；纯 Latin->per-course native 回退。
   `inferOptionLanguage`/`detectOption` 用 prompt 方向推断 MCQ 选项语言（解决 "merhaba"
   这类无变音符土耳其词的歧义）；`detectCardPair` 用 Anki 正反面之一的土耳其信号推断
   另一面。新 `lib/core/html_stripper.dart` (Anki HTML 卡片朗读前去标签) +
   `lib/application/smart_speech.dart` (`currentSpeechLanguages`/`detectSpeakLanguage`/
   `autoReadOnTapForActiveCourse`，getIt + 失败回退 tr/en，测试零依赖)。
2. **AudioController** (`lib/application/audio_controller.dart`): `speak`/`speakWithResult`/
   `_speakWithSystemTts`/`_ensureSystemTtsReady` 加可选 `{String? languageCode}`——
   null 用 target（保持原行为，`audio_controller_tts_engine_test` 的 `speak('Merhaba')`
   ->tr 断言不变）；非 null 用该语言，`resolveLanguageCode` 返回 null 时回退 target。
   不新增公共方法（`FakeAudioController implements AudioController` 只需加参数）。
3. **每课程设置** (`settings_provider.dart` + `locator.dart` `LocalStateKeys`):
   `autoReadOnTapFor(scope)` (默认 true) / `nativeLanguageCodeFor(scope)` (默认 'en')，
   key 编码 courseScope（'' -> 'builtin'），仿 `AnkiDeckManager._deckDoneKey` 模式。
4. **接线**: MCQ 选项 tap（`multiple_choice_renderer.dart`，受 toggle 控制按推断语言朗读）；
   Anki 翻牌（`anki_card_renderer.dart` plain + `anki_html_card_renderer.dart` HTML，
   卡片出现读正面、翻开读背面（受 toggle 控制）+ 每面手动 `record_voice_over` 朗读钮）；
   词典自由文本（`dictionary_page.dart` -> `detectSpeakLanguage`）。已知目标语调用点
   (vocab term / 听力 transcript / ShowWord / SRS term) 走 `speak` (target) 不变。
5. **UI**: `course_management_page.dart` 每课程行加齿轮 -> 底部 sheet（自动朗读 Switch +
   翻译/母语语言 Dropdown 14 项）。`app_strings.dart` +6 串。
6. 测试: `language_detector_test` (29) + `settings_per_course_test` (7)；6 个 AudioController
   fake 加 `{String? languageCode}` 参数。`flutter analyze` 0 error。全量 794/0。

## This round (2026-08-01, code-review batch 1: 5 correctness/perf fixes)
Addressed 5 of the 9 code-review findings on the Anki/FSRS working tree. Batch 1
of 2; the two import-perf fixes and the undo-race fix follow in batch 2 (with
tests).
1. **searchNotes LIKE escaping** (`lib/data/anki_note_dao.dart`): the pattern
   backslash-escaped `%`/`_` but drift 2.21's `like()` emits no `ESCAPE` clause,
   so the escaping was inert and literal-`%` searches returned nothing. Added a
   small `_LikeWithEscape extends Expression<bool>` that emits
   `col LIKE ? ESCAPE '\'` with the pattern bound as a SQL variable (no
   injection); also escapes the backslash itself. New regression test
   "searchNotes treats % and _ in the query as literals, not wildcards".
2. **hasScheduling always true** (`anki_deck_assembler.dart`): dropped the
   `|| collectionCreationTime != 0` disjunct (col.crt is non-zero for every
   real collection, so the flag was always true). Now reflects whether any card
   actually has scheduling.
3. **Media-tag video/source misrouting** (`anki_card_adapter.dart`): a
   `<source>` inside `<video>` was classified as audio when an unrelated
   `<audio>` appeared earlier in the field. Replaced the fragile
   `contains('<audio')` with a nearest-container comparison
   (`lastIndexOf('<audio')` vs `lastIndexOf('<video')`).
4. **schedulerVersion dead data** (`anki_models.dart` + `anki_importer.dart`):
   `col.ver` is the DB schema version, not the scheduler version, and the field
   had no consumers. Dropped it (`anki_models.freezed.dart` regenerated via
   build_runner).
5. **Prerendered-face fire-and-forget** (`anki_html_card_renderer.dart`):
   `upsertPrerenderedFace` was called with no await, swallowing DB errors. Made
   the `onCaptured` callback async with a try/catch + `debugPrint`. (The
   non-atomic upsert race in the DAO is deferred to batch 2.)
`flutter analyze`: 0 errors on changed files (144 pre-existing info/warning
lints untouched). Suite 794 -> 795.

## This round (2026-08-01, code-review batch 2: perf + concurrency fixes)
Addressed the remaining 4 code-review findings (the two import-perf fixes, the
undo race, and the atomic prerendered upsert). All with regression tests. No
generated code touched this round (no `@freezed`/`@JsonSerializable` changes).
1. **copyMedia out of the import transaction** (`anki_import_screen.dart`):
   `AnkiAudioResolver().copyMedia` (file I/O for every audio/image) ran inside
   `database.transaction`, holding the SQLite write lock across the whole copy
   and blocking every other DB write in the app. Moved it before the
   transaction opens (copyMedia is best-effort; a catastrophic failure throws
   before the txn opens, so rollback semantics are unchanged). New
   `ankiCopyingMedia` l10n string for the progress message.
2. **N+1 cardMetaByWordId in assembleBatchAsync** (`anki_review_assembler.dart`
   + `anki_note_dao.dart`): the deck-subtree filter looped
   `cardMetaByWordId(word.wordId)` per due candidate before `_sliceDueBatch`
   capped the batch at 20 - a 500-due-card import issued 500 sequential reads
   every time a review session opened. Added `wordIdsForDecks` (one batched
   query, chunked to stay under SQLite's variable limit) + in-memory set
   membership. Regression test `wordIdsForDecks returns word ids for cards in
   the given decks only`.
3. **undoReview vs in-flight reviewItem race** (`srs_queue_provider.dart`):
   the UI enables Undo as soon as a grade is submitted (before reviewItem
   writes); an undo fired during the fail-path `countFailsOnLocalDay` await
   was overwritten when reviewItem resumed. Added a `_gradesInFlight` set -
   `reviewItem` marks the id in-flight (try/finally), `undoReview` returns
   false while it is (the caller leaves the undo entry and retries once the
   grade completes). Body extracted to `_doReviewItem`. Regression test uses a
   `Completer`-controlled fake `ReviewHistoryDao` to assert undo is refused
   mid-grade and succeeds after.
4. **Atomic upsertPrerenderedFace** (`anki_note_dao.dart`): the read-then-write
   (`Value(front ?? existing?.frontHtml)`) let concurrent front/back captures
   clobber each other (frontHtml written as null). Switched to `Value.absent()`
   for the uncaptured face so `insertOnConflictUpdate` is a single atomic
   statement that only sets the captured face. Regression test asserts the
   other face survives in both capture orders.
`flutter analyze`: 0 errors on changed files. Suite 795 -> 798.

## Notes
- 2026-07-28 Anki smart organization + SRS SQLite (memory-curve round):
  - **SRS state prefs→SQLite (schema v6→v7 part 1)**: new `SrsStates` table
    (wordId PK, queue, dueAt, intervalDays, ease, reps, lapses, isLeech, type,
    lastReviewedAt). `SrsStateDao` (lazySingleton) load/upsert/upsertBatch/delete/
    deleteByPrefix/clearQueue. `SrsQueueProvider` rewritten to a synchronous
    in-memory cache hydrated from SQLite via `ensureLoaded()` + write-through
    persist, preserving all sync consumers (`state`, `dueCount`, `getDueWords`).
    Self-migration in `ensureLoaded()` parses the old prefs blob once, backfills
    the DB, sets `srs.migratedToSqlite.$queueId` flag, then never reads prefs again.
    `SrsWord` gained `lastReviewedAt` (powers forgetting curve without a DB join).
  - **Review history + accuracy fix (schema v7 part 2)**: new `ReviewEvents`
    table (autoincrement, cardId, queue, reviewedAt, quality, prev/next
    intervalDays, prev/nextEase, reps, lapses, type) with `@TableIndex` on
    cardId + reviewedAt. `ReviewHistoryDao` (lazySingleton) insertEvent/
    insertBatch/eventsForCard/recentEvents/allEvents/count/deleteByCardPrefix.
    `reviewItem` now writes a `ReviewEventRecord`. Lazy GetIt resolution
    (`GetIt.instance<ReviewHistoryDao>()` + `@visibleForTesting` setter) avoids
    re-churning ~25 test call sites. Fixed SRS review screen accuracy bug:
    `_grantSessionRewards` now passes real correct/incorrect counts instead of
    `correctCount: reviewedCount, incorrectCount: 0`.
  - **Memory curve model + visualization**: `MemoryCurveProvider.snapshot()`
    computes currentRetention (mean R=exp(-Δt/S) over reviewed cards), forecast
    (dueToday/7Days/30Days), maturity (new/young/mature/leech), and an empirical
    retention-by-interval curve (recall rate bucketed by prevIntervalDays into
    [1,4,7,14,21,30,60,90,180]). `learning_stats.dart` gained a `_MemoryCurveCard`
    (fl_chart LineChart + forecast mini-stats + maturity chips). MemoryCurveProvider
    is optional in the widget tree (try/catch on `context.read`).
  - **Anki smart organization**: `AnkiOrganizationResolver` extracts unit/lesson
    keys from notetype field names (unit/chapter/section/单元/章;
    lesson/topic/subunit/课/节) then tags (unit::/unit:/chapter::/chapter:/
    单元::/单元:; lesson::/lesson:/课::/课:); field takes priority, HTML stripped.
    `anki_deck_assembler.assemble(smartGrouping:)` groups cards into Units→Lessons
    by those keys (deck name fallback); multi-chunk (>20) lessons named
    `"$lessonKey #N"`. Zero-metadata path is byte-identical to the old chunking.
    Import screen shows an organization preview + smart-grouping switch.
  - **Anki revlog parse + migrate**: `AnkiRevlogEntry` model; `_parseRevlog`
    (paginated, table-missing-safe, best-effort) added to `AnkiImporter`.
    `AnkiSrsMigrator.migrate()` now takes `revlog` + optional `ReviewHistoryDao`
    and backfills `ReviewEventRecord`s (revlog ease 1→1/2→3/3→4/4→5).
  - New tests: srs_state_dao (8), review_history_dao (9),
    memory_curve_provider (5), anki_organization_resolver (10); updated
    srs_provider / grammar_review / srs_review_flow / anki_srs_migrator /
    anki_deck_assembler / sm2 / schema_migration / provider_identity / golden /
    learning_stats. Suite went 484 → 528 all pass.
- 2026-07-28 Test-suite repair (pre-existing failures, independent of the
  5-fix code-review round): widget tests that pump `MaterialApp` forgot to
  add `localizationsDelegates`/`supportedLocales` after the 07-16 i18n round,
  so every l10n widget threw `Null check operator` and rendered an error
  widget. Added delegates to `renderer_test_helper`, `course_tree_test`,
  `content_update_dialog_test`, `dark_mode_text_contrast_test`,
  `learning_stats_*_test`, `lesson_dialogs_test`, and the `play_hub` +
  `dictionary` golden tests. Other fixes: deleted obsolete `widget_test`
  (`MyApp`) and `course_database_pos_test` (`WordEntry.pos` was removed);
  added `getAnkiActivityCounts` to `FakeStudyStatsProvider`; updated
  `lesson_dialogs_test` for localized celebration titles / `CONTINUE` /
  `2m 5s`; dropped the stale `_$` freezed-impl assertion in
  `renderer_lookup_test`; fixed `schema_migration_test` (v1-v4 now create a
  pre-v6 `sections` table without `level` so the v6 `addColumn` is meaningful;
  the downgrade test uses a hypothetical v7); regenerated the 8 golden
  baselines on the OHos Flutter 3.35 fork. Suite went 418 pass / 63 fail ->
  484 all pass.
- 2026-07-20 Settings refactor — neurodiversity accessibility + hierarchy + About:
  - New `AccessibilityProvider` (`lib/application/accessibility_provider.dart`) with 6
    persisted flags: textScale (100–200%), reducedMotion, highContrast, dyslexiaFont,
    sensoryReduce, focusMode. Keys added to `LocalStateKeys`.
  - `lib/views/app.dart` rewired: single `_AppShell` watches ThemeProvider +
    AccessibilityProvider, picks light/dark/high-contrast theme variants, swaps
    text theme to Lexend when dyslexiaFont on, and injects a root `MediaQuery`
    override (textScaler + disableAnimations/accessibleNavigation when reducedMotion).
  - `lib/views/theme.dart` added `highContrastLightTheme` / `highContrastDarkTheme`
    getters (copyWith of the base themes: pure black/white surfaces, stronger borders,
    max-contrast text).
  - `AudioController` gained an `AccessibilityProvider` dependency; `_playSound` and
    `_triggerHaptic` early-return when `quietFeedback` (sensoryReduce) is on.
  - Settings hierarchy expanded 5 → 7 categories: Account / Learning (trimmed to
    language+TTS+reminder) / Audio & Haptics (sound+haptic+TTS engine) / Accessibility
    (6 tiles + theme selector) / AI Tools (API config + design chat + textbook
    import) / Data / About. New tiles in
    `lib/views/settings/widgets/settings_accessibility_section.dart`.
  - About page gained Privacy & local-first section, Version & changelog card
    (expandable, hard-coded milestones + PackageInfo), and a "View releases" link;
    credits now note the local-first fork; copyright footer uses `© <year> Turna`.
  - Focus mode gates the `MalaWelcomes` rotating image timer (splash screen).
  - Test wiring: 7 test files that subclass `AudioController` updated to pass the new
    `AccessibilityProvider` positional arg and register it in `getIt`/setUp. New
    `test/application/accessibility_provider_test.dart` (6 tests). `injection.config.dart`
    regenerated via build_runner. 445 → 451.
- `tool/gui` Phase 4 稳定性加固（方案 A）：
  - 修复 widget 生命周期：`DetailPanel.clear_content()` 与
    `TeacherTemplateWidget._clear_content()` 缓存 `widget = child.widget()`，
    避免 `setParent(None)` 后二次调用返回 `None` 导致的崩溃。
  - 撤销栈覆盖补齐：`ListeningTeacherWidget` / `ReadingTeacherWidget` /
    `MasteryTeacherWidget` 中的题目 add/delete/move/change-type/AI-rewrite 全部
    走 `AddItemCommand` / `DeleteItemCommand` / `MoveItemCommand` /
    `ReplaceItemCommand`；听力阶段 add/delete/rename/move 使用新增的
    `AddListeningPhaseCommand` / `DeleteListeningPhaseCommand` /
    `MoveListeningPhaseCommand` / `RenameListeningPhaseCommand`。
  - Wizard 与 AI 导入纳入 undo：`AppendLessonCommand` 让向导建课可撤销；
    `ImportAiSectionCommand` / `AiEditSectionCommand` / `AiEditUnitCommand` /
    `AiEditLessonCommand` 把 `merge_section_resources()` 收进 redo，undo 时
    精确回滚本次新增的词/表达/语法资源。
  - AI API 配置持久化：`MainWindow` 启动时从 `QSettings` 加载，关闭 AI 对话框
    后写回；配置对象在内存中原地更新，保证教师视图共享同一份设置。
  - 异常不再静默吞掉：`CourseAdapter.notify_resources_changed()` 和
    `DetailPanel._on_resources_changed()` 用 `logging.exception` 记录错误，
    保留容错但保留诊断信息。
- `tool/gui` Phase 3 创造性 + 易用性提升：
  - AI 改写助手接入教师视图：`SubLessonFlowWidget` 顶部「🤖 AI 改写本课」可基于
    教师指令改写整门 lesson；Listening/Reading/Mastery 模板编辑器顶部共用
    「🤖 AI 改写」；每道题目卡片右上角「🤖」支持单题改写/扩展。AI 输出保留
    id/template 并通过 `api.validate_lesson` / `lesson_content.normalize_item`
    校验，结果以 `AiEditLessonCommand` / `ReplaceItemCommand` 压入统一撤销栈。
  - 撤销/Redo 补全：新增 `Add/Delete/Rename/Move` 命令覆盖 sub-lesson、stage、
    item，以及 `ReplaceItemCommand`，教师视图所有增删改移动均走 `QUndoStack`。
  - 拖拽排序：`LinearFlowWidget` 安装 `_DragDropFilter`，支持拖拽 sub-lesson
    header 重新排序（sub-lesson → sub-lesson），通过 `_handle_drop` 计算目标
    索引并压入 `MoveSubLessonCommand`。
  - 实时预览：`SubLessonFlowWidget` 增加「👁 实时预览」开关，折叠显示当前 lesson
    所有题目的 `_PreviewCard`，内容变更时自动刷新。
- `tool/gui` Phase 2 教师视图覆盖全部 6 种 canonical 模板：intro/practice/review 不再混用
  通用 LinearFlowWidget，改由 `SubLessonFlowWidget` 显示模板标签并支持一键生成助手
  （intro：从词库生成认识课；practice：选择词汇+题型组合批量生成练习；review：从词库
  生成复习）。listening/reading/mastery 保持原有专用编辑器。生成逻辑统一迁移到
  `tool/gui/src/backend/lesson_content.py` 并新增单元测试。
- App 内 AI 课程功能已与 Python GUI 端（`tool/gui/src/backend/ai_generator.py` +
  `ai_genre.py`）对齐：完整模板/题型/资源 schema prompt、genre 标签批量、
  资源自洽校验与 autoFix、`validateSection` + 1 次自愈重试、许愿模式（独立聊天页
  `AiWishChatPage` 多轮对齐 + 滑动确认条「Swipe to finalize」生成 + 通俗解释）。
  入口已从 Learn 右下 FAB 迁到 `StatAppBar` 右上 `auto_awesome` 图标直进聊天页（后已移除，现入口为 设置 > AI 工具 / 练习 Hub），
  课程参数移到页面 AppBar 齿轮按钮的底部弹层；普通模式/编辑模式与可编辑 JSON 已移除
  （`AiCourseGeneratorPage` 删除）；API 配置移到 Settings 页 AI 区块。不含编辑模式。
- 资源持久化：AI 生成的顶层 `words` / `expressions` / `grammarPoints` 现随 section
  一并写入 `CourseDatabase` 的 `vocabulary` / `expressions` / `grammarPoints` 表
  （`insertOnConflictUpdate`，已存在 id 跳过），与 DatabaseSeeder 合并语义一致。
- 模块化重构：`lib/application/ai/` 子目录承载 `AiApiConfig` / `AiCourseSpec` /
  `ai_genre` / `ai_prompt_builder` / `ai_resource_consistency` /
  `ai_course_service` / `ai_course_provider` / `ai_wish_provider`。原
  `lib/application/ai_course_*.dart` 已删除。
- 新增 24 个核心逻辑单测：`test/application/ai/`（genre 解析、prompt 构建、资源自洽/
  autoFix、parseCompletion + retry Mock HTTP）。
- 许愿模式本轮不支持附件（图片/PDF/Word），仅纯文本多轮对齐。
- Turkish course (`assets/courses/turkish/`) now ships **8 sections** with the
  CEFR progression A1/A1/A1/A2/B1/B1/B2/B2, wired with inter-section
  prerequisites. Section 1 ships a real **intro greetings lesson** (`s1-l2`,
  template `intro`, 3 subLessons: meet words / choose / practice) backed by
  8 vocab words + 2 expressions. Sections 2–8 are metadata-only placeholders
  (1 unit / 1 legacy MCQ lesson each, no vocab refs); full content authoring
  is a future round.
- Grammar points intentionally empty (`grammar_points.json`); this keeps a
  legitimately-empty table for the seeder-idempotent "empty table ≠ reseed"
  regression path.
- `seeder_idempotent_test.dart` asserts vocab + expressions are non-empty
  (real content) while grammar is empty; `course_cli_test.py` asserts the
  vocab CSV has a header + data rows (e.g. `w-merhaba`).
- Piper Swahili TTS + `sherpa_onnx` removed; TTS is system/Google `'tr'` only.

## Previous baselines
- 错题复习 + 二按钮复习 + SM-2 调优 = 411 (all pass); AI align with GUI = 409 (404 non-golden pass; 8 golden env-diff); MiniMax migration = 385; Pre-pivot = 373; Phase 24 = 372; Phase 23 = 358; Phase 22 = 350; Phase 21 = 342.