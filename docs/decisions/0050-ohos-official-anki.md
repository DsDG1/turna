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

鸿蒙 fork SDK 提供原生 PlatformView：

- Dart 侧 `packages/flutter/lib/src/widgets/platform_view.dart` 导出 `OhosView`
- ArkTS 侧 embedding 含 `PlatformViewsControllerHybrid.ets`、
  `PlatformViewFactory.ets`、`PlatformViewWrapper.ets`、
  `PlatformViewRegistryImpl.ets`，经 `NodeRenderType` +
  `EmbeddingNodeController` 合成，并有 `HybridCompositionHandler` /
  `showOverlaySurfaceHybrid()`

**因此官方路径不需要 `webview_flutter`**，§5.4 保持原样。移植目标是 ArkTS
（`XComponent` / `Web` 组件 + `onUrlRequestIntercept`），不是 Kotlin / Swift 逐行翻译。
参照规模：Android 侧 `OfficialAnkiReviewerPlatformView.kt` 441 行 +
media/scheme/mime 辅助约 390 行；iOS 侧 `OfficialAnkiReviewerView.swift` 492 +
`OfficialAnkiSchemeHandler.swift` 309 + factory 45。

**未验证前提（施工前必须先打点，不得由「有 `OhosView`」外推）：**

1. `Platform.operatingSystem == 'ohos'` —— 目前**只有代码注释作证**
   （`official_anki_composition.dart` 的 `initializeReadOnlyLocator`）。若该值不成立，
   所有 `Platform.is*` 判断的写法都要重估。
2. `OhosView` 只有合成模式（`PlatformViewsControllerHybrid`），Android 侧
   `_hcpp` 有 `initHybridAndroidView` / `initExpensiveAndroidView` 两条分支。
   合成模式下的滚动、手势、透明区表现是否等价，**无法靠读代码判定**。
3. ArkUI `Web` 组件能否满足复习器的 CSP（`assets/anki_reviewer/card-frame.html`
   为 `default-src 'none'`）+ 自定义 scheme + 媒体 Range/206。

## 4. 两个真实技术缺口（决策无法消解，须在接线批次解决）

### 4.1 catalog 存储：需要一份独立的 `libsqlite3.so`

`ensureOfficialAnkiSqlite()`（`lib/application/anki_official/storage/official_anki_sqlite.dart`）
只覆盖 Linux / Android。鸿蒙上 sqlite3 的 loader 抛 `Unsupported platform: ohos`。

**这不是引擎的依赖问题**：bridge 内的 SQLite 是 `bundled`，静态编入 `.so`，
`verify_bridge_symbols.sh` 反向断言 `libsqlite3.so` 不得出现。缺的是 **Turna 侧
共享 catalog**（`OfficialAnkiDatabase`）那份独立 FFI 库，须随 hap 分发。

修法：注册 `OperatingSystem.ohos` override + 随 hap 打包一份 `libsqlite3.so`。

### 4.2 平台判断写法

`Platform.is*` 在鸿蒙上**全为 false**（§2 前提 1）。因此新增的鸿蒙接线必须走
`isHarmonyOsTarget`（`lib/core/ohos_target.dart`），不得内联 `Platform.is*`
比较——这正是 ADR 0047 与 `ohos_target_test.dart` 已经确立的单一谓词纪律。
`ohos_eol_architecture_guard_test.dart` 的「capability checks 走单一谓词」断言
**保留有效**。

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
| 0 | 真机探针：打点 `Platform.operatingSystem` / `isHarmonyOsTarget` / `Platform.is*` / catalog 打开结果，把 §3 前提 1 变成收据 | — |
| 1 | `.so` 装进 `ohos/entry/libs/arm64-v8a/` + 构建接线；`resolveOfficialAnkiLibraryPath` 加 ohos 分支 | 步 0 |
| 2 | sqlite override + 独立 `libsqlite3.so` 随 hap 分发 | 步 1 |
| 3 | 平台路由：`OfficialAnkiCapabilityMatrix._hostPlatform` / `forPlatform`、`AnkiImportExecutionPlanner.productModeFor`、`OfficialAnkiCompositionRoot.probe` | 步 1–2 |
| 4 | 撤 `OhosDegradation.officialAnki` + `OfficialAnkiNativeAvailability` 的 ohos 分支 | 步 3 |
| 5 | ArkTS reviewer 插件（`OhosView` 工厂 + `Web` 组件 + 媒体 Range/206），登记进 `EntryAbility`，并入 `_requiredOhosFiles` | 步 1 |
| 6 | 独立 CI workflow（ADR 0047 承诺但尚未存在） | 步 1–5 |

步 5 的验收判据是 §3 的三条未验证前提全部转为真机收据。任一条不成立则保真档位
不成立，届时回到「文本降级」档并修订本文。

## 后果

- ADR 0041 §决策 2 与 ADR 0047 §2 第 2 条作废；两份 ADR 须加本文的修订指针
- 官方 Anki 状态真源（`docs/official-anki-migration/34-cutover-receipt.md`）须记本批
- 平台矩阵（`docs/project-guide.md` §10.1）与 `docs/android-build-setup.md` 的退役节
  须按「Anki 已授权、接线未完成」改写，不得写成已支持
- `test/BASELINE.md` 前插一条收据
- Android / iOS 行为不得回归：`flutter analyze` 0 issue，
  `flutter test --exclude-tags golden` 保持 0 failed
