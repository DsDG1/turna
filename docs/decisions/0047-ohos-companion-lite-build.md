# ADR 0047 — OHOS 伴生轻量版（产品级 EOL 口径的修订）

> 状态：已接受｜日期：2026-10-03
>
> 方案正文：`OHOS-最简兼容方案.md` v1.1（桌面，不入库）
>
> 关联：[ADR 0050](./0050-ohos-official-anki.md)（修订本文 §2 第 2 条与 §5.8）、[ADR 0048](./0048-ohos-companion-audio-tts.md)、[`native/turna_anki_core/build-ohos/README.md`](../../native/turna_anki_core/build-ohos/README.md)
>
> 修订说明：原 ADR 0041（产品级 EOL）已随文档精简删除，其口径由本文取代。**§2 第 2 条「不启用 Official Anki 引擎与保真复习器」与 §5.8「`ohos/` 不得出现 Official Anki 引擎宿主」均由 [ADR 0050](./0050-ohos-official-anki.md) 取代**；§2 其余条款、§3–§7 全部不变。当前接线状态见 [`../status.md`](../status.md) §6。

## 决策

原 ADR 0041（已删）停止的是**产品级** OHOS 支持。本 ADR 不恢复产品线，只授权一个**伴生轻量版**：可独立构建、可独立关闭，不进入主交付、不改变 Android / iOS 任何行为。

### 1. 范围（做什么）

课程内容、SRS / FSRS 调度、词典与生词卡、复习会话与台账、设置 / 透明度日志 / 本地备份导入导出。课程数据库走鸿蒙原生 RDB；文件选择（`.apkg` / 课程包 / 备份）走自带 ArkTS 选择器；音频播放与 TTS 走自带 ArkTS 通道（见 [ADR 0048](./0048-ohos-companion-audio-tts.md)）。

**本地提醒不在伴生范围内**：`flutter_local_notifications` 因公开 API 分叉（`InitializationSettings` 新增上游没有的 `ohos` 字段，官方 SDK 下是硬编译错误）已被移出 override 清单（§7.3）。音频 / TTS 也不需要 override，因为走自维护 ArkTS 通道。

### 2. 范围（不做什么，且由门禁强制）

- 不对齐 Android 全功能（全量对齐另需 4–6 周，其中复习器 5–8 人日，而 Android 侧自身尚有 3 条 HOLD 未收）
- **不启用 Official Anki 引擎与保真复习器** —— 该条已由 [ADR 0050](./0050-ohos-official-anki.md) 取代：鸿蒙伴生版启用 Official Anki 全档（引擎 / `.apkg` 导入 / 课程树投影 / 保真复习器）。现行接线状态见 [`../status.md`](../status.md) §6。
- 不做音频播放 / TTS 的隐式降级：必须在 UI 上显式说明。
- 不从源码构建 OHOS Flutter Engine：使用预编译 SDK（Windows 只能 `gen_snapshot`，完整 Engine 构建需 Linux / macOS）
- 不改 Android / iOS 行为，不降主产品的依赖约束
- **不引入依赖包 fork 补丁工具链**（`tool/apply_patches.sh` / `tool/patches/`）。**但允许** §7 列出的两处**预编译产物 / 上游包**适配，且二者都在仓库内受版本控制、由门禁断言——这与「给第三方 pub 包打补丁」是两件事：前者是我们自维护的移植，后者是被原 ADR 0041（已删）明令删除的东西

### 3. 门禁处置

原「禁止 OHOS 复活」测试改写为**二态**，见 §4 逐条处置表。以 `ohos/` 目录是否存在为分支开关：不存在 → 原 EOL 断言逐字保留（部分回退安全）；存在 → 切换到**范围 ratchet**，一组新的、更强的正向断言。

**这条设计不是白名单绕过**：切换到伴生态时守卫并不沉默，而是换成另一组仍活跃的断言；且 `ohos/` 为空目录或残缺目录会因「必需文件集」断言而失败。

### 4. 门禁逐条处置表

`test/application/anki_official/ohos_eol_architecture_guard_test.dart` 现状 4 个 test / 10 条断言，逐条处置如下。

| test | 断言 | 伴生态下的处置 | 依据 |
|---|---|---|---|
| 1 | `Directory('ohos')` 不存在 | **条件化**（分支开关本身） | 本 ADR 授权 `ohos/` |
| 1 | `lib/data/rdb_query_executor.dart` 不存在 | **条件化** | W4 恢复 RDB 数据层 |
| 1 | `lib/utils/ohos_file_picker.dart` 不存在 | **条件化** | W5 恢复文件选择器 |
| 1 | `tool/apply_patches.sh` 不存在 | **保留，不条件化** | 决策 §2 第 6 条：预编译 SDK 路线不需要补丁工具链 |
| 1 | `Directory('tool/patches')` 不存在 | **保留，不条件化** | 同上 |
| 2 | needle `HarmonyOsRdbExecutor`（扫 `lib`） | **条件化**，随 `lib` 根一起切换 | 出现在 `rdb_query_executor.dart` 与 `locator.dart`，W4 恢复 |
| 2 | needle `OhosInitializationSettings`（扫 `lib`） | **条件化** | 出现在 `local_reminder_service.dart`；本地提醒已退出伴生范围（§1 / §7.3） |
| 2 | needle `OhosNotification`（扫 `lib`） | **条件化** | 同上 |
| 2 | needle `openharmony`（扫 `pubspec.yaml`） | **条件化**，并由「禁一切字样」升级为「override 清单 ratchet」 | fork 的 URL 字面含 `openharmony-tpc` / `openharmony-sig`，绕不开 |
| 2 | needle `tool/apply_patches.sh` | **保留，不条件化** | 与 test 1 一致 |
| 2 | 扫描根缺失即违规 | **保留，不条件化** | 与分支无关 |
| 2 | `README.md` / `AGENTS.md` / `docs/project-guide.md` / `docs/android-build-setup.md` 无 needle | **保留，不条件化** | 写文档时避开上述字面即可 |
| 3 | `official_anki_engine_kind.dart` 无 `case 'ohos':`、无 `legacyFallbackRequired: true` | **「无 `legacyFallbackRequired: true`」保留**；**「无 `case 'ohos':`」已由 [ADR 0050](./0050-ohos-official-anki.md) 移除** | ADR 0050 授权鸿蒙走 Official 路径，该断言与授权直接冲突。`legacyFallbackRequired` 语义未变，其断言继续生效。移除的已知代价记录在 ADR 0050 |
| 4 | Android arm64 打包规则 | **保留，不条件化** | 决策 §2 第 5 条：不改 Android 行为 |

> 修正一处方案初稿的判断：`OhosInitializationSettings` / `OhosNotification` 并非「不触发」，二者都在 `local_reminder_service.dart` 的本地提醒初始化路径上，恢复本地提醒后必然命中。

### 5. 伴生态新增的范围 ratchet（比原「禁字样」更强）

原断言的强度是「这些字符串不许出现」——它无法阻止有人引入一个全新的 fork。伴生态换成「只允许清单内的 override，且每条必须钉 ref」：

1. `pubspec.yaml` 的 git override 集合**必须精确等于** §6 清单（按包名 → URL + ref 比对，多一条少一条都失败）
2. 每条 OHOS override **必须带显式 `ref:`**，禁止跟默认分支
3. 禁止任何指向本地 `ohos/` 目录的 `path:` override
4. `webview_flutter` **不得**被 override。ADR 0050 的保真复习器走**官方路径**（`official_anki_reviewer_view.dart` 的 `PlatformViewLink` / `UiKitView`），鸿蒙 fork SDK 提供原生 PlatformView（`initOhosView` / `initSurfaceOhosView` / `initExpensiveOhosView` 三路齐备）；官方路径不 import `webview_flutter`，故本条保持原样。受本条约束的只有旧 Anki 保真路径 `anki_html_card_view.dart`。**注意**：原生 PlatformView 的存在只说明平台能力；Dart 侧引用 `Ohos*` 标识符在官方 SDK 下是 `undefined_class`，那是 ADR 0050 的第二道关，与本条无关。
5. `flutter_tts` / `audioplayers` **不得**被 override（无 OHOS fork；将来若要加，必须先改本 ADR）。伴生版**没有** override 它们，而是另写 ArkTS 通道（ADR 0048）走平台原生能力。
6. `ohos/` 下**不得**含构建产物（把误提交永久固化为断言）
7. `ohos/` 必须含必需文件集（`module.json5` / `build-profile.json5` / `hvigorfile.ts` / **四个**手写 ArkTS 插件）——空目录或残缺目录失败。权威清单以门禁的 `_requiredOhosFiles` 为准（RDB、文件选择、音频、TTS）
8. **`ohos/` 不得出现 Official Anki 引擎宿主** —— 该条已由 [ADR 0050](./0050-ohos-official-anki.md) 取代：引擎宿主正是 ADR 0050 要装进 `ohos/` 的东西。该条承诺的「针对 `ohos/` 目录本身的」补充断言**从未实现**（门禁只对 Dart 文件断言 `case 'ohos':`），ADR 0050 已记录该缺口并把补门禁留给接线批次。

### 6. 允许的 OHOS 依赖 override 清单

```yaml
shared_preferences:            gitcode.com/openharmony-tpc/flutter_packages.git   ref: br_shared_preferences-v2.5.3_ohos
path_provider:                 gitcode.com/openharmony-tpc/flutter_packages.git   ref: br_path_provider-v2.1.5_ohos
url_launcher:                  gitcode.com/openharmony-tpc/flutter_packages.git   ref: br_url_launcher-v6.3.2_ohos
package_info_plus:             gitcode.com/openharmony-sig/flutter_plus_plugins.git ref: <待 W3 定>
share_plus:                    gitcode.com/openharmony-sig/flutter_plus_plugins.git ref: <待 W3 定>
file_picker:                   gitcode.com/openharmony-sig/fluttertpc_file_picker.git  ref: <待 W3 定>
flutter_local_notifications:   gitcode.com/openharmony-sig/fluttertpc_flutter_local_notifications.git ref: <待 W3 定>
```

**必须重新钉 ref，不能照抄历史。** 历史 `pubspec.yaml` 里 7 条 override 中有 4 条（`package_info_plus` / `share_plus` / `file_picker` / `flutter_local_notifications`）**根本没写 `ref:`**，跟的是默认分支——历史实现本身不可复现，fork 仓库一旦推新分支结果就漂。ratchet 第 2 条就是为堵这个洞。`flutter_local_notifications` 一条已在 §7.3 判定为移除。

### 7. 自维护的两处 Flutter 侧移植

原方案讨论的是两条**全局版本 pin**（`win32: 2.7.0` / `flutter_secure_storage_windows: 2.1.1`）。**实测结论：两条都不再需要**——W1 锁定的 SDK 是 Dart 3.12.2，与官方 3.44.5 一致，`UnmodifiableUint8ListView` 早已具备；故**没有全局 pin 被引入**，§2「不改主产品依赖约束」得以保持。

取而代之的是本节：伴生版**必须自维护**的两处移植。二者都源于同一个上游事实——**OHOS fork 的适配落后于 Flutter 自身的重构**。

#### 7.1 `material_ui` / `cupertino_ui` 的 `TargetPlatform` 移植

Flutter 3.44 把 Material / Cupertino 从框架内**拆成 hosted 包**。fork 适配了框架内副本（`packages/flutter/lib/src/material`、`.../cupertino`，共 129 处 `case TargetPlatform.ohos:`），**没适配拆出去的 hosted 副本**，于是 168 个非穷尽 switch 编译失败。

`openharmony-tpc` / `openharmony-sig` / `CPF-Flutter` 三个组织下**不存在这两个包的任何 fork**，只能自维护。

移植方式**不是发明语义，而是照抄 fork 自己的放置**：

- 匹配键 = switch 的 arm 结构，**剔除 `ohos` 之后**两边才可能相等（fork 的 arm 是 `(android, fuchsia, linux, windows, ohos)`，vendored 是前四项，不剔除永远配不上）
- 只复制 **arm 归属**，不复制顺序（同一 arm 内 case 顺序在 Dart 里无语义）
- **必须逐站点照抄**：绝大多数站点 ohos 与 `android` 同组（另一 arm 是 `iOS+macOS`），但存在刻意放在 iOS 组的站点（如 `adaptive_text_selection_toolbar`——那意味着 OHOS 上用 Cupertino 风格文本选区把手，是原作者的产品决定）。套用「ohos 跟 android」这类统一启发式**会编译通过但渲染出错误的平台样式**，比编译错误更糟

**关键约束（推翻了「vendor 一份就够」的原方案）**：`dependency_overrides` 是**全局的、无平台条件**的。移植若写成 `case TargetPlatform.ohos:`，该副本在**官方 SDK 下根本编译不过**（官方枚举无此值）——实测 Android/iOS 构建与**全部测试**直接崩（全是 `Member not found: 'ohos'`）。因此**同一份 vendor 副本必须同时在两个 SDK 下有效**，唯一可行形态是用**通配 arm** 承载 ohos：显式 label 优先匹配，ohos 落入**末尾追加**的通配 arm，官方 SDK 下该 arm 不可达——语义与 `case TargetPlatform.ohos:` 完全等价。

末尾追加还顺带解掉了可空主体的坑：已有的 `null =>` / `case null:` 在更早的位置，**仍然先匹配**，所以通配 arm 不会遮蔽它，无需 guard。

自动化过程中撞到 8 处语义陷阱，**全部由编译器抓出**（不是推理），这也是本节最有价值的部分——门禁测试对这类错误无能为力：

| 陷阱 | 现象 |
|---|---|
| 单行 arm | 插入新行会复制出整条链，产生重复 arm |
| replace 漏 `\|\|` | 产出 `fuchsia TargetPlatform.ohos \|\|=> v` |
| 模板重复箭头 | 产出 `_ =>=> v` |
| **switch 表达式禁用 `default`** | Dart 只允许 `_`；`default =>` 直接编译失败 |
| **语句的 `default:` 必须居末** | 故「把 `default:` 插入目标 arm 的 label 组」只在目标是末 arm 时成立；统一改为末尾追加独立 arm + 复制 body |
| 尾逗号越界 | 语句体以 `break;` 结束，补逗号即语法错误——逗号只属表达式 |
| **嵌套 switch 归属** | 内层 switch 的 `case` 被算作外层 arm，内层 `}` 被当 body 复制出去，文件被复制成乱码。必须在扫描时跳过嵌套 switch |
| **`null =>` 被误判为通配** | 通配正则放宽到命名常量后，`null =>` 被当成 `_ =>`，导致唯一最需要的站点被跳过 |

工具与产物：

| 项 | 值 |
|---|---|
| 迁移工具 | `third_party/flutter/migrate_ohos_platform.py`（`--check` / `--apply` / `--verify`） |
| 迁移站点 | **84 处**（`material_ui` + `cupertino_ui` 合计），一次 `--apply` 完成 |
| vendored 副本 | `third_party/flutter/material_ui`、`third_party/flutter/cupertino_ui`（520 文件 / 13.26 MB） |
| 声明方式 | `pubspec.yaml` 的 `dependency_overrides` 走 `path:`，**不指 `ohos/`**（门禁断言） |

**已验证的三个失败教训**（都是构建抓出来的，不是推测）：

1. **单行 arm 必须就地替换而非插入**。`TargetPlatform.a || TargetPlatform.b => v` 这类单行 arm，插入新行会复制出整条链，产生重复 arm
2. **replace 时必须显式写出 `||` 分隔符**。prefix 以裸 label 结尾，直接追加会产出 `fuchsia TargetPlatform.ohos ||=> v`
3. **`_ =>` 通配 arm 使 switch 天然穷尽**，解析器若丢弃该 arm 会把它们误判为待迁移（曾产生 1 处假阳性）

因此工具自带 `--verify`：**不依赖两分钟构建**即可断言「没有非穷尽 switch 残留」，且门禁另有 ratchet 钉住站点数与「不得出现缺 `||` 的链」。**升级任一包后站点数变化即红**，这是刻意的：静默漂移比构建失败更难查。

#### 7.2 `@ohos/flutter_ohos` embedding 的 autofill shim

预编译 HAR（`flutter_embedding_<mode>.har`，**252 KB 纯 ArkTS 源码，不含 `.so`**）面向一个带完整 autofill API 的 API 26 SDK；本机只有 HarmonyOS 26.0.0.23，其 `autoFillManager` 只剩 `AutoSaveCallback` 与**两参签名**的 `requestAutoSave(context, callback?)`，故该文件编译失败（`10505001`）。

处理：本地类型别名 + `requestAutoFill` 改 no-op + `requestAutoSave` 改两参。**Turna 无 autofill 表单，故 no-op 是正确行为**；文本输入、IME、平台通道未动。工具 `third_party/flutter/patch_ohos_embedding.py`（`--check` / `--apply`），幂等，6 个 HAR（`ohos-arm64{,-profile,-release}` / `ohos-x64{,-profile,-release}`）全覆盖。

补丁后的符号处置：

| 仍存在 | 已移除（本文件仍在用） |
|---|---|
| `AutoSaveCallback`、`requestAutoSave` | `AutoFillType`（×3）、`ViewData`（×5）、`AutoFillCallback`、`AutoFillTriggerType`、`FillFailureResult`、`FillRequest`、`requestAutoFill`、`SaveRequest` |

> 结构上值得记一笔：HAR 装的是**未编译源码**，ArkTS 编译发生在工程自己的 hvigor 阶段，所以本仓库**不需要编译 embedding**；`ets/modules.abc` 出现在产物 hap 里就是补丁生效的证据。

#### 7.3 fork override 的 SDK 中立性筛选（实测结论）

`dependency_overrides` 全局无平台条件，故**每一个**被 override 的包都必须 SDK 中立。逐个核查 `lib/`（不含 example/test，依赖解析不编译它们）：

| 包 | `lib/` 内 ohos 引用 | 判定 |
|---|---|---|
| `shared_preferences` / `path_provider` / `url_launcher` | **0** | ✅ 可 override，OHOS 支持纯在 ArkTS 侧 |
| `package_info_plus` / `share_plus` | **0** | ✅ 同上 |
| `flutter_secure_storage` | 1 处 `Platform.operatingSystem == 'ohos'`（**字符串比较**，不引入 `Platform.isOhos` 或任何 fork 独有标识符） | ✅ 可 override，vendored 副本见 ADR 0055 §1 |
| `flutter_local_notifications` | 9 处 `defaultTargetPlatform == TargetPlatform.ohos`，**且** `InitializationSettings` 新增上游没有的 `ohos` 字段（类型 `OhosInitializationSettings?`） | ❌ 移除 |

`flutter_secure_storage` 通过筛选的理由与 §7.1 的两处移植**不同**：那两处要承载 `TargetPlatform.ohos` 枚举值（只能用末尾通配 arm 中和），这一处只做字符串比较，官方 SDK 下该分支不可达但**照样编译**。因此它没有通配 arm 下限，门禁改为钉住补丁站点本身（`ohos_eol_architecture_guard_test.dart` 的 `_secureStoragePatchSite`）——重 vendor 时丢掉这一行会编译通过、全部测试通过，只在真机重启后表现为 API key 消失。

`flutter_local_notifications` 被移除的原因**不是**枚举比较（那可用末尾通配 arm 中和，见 §7.1），而是**公开 API 分叉**：一个类型引用在官方 SDK 下是硬编译错误，通配技巧无从下手。采用它还须连带改本仓库 `lib/service/local_reminder_service.dart` 的 OHOS 分支。**代价：本地提醒退出伴生范围**（§1 已记）。

#### 7.4 hvigor 拒绝插件的绝对 srcPath（已解决，且不需要改 DevEco）

装上干净 override 后主产品侧完全正常，但 **OHOS 构建在 hvigor 阶段失败**：

```
> hvigor ERROR: AdaptorError 00303231 Configuration Error
> Error Message: The srcPath is not a relative path:
>   C:/Users/.../Pub/Cache/git/flutter_plus_plugins-.../package_info_plus/ohos
```

**根因不是 DevEco，也不是插件。** 错误定义（`hvigor-logger/res/error/hvigor.json` 的 `THE_SRCPATH_IS_NOT_A_RELATIVE_PATH`）给的 solution 是「检查工程 `hvigorconfig.ts` 里的 srcPath」；而 `hvigorconfig.ts` 只是调 `injectNativeModules`，真正拼 srcPath 的是 `flutter-hvigor-plugin` 的 `relativePath()`：

```ts
let p = path.relative(basePath, filePath)
if (!path.isAbsolute(p) && !p.startsWith('.')) p = './' + p
```

`path.relative()` 在**跨盘符**时返回绝对路径，`isAbsolute` 为真便跳过 `./` 前缀，绝对路径遂交给 hvigor 被拒。

**修法：把 pub cache 放到与工程同盘**（`PUB_CACHE=D:\pub-cache`），不需管理员权限、不需改任何第三方工具。

#### 7.5 由此产生的长期成本（不得当作已解决）

1. **每次升级 `material_ui` / `cupertino_ui` 都要重跑迁移**。这两个包是 Flutter 里变动最频繁的，升级后站点数几乎必然变化，门禁会红——这是**预期行为**，不是回归
2. **伴生版钉在 canary 上**。`3.44.9+ohos-0.0.1-canary1` 是唯一满足框架 ≥3.44 的 OHOS 构建，而 canary 基线会动，等于把上面那条成本再乘一遍
3. 上面两处共 **88 个 Dart 站点 + 1 个 ArkTS 文件**是我们自维护的 Flutter 侧改动面。加上 5 个 git override、3 个 vendored override（本节两处 + ADR 0055 的 `flutter_secure_storage`）与 RDB 插件，这才是伴生版的完整「上游债」清单

## 前置条件与撤销条件

**前置条件（W1 闸门）—— 三条均已满足**

1. DevEco 路径空格已用 8.3 短名绕开且实测通过：`D:\DEVECO~1`，`flutter doctor` 报 `OpenHarmony Sdk at D:\DEVECO~1\sdk, available api versions has [26:default]`，hvigor 全程以无空格路径工作
2. 最小工程 `flutter build hap` 通过，且 Turna 本身产出 `entry-default-unsigned.hap`（`libs/arm64-v8a/libflutter.so` + `ets/modules.abc`）
3. OHOS Flutter SDK 锁定到具体 tag `3.44.9+ohos-0.0.1-canary1`（Dart 3.12.2，与官方 3.44.5 一致）

> **tag 变更记录**：原锁 `3.41.10-ohos-1.0.1`（最新 stable）被证据推翻——本项目代码使用 Flutter 3.44 才有的 API（`onReorderItem`、`SizeTransition.alignment`、`PageView.scrollCacheExtent`），3.41 无法编译。故改用唯一满足框架 ≥3.44 的 OHOS 构建 canary。代价见 §7.5 第 2 条。

推翻依据（`onReorderItem` 逐 SDK 统计）：

| SDK | `onReorderItem` | `onReorder`（旧名） |
|---|---|---|
| `3.41.10-ohos-1.0.1` | **0** | 15 |
| `3.44.5`（官方，当前在用） | **30** | 18 |

**被否决的候选**（均需决策、未执行；均以 `3.44.9+ohos-0.0.1-canary1` 为前提；最终选定 §7.2 的本地 shim）：

1. **给预编译 HAR 打补丁**，把 16 处 `autoFillManager.*` 换成 `oh_modules` 内的本地类型别名。`requestAutoFill` 是运行期调用，Turna 无 autofill 表单故永不触发；但每次 `ohpm install` / `flutter clean` 都要重打，且与 §2.6「不引入 fork 补丁工具链」直接冲突——采用它等于修改本 ADR
2. **从仓库源码自建 `flutter_ohos` 包**。embedder 的 ArkTS 源码在 `engine/src/flutter/shell/platform/ohos/flutter_embedding/`，可 pin 到与 canary tag 同一 commit；Windows 编不了的是 engine 的 C++，不是这个 ArkTS 包（它只需 engine 产物里的 `libflutter.so`）。补丁落在本仓库内、受评审、可版本控制，与候选 1 的机器级重打是两种维护形态。但需先摸清 ohpm 打包与 `libflutter` 的 `.d.ts` 处理，**未验证**
3. 等待上游 `@ohos/flutter_ohos` 跟进 API 26 并发布 3.44 线的 stable（不在本仓库可控范围；对应下方的撤销条件）

**净结论**：当时不存在同时满足「框架 ≥3.44」与「embedder 无 autofill 缺陷」的 OHOS Flutter 构建——这是上游缺口，不是本仓库能自行绕过的配置问题。§7.2 的本地 shim 是本仓库选定的解法。

**撤销条件**（任一成立则本 ADR 失效，原 EOL 断言自动重新生效，因为分支开关是 `ohos/` 是否存在）

- 上游发布适配 API 26 的 `material_ui` / `cupertino_ui`，§7.1 的 vendor 可以撤掉（**这是期望的结局，不是失败**）
- 上游 `@ohos/flutter_ohos` 跟进 API 26，§7.2 的 shim 可以撤掉
- 伴生版被迫引入 Official Anki 宿主或音频隐式降级（本 ADR §2 的两条硬边界）

## 演进记录（保留判断链）

W1 一度判 NO-GO，多次修正后才通过。留此节是因为**每次修正的方向都与预期相反**，后人重做时会踩同一遍：

1. **第一次误判：空格路径是头号地雷。** 实测 8.3 短名直接解决，且 DevEco 的 schema 与 `findBelongProjectPath` 都已重构，官方 FAQ 所述两处「需管理员改安装目录」的坑在本机**根本不存在**。
2. **第二次误判：`flutter --version` 首次引导卡死。** 实为 `flutter_tools` 快照编译，单独跑 21 秒完成。之所以像卡死，是 `shared.bat` 把该步输出重定向到 `NUL`，任何失败都看不见。
3. **第三次误判：真正的 embedding 产物是 `flutter.har`。** `flutter.har`（14.9 MB）是**旧版**产物；实际被 `oh-package-lock.json5` 解析到的是 `flutter_embedding_<mode>.har`（252 KB，纯 ArkTS 源码，不含 `.so`）。认错这一个文件会浪费一整轮。
4. **第四次误判：最新 stable 能当基线。** 本项目代码用了 Flutter 3.44 才有的 API，3.41 编不过；能编 Material 的 3.41 与满足框架需求的 3.44 canary **不重合**。

## 影响与边界

- `ohos_eol_architecture_guard_test.dart` 由「禁 OHOS 存在」改为「OHOS 存在时必须落在伴生范围内」，测试数变化记入 `test/BASELINE.md`
- 活跃文档（README / AGENTS / project-guide）需按伴生范围更新措辞，且避开 ratchet 的 needle 字面
- Android / iOS 构建与测试不得出现回归
- 鸿蒙构建不进主 CI，单独 workflow
