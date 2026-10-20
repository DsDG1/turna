# Turna — Agent 规范

> 本文件是**行为规范**，不是项目介绍。架构 / 功能叙述见 [`docs/project-guide.md`](./docs/project-guide.md)；**当前状态**见 [`docs/status.md`](./docs/status.md)；决策理由见 [`docs/decisions/`](./docs/decisions/)。
>
> 本文件是根级 Agent 指令的**唯一真源**。内容按**实际工作流**排序：先定位落点 → 再看约束 → 最后跑门禁。

---

## 0. 冲突裁决

按序覆盖，下位不得推翻上位：

1. **门禁测试**（`test/architecture/` 与各 `*_test.dart`）—— 规范的可执行形式，最高
2. 本文件的禁则清单
3. **当前状态口径** —— 只认 [`docs/status.md`](./docs/status.md)
4. `docs/project-guide.md` 的架构与设计叙述
5. `docs/decisions/` ADR —— 只提供决策理由，不覆盖以上

事实性数字（schemaVersion、版本号、测试计数、目录清单条数）**一律现场查证，不写死在本文件**；写死即腐坏点。目录与文件**路径**是稳定事实，可直接引用。

**本文件不写日期。** 需要「某件事什么时候发生的」时去 `git log` 或 `docs/status.md`。

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
| 动桌面创作者工具 | `tool/gui/` | 独立 Python 工程，有独立门禁，见 §8 |

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

---

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

---

## 4. 日志与错误处理

- 统一用 `core/logger.dart` 的 `logger`（`t/d/i/w/f`）；**禁 `print`**（analyzer `avoid_print` 强制）、**禁 `debugPrint`**（仅自觉）。`log_capture.dart` 内部防递归的若干处 `debugPrint` 是唯一例外。
  - 理由：logger 进入用户可导出的透明度日志，release 有等级过滤；`debugPrint` 两者皆无。
- 需要堆栈：`logger.w('...', error: e, stackTrace: st)`。
- **空 catch 必须有一行注释说明为何安全**。可静默 catch 仅限两类：GetIt 可选依赖守卫、best-effort 清理；其余操作型失败（写入 / 统计 / 诊断）至少补 `logger.w`。
- 错误通道：可恢复加载失败走 Provider 状态机（如 `SectionLoadState.error`），一次性动作用 SnackBar。
- **不引入全局错误弹窗**；`core/result.dart` 的 `Result` 供 repository 接缝渐进采用。

---

## 5. 状态选型与命名

- UI 局部状态 → `setState`；跨 widget 共享 → `provider`（`ChangeNotifier` + `context.watch/read`）；无 UI 依赖的服务 / 仓库 → `get_it`（injectable 注解）。
- 页面里**不得直接 `getIt<DataLayerType>()`**；数据访问走 repository 接口或 application 门面。
- 页面文件统一 `*_page.dart`，**新代码不得新增 `_screen.dart`**；存量 `_screen.dart` 改名牵连路由与测试，按渐进迁移处理，**不与本规则相关的功能改动不得顺手改名**。
- 组件目录：跨功能共享 → `lib/views/widgets/`；功能域私有 → `<feature>/components/`。**新功能域统一 `components/`**，不再新建 `*/widgets/`。
- 全应用 LLM 出入口唯一：`lib/application/ai/engine/`；页面不得直连其他 LLM SDK。

---

## 6. 数据与算法

- SQL `LIKE` 统一走 `lib/data/sql_like.dart`：用户 / 外部输入经 `escapeLikePattern()` 转义 `%` `_` `\`；drift 侧用 `LikeEscaped` 或 `containsLike()` / `prefixLike()`。**不新增裸 `.like()` 或手写 LIKE**（纯常量前缀豁免）。
- `lib/core/fsrs_optimizer.dart` 与 `fsrs` 包**逐公式镜像**（难度阻尼、召回稳定度、lapse 取 min、0.9 曲线锚定均为包行为）。**升级 fsrs 包必须同步核对模型公式**，否则本地拟合权重与调度口径漂移。
- 调色板真源 `lib/core/theme.dart` ↔ `tool/gui/src/theme_tokens.py`；不得新造 `peacock*` 别名，不得在页面内写裸品牌色常量。

---

## 7. 范围与口径（禁语清单）

- 不做无外部来源的功能声明。**鸿蒙口径分三层，别混用**——产品级 / 伴生版 / Official Anki 三层的事实、Hold 项与移除项，全部见 [`docs/status.md`](./docs/status.md) 的「鸿蒙三层口径」。本文件不复述。
- `tool/gui` 是仓库内创作者桌面工具，**不进 app 本体**（ADR 0032）；它有独立门禁，见 §8。

### 7.1 平台判断纪律

- 平台判断一律走 `isHarmonyOsTarget`（`lib/core/ohos_target.dart`），**不得内联 `Platform.is*` 比较**：鸿蒙上 `Platform.is*` **全为 false**，写成 `Platform.isLinux` 之类会静默走进错误分支。该纪律由 `ohos_eol_architecture_guard_test.dart` 断言。
- **`lib/` 里不得出现 `Ohos*` 标识符**（`OhosView` / `OhosViewController` / `initOhosView` 等）。它们只存在于 OHOS fork SDK，官方 SDK 下是 `undefined_class`，而 `dependency_overrides` 无平台条件——这与 ADR 0047 §7.1 记录的 `case TargetPlatform.ohos:` 是同一个失败类。详见 ADR 0050 §2.2（`undefined_class` 的实际症状）与 §2.3（`Ohos*` 与 `AndroidViewController` 同库、三条路线被否决的论证）。
- `sqlite3` 包没有鸿蒙平台枚举值（只有 android / linux / iOS / macOS / windows / fuchsia）。可用入口只有 `overrideForAll()`，故 `ensureOfficialAnkiSqlite` 的分派方式是**重写**而非加一行 override。

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
| 门禁测试 `test/architecture/docs_hygiene_test.dart` | 文档卫生：ADR 编号唯一、ADR 编号提及真实存在、文档索引无孤儿、活文档不含撤销标记、`AGENTS.md` 无日期戳、无断链、正文里的 `.md` 文件名按路径真实存在、无未闭合代码段 |
| analyzer lint `analysis_options.yaml` | `print` 禁用、async 与 stream 资源泄漏、未处理 Future |
| codegen `make gen` | freezed / json_serializable / auto_route / injectable / drift 生成物与手写源同步 |
| `make guard-gui` | `tool/gui/` 自身的分层 + 数值 ratchet 契约 + GUI 文档树索引无孤儿 / 文档指针存活 / 无未闭合代码段 |
| **仅自觉（尚无断言测试）** | 禁 `debugPrint`、不新增裸 `.like()`、`*_page.dart` 命名、主题色不写裸常量 |

给「仅自觉」条目补断言测试，是把本文件从约定升级为强制的唯一路径；补完即从上表移入上行。

---

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

**启动即白屏。** 症状与 codegen 毫无关系，错误里也不提 `build_runner`。

踩过一次之后 `flutter` on PATH 仍会优先命中官方 SDK（每次构建都会打这条 warning）：

```
Warning: `dart` on your path resolves to ...\flutter\bin\dart
         which is not inside your current Flutter SDK checkout
```

**这条 warning 不是噪音**，出现即说明本次可能编进了官方框架。恢复：`<fork>/bin/flutter.bat pub get`。

**构建 `ohos/` 只能走 `<fork>/bin/flutter.bat build hap --debug|--release`**（裸跑 hvigor 会在插件依赖被清掉后失败，且不会重新生成 `libapp.so` / `flutter_assets`）。

构建前必须先清两个缓存目录（本机工具链的批量删除保护会拦构建，报 `Error Code: 00308018` + `SAFE_DELETE_BULK_CONFIRM_REQUIRED`，**不是 ArkTS 错误**）：`ohos/entry/src/main/resources/rawfile/flutter_assets` 与 `ohos/entry/build/default/cache/default/default@CompileArkTS`。

完整构建流程、产物落位、验签步骤见 [`docs/ohos-build-setup.md`](./docs/ohos-build-setup.md)。

### 9.2 鸿蒙签名材料

签名材料在 `~/.ohos/config/`，由 `ohos/build-profile.json5` 的 `app.signingConfigs[].material` 指向。**五条硬规则**：

1. **三件套必须同代**：`storeFile`（密钥库）、`certpath`（证书链）、`profile` 必须来自同一次生成。不同代 → `ERROR: 11111002 Certificates error`。
2. **别被工具的误导性提示带跑**：它会说 "Please check whether the keyAlias is correct"，但 `hap-sign-tool` 在 `generate-keypair` 与 `sign-app` 两侧都做**别名小写归一**——配置写 `debugKey`、库内条目是 `debugkey` 是**对的**。别名大小写不是失败原因。
3. **密码只能给加密 blob**：明文 → `00303116` / `00303242`。
4. **`app.products[].signingConfig` 必须引用** `signingConfigs[].name`，否则只出 unsigned 包。
5. **真机直装只能用 debug profile**：`type=release` 的 profile 无 `device-ids`，装不上测试机。

明细、blob 结构、排错速查见 [`docs/ohos-build-setup.md`](./docs/ohos-build-setup.md)。

**红线**：release 密钥库口令、任何明文口令、`~/.ohos/config/material/` 的内容，**不得进仓库、提交、CI 日志或对话记录**。口令只允许存在于 `~/.ohos/config/` 与被 git 忽略的 `ohos/SIGNING.local.md`。

---

## 10. 文档锚点

- 引用测试 / 改动 / 验证记录 **禁止行号**，用「文件 + 条目日期 + 标题」三段锚。
  - ✅ `test/BASELINE.md`「架构简化实施计划 P0–P4」条目
  - ✅ `docs/status.md`「迁移总体口径」小节
  - ❌ `BASELINE.md:303-307` —— 该文件前插式只增，行号必然漂移（已发生过：早期用行号锚点的写法在本轮文档精简时已成为悬空指针，修例见 git 历史）
- 指向**会被改写的源码**同样用符号名；仅冻结文件（脚本、schema 表清单）可写行号。
- 改动被引用方时，同步全部入链；指向已迁移 / 已删文档的指针按**断链**处理。
- **文档分层只有四类，不得混写**：行为规范（本文件）· 架构叙述（`docs/project-guide.md`）· 决策理由（`docs/decisions/`）· 当前状态（`docs/status.md`）。
  - 施工日志、真机收据原文、一次性审计报告 → **不写进任何活文档**，留在 git 历史。
  - 一个事实只有一个落点，其余全部改成指针。
- 项目状态数字的清点真源是 `docs/content_inventory_current.md`（由 `tool/export_content_inventory.py` 生成），不是本文件。

---

## 11. 按需查阅（无叙述，只给位置）

| 要找什么 | 去哪 |
|---|---|
| 全部文档在哪、哪篇管什么 | [`docs/README.md`](./docs/README.md)（文档索引） |
| **现在是什么样**（迁移口径 / 平台档位 / Held 项） | [`docs/status.md`](./docs/status.md) |
| 教学法 / 课程体系设计 | [`docs/project-guide.md`](./docs/project-guide.md) §1–§2 |
| 分层 / 架构树 / 关键模式 / 领域模型 | [`docs/project-guide.md`](./docs/project-guide.md) §3 |
| 课程数据格式 | [`docs/project-guide.md`](./docs/project-guide.md) §13 |
| 写课程要遵守的格式契约 | [`docs/authoring/`](./docs/authoring/) |
| 视觉与主题 / 无障碍 | [`docs/project-guide.md`](./docs/project-guide.md) §9 |
| 明确不做的事 | [`docs/project-guide.md`](./docs/project-guide.md) §15 |
| 平台与构建 / 发布流水线 | [`docs/android-build-setup.md`](./docs/android-build-setup.md)；[`docs/ios-build-setup.md`](./docs/ios-build-setup.md)；[`docs/ohos-build-setup.md`](./docs/ohos-build-setup.md) |
| 鸿蒙签名材料 / 签名排错 | 本文件 §9.2；[`docs/ohos-build-setup.md`](./docs/ohos-build-setup.md)（口令在 git-ignored 的 `ohos/SIGNING.local.md`） |
| Official Anki 决策理由 | [`docs/decisions/0050-ohos-official-anki.md`](./docs/decisions/0050-ohos-official-anki.md) |
| 鸿蒙能力边界（三层口径） | 本文件 §7；[`docs/status.md`](./docs/status.md) §6；[ADR 0047](./docs/decisions/0047-ohos-companion-lite-build.md) |
| 决策理由 | [`docs/decisions/`](./docs/decisions/)（编号不复用） |
| 测试基线与已知失配 | [`test/BASELINE.md`](./test/BASELINE.md) |
| 通用 Dart / Flutter 规范 | `.agents/skills/`（按 description 触发，无需 `@` 引用） |
| 子 agent | `.claude/agents/` |

子 agent 的正文口径**以其自身文件为准**，本文件不转述其内容状态；若某 agent 正文与 `docs/project-guide.md` 冲突，以 project-guide 为准并修 agent 文件，不要在本文件挂警告。
