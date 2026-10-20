# ADR 0050 — 鸿蒙启用 Official Anki 全档（引擎 / 导入 / 投影 / 保真复习器）

> 状态：已接受（决策层）｜日期：2026-10-07
>
> 修订 [ADR 0047](./0047-ohos-companion-lite-build.md) §2 第 2 条。Official Anki 的现行状态口径见 [`docs/status.md`](../status.md)。

## 决策

在鸿蒙伴生版上启用 **Official Anki 全档**：`libturna_anki.so` 引擎、`.apkg` 导入、
课程树投影、保真复习器（原生 ArkUI 页面 + `Web` 组件，HTML 不降级为文本）。本 ADR 是
**授权与理由**，不是施工日志；接线进度、真机收据与遗留项以
[`docs/status.md`](../status.md) 为准。

**修订**：原 ADR 0041（已删）§决策 2「不建设 OHOS Official Anki Core」、ADR 0047 §2 第 2 条「不启用
Official Anki 引擎与保真复习器：鸿蒙明确不可用」——**均由本文取代**。

**不作废的条款**：原 ADR 0041（已删）§决策 1（不再为 OHOS 构建 / 发布 / 适配）不变——伴生版仍不进
主交付、不进主 CI；本文授权的是**伴生版内部**开启 Anki，不是恢复产品线。§决策 3 / 4
（`tool/apply_patches.sh` 与 `tool/patches/` 保持删除）不变。§决策 5（未知平台 →
`ankiUnavailable`）不变——本文新增的是一个**已知**平台分支，不是把未知平台放开。
ADR 0047 §5.4（`webview_flutter` 不得被 override）**无需解除**（见 §2.2）；§5.8（`ohos/`
不得出现 Official Anki 引擎宿主）**由本文取代**。

## 理由

### 2.1 前提与平台身份

引擎层的可行性**已由本文 §2.1 的收据确立**（交叉编译 `aarch64-unknown-linux-ohos` 成功、
`libturna_anki.so` 无 `libsqlite3.so` 外部依赖、真机 `dlopen` → `abi_version` 1 →
`engine_new` status 0 → `engine_close` OK）。**该证据未覆盖**（§2.1 范围边界原文）：
磁盘 collection 打开、调度器真实负载、导入链路、卡片渲染——这四项是授权范围内的施工对象与
验收项，不是既成结论。
### 2.2 保真复习器走原生页面，不碰 `webview_flutter`

**旧 Anki 保真**走 `webview_flutter`，鸿蒙无实现；**官方 Anki 保真**走 `PlatformViewLink` /
`UiKitView`。鸿蒙 fork SDK 提供原生 PlatformView 且三路合成模式齐备，与 Android 对称：

| Dart 侧入口 | 控制器 | Android 对应 |
|---|---|---|
| `PlatformViewsService.initOhosView` | `TextureOhosViewController` | `initAndroidView`（TLHC） |
| `PlatformViewsService.initSurfaceOhosView` | `SurfaceOhosViewController` | `initSurfaceAndroidView` |
| `PlatformViewsService.initExpensiveOhosView` | `ExpensiveOhosViewController` | `initExpensiveAndroidView` / `initHybridAndroidView` |

但**官方 SDK 的 `packages/flutter/lib/src/widgets/platform_view.dart` 里没有任何 `Ohos*`
标识符**，实测引用 `OhosViewController` 于官方 SDK 下报 `Undefined class 'OhosViewController'`。`dependency_overrides` 全局无平台条件，在 `lib/` 里直接写
`OhosViewController` / `initOhosView` 会让 **Android/iOS 构建与全部测试同时崩**——
与 ADR 0047 §7.1 描述的失败类同源（那次是 `case TargetPlatform.ohos:`，这次是 `Ohos*` 类名）。
### 2.3 Dart 侧接线：A / B / D 三条路线被真机收据否决，改走 E

初稿曾写「保真档位比 ADR 0047 估的便宜」，**该结论不成立**——它把「平台有原生
PlatformView」当成了「Dart 侧能低成本引用」。

| 路线 | 判定 |
|---|---|
| **A** 条件导出（`dart.library.ohos`） | **前提不存在**：OHOS 目标**不定义** `dart.library.ohos`，条件直接落到 `dart.library.io` |
| **D** dynamic 派发（`PlatformViewsService` 当 `dynamic` 调） | **Dart 不能动态调用静态方法**；它是 class，动态派发按实例方法查找，报 `NoSuchMethodError: Class 'Type' has no instance method 'initOhosView'` |
| **B** vendored 移植（照 ADR 0047 §7.1 承载 `Ohos*`） | **规模不可接受**：`dependency_overrides` 能把 `flutter` 指向本地路径，但那是**把整个 Flutter 框架 vendored 进仓库**（现状 `third_party/` 只有 `material_ui` 与 `cupertino_ui`），且需先废原 ADR 0041（已删）§决策 4/5 |

**A 与 D 的根本障碍是同一个**：`Ohos*` 与 `AndroidViewController` 位于**同一个 library**
（`package:flutter/services.dart`），条件导出只能切 import，**切不开同一个库内部的类**。
另两条独立事实：`PlatformViewSurface` 的构造签名不含 `Ohos*`——障碍在 controller 的
**创建**，不在 widget 的使用；`PlatformViewLink` 的 `surfaceFactory` 与
`onCreatePlatformView` **都是必填**，框架无法替我们造 controller。

**路线 E（已定）：复习器做成独立 ArkUI 页面。** Dart 侧不创建任何 PlatformView，
因此 `Ohos*` 这个问题整体消失——不需要条件导出、不需要 vendored 移植、不需要改 SDK，
也**不需要废任何现行 ADR**。它是仓库里第 5 个手写 ArkTS 插件（继 `RdbPlugin` /
`AudioPlugin` / `TtsPlugin` / `FilePickerPlugin` 之后），沿用既有的 MethodChannel +
`EntryAbility` 显式注册范式。

**交互形态（用户拍定）**：**整页原生页面，翻卡在同一页内完成**。进入复习即切到 ArkUI 页面，
卡片间切换全部在原生页内完成；Dart 只负责下发卡片数据与接收判定。

选原生页而不是嵌入式 PlatformView，是 E 相对 A/B/C 的独立收益（不只是绕过编译障碍）：

| 合成路径 | 每帧代价 |
|---|---|
| PlatformView texture 档 | 原生视图渲到虚拟显示，Flutter 采样进 GL scene —— 拷贝 + 采样，最差 |
| PlatformView surface 档 | 原生视图渲进自己的 surface 由系统合成 —— 无采样，但仍每帧与 Flutter scene 合成 |
| PlatformView hybrid 档 | 同上 + 与宿主滚动逐帧同步 —— 最贵 |
| **ArkUI 页面** | 直接进平台渲染管线，与任意系统应用同级 |
### 2.4 ArkUI `Web` 的三条子句全部成立

复核判据是 ArkUI `Web` 能否满足 CSP（`assets/anki_reviewer/card-frame.html` 为
`default-src 'none'`）+ 自定义 scheme + 媒体 Range/206。三条**全部成立**：CSP 页面报
`cspConnect:"blocked"` 且**服务端见证** `mustNotFetched=false`——探针故意让页面去 `fetch`
一个服务端会记账的 URL，该请求从未到达服务端，即内核确实在执行该策略，而不是静默忽略
`<meta http-equiv>`；这是「页面说被拦」与「内核确实拦了」的分界。自定义 scheme
`https://anki.local` 下 shell / probe / frame 资产全部 200 且 iframe 内联脚本跑通；媒体内核
发出 `Range:bytes=0-`、服务端两次返回 `206`。
### 2.5 资产来源与媒体字节

| 来源 | 内容 | 位置 | 体积 |
|---|---|---|---|
| 静态资源 | `reviewer.html/js/css`、`card-frame.html/js`、`mathjax-config.js`、`manifest.json` | hap 的 `resources/rawfile/flutter_assets/assets/anki_reviewer/` | 其中 MathJax **2.27 MB** |
| 牌库媒体 | `https://anki.local/media/*` | collection 的 media 目录，在文件系统 | 任意 |

**reviewer ability 读得到自己的资源**——它是独立 ability、拿不到
`FlutterAssetManager`。**前缀是 `flutter_assets/assets/…`**：`assets/` 属于路径的一部分，去掉
则每次查找都以 `9001005` 落空，在手机上与「复习器坏了」无法区分。
### 2.6 媒体字节的同步读不可得，只能推送式缓存

`openSync` 从 API 12 起返回 `File` 对象，`readSync` 仍是 API 11 的 `number` 描述符签名，
`closeSync` 是唯一同时接受两者的函数——**这份 SDK 里没有任何接受 `openSync` 所返回句柄的
同步二进制读**，`readFileSync` 也不存在。而 `onInterceptRequest` 同步、`respond` 不能 await：
赌运行时接受 `File`（类型说 `number`）**不选**——这类假设不会在编译期暴露，只会在设备上炸；
改用异步读会把 Range/206 的同步语义变成「先返回后补数据」，而 Range/206 正是已被见证成立
的那一条。
### 2.7 接线点与 ID 空间陷阱

接线位置先前被写成「接进 `OfficialAnkiReviewerView`」，**这是错的**：该 widget 的 `build()`
开头就是 `if (!Platform.isAndroid && !Platform.isIOS) { return OfficialAnkiReviewerErrorView(...); }`。
路线 E 下这个 widget 在鸿蒙上**本就不该存在**——卡片由 ArkUI ability 全屏渲染，Flutter 这边
没有 PlatformView 可创建。正确的接线点是 **`OfficialAnkiReviewerStage` 整条分支**：鸿蒙上
不进 Flutter 复习器，直接开 ability 并用通道驱动。

**接线契约（逐项核对源码）**：

| 环节 | 实际归属 | 签名 |
|---|---|---|
| 翻卡 / 渲染 | `OfficialAnkiReviewerController`（`official_anki_render_state.dart`） | `loadAndShowQuestion` / `showAnswer` / `invalidateGeneration` |
| 输入答案 | 同上，`controller.typed`（`OfficialAnkiTypedAnswerController`） | `updateProvided` / `frozen` / `comparison` |
| AV | 同上，`controller.av`（`OfficialAnkiAvCoordinator`） | — |
| **评分落库** | **不在上面任何一层** | `OfficialAnkiCourseGradesBridge.answerOfficialCard({wordId, rating, millisecondsTaken})` |

关键的一行是最后一条：**评分走的是 `wordId`，渲染走的是 `cardId`，两者不是同一个 ID 空间**
（`answerOfficialCard` 定义在 `official_anki_course_grades_bridge.dart`，是课程成绩桥，
参数名为 `wordId`）。所以鸿蒙驱动器要连的不是「给 presenter 多加一个方法」，而是要一并解决
`wordId ↔ cardId` 的映射、`millisecondsTaken` 的计时起点，以及 `compare_answer` 往返后
`comparisonHtml` 的回填。

**因此「需要一个宽于 `OfficialAnswerPresenter` 的接口」这个说法不准确**：
`OfficialAnswerPresenter` 抽象的是翻卡与渲染，评分在它之下也之外的另一条链上，两者靠
`wordId` / `cardId` 隐式耦合。施工时若只补接口不补映射，会得到**「能开卡但评不了分」的半成品
——而那比现在的响亮失败更坏，因为它看起来是好的**。

**顺序是硬约束**：`pushMediaForCard` 必须先于 `present`，否则媒体请求先撞上
503 `MEDIA_NOT_PUSHED`。
### 2.8 真机首卡暴露的接线缺陷（沉淀出的平台事实）

接线代码从未在设备上跑过，一跑就暴露八处缺陷；逐处修复后拿到首卡全链路收据（渲染 / 翻卡
/ 评分落库 / 队列前进 / 强杀恢复），收据本身见 [`docs/status.md`](../status.md)。缺陷是施工
记录，**沉淀下来的平台事实不是**：

- **audioplayers 无鸿蒙实现**，构造 `AudioPlayer()` 即 `MissingPluginException`，击穿整个渲染
  boot → 鸿蒙音频走自维护通道 `OhosAudioBackend`
- **会话创建须早于 `loadContent` 回调**；否则拦截器捕获 undefined 会话，异常从原生回调逃逸
- **拦截器须在调用时解析会话**，缺失回 503 `reviewer_not_open`（不能 build 时捕获）
- **`main_pages.json` 登记的 @Entry 页面文件被编译为独立模块实例，其模块级状态与直联导入方
  不共享** → 会话存储移入 `AnkiReviewerSessionStore.ets` 三方共用
- **shell 加载编排**：`loadUrl` 在初始导航在途时被吞、`about:blank` 的 `onPageEnd` 不独立触发、
  控制器未挂载时抛 Init error → 改为 `src` 直指 shell URL 由内核驱动
- **小资产预热竞态**：小资产改同步预热（`preloadSync`），2.27MB MathJax 保持 promise 路径
  （同步读会停顿平台线程）
- **`setResponseData` 只接受 `ArrayBuffer`**——传 `Uint8Array` 编译通过但响应体为空，shell 以
  200+空体加载成无 script 空页。**「编译过、跑不通」的又一类**：SDK 签名不含 `Uint8Array`，
  ets-loader 却没有拦下
- **ack 协议接错**：Android 客户端**轮询** `window.__turnaLastRender`，ArkTS 初版在等一条无人
  发送的桥消息 → 重写 `present()` 为 50ms 轮询；其中还踩一层语义差——**ArkTS
  `String.replace()` 只替换首处**（Kotlin 全局替换）
### 2.9 评分回执与评分档

**回执必须稳定可辨**：Dart 回复稳定回执码（`ok` / `ok_complete` / `answer_not_ready` /
`scheduler_busy` / `card_mismatch` / `session_closed` / `engine_error` /
`scheduler_unavailable` / `no_card`），`answer_not_ready` 自愈翻回问题面并 re-present，
ArkUI 点按即禁用、present 重新武装、`ok_complete` 换入完成行。归因值得记住：`rate` 原为
fire-and-forget，Dart 侧一切拒绝被 grades 桥折叠成 `false` 后对页面不可见，**与死按钮不可
区分**。

**正式复习的评分档与安卓对齐为二档**（忘记 / 记住），只发 `again` / `good`：
`OfficialAnkiReviewLedger` 对二态 outcome 发出的 rating 正是 `forgotten → again`、
`remembered → good`，鸿蒙只发这两个词即与安卓逐字等价。归因是同一张卡在安卓
（`BinaryRecallBar` 二档）与鸿蒙（四档）呈现不同选择数，是可感知的产品不一致；安卓是当前
主交付平台，故以安卓为基准。协议层四个 rating 词保留。
### 2.10 三个真实技术缺口（决策无法消解，须在接线批次解决）

**① catalog 存储：需要一份独立的 `libsqlite3.so`，且分派方式要重写。**
`ensureOfficialAnkiSqlite()` 只覆盖 Linux / Android，鸿蒙上 sqlite3 的 loader 抛
`Unsupported platform: ohos`。**这不是引擎的依赖问题**：bridge 内的 SQLite 是 `bundled`，
静态编入 `.so`；缺的是 **Turna 侧共享 catalog** 那份独立 FFI 库，须随 hap 分发。

机制：`sqlite3-2.9.4` 的 `load_library.dart` 里 `OperatingSystem? get os` 是六项
`Platform.is*` if 链，全 false → `null` → `ensureOfficialAnkiSqlite()` 注册的表根本查不到
→ 落到 `_defaultOpen()` 末行抛 `UnsupportedError`。**不是「缺一个枚举值可注册」，而是没有
`OperatingSystem.ohos` 这个注册位存在。** 唯一可用入口是 `open.overrideForAll()`，它不做
平台分派、全平台生效——故修法是**重写分派方式**而非新增一条 override：

```dart
if (isHarmonyOsTarget) {
  open.overrideForAll(_openHarmonyOsSqlite);
  return;
}
// 其余平台保持现有 overrideFor 分支
```

**改动面比初稿描述的大**，须一并记入：

- `ensureOfficialAnkiSqlite()` 有 **11 处调用点**，含 `lib/service/locator.dart` 的主
  isolate 调用与作为 `NativeDatabase.createInBackground(isolateSetup:)` 参数的后台 isolate 调用
- `overrideForAll` 与 `overrideFor` 一样是 **per-isolate 状态**，跨 isolate 需各自注册
- 短路必须发生在 `_opened` 幂等标志**之前**，否则鸿蒙上第二次调用会被幂等吞掉
- `overrideForAll` 一旦误注册会在 Android/iOS 上也生效，故短路条件必须是
  `isHarmonyOsTarget` 而非 `Platform.*`

**已实施并取得真机收据**：新增 `native/turna_anki_core/build-ohos/build-sqlite.sh` 交叉
编译 `libsqlite3.so`（SQLite **3.49.2**，源码取自 cargo registry 里 `libsqlite3-sys-0.34.0`
随附的 amalgamation——**与引擎编译用的是同一份**，故 catalog 与引擎不会在版本上漂移），
产物已提交进 `ohos/entry/libs/arm64-v8a/libsqlite3.so`。编译选项刻意保守：默认
amalgamation 构建，**不开** FTS5 与 JSON1——`lib/` 中两者都无引用，缺了会在 prepare 时响亮
失败，半残的扩展不会。

新增门禁 `test/application/anki_official/official_anki_sqlite_dispatch_test.dart`（**5 例**），
逐条钉住上面那份「改动面」清单：短路在幂等标志之前、守卫是单一谓词而非 `Platform.*`、没有
伪造 `OperatingSystem.ohos`、`overrideForAll` 全局只有一处且在守卫内、Linux/Android 的
per-platform override 仍在、hap 内 `libsqlite3.so` 是 aarch64 且导出核心符号。

> **写这道门禁时踩的坑**：断言若直接扫源码全文，会命中**本文件自己的注释**——分支的注释正
> 解释了「为什么不用 `Platform.is*`」与「为什么不能用 `overrideFor`」，于是这两个标识符必然
> 出现。故门禁对去注释后的代码提问（`ensureCode`）。这不是洁癖：不先去注释，这两条断言在
> 正确实现下也无法通过。

**② hap 声明的最低 API 与 sysroot 存在落差。** `ohos/build-profile.json5` 的
`compatibleSdkVersion` 为 `5.1.0(18)`，而本机 OHOS native sysroot 是 API 26。对
`libturna_anki.so` 逐串核过：含 `OH_TimeService_GetTimeZone` / `dlopen` /
`pthread_create`，**不含** `__android_log_print` / `__system_property_get`，暂未发现会在
API 18 设备上炸的符号。**API 26 加载收据不等于最低 API 18 兼容收据。**

**③ 引擎产物随 hap 提交（路线 A）。** `.so` 已提交进
`ohos/entry/libs/arm64-v8a/libturna_anki.so`——**路线 A = 提交产物而非构建时拷贝**，
因为伴生版尚无 CI 作业，提交产物才可复现。hap 内该文件经 hvigor strip 后**不等于**源文件
字节，但逐串核过**内容等价**（bridge 符号全在；`NEEDED` 仍只有 `libc.so` +
`libtime_service_ndk.so`，**无 `libsqlite3.so`**；ELF64 / `e_machine` = `0xB7`（aarch64））。
`libturna_anki.so` **只有 arm64-v8a 一份**——门禁按「`.so` 实际落点」而非目录名断言，因为
模板留下一个空 `libs/x86_64/`，git 不跟踪空目录，按目录名断言会在本地红、新克隆绿。
### 2.11 门禁处置：**移除**而非重写（显式决策，非疏漏）

§2.1 记录的前置条件写明：「若将来真的推进鸿蒙产品线，必须先撤销原 ADR 0041（已删）并重写门禁，不能靠
加白名单绕过。」本文执行了「撤销原 ADR 0041（已删）§决策 2」，但**选择移除相关断言而不是把它们改写成
二态 ratchet**。

移除的断言：`ohos_eol_architecture_guard_test.dart` 的
`capability matrix never requires Legacy fallback writers` 中「不得出现 `case 'ohos':`」
一条（原为无条件断言）；`anki_import_execution_plan_test.dart` 中把 `'ohos'` 列进
`ankiUnavailable` / `unsupported` 的三处。
### 2.12 接线批次的验收判据

接线按依赖顺序分步（步 0 探针 → 步 1 `.so` 装进 hap → 步 2 重写 SQLite 分派 → 步 3 平台
路由 → 步 4 撤降级标记 → 步 5a 定 Dart 接线路线 → 步 5b ArkTS 复习器页面 → 步 6 独立 CI
workflow），每步都有独立可回滚边界。
## 影响与边界

### 3.1 伴生版的能力边界

| 能力 | 鸿蒙状态 | 依据 |
|---|---|---|
| `.apkg` 导入 | 接线已修复，真机完整导入待验 | 平台路由 + 真实 locator 修复 |
| 课程树投影 / SRS 调度 | 有实现，鸿蒙用户流待验 | 修复 RDB 原子换页；engine-info 不证明实际调度 |
| 共享 catalog | SQLite 加载已验证；真实 locator 已修复，设备待复跑 | 内存探针 + 冷启动修复 |
| **保真复习器（原卡渲染）** | **真机可用**：渲染 / 翻卡 / 评分落库 / 队列前进 | 真机首卡收据；判据与接线契约见 §2 |

此前入口开着、卡片渲染给出 `official_anki.renderer_ohos_pending` 明确文案而非禁用入口，
理由是：**一个「点了没反应」的入口比一个不存在的入口更难归因。** 当前失败形态是打开复习
ability 失败时的 `render_failed` + 重试，以及会话未就绪时拦截层的 503
`reviewer_not_open`——两者都是可恢复的明确失败，不是静默降级。
### 3.2 不成立 / 不做的事

- **不得写「鸿蒙支持 Official Anki」**：完整用户流中真机导入与课程学习解锁仍无收据、步 6 CI
  首跑收据未取、伴生版不进主交付——「支持」是产品级断言，余项未清前不成立。
- 也不得反向写「鸿蒙复习器做不出来」——ArkUI `Web` 满足 CSP / 自定义 scheme / Range/206
  已由真机收据证明，复核链路已在真机走通。
- 路线 E 放弃「卡片列表连续滚动、每张卡都是活渲染」这个形态。
- 依赖脚本自动出声的卡片模板在鸿蒙上不会自动播（§2.4）。
- ADR 0047 的「复习器 5–8 人日」**不可引用为预算**（§2.3）。

### 3.3 对外文档的连带义务

平台矩阵（`docs/project-guide.md` §10.1）与 `docs/android-build-setup.md` 的退役节须按本 ADR
各节结论改写，**不得写成产品级「已支持」**；`test/BASELINE.md` 前插一条收据；Android / iOS
行为不得回归（`flutter analyze` 0 issue，`flutter test --exclude-tags golden` 保持既有通过数）。

