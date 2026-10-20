# Turna — Agent 规范

> 本文件是**行为规范**，不是项目介绍。架构 / 功能 / 教学法叙述一律见 [`docs/project-guide.md`](./docs/project-guide.md)；本文件只回答「改什么落在哪、必须怎么做、绝对不许怎么做、谁来强制、怎么验证」。
>
> 本文件是根级 Agent 指令的**唯一真源**。内容按**实际工作流**排序：先定位落点 → 再看约束 → 最后跑门禁。

## 0. 冲突裁决

按序覆盖，下位不得推翻上位：

1. **门禁测试**（`test/architecture/` 与各 `*_test.dart`）—— 规范的可执行形式，最高
2. 本文件的禁则清单
3. Official Anki 状态口径 —— 只认 [`34-cutover-receipt.md`](./docs/official-anki-migration/34-cutover-receipt.md)
4. `docs/project-guide.md` 的架构与设计叙述
5. `docs/decisions/` ADR —— 只提供决策理由，不覆盖以上

事实性数字（schemaVersion、版本号、测试计数、目录清单条数）**一律现场查证，不写死在本文件**；写死即腐坏点。目录与文件**路径**是稳定事实，可直接引用。

---

## 1. 落点地图

### 1.1 各层职责与依赖方向

`lib/` 按依赖方向单向流动，箭头方向**只能从上往下**：

| 层 | 职责 | 不得做 |
|---|---|---|
| `lib/views/` | 页面与组件，只做渲染与交互 | 不得触碰 `lib/data/` |
| `lib/application/` | 门面：编排 domain 契约与仓储接口，承载用例 | 不得 import `lib/data/` |
| `lib/domain/` | 实体、状态模型、仓储**接口** | 不得反向依赖 `application` / `data` |
| `lib/data/` | Drift 库、DAO、仓储实现 | 不对 `views` / `application` 暴露 |
| `lib/core/` | 跨层公共设施：主题、日志、SRS、文案处理 | 不得依赖 `views` |
| `lib/courses/` | 课程内容加载、校验、查表 | 不持有 UI 状态 |
| `lib/service/` | 平台与生命周期服务：启动、导出、远端备份 | 不得依赖 `views` |
| `lib/di/` | get_it 装配（**豁免**跨层禁则） | 装配代码集中于此 |
| `lib/routing/` | auto_route 路由表与守卫 | 不放业务逻辑 |

### 1.2 改什么 → 动哪里

| 要做的事 | 落点 | 附带动作 |
|---|---|---|
| 加 / 改页面 | `lib/views/<feature>/` | 私有组件进 `views/<feature>/components/`；跨功能才进 `views/widgets/` |
| 加业务用例 | `lib/application/<area>/` | 编排 `domain/` 契约，不直接调 DAO |
| 加领域模型 | `lib/domain/<area>/` | 用 freezed，改完 `make gen` |
| 加持久化 | `lib/domain/repositories/i_*.dart` 声明接口 + `lib/data/` 实现 | 调用方只认接口 |
| 动 SRS 行为 | `lib/core/fsrs_*.dart` | 与 `fsrs` 包逐公式镜像，升级包须同步核对 |
| 加路由 | `lib/routing/routing.dart` 挂 `@RoutePage` | 改完 `make gen` |
| 加依赖 | 目标类上加 `@injectable` 系列注解 | 改完 `make gen` |
| 动课程内容格式 | `lib/courses/` + `assets/courses/` | 改后跑 `lib/courses/course_validator.dart` |
| 动 LLM 能力 | `lib/application/ai/engine/` | 页面不得直连任何 LLM SDK |
| 动桌面创作者工具 | `tool/gui/` | 独立 Python 工程，有独立门禁，见 §7 |

### 1.3 一个真实依赖链（形状参照）

以 `lib/views/review/unified_review_page.dart` 为例，它同时跨 6 个区：

```
views/review/unified_review_page.dart
├─ application/review/review_session_controller.dart      编排
├─ application/study_session/session_settlement_service.dart  结算
├─ domain/review/{review_item, review_ledger, recall_outcome}.dart  契约
├─ core/{theme, logger, html_stripper}.dart               公共设施
├─ views/review/components/*                              子组件
└─ di/injection.dart                                      装配
```

**页面永远不 import `lib/data/`** —— 上例中没有任何 DAO / 数据库句柄，就是这条规则的形状。

---

## 2. 硬约束：分层导入

由 `test/architecture/layering_guard_test.dart` 逐文件强制；失败即层边界已破。

| 方向 | 判定 |
|---|---|
| `views → data` | **禁止**，经 application 服务或 domain 仓库接口 |
| `application` / `domain` / `core` / `service` → `views` | **禁止**（`di/` 装配模块豁免） |
| `domain → application` / `domain → data` | **禁止**；需要能力就在 domain 抽接口（如 `SrsSchedulingGateway`） |
| `application → data` | **硬禁止**；DAO / Repository 一律经 `domain/repositories/` 消费（接口清单以该目录为准） |
| 共享词汇（主题 token、状态模型、结果枚举） | 放 `core` 或 `domain`，**不放页面文件** |

`application → data` 的三类豁免（Drift 句柄传递 / 原生 SQL 事务 / `CourseDatabase` 本地句柄构造）走逐文件白名单。**白名单是双向校验的**：既拦未授权导入，也报「已豁免但不再导入，去删豁免项」——因此豁免项不会悄悄变宽，豁免的增删规程见该测试文件本身。

## 3. Dart 语言层既定选型

`.agents/skills/` 已装通用 Dart / Flutter 规范（Effective Dart、records / patterns、sealed class、widget test 等），**通用最佳实践不再抄进本文件**；本节只记 skills 无法推知的本仓库既定选择。每条均可用 `grep` 在 `lib/` 验证，改选型时先更新本节。

| 主题 | 既定选型 | 不得写成 |
|---|---|---|
| 状态与结果建模 | `sealed class` + pattern matching / switch 表达式 | enum + if 链、`base class` 继承树 |
| 多返回值 | record `(a, b)` | 一次性 DTO / `Map<String, dynamic>` |
| 领域模型 | freezed + `part`，改动后 `make gen` | 手写 `==` / `copyWith` / `toJson` |
| 依赖注入 | injectable 注解 + get_it | 手写 `GetIt.register*` 装配 |
| 路由 | auto_route 注解（`@RoutePage` / `@AutoRouterConfig`） | 手写 `MaterialPageRoute` |
| 具名工具类 | `abstract final class`（禁继承、禁实例化） | 可实例化 class 承载静态方法 |

analyzer 已强制的部分（`analysis_options.yaml`：`strict-casts`、`avoid_print`、`cancel_subscriptions`、`close_sinks`、`unawaited_futures`、`prefer_const_declarations`）不重复写入本文件，改 lint 配置即改约束。

## 4. 日志与错误处理

- 统一用 `core/logger.dart` 的 `logger`（`t/d/i/w/f`）；**禁 `print`**（analyzer `avoid_print` 强制）、**禁 `debugPrint`**（仅自觉）。`log_capture.dart` 内部防递归的若干处 `debugPrint` 是唯一例外。
  - 理由：logger 进入用户可导出的透明度日志，release 有等级过滤；`debugPrint` 两者皆无。
- 需要堆栈：`logger.w('...', error: e, stackTrace: st)`。
- **空 catch 必须有一行注释说明为何安全**。可静默 catch 仅限两类：GetIt 可选依赖守卫、best-effort 清理；其余操作型失败（写入 / 统计 / 诊断）至少补 `logger.w`。
- 错误通道：可恢复加载失败走 Provider 状态机（如 `SectionLoadState.error`），一次性动作用 SnackBar。
- **不引入全局错误弹窗**；`core/result.dart` 的 `Result` 供 repository 接缝渐进采用。

## 5. 状态选型与命名

- UI 局部状态 → `setState`；跨 widget 共享 → `provider`（`ChangeNotifier` + `context.watch/read`）；无 UI 依赖的服务 / 仓库 → `get_it`（injectable 注解）。
- 页面里**不得直接 `getIt<DataLayerType>()`**；数据访问走 repository 接口或 application 门面。
- 页面文件统一 `*_page.dart`，**新代码不得新增 `_screen.dart`**；存量 `_screen.dart` 改名牵连路由与测试，按渐进迁移处理，**不与本规则相关的功能改动不得顺手改名**。
- 组件目录：跨功能共享 → `lib/views/widgets/`；功能域私有 → `<feature>/components/`。**新功能域统一 `components/`**，不再新建 `*/widgets/`。
- 全应用 LLM 出入口唯一：`lib/application/ai/engine/`；页面不得直连其他 LLM SDK。

## 6. 数据与算法

- SQL `LIKE` 统一走 `lib/data/sql_like.dart`：用户 / 外部输入经 `escapeLikePattern()` 转义 `%` `_` `\`；drift 侧用 `LikeEscaped` 或 `containsLike()` / `prefixLike()`。**不新增裸 `.like()` 或手写 LIKE**（纯常量前缀豁免）。
- `lib/core/fsrs_optimizer.dart` 与 `fsrs` 包**逐公式镜像**（难度阻尼、召回稳定度、lapse 取 min、0.9 曲线锚定均为包行为）。**升级 fsrs 包必须同步核对模型公式**，否则本地拟合权重与调度口径漂移。
- 调色板真源 `lib/core/theme.dart` ↔ `tool/gui/src/theme_tokens.py`；不得新造 `peacock*` 别名，不得在页面内写裸品牌色常量。

## 7. 范围与口径（禁语清单）

- 不做无外部来源的功能声明。**鸿蒙口径分三层，别混用**（详见 §7.1）。
- `tool/gui` 是仓库内创作者桌面工具，**不进 app 本体**（ADR 0032）；它有独立门禁，见 §8。

### 7.1 鸿蒙三层口径（写文档 / 写代码 / 做决策前必读）

| 层 | 事实 | 真源 |
|---|---|---|
| **产品级** | 已 EOL。伴生版不进主交付、不进主 CI | [ADR 0041](./docs/decisions/0041-ohos-product-eol.md) |
| **伴生版** | 存在但受限：课程 / SRS / 复习 / 词典 / 设置 / 备份 + 自维护 ArkTS 通道 | [ADR 0047](./docs/decisions/0047-ohos-companion-lite-build.md) |
| **Official Anki** | **已授权；接线步 0–5b 已施工**。步 0–4（2026-10-08）：引擎 / 内存 SQLite / 平台路由 / 降级拆除真机探针收据，`degradations` 只剩 `remoteBackup`。2026-10-13 补修真实 catalog 冷启动、RDB 事务和正式复习回执。**2026-10-14 夜步 5b 完成并取得真机首卡收据**（Mate 90 Pro Max：渲染 / 翻卡 / 评分落库 / 队列前进 / 强杀恢复全链路走通；八处接线缺陷已修，见 ADR 0050 §3.7）。步 6 独立 CI workflow 已于 2026-10-15 落库（无签名 hap 冒烟，`ohos_ci.yml` + `tool/ohos_ci_prepare.py`），**首跑收据待取**（需配 `DEVECO_CMDLINE_TOOLS_URL` 仓库变量）。**2026-10-16 三批缺陷修复施工完毕**（堵死锁 B1–B8 / 流畅度 P1–P5 / 产品化 UI，含返回语义、推进异常防护、会话清理、媒体逐出、消除双渲染、原生产品级 UI；本地门禁全绿，计数以 `test/BASELINE.md` 当日条为准）。**2026-10-17 协议与对等性批次已施工**（R0 双侧协议单一来源 + 对称守卫；R1 探针迁入 `ets/probe/`；预览模式 / JS 禁用 / 卡片字号 / 手动音频重播与 `avHint` / 能力矩阵五项对等；O1 `> 256 KB` 大媒体绕 Base64 走原生 Range 直读；R2 拆出 `AnkiReviewerChrome.ets`；T1 跨语言媒体路径向量与绑定边界单测。hap 构建转绿——**编译器收据，不是真机收据**）。**2026-10-18 评分档对齐安卓**：正式复习由四档（重来 / 困难 / 良好 / 简单）改为与安卓 `BinaryRecallBar` 一致的二档（忘记 / 记住），只发 `again` / `good`；协议层四个 rating 词保留；**真机过卡未验**。**2026-10-18 入口与工具栏批次已施工**（D1 错误出口 / P1-3 媒体单次 IO 与有界并发 / P1-4 暖帧 / P0-1 预热 + `closeReviewer` / P0-2 首屏窗口 8 / D8 工具栏 redo·bury·suspend，后者新增单个 `requestCardAction` 协议方法，回执复用既有词表；本地门禁全绿，计数以 `test/BASELINE.md` 当日条为准）。仍 Held：用户流余项（真机导入、课程学习解锁）；真机复验收据（评分互斥 + 三批验收矩阵：返回手势两态 / 异常注入 / 连续两轮进复习 / 大卡翻面时序；2026-10-17 五项对等性与大媒体直读；2026-10-18 二档落库与按钮形态、预热与首屏窗口的真实时延、工具栏三键的调度效果）。2026-10-18 晚 **UI-15 与编译器收据**：复习面四项形态差异**全部对齐**（Review All 源徽章 / 四档主题含高对比度 / 工具栏启用判定改按 `canRedo`·`canMutate` / UI-16 单源会话完成即交棒给 Flutter 的 `UnifiedReviewCompletion`，原生行只做 600 ms 收尾）；**ArkTS 编译器收据已取得**（`flutter build hap --debug` 产出 signed hap，0 ERROR；此前记的「hvigor 配置漂移」是**错误归因**，真正拦路的是 `SAFE_DELETE_BULK_CONFIRM_REQUIRED`，构建前清两个缓存目录即可，见 34 收据同节）；**2026-10-18 夜真机复验（CMM-AL10 / HarmonyOS 7.0.0.109 / API 26）**：二档按钮、评分落库（`记住→ease=3`）、源徽章、三键 `enabled` 谓词、完成交棒到 `UnifiedReviewCompletion` 均有收据；**但复习主链断在推进**——评分后抛 `advance_failed`，其连锁是 `card_mismatch`（`scheduling_context_stale`），连续过卡不可用；同批修了主题首批时序、预热 deadline、三键可用性配色，并给推进失败加了结构化日志。**因此 2026-10-14 的「队列前进走通」只对四档时代那次会话成立。** 2026-10-18 深夜**推进已修通**：根因不是推进逻辑，而是**复习器作为独立 ability 盖住 Flutter 页面时 Flutter 不产帧**——`setState` 只标脏不重建，于是新卡没人装、没人 present。修法：`OfficialAnkiOhosReviewerBinding.presentInPlace(cardId)` 原地 `loadAndShowQuestion` + present，成功后补一条 `acceptPresentation(question)`（卡片 body 仍持上一张的 presentation，它的回执会被 cardKey 守卫拒掉）；评分与三键（redo/bury/suspend）都接上。真机连评 6 张（记住 ×4 / 忘记 ×1 / 搁置 ×1），进度 `1/8 → 2/9 → 3/11 → 6/16`，**0 次** `rating_stalled`/`advance_failed`；`again` 首次取证（`ease=1 ivl=-60`）。同一根因也解释了「20 s / 60 s 首卡」——是等一帧，不是装配慢。**2026-10-19 入口白屏收口**：预热本身是入口白屏的根因——`_startOfficialOwned` 先 `warmUp` 就把 ability 全屏拉起，而批次还没就绪、Stage 还没 mount，于是原生页只渲染「显示答案」空壳，点击无回执（Dart 侧 `_controller == null` 直接 return），只能靠 60 s idle deadline 自己好。**已整体撤除预热**（页面不再 `warmUp`，首卡由 `OfficialAnkiReviewerStage.attach` 在 Flutter 仍在前台时 present）；**顶栏四键（撤销 / 重做 / 搁置 / 暂停）与 `requestCardAction` / `requestUndo` 协议一并撤除**（四键与二档产品口径不符）；**debug 启动不再拉起全屏能力探针**（探针代码仍在 `ets/probe/`，不再自启，也不再播音频/语音探针）。**真机通过**（2026-10-19 01:45–02:12，截图链 `s1` 探针页 → `s2` 白屏复现 → `n1` 首卡 1/8 正常渲染 → `p1` 翻面二档 → `p2` / `q2` 推进到 2/10，两会话复现；顶栏只剩 `X` + 进度 + 源徽章）。**注意**：上文 2026-10-18 的「P0-1 预热」与「D8 工具栏 redo·bury·suspend」两条**已作废**，只作历史。`productModeFor('ohos')` → 官方档 | [34 收据](./docs/official-anki-migration/34-cutover-receipt.md)「鸿蒙步 5b 真机首卡收据」「鸿蒙评分回执与按钮互斥修复」「鸿蒙复习页缺陷与优化三批施工」「鸿蒙步 6 独立 CI workflow 施工」「鸿蒙复习链路协议门禁、探针隔离、5 项功能对等性补齐与 O1/R2/T1 施工（2026-10-17）」「鸿蒙评分档对齐安卓（2026-10-18）」「鸿蒙复习面 UI-15 / UI-16 对齐与 ArkTS 编译器收据（2026-10-18 晚）」「鸿蒙复习页白屏修复与顶栏精简（2026-10-19）」；[ADR 0050](./docs/decisions/0050-ohos-official-anki.md) §3.6–§3.7 |

**因此**：❌ 不得写「鸿蒙支持 Official Anki」（完整用户流中真机导入与课程学习解锁仍无收据、步 6 CI 首跑收据未取、伴生版不进主交付——「支持」是产品级断言，余项未清前不成立）；❌ 也不得反向写「鸿蒙复习器做不出来」——2026-10-14 已用真机收据证明 ArkUI `Web` 满足 CSP / 自定义 scheme / Range/206，且当夜复习链路（渲染 / 翻卡 / 评分落库 / 队列前进）已在真机走通；✅ 可写「已授权，步 0–5b 已施工，复习链路有真机首卡收据（2026-10-14 夜）；2026-10-16 评分回执与三批修复、2026-10-17 协议与对等性/O1/R2/T1、2026-10-18 二档对齐与入口/工具栏批次已施工（其中 **P0-1 预热与 D8 工具栏三键已于 2026-10-19 撤除**）、2026-10-19 入口白屏修复（撤除预热）与顶栏精简（撤除四键）已施工并**真机通过**；真机导入与课程学习解锁等用户流余项、遗留打磨项与步 6 CI 首跑收据待取（workflow 已于 2026-10-15 落库）」——能力矩阵已把鸿蒙路由到官方档，**不再是 `ankiUnavailable`**。

**三个已知的失真点**（本节之前它们还在文档里）：

1. 「仓库不含 `ohos/`」——ADR 0047 之后为假。
2. 「鸿蒙没有 libsqlite3.so 所以引擎打不开」——因果错了，引擎的 SQLite 是 bundled 的，
   打不开的是 Turna 侧共享 catalog 那份独立 FFI 库。
3. 「给 sqlite3 注册一个 `OperatingSystem.ohos` override 即可」——**该枚举值不存在**
   （`sqlite3-2.9.4` 只有 android/linux/iOS/macOS/windows/fuchsia）。可用入口只有
   `overrideForAll()`，故 `ensureOfficialAnkiSqlite` 的分派方式是**重写**而非加一行
   （已于 2026-10-08 施工，收据见 ADR 0050 §4.1）。

**平台判断一律走 `isHarmonyOsTarget`**（`lib/core/ohos_target.dart`），不得内联
`Platform.is*` 比较：鸿蒙上 `Platform.is*` **全为 false**，写成 `Platform.isLinux` 之类
会静默走进错误分支。该纪律由 `ohos_eol_architecture_guard_test.dart` 断言。

**同理：`lib/` 里不得出现 `Ohos*` 标识符**（`OhosView` / `OhosViewController` /
`initOhosView` 等）。它们只存在于 OHOS fork SDK，官方 SDK 下是 `undefined_class`，
而 `dependency_overrides` 无平台条件——这与 ADR 0047 §7.1 记录的
`case TargetPlatform.ohos:` 是同一个失败类。详见 ADR 0050 §3.1。
- `tool/gui` 是仓库内创作者桌面工具，**不进 app 本体**（ADR 0032）；它有独立门禁，见 §8。

---

## 8. 门禁（默认不跑，按需执行）

**默认工作流不跑测试。** 改完直接构建、出包、交付。不要每轮改动都自动展开 `flutter analyze` / `flutter test`，也不要为了让门禁变绿而自行多跑一轮。测试是**用户明确要求时**才执行的验证手段，不是默认步骤。

| 何时 | 命令 |
|---|---|
| 改 `@freezed` / `@JsonSerializable` / `@AutoRoute` / `@injectable` / drift 后 | `make gen` |
| 用户明确要求验证 / 用户报回归要定位 / 改动本身落在 `test/` 下的门禁断言上 | `flutter analyze` + `flutter test --exclude-tags golden` |
| 测试数变化 | 更新 `test/BASELINE.md`（前插式，只增不删） |
| 架构决策 | 在 `docs/decisions/` 加 ADR，编号不复用 |

**「本轮没跑」不等于「规则已改」**：§0 的裁决顺序不变，门禁测试仍是规范的可执行形式。不跑只改变「这次有没有验证」，不改变任何一条禁则的效力——不得把「反正不跑」当作放宽分层的理由。

- **本地绿线是 `flutter test --exclude-tags golden`**；全量含 golden 的既有失配清单与基线只认 `test/BASELINE.md`，本文件不复述。
- 全量等价：`make ci` = `format-check analyze test test-python lint-gui guard-gui test-gui build-release-smoke`。
- GUI：`python tool/gui/run_gui_tests.py ci` 是快速档；`full` 才是 CI 跑的全量档，`make test-gui` 等于后者。
- 发布：`python tool/build_release.py --version X.Y.Z` —— X.Y.Z 必须与 `pubspec.yaml` 一致，**脚本会断言**；命令里不得硬编码版本号。

### 规则的强制手段（决定会不会腐坏）

写规则时必须标明它靠什么拦，否则只剩自觉：

| 强制手段 | 覆盖 |
|---|---|
| 门禁测试 `test/architecture/layering_guard_test.dart` | §2 全部分层禁则（逐文件，且豁免白名单双向校验） |
| analyzer lint `analysis_options.yaml` | `print` 禁用、async 与 stream 资源泄漏、未处理 Future |
| codegen `make gen` | freezed / json_serializable / auto_route / injectable / drift 生成物与手写源同步 |
| `make guard-gui` | `tool/gui/` 自身的分层 + 数值 ratchet 契约 |
| **仅自觉（尚无断言测试）** | 禁 `debugPrint`、不新增裸 `.like()`、`*_page.dart` 命名、主题色不写裸常量 |

给「仅自觉」条目补断言测试，是把本文件从约定升级为强制的唯一路径；补完即从上表移入上行。

## 9. 环境与仓库事实

- Windows 用 `python`，非 `python3`（`Makefile` 内写的是 `python3`，需按环境替换）。
- 两个 git remote：`origin`（fetch 走 gitee，push 同时推 gitee + github）与 `github`（仅 GitHub）。**GitHub 通常更新更快**，gitee 可能落后；gitee 直连即可。
- 直连 `github.com` 常被重置 / 超时；如需走本机代理，用一次性参数（不改全局配置）：
  ```bash
  git -c http.proxy=http://<proxy-host>:<port> -c https.proxy=http://<proxy-host>:<port> fetch github
  git -c http.proxy=http://<proxy-host>:<port> -c https.proxy=http://<proxy-host>:<port> push github master
  ```
  代理地址属本机配置，**不写入本文件**。

### 9.1 OHOS 伴生版：codegen 必须用 fork SDK（失败症状是白屏）

`pubspec.yaml` 的 `dependency_overrides` 是**全局的、无平台条件**的，所以本机需要**两份 Flutter SDK**：

| SDK | 用途 |
|---|---|
| 官方 SDK | Android / iOS / Web 的 analyze、test、build |
| **OHOS fork**（`3.44.9+ohos-0.0.1-canary1`） | 一切 `ohos/` 构建；路径见 `ohos/local.properties` 的 `flutter.sdk` |

**`dart run build_runner` 必须用 fork 的 `dart`**（或 `make gen`，它走 fork）。用 PATH 上的官方 `dart` 执行会把 `.dart_tool/package_config.json` 的 `flutter` 指向官方 SDK，于是：

```
⛔ Uncaught platform error
Unknown platform. ohos was not recognized as a target platform.
#0 defaultTargetPlatform (package:flutter/src/foundation/_platform_io.dart:39:5)
```

**启动即白屏。** 症状与 codegen 毫无关系，错误里也不提 `build_runner`——2026-10-07 在这上面绕了一圈才定位到。

踩过一次之后 `flutter` on PATH 仍然会优先命中官方 SDK（每次构建都会打这条 warning）：

```
Warning: `dart` on your path resolves to ...\flutter\bin\dart
         which is not inside your current Flutter SDK checkout
```

**这条 warning 不是噪音**，出现即说明本次可能编进了官方框架。恢复：

```bash
<fork>/bin/flutter.bat pub get     # 把 package_config 指回 fork
```

**构建 `ohos/` 只能走 `<fork>/bin/flutter.bat build hap --debug|--release`**：它顺带把插件依赖写进 `ohos/entry/oh-package.json5` 并 `ohpm install`。**裸跑 hvigor 会在插件依赖被清掉后失败**（`ohpm install` 会删掉 `entry/oh_modules/` 下的插件却不重装），且不会重新生成 `libapp.so` / `flutter_assets`——那两样是上一次 flutter 构建的产物，hvigor 只负责打包。

因此改动 `@injectable` / `@freezed` / `@RoutePage` 后的完整顺序是：**fork SDK 跑 codegen → fork SDK 跑 `build hap`**。

**构建前必须先清两个缓存目录**（本机工具链的批量删除保护会拦构建，报 `Error Code: 00308018` + `SAFE_DELETE_BULK_CONFIRM_REQUIRED`，**不是 ArkTS 错误**）：

```bash
rm -rf ohos/entry/src/main/resources/rawfile/flutter_assets \
       ohos/entry/build/default/cache/default/default@CompileArkTS
```

两个目录都是纯构建产物；不清就会在 `FlutterTask` / `CompileArkTS` 阶段被打断，看起来像编译失败。收据见 34 收据「鸿蒙复习面 UI-15 对齐与 ArkTS 编译器收据（2026-10-18 晚）」。

### 9.2 鸿蒙签名材料

签名材料在 `~/.ohos/config/`，由 `ohos/build-profile.json5` 的 `app.signingConfigs[].material` 指向。**五条硬规则**（细节与排错见 [`docs/ohos-build-setup.md`](./docs/ohos-build-setup.md)）：

1. **三件套必须同代**：`storeFile`（密钥库）、`certpath`（证书链）、`profile` 必须来自同一次生成。不同代 → `ERROR: 11111002 Certificates error`。
2. **别被工具的误导性提示带跑**：它会说 "Please check whether the keyAlias is correct"，但 `hap-sign-tool` 在 `generate-keypair` 与 `sign-app` 两侧都做**别名小写归一**——配置写 `debugKey`、库内条目是 `debugkey` 是**对的**。别名大小写不是失败原因（2026-10-20 已实测证伪）。
3. **密码只能给加密 blob**：明文 → `00303116` / `00303242`。
4. **`app.products[].signingConfig` 必须引用** `signingConfigs[].name`，否则只出 unsigned 包。
5. **真机直装只能用 debug profile**：`type=release` 的 profile 无 `device-ids`，装不上测试机。

**红线**：release 密钥库口令、任何明文口令、`~/.ohos/config/material/` 的内容，**不得进仓库、提交、CI 日志或对话记录**。口令只允许存在于 `~/.ohos/config/` 与被 git 忽略的 `ohos/SIGNING.local.md`。

---

## 10. 文档锚点

- 引用测试 / 改动 / 验证记录 **禁止行号**，用「文件 + 条目日期 + 标题」三段锚。
  - ✅ `test/BASELINE.md` 2026-09-24「架构简化实施计划 P0–P4」条目
  - ✅ `docs/official-anki-migration/34-cutover-receipt.md` 的「架构简化批次」小节
  - ❌ `BASELINE.md:303-307` —— 该文件前插式只增，行号必然漂移（已发生过，见 `test/archive/` 修例）
- 指向**会被改写的源码**同样用符号名；仅冻结文件（脚本、schema 表清单）可写行号。
- 改动被引用方时，同步全部入链；指向已迁移/已删文档的指针按**断链**处理。
- 项目状态数字的清点真源是 `docs/content_inventory_current.md`（由 `tool/export_content_inventory.py` 生成），不是本文件。

## 11. 按需查阅（无叙述，只给位置）

| 要找什么 | 去哪 |
|---|---|
| 全部文档在哪、哪篇管什么 | `docs/README.md`（文档索引） |
| 教学法 / 课程体系设计 | `docs/project-guide.md` §1–§2 |
| 分层 / 架构树 / 关键模式 / 领域模型 | `docs/project-guide.md` §3–§4 |
| 各子系统实现状态 | `docs/project-guide.md` §4–§7（AI 功能清单 §7.3） |
| 课程数据格式 | `docs/project-guide.md` §13 |
| 平台与构建 / 发布流水线 | `docs/project-guide.md` §10；`docs/android-build-setup.md`；`docs/ios-build-setup.md`；`docs/ohos-build-setup.md` |
| 鸿蒙签名材料 / 签名排错 | 本文件 §9.2；[`docs/ohos-build-setup.md`](./docs/ohos-build-setup.md)（口令在 git-ignored 的 `ohos/SIGNING.local.md`） |
| 视觉与主题 / 无障碍 | `docs/project-guide.md` §9 |
| 明确不做的事 | `docs/project-guide.md` §15 |
| Official Anki 全部进度与证据 | `docs/official-anki-migration/34-cutover-receipt.md` |
| 鸿蒙能力边界（三层口径） | 本文件 §7.1；[ADR 0047](./docs/decisions/0047-ohos-companion-lite-build.md) |
| 决策理由 | `docs/decisions/`（编号不复用，0021 / 0043 为历史复用） |
| 测试基线与已知失配 | `test/BASELINE.md`（更早见 `test/archive/`） |
| 通用 Dart / Flutter 规范 | `.agents/skills/`（按 description 触发，无需 `@` 引用） |
| 子 agent | `.claude/agents/` |

子 agent 的正文口径**以其自身文件为准**，本文件不转述其内容状态；若某 agent 正文与 `docs/project-guide.md` 冲突，以 project-guide 为准并修 agent 文件，不要在本文件挂警告。
