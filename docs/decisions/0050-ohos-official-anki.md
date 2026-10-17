# ADR 0050 — 鸿蒙启用 Official Anki 全档（引擎 / 导入 / 投影 / 保真复习器）

- 状态：已接受（**决策层**；接线步 0–5b 已施工——步 0–4 于 2026-10-08 取得真机收据（§4 与 §6 步表），步 5b 于 2026-10-14 夜取得真机首卡收据（§3.7）；步 6 独立 CI workflow 已于 2026-10-15 落库，首跑收据待取）
- 日期：2026-10-07
- 修订：[ADR 0041](./0041-ohos-product-eol.md) §决策 2、[ADR 0047](./0047-ohos-companion-lite-build.md) §2 第 2 条
- 前置：[ADR 0046](./0046-ohos-anki-core-probe.md)（引擎层真机收据）、[ADR 0047](./0047-ohos-companion-lite-build.md)（伴生版授权）
- 编号说明：0049 之后的下一个可用编号。

## 决策

> 2026-10-13 调用链订正：此前内存 catalog / engine-info 探针不覆盖真实
> 冷启动、导入与正式复习。真实 locator 和正式复习接缝已补修，详见
> [34 收据](../official-anki-migration/34-cutover-receipt.md)「鸿蒙生产调用链修复」。
> 2026-10-14 夜：步 5b 完成并取得真机首卡收据（§3.7）；
> 2026-10-15：步 6 独立 CI workflow 落库，首跑收据待取；
> API 26 加载收据不等于最低 API 18 兼容收据。

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

### 3.1 Dart 侧接线：A / B / D 三条路线均被真机收据否决，改走 E

> **（2026-10-07 订正）** 本节初稿写「保真档位比 ADR 0047 估的便宜」，**该结论不成立**，
> 依据是把「平台有原生 PlatformView」当成了「Dart 侧能低成本引用」。
>
> **（2026-10-08 终局）** 初稿列的 A / B 两案**已用真机收据逐条否决**，本节改记
> 路线 **E**。初稿的 A 案前提本身就是错的。

官方 SDK 的 `packages/flutter/lib/src/widgets/platform_view.dart` 里**没有任何
`Ohos*` 标识符**。实测引用 `OhosViewController` 于官方 SDK 下：

```
error - Undefined class 'OhosViewController'.
```

`dependency_overrides` 全局无平台条件（ADR 0047 §7.1 已记录该约束），因此在 `lib/`
里直接写 `OhosViewController` / `initOhosView` 会让 **Android/iOS 构建与全部
测试同时崩**——与 ADR 0047 §7.1 描述的失败类**完全同源**（那次是
`case TargetPlatform.ohos:`，这次是 `Ohos*` 类名）。

#### 三条路线的否决收据（2026-10-08，Mate 90 Pro Max / API 26）

| 路线 | 设想 | 收据 | 判定 |
|---|---|---|---|
| **A** 条件导出 | 用 `dart.library.ohos` 切出只含鸿蒙分支的文件 | `branch=BRANCH_IO` | **前提不存在**：OHOS 目标**不定义** `dart.library.ohos`，条件直接落到 `dart.library.io` |
| **D** dynamic 派发 | 文件里不写任何 `Ohos*`，把 `PlatformViewsService` 当 `dynamic` 调 | `NoSuchMethodError: Class 'Type' has no instance method 'initOhosView'`<br>`Found: initOhosView({required int id, ...}) => OhosViewController` | **Dart 不能动态调用静态方法**；而 `PlatformViewsService` 是 class，动态派发按实例方法查找 |
| **B** vendored 移植 | 照 ADR 0047 §7.1 手法承载 `Ohos*` | — | **规模不可接受**：`dependency_overrides` 确实能把 `flutter` 指向本地路径，但那是**把整个 Flutter 框架 vendored 进仓库**（现状 `third_party/` 只有 `material_ui` 与 `cupertino_ui`），且需先废 ADR 0041 §决策 4/5 |

**A 与 D 的根本障碍是同一个**：`Ohos*` 与 `AndroidViewController` 位于**同一个
library**（`package:flutter/services.dart`）。条件导出只能切 import，**切不开同一
个库内部的类**。另两条独立事实一并核实：

- `PlatformViewSurface` 的构造签名是通用的 `PlatformViewController`，**不含
  `Ohos*`** —— 障碍在 controller 的**创建**，不在 widget 的使用。
- `PlatformViewLink` 的 `surfaceFactory` 与 `onCreatePlatformView` **都是必填**，没有
  默认创建路径，故框架无法替我们造 controller。

**D 的收据另有一层价值**：Dart 在报错里回显了 `initOhosView` 的**完整签名**，据此
确认该入口在设备上确实存在（§3 未验证前提 2 的一部分）。

#### 路线 E（已定）：复习器做成独立 ArkUI 页面

**Dart 侧不创建任何 PlatformView**，因此 `Ohos*` 这个问题整体消失 —— 不需要条件
导出、不需要 vendored 移植、不需要改 SDK，也**不需要废任何现行 ADR**。

它是仓库里**第 5 个手写 ArkTS 插件**（继 `RdbPlugin` / `AudioPlugin` /
`TtsPlugin` / `FilePickerPlugin` 之后），沿用既有的 MethodChannel + `EntryAbility`
显式注册范式，须并入 `_requiredOhosFiles`（ADR 0050 §5 已列该要求）。

**交互形态（用户拍定）**：**整页原生页面，翻卡在同一页内完成**。进入复习即切到
ArkUI 页面，卡片间切换全部在原生页内完成；Dart 只负责下发卡片数据与接收判定。

**为什么在动线上选原生页而不是嵌入式 PlatformView**（这是 E 相对 A/B/C 的独立
收益，不只是绕过编译障碍）：

| 合成路径 | 每帧代价 |
|---|---|
| PlatformView texture 档 | 原生视图渲到虚拟显示，Flutter 采样进 GL scene —— 拷贝 + 采样，最差 |
| PlatformView surface 档 | 原生视图渲进自己的 surface 由系统合成 —— 无采样，但仍每帧与 Flutter scene 合成 |
| PlatformView hybrid 档 | 同上 + 与宿主滚动逐帧同步 —— 最贵 |
| **ArkUI 页面** | 直接进平台渲染管线，与任意系统应用同级 |

ArkUI 侧动画能力已核实存在：`animateTo` / `animateToImmediately` / curve / spring /
interpolation 全套（SDK `ets/component/common.d.ts`）。

**代价与限定，须一并记住**：

1. **失去「卡片列表连续滚动、每张卡都是活渲染」这个形态**，改为整页切换。
2. **卡片内容本身的渲染不会变快** —— ArkUI 页面里仍要放 `Web` 组件加载同一份
   `assets/anki_reviewer/card-frame.html`，HTML 渲染质量由 Web 引擎决定，与走哪条路
   无关。E 换来的是**转场与合成**，不是卡片动画魔法。

**§6 步 5 的工作量估算仍必须重估**：ADR 0047 的「复习器 5–8 人日」是照
**嵌入式 PlatformView** 估的，不含本节的否决过程与 E 的形态重设计。在 5b 出真机
收据之前，不得引用该数字作为鸿蒙复习器的预算。

**未验证前提（施工前必须先打点，不得由「有 `OhosView`」外推）：**

1. ~~`Platform.operatingSystem == 'ohos'` —— 目前只有代码注释作证~~
   **（2026-10-08 已结，见 §2.1）**——真机收据确认为 `"ohos"`，`isHarmonyOsTarget`
   为 `true`，`Platform.is*` 全 false。原注释（`official_anki_composition.dart`
   的 `initializeReadOnlyLocator`）从此有了实证后盾，`Platform.is*` 的写法不需要
   重估。
2. ~~三路合成模式齐备不等于行为等价~~ **（2026-10-08 已被路线 E 消解）**
   —— 既然 Dart 侧不再创建 PlatformView，「选哪一路合成模式」这个问题**不再需要
   回答**。它唯一残留的价值是 §3.1 的 D 案收据顺带确认了 `initOhosView` 在设备上
   确实存在（签名被 Dart 在报错中回显）。该前提就此作废，不得再作为待验项引用。
3. ~~ArkUI `Web` 组件能否满足复习器的 CSP（`assets/anki_reviewer/card-frame.html`
   为 `default-src 'none'`）+ 自定义 scheme + 媒体 Range/206。~~
   **（2026-10-14 已结，收据见 §3.2）——三条子句全部成立，保真档位成立，步 5b 解锁。**
   路线 E 把复习器渲染搬进 ArkUI 页面，但页面里仍要放 `Web` 组件加载同一份
   `card-frame.html`，所以这条不但没有被绕过，反而成了整条路的收窄口。

### 3.2 前提 3 的真机收据（2026-10-14，Mate 90 Pro Max / API 26）：**成立**

探针本体（2026-10-17 R1 起为 `ohos/entry/src/main/ets/probe/` 七个 ArkTS 文件 +
`lib/application/anki_official/render/official_anki_reviewer_probe.dart`；R1 之前是
`ohos/entry/src/main/ets/anki/` 下四个 + `pages/AnkiReviewerProbePage.ets` +
`entryability/AnkiReviewerProbeAbility.ets` + `anki/AnkiReviewerAssetProbe.ets`）
此前已写好但
**没有真机收据**，因为需要一次真实手势。2026-10-14 连上设备后跑通，原始判定行：

```
page={"shellSubresource":"loaded","frame":"loaded","cspConnect":"blocked",
      "audioState":"ready","audioDuration":2,"audioError":-1,
      "seekPhase":"done","seekApplied":1,"seekReadBack":1,
      "playRejected":"NotAllowedError","seekPlayError":"NotAllowedError",
      "seekPlaying":false}
requests=[GET /assets/shell.html->200 | GET /assets/probe.css->200 |
          GET /assets/probe.js->200 | GET /assets/frame.html->200 |
          GET /media/probe.wav->206 | GET /media/probe.wav->206 |
          GET /favicon.ico->404 | GET /favicon.ico->404]
rangeRequests=[GET /media/probe.wav Range:bytes=0- | GET /media/probe.wav Range:bytes=0-]
ranged=true mustNotFetched=false denials=0
```

**逐条对照前提 3 的三个子句**：

| 子句 | 收据 | 判定 |
|---|---|---|
| CSP（`connect-src 'none'`） | 页面报 `cspConnect:"blocked"`，**且**服务端见证 `mustNotFetched=false` | ✅ 成立 |
| 自定义 scheme `https://anki.local` | `shell.html` / `probe.css` / `probe.js` / `frame.html` 全部 200，iframe 内联脚本跑通（`frame:"loaded"`） | ✅ 成立 |
| 媒体 Range/206 | 内核发出 `Range:bytes=0-`，服务端两次返回 `206`（`Accept-Ranges: bytes` + `Content-Range`），`ranged=true` | ✅ 成立 |

CSP 这一条**不是只看页面自述**：探针故意让页面去 `fetch` 一个服务端会记账的 URL，
`mustNotFetched=false` 说明那个请求从未到达服务端——即内核确实在执行该策略，而不是
静默忽略 `<meta http-equiv>`。这是「页面说被拦」与「内核确实拦了」的分界。

**探针自身有一个缺陷，先修才问得出问题**：`AnkiProbeAssets.probeJs()` 里
`PENDING = 4` 只数四个**自动**检查（shellSubresource / cspConnect / frame / audioState），
`seekPhase` 不在其中。于是 `audioState` 一落定就满足 `settled >= 4` 而立即上报，
ability 随即 `terminateSelfWithResult`——实测整轮在加载后约 1.5 秒结束，人根本来不及点
`PLAY + SEEK`，**4b 在实践中不可达**（前几轮收据里 `seekPhase` 恒为 `"pending"` 正是这个原因）。
改为 `PENDING = 5`，判定改为等手势或等 30 秒 `not-gestured` 兜底（仍落在 ability 的 40 秒
`PROBE_TIMEOUT_MS` 内），手势用 `uitest uiInput click` 注入。

**一条超出前提 3 的新发现：脚本触发的 `play()` 被拒。** 无论从页面脚本直接调，还是从
ArkUI `Button.onClick` 经 `runJavaScript` 调，都返回 `NotAllowedError`，`seekPlaying=false`。
探针的 `summarise()` 把 `seekPlaying` 并入 `range` 判据，因此它自己的汇总是
`range=FAIL`。**这个 FAIL 不推翻前提 3**，理由有两条，都可核验：

1. 前提 3 问的是 Range/206，不是「能否出声」，而 Range/206 已由上面的服务端见证成立。
2. 真复习器**从不让 Web 自己放音**：`assets/anki_reviewer/card-frame.js` 全文没有
   `play()` / `autoplay`，`snapshotMediaUrls()`（`card-frame.js` 的
   `querySelectorAll("img, audio, source, video")`）只读 `src` 用于重渲染后重新锚定，
   且只剥离 `<video>`、不剥 `<audio>`。真正的 AV / TTS 回放由 **Dart 侧**
   `OfficialAnkiAvCoordinator` 驱动 `OfficialAnkiAvPlayer`（平台播放器），不经过 Web 的
   媒体元素，鸿蒙上走 ADR 0048 的自维护 ArkTS 音频通道。

**因此留下的真实边界**：卡片 HTML 里裸写的 `<audio>` 仍可由用户点按播放（媒体管线已证通），
但**依赖脚本自动出声的卡片模板在鸿蒙上不会自动播**。这是新约束，须在正式复习页的
文档与降级说明里写明，不是保真档位不成立的理由。


### 3.3 资产来源收据（2026-10-14）：**ArkTS 侧 rawfile 可读，promise 形式也落定**

前提 3 证明 `Web` 能渲染，但没回答页面**拿什么去渲染**。正式页要供两份字节，性质不同：

| 来源 | 内容 | 位置 | 体积 |
|---|---|---|---|
| 静态资源 | `reviewer.html/js/css`、`card-frame.html/js`、`mathjax-config.js`、`manifest.json` | hap 的 `resources/rawfile/flutter_assets/assets/anki_reviewer/` | 其中 MathJax **2.27 MB** |
| 牌组媒体 | `https://anki.local/media/*` | collection 的 media 目录，在文件系统 | 任意 |

**静态资源已收据**（`AnkiReviewerAssetProbe`，八个文件逐一读出，字节数与
`assets/anki_reviewer/manifest.json` **逐个吻合**）：

```
sync[reviewer.html=865 reviewer.js=11250 reviewer.css=1386 card-frame.html=921
     card-frame.js=10514 mathjax-config.js=248 manifest.json=1323
     mathjax/tex-svg-full.js=2275113]
promise=ok:865
```

由此确定两件事：

1. **reviewer ability 读得到自己的资源。** 它是独立 ability、拿不到
   `FlutterAssetManager`，这一点曾被写成「hap 里有资源不等于第二个 ability 能读到」——
   现在是读到的事实，不是推断。前缀是 `flutter_assets/assets/…`（`AudioPlugin` 的
   `ASSET_ROOT`；`assets/` 属于路径的一部分，去掉则每次查找都以 `9001005` 落空，
   而在手机上这与「复习器坏了」无法区分）。
2. **promise 形式可用，于是正式页走 promise，不走同步。** `AudioPlugin` 记过
   「`getRawFileContent` 的 promise 形式在 Mate 90 Pro Max / API 26 从不落定」——
   那条记录的**主语是 Dart future**（Dart 侧读到自己 10s 超时才返回），与 ArkTS 侧
   这一层不是同一次调用。本次是 ArkTS 侧的直接观测：promise 正常返回 865 字节。
   两条不冲突，但差别足以决定实现：2.27 MB 的同步读是平台线程上的停顿，promise 读不是，
   正式页没有理由再选同步。

**静态资源因此不构成 5b 的风险。** 尚未收据的是**媒体**，且它不是一个可以顺手补的读文件：
媒体的防线在 `OfficialAnkiMediaResolver`（纯 Dart——路径白名单、符号链接拒绝、越界检查、
MIME 映射），而 origin server 跑在 ArkTS。谁来做这次解析看着像安全边界归属的决定，
但**本仓库已有先例，不必再问**：`ios/Runner/AnkiReviewer/OfficialAnkiSchemeHandler.swift`
就是原生侧自带防线——`isSafeMediaName` / `isSafeAssetName` / `resolveMediaFile`
（`resolvingSymlinksInPath` + 前缀比对），源码分段标题直接写着
`media path safety (mirrors OfficialAnkiMediaPath/Store)`，并自带完整的 Range 解析与
206 应答。因此 ArkTS 侧的形状是**已定的**：照 Swift 那份原生重写，Dart 的
`OfficialAnkiMediaPath` 作规范源，跨平台一致性靠测试约束——而不是把每次请求回灌给 Dart
去解析（后者会让带 Range 的媒体走一轮通道往返，代价换不来安全性）。

这条先例也纠正了一处想当然：**「安全边界不能有两种实现」在本仓库不成立**，
因为 iOS 已经这么做了。真正的约束不是「只有一份实现」，而是「Dart 侧是规范源，
原生侧不得偏离」，所以后续必须有跨平台路径规则一致性测试，否则 iOS 与鸿蒙的
`isSafeMediaName` 会各走各的。

### 3.4 步 5b 施工中发现的平台断层（2026-10-14）：`fileIo` 没有可用的同步二进制读

写生产版 origin server 时撞上的，不是笔误而是 SDK 的代际断层，查类型声明原文可证：

```
openSync(path, mode?): File                    @since 12
readSync(fd: number, buffer, options?): number @since 11
closeSync(file: number | File): void           ← 收两种
```

`openSync` 从 API 12 起返回 `File` 对象，而 `readSync` 仍是 API 11 的 `number` 描述符签名，
`closeSync` 是唯一同时接受两者的函数。**结果是：这份 SDK 里没有任何接受 `openSync` 所返回句柄的
同步二进制读**，`readFileSync` 也不存在（整个 `@ohos.file.fs` 声明中没有该函数）。

而 `onInterceptRequest` 是同步的，`respond` 不能 await。两条路都有代价：

- 赌运行时接受 `File`（类型说 `number`）——**不选**，这类假设不会在编译期暴露，只会在设备上炸；
- 改用异步读——会把 Range/206 的同步语义变成「先返回后补数据」，而 Range/206 正是 §3.2
  里已被服务端见证成立的那一条，最不该在这里引入不确定性。

**选定**：媒体字节由 **Dart 预先推给 ArkTS 缓存**（`cacheMedia(name, base64)`），
`respond` 再从缓存同步切片；未推送时回 **503 `MEDIA_NOT_PUSHED`**，刻意与 `escape` /
`missing` 区分，因为前两者是路径规则判定、后者是推送尚未发生，答 403 会把时序问题
栽到卡片头上。

> **订正（2026-10-14 施工中）**：本节初稿写的是「媒体字节由调用方注入的 `MediaProvider`
> 供给」，**该形状不成立**——`respond` 是同步的，它回调 Dart 取字节，而 MethodChannel
> 调用是 Promise，两者无法同时满足。所以改为**推送式缓存**，与八个资源的 preload 同形：
> Dart 在会请求它的那次 `present` 之前把当前卡的媒体推过来。记录这个订正是因为它是一个
> **能过编译器、过不了真机**的设计，与 §3.6 的接线问题属于同一类。

这个改法有实质好处而不仅是权宜：媒体读取因此落到 Dart 侧那个**已有且被测过的**
`OfficialAnkiMediaResolver`（它本来就做定位读，正好满足 Range 切片），而不是在 ArkTS 里
重写一遍文件读。**符号链接那道防线没有外包**——仍在 ArkTS 侧用 `lstatSync` 直接拒绝
（`fileIo` 无同步 realpath，且分类器已保证名字无分隔符，故 `mediaRoot/<名字>` 本身是软链
是唯一逃逸路径，拒掉即可）。

**须记的方法论**：本批 20 个 ArkTS 错误里，`flutter analyze` 一个都发现不了——
ArkTS 的静态约束（`arkts-no-untyped-obj-literals` 禁 `Record<string, object>`、
SDK 签名代际不一致）只有反复构建才拦得住。**「编译通过」在这条链上必须现场验证，
不得据先前一次构建推断。**

### 3.5 接线点的更正（2026-10-14）：分支在 `OfficialAnkiReviewerStage`，不在 View

接线位置先前被写成「接进 `OfficialAnkiReviewerView`」，**这是错的**，查源码可证：
`official_anki_reviewer_view.dart` 的 `build()` 开头就是

```dart
if (!Platform.isAndroid && !Platform.isIOS) {
  return OfficialAnkiReviewerErrorView(
    messageKey: isHarmonyOsTarget ? 'official_anki.renderer_ohos_pending' : …);
}
```

路线 E 下这个 widget 在鸿蒙上**本就不该存在**——卡片由 ArkUI ability 全屏渲染，Flutter 这边没有
PlatformView 可创建。正确的接线点是 **`OfficialAnkiReviewerStage` 整条分支**：鸿蒙上不进
Flutter 复习器，直接开 ability 并用通道驱动。

**这意味着 Stage 里的 Flutter chrome 在鸿蒙上都必须让位**——翻卡按钮、四档评分、
`TextField` 输入框、AV 提示、错误视图，这些路线 E 已经搬进了 `AnkiReviewerPage`。

**接线契约查实（2026-10-14，逐项核对源码）**：

| 环节 | 实际归属 | 签名 |
|---|---|---|
| 翻卡 / 渲染 | `OfficialAnkiReviewerController`（`official_anki_render_state.dart`） | `loadAndShowQuestion` / `showAnswer` / `invalidateGeneration` |
| 输入答案 | 同上，`controller.typed`（`OfficialAnkiTypedAnswerController`） | `updateProvided` / `frozen` / `comparison` |
| AV | 同上，`controller.av`（`OfficialAnkiAvCoordinator`） | — |
| **评分落库** | **不在上面任何一层** | `OfficialAnkiCourseGradesBridge.answerOfficialCard({wordId, rating, millisecondsTaken})` |

关键的一行是最后一条：**评分走的是 `wordId`，渲染走的是 `cardId`，两者不是同一个 ID
空间**（`answerOfficialCard` 定义在 `official_anki_course_grades_bridge.dart`，是课程成绩
桥，参数名为 `wordId`）。所以鸿蒙驱动器要连的不是「给 presenter 多加一个方法」，而是
要一并解决 `wordId ↔ cardId` 的映射、`millisecondsTaken` 的计时起点，以及
`compare_answer` 往返后 `comparisonHtml` 的回填。

**因此本节先前的说法「需要一个宽于 `OfficialAnswerPresenter` 的接口」不准确**：
`OfficialAnswerPresenter` 抽象的是翻卡与渲染，评分在它下面也之外的另一条链上，
两者靠 `wordId`/`cardId` 隐式耦合。施工时若只补接口不补映射，会得到
**「能开卡但评不了分」的半成品——而那比现在的响亮失败更坏，因为它看起来是好的**。

**顺序是硬约束**：`pushMediaForCard` 必须先于 `present`，否则媒体请求先撞上
503 `MEDIA_NOT_PUSHED`。

### 3.6 步 5b 调用方接线（2026-10-14）

`AnkiReviewerPage`、`AnkiReviewerAbility`、`AnkiReviewerSession`、`AnkiReviewerBridge`
与插件方法均已写。Dart 侧 `OfficialAnkiOhosReviewerBinding` 由
`OfficialAnkiReviewerStage` 在鸿蒙上挂上：先 `open`（该 future 要等学习者关掉
ability 才结束），壳加载后再呈现；`pushMediaForCard` 先于 `present`；翻卡走
`OfficialAnkiReviewerController.showAnswer`（`compare_answer` 的 `comparisonHtml`
随答案面 payload 回去）；评分用 `officialAnkiWordId` 调
`OfficialAnkiCourseGradesBridge.answerOfficialCard`，`millisecondsTaken` 从翻卡
时刻起算。正式复习页把桥的 `onAnswer` 接到 `OfficialReviewSession.answerAndConfirm`，
成功后只记学习会话回执并前进，不再第二次落库。ArkTS 页通过同一条 MethodChannel
把 `showAnswer` / `rate` / `typedChanged` 送回 Dart，并在 `onPageEnd` 后才算壳就绪。

这仍然**不等于跑通**——上机当晚（2026-10-14 夜）即在真机上暴露八处接线缺陷并逐处
修复，随后拿到首卡收据，见 §3.7。步 6 独立 CI workflow 已于 2026-10-15
落库、首跑收据待取（§6 步表行 6）。

输入答案的归属已核实并落定：**它在所有平台都是原生的，不是鸿蒙变通**。
`card-frame.js` 的 `applyTyped` 把 `[[type:…]]` 答题前渲染成空占位 span、答题后渲染成官方
引擎 `compare_answer()` 的对照 HTML，Web 从头到尾看不到原始输入；Flutter 侧是
`TextField` → `controller.typed.updateProvided` → 提交后 `frozen`。ArkUI 页补的是路线 E
拆出去的那一半输入框，不是新增一条管线。

### 3.7 真机首卡收据与八处接线修复（2026-10-14 夜）

接上真机（Mate 90 Pro Max / API 26 / HarmonyOS 7.0.0.109）冷启动进入正式复习，
首屏即复现 `official_anki.render_failed`——接线代码从未在设备上跑过，一跑就暴露
八处缺陷。逐轮「构建 → 装机 → 复现 → 定位」，全部修复后拿到**首卡全链路收据**：

- **渲染**：卡 781 问题面经 `https://anki.local/assets/reviewer.html` 完整渲染
  （官方 shell，卡片文字进无障碍树，截图存档）。
- **翻卡**：`Show answer` → 答案面 + 四档评分按钮，`ack type=renderComplete
  side=answer`（翻卡后约 60ms，代次匹配）。
- **评分落库**：`good` 经 `wordId → answerOfficialCard → answerAndConfirm` 提交，
  队列 **781→782→783→784 三次真实前进**——评分确实写进了调度。
- **重启恢复**：多轮强杀冷启动后复习会话自动恢复到当前卡（附带收据）。

八处缺陷，每处都有设备收据（完整清单见 `test/BASELINE.md` 2026-10-14「步 5b 真机
首卡收据」条）：

1. **`OfficialAnkiAvPlayerAdapter` 在鸿蒙构造 `AudioPlayer()`**——audioplayers 无
   鸿蒙实现，构造即 `MissingPluginException(xyz.luan/audioplayers.global)`，击穿
   整个渲染 boot（用户看到的就是 `render_failed`）。鸿蒙改走 `OhosAudioBackend`
   （新增按路径播放 / 停止 / 释放，`playFile` 带 `awaitCompletion` 播完回执）。
2. **会话在 `loadContent` 回调里才创建**——页面预构建先于回调执行，拦截器捕获
   undefined 会话后 `TypeError: Cannot read property origin of undefined` 从原生
   回调逃逸，进程濒临 RuntimeError。会话创建提前到 `loadContent` 之前。
3. **拦截器在 build 时捕获会话**——改为调用时解析，缺失回 503 `reviewer_not_open`。
4. **@Entry 页面模块与直联导入方各持一份模块级状态**——会话由 ability 创建 35ms
   后页面侧仍读 undefined（503 收据为证）。会话存储移入库模块
   `AnkiReviewerSessionStore.ets`，三方共用。**须记的平台事实**：`main_pages.json`
   登记的 @Entry 页面文件被编译为独立模块实例，其模块级状态与直联导入方不共享。
5. **shell 加载编排三连败**——显式 `loadUrl` 在初始导航在途时被吞、`about:blank` 的
   `onPageEnd` 不独立触发、控制器未挂载时抛 Init error。最终采用探针同款形态：
   `src` 直指 shell URL 由内核驱动，预加载只在 `aboutToAppear` 抢提前量。
6. **小资产预热竞态**——七个 ~16KB 资产改 `getRawFileContentSync` 同步预热
   （`preloadSync`），2.27MB MathJax 保持 promise 路径（同步读会停顿平台线程）。
7. **`setResponseData` 只接受 `ArrayBuffer`**——传 `Uint8Array` 编译通过但响应体
   为空，shell 以 200+空体加载成无 script 空页（`document.scripts=[]` 为证）。探针
   未踩中，因其资产恰好是字符串形态。**须记**：这是「编译过、跑不通」的又一类——
   SDK 签名不含 `Uint8Array`，ets-loader 却没有拦下。
8. **ack 协议接错**——Android 客户端**轮询** `window.__turnaLastRender`
   （`pollCompletion`），ArkTS 初版在等一条无人发送的桥消息，两面均 12s
   `RENDER_TIMEOUT`。重写 `present()` 为 50ms 轮询；其中还踩一层语义差——
   **ArkTS `String.replace()` 只替换首处**（Kotlin 全局替换），从 Android 移植的
   JSON 解包在该差下永远失败，改由 JS 侧拼无引号分隔串取值。

**遗留打磨项（不推翻首卡收据）**：中途关闭 ability 再重开会开在后台，需「重试」
恢复；换卡瞬间评分门存在时序空窗（窗口期重复点击收到 `answer_not_ready` 拒绝）；
换卡后偶现直接呈现答案面（reveal 状态未随换卡复位）。**完整用户流余项**：课程
学习解锁无真机收据；步 6 独立 CI workflow 已于 2026-10-15 落库、首跑收据
待取；伴生版不进主交付不变。

**2026-10-16 补记（评分回执与按钮互斥）**：上两条打磨项已代码修复。归因——
`rate` 原为 fire-and-forget，Dart 侧一切拒绝（含 `answer_not_ready`）被 grades 桥
折叠成 `false` 后对页面不可见，与死按钮不可区分；另新证实第三条死按钮路径：末卡
评分后队列完结、无 present 换行，完成屏被 ability 盖住。修复——Dart 回复稳定
回执码（`ok` / `ok_complete` / `answer_not_ready` / `scheduler_busy` /
`card_mismatch` / `session_closed` / `engine_error` / `scheduler_unavailable` /
`no_card`），`answer_not_ready` 自愈翻回问题面并 re-present；ArkUI 点按即禁用、
present 重新武装、`ok_complete` 换入完成行（Close→`terminateSelf`）。单测 2149
全绿；**真机复验收据待取**（互斥 / 回执 / 自愈 / 完成行四点）。ability 重开在
后台一项未触碰，仍为遗留。

## 4. 三个真实技术缺口（决策无法消解，须在接线批次解决）

**4.1 的 SQLite 加载、4.2 的 API 26 设备加载于 2026-10-08 取得收据**；
真实 locator 于 2026-10-13 补修，最低 API 18 兼容仍待验。4.3 记步 1 已交付的静态部分，
4.4 是贯穿全部接线批次的纪律。**步 3 的能力矩阵硬拒与步 4 的降级标记已于同日拆除**
（`runtimeOk=true reason=ready`，`degradations=remoteBackup`）。

**步 0–4 完成后伴生版的实际边界**（这是「已授权」的准确含义）：

| 能力 | 鸿蒙状态 | 依据 |
|---|---|---|
| `.apkg` 导入 | 接线已修复，真机完整导入待验 | 平台路由 + 2026-10-13 真实 locator 修复 |
| 课程树投影 / SRS 调度 | 有实现，鸿蒙用户流待验 | 2026-10-13 修复 RDB 原子换页；engine-info 不证明实际调度 |
| 共享 catalog | SQLite 加载已验证；真实 locator 已修复，设备待复跑 | 内存探针 + 2026-10-13 冷启动修复 |
| **保真复习器（原卡渲染）** | **真机可用**（2026-10-14 夜首卡收据：渲染 / 翻卡 / 评分落库 / 队列前进；遗留打磨项见 §3.7） | §3.7 真机收据；判据 §3.2；静态资源 §3.3；平台断层 §3.4；接线契约 §3.5；调用方接线 §3.6 |

**保真复习器的「响亮失败」时代已于 2026-10-14 夜结束**（§3.7）。此前入口开着、
卡片渲染给出 `official_anki.renderer_ohos_pending` 明确文案而非禁用入口，理由
已由当时的收据记录：一个「点了没反应」的入口比一个不存在的入口更难归因。当前
失败形态是打开复习 ability 失败时的 `render_failed` + 重试，以及会话未就绪时
拦截层的 503 `reviewer_not_open`——两者都是可恢复的明确失败，不是静默降级。

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

### 4.2 hap 声明的最低 API 与 sysroot 存在落差 —— **API 26 已验证，最低 API 18 待验**

`ohos/build-profile.json5` 的 `compatibleSdkVersion` 为 `5.1.0(18)`，而本机
OHOS native sysroot 是 API 26（ADR 0047 §7.4 记录的 DS-243 单档 SDK）。对
`libturna_anki.so` 逐串核过：含 `OH_TimeService_GetTimeZone` / `dlopen` /
`pthread_create`，**不含** `__android_log_print` / `__system_property_get`，
暂未发现会在 API 18 设备上炸的符号。

**但这只是静态字符串检查，不是收据。** 步 1 打包后须在真机上确认 hap 声明的最低
API 与引擎 `.so` 的实际最低需求一致，否则装机即 `dlopen` 失败。

**2026-10-08 真机收据：`dlopen=ok abi=1 path=libturna_anki.so`**
（Mate 90 Pro Max / API 26，装 `entry-default-signed.hap`）。**仅证明该 API 26
设备可以加载引擎，不能证明引擎在声明的最低 API 18 设备可运行。** 这条收据的强度在于 `dlopen` 成功即意味着**全部
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
| 1 | `.so` 装进 `ohos/entry/libs/arm64-v8a/` + 构建接线；`resolveOfficialAnkiLibraryPath` 加 ohos 分支；API 26 真机加载 —— **已完成（2026-10-08，`dlopen=ok abi=1`）；最低 API 18 兼容仍待验** | 步 0 |
| 2 | 重写 `ensureOfficialAnkiSqlite` 分派为 `overrideForAll`（§4.1）+ 独立 `libsqlite3.so` 随 hap 分发 —— **已完成（2026-10-08，`catalog=ok sqlite=3.49.2`）** | 步 1 |
| 3 | 平台路由：`OfficialAnkiCapabilityMatrix._hostPlatform` / `forPlatform`、`AnkiImportExecutionPlanner.productModeFor`、`OfficialAnkiCompositionRoot.probe` —— **已完成（2026-10-08，`runtimeOk=true reason=ready abi=1`）** | 步 1–2 |
| 4 | 撤 `OhosDegradation.officialAnki` + `OfficialAnkiNativeAvailability` 的 ohos 分支 —— **已完成（2026-10-08，`degradations=remoteBackup`）** | 步 3 |
| 5a | **定 §3.1 的 Dart 接线路线** —— **已完成（2026-10-08）：A / B / D 三案被真机收据否决，选定 E（独立 ArkUI 页面，翻卡在页内完成）** | 步 4 |
| 5b | **ArkTS 复习器页面**（第 5 个手写插件：`Web` 组件 + 自定义 scheme + 媒体 Range/206 + CSP），登记进 `EntryAbility`，并入 `_requiredOhosFiles` —— **不再需要 PlatformView 工厂** —— **已完成（2026-10-14 夜）**：判据已结（§3.2）；页面与调用方接线（§3.6）；真机首卡收据——渲染 / 翻卡 / 评分落库 / 队列前进（§3.7）；生产页 / ability / 会话存储已并入 `_requiredOhosFiles`；遗留打磨项与用户流余项见 §3.7 | 步 5a |
| 6 | 独立 CI workflow（ADR 0047 承诺）—— **已施工（2026-10-15）**：`.github/workflows/ohos_ci.yml`（fork SDK 按 gitcode 公开 tag 克隆 + 华为 OBS 工件镜像 + ADR 0047 §7.2 shim + `tool/ohos_ci_prepare.py` 无签名准备）落库，本地可验部分全绿；**首跑收据待取**——DevEco command-line tools zip 无稳定公开直链，需配 `DEVECO_CMDLINE_TOOLS_URL` 仓库变量（或 dispatch inputs）后首跑，首跑绿前不改判为完成 | 步 1–5b |

步 5b 的验收判据收敛为**一条**：§3 的未验证前提 3 —— ArkUI `Web` 能否满足 CSP +
自定义 scheme + 媒体 Range/206。（前提 1 已于 2026-10-08 结清，前提 2 已被路线 E
消解——不再创建 PlatformView 就没有「选哪一路合成模式」这个问题。）**这一条不成立
则保真档位不成立**，届时回到「文本降级」档并修订本文。

**判据已于 2026-10-14 判定：成立**（§3.2 收据，三条子句逐条有服务端见证）。
故 5b 的**风险闸门已开**，「文本降级」档不再触发。**2026-10-14 夜，5b 完成**：
页面、通道与调用方接线（§3.6）当晚上机，八处接线缺陷逐处修复后拿到首卡全链路
收据（§3.7）——渲染、翻卡、评分落库、队列前进。完整用户流的余项（课程学习解锁）
与遗留打磨项见 §3.7；步 6 独立 CI workflow 已于 2026-10-15 落库，首跑收据
待取（工具链配置见步表行 6 与 [34 收据](../official-anki-migration/34-cutover-receipt.md)
「鸿蒙步 6 独立 CI workflow 施工」节）。

**§3.1 已不再是本表最大的不确定项** —— 它已由 §3.1 的否决收据与路线 E 结清。但
**ADR 0047 的「复习器 5–8 人日」仍不可引用为预算**：它是照嵌入式 PlatformView 估的，
既不含三案的否决过程，也不含 E 的形态重设计，也不含 §3.7 的八处真机修复。页面本体
现已施工完毕（§3.6–§3.7），但那是事后事实，不是事前估算；后续同类工作的预算仍应
按 §3.7 暴露的缺口类别另估，不得回填本 ADR。

## 后果

- ADR 0041 §决策 2 与 ADR 0047 §2 第 2 条作废；两份 ADR 须加本文的修订指针
- 官方 Anki 状态真源（`docs/official-anki-migration/34-cutover-receipt.md`）须记本批
- 平台矩阵（`docs/project-guide.md` §10.1）与 `docs/android-build-setup.md` 的退役节
  须按本 ADR 各节收据状态改写（步 0–5b 已施工、5b 有真机首卡收据；步 6 workflow
  已落库待首跑收据；
  完整用户流余项与遗留打磨项见 §3.7），不得写成产品级「已支持」
- `test/BASELINE.md` 前插一条收据
- Android / iOS 行为不得回归：`flutter analyze` 0 issue，
  `flutter test --exclude-tags golden` 保持 0 failed
