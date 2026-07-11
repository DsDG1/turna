# Varnamala Future Plan v4：从"内容可生产"到"框架可维护 + 体验完整"

> 本文档继承 [`future3.md`](./future3.md)。future3 把框架从"打磨完毕"推进到"内容生产工具链就绪"（Phase 13–15.5 已完成）；future3 留下的工作分两类：**纯内容**（试点种子、全量 Swahili 替换、lesson 重写）与**非内容的框架/功能/工程**（学习体验功能、可访问性、发布流水线）。future4 把后者与"框架本身的优化"合并成一份**综合大计划**——把"能跑"提升为"能长期维护、能规模化、能放心重构"，同时把对学习者有长期价值的功能补齐。
>
> 撰写日期：2026-07-11
> 适用对象：开发者 / Agent
> **本轮范围：框架优化 + future3 遗留的非内容功能/工程。不新增真实 Swahili 词表（内容留 future5）。Kannada-as-Swahili 占位词保留到下一内容轮。**

---

## 1. 文档定位

| 文档 | 回答的问题 | 状态 |
|---|---|---|
| `dreamplan.md` | 早期"宏大愿景"（11,000 课、GUI 编辑器等） | 已被 future2 取代，仅作历史参考 |
| `future2.md` | 如何去社交化、打磨框架到任意内容可渲染/复习/统计 | 已完成（Phase 7–12） |
| `future3.md` | 内容审计、内容生产 CLI、音频策略、工程债清理 | Phase 13–15.5 已完成；Phase 16/20/21 纯内容推迟到 future5 |
| `future4.md` | 框架优化（架构/性能/测试/构建卫生）+ future3 遗留非内容功能/工程 | **本文档** |
| `future5.md` | 真实 Swahili 词表全量替换、lesson 重写（内容轮） | 下一轮，待 future4 地基就位 |

**核心原则延续**：
- 本地优先、无云、无社交、无付费摩擦。
- 不引入 Hearts / League / Leaderboard / Gems 商店等"反学习"机制。
- **不新增真实 Swahili 词表**——内容留 future5。但**可以做依赖内容之外的功能**：词典页搜索现有占位词即可验证；弱词训练用的是现有 `MistakeProvider` 数据；提醒、课程树状态、可访问性都不依赖新内容。
- 任何改动必须回答：**它是否让框架更可维护 / 更可规模化 / 更可测试 / 让单人离线学习体验更好？**
- **不动内容资产**：`assets/courses/**`、`migration/`、`vocab_map.json` 本轮一律不碰。本轮验收以 `flutter test` / `flutter analyze` / 新增功能测试为准，不以"真实 Swahili 词数"为准。

---

## 2. 当前真实状态（future3 Phase 15.5 之后）

> 基线（2026-07-10）：`flutter test` **221/221**，`flutter analyze` **0 issue**；包名 `varnamala`。8 个 ADR（0001–0008）在册。
>
> Phase 16 后（2026-07-11）：`flutter test` **296/296**，`flutter analyze` **0 issue**。新增 `sm2_test`、`lesson_link_store_test`、`study_log_repository_test`、`course_repository_test`，扩展 `schema_migration_test`、`srs_provider_test`。
>
> Phase 17 后（2026-07-11）：`flutter test` **314/314**，`flutter analyze` **0 issue**。新增 `verbose_test`、`seeder_cross_course_validation_test`、`content_update_dialog_test`；扩展 `course_repository_test`（损坏 content 降级）、`study_log_repository_test`（`_readLogs` 降级）、`schema_migration_test`（v6→v5 降级）、`seeder_idempotent_test`（复合版本）。ADR 0009 新增，ADR 0006/0002 更新。`com.example.varnamala` → `com.varnamala.app` + 签名骨架；`CourseDatabase` 加降级处理；内容版本复合 `index+expressions` + 跨 course id 门禁；内容更新提示（ADR 0002）落地。
>
> Phase 18 后（2026-07-11）：`flutter test` **326/326**，`flutter analyze` **0 issue**。`AudioController` 用注入 `_settingsProvider` + `VocabAudioResolver`（不再 import `swahili_vocab`）；`MatchProvider` 构造注入 `AppPrefs` + 字段封装；`AppRouter` 注解化 + `CourseReadyGuard`；`speakListenContent` 下沉路径判断。ADR 0010 新增，ADR 0007 更新。
>
> Phase 19 后（2026-07-11）：`flutter test` **332/332**，`flutter analyze` **0 issue**。4 输入 renderer 去按键 `setState`（VLB）；`LearningStats` future 缓存；`getWeakWords` 走 `MistakeProvider`；课程树展开惰性 ListView + section Selector。
>
> Phase 20 后（2026-07-11）：`flutter test` **340/340**，`flutter analyze` **0 issue**。`expressionDueCount` 缓存；SRS encode 基线 + ADR 0011 推迟分片；StudyLog recent 队列 (cap 200) + ADR 0012；play hub `_PlayHubCard`；views 外 `Colors.white` → 0。
>
> Phase 21 后（2026-07-11）：`flutter test` **342/342**，`flutter analyze` **0 issue**。`SrsQueueProvider` 基类 + 薄子类（ADR 0013）；`ICourseRepository`/`IStudyLogRepository`；Piper init Completer 化。
>
> Phase 22 后（2026-07-11）：`flutter test` **350/350**，`flutter analyze` **0 issue**。词典页 + 弱词小测（30d/≥2）+ 本地每日提醒 + 课程树 due/weak 状态 + MCQ Semantics；ADR 0014。
>
> Phase 23 后（2026-07-11）：`flutter test` **358/358**，`flutter analyze` **0 issue**。GameProvider 拆为 Score/Streak/LessonProgress/GameMilestone + 薄外观；`streak_resolver` 纯函数；ADR 0015。
>
> Phase 24 后（2026-07-11）：`flutter test` **372/372**，`flutter analyze` **0 issue**。`test/integration/` 三流 + `test/golden/` 亮暗 8 图；ADR 0016。
>
> Phase 25 后（2026-07-11）：`flutter test` **372/372**，`flutter analyze` **0 issue**。新增 `tool/build_release.py`、`test/tool/build_release_test.py`、`docs/decisions/0017-release-pipeline-and-versioning.md`；更新 `.github/workflows/flutter_ci.yml`、`Makefile`、`docs/decisions/0004-ci-strategy.md`；生成 `docs/content_inventory_v0.4.0-future4.md`。

### 2.1 已稳固保留的好模式（本轮必须保持）

- 插件式 Renderer 分发（`renderer_module.dart` + `Interaction` sealed union）。
- `InteractionState` 与 UI 分离；isolate Piper worker；`AudioController` 集中 system↔offline fallback（`speakWithResult`）。
- `VarnamalaTheme` 颜色助手 + `_isDark(context)` 模式。
- `CourseRepository.section()` 的 batch `isIn` 查询（无 N+1）。
- `_writeChain` 串行化（`StudyLogRepository` / `LessonLinkStore`）。
- DB-as-derived-cache：`CourseDatabase` 是 seeded cache，JSON 资产是 source of truth。
- in-flight 合并（`SwahiliCourse.loadSection` / `CourseProvider.ensureSectionLoaded`）。
- sealed `Interaction` 联合体 + 穷尽 helper。
- `LessonCompletionCoordinator` 把完成副作用从 viewmodel 分离。
- `RepaintBoundary` + `Selector` 在课程树的细粒度重建。

### 2.2 本轮要解决的问题（已逐一核对源码）

| 类别 | 代表问题 | 已核对位置 |
|---|---|---|
| 架构/质量 | `GameProvider` god-class（428 行，4 broadcast 流，12+ prefs key，score/streak/achievement/lesson 完成全管）；streak 解析应为纯函数但留在 provider 内 | `lib/application/game_provider.dart:35-428`，`_resolveStreakOnPractice` 在 :375-408 |
| 架构/质量 | `AudioController._triggerHaptic`/`_playSound` 用 `getIt<SettingsProvider>()` 而非已注入的 `_settingsProvider` 字段 | `audio_controller.dart:123,127` vs 构造器 :77-90 |
| 架构/质量 | `MatchProvider` 全部游戏状态公开可变；`getIt<AppPrefs>()` 直取而非构造注入 | `match_provider.dart:28-48`，:58 |
| 架构/质量 | `StudyStatsProvider.getWeakWords()` 直读 prefs mistake log，绕过 `MistakeProvider._cached` | `study_stats_provider.dart:123-135`；`mistake_provider.dart:29-45` |
| 架构/质量 | `SrsProvider` 与 `GrammarReviewProvider` 近乎同构 | 两文件同字段 `_cachedState/_cachedDueWords/_cachedDueAt/_cachedDueCount` |
| 架构/质量 | `PiperSwahiliTts._init()` 忙等轮询（`while(_initializing) await 20ms`）而非 `Completer` | `piper_swahili_tts.dart:171-176` |
| 架构/质量 | `AudioController.speakWord` 直接 import `swahiliVocabById` → 音频耦合到 Swahili 内容 | `audio_controller.dart:16,363-370` |
| 架构/质量 | `ListenOnlyRenderer._speak()` 在 renderer 里做 asset 路径判断（`/` / `assets` 前缀），该逻辑应在 AudioController | `listen_only_renderer.dart:66-86` |
| 架构/质量 | 无 repository 接口（`ICourseRepository`/`IStudyLogRepository`），全具体类 | `lib/data/*` |
| 架构/质量 | `AppRouter` 在 `main.dart:45` 手动 `registerLazySingleton` 而非注解；无 route guard | `main.dart:45`，`lib/routing/routing.dart` |
| 性能/扩展 | 4 个输入 renderer `onChanged: (_) => setState(() {})` → 每次按键全子树重建 | `fill_blank_renderer.dart:148`、`type_the_word_renderer.dart:123`、`reading_short_answer_renderer.dart:107`、`translate_sentence_renderer.dart:142` |
| 性能/扩展 | `LearningStats` 每次 build 新建 3 个 FutureBuilder，无缓存，切 tab 重发 | `learning_stats.dart:28-52` |
| 性能/扩展 | `play_hub_screen.dart` 5 个近似卡片未参数化 | `_QuickPlayCard`/`_MistakesCard`/`_ReviewCard`/`_GrammarReviewCard`/`_DailyChallengeCard` |
| 性能/扩展 | `SrsProvider._persist` 每次复习全量重编码 `Map<String,SrsWord>` JSON；`expressionDueCount` 每次全扫（与 `dueCount` 缓存不对称） | `srs_provider.dart:232,239-252` |
| 性能/扩展 | `StudyLogRepository.appendLog` 每次 append 全量读+写 90 天日志 | `study_log_repository.dart:34-42` |
| 性能/扩展 | 课程树大数据量 ListView 未优化（lesson > 100）、资源懒加载缺失 | `course_tree.dart` |
| 测试 | 无 `test/core/sm2_test.dart`（SM-2 仅经 SrsProvider 间接测） | `test/core/` 只有 3 个文件 |
| 测试 | 无 `StudyLogRepository`/`CourseRepository`/`LessonLinkStore` 直接测试 | `test/` 目录 |
| 测试 | schema 迁移测试缺 v3→v5（只有 v1/v2/v4） | `test/data/schema_migration_test.dart:19,37,65` |
| 测试 | 无 `play_hub_screen`/`match_words`/`srs_review_screen`/`settings_sound_section`/profile 组件测试；无集成测试；无 golden；`MatchProvider`/`CourseProvider`（section 加载）无测试 | — |
| 构建/卫生 | `com.example.varnamala` 占位（TODO）；debug 签名（TODO） | `android/app/build.gradle:44,63` |
| 构建/卫生 | `AppPrefs.printBefore` debug 下对每次 prefs 写 `logger.d` 全量值 | `locator.dart:80-84` |
| 构建/卫生 | 持久化错误处理不一致：CourseRepository 用 `logger.w`，StudyLogRepository 用 `assert(()=>print())`（release 静默），LessonLinkStore 用裸 `print()`，SrsProvider 用 `debugPrint` | 多文件 |
| 构建/卫生 | `CourseDatabase.migration` 无 `onDowngrade`（降级崩溃）；`expressions.json` 自带 version 未被 `seedIfNeeded` 检查（只查 `index.json` version） | `course_database.dart:147`；`course_database_seeder.dart:41` |
| 构建/卫生 | 跨 course 的 lesson id 唯一性只在 CI 的 `validateSwahiliCourse` 检查，runtime `validateSection` 不检 → 跨 section 重复 id 能过 section 校验但破坏 `loadLessonById` | `course_validator.dart:110-111` |
| 构建/卫生 | `CourseRepository._toLesson`（:209）裸 `jsonDecode + LessonContent.fromJson` 无 try-catch → 内容 JSON 损坏时未捕获 | `course_repository.dart:217-221` |
| 构建/卫生 | ~40 处 `Colors.white` / 硬编码色散落 `views/**`（match_words、gems_display、review_components、statistics、loader 等） | grep 确认多文件 |
| 功能（future3 遗留） | 词典/搜索页缺失 | — |
| 功能（future3 遗留） | 弱词专项复习缺失（数据源 `getWeakWords` 已有但未做小测 UI） | — |
| 功能（future3 遗留） | 本地复习提醒缺失（`flutter_local_notifications` 未引入） | — |
| 功能（future3 遗留） | 课程树状态增强（已完成/弱词/到期复习标识）缺失 | — |
| 功能（future3 遗留） | 内容更新提示（version 跳变时询问重置进度）缺失 | — |
| 功能（future3 遗留） | 可访问性：icon button tooltip、MCQ 屏幕阅读器、对比度、输入框语义标签 | — |
| 功能（future3 遗留） | 发布流水线：版本策略、构建脚本、内容清单 | — |

**注**：Phase 16 已补齐 `sm2_test`、`lesson_link_store_test`、`study_log_repository_test`、`course_repository_test`，并扩展 `schema_migration_test` 覆盖 `v3 → v5`。上表中对应的三个"测试"行已解决，保留作为历史追踪。

**Phase 16 跑出来的两个待修缺口**（已纳入 Phase 17）：

| 位置 | 现象 | 计划修复 |
|---|---|---|
| `lib/data/study_log_repository.dart:_readLogs()` | 遇到损坏 JSON 直接抛 `FormatException`，无降级 | Phase 17 统一错误处理时包 try-catch，降级为空列表并 `logger.w` |
| `lib/data/course_repository.dart:_toLesson()` | 遇到损坏 `contentJson` 直接抛异常，无降级 | Phase 17 加 try-catch，降级为 `const LessonContent()` 并 `logger.w` |

---

## 3. 总目标

**在不新增任何真实 Swahili 内容的前提下，把 Varnamala 从"能跑通"提升到"能长期维护、能规模化、能放心重构，且对学习者体验完整"。**

六条线（对应若干 Phase）：

1. **架构与代码质量**：拆 god-class、收敛 DI、纯函数下沉、repository 接口化、解耦音频与内容。
2. **性能与可规模化**：消除按键级全重建、缓存统计 Future、参数化重复组件、SRS/日志增量持久化、课程树大数据量优化。
3. **测试覆盖**：补齐核心引擎与 repository 直接测试、补 schema v3、补缺失 widget 测试、引入集成测试与 golden。
4. **构建与工程卫生**：应用 ID 与签名、prefs 日志卫生、错误处理统一、迁移健壮性、内容完整性运行时门禁。
5. **学习体验功能**（future3 遗留）：词典/搜索页、弱词专项复习、本地复习提醒、课程树状态增强、内容更新提示。
6. **发布工程**（future3 遗留）：版本策略、构建脚本、内容清单、分发准备。

---

## 4. 明确不做（继承并扩展）

| 不做项 | 原因 |
|---|---|
| 任何新真实 Swahili 词表 / 全量替换 / lesson 重写 | 内容留 future5 |
| 试点内容种子（future3 Phase 16） | 纯内容，留 future5 |
| 多语言课程（除 Swahili 外）的真正落地 | 仅做"解耦"使其**可能**，不引入新语种 |
| 云端 / 后端 / 同步 | 本地优先不变 |
| 重写 Renderer 插件机制 / Interaction sealed union | 已是好模式，保留 |
| 替换 isolate Piper worker 架构 | 保留，仅修 `_init` 等待方式 |
| 替换 `CourseRepository` batch 查询 / `_writeChain` / DB-as-cache 策略 | 保留，仅补健壮性 |
| Hearts / League / Leaderboard / Gems 商店 / streak repair | 反学习机制，永不引入 |

---

## 5. 阶段规划

> **顺序原则**：先补测试地基再动架构；框架健壮性/卫生最先（为功能铺安全网）；功能开发放在框架地基与 DI 收敛之后；高风险大重构（拆 `GameProvider`）放最后并用"外观保留"降险；集成/golden 与发布流水线收尾。
>
> 每个阶段独立可发布、可测、可回滚。每个阶段结束必须 `flutter test` 全绿 + `flutter analyze` 0 issue，并把基线写回 `test/BASELINE.md`。

---

### Phase 16：测试地基（1 周） ✅ 已完成

**完成时间**：2026-07-11  
**提交**：`112ea20` on `future4/phase-16-test-foundation`

**目标**：在做任何架构重构前，先把"会被重构波及"的核心模块用直接测试钉住，避免重构时静默回归。

**范围**：
- 新增 `test/core/sm2_test.dart`：直接测 `Sm2Engine.review` 的 interval/ease/reps/lapse 演进（again/hard/good/easy 四档；首次复习；连续 good 的间隔增长；lapse 后重置 reps）。当前 SM-2 仅经 `SrsProvider` 间接覆盖（`lib/core/sm2.dart`）。
- 新增 `test/data/study_log_repository_test.dart`：用 fake/内存 prefs 测 `appendLog`→`readLastNDays` 聚合、90 天 purge、`clearAll`、`_writeChain` 串行（并发 append 不丢）、dailyStats 腐化降级为空（`lib/data/study_log_repository.dart`）。
- 新增 `test/data/course_repository_test.dart`：用 in-memory `NativeDatabase.memory()` 测 `section()` batch 取回顺序与分组、`lessonById`、`sectionShells`、`_decodePracticeItems`/`_decodeStringList` 腐化降级（`lib/data/course_repository.dart`）。
- 新增 `test/application/lesson_link_store_test.dart`：`upsertFirstSeen` 只记首次、`containsId`、`lessonNameFor`、`_writeChain` 串行（`lib/application/lesson_link_store.dart`）。
- 扩展 `test/data/schema_migration_test.dart`：补 v3→v5 用例（v3 = v2 grammar_points + `practiceItems` 列已存在；验证迁移到 v5 保留 practiceItems 且新增 expressions 表）。当前只有 v1/v2/v4。
- 扩展 `test/application/srs_provider_test.dart`：`registerWord`/`registerAll`、`getDueWords` 缓存命中/失效、`dueCount` 缓存回退、`reviewWord` 演进。为 Phase 19/20 改动建网。

**验收**：
- `flutter test` 数量从 221 提升到 **296**，全绿。
- `sm2_test.dart` 覆盖 SM-2 四档质量全路径 + leech 判定。
- `schema_migration_test.dart` 含 `v1/v2/v3/v4 -> v5` 用例，并断言 `v3` 的 `practiceItems` 保留。
- `test/BASELINE.md` 已更新。
- 不改动任何生产代码。

**ADR**：无新增（测试策略沿用 ADR 0005）。

---

### Phase 17：工程卫生波次 E + 构建健壮性 + 内容更新提示（1.5 周） ✅ 已完成

**完成时间**：2026-07-11  
**状态**：`flutter test` 314/314，`flutter analyze` 0 issue。详见 `test/BASELINE.md`。ADR 0009 新增，ADR 0006/0002 更新。

**目标**：把"明显不对但没人改"的卫生问题批量清掉，补迁移/内容完整性健壮性，并落地 future3 遗留的"内容更新提示"。可单独 ship，为后续功能开发铺干净地基。

**范围**：
- **`AppPrefs.printBefore` 降噪**（`locator.dart:80-84`）：debug 下对每次 prefs 写 `logger.d` 全量打印值——噪声 + debug 日志潜在数据泄漏。改为：默认只打 key，值仅在 `kDebugMode && Very.verbose` 二级开关下打印；确认 release 完全无输出。
- **错误处理统一**（落实 ADR 0006 到持久化层）：把 `StudyLogRepository` 的 `assert(() { print() })`（release 静默）、`LessonLinkStore` 的裸 `print()`、`SrsProvider` 的 `debugPrint` 统一为 `logger.w`，确保 release 可观测。逐文件改，不改语义。
- **`CourseRepository._toLesson` 加 try-catch**（`course_repository.dart:209-221`）：与同文件 `_decodePracticeItems`/`_decodeStringList` 已有的腐化降级对齐——`jsonDecode(contentJson) + LessonContent.fromJson` 包 try-catch，腐化时降级为 `const LessonContent()` 并 `logger.w`，避免损坏的内容 JSON 未捕获传播。
- **`StudyLogRepository._readLogs` 加 try-catch**（`study_log_repository.dart:128-136`）：与 `readAllDailyStats` 已有的腐化降级对齐——`jsonDecode(raw)` 包 try-catch，腐化时降级为空列表并 `logger.w`。Phase 16 的测试已暴露此缺口。
- **`CourseDatabase.migration` 加 `onDowngrade`**（`course_database.dart:147`）：当前降级直接崩溃。加 `onDowngrade`（createAll 或显式 throw 带可读信息，决策见 ADR）。
- **跨 course lesson id 运行时门禁**（`course_validator.dart:110-111`）：runtime `validateSection` 不检跨 section 重复 id。在 `DatabaseSeeder` seed 阶段（已有全量 sections）加一次跨 course id 唯一性断言，重复时 `logger.e` + 抛 `CourseValidationException`，把 CI-only 检查变成运行时也守得住。
- **`expressions.json` version 纳入 seed 校验**（`course_database_seeder.dart:41`）：当前只查 `index['version']`。`expressions.json` 有自己的 version 字段但变化不触发 reseed → 静默 seed miss。把 expressions version 纳入 reseed 触发条件。
- **Android applicationId + 签名骨架**（`android/app/build.gradle:44,63`）：`com.example.varnamala` → 确定真实 applicationId（记入 ADR）；release 签名配置骨架（不要求本轮接入真 keystore，但 TODO 占位替换为可配置 `signingConfig` 读取 `key.properties` 的骨架）。
- **内容更新提示**（future3 Phase 17 遗留子项）：App 启动检测内置课程 version 变化；若 version 升高，弹出说明"课程已更新。是否重置进度？"（保留/重置二选一，沿用 ADR 0002 策略）。本轮 version 机制已在（Phase 17 已纳 expressions version），只需加启动检测 + 弹窗。**不依赖新内容**——现有 version 跳变即可触发。

**验收**：
- `flutter analyze` 0 issue；`flutter test` 全绿。
- grep 确认持久化层无裸 `print()`、无 `assert(()=>print())`、无 `debugPrint` 用于错误（统一 `logger.w`）。
- 故意注入损坏 lesson content JSON 的测试 → `lessonById` 返回空 content 且不抛。
- 故意注入损坏 study logs JSON 的测试 → `readLogs` 返回空列表且不抛。
- 故意降级 schema 的测试 → 不崩溃（`onDowngrade` 路径）。
- 跨 section 重复 lesson id 的 fixture → seeder 抛错而非静默通过。
- `build.gradle` 无 `com.example`、无 `TODO: Add your own signing`。
- 内容更新提示在 version 跳变时弹窗（widget 测试）。

**ADR**：
- 新增 `docs/decisions/0009-android-application-id-and-signing.md`：applicationId 命名与 release 签名配置方式（`key.properties` 骨架）+ `onDowngrade` 策略。
- 更新 `docs/decisions/0006-unified-error-handling.md`：补"持久化层错误统一 `logger.w`"小节。

**测试**：
- `course_repository_test.dart` 加损坏 content 降级用例；`study_log_repository_test.dart` 加损坏 logs 降级用例。
- `schema_migration_test.dart` 加降级用例。
- `seeder` 测试加跨 section 重复 id 抛错 + expressions version 触发 reseed 用例。
- 内容更新提示 widget 测试。

---

### Phase 18：DI 收敛 + 音频/内容解耦（1.5 周） ✅ 已完成

**完成时间**：2026-07-11  
**状态**：`flutter test` 326/326，`flutter analyze` 0 issue。详见 `test/BASELINE.md`。ADR 0010 新增，ADR 0007 更新。

**目标**：消除"已注入又直取 getIt"的反模式，把音频从 Swahili 内容解耦（为未来多语种铺路，本轮不引入新语种）。前置 Phase 16。

**范围**：
- **`AudioController` 用注入字段**（`audio_controller.dart:123,127`）：`_triggerHaptic`/`_playSound` 改用构造器已注入的 `_settingsProvider`，删掉 `getIt<SettingsProvider>()`。
- **`MatchProvider` 构造注入 `AppPrefs`**（`match_provider.dart:58`）：`getIt<AppPrefs>()` → 构造器注入，对齐项目 DI 约定。
- **`MatchProvider` 封装**（`match_provider.dart:28-48`）：`englishWords`/`targetWords`/`matchedPairs`/`selectedEnglishWord`/`selectedTargetWord`/`matchedWords`/`wordPairs`/`sessionScore` 等 12+ 公开可变字段 → 私有化 + 只读 getter。`secondsRemaining` 私有化（`countdownNotifier` 已是公开 `ValueNotifier`，UI 应只听它）。
- **`AudioController.speakWord` 解耦 Swahili 内容**（`audio_controller.dart:16,363-370`）：去掉 `import swahili_vocab.dart`。引入 `VocabAudioResolver` 抽象（接口 in `lib/domain/audio/`），`swahiliVocabById` 查询移到 Swahili 侧 `@lazySingleton` 实现。`AudioController` 只依赖接口。本轮不改行为，只搬依赖方向。
- **asset 路径判断下沉**（`listen_only_renderer.dart:66-86`）：`/` / `assets` 前缀的路径判断从 renderer 移入 `AudioController`（统一 `speakFromAsset` 的前缀归一化），renderer 只调 `audioController.speakFromAsset(path)` 或 `speak(text)`。
- **`AppRouter` 注解化**（`main.dart:45`，`lib/routing/routing.dart`）：手动 `getIt.registerLazySingleton<AppRouter>` 改为 `@LazySingleton()` 注解。加一个最小 route guard 骨架（`CourseReadyGuard`：DB 未 seed 完成时重定向到 splash），本轮可只接 splash 一个点验证机制——也为 Phase 22 词典新 route 铺路。

**验收**：
- grep 确认 `audio_controller.dart`、`match_provider.dart` 无 `getIt<` 直取（除 `_applyGemBonus` 兜底）。
- `MatchProvider` 字段全部 `_` 私有 + 只读 getter；既有 match_words widget 测试通过（如有，否则补最小 widget 测试）。
- `AudioController` 不再 import `swahili_vocab.dart`；`speakWord` 行为不变（fake resolver 测试覆盖）。
- `main.dart` 无手动 `registerLazySingleton<AppRouter>`；app 启动路由不变。
- `flutter test` 全绿，`flutter analyze` 0 issue。

**ADR**：
- 新增 `docs/decisions/0010-audio-content-decoupling.md`：`VocabAudioResolver` 抽象与多语种铺路策略（本轮不引入新语种）。
- 更新 `docs/decisions/0007-di-consolidation-and-refactors.md`：补"已注入字段优先于 getIt 直取"规则 + `AppRouter` 注解化。

**测试**：
- `match_provider_test.dart`：状态封装后行为不变（选词/匹配/换位/轮次）。
- `audio_controller_test.dart` 加 `speakWord` 走 resolver 的 fake 测试。
- `app_router` guard 的最小 widget 测试。

---

### Phase 19：性能波次 I — 输入重建 + 统计缓存 + rebuild 审计（1 周） ✅ 已完成

**完成时间**：2026-07-11  
**状态**：`flutter test` 332/332，`flutter analyze` 0 issue。详见 `test/BASELINE.md`。

**目标**：消灭最高频的无谓重建——按键级全子树重建、统计页 FutureBuilder 重复触发——并补 future3 Phase 18 的 Provider rebuild 审计。前置 Phase 16。

**范围**：
- **输入 renderer 去 `setState`**（4 文件）：`fill_blank_renderer.dart:148`、`type_the_word_renderer.dart:123`、`reading_short_answer_renderer.dart:107`、`translate_sentence_renderer.dart:142` 的 `onChanged: (_) => setState(() {})` → `ValueListenableBuilder` 绑 `TextEditingController`，只在"提交/校验"时才 `setState`，按键只重建输入框局部。提交按钮 enabled 态用 `ValueListenableBuilder` 自然驱动。
- **`LearningStats` 缓存**（`learning_stats.dart:28-52`）：3 个 FutureBuilder 每次 build 新建 future，切 tab 重发。改为 `StatefulWidget` + `didChangeDependencies` 里一次性赋值；`StudyStatsProvider` 变化时通过 `ChangeNotifier` 触发重建，而非靠 FutureBuilder 重发。
- **`StudyStatsProvider.getWeakWords()` 走 `MistakeProvider` 缓存**（`study_stats_provider.dart:123-135`）：当前直读 prefs mistake log 绕过 `MistakeProvider._cached`。改为注入 `MistakeProvider` 并复用其已解码缓存，避免双份解码 + 缓存不一致。**同时为 Phase 22 弱词训练提供干净的弱词数据源**。
- **Provider rebuild 审计**（future3 Phase 18 性能子项）：全局排查 `context.watch`/`Consumer` 粗粒度使用，改 `Selector`；课程树大数据量 ListView 优化（lesson > 100 的惰性构建/缓存）；图片/音频资源懒加载。

**验收**：
- 手动 profile：在 fill_blank/type_the_word 输入时，DevTools rebuild 统计只重建输入框子树，不再重建整个 renderer。
- `LearningStats` 切 tab 回来不重发 future（DevTools 无重复 prefs 读）。
- `getWeakWords` 不再直读 prefs；`MistakeProvider` 是唯一解码点。
- 低端 Android 设备上课程树滚动流畅。
- `flutter test` 全绿。

**ADR**：无新增；可在 `docs/decisions/0005-test-coverage-expansion.md` 补一条"重建性能 widget 测试基线"。

**测试**：
- 4 个 renderer 的 widget 测试：输入不触发父级重建（用 `tester` 计数 rebuild）。
- `learning_stats_test.dart`：切 tab future 不重发。
- `study_stats_provider_test.dart`：`getWeakWords` 复用 `MistakeProvider` 缓存（mock 验证只解码一次）。
- 课程树大数据量 widget 性能测试。

---

### Phase 20：性能波次 II — SRS/日志增量持久化 + 组件参数化 + 硬编码色收敛（2 周） ✅ 已完成

**完成时间**：2026-07-11  
**状态**：`flutter test` 340/340，`flutter analyze` 0 issue。ADR 0011/0012 新增。详见 `test/BASELINE.md`。

**目标**：去掉两个 O(n) 持久化热点，参数化重复 UI，收敛硬编码色，为规模化（大词表/长学习历史）扫清天花板。前置 Phase 16。

**范围**：
- **`expressionDueCount` 缓存**（`srs_provider.dart:232`）：当前每次全扫，与 `dueCount` 缓存不对称。维护 `_cachedExpressionDueCount`，与 word dueCount 同策略。
- **`SrsProvider._persist` 增量化评估**（`srs_provider.dart:239-252`）：当前每次复习全量 `jsonEncode` 整个 `Map<String,SrsWord>`——O(n) 每次复习。本轮**不重写存储格式**（风险高），先加性能基线测试（500/2000/10000 词下 `_persist` 耗时），再决定：>2000 词单次 encode > 5ms 则把 state 拆成 N 个分片 key（`srs.state.shard.<i>`），review 只重编受影响分片；若评估无瓶颈，本步只落 ADR 记录"当前规模无须分片，阈值 = X"，推迟实现。**决策点在 ADR**。
- **`StudyLogRepository.appendLog` 增量化**（`study_log_repository.dart:34-42`）：当前每次 append 全量读+写 90 天日志。改为增量事件队列（新 key `study.logs.recent`，cap 200）后台合并进主日志 + purge；或 ring-buffer append。保留 `_writeChain` 串行语义，`readLogs` 合并两源。**决策点在 ADR**。
- **`play_hub_screen` 卡片参数化**（`play_hub_screen.dart:88-470`）：5 个近似卡片合并为单个 `_PlayHubCard`（参数：title、subtitle、icon、badge、onTap、enabled、accentColor）。`_StatsCard` 保留（结构不同）。**为 Phase 22 新增 Weak Words 卡片复用同一组件**。
- **`Colors.white` / 硬编码色收敛**（views/** 约 40 处）：`match_words.dart:151,160,232`、`gems_display.dart:20,26,39`、`review_components.dart:33`、`statistics.dart:50`、`loader.dart:14` 等 → `VarnamalaTheme` 助手，保证暗色模式正确。按文件批次推进，每批过 widget 测试。**与 Phase 22 可访问性颜色对比度互补**。

**验收**：
- `expressionDueCount` 与 `dueCount` 同样有缓存（测试验证多次调用只扫一次）。
- SRS `_persist` 性能基线测试落地；是否分片由 ADR 决定并实现或显式推迟。
- `appendLog` 在 1000 条历史下耗时显著低于全量重写（基准测试）。
- `play_hub_screen` 只剩 `_PlayHubCard` + `_StatsCard` + `_SectionTitle`。
- grep `views/**` `Colors.white` 命中数下降至 theme.dart 内允许的少量。
- `flutter test` 全绿，`flutter analyze` 0 issue。

**ADR**：
- 新增 `docs/decisions/0011-srs-persistence-scaling.md`：分片阈值与策略（含"当前规模不实现"的量化决策）。
- 新增 `docs/decisions/0012-study-log-append-strategy.md`：增量队列 vs ring buffer 选择。

**测试**：
- `srs_provider_test.dart` 加 `expressionDueCount` 缓存断言 + `_persist` 性能基线。
- `study_log_repository_test.dart` 加 append 性能基准（1000 条）。
- `play_hub_screen_test.dart`：5 卡片渲染 + onTap 路由。
- 各 `views` 暗色硬编码清理的 widget 回归。

---

### Phase 21：SRS 基类抽取 + repository 接口化 + Piper Completer（1.5 周） ✅ 已完成

**完成时间**：2026-07-11  
**状态**：`flutter test` 342/342，`flutter analyze` 0 issue。ADR 0013 新增，ADR 0007 更新。详见 `test/BASELINE.md`。

**目标**：在性能波次与测试地基到位后，做中等风险的结构收敛——消除 `SrsProvider`/`GrammarReviewProvider` 重复，引入 repository 接口，修 Piper 忙等。前置 Phase 16, 18。

**范围**：
- **`SrsProvider`/`GrammarReviewProvider` 共享基类**：抽 `abstract class SrsQueueProvider extends ChangeNotifier`（`lib/application/srs_queue_provider.dart`），封装 `appPrefs`/`linkStore`/`_engine`/`_cachedState`/`_cachedDueWords`/`_cachedDueAt`/`_cachedDueCount` + `state`/`register`/`review`/`getDue`/`dueCount`/`_persist`。子类只覆写：prefs key、`SrsItemType` 过滤、`LinkType`。两者变薄到 ~50 行。**保持公开 API 不变**（调用方无感）。
- **Repository 接口**：定义 `lib/domain/repositories/`：`ICourseRepository`（`section`/`lessonById`/`sectionShells`/`vocabulary`/`grammarPoints`/`expressions`/`grammarPointById`/`expressionById`）、`IStudyLogRepository`（`appendLog`/`readLogs`/`readAllDailyStats`/`readLastNDays`/`clearAll`）。`CourseRepository`/`StudyLogRepository` implements。**注入点暂不改**（仍注册具体类），仅为可替换/可 mock 铺路；本轮不强制全切接口注入。
- **`PiperSwahiliTts._init` Completer 化**（`piper_swahili_tts.dart:171-176`）：`while(_initializing) await 20ms` 改为 `Completer<void>`，in-flight 调用 await 同一 completer。保留 isolate worker 架构不变。

**验收**：
- `SrsProvider`/`GrammarReviewProvider` 行为不变（既有 + Phase 16 测试全绿）；两者代码行数显著下降。
- `ICourseRepository`/`IStudyLogRepository` 存在且具体类 implements；既有调用点不变。
- `PiperSwahiliTts` 并发 init 测试不再走轮询；init 失败复用同一错误路径。
- `flutter test` 全绿，`flutter analyze` 0 issue。

**ADR**：
- 新增 `docs/decisions/0013-srs-queue-base-class.md`：基类抽取的 API 与子类差异点。
- 更新 `docs/decisions/0007-di-consolidation-and-refactors.md`：repository 接口引入与"暂不强制接口注入"的过渡策略。

**测试**：
- `srs_queue_provider_test.dart`：基类共享行为（注册/复习/缓存/持久化）。
- `grammar_review_provider_test.dart`：子类差异点（grammarPointId 键、LinkType）。
- `piper_tts_test.dart`：并发 init 走 Completer（fake worker）。

---

### Phase 22：学习体验功能 + 可访问性（2.5 周） ✅ 已完成

**完成时间**：2026-07-11  
**状态**：`flutter test` 350/350，`flutter analyze` 0 issue。ADR 0014 新增。详见 `test/BASELINE.md`。

**目标**：把 future3 Phase 17/18 遗留的非内容功能补齐——词典、弱词复习、本地提醒、课程树状态、可访问性。框架地基（测试、DI、性能、参数化卡片、干净弱词数据源）就位后做功能。前置 Phase 17, 18, 20。

**范围**：
- **词典 / 搜索页**：新 route `/dictionary`（用 Phase 18 的 route guard 机制）；按 term/translation/tag 搜索 vocab / expression / grammar point；显示 term、translation、pronunciation、example expression、音频播放按钮（经 Phase 18 解耦的 `AudioController` + `VocabAudioResolver`）。**搜索现有占位词即可验证，不需新内容**。复用 `swahiliVocabById`/`swahiliVocabByTranslation` 查找（`lib/courses/swahili_vocab.dart`）。
- **弱词专项复习**：Play hub 新增 "Weak Words" 卡片（复用 Phase 20 的 `_PlayHubCard`），生成 10 题小测，只含最近 30 天内错 ≥2 次的词。弱词数据源用 Phase 19 清理后的 `StudyStatsProvider.getWeakWords()`（走 `MistakeProvider`）。统计逻辑下沉为 `WeakWordQuizAssembler`（类似已有 `DailyChallengeAssembler`，`lib/application/daily_challenge_assembler.dart`）。
- **本地复习提醒**：`flutter_local_notifications`；Settings 页加 "Daily reminder" 开关与时间选择（复用 `SettingsProvider`）；提醒文案温和（如 "Time for a quick Swahili review"），无 streak repair、无惩罚。
- **课程树状态增强**：单元卡片显示：已完成 / 有弱词 / 有到期复习；lesson icon 根据状态变色。复用 `ProgressProvider`（已完成）、`SrsProvider.dueCount`（到期）、`MistakeProvider`/`StudyStatsProvider`（弱词）。用 `Selector` 细粒度避免重建。
- **可访问性**（future3 Phase 18 子项）：所有 icon button 加 `tooltip`；MCQ 选项支持屏幕阅读器朗读（`Semantics`）；颜色对比度检查（亮/暗，复用已有 `dark_mode_text_contrast_test.dart` 模式）；输入框加语义标签。

**验收**：
- 词典页可搜索并播放现有 vocab / expression 音频。
- 弱词小测正确聚合错题（最近 30 天错 ≥2 次）。
- 本地提醒在设定时间弹出（需真机/模拟器测试）。
- 课程树状态变色正确（已完成/弱词/到期）。
- icon button 全有 tooltip；MCQ 屏幕阅读器可朗读；对比度达标。
- `flutter test` 新增用例全过；低端 Android 设备上课程树滚动流畅。

**ADR**：
- 新增 `docs/decisions/0014-dictionary-and-weak-word-review.md`：词典数据源、弱词聚合阈值（30 天/≥2 次）。
- 本地提醒策略可在 `0006`/`0010` 旁补充说明。

**测试**：
- `dictionary_page_test.dart`、`weak_word_quiz_assembler_test.dart`、`weak_words_page_test.dart`、`settings_reminder_test.dart`、课程树状态 widget 测试、a11y 对比度回归。

---

### Phase 23：GameProvider 拆分（2 周，高风险，最后做） ✅ 已完成

**完成时间**：2026-07-11  
**状态**：`flutter test` 358/358，`flutter analyze` 0 issue。ADR 0015 新增。详见 `test/BASELINE.md`。

**目标**：把 428 行 god-class 按职责拆分，但**只在 Phase 16 测试地基 + Phase 18 DI 收敛完成后**进行，且用"外观保留"策略降低风险。前置 Phase 16, 18。

**范围与策略**：
- 当前 `GameProvider`（`game_provider.dart:35-428`）管：score、streak、achievement、lesson 完成记录、gem 奖励、4 broadcast 流。拆为：
  - `ScoreProvider`：score + XP。
  - `StreakProvider`：streak + `lastStreakDate` + `checkStreakOnAppOpen`。
  - `LessonProgressProvider`：`completedLessonIds`/`perfectLessonIds` + `recordLessonCompletion`/`resetLessonProgress`。
  - `AchievementProvider`：achievement 解锁 + gem 奖励协调。
- **纯函数下沉**：`_resolveStreakOnPractice`（`:375-408`）已是纯函数，移到 `lib/core/streak_resolver.dart`（接受 `oldStreak`/`oldDate`/`today`，返回 `StreakResolution`），单独单测。
- **外观保留**（降险关键）：保留 `GameProvider` 作为**薄外观**，转发到四个子 provider，维持 `completedLessonIds`/`completedLessonsStream`/`getUserStreakStream` 等公开 API 不变，使所有调用方零改动（**含 Phase 22 新增的课程树状态读取**）。后续可逐步迁移调用方到子 provider，但本轮不强求。
- **流收敛**：4 个 broadcast StreamController 评估是否可由子 provider 各自持有 + `GameProvider` 聚合，或保留在 `GameProvider` 由子 provider 调用回调。决策在 ADR。
- **gem 单写者**：`_applyGemBonus` 经 `GemsProvider` 的 single-writer 约定保留。

**验收**：
- `flutter test` 全绿（既有 GameProvider 测试 + Phase 16 新增测试 + 新 `streak_resolver_test.dart`）。
- `GameProvider` 行 < ~80 行（纯转发）；四个子 provider 各自可独立测试。
- `streak_resolver.dart` 是纯函数，无 prefs/无副作用，单测覆盖 gap=0/1/2/null 全路径。
- 所有 `GameProvider` 既有调用点 + Phase 22 新增调用点零改动（外观策略生效）。
- `flutter analyze` 0 issue。

**ADR**：
- 新增 `docs/decisions/0015-gameprovider-split.md`：拆分边界、外观保留策略、流归属、迁移路径。
- 更新 `docs/decisions/0007-di-consolidation-and-refactors.md`：GameProvider 拆分纳入 DI 收敛记录。

**测试**：
- `streak_resolver_test.dart`：纯函数全路径。
- `score_provider_test.dart` / `streak_provider_test.dart` / `lesson_progress_provider_test.dart` / `achievement_provider_test.dart`：各自独立。
- `game_provider_facade_test.dart`：外观转发后既有 API 行为不变（含 Phase 22 课程树状态读取，回归保护）。

---

### Phase 24：集成测试 + golden 基线（1.5 周） ✅ 已完成

**完成时间**：2026-07-11  
**状态**：`flutter test` 372/372，`flutter analyze` 0 issue。ADR 0016 新增。详见 `test/BASELINE.md`。

**目标**：在结构收敛与功能完成后，建立端到端与视觉回归基线，防止后续内容轮/重构破坏用户路径。前置 Phase 22, 23。

**范围**：
- 新增 `integration_test/lesson_flow_test.dart`：lesson 流程端到端（load section → 进 lesson → 答题 → 完成 → 返回课程树 → badge 出现）。用 in-memory DB + fake audio。
- 新增 `integration_test/srs_review_flow_test.dart`：SRS 到期 → 复习 → dueCount 下降 → 持久化跨重启（重启 = 重建 provider）。
- 新增 `integration_test/dictionary_and_weak_words_test.dart`：词典搜索 → 播放 → 弱词小测 → 完成（覆盖 Phase 22 功能端到端）。
- 新增 golden 测试（`test/golden/`）：至少 4 屏——`play_hub_screen`（含 Weak Words 卡）、`srs_review_screen`、`settings_sound_section`（含提醒开关）、`dictionary_page`——亮/暗双主题。golden 用 `flutter test --update-goldens` 生成并提交。
- 补缺失 widget 测试：`match_words`、`settings_sound_section`、profile 组件、lesson 完成/mastery retry 对话框。

**验收**：
- 三个集成测试在 `flutter test` 下通过。
- golden 测试亮/暗双主题通过（CI 上 `--update-goldens` 仅手动触发）。
- `flutter test` 总数 ≥ 221 + Phase 16~24 累计新增（估 +100~140）。
- `test/BASELINE.md` 更新最终基线。

**ADR**：
- 新增 `docs/decisions/0016-integration-and-golden-test-strategy.md`：集成测试范围、golden 维护策略（何时 `--update-goldens`、CI 失败处理）。

**测试**：本阶段产出即测试。

---

### Phase 25：发布流水线与版本策略（1 周） ✅ 已完成

**完成时间**：2026-07-11  
**状态**：`flutter test` 372/372，`flutter analyze` 0 issue。详见 `test/BASELINE.md`。ADR 0017 新增，ADR 0004 更新。

**目标**：把 future3 Phase 19 遗留的发布工程补齐，把框架+功能成果固定为可持续发布节奏。前置 Phase 24。

**范围**：
- **版本号与 tag 策略**：明确语义化版本规则（内容大改升 minor，工程改动升 patch）；准备 `v0.4.0-future4` 发布（框架+功能轮）。
- **构建脚本**：`tool/build_release.py`：自动执行 `flutter pub get`、`build_runner`、`flutter build apk/appbundle/web`、资源校验；生成带版本号的构建产物；复用 Phase 17 的 applicationId/签名骨架。
- **内容清单报告**：`docs/content_inventory_v0.4.0-future4.md`：词汇数、表达数、语法点数、lesson 数、音频覆盖率（现有占位内容）+ 已知问题与下一步内容缺口（交接 future5）。
- **分发准备**：截图（可用现有占位内容 + 新功能页）、应用描述。
- **CI**：CI workflow（Makefile per ADR 0004）跑通 `flutter test` + `flutter analyze` + 构建。

**验收**：
- 一条命令可打出 release APK/AAB。
- 内容清单报告可阅读。
- CI 跑通 test + analyze + 构建。

**ADR**：
- 新增 `docs/decisions/0017-release-pipeline-and-versioning.md`：版本规则、构建脚本、内容清单格式。
- 更新 `docs/decisions/0004-ci-strategy.md`：补构建脚本集成。

**测试**：
- `build_release.py` 的 Python 单元测试（future3 Phase 18 遗留）。
- CI 冒烟测试。

---

### Phase 26：文档收尾与内容轮交接（0.5 周）

**目标**：综合收尾，更新文档反映 future4 完成状态，明确 future5（内容轮）入口。前置 Phase 25。

**范围**：
- 更新 `CLAUDE.md`：反映 future4 完成状态（新 provider、新 route、新功能、新 ADR）。
- 写 `docs/decisions/0018-future4-completion-and-content-handoff.md`：总结 future4 完成项，明确 future5（内容轮）入口——真实 Swahili 词表替换的干净地基已就位（集成测试 + golden 兜底、`VocabAudioResolver` + repository 接口铺路、SRS/日志性能天花板移除）。
- `test/BASELINE.md` 最终基线；`docs/content_inventory_v0.4.0-future4.md` 定稿。

**验收**：
- `CLAUDE.md` 与代码一致。
- ADR 0001–0018 在册。
- `BASELINE.md` 反映最终基线；future5 入口文档清晰。

**ADR**：
- 新增 `docs/decisions/0018-future4-completion-and-content-handoff.md`。

---

## 6. 阶段总览与时间表

| Phase | 主题 | 来源 | 风险 | 估时 | 前置 |
|---|---|---|---|---|---|
| 16 | 测试地基 | 框架 | 低 | 1 周 | — |
| 17 | 工程卫生 + 构建健壮性 + 内容更新提示 | 框架 + future3 P17 | 低 | 1.5 周 | 16(可选) |
| 18 | DI 收敛 + 音频/内容解耦 | 框架 | 中 | 1.5 周 | 16 |
| 19 | 性能 I：输入重建 + 统计缓存 + rebuild 审计 | 框架 + future3 P18 | 中 | 1 周 | 16 |
| 20 | 性能 II：SRS/日志增量 + 组件参数化 + 硬编码色收敛 | 框架 | 中 | 2 周 | 16 |
| 21 | SRS 基类 + repository 接口 + Piper Completer | 框架 | 中 | 1.5 周 | 16, 18 |
| 22 | 学习体验功能（词典/弱词/提醒/课程树状态）+ 可访问性 | future3 P17/P18 | 中 | 2.5 周 | 17, 18, 20 |
| 23 | GameProvider 拆分 | 框架 | **高** | 2 周 | 16, 18 |
| 24 | 集成测试 + golden 基线 | 框架 + future3 P18 | 低 | 1.5 周 | 22, 23 |
| 25 | 发布流水线 + 版本策略 | future3 P19 | 低 | 1 周 | 24 |
| 26 | 文档收尾 + 内容轮交接 | 综合 | 低 | 0.5 周 | 25 |

**总计约 15–18 周**（一人全职）。高风险项（23）被刻意推到功能之后并用"外观保留"降险；低风险高价值项（16, 17）最先；功能（22）在框架地基（16–21）就位后做；集成/golden 与发布收尾。

---

## 7. 风险与缓解

| 风险 | 缓解 |
|---|---|
| 拆 GameProvider 引入回归 | Phase 16 先钉测试；Phase 23 用"外观保留"使调用方（含 22 新增）零改动；`game_provider_facade_test.dart` 回归 |
| SRS 持久化格式改动破坏进度 | Phase 20 不改格式，先测后定；分片策略由 ADR 量化阈值决定，当前规模可能不实现 |
| StudyLog 增量化改读取语义 | 保留 `_writeChain`；`readLogs` 合并两源；既有 `study_log_repository_test.dart`（Phase 16）兜底 |
| repository 接口引入但无人用 | 本轮不强切接口注入，仅定义 + 具体类 implements；迁移留后续 |
| golden 测试 CI 抖动 | ADR 0016 规定 golden 仅手动 `--update-goldens`，CI 失败阻塞而非自动更新 |
| 跨 section 重复 id 门禁误伤现有课程 | 先跑 `validateSwahiliCourse` 确认当前课程无重复；门禁只在 seeder 抛错，不改内容 |
| 音频解耦引入新语种诱惑 | ADR 0010 明确"本轮不引入新语种"，只搬依赖方向 |
| 暗色硬编码清理误改对比度 | 每批过 widget 测试 + 暗色 golden（Phase 24）兜底 |
| 功能开发依赖未就绪的数据源 | Phase 19 清理 `getWeakWords` → 22 弱词训练；Phase 18 解耦 `AudioController` → 22 词典音频；Phase 20 参数化卡片 → 22 新卡片复用；显式前置依赖 |
| 本地提醒真机依赖 | 模拟器验证 + CI 跳过真机项，文档标注需真机复测 |

---

## 8. 决策记录（ADR）清单

future4 期间新增/更新的 ADR（延续 0008 之后）：

| 编号 | 标题 | 阶段 |
|---|---|---|
| 0009 | Android applicationId 与 release 签名配置（含 `onDowngrade` 策略） | 17 |
| 0010 | 音频与内容解耦（`VocabAudioResolver`） | 18 |
| 0011 | SRS 持久化规模化策略与分片阈值 | 20 |
| 0012 | StudyLog append 增量化策略 | 20 |
| 0013 | SRS 队列基类抽取 | 21 |
| 0014 | 词典与弱词复习（数据源、弱词聚合阈值） | 22 |
| 0015 | GameProvider 拆分与外观保留 | 23 |
| 0016 | 集成测试与 golden 维护策略 | 24 |
| 0017 | 发布流水线与版本策略 | 25 |
| 0018 | future4 完成与内容轮交接 | 26 |
| 更新 0004 | 构建脚本集成 | 25 |
| 更新 0006 | 持久化层错误统一 `logger.w` | 17 |
| 更新 0007 | 已注入字段优先、AppRouter 注解化、GameProvider 拆分、repository 接口 | 18/21/23 |

---

## 9. 成功标准（future4 完成时）

- [ ] `flutter test` 全量通过，基线较 221 显著提升（估 +100~140）。
- [ ] `flutter analyze` 0 issue。
- [ ] 测试存在且绿：`sm2_test`、`study_log_repository_test`、`course_repository_test`、`lesson_link_store_test`、`srs_provider_test`、`match_provider_test`、`streak_resolver_test`、四子 provider 测试、`game_provider_facade_test`、`dictionary_page_test`、`weak_word_quiz_assembler_test`、`weak_words_page_test`、`settings_reminder_test`、a11y 对比度回归。
- [ ] `schema_migration_test.dart` 含 v3→v5 与降级用例。
- [ ] `integration_test/`：`lesson_flow`、`srs_review_flow`、`dictionary_and_weak_words` 三套通过。
- [ ] golden 测试（亮/暗，含新功能页）通过。
- [ ] `GameProvider` < ~80 行（外观）；`streak_resolver` 为纯函数。
- [ ] `SrsProvider`/`GrammarReviewProvider` 共享基类，行数显著下降。
- [ ] `AudioController` 不 import `swahili_vocab`；`audio_controller`/`match_provider` 无 `getIt<` 直取；`MatchProvider` 字段私有 + 只读 getter。
- [ ] 4 个输入 renderer 无 `onChanged: setState`；`LearningStats` future 缓存；`getWeakWords` 走 `MistakeProvider`。
- [ ] `play_hub` 卡片参数化为 `_PlayHubCard`（含 Weak Words 卡）；词典/弱词/提醒/课程树状态功能可用。
- [ ] `build.gradle` 无 `com.example` 无签名 TODO；prefs 错误统一 `logger.w`；`CourseRepository._toLesson` 有 try-catch；`CourseDatabase` 有 `onDowngrade`；seeder 检跨 section 重复 id + expressions version；内容更新提示弹窗。
- [ ] a11y：icon button 全 tooltip、MCQ 屏幕阅读器、对比度达标、输入框语义标签。
- [ ] 一条命令打 release APK/AAB；内容清单 v0.4.0-future4 可读；CI 跑通。
- [ ] ADR 0001–0018 在册，0004/0006/0007 已更新。
- [ ] `CLAUDE.md` 与代码一致；`BASELINE.md` 最终基线；future5 入口文档清晰。

---

## 10. 与未来内容轮（future5）的关系

future4 把"框架的可维护性 / 可测试性 / 可规模化"做完、并把对学习者的非内容功能补齐后，future5（内容轮）就可以在干净地基上安全推进 future3 Phase 16/20/21 的纯内容工作：

- 真实 Swahili 词表全量替换与 lesson 重写（此时已有集成测试与 golden 兜底，内容 PR 的回归风险被框定）。
- 真正引入第二个语种时，`VocabAudioResolver`（0010）与 repository 接口（0013/0007）已就位，只需新增一个语种的实现，无需动框架。
- SRS/日志在大词表与长学习历史下的性能天花板已移除（0011/0012）。
- 弱词训练、词典、提醒、课程树状态等功能已就位，真实内容一进来立即对学习者产生价值。

---

*本文档是 future3.md 的下一章。核心原则不变：单人、本地、纯净、无社交摩擦。变化的是：从"能生产内容"转向"让框架本身经得起规模化与长期维护，同时把学习体验补完整"，为下一轮真实内容落地铺好干净地基。*