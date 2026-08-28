# 垃圾代码审计报告 — Turna / Varnamalaplus

**日期**：2026-08-28　**范围**：`lib/`（586 dart）、`test/`、`tool/`、`native/` 自有代码、`assets/`、`pubspec.yaml`
**方法**：`flutter analyze` + 三路并行语义扫描 + 关键条目人工复核（grep 双重验证）

---

## 结论先行

**lint 层面非常干净**：`flutter analyze` 全项目只报 4 条 `unnecessary_const`（均在 test 文件）。**0 个 TODO、0 段注释掉的代码、0 个 `avoid_print` 违规、0 个硬编码密钥。** 这项目的代码卫生高于平均线。

**但 lint 抓不到语义级死代码，那里有真货**。共发现：

| 类别 | 数量 | 影响 |
|---|---|---|
| 完全孤儿的 dart 文件 | 9 个 / 1,252 行 | 纯死重，可直接删 |
| 僵尸机制（有实现无调用方） | 1 条完整死链 + 6 处独立僵尸 | 功能已死透但代码全在 |
| 僵尸公开符号 | 11 个（含 1 个全死 flag 类） | — |
| 僵尸成员（Provider/Repo/Coordinator） | 12+ 个（另有 19 个同类） | — |
| 死资源 | 5 个 PNG（2.52 MB 进包） | 包体积 |
| 版本库污染 | 455 个文件（AI 工具状态） | 提交历史 |
| `debugPrint` 绕开日志管线 | 110 处 | 诊断盲区 |

**最大的一块垃圾是一条完整的僵尸链**（见 B-0），它是 2026-08-27 legacy Anki 删除的遗留。

---

## A 档：可立即删（零风险，已双重验证）

### A-1. 9 个完全孤儿文件 — 1,252 行 / 40 KB

lib/ 与 test/ 均无 import 指向，无 `main()`。已用脚本解析全部 import 图并逐一 grep 类名复核。

```
  24 行  lib/application/ai/companion/ai_companion_feature_flags.dart
  34 行  lib/application/ai/companion/companion_prompt_registry.dart
 111 行  lib/application/ai/companion/course_knowledge_retriever.dart
 147 行  lib/application/ai/companion/learner_profile_assembler.dart
   6 行  lib/courses/languages/languages.dart
 199 行  lib/views/ai/textbook/textbook_conflict_preview.dart
 261 行  lib/views/ai/textbook/textbook_review_panel.dart
 166 行  lib/views/onboarding/onboarding_screen.dart
 304 行  lib/views/widgets/turna_toast.dart
```

复核证据：`OnboardingScreen` / `TurnaToast` 全库仅出现在各自文件内；`textbook_*` / `companion_*` 零命中。
⚠️ `onboarding_screen.dart` 和 `turna_toast.dart` 是完整 UI 组件，删除前确认不是「预留未接线」的功能。

### A-2. 死资源 — 5 个 PNG，2.52 MB（**进 App 包**）

`assets/images/turna/` 下 5 个，flutter_gen 符号（`Assets.images.turna.*`）与文件名双重 grep 均 0 命中：

```
 824 KB  assets/images/turna/app_logo.png        ← 与 assets/images/app_logo.png 字节完全相同
 425 KB  assets/images/turna/turna_encourage.png
 535 KB  assets/images/turna/turna_listening.png
 392 KB  assets/images/turna/turna_standing.png
 402 KB  assets/images/turna/turna_thinking.png
```

同类 8 个 `assets/images/turna_*.jpg`（2.56 MB）是 `tool/convert_mascot_to_png.py` 的**输入源**，不建议删，建议**移出 `assets/`**（工具仍可用，包体积省 2.56 MB）。

### A-3. 其他确定垃圾

| 项 | 大小 | 依据 |
|---|---|---|
| `android/app/src/main/res/mipmap-*/ic_launcher.png`（5 个） | 4 KB | Flutter 默认模板图标，`AndroidManifest` 只认 `launcher_icon` |
| `assets/courses/turkish/.varnamala-backup/`（24 文件） | 46 KB | GUI 运行时产物，已被 gitignore、`git ls-files` 0 跟踪 |
| `pubspec_overrides.yaml.disabled` | 1.9 KB | OHOS 遗留（ADR 0041 已 EOL）。注释声称的「OHOS git forks」在 pubspec 里已 0 命中 |
| `pubspec.yaml` → 移除 `cupertino_icons` | — | 全仓库 0 处 import，Flutter 模板遗留 |
| `build/ohos/` | 99 MB | OHOS EOL 后的构建产物（已 gitignore，仅占磁盘） |
| `.deveco/` | 57 MB | DevEco 工具链缓存（已 gitignore） |

---

## B 档：僵尸机制（代码在，功能死 — 需决策）

### B-0. 完整死链：「智能去解密」预渲染缓存 ☠️

这是 legacy Anki 删除留下的**一条完整僵尸链**，四环全死、互相咬合：

```
onCaptured 回调零传入方（anki_html_card_view.dart:54）
        ↓  _capture() 在 :454 恒 return
upsertPrerenderedFace 生产零调用（anki_note_dao.dart:727，仅 test 用）
        ↓  预渲染表恒为空
prerenderCacheStats / deletePrerenderedByPrefix → 永远统计 0、永远删空集合
        ↑
ankiPreRenderEnabled 开关（settings_provider.dart:33）→ 不控制任何行为分支
```

**复核证据**：
- `upsertPrerenderedFace` 在 lib/ 只出现 2 次，均为定义处 `:727` 和它自己的审计日志字符串 `:735`；8 处调用全在 test。
- `ankiPreRenderEnabled` 有 12 处命中，但全是 prefs 读写（`:106/:205/:323`）、getter/setter、UI 展示（`settings_advanced_section.dart:128`、`system_health_page.dart:297`）、备份清单。**lib 内无任何行为分支读取它** —— 用户能在设置页拨这个开关，拨了什么也不会发生。

**处置**：整链拆除。涉及 `anki_html_card_view.dart`、`anki_note_dao.dart`、`settings_provider.dart`、`storage_inventory_service.dart`、`storage_maintenance_service.dart`、设置页/系统健康页 UI、2 个测试文件。

### B-1. 其他独立僵尸（全部双重验证）

| 位置 | 符号 | 判定依据 |
|---|---|---|
| `official_formal_due_repository.dart:197` | `onSourceRefreshNeeded` | 全库仅 2 处：声明 + `:339` 的 `?.call()`。**零赋值、零传入、零测试** —— 与 `onCaptured` 完全同构，头号目标 |
| `official_anki_course_entry.dart:32` | `courseOf` | 全库仅 3 处：声明、`:42` 重置为 null、`:100` 读取 → 恒走 fallback |
| `official_anki_course_entry.dart:36` | `pathsOf` | 同上，`:43` 重置、`:150` 读取 → 恒 null |
| `official_anki_course_entry.dart:30` | `activeSectionIds` | 生产无赋值，仅测试在 `:80` 赋过 |
| `unified_review_page.dart:39-40` | `onOutcomeRecorded` / `onOutcomeUndone` | 唯一构造点 `srs_review_screen.dart:92` 未传；`UnifiedReviewRoute` 无任何 push 点 → 恒空转 |
| `official_anki_feature_flags.dart:35` | `legacyMirror` | lib 内**零读取点**（只有自身定义/copyWith），连聚合 getter 都没有 → `TURNA_OFFICIAL_ANKI_LEGACY_MIRROR` 环境变量完全无效 |
| `official_anki_feature_flags.dart:23` | `diagnostics` | lib 内零消费点 → `TURNA_OFFICIAL_ANKI_DIAGNOSTICS` 死开关 |
| `official_anki_feature_flags.dart:33` | `courseGradesScheduler` | 唯一消费者 `official_anki_course_grades_bridge.dart:30`，生产恒 false → 该分支恒不执行 |
| `system_health_monitor.dart:38` | `integrityProbe` | 生产注册点 `locator.dart:346` 未传，恒走默认实现（**仅测试引用**，GetIt 动态注册标疑似） |
| `remote_backup_service.dart:78` | `busyGuard` | 生产未传 → `:157` 恒 false，busy 拦截分支不可达（**仅测试引用**） |

### B-2. 僵尸公开符号（已复核）

- `lib/application/ai/companion/ai_companion_feature_flags.dart:4` — `AiCompanionFeatureFlags` 整类死透：全库仅 2 处（类声明 + 构造器），零实例化、零字段访问、零 DI 注册。连同 8 个 flag 字段（`durableSessions`/`evidenceProfile`/`hintLadder`/`todayPlan`/`courseCitations`/`learningNotes`/`offlineRetrieval`/`roleplayRecap`）。
- `canonical_card_key.dart:77` — `CanonicalCard`（注意不是 `CanonicalCardKey`，后者活得好好的）：仅声明 + 构造器。
- `card_presentation.dart:99` — `PresentationCandidate`：同上。
- `anki_import_completion_coordinator.dart:48` — `typedef AnkiImportCompletion`：0 处引用。
- `anki_import_completion_coordinator.dart:50` — extension 方法 `wireKeyForImportId`（1 参版）：0 调用；`anki_import_screen.dart:372/386` 命中的是同名 3 参局部函数。

### B-3. 僵尸成员（仅声明处 1 次，无读取、无测试）

`official_formal_review_coordinator.dart` 三个（`hasMoreCards:370` / `liveLength:218` / `recoveredCount:392`）、
`official_anki_mutation_receipt.dart:27 blocksCard`、`anki_deck_manager.dart:517 shouldMigrateToSqlite`、
`official_anki_present_ack.dart:108 acceptedGeneration`、`official_anki_operation_coordinator.dart:58 isReviewing`、
`anki_import_execution_plan.dart:76 isUnsupported`、`formal_review_source_coordinator.dart:108 completedSourceCount`、
`ai_cancel_token.dart:25 onCanceled`、`theme_provider.dart:32 currentTheme`、`srs_provider.dart:290 expressionTotalSeen`

同类还有 19 个（`lesson_viewmodel.dart` 占 5 个、`course_provider.dart` 2 个等），未逐一复核。

### B-4. `lib/core/extensions.dart` — 杂物抽屉

单文件塞 16 个 extension，**17 个死成员**（各自全库仅声明处 1 次）：
`isNotOkay:31`、`isOkay:36`、`getRandomString:68`、`toYMD:75`、`toFTS:79`、`toAPIFormat:81`、`toTimeOfDay:93`、`imgUrl:105`、`toHumanDate:123`、`toDDMMYYYY:133`、`toYYYYMMDD:142`、`removeSignature:156`、`getPageNumber:169`、`humanizeEstimatedTime:193`、`toFormattedTime:208`、`handleRouting:214`、`formatToHHMMSS:224`、`getEnumValue:233`

其中 6 个 extension 整体死（`RoutingHandler` / `EnumType` / `TimeOfDayExtension` / `RandomString` / `RemoveQueryParams` / `UrlPageExtractor`），已下钻到成员名级别二次验证。建议整文件单独立项。

---

## C 档：需人工确认

| # | 项 | 问题 |
|---|---|---|
| 1 | 10 个「仅被 test/ 引用」的 dart 文件（1,397 行） | 生产代码零引用但测试在用。最大的是 `lib/data/ai_companion_repository.dart`（779 行），删除会连带破坏 10 个测试文件 |
| 2 | `official_anki_import_orchestrator.dart` vs `unified_anki_import_orchestrator.dart` | 两套近似的导入编排实现并存，疑似历史双轨遗留，需判断是否合并 |
| 3 | `assets/sounds/turkish/listening/**`（9 个 mp3，12.37 MB） | **不进 App 包**（pubspec 目录声明不递归，已由 gen 产物证实）。仅 `tool/mix_listening_a1.py` 的输入。若不再生成听力节目可整体删 |
| 4 | `assets/images/app_logo_store_{1024,216}.png`（875 KB） | 代码零引用，疑为商店上架外部用图。建议移出 `assets/` |
| 5 | `import_sorter: ^4.6.0` | pubspec/analysis_options 中无配置节、无 import。若团队未在用可移除 |
| 6 | `json_annotation: ^4.9.0` | 0 处 import（`JsonKey` 由 `freezed_annotation` 转出）。移除后需跑 analyze + 全量测试验证 |
| 7 | `package:collection/` | 被 `routing.gr.dart` import 但未在 pubspec 声明（`depend_on_referenced_packages` 违规） |

---

## D 档：工程卫生（非死代码，但值得修）

### D-1. `debugPrint` 造成诊断盲区（110 处）

`lib/core/log_capture.dart:81` 只通过 `Logger.addLogListener` 挂载，**只能捕获 `logger.*` 事件**。110 处 `debugPrint` 全部绕开日志管线 —— 用户导出的诊断日志里看不到这些分支。项目自己在 `lib/core/result.dart:6` 就写明「Prefer this over scattering `try/catch + debugPrint`」，但没执行。

**建议优先迁移这 9 处**（本来就是临时调试，成功路径也在打）：
```
lib/views/settings/remote_backup_page.dart:182        SAVEANDTEST: store=... busy=... canSave=...
lib/application/anki_official/official_anki_internal_page.dart:146/162/204/219/230/233/855
lib/application/audio_controller.dart:305             TTS route: system OK
```
最脏的单文件：`lib/service/tts_availability_checker.dart`（23 处）、`audio_controller.dart`（10 处）、`anki_deck_manager.dart`（9 处）。

⚠️ 迁移 `ai_engine_config_holder.dart:186/215/243` 时注意别把 API key 值带进日志。
⚠️ `lib/core/log_capture.dart` 自己的 4 处 debugPrint **不能改**（会递归）。

### D-2. `.gitignore` 斜杠锚定漏洞 → 455 个 AI 工具状态文件进了版本库

`.gitignore:115-119` 的 5 条规则写作 `.mimosa/hook-state/`（含斜杠），被 Git 锚定到仓库根目录，**匹配不到 `tool/gui/.mimosa/`、`native/turna_anki_core/.mimosa/` 这类嵌套路径**。实测 `git check-ignore tool/gui/.mimosa/...` 未命中。

```
442 个  .mimosa/ 文件被 git 跟踪
 13 个  .zcode/plans/plan-sess_*.md 被跟踪（.gitignore 完全没有 .zcode 规则）
```

修复：改为 `**/.mimosa/**` 形式并补 `.zcode/`，然后 `git rm -r --cached` 清掉已跟踪的 455 个文件（合计约 325 KB，但污染提交历史）。

### D-3. `tool/gui/_capture_missing.py` — 唯一建议直接删的脚本

141 行，docstring 自述「只补两张截图」的一次性脚本，**已被 git 跟踪**，且硬编码了别人的主目录：
```python
ROOT    = Path("/home/whwen/documents/reso/Varnamalaplus/Varnamalaplus")   # :12
OUT_DIR = Path("/home/whwen/documents/reso/Varnamalaplus/TurnaWeb/docs/...")  # :17 输出到仓库外
```
同目录的 `_capture_screens.py:18` 已正确用 `__file__` 推导 ROOT —— 说明这本该改而没改。

### D-4. 本地磁盘垃圾

`__pycache__/` 56 个目录（tool/ + test/），已 gitignore、未跟踪，`find . -name __pycache__ -type d -exec rm -rf {} +` 即可。

---

## 复核说明（防止误删）

本报告所有「确定」级结论均经**双重验证**：先由扫描 agent 用词法统计定位，再由我用独立 grep 逐条复核引用计数。扫描中已识别并排除的假阳性类型：

- **extension 名天然只出现 1 次**（调用点不写 extension 名）→ 已下钻到成员名级别二次验证，7 个「看起来死」的 extension 经查为活，已排除
- **`CanonicalCard` vs `CanonicalCardKey`** 前缀误命中 → 按词边界区分
- **`manifest.json`** 在 lib/ 的 41 处命中全是同名 `legacy-manifest.json`
- **`runtime_memory_platform_stub.dart:1` 的 `() => null`** 看似死桩，实为 web 条件导入路径，**不可删**
- **条件 import 第二分支**（`import 'x.dart' if (dart.library.io) 'y.dart'`）会让 `y.dart` 被误判为孤儿 → 3 个 `*_platform_io.dart` 已确认为间接引用
- 大小写不敏感搜 `todo` 会命中 `toDouble()`（40 处误报）；搜 `/home/` 会命中 `views/home/`；搜 `temp` 会命中 `template`

**未覆盖**：`test/application/anki/` 等目录与已删除的 `lib/application/anki/` 对应，未逐一核对它们是否仍在测试已删类（若存在编译期 mock 则不会报错，属静默遗留），建议单独排查。
