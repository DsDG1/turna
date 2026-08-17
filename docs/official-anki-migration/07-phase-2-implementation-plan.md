# Phase 2 官方原卡渲染实施计划

> 状态：已施工；结果见 `08-phase-2-result-report.md`（`P2 TECHNICAL CONDITIONAL GO / P2 PRODUCTION NO-GO`）  
> 制定日期：2026-08-17  
> 当前分支：`spike/official-anki-core-android`  
> 计划基线：`cc1484b3`（实际开工时由 P2-000 重新记录完整 SHA）  
> 上游 Anki pin：`967aa0d578fc75181e292e95326f9b58698da25c`  
> 首发平台：Android arm64  
> 前置结果：`06-phase-0-phase-1-technical-remediation-result.md` 的
> `TECHNICAL CONDITIONAL GO`  
> 明确排除：License、AGPL 展示、源码要约、法律确认及其签字  
> 生产切流：本计划全部硬门禁通过前保持关闭

## 1. 目的

Phase 0 已验证官方 Anki `rslib` 可以在 Host 和 Android arm64 上运行，Phase 1 已建立
稳定 C ABI、contract v1、真实 FFI transport、持久 worker isolate、官方导入 Saga、
Collection backup/recovery 和来源 catalog。Phase 2 不再自行解释模板，而是把官方
Collection 的渲染结果接入一个独立、可复用、受限制的 Android Reviewer WebView。

本计划同时纳入 Phase 0/1 收口后仍会阻碍长期 Reviewer 会话的修补项，避免在有资源泄漏、
主 isolate 自动回退或隐藏 operation 的底座上继续施工。

Phase 2 要解决的用户可见问题是：

1. Unicode 字段和媒体文件名不再因自研解析链路出现乱码。
2. Basic、Reverse、Cloze、FrontSide 和多模板卡按官方 Card ID 渲染。
3. 原始 Anki Card 始终走同一个 Reviewer WebView，不再按 HTML 特征猜测 Flutter/WebView。
4. 正面和背面在同一个 WebView 实例中切换，不再交换字段或拼接两套文档。
5. 音频、视频标记和 TTS 参数来自官方 AV tag，而不是 Dart 正则扫描。
6. Typed Answer 使用官方 Cloze 提取和答案比较语义。
7. MathJax 在离线状态可用。
8. 卡片 JavaScript 无法访问应用文件、任意网络和原生接口。
9. 官方路径失败时明确报错，不自动回退旧模板 renderer 或 Turna SRS。

## 2. 阶段决策

当前允许开始 P2 的 contract、Host、PlatformView 和安全媒体 Spike，因此结论是：

```text
P2 CONSTRUCTION GO
P2 PRODUCTION NO-GO
```

`CONSTRUCTION GO` 不代表可以打开生产 flag。生产启用必须同时满足：

- 本计划 P2-000～P2-060 的硬门禁。
- Phase 1 遗留的 Android release、第二设备、clean CI、真实 Native cancel 条件。
- 产品另行决定的 native 体积条件。
- 本计划范围外的独立发布门禁。

## 3. 命名与阶段边界

本目录统一使用：

```text
Phase 0：技术 Spike
Phase 1：稳定 Engine 与官方导入
Phase 2：官方原卡渲染（本计划）
Phase 3：课程投影
Phase 4：官方 Scheduler
Phase 5：Legacy 迁移与删除
Phase 6：可选 AnkiWeb Sync
```

Phase 2 交付的是“官方原卡渲染和交互预览”，不是完整调度器。P2 页面可以展示卡片、翻面、
播放 AV/TTS 和完成 Typed Answer，但不得把 Again/Hard/Good/Easy 写入 Turna SRS，也不得
提前实现另一套简化官方 Scheduler。

## 4. 范围

### 4.1 本计划包含

- Phase 1 遗留的会话关闭、handle 释放和 fail-closed 修补。
- 将已存在的 Rust `RENDER_CARD` 正式纳入 contract/capability/Dart Engine。
- Typed Answer 的官方字段解析、Cloze 提取和答案比较 operation。
- 新建 Android 专用安全 Reviewer PlatformView。
- `https://anki.local` shell/media origin 和子资源拦截。
- 同一 WebView 的 question/answer 生命周期。
- 官方 AV/TTS tag 到 Turna 播放层的适配。
- 离线 MathJax 和固定版本 reviewer assets。
- 官方卡片浏览/诊断入口和独立 feature flag。
- Host、Dart、Android instrumented、真机、安全和性能测试。
- P2 结果报告、产物 hash、设备证据和 Go/No-Go 决策。

### 4.2 明确排除

- License、About、source offer 和法律结论。
- 正式 Again/Hard/Good/Easy 调度写入。
- FSRS、review queue、revlog、undo/redo UI。
- 完整课程 Section/Unit/Lesson 投影。
- 删除 Legacy importer、renderer、SRS 或现有用户数据。
- AnkiWeb Sync。
- OHOS、iOS、Windows、Linux 和 Web 的正式 Reviewer。
- 完整移植 Anki Desktop Qt、AnkiDroid 页面或整个官方 Reviewer 构建系统。

### 4.3 红线

- 官方 Collection 是 Anki 内容唯一事实源。
- Dart 不读取或修改 `collection.anki2`。
- Dart 不重新实现 Mustache/Cloze/Reverse/FrontSide 模板语义。
- 原始 Anki Card 不走 Flutter HTML renderer。
- 派生课程练习不进入原卡 Reviewer WebView。
- WebView 不使用 `file://` 或 `content://` 访问 Collection media。
- 卡片页面不暴露 `addJavascriptInterface`、JavaScript channel 或通用 native bridge。
- 不以 CSP 作为唯一网络/文件安全措施。
- official renderer 失败不得自动调用 Legacy renderer。
- P2 不删除 Legacy；物理删除留到 Phase 5。
- 不用 Fake、Host、旧 APK 或旧 `.so` 代替 Android 新产物证据。
- 不把“同一个 WebViewController”误写成“同一个未重载的 Reviewer 文档”。

## 5. 当前真实状态

### 5.1 已具备

- Rust Bridge 已定义 `OP_RENDER_CARD = 10`。
- Rust 已调用官方 `Collection::render_existing_card(..., partial_render=false)`。
- 当前响应已包含 question、answer、CSS、`latex_svg`、`is_empty`。
- 当前响应已通过官方 `extract_av_tags()` 返回正反面 sound/video 和 TTS DTO。
- Native golden 已覆盖 Unicode、Reverse、Cloze、FrontSide/CSS 和 media paths。
- fixture 集中已有 Typed Answer、TTS 和 MathJax 类型样本。
- Dart 已有 production DynamicLibrary transport 和持久 worker isolate。
- Official source catalog 已能把 Turna source/card 关联到官方 Card ID。
- 所有 production official flags 默认关闭。

### 5.2 已实现但尚未正式接通

| 项目 | 当前事实 | P2 必须完成 |
|---|---|---|
| `RENDER_CARD` | Rust dispatcher 可调用 | operations 文档、capability、contract minor、Dart API |
| Render golden | Native 覆盖 5 类 | 9 fixture、Host Dart FFI、Android WebView |
| AV/TTS | Native 已返回官方 tag | 正确选择 display HTML、播放生命周期和设备测试 |
| Typed Answer | fixture/上游服务存在 | 高层 Bridge 语义、Dart DTO、UI 和 comparison HTML |
| MathJax | 上游和 fixture 存在 | 离线资源、shell loader、golden |
| WebView | Legacy 组件存在 | 独立安全 PlatformView；旧组件不得复用 |

### 5.3 P2 开工前必须修补的 P1 遗留

#### L-SESSION-DISPOSE：Worker 没有机会优雅关闭

当前 `OfficialAnkiSession.dispose()` 先设置 `_disposed = true`，再调用 `_rpc('dispose')`。
如果 `_rpc()` 拒绝 disposed session，worker 收不到 close/dispose 请求，只能被立即 kill。

风险：

- Native engine handle 留在进程级 registry。
- Collection 锁和文件句柄不能按预期释放。
- Reviewer 多次进入/退出后出现 `COLLECTION_LOCKED`。
- 内存和媒体状态随会话累积。

P2-001 必须先发送 dispose RPC、等待确认，再标记 disposed；超时路径也必须显式调用 control
transport 的 engine close，最后才 kill isolate。

#### L-INPROCESS-FALLBACK：失败后自动回到 UI isolate

当前 composition 捕获 worker isolate 的 `OfficialAnkiException` 后自动创建
`OfficialAnkiInProcessHost`。P2 的长期 Collection 查询和渲染不能依赖该行为。

生产模式必须 fail closed。In-process host 只能由显式 test/internal diagnostics 参数启用，
且界面必须显示当前不是 production worker。

#### L-HIDDEN-RENDER：operation、capability 和 Dart contract 不一致

Rust 能识别 `RENDER_CARD`，但 `ENGINE_INFO.capabilities`、`contract/operations.md` 和 Dart
`OfficialAnkiOperation` 没有该能力。P2 不得绕过 capability 直接调用 operation 10。

#### L-EXTERNAL-GATES：Phase 1 仍是 Conditional Go

- 新 release APK 未完成完整 official import/reopen/render 闭环。
- 第二台 Android 设备未验证。
- Native 导入中 cancel 未在真实 Android/5k 条件验证。
- clean CI runner 尚无一次完整成功记录。
- native 体积仍需产品技术确认。

这些条件不阻止 Host 和内部 debug P2 施工，但阻止 production renderer flag。

## 6. 目标架构

```text
Official Collection
       │ Card ID
       ▼
Rust Bridge / official render_existing_card
       │ strict versioned DTO
       ▼
OfficialAnkiSession persistent worker isolate
       │ OfficialAnkiRenderedCard
       ▼
OfficialAnkiReviewerController
       ├── AV/TTS → AudioController / SmartSpeech
       └── card payload → Android OfficialAnkiReviewerPlatformView
                              │
                              ├── fixed offline reviewer shell
                              ├── same WebView question/answer swap
                              ├── https://anki.local/assets/...
                              └── https://anki.local/media/...
                                       │ canonical path gate
                                       ▼
                                collection.media only
```

Legacy source 和 official source 必须在路由层先分开：

```text
Legacy source   → existing Legacy renderer（Phase 5 前只读保留）
Official source → OfficialAnkiReviewer（失败即错误页，不 fallback）
Turna exercise  → Flutter Widget（不是原始 Anki Card）
```

## 7. Contract 设计

### 7.1 operation 编号

现有编号不可重排：

| 编号 | operation | P2 行为 |
|---:|---|---|
| 10 | `RENDER_CARD` | 将现有内部能力正式发布 |
| 22 | `COMPARE_TYPED_ANSWER` | 按 Card ID/marker 解析 expected 并调用官方 compare |
| 23 | `EXTRACT_CLOZE_FOR_TYPING` | 官方 Cloze 提取；主要供 Rust 高层逻辑和 contract test |

11～16 已预留给 Scheduler，17～21 已被 backup/page/batch/restore 使用，禁止挪用。

新增 operation 后 contract minor 从 `1.0` 增到 `1.1`。主版本不变。旧 Dart 只能在 capability
存在时调用；新 Dart 对不含 capability 的旧 native 必须 fail closed。

### 7.2 `RENDER_CARD` 请求

```json
{
  "cardId": 123,
  "browser": false,
  "includeAvTags": true
}
```

约束：

- `cardId` 必须为正整数。
- production reviewer 固定 `browser=false`。
- `partial_render=false` 由 Rust 固定，Dart 不得覆盖。
- Collection 未打开、Card 不存在、模板渲染失败分别映射稳定 error code。

### 7.3 `RENDER_CARD` 响应

```json
{
  "cardId": 123,
  "questionHtml": "raw official html with AV markers",
  "answerHtml": "raw official html with AV markers",
  "questionDisplayHtml": "official html after AV extraction",
  "answerDisplayHtml": "official html after AV extraction",
  "css": ".card {...}",
  "latexSvg": false,
  "isEmpty": false,
  "questionAvTags": [],
  "answerAvTags": [],
  "typedAnswer": null
}
```

`questionDisplayHtml`/`answerDisplayHtml` 是 UI 唯一允许显示的字段。raw HTML 仅保留用于
contract golden 和诊断，避免 `[sound:...]`/TTS directive 显示或重复播放。

字段命名统一使用 camelCase。Bridge 内部的 snake_case 临时响应必须在本任务中迁移；如果
需要兼容旧测试，Dart 可在一个 contract minor 内读两种名称，但只写 camelCase。

### 7.4 Typed Answer 高层语义

Rust 在渲染时识别 `[[type:Field]]`、`[[type:cloze:Field]]` 和 `[[type:nc:Field]]`，并查询
当前 Card、Note、Notetype field、font/size。Cloze expected 使用官方
`extract_cloze_for_typing()`，不得在 Dart 中解析 `{{cN::...}}`。

建议 DTO：

```json
{
  "marker": "[[type:Back]]",
  "fontFamily": "Arial",
  "fontSizePx": 20,
  "combining": true,
  "clozeOrdinal": null
}
```

expected answer 不必在 render DTO 暴露。`COMPARE_TYPED_ANSWER` 接受：

```json
{
  "cardId": 123,
  "marker": "[[type:Back]]",
  "provided": "learner input"
}
```

Rust 根据同一 Card 再次解析 expected/combining，调用官方 `compare_answer()` 并返回：

```json
{
  "comparisonHtml": "...official diff html...",
  "hasExpected": true
}
```

这样 Flutter 不持有另一份字段/模板解释逻辑，也不会因为 UI 缓存的 expected 与 Collection
更新不同步。

### 7.5 Error mapping

至少覆盖：

| Native 情况 | 稳定错误 | recoverable |
|---|---|---:|
| Collection 未打开 | `INVALID_STATE` | 是 |
| Card 不存在 | `CARD_NOT_FOUND` | 否 |
| 模板渲染失败 | `RENDER_FAILED` | 视 details |
| Typed marker 无字段 | `TYPED_FIELD_NOT_FOUND` | 否 |
| Cloze ordinal 无内容 | `TYPED_CLOZE_EMPTY` | 否 |
| 请求超过限制 | `INVALID_ARGUMENT` | 否 |
| contract 不兼容 | `CONTRACT_VERSION_MISMATCH` | 否 |

用户界面显示稳定本地化 message key；raw backend 文本只进入 debug log，不能直接显示内部路径。

## 8. Reviewer shell 与 Android PlatformView

### 8.1 为什么不复用 Legacy `AnkiHtmlCardView`

旧组件允许 `file://`，使用 unrestricted JavaScript、JavaScript channel、整页
`loadHtmlString()` 和运行后 DOM capture/cache。继续扩展它会让官方和 Legacy 语义再次混合。

P2 新建独立 Android PlatformView，直接持有原生 WebView 和 WebViewClient。不要修改
`webview_flutter` package 源码，不依赖其 Dart navigation callback 充当子资源防火墙。

候选文件：

```text
android/app/src/main/kotlin/me/dsdogs/turna/anki/reviewer/
  OfficialAnkiReviewerPlugin.kt
  OfficialAnkiReviewerFactory.kt
  OfficialAnkiReviewerPlatformView.kt
  OfficialAnkiReviewerClient.kt
  OfficialAnkiMediaHandler.kt
  OfficialAnkiWebPolicy.kt

lib/views/anki_official/
  official_anki_reviewer_view.dart
  official_anki_reviewer_controller.dart
  official_anki_reviewer_page.dart
```

如果采用 app 内 PlatformView 注册，可由 `MainActivity.configureFlutterEngine()` 注册；注册代码
必须独立封装，避免继续把业务逻辑堆进 `MainActivity.kt`。

### 8.2 Shell 生命周期

```text
create WebView
    ↓
apply security settings
    ↓
load https://anki.local/assets/reviewer.html once
    ↓
setCard(questionDisplayHtml, answerDisplayHtml, css, theme)
    ↓
showQuestion
    ↓
showAnswer（同一 WebView、同一 document、同一 qa 容器）
    ↓
clearCard / reuse next card
    ↓
destroy WebView
```

不得在翻面时再次 `loadHtmlString()`；不得创建第二个 WebView；不得把答案作为另一个 Flutter
HTML Widget；不得把正反面长期同时放在 DOM 中再只改透明度。

### 8.3 Shell assets

候选目录：

```text
assets/anki_reviewer/
  reviewer.html
  reviewer.css
  reviewer.js
  mathjax/...
  manifest.json
```

`manifest.json` 至少记录：

- asset version。
- 对应 backend commit。
- 每个文件 SHA-256。
- MathJax 版本。
- 构建命令或来源说明。

只移植/实现移动端所需的最小 Reviewer DOM 更新行为。卡片 `<script>` 的执行语义需要兼容
官方 Reviewer 的 `setInnerHTML` 行为；普通 `element.innerHTML = ...` 不会可靠执行注入脚本，
不能因此误判“自定义 JS 已兼容”。

### 8.4 Flutter ↔ PlatformView 控制协议

允许的 Flutter 到原生方法：

```text
setCard
showQuestion
showAnswer
setTheme
clearCard
dispose
```

原生到 Flutter 事件限制为非特权状态，例如：

```text
ready
pageHeightChanged
renderError
consolePolicyViolation（debug only）
```

卡片 JavaScript 不能直接调用这些 MethodChannel。禁止向 WebView 添加任意 JavaScript
interface/channel。Typed Answer 优先使用 Flutter overlay；如果必须放在 WebView 中，用户输入
只能由 Flutter/原生主动读取固定 `#typeans`，不能开放页面到 native 的通用消息入口。

## 9. 媒体 origin

### 9.1 URL 空间

```text
https://anki.local/assets/<fixed asset>
https://anki.local/media/<percent-encoded filename>
```

其他 host、port、scheme 和路径一律拒绝。`https://anki.local/` 不是实际网络服务；所有允许的
响应都由原生 WebViewClient/asset loader 在进程内生成。

### 9.2 media canonicalization

每个请求执行：

1. 验证 scheme=`https`、host=`anki.local`、port 为空/默认。
2. 只接受 `/media/` 前缀。
3. URL percent-decode 恰好一次。
4. 拒绝 NUL、反斜杠混淆、空绝对路径和平台绝对路径。
5. 将相对名称拼到当前 profile 的 `collection.media`。
6. 对 root 和 candidate 执行 canonical path 校验。
7. candidate 必须等于 root 内文件，不能是目录。
8. 拒绝 `..`、符号链接逃逸和指向其他应用私有目录的路径。
9. 根据扩展名和有限 sniff 设置 MIME，不执行未知内容。
10. 对音视频支持只读 Range 请求和正确的长度/状态头。

Unicode 文件名必须按文件系统实际名称匹配。不得为了“统一字符”擅自做 NFC/NFD 重命名；
测试必须包含空格、`#`、`%`、问号字面量、中文、土耳其语、梵文和组合字符。

### 9.3 媒体拒绝策略

必须返回受控 403/404 空响应，而不是交给系统网络栈继续请求：

- `file://`
- `content://`
- `http://` 和外部 `https://`
- `intent://`
- `javascript:` 顶层导航
- `ws://`/`wss://`
- 非 `anki.local` iframe/script/font/img/audio/video
- `/media/../...`
- 双重编码穿越，如 `%252e%252e`
- symlink escape

## 10. WebView 安全策略

### 10.1 Android settings

至少显式设置：

- JavaScript：开启，服务于官方/自定义卡片兼容。
- file access：关闭。
- content access：关闭。
- file URL universal access：关闭。
- mixed content：never allow。
- geolocation：关闭。
- media playback user gesture：按 AV 设计显式控制。
- multiple windows：关闭。
- downloads：无 DownloadListener 或全部拒绝。
- safe browsing：平台支持时开启。
- third-party cookies：关闭。
- WebView debugging：仅 debug 且 diagnostics flag 开启。
- camera/microphone/MIDI/protected-media permissions：全部拒绝。
- HTTP auth/client certificate：全部拒绝。

### 10.2 Navigation/resource policy

- 主 frame 永远停留在 `https://anki.local/assets/reviewer.html`。
- 卡片 `<a>` 默认不跳转；P2 不直接打开外部浏览器。
- 新窗口、popup、form submit、download 全部拒绝。
- `shouldInterceptRequest` 对所有子资源执行 allowlist，不只检查 main-frame navigation。
- CSP 是第二道防线，不是唯一防线。

候选 CSP：

```text
default-src 'none';
img-src https://anki.local data: blob:;
media-src https://anki.local data: blob:;
font-src https://anki.local data:;
style-src 'unsafe-inline' https://anki.local;
script-src 'unsafe-inline' https://anki.local;
connect-src 'none';
frame-src 'none';
object-src 'none';
base-uri https://anki.local/media/;
form-action 'none';
```

是否允许 `data:`/`blob:` 必须由 fixture 证明必要性；不必要的 directive 从 allowlist 删除。

### 10.3 卡片脚本能力边界

允许卡片脚本：

- 修改自身 DOM/CSS。
- 执行本地交互动画。
- 访问卡片已加载的局部状态。

不允许卡片脚本：

- 读取 Collection 路径或其他应用文件。
- 调用 Dart、Kotlin 或 Rust API。
- 发任意网络请求。
- 请求相机、麦克风、定位、通知。
- 打开新窗口、下载或启动 intent。
- 跨卡片持久化特权状态。

## 11. AV/TTS 适配

### 11.1 数据来源

仅使用 Rust 返回的官方 `questionAvTags` 和 `answerAvTags`。禁止再次扫描 HTML 中的
`[sound:...]` 或 `[anki:tts ...]`。

### 11.2 生命周期

```text
show question → 可按设置自动播放 question tags
show answer   → 停止 question；播放 answer tags
next card     → 停止全部 AV/TTS；清空队列
leave page    → 停止全部；释放 player/session
replay        → 只重播当前 side tags
```

必须去重同一 side 的重复调用，防止 WebView onReady、Flutter rebuild 和翻面事件导致多次播放。

### 11.3 文件与 TTS

- sound/video filename 通过新的 `OfficialAnkiMediaResolver` 在受信任代码中解析。
- resolver 与 WebView media handler 共享相同 canonicalization 规则。
- 不复用允许 http/file 任意输入的 Legacy `AnkiMediaUrlResolver`。
- TTS 映射 `fieldText`、`lang`、`voices`、`speed`、`otherArgs`。
- 设备没有匹配 voice 时展示可恢复提示，不伪装成播放成功。
- P2 不承诺 Anki Desktop 专用 TTS backend；使用 Turna 当前平台语音层。

## 12. Typed Answer

### 12.1 UI 选择

首选 Flutter overlay 输入框：

- 不向卡片页面暴露 JavaScript channel。
- 输入法、焦点、无障碍和主题更容易控制。
- 用户输入只进入 `COMPARE_TYPED_ANSWER`。

shell 将 typed marker 替换为受控 placeholder；Flutter 根据 placeholder 的测量位置放置输入框。
如果位置同步在真实设备不可接受，可改为 WebView 内固定 input，但仍由原生主动读取，不提供页面
到 native 的通用 callback。

### 12.2 正反面行为

- 问题面：marker 替换为输入框/placeholder。
- 用户翻面：冻结 provided answer。
- Rust 调用官方 compare，返回 comparison HTML。
- 答案面：marker 替换为 comparison HTML。
- `FrontSide` 中的 `<hr id=answer>` 顺序遵循官方 Reviewer 行为。
- Typed Answer 只比较答案，不自动决定 Scheduler grade。

### 12.3 必测语义

- 普通 `{{type:Field}}`。
- `{{type:cloze:Field}}` 和多 Cloze ordinal。
- `{{type:nc:Field}}` combining=false。
- 空字段、未知字段、空 Cloze。
- Unicode combining marks、日语、希伯来语。
- HTML expected、换行、`<br>` 和实体。
- 问题/答案模板中 marker 出现位置不同。

## 13. MathJax 与 LaTeX

### 13.1 MathJax

- MathJax 固定版本随应用离线打包。
- shell 检测当前面是否包含 MathJax，再异步 typeset 当前 qa 容器。
- 翻面/换卡前 clear 上一面 typeset state。
- 不访问 CDN。
- asset manifest 记录版本和 hash。
- 首次加载、缓存加载、离线、深色主题都要有 golden/真机证据。

### 13.2 LaTeX media

`latexSvg` 不代表 Android 需要运行桌面 LaTeX 工具链。若包内已有官方生成的 LaTeX
图片/SVG，按普通媒体提供；若媒体缺失，显示兼容性错误和缺失文件名，不在移动端静默生成错误
公式，也不尝试执行任意 LaTeX 命令。

## 14. Flutter 应用层

候选新增文件：

```text
lib/application/anki_official/render/
  official_anki_render_facade.dart
  official_anki_render_state.dart
  official_anki_media_resolver.dart
  official_anki_av_coordinator.dart
  official_anki_typed_answer_controller.dart

lib/views/anki_official/
  official_anki_reviewer_page.dart
  official_anki_reviewer_view.dart
  official_anki_reviewer_controller.dart
  official_anki_reviewer_error_view.dart
```

### 14.1 状态机

```text
idle
  → loadingCard
  → questionReady
  → showingQuestion
  → comparingTypedAnswer（可选）
  → showingAnswer
  → clearing
  → idle

任意状态 → recoverableError / fatalError / disposed
```

每个异步结果携带 monotonically increasing generation/card token。快速切卡时，旧 render、
MathJax、AV 或 compare 结果不得覆盖新卡状态。

### 14.2 Collection/session 所有权

- Composition root 持有一个 profile 对应的 `OfficialAnkiSession`。
- Import、browse、render 通过同一 worker 串行访问 Collection。
- Reviewer 不自行打开第二个 Collection。
- 页面退出释放 UI/WebView，但 Collection session 是否关闭由 composition 生命周期决定。
- 应用退出/profile 切换必须优雅 close Collection 和 engine handle。

### 14.3 Feature flags

新增独立 flag：

```text
TURNA_OFFICIAL_ANKI_RENDERER
TURNA_OFFICIAL_ANKI_REVIEWER_DIAGNOSTICS
```

建议判定：

```text
allowsOfficialRenderer =
  renderer && engine && catalogReady && runtimeCapable && platformReady
```

默认全部为 `false`。Renderer flag 不隐式打开 import flag；内部测试可对已经导入的 official
source 单独开 renderer。Release 没有 capability 或平台条件时显示不可用，不 fallback。

## 15. Legacy 处理

总体方案中的“P2 删除旧模板渲染与 fallback”需要拆成两个含义：

1. P2 必须删除 official source 到 Legacy renderer 的运行时 fallback。
2. P2 不物理删除 Legacy renderer 源码和 Legacy 数据路径。

物理删除必须等待 Phase 5，因为现有 Legacy source 尚未完成迁移。P2 对 Legacy 的动作只有：

- 冻结，不新增模板语义。
- 添加 source-kind 明确路由。
- 添加测试证明 official source 永远不会进入 Legacy renderer。
- 添加日志证明 Legacy source 仍可只读打开。

## 16. 工作分解

### P2-000：基线、证据与工作树保护

任务：

- 记录完整 HEAD、branch、submodule SHA、`git status --short`。
- 区分 tracked、untracked、submodule dirty 和构建产物。
- 记录当前 Host `.so`、Android `.so`、APK 是否为 stale。
- 建立 `artifacts/phase2/<run-id>/manifest.txt` 或等价外部证据目录。
- 禁止 reset/checkout/删除用户改动。

验收：

- 后续每项结果都能回指 commit、命令、平台和 artifact hash。
- 没有把 Phase 1 旧 APK 作为 P2 证据。

依赖：无。阻塞：全部 P2 任务。

### P2-001：优雅 dispose 与 handle/Collection 释放

任务：

- 修正 `OfficialAnkiSession.dispose()` 顺序。
- worker `dispose` 必须依次关闭 orchestrator/db、Collection、engine、ReceivePort。
- 返回 dispose ack 后才 kill isolate。
- 超时路径记录错误，并用受控 transport close 释放 handle。
- dispose 幂等；并发 dispose 共享同一个 future。
- 修正 spawn 失败时已创建 isolate/ReceivePort/handle 的回收。

测试：

- spawn→open→dispose→reopen 100 次。
- dispose during idle/render/error。
- 双重 dispose。
- dispose timeout 注入。
- 每次结束 Native registry handle 数回到基线。
- Android 反复进入/退出 reviewer 无 `COLLECTION_LOCKED`。

### P2-002：移除生产 in-process 自动回退

任务：

- composition 默认 worker 失败即 fail closed。
- `OfficialAnkiInProcessHost` 仅 test/internal explicit option 可用。
- diagnostics 明确标记 execution mode。
- production flag 下检测到 in-process mode 立即拒绝 renderer/import。

测试：

- worker spawn failure 不创建 in-process host。
- internal explicit option 仍能用于测试。
- UI isolate heartbeat 在 100 次 render 中持续响应。

### P2-003：关闭与 P2 相关的 Phase 1 外部条件

任务：

- 新 debug APK：official import→reopen→render。
- 新 release APK：加载 `.so`、open/check、internal smoke（不得打开用户入口）。
- 真实 Native 5k import cancel 后恢复/open/check。
- clean CI 跑 official native/Dart gates。
- 第二台不同 Android API/WebView 设备 smoke。
- 记录 APK/`.so` 体积，交产品保留 C2 结论位置。

说明：该任务可以与 P2-010～P2-021 开发并行，但在 P2-053 前必须关闭。

### P2-004：调整总体方案的删除与 Scheduler 边界

任务：

- 把 P2 的“删除旧 renderer”改成“移除 official fallback；源码 Phase 5 删除”。
- 明确 P2 reviewer 不写 grade/schedule。
- README 索引加入本计划。

### P2-010：正式化 Native render contract

任务：

- 更新 `engine.rs`、`ops.rs`、`contract.rs`、`operations.md`。
- capability 加入 `RENDER_CARD`、`COMPARE_TYPED_ANSWER`、
  `EXTRACT_CLOZE_FOR_TYPING`。
- contract minor 升到 1.1。
- 统一 camelCase DTO 和稳定 error mapping。
- 区分 raw/display HTML。
- 请求大小、响应大小和异常 HTML 设上限并测试。

验收：

- operation name/id 一致性测试。
- capability/operations.md/Dart 常量一致性测试。
- 9 fixture Native render golden。
- malformed、missing card、empty card、panic mapping。

### P2-011：Dart Engine、FFI 和 worker render API

任务：

- 增加 `OfficialAnkiRenderedCard`、AV、Typed DTO。
- `OfficialAnkiEngine` 增加 render/compare/extract 方法。
- Fake、FFI、Session worker 全部实现相同接口。
- capability gate 在 facade 入口执行。
- 所有 UI 调用只经过 `OfficialAnkiRenderFacade`。

测试：

- DTO decode 未知字段向后兼容。
- old native 缺 capability 时 fail closed。
- Host Dart 真实 FFI 跑 9 fixture。
- 大 HTML/Unicode/AV/TTS typed 响应跨 isolate 不损坏。

### P2-020：Reviewer shell 与 PlatformView 骨架

任务：

- 注册专用 Android PlatformView。
- 固定 shell 只加载一次。
- 建立最小 MethodChannel 控制协议。
- WebView destroy、Flutter rebuild、orientation/theme 切换安全。
- 实现 ready/error/height 事件。

验收：

- 100 张卡复用同一 WebView，无每面 reload。
- question/answer 在同一 qa 容器切换。
- 页面销毁后无 callback setState、WebView 泄漏。

### P2-021：安全 media origin

任务：

- 实现 `anki.local/assets` 和 `anki.local/media` 拦截器。
- root canonicalization、decode-once、symlink gate。
- MIME、Content-Length、Cache-Control、Range。
- external request 返回受控拒绝响应。
- Flutter AV resolver 复用同一套路径规则/测试向量。

验收：

- Unicode/media fixture 全部显示/播放。
- 穿越、双编码、symlink、绝对路径全部拒绝。
- 无 `file://`/`content://` 请求。

### P2-022：同 WebView 正反面与自定义脚本

任务：

- shell 接收 q/a/css/theme 并保留同一 document。
- 正面、背面各执行一次兼容的 DOM/script 更新。
- 快速重复翻面幂等。
- 切卡清理旧 DOM、timer、event handler 和 MathJax state。
- Card ID/generation guard 防止旧结果覆盖。

验收：

- Basic、Reverse、Cloze、FrontSide、自定义 JS fixture。
- 翻面不会再调用 `loadHtmlString()`。
- 前卡脚本不能改变下一张卡初始状态。

### P2-023：WebView policy hardening

任务：

- 显式设置第 10 节全部 WebSettings。
- 实现 navigation/window/download/permission/auth/client-cert 拒绝。
- 固定 CSP。
- release 关闭 WebView debugging。
- debug policy violation 日志脱敏并限流。

验收：

- P2-051 恶意卡测试全部拒绝。
- 无 native JavaScript bridge。

### P2-030：AV/TTS coordinator

任务：

- 映射官方 q/a tags。
- question/answer/next/dispose 的 stop/autoplay/replay。
- TTS voice/lang/speed 参数适配。
- missing media/voice 的稳定错误 UI。

验收：

- 不显示 AV directive。
- 不重复播放。
- 离页立即停止。
- sound+TTS 混合 fixture 顺序一致。

### P2-031：Typed Answer

任务：

- Rust 高层 marker/field/cloze 解析。
- `COMPARE_TYPED_ANSWER`。
- Flutter input/controller。
- answer side comparison HTML 注入。
- unknown/empty typed field UI。

验收：第 12.3 节全部语义测试通过。

### P2-032：离线 MathJax

任务：

- 固定资源、manifest、hash。
- shell lazy load/typeset/clear。
- dark mode、连续切卡和错误边界。
- 禁止 CDN。

验收：

- 飞行模式下 MathJax fixture 正确。
- external request log 为零。
- 连续 100 张数学卡 RSS 不持续线性增长。

### P2-040：内部官方卡片预览入口

任务：

- 从 official source/card catalog 选择 Card ID。
- 加入内部 browser/reviewer page。
- 展示 source、Card ID、backend commit、render duration（diagnostics only）。
- 支持 question/answer、AV/TTS、typed；不显示有效评分写入。

验收：真实导入 `blank (1).apkg` 和 9 fixture 可逐卡预览。

### P2-041：生产路由和 feature flag

任务：

- 增加 renderer/diagnostics flags。
- source-kind 路由。
- official error 不 fallback。
- Legacy source 行为保持只读不变。
- release 默认关闭。

验收：

- 全 flag 关闭时行为与当前 release 一致。
- 只开 renderer 但能力不足时 fail closed。
- official source 永不进入 Legacy renderer mock。

### P2-050：Fixture、golden 和 contract 回归

测试层：

- Rust unit/contract/golden。
- Dart DTO/Fake/state-machine。
- Host Dart real FFI。
- Android instrumented PlatformView。
- 真机 screenshot/interaction。

截图使用结构断言加容差 golden，不能只依赖像素完全一致；字体/WebView 小版本差异必须单独记录。

### P2-051：恶意卡片安全套件

新增 fixture：

- 外部 img/script/font/audio/video。
- fetch/XHR/WebSocket/EventSource。
- iframe/form/popup/download。
- file/content/intent/javascript scheme。
- 目录穿越、双编码和 symlink。
- 相机/麦克风/定位权限。
- 尝试探测 JavaScript channel/native interface。
- 超大 DOM、无限 timer、console flood。

验收不仅看页面错误，还要从拦截器计数、系统日志和文件访问测试证明没有请求逃逸。

### P2-052：性能、内存和生命周期

测量：

- 首张冷 render。
- 后续热 render P50/P95。
- WebView shell 首载。
- question→answer 时间。
- 100 张连续卡 RSS。
- 100 次进入/退出页面后的 WebView/handle 数。
- 10 MB HTML、1000 media ref 的受控失败/性能。
- 前后台 20 次、旋转/主题切换、进程重建。

初始预算（P2-000 后可按设备基线调整）：

| 指标 | 目标 |
|---|---:|
| Host warm `RENDER_CARD` P95 | ≤ 50 ms |
| 中档 Android warm render→question visible P95 | ≤ 250 ms |
| question→answer visible P95（无首次 MathJax） | ≤ 120 ms |
| 100 张后 RSS 增量 | ≤ 80 MB 且无持续线性增长 |
| 100 次页面退出后 Native handle 增量 | 0 |
| 外部网络成功请求 | 0 |

预算若调整，必须记录设备、WebView version、样本和原因，不能静默放宽。

### P2-053：Android debug/release 与设备矩阵

至少：

| 平台 | 要求 |
|---|---|
| Host Linux | Rust + Dart real FFI 全套 |
| Android debug 设备 A | 当前主设备，完整 fixture/安全/生命周期 |
| Android debug 设备 B | 不同 API 或 WebView major，smoke + media + MathJax |
| Android release | `.so`、shell assets、render smoke、debugging disabled |

记录：APK SHA-256、大小、`.so` SHA-256、backend commit、WebView version、Android API、设备型号。

### P2-060：文档与决策

输出 `08-phase-2-result-report.md`，必须分栏记录 Fake/Host/Android debug/Android release。

允许结论：

```text
P2 TECHNICAL GO
P2 TECHNICAL CONDITIONAL GO
P2 NO-GO
```

未测项写“未测”，不写“通过”。如果 Renderer 仍默认关闭但技术门禁通过，可以是 Technical Go；
外部发布条件不在本计划中冒充技术失败或技术完成。

## 17. 依赖关系

```text
P2-000
  ├── P2-001 ── P2-002 ───────────────┐
  ├── P2-003 ───────────────────────┐  │
  └── P2-004                       │  │
                                    │  │
P2-010 ── P2-011 ── P2-040 ── P2-041│  │
   │                                  │  │
   ├── P2-031                         │  │
   └── P2-030                         │  │
                                      │  │
P2-020 ── P2-021 ── P2-023            │  │
   ├── P2-022                          │  │
   └── P2-032                          │  │
                                      │  │
全部功能 ── P2-050 ── P2-051 ── P2-052 ── P2-053
                                                  │
                                                  └── P2-060
```

最多允许并行：

- Native contract（P2-010/011）。
- Android PlatformView/media Spike（P2-020/021）。
- P1 外部门禁（P2-003）。

合流前必须先关闭 P2-001/002，防止测试在泄漏或错误线程路径上给出假阳性。

## 18. 测试矩阵

| 能力 | Rust | Dart Fake | Host FFI | Android instrumented | 真机 |
|---|---:|---:|---:|---:|---:|
| Contract/capability | 必须 | 必须 | 必须 | smoke | smoke |
| Unicode render | 必须 | DTO | 必须 | 必须 | 必须 |
| Reverse | 必须 | state | 必须 | 必须 | 必须 |
| Cloze/multi-ord | 必须 | state | 必须 | 必须 | 必须 |
| FrontSide/CSS | 必须 | DTO | 必须 | 必须 | 必须 |
| Media Unicode/Range | path unit | resolver | manifest | 必须 | 必须 |
| AV/TTS | tag golden | coordinator | 必须 | event | 必须 |
| Typed Answer | 必须 | controller | 必须 | 必须 | 必须 |
| MathJax | n/a | state | asset hash | 必须 | 必须 |
| 恶意卡 | path unit | policy | n/a | 必须 | 必须 |
| Dispose/handle | 必须 | 必须 | 必须 | 必须 | 必须 |
| 性能/RSS | benchmark | n/a | 必须 | 必须 | 必须 |

## 19. 退出门禁

### 19.1 Contract/Native

- [ ] `RENDER_CARD` 正式出现在 operations、capabilities、Rust、Dart。
- [ ] contract 1.1 向后兼容测试通过。
- [ ] 9 fixture official golden 通过。
- [ ] Typed Answer 使用官方 compare/cloze 服务。
- [ ] UI 只显示 AV extraction 后的 display HTML。

### 19.2 生命周期

- [ ] dispose 可到达 worker 并释放 engine handle。
- [ ] production 无 in-process 自动回退。
- [ ] 100 次 reopen 无锁/handle 泄漏。
- [ ] render 不阻塞 UI isolate heartbeat。

### 19.3 Reviewer/WebView

- [ ] 同一张卡正反面使用同一 WebView 和 document。
- [ ] 原卡不存在 Flutter/WebView 启发式选择。
- [ ] 不使用 `file://`/`content://`。
- [ ] 无通用 native JavaScript bridge。
- [ ] release WebView debugging 关闭。

### 19.4 媒体与交互

- [ ] Unicode 媒体、Range、MIME 通过。
- [ ] AV/TTS 不显示、不重复播放，切卡停止。
- [ ] Typed Answer 普通/Cloze/nc/Unicode 通过。
- [ ] MathJax 离线通过。

### 19.5 安全

- [ ] 外部网络成功请求为 0。
- [ ] 路径穿越/双编码/symlink 全拒绝。
- [ ] navigation/popup/download/permission 全拒绝。
- [ ] 恶意卡无法调用 Dart/Kotlin/Rust。

### 19.6 Android/CI

- [ ] 新 debug APK 完整通过。
- [ ] 新 release APK smoke 通过。
- [ ] 第二设备通过规定矩阵。
- [ ] clean CI 一次完整成功。
- [ ] APK/`.so`/assets hash 和体积已记录。

### 19.7 路由与数据

- [ ] official source 失败不 fallback Legacy。
- [ ] Legacy source 仍只读可用。
- [ ] P2 不写 Turna SRS 或官方 Scheduler。
- [ ] 所有 production flags 默认 false。

任何硬门禁未通过时不得写 `P2 TECHNICAL GO`。

## 20. 回滚方案

P2 全部通过 feature flag 接入，回滚顺序：

1. 关闭 `TURNA_OFFICIAL_ANKI_RENDERER`。
2. 保持 official import/source/catalog 数据不删除。
3. official source 显示“renderer unavailable”，不自动改写为 Legacy source。
4. Legacy source 仍走原只读 renderer。
5. 回滚 Dart/UI commit 不回滚 Collection schema 或导入数据。
6. 如 native contract 1.1 有问题，恢复旧 native 时 capability gate 会拒绝新 operation。

禁止通过删除 Collection、catalog、media 或用户 Legacy 数据实现回滚。

## 21. 建议 commit 切分

```text
docs(anki): baseline Phase 2 renderer work
fix(anki): gracefully dispose official worker sessions
fix(anki): fail closed when official worker startup fails
feat(anki): publish official render contract v1.1
feat(anki): expose render and typed answer through worker isolate
feat(android): add isolated official anki reviewer platform view
feat(android): serve official anki media from a guarded local origin
feat(anki): reuse one reviewer document across card sides
feat(anki): play official av and tts tags
feat(anki): compare typed answers with official core
feat(anki): bundle offline reviewer math assets
feat(anki): add internal official card preview routing
test(anki): add reviewer fidelity and hostile-card gates
test(android): measure reviewer lifecycle and resource isolation
docs(anki): record Phase 2 technical result
```

每个 commit 只暂存明确文件。禁止 `git add .`，禁止把工作树中无关文件或 submodule 改动混入。

## 22. 工期估算

| 工作块 | 工程日 |
|---|---:|
| P1 遗留修补与外部门禁 | 3～6 |
| Native/Dart render contract | 4～6 |
| Android PlatformView + media origin | 7～10 |
| 正反面 shell + security hardening | 4～7 |
| AV/TTS + Typed Answer | 4～7 |
| MathJax | 2～4 |
| fixture/security/performance/device | 6～10 |
| 文档与收口 | 1～2 |
| 合计 | **31～52 工程日** |

存在并行开发时，单平台日历时间预计约 4～6 周；单人串行更接近 6～10 周。估算不包含
License/法律等待、Phase 3 课程投影或 Phase 4 Scheduler。

最大不确定性不是官方渲染，而是：

1. Android WebView 子资源拦截和 Range/media 兼容。
2. 自定义卡片脚本与严格安全策略的冲突。
3. Typed Answer 在 Flutter overlay 与 WebView 布局间的定位。
4. 不同系统 WebView/字体版本下的 MathJax 和截图差异。

## 23. 开工顺序

第一批必须先完成：

1. **P2-000**：冻结证据基线和工作树边界。
2. **P2-001**：修复 dispose/handle 生命周期。
3. **P2-002**：移除 production in-process fallback。
4. **P2-010**：把现有 `RENDER_CARD` 正式化为 contract 1.1。
5. **P2-020/P2-021 Spike**：证明专用 PlatformView 能在 `anki.local` 下安全提供
   Unicode 图片和 Range 音频。

只有前五项通过，才扩大到 Typed Answer、MathJax、正式页面路由和大规模截图验收。

