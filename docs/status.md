# 状态（唯一真源）

> 本文件只回答一件事：**现在是什么样**。
>
> 不回答「为什么这么定」——那是 [`decisions/`](./decisions/) 的事；不回答「代码怎么分层」——那是 [`project-guide.md`](./project-guide.md) 的事；不回答「改代码该守什么」——那是 [`../AGENTS.md`](../AGENTS.md) 的事。
>
> **历史不在这里。** 每次施工的经过、真机收据原文、排查过程，一律在 git 历史（`git log -- docs/status.md`）与对应 ADR 里。本文件只保留**当前仍然成立的结论**。
>
> 改动本文件前先确认：写下的状态有可核验证据，且它没有过期。

---

## 1. 迁移总体口径

**记忆卡（Official Anki v2）验收通过**（在 [ADR 0044](./decisions/0044-anki-v2-revival.md) 真机强杀与大库矩阵闭环、Legacy v1 读写及旧表退役、[ADR 0057](./decisions/0057-card-adaptation-plan.md) 单一展示解析器与 [ADR 0067](./decisions/0067-memory-card-returns-to-course-domain.md) 回归课程域收口后即早就具备通过条件，现正式标为通过）。

- **生产底座唯一定型**：host 侧 R0–R8 一次性收口全绿；架构简化 P0–P4 落地（Legacy 读退役 / `course.db` v24 与 v27 删表 / 目录账本 18→5 收敛 / 备份互斥）；单一解析器 `OfficialCardPresentationResolver.resolveCard` 统一导入预览、课时派生与正式复习（[ADR 0057](./decisions/0057-card-adaptation-plan.md)）；牌组回归课程域呈现（[ADR 0067](./decisions/0067-memory-card-returns-to-course-domain.md)）。
- **主力平台**：**Android arm64 + iOS**，走同一条 Official 生产路径。
- **鸿蒙口径边界**（详见 §6）：不得把伴生版启用 Official Anki 混写为产品级「鸿蒙支持 Official Anki」（产品级已 EOL），也不得写「鸿蒙复习器做不出来」（真机首卡收据已证明 ArkUI `Web` 满足 CSP / 自定义 scheme / Range 206，见 [ADR 0050](./decisions/0050-ohos-official-anki.md)）。

---

## 2. 平台档位

档位由代码判定，不是文档口径：[`AnkiImportExecutionPlanner.productModeFor`](../lib/application/anki_official/import/anki_import_execution_plan.dart) 返回 `AnkiProductMode`。

| 平台 | 档位 | 前提 |
|---|---|---|
| Android | 官方档（枚举名 `officialAndroid`） | cutover flag 开启 |
| iOS | 官方档（同上，同一条生产路径） | cutover flag 开启 |
| 鸿蒙 | 官方档 | cutover flag 开启；接线步 0–5b 已施工（§6） |
| 其余（linux / windows / web / macos） | `ankiUnavailable` | 新导入与正式复习不可用；**不得创建 Legacy Anki 写者** |
| 全部平台 | `ankiUnavailable` | cutover flag 关闭时 |

`officialAndroid` 这个枚举名是 iOS 加入支持集之前留下的，改名要动全部调用点，无行为收益——保留原名，别当错号修。

---

## 3. 已验证能力（证据台账）

| 平台 / 形态 | 覆盖 | **未覆盖** |
|---|---|---|
| Android **真机** PLG110，**debug 构建** | 写侧链路：导入 → 账本 → 视图 → 删除收敛。硬性能：10 万卡 commit 3.5s、视图重建 2.8s、强杀零数据损伤 | ①生产 bundle 未验；②同夜 F6 阻断「进一个课时」，已修但**修后无真机复跑** |
| iOS **模拟器** iPhone 17 / iOS 26.5 | 真 .apkg 导入完成 + 复习器 Q→A 渲染 | ①非物理真机；②未覆盖升级安装 / 备份恢复 / 强杀恢复 |
| 鸿蒙 **真机** Mate 90 Pro Max / API 26 | 引擎、内存 SQLite、平台路由、降级拆除探针收据；首卡全链路（渲染 / 翻卡 / 评分落库 / 队列前进 / 强杀恢复） | 真机导入、课程学习解锁（§6） |
| 鸿蒙 **真机** CMM-AL10 / HarmonyOS 7.0.0.109 / API 26 | 二档评分按钮、评分落库（记住 → `ease=3`）、源徽章、工具栏启用谓词、完成交棒、连续过卡推进 | 遗留打磨项；步 6 CI 首跑收据 |

记忆卡（Official Anki v2）子系统整体已通过验收；上表保留各平台已取得的实测证据与设备边界，每次更新状态仍照实填写覆盖与未覆盖范围。

---

## 4. 仍未验收（Held）

> 注：记忆卡（Official Anki v2）及适配方案（[ADR 0057](./decisions/0057-card-adaptation-plan.md)）已通过验收，不再列为阻断项；以下仅为跨平台分发与非阻断工程余项。

- **iOS 物理真机与分发链路**：模拟器不替代物理真机 release 签名、干净/升级安装与 TestFlight 分发验证。
- **全应用级 release 真机巡检**：跨版本升级安装、迁移包与远程备份恢复的实机冒烟。

---

## 5. 工程决策收口（ADR 0073）

开放决策①②与记忆卡适配非阻断尾项均已收口（详见 [ADR 0073](./decisions/0073-anki-engine-lifecycle-and-shared-card-ownership.md)）：

- **① 引擎生命周期与确定性开库**：`ensureOfficialProfileOpen` 统一幂等打开 Collection（`collectionAlreadyOpen` 视作成功，瞬时 `schedulerBusy` / `collectionLocked` 短暂退避重试），已接入 `OfficialAnkiStartupRecovery`、`AnkiDeckManager`、需开库的 `OfficialAnkiMaintenanceRunner` 任务及 `OfficialAnkiV2LessonContent`；同时保留按需懒开前提。`OfficialAnkiAdaptationStore.deleteSourceNamespace` 改为返回 `bool` 汇总删除结果，并由 `OfficialAnkiV2RetireService.runRetireJob` 步骤 ③ 补偿清理延迟留下的适配命名空间。
- **② 共享 Collection 所有权与分层抽样**：`OfficialAnkiImportLog.importedOrSharedNoteIds` 显式排除 `conflictingNoteIds`，避免冲突笔记落入 `anki_source_cards`；`updatedNoteCount` 与 `conflictingNoteCount` 经 `OfficialAnkiV2CommitResult` / `AnkiImportSummary` 展示在导入完成页；`OfficialAnkiV2RetireService.runRetireJob` 步骤 ② 经 `OfficialAnkiSourceDao.retainingSharedCardIds` 保护仍在使用的兄弟来源共享卡；替换重导路径通过 `AnkiDeckManager.uninstall(..., awaitEnginePass: true)` 等待旧源删卡完成再提交新包；`AdaptationInputBuilder` 保持 Rust C ABI 不变，在全部 `schema.samples` 上统计媒体分布并做 Dart 侧确定性分层抽样。
- **视图提示列与仓储接口收口**：`anki_course_tree_view.presentation_kind`、相关漂移诊断（`OfficialCardPresentationResolver` / `PresentationReason`）已随 `CourseDatabase` 升级移除；Official v2 与导入链路已接入 `IOfficialAnkiV2ViewStore` / `IAnkiUnificationStore`。限制③（双代并存）此前已随 v1 整体退役消解。

---

## 6. 鸿蒙三层口径

三层不要混用。「鸿蒙」这个词在不同层指的不是一回事。

| 层 | 事实 | 真源 |
|---|---|---|
| **产品级** | 已 EOL。伴生版不进主交付、不进主 CI | [ADR 0050](./decisions/0050-ohos-official-anki.md)（原 ADR 0041 已删，口径见 ADR 0047 与 ADR 0050） |
| **伴生版** | 存在但受限：课程 / SRS / 复习 / 词典 / 设置 / 备份 + 自维护 ArkTS 通道；**不含 AI 生成**（华为审核合规移除，[ADR 0056](./decisions/0056-ohos-remove-ai-compliance.md)）；**不含跟读识别**（readAloud 题型降级为听示范卡，[ADR 0061](./decisions/0061-read-aloud-word-matching.md)） | [ADR 0047](./decisions/0047-ohos-companion-lite-build.md) |
| **Official Anki** | 已授权；接线步 0–5b 已施工 | [ADR 0050](./decisions/0050-ohos-official-anki.md) |

### 已成立

- `productModeFor('ohos')` → 官方档。能力矩阵已把鸿蒙路由到官方档，**不再是 `ankiUnavailable`**。
- ArkTS 编译器收据已取得：`flutter build hap --debug` 产出 signed hap，0 ERROR。
- 复习评分档为**二档**（忘记 / 记住），只发 `again` / `good`，与安卓 `BinaryRecallBar` 同语义；协议层四个 rating 词保留。
- 顶栏只剩 `X` + 进度 + 源徽章。
- 入口白屏已收口，真机通过：预热整体撤除，首卡由 `OfficialAnkiReviewerStage.attach` 在 Flutter 仍在前台时 present。

### 不要复刻旧实现

预热（`warmUp`）、顶栏四键（撤销 / 重做 / 搁置 / 暂停）、`requestCardAction` / `requestUndo` 协议方法、debug 启动自拉的全屏能力探针——**这些曾实现，后来移除**。要加回去之前，先看 git 历史里它们为什么被移除。

当前顶栏只有 `X` + 进度 + 源徽章。入口白屏的根因是预热本身：预热会把 ability 全屏拉起，而批次尚未就绪、Stage 尚未 mount，原生页只渲染出空壳。首卡现由 `OfficialAnkiReviewerStage.attach` 在 Flutter 仍在前台时 present。

### 仍 Held

- **步 6 独立 CI 首跑收据**：workflow 已落库（`ohos_ci.yml` + `tool/ohos_ci_prepare.py`，无签名 hap 冒烟），首跑需先配 `DEVECO_CMDLINE_TOOLS_URL` 仓库变量。
- **用户流余项**：真机导入、课程学习解锁。

### 平台纪律

- 平台判断一律走 `isHarmonyOsTarget`（`lib/core/ohos_target.dart`），**不得内联 `Platform.is*` 比较**——鸿蒙上 `Platform.is*` 全为 false。
- `lib/` 里不得出现 `Ohos*` 标识符（`OhosView` / `OhosViewController` / `initOhosView` 等）。它们只存在于 OHOS fork SDK，官方 SDK 下是 `undefined_class`，而 `dependency_overrides` 无平台条件。
- `sqlite3` 包没有鸿蒙平台枚举值，可用入口只有 `overrideForAll()`——不是加一行 override。

---

## 7. 课程内容更新

**当前内置课程**：`tr` 由 [`assets/courses/manifest.json`](../assets/courses/manifest.json) 指向 `assets/courses/nouveau-turkish/`。旧 `turkish/` 已迁为 `test/fixtures/turkish_course/`，不再随 app 打包。第 1 章包含第 0 单元「认识土耳其语」（1 门无判分 `guide` 课、6 页，见 [ADR 0074](./decisions/0074-ungraded-guide-lessons.md)）与首单元候选内容（24 课、27 个可玩节点），共 2 个单元、25 课、17 个词和 4 个固定表达；第 2–8 章只有真实主题/等级规划，仍为 `units: []`。实际指标以 [`content_inventory_current.md`](./content_inventory_current.md) 为准，课程地图见 [`authoring/nouveau-turkish-course-map.md`](./authoring/nouveau-turkish-course-map.md)。**12 条真实听力音频、人工语言审校、移动真机与学习效果验收尚未完成。**

**对话与复习课能力**：`dialogue` 模板复用角色轮次、逐句 TTS 与既有判分管线；首单元现有 3 个对话课候选。平铺复习课 `reviewPolicy` 已用于正式候选复习池：18 题，抽取 15–16 题。见 [ADR 0070](./decisions/0070-scenario-dialogue-lessons.md) 与 [ADR 0071](./decisions/0071-review-question-pool.md)。

**作者与发布契约**：题型结构、Phase Two 配方、资源元数据、替代答案、阅读词形和作者工作区已统一；GUI「定稿」不分配 OTA 版本，媒体随 app、课程 ZIP 仅 JSON。决策见 [ADR 0072](./decisions/0072-phase-two-authoring-and-release-contract.md)。

**子课播放粒度**：多子课的课在课程树上按子课拆为独立节点，每节点一次独立会话、独立发奖（课级完成走结算门）；数据格式不变，`lessons` 表 v34 起携带 L1 子课摘要列。见 [ADR 0064](./decisions/0064-sub-lesson-tree-nodes-and-sessions.md)。

本地内容读取接缝已接线：`CourseContentSource`、`DatabaseSeeder` 和 `CourseProvider.refreshBuiltinContent` 支持整套选源、版本比较、损坏更新回落、事务重播种与缓存刷新；决策见 [ADR 0058](./decisions/0058-builtin-course-content-source.md)。`tool/publish_course.py` 已实现本地快照校验、升版、zip 与 feed 生成、SHA-256 和历史清单，并已实际生成首包；`check_builtin_version` 拒绝低于内置的版本、对同版包给 stderr 警告（接缝同版选内置 assets），发布契约见 [ADR 0059](./decisions/0059-course-release-feed.md)。`CourseOtaService` 已实现 feed/zip 下载、相对 URL 解析、传输策略、SHA-256/大小校验、JSON-only zip-slip 防护、整包课程校验、版本拒绝及可恢复的原子目录切换；服务层测试覆盖失败保留旧内容与中断恢复。学习设置页的 `SettingsCourseUpdateTile` 已接入手动 URL 更新、进度/错误反馈和 `CourseProvider.refreshBuiltinContent`；下载成功但应用被学习／备份门控拦截时可免重下重试。`SettingsCourseRestoreTile` 通过 `CourseOtaService.clearInstalledContent` 删除已下载目录（含 backup 与 tmp）并重播种回内置内容，随后写 `contentVersionAcknowledged`，避免降级重弹版本升级确认提示（原 ADR 0002，已随文档精简删除）。内存 DB 全链路已验证 HTTP 安装 → 重播种 → 课程树显示新内容，以及清除后回落内置内容。**尚未完成云端热更新日常闭环**：远端托管发布与真机验收仍待实现；本地覆盖、恢复入口与进度提示也尚无真机验收证据。

---

## 8. 设计翻新

全 App「湿地雾光」逐页重设计（计划见 [`app-design-refresh-plan.md`](./app-design-refresh-plan.md)）已完成 **S0–S7 全部代码与资产重构**（规则定稿见 [ADR 0075](./decisions/0075-uniform-4px-geometry-and-bauhaus-icons.md)）：

- **统一 4px 几何体系**：`lib/core/theme.dart` 收口为唯一矩形圆角令牌 `TurnaTheme.radius`（4px，保留 `cardRadius` 别名），旧圆角阶梯全部移除；四套主题（浅色 / 深色 / 高对比浅 / 高对比深）的按钮、输入框、分段控件、标签、对话框、底部弹层（顶两角 4px）、SnackBar 与全局 `TurnaSwitch` / `TurnaSlider`（`lib/views/widgets/turna_controls.dart`）统一为 4px，真圆形元素改用 `BoxShape.circle`，设置域局部方形覆写并入全局。
- **包豪斯几何 SVG 图标族**：在 `assets/icons/` 落地全套 24×24 包豪斯几何 SVG（静态校验全通过），经纯 Dart 枚举 `TurnaIconId`（`lib/core/turna_icon_id.dart`）与 `TurnaIcon`（`lib/views/widgets/turna_icon.dart`）全量替换全 `lib/` 中的 Material `Icons.*`，并剥离 `domain/cosmetics/` 与 `application/settings/settings_destination.dart` 中的 `IconData` 依赖。
- **共享骨架与 R01–R18 逐页收口**：落地 `TurnaTopBar`、`TurnaLoader`（三档几何加载器，遵守 `reducedMotion`）、`TurnaDialogPanel` / `showTurnaConfirmDialog` / `showTurnaInfoDialog` / `showTurnaFormDialog`、4px `TurnaSnackBar` 与 `TurnaReadingLayout`；完成 R01 外壳与启动、R02 课程树、R03 课程管理书架式重做、R04–R06 课时与全题型（含 B11 键盘避让与完成/重试弹层统一）、R07 练习台与信息浮层、R08–R10 复习与错题报告、R11 词典（含宽屏并排）、R12–R13 记忆卡导入步骤工作区 / 复习主卡与修复中心、R14 AI 卡面收敛与教材导入、R15 个人 / 成就与包豪斯分享海报、R16–R18 设置 / 存储诊断（B5）/ 备份弹层与说明页阅读合并（B9）。
- **品牌资产重绘（P6）**：`TurnaGeometry` 补齐 `brokenStreak` 几何熄火构图并退役 `assets/images/offFire.png`；重绘湿地雾光包豪斯版 `app_logo.png`（含 `store_1024` / `store_216`）与 `turna_reading.png` / `turna_waving.png`，同步 Android / iOS / Web / macOS / OHOS 启动器图标并通过 `sync_ohos_icons_test.py`。
- **架构门禁棘轮**：`test/architecture/code_conventions_guard_test.dart` 新增统一 4px 几何、零 Material `Icons.*`、共享 `TurnaTopBar` / `TurnaSheet` / `TurnaDialogPanel` / `TurnaLoader` 及禁裸黑白色的强制断言。

**材质第三轮（[ADR 0068](./decisions/0068-ambient-light-and-frosted-glass.md)）**：L0「白 + 三片极淡天光」（`AmbientLight`，峰值 ≤8.6%，只落边缘）与 `GlassLevel.l2Frost`（每页 ≤2 张）继续生效；个人页头卡保持静态淡彩玻璃，L0 天光保持静态。

**ADR 0067 记忆卡回归课程域已落地**（数据 / 引擎层零改动）：记忆卡牌组以课程形态进入课程管理书架索引，练习台与个人页按当前课程裁剪，第三方卡片内容区保真契约保持不变。

**验收边界**：本轮已在离线环境下完成全量 SVG 静态校验、OHOS 图标同步单测、`dart format` 全文件语法校验与全库静态门禁扫描；云端环境因 `gitcode.com` 对 OHOS 依赖返回 HTTP 418 无法在线运行 `flutter pub get` / `flutter test` / Golden 重录，需要在本机或 CI 环境执行 `flutter analyze`、`flutter test --exclude-tags golden`、`flutter test --update-goldens test/golden/` 以及 Android / iOS / 鸿蒙真机视觉、宽屏、屏幕阅读器与帧耗时验收。

---

## 9. 维护规则

1. 本文件**只增结论，不增流水**。一轮施工做完，把结论改写成一两行状态，不要追加一段施工经过。
2. 状态变了就**改写**对应条目，不要在旁边加一句「其实……」——那正是本文件要消灭的写法。
3. 撤销一个结论就**删掉它**，不要在旁边留一句"其实……"。要查历史去 git。
4. 每条状态要么指向 ADR，要么指向代码或测试；指向会被改写的源码时用符号名，不写行号。
5. 测试数、版本号、文件清单这类会漂的数字**不写这里**，现场查。
