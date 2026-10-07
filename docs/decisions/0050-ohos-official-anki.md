# ADR 0050 — 鸿蒙启用 Official Anki 全档（引擎 / 导入 / 投影 / 保真复习器）

- 状态：已接受（**决策层**；接线未施工）
- 日期：2026-10-07
- 修订：[ADR 0041](./0041-ohos-product-eol.md) §决策 2、[ADR 0047](./0047-ohos-companion-lite-build.md) §2 第 2 条
- 前置：[ADR 0046](./0046-ohos-anki-core-probe.md)（引擎层真机收据）、[ADR 0047](./0047-ohos-companion-lite-build.md)（伴生版授权）
- 编号说明：0049 之后的下一个可用编号。

## 决策

在鸿蒙伴生版上启用 **Official Anki 全档**：`libturna_anki.so` 引擎、`.apkg`
导入、课程树投影、保真复习器（PlatformView + WebView，HTML 不降级为文本）。

本 ADR **只授权，不施工**。它取代的是两条**范围排除**，不撤销伴生版本身
（[ADR 0047](./0047-ohos-companion-lite-build.md) 仍然有效，其 §1 课程 / SRS /
复习 / 词典 / 设置范围、§7 的自维护移植清单、§7.4–7.5 的长期成本全部不变）。

## 1. 修订的两条决策

| 原条款 | 处置 |
|---|---|
| ADR 0041 §决策 2「不建设 OHOS Official Anki Core」 | **作废**，由本文取代 |
| ADR 0047 §2 第 2 条「不启用 Official Anki 引擎与保真复习器：鸿蒙明确不可用」 | **作废**，由本文取代 |

### 不作废的条款

- **ADR 0041 §决策 1**（不再为 OHOS 构建 / 发布 / 适配）——伴生版仍不进主交付、
  不进主 CI（[ADR 0047](./0047-ohos-companion-lite-build.md) §1、§2 第 5 条）。
  本文授权的是**伴生版内部**开启 Anki，不是恢复产品线。
- **ADR 0041 §决策 3 / 4**（`tool/apply_patches.sh` 与 `tool/patches/` 保持删除）不变。
- **ADR 0041 §决策 5**（未知平台 → `ankiUnavailable`）不变——本文新增的是一个
  **已知**平台分支，不是把未知平台放开。
- **ADR 0047 §5.4**（`webview_flutter` 不得被 override）**无需解除**，理由见 §3。
- **ADR 0047 §5.8**（`ohos/` 不得出现 Official Anki 引擎宿主）**由本文取代**：
  引擎宿主正是本文要装进 `ohos/` 的东西。
- ADR 0047 的 sunset export 结论不变（[ADR 0041](./0041-ohos-product-eol.md)
  §Sunset export status）。

## 2. 已有证据（不是本文的新主张）

引擎层的可行性**已由 ADR 0046 收据确立**，本文只是据此推进产品接线：

- 交叉编译 `aarch64-unknown-linux-ohos`：`Finished release profile in 2m 39s`，
  无 feature 关闭、无 C 依赖失败、无补丁冲突
- `libturna_anki.so` 23,123,056 字节，`NEEDED` = `libc.so` +
  `libtime_service_ndk.so`，7 个 bridge 符号全导出，**无 `libsqlite3.so` 外部依赖**
- 真机（Mate 90 Pro Max，API 26，hap 进程内）：`dlopen` OK → `abi_version` 1 →
  `engine_new` status 0（内部 `touch_rslib()` 建内存 Collection）→ `engine_close` OK
- 工具链：`native/turna_anki_core/build-ohos/`，可复跑

**明确未被上列证据覆盖的**（ADR 0046 §范围边界原文）：磁盘 collection 打开、
调度器真实负载、导入链路、卡片渲染。本文授权范围**包含**这四项，因此它们是
下一批的施工对象与验收项，不是本文的既成结论。

## 3. 保真复习器走 PlatformView，不碰 `webview_flutter`

这一条决定了 ADR 0047 §5.4 无需解除，因此也决定了工作量口径。

**两条不同的路，历史上容易混淆：**

| 路径 | 实现 | 现状 |
|---|---|---|
| 旧 Anki 保真 | `lib/views/anki/anki_html_card_view.dart` → `webview_flutter` | 鸿蒙无实现 |
| **官方 Anki 保真** | `lib/views/anki_official/official_anki_reviewer_view.dart` → `PlatformViewLink`（Android）/ `UiKitView`（iOS） | 鸿蒙**有**等价物 |

鸿蒙 fork SDK 提供原生 PlatformView，且**三路合成模式齐备**，与 Android 对称：

| Dart 侧入口 | 控制器 | Android 对应 |
|---|---|---|
| `PlatformViewsService.initOhosView` | `TextureOhosViewController` | `initAndroidView`（TLHC） |
| `PlatformViewsService.initSurfaceOhosView` | `SurfaceOhosViewController` | `initSurfaceAndroidView` |
| `PlatformViewsService.initExpensiveOhosView` | `ExpensiveOhosViewController` | `initExpensiveAndroidView` / `initHybridAndroidView` |

Widget 侧另有 `OhosView` / `OhosViewSurface`。ArkTS 侧 embedding 含
`PlatformViewsControllerHybrid.ets`、`PlatformViewFactory.ets`、
`PlatformViewWrapper.ets`、`PlatformViewRegistryImpl.ets`，经 `NodeRenderType` +
`EmbeddingNodeController` 合成，并有 `HybridCompositionHandler` /
`showOverlaySurfaceHybrid()`。

**因此官方路径不需要 `webview_flutter`**，§5.4 保持原样。原生侧移植目标是 ArkTS
（`XComponent` / `Web` 组件 + `onUrlRequestIntercept`），不是 Kotlin / Swift 逐行翻译。
参照规模：Android 侧 `OfficialAnkiReviewerPlatformView.kt` 441 行 +
media/scheme/mime 辅助约 390 行；iOS 侧 `OfficialAnkiReviewerView.swift` 492 +
`OfficialAnkiSchemeHandler.swift` 309 + factory 45。

### 3.1 但 Dart 侧接线有第二道关：`Ohos*` 标识符在官方 SDK 下不存在

> **（2026-10-07 订正）** 本节初稿写「保真档位比 ADR 0047 估的便宜」，**该结论不成立**，
> 依据是把「平台有原生 PlatformView」当成了「Dart 侧能低成本引用」。

官方 SDK 的 `packages/flutter/lib/src/widgets/platform_view.dart` 里**没有任何
`Ohos*` 标识符**。实测引用 `OhosViewController` 于官方 SDK 下：

```
error - Undefined class 'OhosViewController'.
```

`dependency_overrides` 全局无平台条件（ADR 0047 §7.1 已记录该约束），因此在 `lib/`
里直接写 `OhosViewController` / `initOhosView` 会让 **Android/iOS 构建与全部
测试同时崩**——与 ADR 0047 §7.1 描述的失败类**完全同源**（那次是
`case TargetPlatform.ohos:`，这次是 `Ohos*` 类名）。

可行路线二选一，需在步 5 前定：

| 方案 | 做法 | 代价 |
|---|---|---|
| **A. 拆分 + 条件导出** | 把 reviewer 视图按平台拆文件，鸿蒙专用部分只由鸿蒙 target 导入 | Dart 侧无符号泄漏，但视图需按平台分叉 |
| **B. 再做一次 vendored 移植** | 照 ADR 0047 §7.1 的通配 arm 手法承载 `Ohos*` | 同一套移植工具与 ratchet，但要为 Flutter 框架类做（体量与 `material_ui` 不同量级） |

**§6 步 5 的工作量估算必须重估**：ADR 0047 的「复习器 5–8 人日」不含这一关。
在路线定下来之前，不得引用该数字作为鸿蒙复习器的预算。

**未验证前提（施工前必须先打点，不得由「有 `OhosView`」外推）：**

1. `Platform.operatingSystem == 'ohos'` —— 目前**只有代码注释作证**
   （`official_anki_composition.dart` 的 `initializeReadOnlyLocator`）。若该值不成立，
   所有 `Platform.is*` 判断的写法都要重估。
2. 三路合成模式齐备**不等于**行为等价：Android 侧 `_hcpp` 先探
   `HybridAndroidViewController.checkIfSupported()` 再在两条分支间选择，鸿蒙侧
   `OhosViewController` 无对应的 `checkIfSupported`。选哪一路、滚动 / 手势 /
   透明区表现是否等价，**无法靠读代码判定**。
3. ArkUI `Web` 组件能否满足复习器的 CSP（`assets/anki_reviewer/card-frame.html`
   为 `default-src 'none'`）+ 自定义 scheme + 媒体 Range/206。

## 4. 三个真实技术缺口（决策无法消解，须在接线批次解决）

### 4.1 catalog 存储：需要一份独立的 `libsqlite3.so`，且分派方式要重写

`ensureOfficialAnkiSqlite()`（`lib/application/anki_official/storage/official_anki_sqlite.dart`）
只覆盖 Linux / Android。鸿蒙上 sqlite3 的 loader 抛 `Unsupported platform: ohos`。

**这不是引擎的依赖问题**：bridge 内的 SQLite 是 `bundled`，静态编入 `.so`，
`verify_bridge_symbols.sh` 反向断言 `libsqlite3.so` 不得出现。缺的是 **Turna 侧
共享 catalog**（`OfficialAnkiDatabase`）那份独立 FFI 库，须随 hap 分发。

> **（2026-10-07 订正）** 本节初稿写「注册 `OperatingSystem.ohos` override」——
> **该枚举值不存在**，照此实施会编译失败。

`sqlite3-2.9.4` 的 `lib/src/ffi/load_library.dart` 中：

```dart
enum OperatingSystem { android, linux, iOS, macOS, windows, fuchsia }
```

没有 `ohos`。`OpenDynamicLibrary.os` 是一条 `if` 链，六个 `Platform.is*` 在鸿蒙上
全 false 时返回 `null`；`_overriddenPlatforms[null]` 永不命中，最终落到
`_defaultOpen()` 末行抛 `UnsupportedError`。**所以那行注释里的报错属实，但机制不是
「缺一个枚举值可注册」，而是没有 `OperatingSystem.ohos` 这个注册位存在。**

唯一可用入口是 `open.overrideForAll()`，它不做平台分派、全平台生效。因此修法是
**重写分派方式**而非新增一条 override：

```dart
if (isHarmonyOsTarget) {
  open.overrideForAll(_openHarmonyOsSqlite);
  return;
}
// 其余平台保持现有 overrideFor 分支
```

**改动面比初稿描述的大**，须一并记入：

- `ensureOfficialAnkiSqlite()` 有 **11 处调用点**，含
  `lib/service/locator.dart` 的主 isolate 调用与作为
  `NativeDatabase.createInBackground(isolateSetup:)` 参数的后台 isolate 调用
- `overrideForAll` 与 `overrideFor` 一样是 **per-isolate 状态**，跨 isolate 需各自注册
- 短路必须发生在 `_opened` 幂等标志**之前**，否则鸿蒙上第二次调用会被幂等吞掉
- `overrideForAll` 一旦误注册会在 Android/iOS 上也生效，故短路条件必须是
  `isHarmonyOsTarget` 而非 `Platform.*`

### 4.2 hap 声明的最低 API 与 sysroot 存在落差（尚无收据）

`ohos/build-profile.json5` 的 `compatibleSdkVersion` 为 `5.1.0(18)`，而本机
OHOS native sysroot 是 API 26（ADR 0047 §7.4 记录的 DS-243 单档 SDK）。对
`libturna_anki.so` 逐串核过：含 `OH_TimeService_GetTimeZone` / `dlopen` /
`pthread_create`，**不含** `__android_log_print` / `__system_property_get`，
暂未发现会在 API 18 设备上炸的符号。

**但这只是静态字符串检查，不是收据。** 步 1 打包后须在真机上确认 hap 声明的最低
API 与引擎 `.so` 的实际最低需求一致，否则装机即 `dlopen` 失败。

### 4.3 平台判断写法

`Platform.is*` 在鸿蒙上**全为 false**（§3 未验证前提 1）。因此新增的鸿蒙接线必须走
`isHarmonyOsTarget`（`lib/core/ohos_target.dart`），不得内联 `Platform.is*`
比较——这正是 ADR 0047 与 `ohos_target_test.dart` 已经确立的单一谓词纪律。
`ohos_eol_architecture_guard_test.dart` 的「capability checks 走单一谓词」断言
**保留有效**。这也是 §4.1 里 `overrideForAll` 短路条件必须用 `isHarmonyOsTarget`
而非 `Platform.*` 的原因。

## 5. 门禁处置：**移除**而非重写（显式决策，非疏漏）

ADR 0046 §副作用写明：「若将来真的推进鸿蒙产品线，必须先撤销 ADR 0041 并重写门禁，
不能靠加白名单绕过。」本文执行了「撤销 ADR 0041 §决策 2」，但**选择移除相关断言
而不是把它们改写成二态 ratchet**。

移除的断言：

1. `ohos_eol_architecture_guard_test.dart` 的
   `capability matrix never requires Legacy fallback writers` 中
   「不得出现 `case 'ohos':`」一条 —— 原为无条件断言
2. `anki_import_execution_plan_test.dart` 中把 `'ohos'` 列进
   `ankiUnavailable` / `unsupported` 的三处

**保留的断言**（与本文无冲突）：

- `legacyFallbackRequired: true` 不得出现（`legacyFallbackRequired` 语义未被本文改变）
- `official_anki_architecture_guard_test.dart` 对
  `anki_import_execution_plan_test.dart` 的存在性与 `unsupported` /
  `writesLegacyNoteStore` 断言
- 「OHOS capability checks 走单一谓词」断言
- ADR 0047 §5 的 override ratchet（含 §5.4 `webview_flutter` 禁 override）
- ADR 0047 §5.7 的 `ohos/` 必需文件集（新增 ArkTS 插件须并入 `_requiredOhosFiles`）

**已知代价（接受）**：移除后，「鸿蒙不得启用 Official Anki」不再有任何自动化保护。
后续若有人误改鸿蒙分支，门禁不会拦。本文即该决策的唯一记录。

**建议补的正门禁（本文不强制，留给接线批次）**：

- `ohos/` 目录级「不得出现未注册进 `EntryAbility` 的 PlatformView 工厂」——
  与既有「手写插件必须注册」断言同源，官方 reviewer 会引入第 5 个手写 ArkTS 插件
- 把 `.so` 纳入 `ohos/` artifact 检查 —— 当前 `ohos/.gitignore` 只忽略
  `libapp` / `libflutter` / `libvmservice`，把 23 MB 的 `libturna_anki.so` 放进
  `ohos/entry/libs/arm64-v8a/` **不会被任何门禁拦下**

## 6. 接线批次（本文只授权，不含在本批）

按依赖顺序，每步都有独立可回滚边界：

| 步 | 内容 | 前置 |
|---|---|---|
| 0 | 真机探针：打点 `Platform.operatingSystem` / `isHarmonyOsTarget` / `Platform.is*` / catalog 打开结果，把 §3 未验证前提 1 变成收据 | — |
| 1 | `.so` 装进 `ohos/entry/libs/arm64-v8a/` + 构建接线；`resolveOfficialAnkiLibraryPath` 加 ohos 分支；真机确认 §4.2 的 API 落差 | 步 0 |
| 2 | 重写 `ensureOfficialAnkiSqlite` 分派为 `overrideForAll`（§4.1）+ 独立 `libsqlite3.so` 随 hap 分发 | 步 1 |
| 3 | 平台路由：`OfficialAnkiCapabilityMatrix._hostPlatform` / `forPlatform`、`AnkiImportExecutionPlanner.productModeFor`、`OfficialAnkiCompositionRoot.probe` | 步 1–2 |
| 4 | 撤 `OhosDegradation.officialAnki` + `OfficialAnkiNativeAvailability` 的 ohos 分支 | 步 3 |
| 5a | **先定 §3.1 的 Dart 接线路线**（拆分条件导出 / vendored 移植），否则 5b 无法开工 | 步 4 |
| 5b | ArkTS reviewer 插件（PlatformView 工厂 + `Web` 组件 + 媒体 Range/206），登记进 `EntryAbility`，并入 `_requiredOhosFiles` | 步 5a |
| 6 | 独立 CI workflow（ADR 0047 承诺但尚未存在） | 步 1–5b |

步 5b 的验收判据是 §3 的三条未验证前提全部转为真机收据。任一条不成立则保真档位
不成立，届时回到「文本降级」档并修订本文。

**§3.1 是本表最大的不确定项**，且 ADR 0047 的「复习器 5–8 人日」不含它。在 5a
定档之前不得引用该数字作为预算。

## 后果

- ADR 0041 §决策 2 与 ADR 0047 §2 第 2 条作废；两份 ADR 须加本文的修订指针
- 官方 Anki 状态真源（`docs/official-anki-migration/34-cutover-receipt.md`）须记本批
- 平台矩阵（`docs/project-guide.md` §10.1）与 `docs/android-build-setup.md` 的退役节
  须按「Anki 已授权、接线未完成」改写，不得写成已支持
- `test/BASELINE.md` 前插一条收据
- Android / iOS 行为不得回归：`flutter analyze` 0 issue，
  `flutter test --exclude-tags golden` 保持 0 failed
