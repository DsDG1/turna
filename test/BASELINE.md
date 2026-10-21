# 测试基线收据

> 本文件只保留最近批次的测试基线。更早的批次在 git 历史里（`git log -- test/BASELINE.md`）。
> 引用收据用「文件 + 条目日期 + 标题」三段锚，禁止行号。

## 最近批次

---

### 2026-10-21 app 内文案去 Anki 化：统一写「记忆卡」

- **性质**：文案批次（无行为改动）；**测试数 +6**（新增 `test/architecture/app_wording_terminology_guard_test.dart` 6 条）。
- **改动**：①app 内面向用户的文案不再出现 anki / Anki，统一写「记忆卡」——`lib/l10n/app_strings.dart` 74 处字符串（**只改字面量**，getter 名与标识符不动）、`assets/changelog.md` 14 处（应用内更新日志）、`lib/application/settings/release_manifest.dart` 17 处（更新日志后援）、`lib/application/system_health_monitor.dart` 与 `lib/views/settings/system_health_page.dart`（诊断模块名「记忆卡渲染」**两处必须同步**：页面按模块名匹配建议分支，只改一边会让建议弹窗静默失效）、`lib/application/ai/ai_card_context_resolver.dart`（来源显示名）、`lib/application/settings/commands/reset_learning_settings_command.dart`、`lib/domain/audio/anki_media_platform_stub.dart`（平台不支持时的报错文案）、`assets/anki_reviewer/`（复习器页 `<title>` 与 iframe 无障碍标签）。②`assets/anki_reviewer/manifest.json` 的 sha256 / bytes 随资产同步更新，`assetVersion` p2e-2 → p2e-3。③`AGENTS.md` §7.2 新增术语口径（app 内写「记忆卡」；三类例外：第三方 AGPL 许可文本 / 内部契约（协议键、原生库名、本地源、表名、id 前缀、level 标记）/ 文档层），§8 强制手段表登记新门禁。④新增 `test/architecture/app_wording_terminology_guard_test.dart`（6 条）：字符串表严格扫描 + 全 `lib/` 中文文案扫描 + 应用内更新日志与复习器资产扫描，另加两条**反向锚点**（AGPL 文本必须仍点名 Anki、协议键必须仍在字符串表），防止「去品牌」被做成「去许可」。⑤两处测试断言跟随文案更新（`play_hub_screen_test` 11 处、`storage_diagnostics_page_test` 1 处）。文档层（`docs/`、ADR、根 `CHANGELOG.md`）按约定不改。
- **验证**：`flutter test --tags golden` **12 passed**（`play_hub` golden 不渲染该文案，无需重生）；`flutter test --exclude-tags golden` **2291 passed / 0 failed**（较上一批 2285 +6，即新增门禁本身）；新门禁 `app_wording_terminology_guard_test` **6 passed**；`flutter analyze --no-pub` **No issues found**。
- **未验**：未出包、未在真机/模拟器上肉眼过一遍新措辞（「记忆卡组」这类连写是否符合预期观感，未经用户确认）。

---

### 2026-10-21 AI 课程助手移出课时 + 统一 section JSON + 后台生成 + 我的练习库

- **性质**：功能改造批次；**测试数 +16**（删除 `ai_lesson_helper_undo_test` 2 条、`ai_lesson_undo_store_test` 2 条、`srs_tutor_provider_test` 7 条、`ai_prompt_catalog_test` 2 条已退役 prompt、`ai_tutor_chat_session_test` 1 条弃用断言；新增 `ai_practice_pipeline_test` 12 条、`ai_practice_quality_test` 11 条、`ai_practice_repository_test` 6 条、`schema_33_ai_course_library_test` 1 条）。
- **改动**：①课时 AppBar 删掉「AI 课程助手」入口与 `AiLessonHelper*` / `AiLessonUndoStore` / 撤销横幅，连带删掉「降低/提高难度、加 3 题、改听力、优化提示词」5 个单课 chip；单题 AI 提示与深度讲解保留。②新增 `lib/application/ai/practice/`：`AiPracticePrompts`（移植 GUI 的模板/资源/ID/CEFR/干扰项/大纲/分课提示词语义）、`AiPracticePipeline`（大纲校验、shell、splice、逐课/整节校验，文本题型白名单）、`AiPracticeGenerator`（大纲→逐课→校验，失败带错误重问一次）、`AiPracticeJobQueue`（app 级 `@lazySingleton`，`queued/running/ready/failed`，关闭面板不取消）、`AiPracticeSourceContextBuilder`（错题/弱词/难懂点证据块）。③`course.db` **v33** 新增 `ai_courses` + `ai_course_versions` 两张表（合集 / 每次生成一版）配 `AiPracticeRepository`；v32 的 `ai_practice_sets` 平表在迁移里 1:1 拆成「1 合集 + 1 版本」后删除（平表把任务生命周期和收藏内容挤在同一行，重新生成会覆盖旧内容、失败一次连能用的版本一起藏起来）。生成物不写 `sections/units/lessons`（seeder 内容版本变化会清空课程表，且会污染学习页课程树）。内容核验由 `AiPracticeQualityChecker` 两级把关：阻断级（越界正确答案、重复选项、空阶段、生词零覆盖、占位文本、阅读无段落等）先修两次再判失败，提示级只写进核验报告。④AI Hub 新增「我的练习」区与生成 sheet（按错题/弱词/难懂点、自定义课程：主题/等级/单元/课数/课型/编排意图/词表接地）；新增库页（多选删除、存放=置顶保留、7 天过期）、开练页（从 section JSON 走 `LessonViewModel.loadLessonInstance`，不记课程完成度/成就）、详情页（目录树 / 核验报告 / 生成历史）；练习页「智能练习」角标显示生成中/待练习。⑤删除 `TutorLaunchSheet`、`SrsTutorProvider`、`AiWishProvider`、`AiWishChatPage` 与 `AiWishChatRoute`；教材导入 tombstone 保留。⑥新增 ADR 0054，同步 `docs/project-guide.md` §7 与 `docs/README.md` ADR 索引。
- **验证**：`flutter analyze --no-pub` **No issues found**；练习库四份测试 **30 passed**（`ai_practice_pipeline_test` 12 / `ai_practice_quality_test` 11 / `ai_practice_repository_test` 6 / `schema_33_ai_course_library_test` 1）；`test/application/ai` + `test/data` + `test/views/ai` + `test/views/settings` + `test/routing` + `provider_identity_test` + `course_scope_codec_migration_test` **466 passed**；`test/architecture/` **27 passed**（含 `layering_guard_test`、`docs_hygiene_test`）。真实端点冒烟（MiniMax `api.minimax.cn/v1` / `MiniMax-M3.1-Flash`，仅 2 次调用）：大纲返回合法 JSON（1 unit / 1 lesson / 2 words），逐课返回合法 lesson JSON（6 道 `multipleChoice`，无音频题型）。`flutter build apk --debug --no-pub`（OHOS fork SDK）**built app-debug.apk**。**收尾全量复跑**：`flutter test --exclude-tags golden` **2285 passed / 0 failed**（3m0s）；`flutter test --tags golden` **12 passed**（修掉两条长期红着的门禁后，见下一条）；`python -m unittest discover -s test -p "*_test.py"` **Ran 60 tests / OK**；`tool/gui run_gui_tests.py full -j 4` **ran=204 passed=204 failed=0**；`check_ai_boundaries` / `gen_module_tree --check` / `check_docs_index` 三条门禁全绿。
- **未验**：APK 未安装到真机/模拟器；未在界面上点过「生成 → 切页 → 回到我的练习 → 开练 → 调整/删除/存放」完整流程。

---

### 2026-10-21 门禁修复：OHOS vendored 白名单 + 课程树 golden 基线

- **性质**：测试/门禁批次；无产品代码改动。
- **改动**：①ADR 0055 §1 引入的 vendored `flutter_secure_storage` 覆盖没进 `ohos_eol_architecture_guard_test` 的白名单，全量一直有一条红。白名单拆成两张表：「允许出现的 vendored 覆盖」与「TargetPlatform 移植子集（带通配 arm 下限）」，另加 `_secureStoragePatchSite` 钉住唯一的补丁行——重 vendor 丢掉该行会编译通过、全部测试通过，只在真机重启后表现为 API key 消失。ADR 0047 §7.3 补上这一行的筛选依据，§7.5 的 override 计数订正为 5 个 git + 3 个 vendored。②`course_tree_expanded_light` 自 2026-09-22 起就是红的（此前 BASELINE 一直记作「既有失败」，没查因）：课程树新增 `_ensureNextUpExpanded` 后单元进页即自动展开，测试再点一下标题反而把它**收起**，抓到的正是收起态。测试改为断言展开态、不再盲点；`course_tree_expanded_dark.png` 原本就是收起态，一并按展开态重生（light 字节未变，说明它本来就是对的）。
- **验证**：`ohos_eol_architecture_guard_test` **14 passed**，并做变异验证（把补丁行改成 `false` 即成红）；`flutter test --tags golden` **12 passed**；`flutter test --exclude-tags golden` **2285 passed / 0 failed**。
- **未验**：无（两处都只碰测试与文档）。


---

### 2026-10-20 文案中立化 + 系统提示词面板开放全部 AI 功能（含一键恢复默认）

- **性质**：文案 + 能力扩大批次；**测试数 +7**（`ai_prompt_catalog_test` +5、`srs_tutor_provider_test` +1、`ai_prompt_sheet_test` +1）。
- **文案中立化**：用户可见文案里的「土耳其语」清零，只剩三处真实指代（`ttsNativeLanguageLabel` 的语言名映射、关于页的转向史实、Anki 示例牌组）。具体：复习进度来源 `课程 · 土耳其语` → `课程`；词典搜索提示、每日挑战副标题、导出课程副标题、内容更新提示去掉语言名；TTS 三处改成按当前语言取名——`settingsTtsGoogleInstalledMissingVoice` / `splashGoogleTtsMissingBody` / `splashGoogleTtsNotReadyBody` 由 getter 改为带参方法。
- **提示词面板开放**：`AiPromptFeature` 由 5 个扩到 9 个，新增 `tutorPlan`（定制复习）、`courseGeneration`（课程生成 / 愿望建课）、`lessonTransform`（AI 改课）、`courseExplainer`（课程说明）；后三者原本内联在各 provider 里的 system 文案搬进 `AiPromptCatalog`，JSON schema 契约仍留在用户消息里（面板 `usage` 与页脚都写明这一点）。
- **一键默认**：面板新增「全部恢复默认」（存在自定义时才出现，二次确认），调用既有的 `AiPromptOverridesStore.clearAll()`。
- **顺带统一**：5 处 `AiPromptOverridesStore.resolve().textFor(...)` 收敛为 `AiPromptOverridesStore.overrideFor(...)`。
- **验证**：`flutter analyze`（`lib/application/ai`、`lib/views/ai`、`lib/l10n`、`lib/views/splash`、`lib/views/settings` 等）No issues found；`test/application/ai` + `srs_tutor_provider_test` + `test/views/ai` + `test/views/splash` + `test/views/settings` + `test/architecture` **306 passed / 0 failed**。新增断言覆盖「每个功能都有非空默认文本且追加生效」「定制复习的 system 消息真的带上用户追加」「一键恢复清空全部且不残留空提示词」。
- **未验**：真机看 9 个芯片的面板排版；未构建安装包。

---

### 2026-10-20 AI 讲解在 Anki 语境下不再冒充「土耳其语」

- **性质**：行为修正批次；**测试数 +2**（`ai_prompt_catalog_test`）。
- **症状**：从复习页打开 Anki 卡片的「卡片讲解」时，系统提示词固定写 `You are a language-learning companion for Turkish.` —— 导入日语 / 英语牌组后，AI 仍按课程语言讲解；AI Hub 的介绍文案也有「问任何土耳其语相关问题」「解释一段土耳其语句子」这类硬编码。
- **改动**：①`unified_review_page` 的讲解语言改按来源判定（课程卡片 → 当前课程语言显示名；`LegacyAnkiSource` / `OfficialAnkiSource` → `null`）；②`AiPromptCatalog.cardExplain` 接收可空语言，未知时改为「从卡片文本自行判断，不要默认课程语言」；③`AiCardExplainProvider` 删掉 `'the target language'` 兜底，null 原样透传；④AI 介绍 / 示例文案去土耳其语硬编码（自由问答作用与适用场景、追问示例、课程生成示例、自定义提示词占位符）。
- **验证**：`flutter analyze`（`lib/application/ai`、`lib/views/review`、`lib/l10n`）No issues found；`test/application/ai` + 复习页守卫 **210 passed / 0 failed**；`test/views/review` + `test/architecture` **57 passed / 0 failed**。
- **未验**：真机点「Anki 卡片 → 卡片讲解」未跑；未构建安装包。

---

### 2026-10-20 AI 定制复习 / 学习诊断全挂：JSON 模型留空时把 `model: ""` 发上线

- **性质**：缺陷修复批次；**测试数 +10**（`ai_engine_config_test` +5、`ai_engine_test` +1、新增 `ai_error_mapper_test` 4 条）。
- **症状**：`custom` 预设下 AI 对话可用，而「定制复习（弱词 / 错题）」「学习诊断」「生成课程」等一切走 JSON 的调用全部失败，界面显示 `AI planning failed: ... HTTP 400 ... unknown model`。
- **根因**：`AiEngineConfig.selectModel` 移植 `config.py:select_model` 时，把「留空回落到 `self.model`」写成了「回落到 `preset.defaultModel`」。deepseek / mimo 预设的默认模型非空，缺陷被掩盖；`custom` 预设的默认模型是空串，于是 JSON 请求带着 `model: ""` 上线。`isComplete` 又只校验会话模型，配置页因此照常显示「已配置」，界面看不出异常。
- **改动**：①`selectModel` 收敛成单一回退链——JSON 侧留空继承会话模型（新增 `effectiveChatModel` / `effectiveJsonModel`，未知 kind 同样回落到会话模型），`isComplete` 改用 `effectiveChatModel`；②`fromJson` 把空串模型归一成 `null`（旧设置页把空输入框原样存成 `''`，迁移到 `custom` 后既拿不到 retired 默认值、也不像「没填」）；③配置页 JSON 模型字段补提示「留空则与聊天模型相同」，并补该字段的预设快选芯片；④`AiErrorMapper` 新增 `modelUnavailable`（`unknown model` / `model_not_found` 一族，`canRetry: false`、`canConfigure: true`）；⑤`SrsTutorProvider` 规划失败改走 `AiErrorMapper`，供应商原始 body 只进 `logger.w`，不再直出到界面。
- **验证**：`flutter analyze`（改动面 `lib/application/ai`、`lib/views/ai`、`lib/l10n` 等）No issues found；5 个测试文件 **47 passed / 0 failed**（`ai_engine_config_test` 19、`ai_engine_test` 5、`ai_error_mapper_test` 4、`ai_http_client_test`、`srs_tutor_provider_test`）；对真实端点（MiniMax `api.minimax.cn/v1`）实测复现：`model: ""` → `400 invalid params, unknown model '' (2013)`，同名模型正确值 → `200`，`response_format: json_object` 亦被接受。
- **未验**：全量 `flutter test --exclude-tags golden` 未跑；app 内端到端（配置页改模型 → 点「定制复习」）未在真机或模拟器点过。

---

### 2026-10-20 文档体裁分离与全量瘦身（删施工日志 / 建状态唯一源 / 加文档门禁）

- **性质**：纯文档批次，零运行时行为改动；**测试数 +11**（新增 `test/architecture/docs_hygiene_test.dart` 11 条断言）。
- **改动**：①**删除** 14 个一次性文档——`docs/official-anki-migration/` 整目录（4 份计划 + 收据 + archive）、`docs/ankiUpdate/`（2）、`docs/reviews/`（1）、ADR 0030 / 0036 / 0041 / 0046、`test/archive/BASELINE-pre-2026-09-20.md`、`native/turna_anki_core/contract/archive/README.md`、`tool/gui/docs/archive/`（4）、`tool/gui/docs/ai_configuration_and_features_report.md`；施工日志与真机收据原文一律转入 git 历史。②**新建 `docs/status.md`** 作为状态唯一源（迁移口径 / 平台档位 / 证据台账 / Held 项 / 鸿蒙三层口径），`AGENTS.md` §0 的状态口径由旧收据改指它。③`AGENTS.md` 27.6 → 19.9 KB：删 §7.1 状态快照（3481 字符单行）与真机收据、§9.1/§9.2 排错流水改为指向 `docs/ohos-build-setup.md`，**规范正文日期戳归零**。④`docs/project-guide.md` 68.6 → 24.2 KB（删「现状速览 / 目录 / 实现清单 / 下一轮计划」，保留教学法 / 架构 / 格式契约 / 「不做的事」）。⑤ADR 撞号修复：0021 与 0043 各有两篇历史复用 → 改为 0052 / 0053（接在 0051 之后），标题编号同步；ADR 目录 241.9 → 160 KB，**编号决策项零非预期丢失**（首轮压缩误删决策表格，已按 HEAD 原文逐篇重建）。⑥**清理失效文档指针 243 行 / 83 个文件**：`doc 34` / `plan 34`（77 行）、`step3.md` / `step4.md` / `step6.md`（28）、`doc 41`（24）、`official-anki-migration` / `cutover-receipt` / `ankiUpdate`（67）、`ADR 0041`（31）、`ADR 0046`（11）、`v2-first-device-findings.md`（5），全部改指现存 ADR 0043 / 0044 / 0050 或 `docs/status.md`。⑦`tool/gui` 文档树 321.9 → 184.3 KB（`tests/BASELINE.md` 142.3 → 24.4 KB；`ai_refactor_contract.md` §1–§18 编号与 §14 逐字保留）。⑧**取消跟踪**两个 HiLog 设备抓取（`ohos_launch_fixed.log` 17.8 MB + `ohos_launch_repro.log` 27.9 MB，零引用），并补 `.gitignore` 规则覆盖 `ohos_launch_*.log` 与 `build_ohos_*.log`（文件保留在磁盘）。⑨**门禁加到 10 条断言**：新增「ADR 编号提及必须真实存在」与「正文里反引号包着的 `.md` 文件名必须真实存在」；后者按**路径**判定（相对所在文件或相对仓库根），不按裸文件名兜底——兜底会让「同名但在别处」的死指针蒙混过关。连带修掉 3 处只能靠同名兜底的指针：ADR 0020 / 0031 指向 2026-09-29 已删的根 `CLAUDE.md`（标注「已删」），ADR 0053 的 `course-layout.md` / `course-pack-format.md` 改为 `docs/authoring/` 全路径。⑩**GUI 侧门禁加第二条不变式**：`tool/gui/tool/check_docs_index.py` 除「索引无孤儿」外，同时校验**文档指针存活**——GUI 树里反引号包着的 `.md` 名与 Markdown 链接都必须解析到真实文件（基准：提及所在文件 / GUI 工程根 / 仓库根）。连带修掉 3 处只靠同名兜底的指针：`tool/gui/docs/ai_refactor_contract.md` 的 `docs/archive/experienceai.md` 补「已移至」现路径，`CHANGELOG.md` 的 `CLAUDE.md` 与 `dreamplan.md` / `future2.md` / `future3.md` / `future4.md` 标注「已删」。⑪**复查发现压缩把正文截断了**：首轮压缩把 13 篇 ADR 由英文改写成中文时在句中断句，造成内容丢失。逐条与 HEAD 原文比对后修复——ADR 0001（状态 / 决策 / 理由三处截断 + 丢「被否决的选项」整段）、0002（落地形态缺「重置动作 / 持久化 / 一次性 reseed」3 条 + 头部 `Related` 截断）、0007（决策 5「不迁移 Freezed」+ 理由第 4 条 + 丢 `MatchProvider` 封装 / `AppRouter` 路由守卫两条决策 + 后果整节）、0010（决策 4/5 + 理由一段 + 后果一条）、0011（决策 3 截断 + 决策 4 + 「影响与边界」整节为空）、0015（表缺 2 行 + 4 条 bullet + 丢「迁移路径」整节）、0020（头部丢 `Supersedes` + 决策 3/4 + 后果一条）、0021（决策 3/4/5 + 理由截断 + 后果缺 4 条）、0026（决策 3/4 + 理由截断 + 后果缺 2 条）、0031（丢「不在范围」清单）、0032（丢「不动 `CLAUDE.md`」）、0033（丢「与契约同步」）、0034（决策 3–6 + 理由一段）、0037（丢「取代」行 + 三次修订的日期）、0038（决策第二段 + 「影响与边界」整节为空）、0039（`SecureCredentialStore` 那条 bullet 截断在 `secure_credential_s` + 页面行为丢 2 条 + 背景少一句）、0042（决策 4/5/6 + 头部丢关联）、0043（丢过程档指针 + 评审日期）、0044（丢过程档指针）、0045（决策 4/5 + 头部 `关联` 截断）、0047（丢「被否决的候选」3 条 + autofill 符号处置表 + SDK 档位证据表 + 方案正文指针）、0050（丢 §2.5 资产来源表 + 2 处代码段被折断）、0053（决策 3/4/5 + 理由与后果各截断）。为防复发，固化 3 个机械判据：①**全文反引号奇偶**（奇数 = 句中断在代码段里）——该判据已落成门禁：`docs_hygiene_test.dart` 第 11 条断言与 `check_docs_index.py` 的第三项检查，两侧均做过变异测试（注入未闭合反引号 → exit 1 并报出文件名 → 还原后字节级一致）；②**段落技术标识符覆盖**（HEAD 每段的技术 token 必须能在现文找到，跨语言成立）；③**编号决策项 / 表格行计数**（现文不得少于 HEAD）。接收侧同批补回 2 处死指针：ADR 0020 与 0031 指向 2026-09-29 已删的根 `CLAUDE.md`（标注「已删」）。
- **体量（口径：仓库自有 .md，排除 `.agents/` `.cursor/` `third_party/` 与 `native/turna_anki_core/anki/` 子模块内容）**：`docs/` 子树 66 篇 / 806.7 KB → 52 篇 / 339.7 KB；全口径 105 篇 / 1,741.5 KB → 84 篇 / 666.2 KB（**−1,075.2 KB，剩 38%**；含⑪回补的截断内容）。
- **验证**：`flutter analyze lib test` No issues found ✓；`flutter test test/architecture/docs_hygiene_test.dart` **11/11 通过** ✓；`ohos_eol_architecture_guard_test.dart` 等 6 个被触及的测试文件 **39 passed / 0 failed** ✓；`python tool/gui/tool/check_docs_index.py` **0 orphans** ✓；全仓 markdown 相对链接扫描 **0 断链** ✓；失效文档指针扫描 **0 残留**（余下命中均为标注「（已删）」的纯文本历史引用，非链接）✓；文档门禁**变异测试**通过——插入一个不存在的 `.md` 指针后门禁 exit 1 并精确报出所在文件与行号，改回后文件字节级一致；GUI 门禁 `check_docs_index.py` **7 documents, 0 orphans, 0 unresolved pointers, 0 unbalanced code spans** ✓（同样做过变异测试：注入假指针 → exit 1 + 精确行号 → 还原后复绿）；全树 85 篇项目 markdown（含 `tool/gui/` 与 `native/turna_anki_core/`）正文指针终检 **0 未解析** ✓；⑪复查后重跑三个机械判据：全仓 84 篇 markdown **反引号奇偶 0 处失衡** ✓；截断检测（段落末行无终结符 + 表格单元格数配对）**0 真命中**（余 6 处为手工硬换行、4 处为转义竖线误报）✓；内容保全验收（编号决策项 / 表格行 / 段落技术标识符覆盖）**ADR 决策项零缺失** ✓
- **未验**：全量 `flutter test --exclude-tags golden` 未跑（本批不改运行时行为，仅新增一个测试文件，已单独跑通）；`make ci` 未跑；鸿蒙 fork SDK 未构建。
- **不在本批范围**：`ohos/build-profile.json5`（release 签名材料 → debug）与 `ohos/hvigor/hvigor-config.json5`（新增 `execution` 块）的工作区改动**未纳入本批**，二者 mtime 与同期的 `ohos_launch_*.log` 抓取一致，判断为并行的真机调试会话所致，已保持原样留在工作区未暂存，由负责人判定是否保留。

---

### 2026-10-20 鸿蒙签名配置修复 + release 包产出 + 全量门禁首跑（`make ci` 等价复刻）

- **性质**：修复 + 发布准备批次，测试数未变（无新增 / 删除用例）。
- **改动**：①根因是密钥库与证书**不同代**（`storeFile` 指 debug 密钥库、`certpath` 指 release 分发证书，报 `ERROR: 11111002`），`ohos/build-profile.json5` 的 `certpath` / `profile` 改指同代 debug 材料，密钥库、别名与加密密码原样不动；②`ohos/build-profile.json5.release` 由明文口令改为 DevEco 同构加密 blob（PBKDF2 + AES-128-GCM），`.gitignore` 注释订正为「存加密 blob、机器本地、不可入库」，并顺手删掉 `ohos/` 下 16 个 `.tmp_*` 排查残留；③`build-profile.json5` 补注释规则（同代要求、11111002 与误导性 keyAlias 提示、别名小写化、只有 debug p7b 带 `device-ids`）；④`Makefile` 的 `build-release-smoke` 加 `--allow-version-mismatch`（`build-release` 保持严格断言）。
- **验证**：`format-check` 953 files / 0 changed ✓；`analyze` No issues found ✓；`test`（含 golden）**2246 passed / 1 failed**（唯一失败为既有项 `golden/goldens/course_tree_expanded_light.png`）；`test-python` **Ran 60 tests / OK** ✓；`lint-gui` ✓；`guard-gui` ✓；`test-gui` **ran=204 passed=204 failed=0** ✓；`build-release-smoke` APK 阶段通过、AAB 阶段失败（Android 侧既有项，非本批引入）。
- **未验**：真机安装与 AppGallery 上传；本批 release 包未在真机或商店侧验证。

---

### 2026-10-20 发布 0.9.1：应用内 changelog 同步 + 签名材料防入库 + 全量工作区核验

- **性质**：发布准备批次，版本 `0.9.0+5` → `0.9.1+6`。
- **改动**：①版本号同步三处（`pubspec.yaml`、`ohos/AppScope/app.json5` 的 `versionCode: 6` / `versionName: "0.9.1"`、`ohos/local.properties`），`app.json5` 注释订正为「No test asserts this sync today」（既有守卫只断言文件存在）；②应用内 changelog 三处同步（`assets/changelog.md`、`release_manifest.dart` 的 `fallbackReleases` / `journeySteps`、`changelog_page.dart` 阶段数改由 `journeySteps` 派生）；③签名材料防入库：`.gitignore` 加 `ohos/build-profile.json5.release` / `.unsigned` / `tool/_tmp_*` 三条规则；④golden 归属判定与测试加固：回干净 HEAD 对照后确认 `settings_reminder_light/dark` 失效属本批并已重生，`changelog_page_test.dart` 加 2 条守卫、3 处脆弱断言改为 `scrollUntilVisible`。
- **验证**：`flutter analyze` No issues found；全量 `flutter test --exclude-tags golden` **2235 passed / 0 failed**（较上批 +2）；`python -m unittest discover -s test -p "*_test.py"` **Ran 60 tests / OK**；`test/golden/` **11 passed / 1 failed**（唯一失败即既有项 `course_tree_expanded_light`）；`dart format lib test` 全库合规。
- **未验**：真机；鸿蒙 fork SDK 未构建；`make ci` 的 `test-gui` / `build-release-smoke` 未跑。

---

### 2026-10-20 设置页开关 ON 态白色 thumb 被吞，一行颜色改回 + 像素级回归测试

- **性质**：视觉缺陷修复批次，1 行代码改动 + 1 个新测试文件。
- **改动**：①`settings_section.dart` 的 `settingsAdaptiveSwitch` 在 `WidgetState.selected` 态把 `thumbColor` 由 `TurnaTheme.brandTeal`（与 `activeTrackColor` 同色，thumb 与 track 融成一体）改 `TurnaTheme.textOnPrimary`（白），OFF 态仍走平台默认，两态区分度保留；该写法自 `980224e6` 引入即如此，非本次回归；②一处改动覆盖设置页全部 5 个开关入口，裸 `Switch` 两处本就正确未动；③新增 `test/views/settings/settings_switch_thumb_test.dart` 3 条像素级断言（渲进 `RepaintBoundary` → `toImage` → 统计白色 / teal 像素），已验证回退修复即精确失败。
- **验证**：`flutter analyze` No issues found；全量 `flutter test --exclude-tags golden` **2233 passed / 0 failed**；`flutter test test/views/settings/` **50 passed / 0 failed**；新测试 3 passed；`dart format --set-exit-if-changed` 干净。
- **未验**：真机观感；`test/golden/` 未跑（本批无 golden 图变更）。

---

### 2026-10-20 AI 面收敛与「智能练习」入队：去蓝紫 / 去 emoji / 服务商精简与接口责任标注 / 系统提示词可见可追加 / 练习页「AI 助手」横幅移除

- **性质**：产品面收敛批次，AI 从「并行专区」收回为「练习的一个来源」。
- **改动**：①配色与文案：AI 面 11 处 `amethystLeague` 移出（Hero 渐变改 `brandTealDark→brandTealLight`，图标与强调改 `brandTeal`；`amethystLeague` 常量保留，词典 / 练习信息面板 / 成就目录仍在用），全库用户可见 emoji 清零，并修两处假文案（AI 必然出网，隐私表述改为「配置只存本机，请求直达服务商」）；②服务商收敛（破坏性）：`AiProvider` 由 `deepseek / kimi / qwen / mimo / custom` 收敛为 `deepseek / mimo / custom`，`AiEngineConfig` 加 `schemaVersion: 2`，用 `kRetiredPresets`（`kimi` / `qwen` → `custom` + 原 Base URL + 原模型）与 `kRetiredModelAliases` 迁移，避免静默坏配置；③新增 `ai_prompt_catalog.dart`（5 功能默认 prompt 单一来源）、`ai_prompt_overrides.dart`（单键、追加式、4000 字上限）与 `ai_prompt_sheet.dart`（只追加不替换，默认文本含安全边界），配置页另加常驻 `_EndpointScopeNotice` 标注接口与责任；④练习页横幅移除，复习队列 2×2 增第四格「智能练习」（引擎未配置挂橙色「未配置」徽标），AI Hub 与功能手册标题同步改名。
- **验证**：`flutter analyze lib test` No issues found；全量 `flutter test --exclude-tags golden` **2225 passed / 0 failed**；`test/golden/play_hub_golden_test.dart` 2 passed（`play_hub_light/dark` 已重生）。
- **未验**：真机；鸿蒙侧 `flutter_secure_storage` 无该平台实现，AI 密钥只能 `sessionOnly`（重启需重填），未接平台侧 fork 覆盖。

---

### 2026-10-20 永久删除「开发者实验室」（Fun Lab）及其底层子系统

- **性质**：产品面清理批次，功能整体删除（不是隐藏）。
- **改动**：①删除设置分类 `SettingsDestination.developer`、设置首页 debug 入口块、`DeveloperSettingsPage`（含 `@RoutePage`）、`SettingsFunSection`、`FunProvider`、`FunLabSnapshotService`，`make gen`（fork SDK）重生成路由与 DI 并确认无残留；②连带清理成就页横幅与 `funPreview` 分支、`LocalStateKeys` 两个 Fun 键（备份清单同步移除）、`ISrsStateStore.countPostponable` / `postponeActiveBy` 及 DAO 实现、66 条文案与文档指路；③`CourseDatabase.kSchemaVersion` 30→31，v31 为纯 `DROP TABLE IF EXISTS`（4 张 Fun 表），onCreate 与 v15 / v20 / v25 迁移同步；④删 `fun_lab_snapshot_service_test.dart`（7 条）与 `achievement_badge_card_test.dart`（1 条），schema 迁移用例改 v30→v31 删表用例。
- **验证**：fork SDK `build_runner` exit 0；`flutter analyze` No issues found；全量 `flutter test --exclude-tags golden` **2192 passed / 0 failed**（本批净减 8 条）。
- **未验**：golden 未跑；真机未跑。

---

### 2026-10-19 暗色背景去绿 + 四个主 tab 顶栏统一

- **性质**：视觉一致性批次，两件互相独立但同一诉求的改动。
- **改动**：①夜间背景由墨绿改为中性黑阶（scaffold `#000000`、AppBar `#0F0F0F`、card `#141414`、elevated `#1E1E1E`、分割线 `#2A2A2A`、input / chip `#121212`），退役色值 `#0F2119` / `#152B21` / `#12261C` / `#1B3529` / `#2C453A` 在 `lib` / `android` / `ohos` / `tool/gui` 全仓零残留，并同步 Android `colors.xml`、鸿蒙 `AnkiReviewerChrome.ets` 的 `nightPalette()` 与 `tool/gui` 的 `_DARK_PALETTE`；②抽 `TurnaTheme.tabAppBarHeight = 60.0` 单一 token，三页 `preferredSize` 与设置页 `toolbarHeight` 统一读它，设置页标题由 `headlineSmall` 降为 `titleLarge` / w700 并删掉自绘底色覆盖；③新增 `test/views/tab_app_bar_contract_test.dart` 4 条，重生 6 张暗色 golden。
- **验证**：`flutter analyze` No issues found；全量 `flutter test --exclude-tags golden` **2197 passed / 0 failed**；`test/views/` 382 passed；`test/architecture/` 13 passed；`test/golden/` **11 passed / 1 failed**（唯一失败即既有项 `course_tree_expanded_light`）。
- **未验**：真机 / 模拟器上的顶栏观感与 golden 未覆盖的页面；`tool/gui` 的 Qt 测试在本机跑不了（venv 在 Linux 内建）。

---

### 2026-10-19 课程树单元名、官方视图读失败、课内 Anki 不写错题本、鸿蒙预热 API 删除与二档文案

- **性质**：把集中在 Official Anki 的几处行为一起收口。
- **改动**：①`kSchemaVersion` 29→30，`anki_course_tree_view` 增 `unit_key`（v29 升级用 `ADD COLUMN … DEFAULT ''`，旧行仍可读），展示用非空 `unitKey`、空则退回 `lessonKey`，已安装的三级牌组需下次冷启动重建才换成真实单元名；②视图缺表仍返回空并记 info，其它 SQL 错误记 warning 后抛出，`CourseProvider.officialTreeLoadError` 与 `bootFailed` 分开，课程树顶部固定文案「官方课程暂时读不出来，内置课程不受影响。」；③anki-owned 课内提交统一走 `_applyAnkiCourseSubmit`，提交失败不再写错题本或 Turna FSRS；④鸿蒙侧 `advanceAndPresentAfterNativeRating` / `presentSessionCardInPlace` 挪到 `official_review_advance.dart`，删除 `warmUp`、`OfficialAnkiOhosReviewerWarmUp` 与 idle deadline，底栏 `ratingLabel` 只映射 again→忘记 / good→记住，Release 下 `requireImporter(useFake: true)` 直接抛 `capabilityMissing`。
- **验证**：`flutter analyze`（改动文件）No issues found；全量 `flutter test --exclude-tags golden` **2193 passed / 0 failed**；删 9 条只覆盖 warmUp 的用例，新增 6 条（schema v30 / 单元名 / 缺表 / 坏列 / 坏视图保留内置课 / 提交失败不写错题本）。
- **未验**：真机。

---

### 2026-10-19 README 与详解版重写 + 文档树精简（删 3 篇 / 改 2 篇 / 新增 1 篇索引）；纯文档，零代码行为改动 / 零测试增减

- **性质**：文档治理批次，目标是让 README 不再是黑话并砍掉已闭环的冗余文档。
- **改动**：①`README.md` 全文改大白话（开头一句话说清产品是什么，「能做什么」按用户视角列 8 项，FSRS 一句话解释，新增「运行需要什么」表与「不做的事」）；②`docs/project-guide.md` 保留原 17 节编号与标题（锚点不动）但内容按「只写还在的代码」重写，§5.13 删除后各节号不动，新增开篇现状速览表与 §1 目标用户 / 已知取舍；③订正过期事实（`schemaVersion` 实读 29、drift 13 张表、LessonTemplate 为 6 种教学模板 + 1 种兜底、`make ci` 实际 8 个目标），并对齐 Android / iOS 构建文档与 `tool/gui` 跑法；④删 3 篇（先内联独有内容再删）并新增 `docs/README.md` 文档索引，保留 `ankiUpdate` 两篇、`docs/official-anki-migration/archive/` 与全部 37 篇 ADR，另修 6 处断链（含 `.agents/skills` 下 20 处缺 `quick-rules/` 前缀）。
- **验证**：`flutter analyze` No issues found；`flutter test --exclude-tags golden` **2189 passed / 0 failed**；`python -m unittest discover -s test -p "*_test.py"` **Ran 60 tests / OK**；`check_docs_index.py --quiet` 12 documents, 0 orphans；全部 214 篇受版本控制的 markdown 相对链接全量解析，断链 0。
- **未验**：`tool/gui` 的 `gen_module_tree.py --check` 与 `check_ai_boundaries.py` 在干净 HEAD 上同样 exit 1，属本批之外的既存失败，未处理。

---

### 2026-10-19 鸿蒙复习页白屏修复：移除预热 + 顶栏四键收回 + 启动探针关闭；真机通过

- **性质**：入口缺陷修复 + 产品面精简，提交 `9f41ed25`。
- **改动**：①根因是预热与「首卡只能由 widget 树 attach 时 present」互斥——独立 ability 盖住 Flutter 页面时 Flutter 不产帧，`setState` 只标脏不重建，Stage 永不 mount，点击翻面无回执，只能靠 60 s idle deadline 自愈；②页面不再预热，首卡由 `OfficialAnkiReviewerStage.attach` 在 Flutter 仍在前台时 present，advance / present 抽成顶层 helper 并加顺序守卫；③顶栏四键（撤销 / 重做 / 搁置 / 暂停）与 `requestCardAction` / `requestUndo` 协议全链路删除，payload 契约字段 `canRedo` / `canMutate` 保留（页面不消费），另新增 `chromeThemeFor({dark, highContrast})` 单一来源；④启动不再拉起 `AnkiReviewerProbeAbility` 与音频 / 语音探针（探针代码仍在 `ets/probe/`，需手动启动），守卫改为反向断言（四词按钮与 handler 不得回归、页面源码不得出现预热）。
- **验证**：analyze 0 issue；相关两目录 `flutter test` 429 / 430 passed；fork `flutter build hap --debug` rc=0；真机（CMM-AL10 / HarmonyOS 7.0.0.109 / API 26）截图链 `s1→s2→n1→p1→p2→q1→q2`，入口不白屏 / 首卡呈现 / 翻面 / 二档 / 评分后推进 / 顶栏精简全部通过。
- **未验**：首卡时延数值、连续过卡 ≥6、Review All 跨源、高对比度观感、`presentInPlace` 跳过分支的边角。

---

### 2026-10-18 鸿蒙复习推进修通：注入了「被盖住的 Flutter 页不产帧」这条真根因，并让 binding 原地装卡 present

- **性质**：真机缺陷修复 + 真机收据（CMM-AL10 / HarmonyOS 7.0.0.109 / API 26）。
- **改动**：①根因同上一条——复习器是独立 ability，盖住 Flutter 页面时 `setState` 只标脏不重建，binding 拿不到新卡，一次 present 都不发，12 s 后 watchdog 判 `rating_stalled`（评分回执本身是 ok 的，差的只是「谁把下一张装进来」）；②新增 `OfficialAnkiOhosReviewerBinding.presentInPlace(cardId)`，成功判据为 `card.cardId == cardId && !ui.isError`；③成功后补 `acceptPresentation(question)`，否则新卡永远没有 `questionReceipt`、`canReveal` 为 false，翻面在 Dart 侧静默 no-op；④评分分支与 redo / bury / suspend 三键路径都接上，并新增 7 条诊断日志（body rebuild / body boot / stage attach / present card / present suppressed / in-place present）。
- **验证**：`flutter analyze lib` No issues found；全量 `flutter test --exclude-tags golden` **2197 passed / 0 failed**（新增 3 条守卫）；`flutter build hap --debug`（fork SDK）成功并 `hdc install -r` 装机；真机一次会话连评 6 张（记住 ×4 / 忘记 ×1 / 搁置 ×1），进度 `1/8 → 2/9 → 3/11 → 6/16`，全程 **0 次** `rating_stalled` / `advance_failed`，`again` 首次取证 `ease=1 ivl=-60`。
- **未验**：Flutter 帧恢复时同一张卡会重渲染一次（需把渲染控制器提到会话级持有，属结构性改动，未做）。

---

### 2026-10-18 鸿蒙复习链路首次真机复验：三处修复 + 两处阻塞缺陷登记

- **性质**：真机验收（CMM-AL10 / HarmonyOS 7.0.0.109 / API 26），首次把 UI-15 / UI-16 的 ArkTS 改动放上设备。
- **改动**：①已验证通过二档按钮、`记住 → ease=3(good) ivl=6`、Review All 源徽章、三键 `enabled` 属性、完成交棒到 `UnifiedReviewCompletion`、早退不发完成屏；②登记两处阻塞缺陷（未修）——评分后推进抛 `advance_failed`，连锁 `card_mismatch`（`official_anki.scheduling_context_stale`）；③主题首批时序：抽 `_syncChrome()` 前置，`attach` / `rebind` 增 `chromeTheme` 形参，首卡不再用构造默认值；④预热 deadline 20 s → 60 s 并在 `attach` 起手 disarm，三键颜色按同一谓词走 `textPrimary` / `textSecondary`，`advanceFromNativeRating` 失败分支加结构化日志（`phase` / `locked` / `current` / `items`）。
- **验证**：`flutter analyze lib` No issues found；全量 `flutter test --exclude-tags golden` **2192 passed / 0 failed**（新增 2 例 chrome 守卫）；`flutter build hap --debug` 成功并 `hdc install -r` 装机。
- **未验**：`advance_failed` 根因（下一轮带日志复现）、`again` 落库值、高对比度色板观感、`sourceProgress` 多源场景、连续进出 ×20。

---

### 2026-10-18 鸿蒙 UI-16 完成屏交棒：单源会话答完即把完成屏还给 Flutter

- **性质**：对齐缺口收尾 + 修一个结算缺陷。
- **改动**：①`_onNativeAbilityClosed` 改为按 `answeredCount > 0` 结算，且 `verdict == completed && isComplete && answered > 0` 时不 pop，保留 Flutter 侧已渲染好的完成屏（Review All 未完成时显示换源 spinner，避免闪一张属于刚结束那个源的完成屏）；②`ohosReviewerPayload` 新增 `autoComplete`，ArkTS 侧 `ReviewerPresentPayload` / `ReviewerChromeState` 同步（`chromeState` 第 16 个参数），`fetchSettlement` 拿到统计后 600 ms 自动 `endReview(VERDICT_COMPLETED)`，完成行在 `autoComplete` 时只出「复习完成 / 正在打开结算…」；③`endReview` 加 `terminating` 幂等守卫，`resetChrome` 只复位 `autoCloseScheduled`（`terminating` 守的是 ability 不是 session）；④Review All 不自动关——下一源复用同一个 ability，结束的源武装的定时器会关掉下一源正在用的页面，故定时器回调再校验 `alive && complete` 作双保险。
- **验证**：`flutter analyze lib` No issues found；全量 `flutter test --exclude-tags golden` **2190 passed / 0 failed**；`flutter build hap --debug` 成功（签名 hap）；`ohos_card_action_chrome_guard_test.dart` 新增 1 例 5 断言。
- **未验**：真机（600 ms 交棒观感、完成屏 XP 非零、Review All 跨源不被误关）。
