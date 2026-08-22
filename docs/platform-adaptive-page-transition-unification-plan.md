# Turna 平台自适应页面过渡统一计划

> 状态：**代码侧已实施（2026-08-22）**；真机性能采样（RT-001）与 Android/iOS 手工验收矩阵（RT-004/RT-009 真机部分）待执行，见 §13 实施记录  
> 日期：2026-08-22  
> 范围：全屏页面 push/pop、Android 预测返回、iOS/macOS 边缘返回、减弱动效、导航入口收口与转场性能验收  
> 不包含：页面内动画、题目反馈动画、Dialog/BottomSheet 动画、底部主 Tab 的视觉改版

## 0. 结论先行

Turna 的全屏页面导航统一采用 Flutter/AutoRoute 提供的平台自适应默认行为：

```text
Android / Fuchsia       -> Material 平台默认页面路由与系统返回语义
iOS / macOS             -> Cupertino 页面路由与边缘返回手势
Windows / Linux         -> Material 桌面默认行为
Web                     -> AutoRoute adaptive 的 Web 默认行为
系统或应用减弱动效开启   -> 遵循系统无障碍动画策略
```

不得继续把某一个平台的风格强制应用到全部平台，不新增自定义曲线、视差、阴影、模糊、缩放或人为延长的转场。

本轮核心改动是把当前全局强制的：

```dart
RouteType get defaultRouteType => const RouteType.cupertino();
```

替换为平台自适应路由，并把绕开 AutoRoute 的全屏 `MaterialPageRoute` 入口一并收口。只改全局这一行而保留零散手写路由，不算完成。

## 1. 背景与问题定义

当前用户可感知的问题不是页面持续滚动卡顿，而是每次进入新页面时出现掉帧。代码层的共同路径有两条：

1. 32 个已注册页面通过 AutoRoute 导航；`AppRouter.defaultRouteType` 强制返回 `RouteType.cupertino()`。
2. 另有 24 处 `MaterialPageRoute`，分布在 15 个文件中，绕开全局 AutoRoute 策略。

强制 Cupertino 路由在 Android 上执行约 500ms 的 iOS 风格全屏滑入、旧页视差移动和动态边缘阴影。转场首帧还要完成目标页面首次 build/layout/raster；旧页面通常是带 `IndexedStack` 和毛玻璃底栏的 `HomePage`。在高刷 Android 设备上，120Hz 帧预算约为 8.3ms，因此即使旗舰设备也可能在路由创建或首次栅格化时错过 vsync。

零散 `MaterialPageRoute` 又形成第二套导航行为，使不同入口的动画、返回手势和性能表现不一致。

## 2. 目标与非目标

### 2.1 目标

1. 全屏页面只使用平台自适应默认路由，不自行设计“Turna 转场风格”。
2. Android 使用 Flutter 当前 SDK 的 Material 默认转场，并支持平台预测返回。
3. iOS/macOS 使用实际 Cupertino 路由，保留边缘滑动返回，而不只是视觉上模仿 Cupertino。
4. AutoRoute 与手写 Navigator 入口遵守同一策略。
5. 系统“减少动态效果”和 Turna“减弱动效”设置继续生效。
6. 页面切换在 Profile/Release 构建和 120Hz Android 真机上无连续掉帧。
7. 平台页面路由、弹层和底部 Tab 的语义保持清晰，避免把所有导航都塞进一种动画。

### 2.2 非目标

1. 不把每个 Flutter 页面拆成 Android Activity 或 iOS ViewController。
2. 不追逐 One UI、ColorOS、OriginOS 等 OEM 私有 Activity 动画；Flutter 页面位于同一个 Activity 内，只遵循 Flutter 官方的平台导航规范。
3. 不在本轮重做页面 UI、阴影、卡片样式或业务数据加载。
4. 不给底部四个主 Tab 增加左右滑动、缩放或 Hero 动画。
5. 不改变 Dialog、BottomSheet、PopupMenu、SnackBar 的组件语义。
6. 不以缩短动画掩盖目标页面首帧过重；若仍有个别页面掉帧，必须依据 trace 单独处理。

## 3. 不再摇摆的设计决策

### D1：AutoRoute 全局使用 `RouteType.adaptive`

目标配置：

```dart
@override
RouteType get defaultRouteType => const RouteType.adaptive(
      enablePredictiveBackGesture: true,
    );
```

约束：

- 不改成全局 `RouteType.material()`，否则会把 Android 路由语义强加给 iOS/macOS。
- 不使用全局 `RouteType.custom()`。
- 不设置自定义 `duration`、`reverseDuration` 或 `transitionsBuilder`。
- 保持 AutoRoute 默认 `allowSnapshotting: true`；只有真机证明某个 PlatformView 页面出现黑帧/陈旧帧时，才允许在该路由上单独关闭并记录原因。

### D2：底部主 Tab 保持即时切换

学习、游玩、个人、设置是同一导航层级的四个目的地，不是 push/pop 页面。当前 `IndexedStack` 切换保持无页面转场：

- 不做 Cupertino 横向滑动。
- 不做 Material 页面 push。
- 不做跨 Tab Hero。
- 本计划不处理 `IndexedStack` 的懒加载；该问题可在独立性能任务中处理。

### D3：弹层保留弹层语义

- `showDialog` 继续作为 Dialog。
- `showModalBottomSheet` 继续作为 BottomSheet。
- PopupMenu、Date/Time Picker 继续使用 Flutter 平台组件。
- 不为了“统一动画”把弹层改成全屏 PageRoute。

### D4：正式全屏页面优先收口到 AutoRoute

用户可达、具备稳定页面身份的全屏页面必须注册为 `@RoutePage()`，从调用处使用 `context.router.push(...)` 或等价的类型安全入口。

理由：

- 统一走 `RouteType.adaptive`。
- 统一守卫、深链、测试和返回栈语义。
- iOS/macOS 获得实际 Cupertino 路由和边缘返回能力。
- 避免调用处自行决定平台动画。

### D5：运行时内部页面只允许“原生路由选择器”，不允许自定义动画

少量仅供内部诊断、由运行时组装 Widget 的页面若不适合进入生成路由表，可保留一个集中式平台路由工厂：

```text
iOS/macOS -> CupertinoPageRoute
其余平台   -> MaterialPageRoute
```

该工厂只能选择 Flutter 官方路由类：

- 禁止 `PageRouteBuilder`。
- 禁止 `transitionsBuilder`。
- 禁止自定义曲线、时长、透明度或变换。
- 调用点不得再直接实例化 `MaterialPageRoute`/`CupertinoPageRoute`。

如果最终盘点证明所有内部页都能静态注册，则不新增该工厂，全部走 AutoRoute。

### D6：不覆盖 `ThemeData.pageTransitionsTheme`

Android 的 Material 路由应读取当前 Flutter SDK 的平台默认 `PageTransitionsTheme`。主题层不得新增 Turna 专属页面动画，也不得固定某一代 Android 动画。

### D7：转场性能与页面首帧性能分开验收

完成平台自适应迁移后：

- 如果轻量页面也掉帧，继续检查路由/图层合成。
- 如果只有数据库、WebView、长列表页面掉帧，视为目标页首帧初始化问题，单独延后工作或增加轻量骨架。
- 不允许为了个别重页面重新引入全局无动画或全局自定义短动画。

## 4. 当前导航盘点

### 4.1 AutoRoute 主路径

`lib/routing/routing.dart` 当前注册 32 个页面，全部继承全局强制的 Cupertino 类型。第一阶段统一切换后，这些路由会自动获得平台自适应行为。

需要重点回归的代表页面：

| 类型 | 代表路由 | 验证重点 |
| --- | --- | --- |
| 轻量列表 | `SectionPickerRoute` | 用于隔离纯转场掉帧 |
| 普通长列表 | `AchievementsRoute` / `ReviewProgressRoute` | 首帧布局与滚动状态 |
| 有初始化任务 | `NewLessonRoute` / `SrsReviewRoute` | 转场与异步启动是否竞争 |
| 大型页面 | `AnkiImportRoute` | 首帧构建时间、返回栈 |
| PlatformView | 官方 Anki reviewer 相关入口 | snapshot、黑帧、返回手势 |
| 带守卫 | `DictionaryRoute` / `AiHubRoute` | redirect 不产生双重动画 |

### 4.2 直接 `MaterialPageRoute` 路径

当前共 24 处，分布在以下文件：

- `lib/application/anki_official/official_anki_internal_page.dart`
- `lib/views/ai/ai_api_config_page.dart`
- `lib/views/ai/ai_hub_page.dart`
- `lib/views/ai/components/ai_not_configured_panel.dart`
- `lib/views/anki/anki_import_screen.dart`
- `lib/views/anki/anki_review_screen.dart`
- `lib/views/anki_official/official_anki_canonical_link_view.dart`
- `lib/views/anki_official/official_anki_source_management_page.dart`
- `lib/views/settings/about_turna_page.dart`
- `lib/views/settings/privacy_details_page.dart`
- `lib/views/settings/settings_page.dart`
- `lib/views/settings/system_health_page.dart`
- `lib/views/settings/widgets/settings_about_section.dart`
- `lib/views/settings/widgets/settings_account_section.dart`
- `lib/views/settings/widgets/settings_advanced_section.dart`

施工时逐项分类：

| 分类 | 处置 |
| --- | --- |
| 正式用户可达全屏页 | 注册 AutoRoute，替换为类型安全 push |
| 已有 AutoRoute 但调用处绕行 | 改用已有 Route，不新增重复页面定义 |
| 内部/诊断静态页 | 优先注册 AutoRoute；确有运行时限制再使用 D5 工厂 |
| Dialog/Sheet 内容 | 保持弹层，不纳入 PageRoute 迁移 |
| 外部系统页面 | 保持 `url_launcher`/平台 API，不包装为 Flutter 页面转场 |

### 4.3 当前没有的模式

当前生产 `lib/` 中没有 `PageRouteBuilder`、`RouteType.custom` 或显式 `transitionsBuilder`。本轮应保持这一点，不用新自定义动画替换旧 Cupertino 动画。

## 5. 目标架构

```text
用户触发导航
  |
  +-- 底部主 Tab --------------------> IndexedStack 即时切换
  |
  +-- Dialog / BottomSheet ----------> Flutter 对应弹层 API
  |
  +-- 正式全屏页面 -------------------> AutoRoute
  |                                      |
  |                                      +-- RouteType.adaptive
  |                                           +-- Android: Material route
  |                                           +-- iOS/macOS: Cupertino route
  |                                           +-- Web/desktop: 平台默认
  |
  +-- 极少量运行时内部页 -------------> 官方路由类选择器（无自定义动画）
```

导航调用层不得知道动画曲线、位移、阴影或时长；它只表达“进入哪个页面”。平台路由负责“怎样进入”。

## 6. 分阶段实施计划

### P0：建立可复现基线

任务：

1. 使用最新 Android 旗舰真机的 Profile 和 Release 构建采样，Debug 仅用于功能调试，不作为性能结论。
2. 记录屏幕实际刷新率和每帧预算；120Hz 以 8.3ms 为基准，60Hz 以 16.7ms 为基准。
3. 对以下三组各执行至少 20 次 push/pop：
   - 轻量页：`SectionPickerRoute`。
   - 普通页：`AchievementsRoute` 或 `ReviewProgressRoute`。
   - 重页面：课程、Anki 或 WebView 页面。
4. 保存 Flutter DevTools Performance trace，区分 UI、Raster 和 shader/pipeline 峰值。
5. 记录开启“减弱动效”后的 A/B 结果，确认掉帧与 route animation 的相关性。

交付：

- 基线设备、构建模式、刷新率、Flutter commit/version。
- 每组转场的 janky frame ratio、最长 UI frame、最长 Raster frame。
- 至少一份轻量页和一份重页面 trace。

### P1：切换 AutoRoute 全局策略

任务：

1. 将 `AppRouter.defaultRouteType` 改为 `RouteType.adaptive(...)`。
2. 开启并验证 AutoRoute 的 Android predictive-back 支持。
3. 核对 Android 工程的系统返回配置；若当前 Flutter/Android embedding 要求 manifest opt-in，则只添加官方要求的配置，不增加自定义返回动画。
4. 保持 `allowSnapshotting` 默认开启。
5. 重新生成 `routing.gr.dart`（如果生成器输出发生变化）。
6. 增加路由策略契约测试，防止未来重新强制 Cupertino/Material。

阶段验收：

- Android 自动路由使用 Material 路由。
- iOS/macOS 自动路由使用 Cupertino 路由。
- Web 不出现移动端横向滑入。
- AutoRoute 页面不再全平台强制 iOS 动画。

### P2：收口正式手写全屏路由

任务：

1. 对 §4.2 的 24 处调用建立迁移清单，逐项标注目标 Route 名称。
2. 已有 Route 的页面直接替换调用；禁止创建第二个语义重复 Route。
3. 没有 Route 的正式页面补 `@RoutePage()` 和 `AutoRoute(...)`。
4. 保留参数和返回值的静态类型，例如布尔确认结果、mapping draft、导入结果。
5. 将调用处的 `Navigator.push(MaterialPageRoute(...))` 改成 AutoRoute push。
6. 每迁一组就运行生成器、分析和相关 widget 测试，避免一次性生成巨大不可审阅 diff。

推荐批次：

- P2-A：设置/关于/隐私/系统健康页面。
- P2-B：AI 配置与 AI Hub 子页面。
- P2-C：Anki 用户可达页面。
- P2-D：官方 Anki 内部与诊断页面。

阶段验收：

- 用户可达全屏页面不再直接构造 `MaterialPageRoute`。
- 所有生产导航进入同一 AutoRoute 栈。
- 返回结果、深链和 guard 行为无回归。

### P3：处理确实无法注册的运行时内部页

任务：

1. 复核 P2-D 遗留项是否确实依赖运行时 Widget。
2. 若无遗留，不新增任何平台路由工厂。
3. 若存在遗留，在 `lib/routing/` 增加唯一的官方路由类选择器。
4. 用静态检查禁止其他文件直接创建 `MaterialPageRoute`、`CupertinoPageRoute` 或 `PageRouteBuilder`。
5. 为选择器添加 Android/iOS/macOS 平台分支测试。

阶段验收：

- 只有一个被明确允许的内部路由选择位置。
- 选择器没有动画参数。
- 内部入口在 Android/iOS 的返回手势和转场语义正确。

### P4：无障碍与返回行为收口

任务：

1. 验证系统“移除动画/减少动态效果”设置。
2. 验证 Turna“减弱动效”设置继续通过根 `MediaQuery` 生效。
3. Android 验证：系统返回按钮、返回手势、预测返回预览、取消返回手势。
4. iOS 验证：左缘返回、半途取消、返回后页面状态保持。
5. 验证 Dialog/BottomSheet 不被页面路由策略影响。
6. 验证 Home 四个 Tab 不产生 push 历史，不播放页面转场。

阶段验收：

- 减弱动效不再播放完整页面位移动画。
- 预测返回不会触发双重 pop、黑屏或旧页面重建。
- iOS 边缘返回不会被 Material 路由调用点破坏。

### P5：转场完成后的针对性性能修复

仅当 P1～P4 后 trace 仍证明某些页面掉帧时执行：

1. 目标页第一帧先建立完整 `Scaffold` 和轻量骨架。
2. 非首屏必需的数据库读取、JSON 解码、列表聚合或 PlatformView 创建延后到路由转场完成后。
3. 不在 `build()` 中启动异步任务。
4. 不用固定 `Future.delayed` 猜测动画时长；应监听路由 animation 状态或使用明确的首帧/转场完成信号。
5. 每个延后项必须有 before/after trace，证明它确实位于掉帧帧内。
6. PlatformView 路由若存在 snapshot 黑帧，可单路由评估 `allowSnapshotting: false`，不得全局关闭。

阶段验收：

- 轻量页转场无连续掉帧。
- 重页面即使数据未完成，也能平滑进入并显示稳定骨架。
- 不引入点击后无反馈的等待窗口。

### P6：清理与文档收口

任务：

1. 删除过时的 Cupertino 强制策略注释。
2. 在 `docs/project-guide.md` 写明导航规范。
3. 增加 CI 契约：禁止新的通用 `PageRouteBuilder` 和直接全屏路由分叉。
4. 在实施记录中列出允许保留的例外及理由。
5. 保存最终 Android/iOS 手工验收矩阵和性能结果。

## 7. 测试计划

### 7.1 静态/契约测试

新增路由策略测试，至少覆盖：

1. `routing.dart` 不包含全局 `RouteType.cupertino()` 或 `RouteType.material()`。
2. 默认类型为 `RouteType.adaptive`。
3. 生产 `lib/` 不出现未列入 allowlist 的 `PageRouteBuilder`、`transitionsBuilder`。
4. 用户可达页面不直接构造 `MaterialPageRoute`/`CupertinoPageRoute`。
5. Bottom Tab 继续走 `TabRouter`/`IndexedStack`，不进入根 Navigator 栈。

### 7.2 Widget 测试

1. Android platform override 下 push/pop 正常，路由为 Material 语义。
2. iOS/macOS platform override 下路由为 Cupertino 语义。
3. 页面返回值可穿过 AutoRoute 正确返回调用方。
4. guard redirect 只发生一次，不叠加两段转场。
5. `reducedMotion=true` 时根 MediaQuery 标志正确传入 Navigator 子树。
6. Tab 切换保留各页状态且不增加 Navigator stack depth。

### 7.3 真机矩阵

| 平台 | 构建 | 必测项目 |
| --- | --- | --- |
| Android 最新旗舰 120Hz | Profile + Release | push/pop、预测返回、连续 20 次、轻/中/重页面 |
| Android 中端 60/90Hz | Release | 首次打开、冷/热路由、长列表 |
| Android 低版本 | Release | 系统返回兼容、无预测返回时正常降级 |
| iPhone | Profile/Release | Cupertino 滑入、边缘返回、取消手势 |
| Linux/Windows | Profile | 默认桌面行为、无移动端边缘手势 |
| Web | Release | 不出现移动端强制横向转场、浏览器返回正常 |

### 7.4 性能门槛

以 Profile/Release 真机 trace 为准：

1. 热路由连续 20 次 push/pop 不出现连续两个以上 missed-vsync frame。
2. janky frame ratio 低于 1%；若平台工具和 Flutter 指标口径不同，报告中同时保留原始口径。
3. 120Hz 下 UI/Raster P99 目标低于 16.7ms，并持续推动到 8.3ms 帧预算；不得用平均值掩盖尖峰。
4. 转场开始后必须在首帧提供可见反馈，不出现点击后空等。
5. 第一次 shader/pipeline warm-up 与热路由结果分开记录。
6. PlatformView 页面不得出现黑帧、闪屏、陈旧快照或双层 AppBar。

## 8. 预计文件影响

核心文件：

- `lib/routing/routing.dart`
- `lib/routing/routing.gr.dart`（生成文件）
- `lib/views/app.dart`（原则上只验证，不应新增动画配置）
- §4.2 所列的直接路由调用文件
- 新增的路由策略/导航 widget 测试
- `docs/project-guide.md`

条件性文件：

- `android/app/src/main/AndroidManifest.xml`：仅在当前 embedding 的预测返回要求真机 opt-in 时修改。
- `lib/routing/platform_page_route.dart`：仅当 P3 证明存在无法静态注册的内部页时新增。

明确不应修改：

- `lib/views/theme.dart`：不加入 `pageTransitionsTheme` 覆盖。
- BottomNavigator 的选中动画：不属于全屏页面转场。
- Dialog/BottomSheet 的默认动画。

## 9. 风险与防护

| 风险 | 后果 | 防护 |
| --- | --- | --- |
| 只改全局 RouteType | 手写路由仍分叉 | P2 强制盘点 24 处调用 |
| 全部改成 Material | iOS 丢失真实边缘返回 | 必须使用 adaptive |
| 自定义“更轻”动画 | 再次偏离平台默认，未来维护成本上升 | 禁止 custom transition |
| 预测返回配置不完整 | Android 返回闪屏/双 pop | 真机手势矩阵 + integration test |
| PlatformView snapshot 不兼容 | WebView 黑帧或陈旧帧 | 仅单路由例外，保存证据 |
| 目标页首帧仍过重 | 换动画后仍掉帧 | P5 依据 trace 延后初始化 |
| 大批生成路由一次提交 | diff 难审、回归难定位 | P2 分四批提交 |
| 静态规则误伤测试/内部代码 | CI 噪声 | 明确目录范围和最小 allowlist |

## 10. 提交与回滚策略

建议拆分为以下可独立回滚的提交：

1. `test(routing): add transition baseline and policy contracts`
2. `refactor(routing): use platform-adaptive default routes`
3. `refactor(routing): migrate settings and about page pushes`
4. `refactor(routing): migrate AI page pushes`
5. `refactor(routing): migrate Anki page pushes`
6. `refactor(routing): consolidate internal adaptive navigation`
7. `perf(routing): defer trace-proven heavy first-frame work`（如需要）
8. `docs(routing): record adaptive navigation contract and evidence`

如果某阶段出现严重回归，只回滚对应批次，不恢复全局强制 Cupertino。若 `adaptive` 本身存在框架级阻断，应先回退为平台官方 Route 类选择器，而不是重新加入自定义动画。

## 11. Definition of Done

以下条件全部满足才算完成：

- [x] AutoRoute 默认使用平台自适应路由。（`routing.dart` → `RouteType.adaptive(enablePredictiveBackGesture: true)`）
- [x] Android 不再播放强制 Cupertino 500ms 转场。（契约测试 + Android 平台语义测试证明 Material 路由；真机复核见 RT-004）
- [x] iOS/macOS 保留实际 Cupertino 路由与边缘返回。（平台语义测试断言真实 `CupertinoPageRoute` 类）
- [x] 24 处直接 `MaterialPageRoute` 已迁移或有唯一、书面化例外。（实际盘点 23 处：22 处迁入 AutoRoute，1 处走 D5 工厂，见 §13）
- [x] 生产代码没有自定义页面转场曲线、时长或阴影。（契约测试扫描 `PageRouteBuilder`/`transitionsBuilder` 为零）
- [x] Bottom Tab、Dialog、BottomSheet 保持正确导航语义。（契约测试锁定 `IndexedStack`；弹层未改动）
- [ ] Android 预测返回和普通返回均通过真机测试。（manifest opt-in 与 `enablePredictiveBackGesture` 已就绪；真机矩阵待执行）
- [ ] Turna 与系统减弱动效设置通过测试。（根 `MediaQuery` 注入逻辑未改动保留；真机/集成验证待执行）
- [ ] 120Hz Android Profile/Release 性能达到 §7.4 门槛。（需 RT-001 真机采样）
- [ ] 重页面残余掉帧均有 trace、责任页面和独立修复记录。（依赖 RT-010 真机复测）
- [x] `flutter analyze`、相关 widget/unit tests 和路由生成检查通过。（analyze 无 error；全量测试与迁移前基线一致，见 §13）
- [x] `docs/project-guide.md` 已记录导航合同。

## 12. 实施任务编号

| ID | 任务 | 依赖 | 产物 | 状态 |
| --- | --- | --- | --- | --- |
| RT-001 | 采集轻/中/重页面转场基线 | 无 | Profile/Release trace | **待执行**（需真机） |
| RT-002 | 增加路由策略契约测试 | RT-001 | routing policy test | 完成（`test/routing/routing_policy_contract_test.dart`） |
| RT-003 | AutoRoute 改为 adaptive | RT-002 | `routing.dart` 变更 | 完成 |
| RT-004 | Android 预测返回验证 | RT-003 | 设备记录/必要配置 | 代码侧完成（manifest opt-in + 契约测试）；真机验证待办 |
| RT-005 | 设置/关于路由迁移 | RT-003 | P2-A diff | 完成 |
| RT-006 | AI 路由迁移 | RT-003 | P2-B diff | 完成 |
| RT-007 | Anki 正式路由迁移 | RT-003 | P2-C diff | 完成 |
| RT-008 | 内部/诊断路由收口 | RT-007 | P2-D/P3 diff | 完成 |
| RT-009 | 无障碍与跨平台手势测试 | RT-005～008 | 测试矩阵 | widget 层平台语义测试完成；真机手势矩阵待办 |
| RT-010 | 复测并定位残余首帧掉帧 | RT-009 | before/after trace | 待执行（需真机） |
| RT-011 | 条件性首帧性能修复 | RT-010 | 独立性能提交 | 未触发（依赖 RT-010 结论） |
| RT-012 | 文档与 CI 规则收口 | RT-011 | 项目指南/最终报告 | 完成（CI 经由 `flutter test` 运行契约测试；真机矩阵部分留待 RT-004/009） |

## 13. 实施记录（2026-08-22）

### 13.1 代码改动

- **P1（RT-003）**：`lib/routing/routing.dart` 的 `defaultRouteType` 由 `RouteType.cupertino()` 改为 `RouteType.adaptive(enablePredictiveBackGesture: true)`；`android/app/src/main/AndroidManifest.xml` 增加 `android:enableOnBackInvokedCallback="true"`（Flutter 官方预测返回 opt-in）。`allowSnapshotting` 保持默认开启，未新增任何 duration/transitionsBuilder。
- **P2（RT-005～008）**：§4.2 清单实际盘点为 23 处直接 `MaterialPageRoute`（文档原记 24，其中 1 处为注释）。22 处改为 `context.router.push(...)`，1 处改走 D5 工厂。新增 `@RoutePage()` 页面 12 个并注册：`AboutTurnaRoute`、`PrivacyDetailsRoute`、`ChangelogRoute`、`TransparencyLogRoute`、`AiApiConfigRoute`、`AvatarRingsRoute`、`OfficialAnkiInternalRoute`、`OfficialAnkiMappingRoute`、`OfficialAnkiReviewerRoute`、`OfficialAnkiReviewRoute`、`OfficialAnkiMigrationPreviewRoute`、`OfficialAnkiSourceManagementRoute`。另把已生成但从未注册的 `AnkiDeckStatsRoute`、`AnkiCardBrowserRoute` 补注册（原先调用点若走路由会失败）。注册路由总数 30 → 44。
- **P3（RT-008）**：新增 `lib/routing/platform_page_route.dart` 唯一官方路由类选择器（iOS/macOS → `CupertinoPageRoute`，其余 → `MaterialPageRoute`，无任何动画参数）。`officialAnkiBuildSourceManagementPage` 重构为 `officialAnkiResolveSourceManagementDeps`（返回依赖 record 而非运行时 Widget），使课程映射页可静态注册，消掉一处预期例外。
- **P6（RT-012）**：`docs/project-guide.md` §3「关键模式」写入导航合同；CI 契约由下述测试承担（`flutter_ci.yml` 已运行 `flutter test`）。

### 13.2 允许保留的例外（D5 工厂使用点，共 1 处）

| 调用点 | 理由 |
| --- | --- |
| `lib/views/anki_official/official_anki_canonical_link_view.dart` 官方路径解析失败时 push 的内联错误 `Scaffold` | 运行时组装、无稳定页面身份，不适合注册路由表；经 `platformPageRoute` 选择官方路由类 |

### 13.3 新增测试

- `test/routing/routing_policy_contract_test.dart`：默认路由 adaptive + 预测返回开启、无 per-route 类型分叉、无 `PageRouteBuilder`/`transitionsBuilder`、官方路由类仅在允许文件构造、`IndexedStack` 底部 Tab、`theme.dart` 不覆盖 `PageTransitionsTheme`、manifest opt-in 存在。
- `test/routing/adaptive_route_semantics_test.dart`：使用真实 `AppRouter.defaultRouteType` 实例驱动测试路由，断言 Android→Material、iOS/macOS→真实 `CupertinoPageRoute`、push/pop 往返。
- `test/routing/platform_page_route_test.dart`：D5 选择器的平台分支与 Navigator 往返。
- `test/views/lesson/renderers/renderer_test_helper.dart` 新增 `buildRouted`：为经 `context.router` 导航的渲染器提供 AutoRoute 搭桩（`show_word_test` 相应用例迁移）。

### 13.4 验证结果

- `flutter analyze`：无 error；新增代码无 warning（仓库既有 info/warning 未触碰）。
- `flutter test` 全量：与迁移前基线一致——仅 10 个预先存在的失败（8 个 golden 字体渲染 + 2 个 anki import 流程用例，已在 HEAD 上复现确认与本次改动无关）；本次改动引入的失败为 0。
- `dart run build_runner build`：`routing.gr.dart` 正常再生成。

### 13.5 待执行（真机部分）

1. RT-001 基线采样与 §7.4 性能门槛验收（Profile/Release、120Hz 真机）。
2. RT-004 Android 预测返回真机验证（需在开发者选项开启预测返回动画）。
3. RT-009 真机手势矩阵：iOS 边缘返回/半途取消、Android 三键/手势/预测返回、减弱动效 A/B。
4. RT-010/011 视 trace 结论决定是否做目标页首帧延后优化。

