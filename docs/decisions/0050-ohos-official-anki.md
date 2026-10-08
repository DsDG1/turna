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

### 2.1 平台身份收据（2026-10-08，步 0 完成）

真机 Mate 90 Pro Max（CMM-AL10，HarmonyOS 7.0.0.109，API 26），fork SDK
`3.44.9+ohos-0.0.1-canary1` 编 `entry-default-signed.hap` 装机后读启动日志，
探针见 `lib/service/app_startup.dart` 的 `[OhosProbe]`、catalog 探针为
`probeOfficialAnkiSqlite()`（`official_anki_sqlite.dart`，只读 + `openInMemory`）：

```
operatingSystem=ohos
defaultTargetPlatform=ohos
isHarmonyOsTarget=true
isAndroid=false isIOS=false isLinux=false isMacOS=false isWindows=false
degradations=officialAnki,remoteBackup

ankiLibraryResolved=<null>
runtimeOk=false reason=unsupported_platform abi=null
catalog=throw UnsupportedError: Unsupported operation: Unsupported platform: ohos
```

四条推论，均为收据而非推断：

1. `Platform.operatingSystem` 真值是 `"ohos"`（**§3 未验证前提 1 已结**）。
2. `Platform.is*` 在鸿蒙上**全为 false**，与 §4.4 的纪律一致。
3. `isHarmonyOsTarget` 在真机上为 `true`，故 §4.1 的 `overrideForAll` 短路条件
可以用它——若换成 `Platform.*` 判断，Android / iOS 会被污染。
4. **catalog 在鸿蒙上当前就是打不开的**，不是「可能失败」。§4.1 预判的错误文本
   逐字命中，机制同时被证实：`sqlite3-2.9.4` 的 `load_library.dart` 里
   `OperatingSystem? get os` 是六项 `Platform.is*` if 链，全 false → `null` →
   `ensureOfficialAnkiSqlite()` 注册的表根本查不到 → 落到 `_defaultOpen()` 末尾
   抛出。无 `OperatingSystem.ohos` 注册位。

**本节收据之后被步 1 改变的**（2026-10-08，见 §4.3）：`ankiLibraryResolved` 从
`<null>` 变为 `libturna_anki.so`。**仍未改变**：`reason=unsupported_platform`
——能力矩阵仍在 `official_anki_composition.dart` 用 `Platform.is*` 硬拒鸿蒙，
属步 3/4。这正是需要绕开矩阵才能测 `dlopen` 的原因（§4.2）。

**关于 `Platform.operatingSystemVersion`**：真机返回
`HarmonyOS HongMeng Kernel 1.13.0 #1 SMP Tue Sep 29 12:53:48 UTC 2026`，
即 **uname 风格字符串，不是 API level**。§4.2 的 API 落差不能靠它判断。

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

1. ~~`Platform.operatingSystem == 'ohos'` —— 目前只有代码注释作证~~
   **（2026-10-08 已结，见 §2.1）**——真机收据确认为 `"ohos"`，`isHarmonyOsTarget`
   为 `true`，`Platform.is*` 全 false。原注释（`official_anki_composition.dart`
   的 `initializeReadOnlyLocator`）从此有了实证后盾，`Platform.is*` 的写法不需要
   重估。
2. 三路合成模式齐备**不等于**行为等价：Android 侧 `_hcpp` 先探
   `HybridAndroidViewController.checkIfSupported()` 再在两条分支间选择，鸿蒙侧
   `OhosViewController` 无对应的 `checkIfSupported`。选哪一路、滚动 / 手势 /
   透明区表现是否等价，**无法靠读代码判定**。
3. ArkUI `Web` 组件能否满足复习器的 CSP（`assets/anki_reviewer/card-frame.html`
   为 `default-src 'none'`）+ 自定义 scheme + 媒体 Range/206。

## 4. 三个真实技术缺口（决策无法消解，须在接线批次解决）

**4.1、4.2 已于 2026-10-08 结清**（真机收据见各节）；4.3 记步 1 已交付的静态部分，
4.4 是贯穿全部接线批次的纪律。**步 3 的能力矩阵硬拒与步 4 的降级标记已于同日拆除**
（`runtimeOk=true reason=ready`，`degradations=remoteBackup`）。

**步 0–4 完成后伴生版的实际边界**（这是「已授权」的准确含义）：

| 能力 | 鸿蒙状态 | 依据 |
|---|---|---|
| `.apkg` 导入 | 可用 | `productModeFor('ohos')` → 官方档 |
| 课程树投影 / SRS 调度 | 可用 | `runtimeOk=true reason=ready`，`officialCore=true` |
| 共享 catalog | 可用 | `catalog=ok sqlite=3.49.2` |
| **保真复习器（原卡渲染）** | **不可用，响亮失败** | 步 5b 未做；见下 |

**保真复习器在鸿蒙上会渲染不出来**（ArkTS PlatformView 是步 5b）。该失败**故意
不通过禁用入口来掩盖**：入口开着，卡片渲染时给出明确文案
（`official_anki.renderer_ohos_pending`，说明「组件尚未提供、导入与调度不受影响」）。
**理由**：一个「点了没反应」的入口比一个不存在的入口更难归因——用户无法判断坏的是
哪一半。文案里**刻意不用「未启用」**，因为鸿蒙上没有任何东西被关闭，说「未启用」
会把用户引去找一个不存在的开关，并把「缺一个平台组件」这件事藏起来。

这条失败路径**只经代码验证，未在真机上触发过**（需用户导入 `.apkg` 并进入卡片，
本批未走 UI）。

### 4.1 catalog 存储：需要一份独立的 `libsqlite3.so`，且分派方式要重写 —— **已结**

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

**已实施并取得真机收据（2026-10-08）**：新增
`native/turna_anki_core/build-ohos/build-sqlite.sh` 交叉编译 `libsqlite3.so`
（SQLite **3.49.2**，源码取自 cargo registry 里 `libsqlite3-sys-0.34.0` 随附的
amalgamation——**与引擎编译用的是同一份**，故 catalog 与引擎不会在版本上漂移）。
产物 1,126,840 字节，`NEEDED` 只有 `libc.so`，已提交进
`ohos/entry/libs/arm64-v8a/libsqlite3.so`（同路线 A）。

编译选项刻意保守：默认 amalgamation 构建，**不开** FTS5 与 JSON1——`lib/` 中
两者都无引用（已核），缺了会在 prepare 时响亮失败，半残的扩展不会。

真机收据：`catalog=ok sqlite=3.49.2`（此前是
`catalog=throw UnsupportedError: Unsupported operation: Unsupported platform: ohos`）。
**版本号由库自身返回，故这条同时证明加载的正是我们编的那份**，而不是系统里的某个
同名库。

新增门禁 `test/application/anki_official/official_anki_sqlite_dispatch_test.dart`
（**5 例**），逐条钉住上面那份「改动面」清单：短路在幂等标志之前、守卫是单一谓词而非
`Platform.*`、没有伪造 `OperatingSystem.ohos`、`overrideForAll` 全局只有一处且在守卫
内、Linux/Android 的 per-platform override 仍在、hap 内 `libsqlite3.so` 是 aarch64
且导出核心符号。四种错误改法（幂等提前 / `Platform.isLinux` 守卫 / 伪造枚举 /
无守卫全局注册）**逐个反向验证都会红**。

> **写这道门禁时踩的坑**：断言若直接扫源码全文，会命中**本文件自己的注释**——
> 分支的注释正解释了「为什么不用 `Platform.is*`」与「为什么不能用 `overrideFor`」，
> 于是这两个标识符必然出现。故门禁对去注释后的代码提问（`ensureCode`）。
> 这不是洁癖：不先去注释，这两条断言在正确实现下也无法通过。

### 4.2 hap 声明的最低 API 与 sysroot 存在落差 —— **已结，无落差**

`ohos/build-profile.json5` 的 `compatibleSdkVersion` 为 `5.1.0(18)`，而本机
OHOS native sysroot 是 API 26（ADR 0047 §7.4 记录的 DS-243 单档 SDK）。对
`libturna_anki.so` 逐串核过：含 `OH_TimeService_GetTimeZone` / `dlopen` /
`pthread_create`，**不含** `__android_log_print` / `__system_property_get`，
暂未发现会在 API 18 设备上炸的符号。

**但这只是静态字符串检查，不是收据。** 步 1 打包后须在真机上确认 hap 声明的最低
API 与引擎 `.so` 的实际最低需求一致，否则装机即 `dlopen` 失败。

**2026-10-08 真机收据：`dlopen=ok abi=1 path=libturna_anki.so`**
（Mate 90 Pro Max / API 26，装 `entry-default-signed.hap`）。**API 18 的声明可以加载
API 26 编译的引擎，落差不成立。** 这条收据的强度在于 `dlopen` 成功即意味着**全部
重定位已解析**——`NEEDED` 的 `libc.so` 与 `libtime_service_ndk.so` 都拿到了，
且 `turna_anki_abi_version` 真的被查到了，不是「符号碰巧没被用到」。

**但拿这条收据必须绕开能力矩阵。** `OfficialAnkiCompositionRoot.probe` 在
`official_anki_composition.dart` 用 `Platform.isAndroid || isIOS || isLinux ||
isMacOS` 硬拒鸿蒙，引擎**到不了 loader**，故 `runtimeOk=false
reason=unsupported_platform` 与「dlopen 失败」在日志上无法区分（同一次收据里
两者并存）。为此新增 `OfficialAnkiNativeTransport.probeDlopen()`：直接
`DynamicLibrary.open` + 只查 ABI 符号，不开也不关任何引擎句柄。

这也说明**能力矩阵的 ohos 硬拒本身就是下一步要拆的东西**（§6 步 3/4），
不是可以留着当保险的兜底——它现在挡住的正是唯一能回答 API 问题的那条路径。

### 4.3 步 1 静态侧已结的部分（2026-10-08）

`.so` 已提交进 `ohos/entry/libs/arm64-v8a/libturna_anki.so`（ADR 0050 §6 步 1，
路线 A：提交产物而非构建时拷贝——伴生版尚无 CI 作业，提交产物才可复现）。
SHA-256 `24CC49E3…F671E5`，23,123,056 字节。`flutter build hap` 成功，hap 内
`libs/arm64-v8a/libturna_anki.so` **18,882,664 字节**——hvigor 做了 strip，
故**不等于**源文件字节，但逐串核过**内容等价**：

- 8 个 bridge 符号全在：`turna_anki_abi_version` / `_engine_new` / `_engine_open` /
  `_call` / `_cancel` / `_engine_close` / `_buffer_free`，加 `turna_anki_core`
- `NEEDED` 仍只有 `libc.so` + `libtime_service_ndk.so`，**无 `libsqlite3.so`**
- ELF64 / `e_machine` = `0xB7`（aarch64）
- 仍**不含** `__android_log_print` / `__system_property_get`

**注意**：hap 内另有 x86_64 的 `libc++_shared.so` / `libonnxruntime.so` /
`libsherpa*.so`（sherpa-onnx 与 onnxruntime 插件自带，非本批引入）。
`libturna_anki.so` **只有 arm64-v8a 一份**——门禁按「`.so` 实际落点」而非目录名
断言（见下），因为模板留下一个空 `libs/x86_64/`，git 不跟踪空目录，按目录名断言会
在本地红、新克隆绿。

`resolveOfficialAnkiLibraryPath` 加 ohos 分支，返回裸名 `'libturna_anki.so'`
（hap 的 `libs/arm64-v8a` 在 loader 搜索路径上），分支条件是 `isHarmonyOsTarget` 而非
`Platform.*`——后者在鸿蒙恒 false，会让鸿蒙永远走不到这个分支。

**本节的缺口**：无。上一版记的「设备掉线、真机 `dlopen` 收据未取得」已由 §4.2 的
收据补齐。

### 4.4 平台判断写法

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

**该代价已于 2026-10-08 部分收回**（§6 步 3）：新增断言
`HarmonyOS routes to Official engine, not to unavailable`，方向与被移除的那条
**相反**——它要求鸿蒙**不得**落进 unsupported 桶。故「鸿蒙被误改成不可用」现在
会被拦；**「鸿蒙被误改回 Legacy 写路径」仍然无人拦**（`legacyFallbackRequired: true`
断言覆盖不到，因为官方路径根本不经过那个字段）。

**建议补的正门禁（本文不强制，留给接线批次）**：

- `ohos/` 目录级「不得出现未注册进 `EntryAbility` 的 PlatformView 工厂」——
  与既有「手写插件必须注册」断言同源，官方 reviewer 会引入第 5 个手写 ArkTS 插件
- 把 `.so` 纳入 `ohos/` artifact 检查 —— 当前 `ohos/.gitignore` 只忽略
  `libapp` / `libflutter` / `libvmservice`，把 23 MB 的 `libturna_anki.so` 放进
  `ohos/entry/libs/arm64-v8a/` **不会被任何门禁拦下**
  **（已做，2026-10-08）**——§6 步 1 落地时补了
  `companion hap ships the arm64 Anki engine in libs/arm64-v8a`，含 ABI 检查、
  arm64-only、commit-in-git 三项；步 2 的 `libsqlite3.so` 由
  `official_anki_sqlite_dispatch_test.dart` 覆盖

## 6. 接线批次（本文只授权，不含在本批）

按依赖顺序，每步都有独立可回滚边界：

| 步 | 内容 | 前置 |
|---|---|---|
| 0 | 真机探针：打点 `Platform.operatingSystem` / `isHarmonyOsTarget` / `Platform.is*` / catalog 打开结果 —— **已完成，收据见 §2.1（2026-10-08）** | — |
| 1 | `.so` 装进 `ohos/entry/libs/arm64-v8a/` + 构建接线；`resolveOfficialAnkiLibraryPath` 加 ohos 分支；真机确认 §4.2 的 API 落差 —— **已完成（2026-10-08，`dlopen=ok abi=1`）** | 步 0 |
| 2 | 重写 `ensureOfficialAnkiSqlite` 分派为 `overrideForAll`（§4.1）+ 独立 `libsqlite3.so` 随 hap 分发 —— **已完成（2026-10-08，`catalog=ok sqlite=3.49.2`）** | 步 1 |
| 3 | 平台路由：`OfficialAnkiCapabilityMatrix._hostPlatform` / `forPlatform`、`AnkiImportExecutionPlanner.productModeFor`、`OfficialAnkiCompositionRoot.probe` —— **已完成（2026-10-08，`runtimeOk=true reason=ready abi=1`）** | 步 1–2 |
| 4 | 撤 `OhosDegradation.officialAnki` + `OfficialAnkiNativeAvailability` 的 ohos 分支 —— **已完成（2026-10-08，`degradations=remoteBackup`）** | 步 3 |
| 5a | **先定 §3.1 的 Dart 接线路线**（拆分条件导出 / vendored 移植），否则 5b 无法开工 | 步 4 |
| 5b | ArkTS reviewer 插件（PlatformView 工厂 + `Web` 组件 + 媒体 Range/206），登记进 `EntryAbility`，并入 `_requiredOhosFiles` | 步 5a |
| 6 | 独立 CI workflow（ADR 0047 承诺但尚未存在） | 步 1–5b |

步 5b 的验收判据是 §3 的三条未验证前提全部转为真机收据——**前提 1 已于 2026-10-08
结清（§2.1），故实际只剩 2 与 3**（哪一路合成模式可用、ArkUI `Web` 能否满足 CSP +
自定义 scheme + 媒体 Range/206）。任一条不成立则保真档位不成立，届时回到「文本降级」
档并修订本文。

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
