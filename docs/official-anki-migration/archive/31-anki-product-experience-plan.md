# 31 — Anki 产品体验收口

> 文档代号：P-ANKI-UX  
> 日期：2026-08-20  
> 状态：**历史规格；勿按本文开施工波次。** OHOS Legacy 作废（[ADR 0041](../decisions/0041-ohos-product-eol.md)）；Official-first 是生产 bundle（`OfficialAnkiFeatureFlags.productionAndroid`），不是独立 dart-define。现行入口：[34](./34-official-anki-production-cutover-and-ohos-retirement-plan.md)（2026-08-24 接管）。  
> 前置：ADR [`0036`](../decisions/0036-official-anki-core-migration.md)、[`30`](./30-course-like-card-experience-plan.md)、[`29`](./archive/29-p5e-wave1-production-decoupling-report.md)（已归档）  
> 目标：先让 Android 生产导入稳定成功；再把路径收成「导入能看懂、复习像语言课、高级页不是实验室」。账本仍是官方 Collection / FSRS。

课化判定、kindsFor、练习链、课程写回的细规格以 [`30`](./30-course-like-card-experience-plan.md) 为准（Host / Unit 已过，生产默认未翻）。本文件管：**导入硬阻断、默认打开什么、用户看见什么、实验室入口怎么收**。

每一波可单独开 PR、单独测试、单独回滚。

---

## 0. 一句话

现在不是「体验差一点」，是 **Android 生产导入经常根本走不通**。先把卡稳定写进官方 Collection 并接上复习入口，再谈课化和首页。

---

## 1. 现状

### 1.1 已经对了（不要撤回）

- Android 新导入**意图**走官方 `rslib`（`CUTOVER` 默认 true，灰度默认 `g4`，导入/引擎 flag 默认开）。
- 正式复习能写官方 Scheduler（四档、Undo、Bury/Suspend）。Device A 上 fixture 评过分。
- 分类器与课化表面已有 Host/单测；投影 `algorithmVersion = 2`。
- P6 AnkiWeb 同步已取消。OHOS 仍 Legacy。

### 1.2 导入：能写库，不能当产品

Android 向导在 `_parseFile` 里若 `facade.isOfficial`，立刻 `importOfficialOrNull`，成功则 `_step = 4`。这不是「向导简化」，是半截入口。

| # | 事实 | 用户看到 |
|---|---|---|
| 1 | `AnkiImportFacade.resolve(officialImporter: CompositionRoot.session)`。启动只跑 `initializeReadOnlyLocator`，**不** `requireImporter`。Session 多半要先逛 Play Hub / Anki 复习页才会被 due sync 拉起。从课程管理直接导入 → `session == null` → `flag_fail_closed`，**不会退回 Legacy** | `解析失败：...`，退回选文件 |
| 2 | 官方成功也不写 `_summary`。完成页没有张数；「开始学习」读 `summary.importId`，等于空操作 | 绿勾，但像没导成 |
| 3 | 成功后 `OfficialAnkiNewImportCutover` **再用 Legacy `AnkiImporter.parse`** 拼课程树。`collection.anki21b` 会被 Legacy 拒绝 | Collection 里可能已有卡，向导仍报解析失败 |
| 4 | 「导入示例」走内存 `AnkiSampleDeck`，不经官方 `.apkg` | 不能当「真包能过」的证据 |
| 5 | 课程投影 / `COURSE_ENTRY` 默认关；复习 `_practiceMode` 默认 false | 即便导进，也不像语言课 |

对照「真正能导入」：

| | 现在 |
|---|---|
| 选文件把卡写入官方 Collection | **有条件可以**（worker 已在、且 cutover 二次 parse 没炸） |
| 向导显示张数并确认后才提交 | 没有 |
| 完成后能复习、due 对得上 | 不稳定 |
| 导入后像语言课 | 默认没有 |
| 任意现行 Anki 导出包 | 不保证（anki21b / session 空） |

HarmonyOS / 非 Android：走 Legacy，经典 `.apkg` 相对能用，没有官方 FSRS / 原卡渲染。

### 1.3 其它用户可见问题

| 路径 | 现状 |
|---|---|
| 正式复习 | 标题 `Official Review`，默认 WebView |
| 课化表面 | 手动切换；自绘卡，未接语言课 renderer |
| 首页 | 弱词 / 语法 / Anki / 词汇 SRS + 调试字 `Official Anki due: N` |
| 课程练习 | `courseGradesScheduler` 默认关：课上学过，Anki 里还是新卡 |
| 高级设置 | Spike 仅 debug；**内部导入** 条件是 `kDebugMode \|\| allowsOfficialImport`，release 也能进。subtitle 仍写「生产 flag 默认关闭」 |

### 1.4 和 `30` 的分工

`30`：怎么分类、投影、画卡、写回调度。  
`31`：导入先别断、默认翻哪几个、实验室入口藏哪、首页 due 怎么合成。

---

## 2. 铁律

1. 官方 Collection 是唯一 Anki 事实源。不恢复自研包解析 / 模板引擎 / Scheduler。
2. `lib/application/anki_official/` 禁止 import Legacy `application/anki` 或 `views/anki`（禁导测试）。
3. 复杂原卡走隔离 WebView。禁止用牌组 distractor 冒充选项。
4. 不对 WebView 做 3D `rotateY`。不对同一张卡双写官方 Scheduler 和 Turna `srs_states`。
5. 不把 canonicalLink 预览当正式评分。不实现 AnkiWeb。
6. 官方导入失败 **不得静默回退 Legacy**（会双账本）。但 **session 未就绪必须先 `requireImporter`，禁止用 null session 假装 flag 关闭**。
7. cutover 若仍需 Legacy parse 才能挂课程树，**不得让这一步把已经成功的官方导入显示成失败**；anki21b 走官方计数，不经 Legacy unzip。
8. OHOS 继续 Legacy。本计划首发 Android。

---

## 3. 完成态 / 明确不做

导入一副普通中英 Basic 牌组后应做到：

1. 冷启动、从未打开 Play Hub，从课程管理选文件也能导入（会拉起 worker）。
2. 先看到张数 / 是否覆盖，确认后再 `source.state == active`。
3. 出错是人话，停在选文件或预览，不是完成页，也不是 `解析失败：OfficialAnkiException`。
4. 完成页有张数，「去复习」能进到期队列。
5. 简单卡 Flutter 课面 + 四档；复杂卡 WebView + ACK。
6. 课程树能练（W3）。首页一个 Anki 数字，无调试字，无 Spike/内部导入。

不做：AnkiWeb、再克隆桌面 Reviewer、默认 3D 翻转、P5-E 删 Legacy、把 P5C/D4 演练做成用户功能。

---

## 4. 波次

禁止把导入打通、课化默认、实验室清理、课程写回揉进同一个 PR。

| 波次 | 名称 | 用户能感到什么 | 建议顺序 |
|---|---|---|---|
| **W2** | 导入打通 + 向导 | 真能导进去；有预览/确认/人话错误/去复习 | **第一刀（含硬阻断）** |
| W1 | 复习默认课化 | 单词牌默认 Flutter；保真卡仍 WebView；中文 chrome | 紧接 W2，可部分并行 |
| W0 | 实验室入口 | release 高级页没有 Spike/内部导入 | 可与 W2 同批，不可替代 W2 |
| W3 | 打开课程投影 | 导入后课程树出现语言课 | 依赖 W2 导入稳定、`30` B–D |
| W4 | 首页 due | 一个 Anki 数字，无调试字 | 依赖 W1 复习路径 |
| W6 | 接真 renderer | 翻面/TTS 与语言课同一套 | 可在 W1 后并行 |
| W5 | 课程写回调度 | 课上练完到期减少（默认关） | 最后，单独评审 |

**第一批：W2（必须含 §5.1 硬阻断）+ W1 + W0。** 没有 W2，课化和实验室清理都是空谈。W5 改 P3-051 语义，必须单独 flag。

---

## 5. W2 — 导入打通 + 向导

### 5.1 硬阻断（单独 PR 即可合，优先于向导美化）

`lib/views/anki/anki_import_screen.dart` `_parseFile`：

1. **先 `requireImporter`，再 resolve facade。** 禁止把可能为 null 的 `CompositionRoot.session` 传进去。`officialImporter == null` 不得映射成 `flag_fail_closed`。
2. 官方结果要填 `_summary`（张数、sourceId、importId）。完成页「开始学习 / 去复习」必须带得动 scope 或 ReviewGate。
3. `attachFromApp` 失败不得把已 active 的官方 source 显示成整次导入失败。要么官方挂树不依赖 Legacy parse，要么 anki21b 跳过 Legacy、只写 catalog + 复习入口，向导说明「已导入，课程树稍后生成」。
4. 示例牌组继续可用，文档/验收不得拿它当官方导入证据。

测试：

- session 初始为 null：选经典 Basic `.apkg` 仍能导入（本测试里会 spawn worker / fake）。
- 确认前（向导 PR）或至少本 PR：`source.state == active` 且完成页 `summary.cardCount > 0`。
- 从课程管理入口进向导（不先开 Play Hub）的 widget/集成测试，或明确的 facade 单测覆盖 null session。

完成定义：冷启动 Android，课程管理 → 选经典 `.apkg` → 完成页有张数 → 能打开正式复习。不依赖是否去过 Play Hub。

### 5.2 向导（可紧随 5.1）

不要把 Legacy notetype 编辑器套到官方 Collection 上。映射是 W3。这里只让用户做决定：

```text
Step 0  选文件
Step 1  官方 probe / 计数（可取消；不 commit）
Step 2  摘要：名、笔记/卡片/媒体、同源则「将更新」
Step 3  BottomSheet 确认 → Saga：打开 Collection → 导入 → 索引 → 挂入口
Step 4  完成：张数 + 去复习 + 留在这里
```

没有 cheap preview 时：允许打开包拿 counts、确认前不 commit。禁止为预览再写自研 unzip/sqlite。

人话错误（官方/Legacy 共用，改进 D 的"e.toString() 直接报错"已被本表覆盖；原文 `anki-import-usability.md` 已删除，git 历史可查）：

| 内部 | 给用户 |
|---|---|
| 取消 | 回 Step 0，不报错 |
| 扩展名不对 | 请选择 .apkg 或 .colpkg |
| 读失败 | 无法读取该文件 |
| 损坏 / 官方拒绝 | 文件已损坏或不是有效的 Anki 牌组 |
| anki21b 且课程树暂挂不上 | 已导入官方牌组；练习课稍后再生成（若走 5.1.3 降级） |
| 其它 | 导入失败，请重试 + 可展开详情 |

本波可带：入库确认（改进 C）、记住上次开关（改进 F）。  
不做：最近导入（B）、`?` 浮窗（E）。

### 5.3 改哪些文件

- `lib/views/anki/anki_import_screen.dart`
- `lib/application/anki_official/import/anki_import_facade.dart`（null importer ≠ flags off）
- `lib/application/anki_official/migration/official_anki_new_import_cutover.dart`
- `lib/application/anki_official/official_anki_composition.dart`（导入路径调用 `requireImporter`）
- `lib/l10n/app_strings.dart`
- 导入页 / facade / cutover 测试

---

## 6. W1 — 正式复习默认课化

到期复习不再默认 `Official Review` WebView。简单卡 Flutter；fidelity 才嵌官方 Reviewer。细规格 [`30` §8–§9](./30-course-like-card-experience-plan.md)。

本波最小：

1. 兼容卡默认课化（`_practiceMode` 默认 true，或按分类器自动选表面）。
2. AppBar / Show Answer / Bury 提示进 `AppStrings`。
3. 保真卡 ACK、Undo/Redo/Bury/Suspend 不回归。
4. 「切换原版 WebView」可留逃生，不当默认。

不要：接 `LessonViewModel`；用课程 intro 的 `showWord` 当复习卡；本波写回调度（W5）；本波换掉自绘 `PracticeReviewSurface`（W6）。

完成定义：Basic 词汇卡进 Anki 复习是 Flutter + 四档、无 WebView；脚本卡仍 WebView；无 `Official Review` / `Show Answer` 硬编码。入口仍是 `AnkiReviewRoute` → ReviewGate。

---

## 7. W0 — 实验室入口

高级设置不再当 Phase 0–4 验收台。

| 入口 | 动作 |
|---|---|
| Spike 设置项 | **删除。** `spike/` 代码可留供单测 / 换 `.so`，不进导航 |
| 内部导入设置项 | 仅 `kDebugMode` 或 `TURNA_OFFICIAL_ANKI_DIAGNOSTICS`。release 不可见 |
| 内部页导入/预览/正式复习 | debug 可留。删「复习入口尚未开放」 |
| P5C / D4 演练 | 仅 `migrationPilot` |
| 课程映射 / Legacy 迁移预览 | **不删能力。** W0 只藏；W3 把映射做成正式页 |
| Legacy 保真四项 | 文案标明「仅旧版 / HarmonyOS」。官方新源忽略 |

AGPL 已在 About 注册，不靠 Spike 页。

完成定义：release 高级页没有 Spike、没有内部导入；debug 仍能打开内部页；正式导入/复习不经过该页。

---

## 8. W3 — 打开课程投影

「导入 Anki」重新等于「多了一门课」。分类器已在；生产 flag 没开。

Android 默认翻 `TURNA_OFFICIAL_ANKI_PROJECTION` 与 `COURSE_ENTRY` 为 true。Basic 高置信自动确认。保真卡 `canonicalLink`，导入不失败。OHOS 保持关。

细规格 [`30` B–D](./30-course-like-card-experience-plan.md)。W3 主要是翻默认、导入完成后挂树、映射页可发现（完成页或中文来源管理），不再只藏 debug 内部页。

回滚用 flag，**不降** `algorithmVersion`。关 `COURSE_ENTRY` 仍能从 Anki 复习入口复习原卡。

---

## 9. W4 — 首页 due

只消灭 Anki 自己的双数字和调试字，不合并语法/弱词/课程 SRS。

1. 删除 Play Hub `Official Anki due: $officialDue` 与 `Key('official-anki-due')`。测试改断言磁贴聚合数字。
2. Badge 继续 `OfficialAnkiHomeDue.aggregatedAnkiDue`。点进 `AnkiReviewRoute`。
3. 0 due 磁贴仍在，避免丢掉导入入口。

用户不必知道 engine 名字。官方源 ReviewGate，Legacy 源旧 session。

---

## 10. W5 / W6（后置）

**W6** 在 W1 之后：`PracticeReviewSurface` 改 `lookupRenderer()`（`AnkiCardRenderer` / MCQ / FillBlank / ListenAndPick）。本波才接 TTS、减动画。复杂卡交叉淡入，不旋转 WebView。

**W5** 对齐 [`30` G](./30-course-like-card-experience-plan.md)：`COURSE_GRADES_SCHEDULER` 默认 false。介绍不写分；每 cardId 一课只写一次；客观错 → Again，全对 → Good。PR 前必须证明单卡 `answer` 是否必须在 due 队列里。官方 wordId 不得进自研 `srs_states`。未完成 W1/W3 不做。

---

## 11. 更后置（不挡第一批）

| 项 | 原因 |
|---|---|
| 最近 3 条导入、术语 `?` | 不修断裂路径 |
| 官方卡浏览器 / 每日上限 UI | 能复习就能学 |
| 后台导入 | 先分阶段进度 |
| Lite / 去解密 | 仅 Legacy/OHOS |

---

## 12. PR 切分

| PR | 波次 | 内容 | 依赖 |
|---|---|---|---|
| **PR-A** | W2 §5.1 | `requireImporter`；null session 可导入；填 `_summary`；cutover 失败不假失败 | 无，**先合** |
| PR-B | W2 §5.2 | 预览/确认/人话错误/去复习 | PR-A |
| PR0 | W0 | 设置去掉 Spike；内部导入 debug-only | 无 |
| PR1 | W1 | 复习默认课化 + 中文 chrome | 无（不依赖课程树） |
| PR5 | W3 | 翻 projection/courseEntry；映射入口中文 | PR-A（建议 PR-B 后） |
| PR6 | W4 | 删 Play Hub 调试 due | PR1 |
| PR7 | W6 | 接语言课 renderer + TTS | PR1 |
| PR8 | W5 | 课程写回，默认关 | PR5 + 单卡 answer 结论 |

每个 PR：

```bash
flutter test --no-pub test/application/anki_official/official_anki_forbidden_imports_test.dart
```

W2 加 facade / 导入页测试。W1 加「vocab 默认无 reviewer platform view」并回归 ACK。W3 跑 projection p3fix/p3r。W0：release 路径找不到内部导入标题。

---

## 13. 开关（本计划之后）

| 项 | 默认 |
|---|---|
| 复习课化（兼容卡） | Android true |
| `TURNA_OFFICIAL_ANKI_PROJECTION` / `COURSE_ENTRY` | Android true（W3） |
| `TURNA_OFFICIAL_ANKI_COURSE_GRADES_SCHEDULER` | **false** |
| `TURNA_OFFICIAL_ANKI_DIAGNOSTICS` | false |
| Spike 设置项 | 删除 |
| 内部导入设置项 | 仅 debug / diagnostics |

关课化 → 全员 WebView。关 `COURSE_ENTRY` → 课程树消失，复习仍在。不要降 `algorithmVersion`。

---

## 14. 验收

自动化（相关 PR）：

```bash
flutter test --no-pub test/application/anki_official/official_anki_forbidden_imports_test.dart
flutter test --no-pub test/application/anki_practice
flutter test --no-pub test/application/anki_official
flutter test --no-pub test/views/play/play_hub_screen_test.dart
```

手工（Android arm64，**不要用示例牌组当 W2 证据**）：

1. 杀进程冷启动 → 课程管理 → 选经典 Basic `.apkg`（未先开 Play Hub）→ 完成页有张数 → 去复习能看到卡。
2. 坏文件 / `.txt`：人话错误，不是完成页。
3. 到期简单卡：Flutter + 四档；Again 后面数变。脚本卡：WebView，无白屏。
4. release 高级页无 Spike/内部导入。
5. W3 后课程第一节不是网页。W4 后 Play Hub 无 `Official Anki due`。

---

## 15. 代码锚点

```text
lib/views/anki/anki_import_screen.dart
lib/application/anki_official/import/anki_import_facade.dart
lib/application/anki_official/official_anki_composition.dart   # requireImporter
lib/application/anki_official/migration/official_anki_new_import_cutover.dart
lib/views/anki_official/official_anki_review_page.dart
lib/views/settings/widgets/settings_advanced_section.dart
lib/views/play/play_hub_screen.dart
lib/application/anki_official/official_anki_feature_flags.dart
test/application/anki_official/official_anki_forbidden_imports_test.dart
```

---

## 16. 验收一句话

冷启动就能导入经典 `.apkg`，完成页有张数，简单卡按语言课复习；release 高级页没有实验室入口。示例牌组和内部页不算验收。Collection 与 FSRS 始终是官方的。
