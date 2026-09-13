# Phase 2 官方原卡渲染修补计划

> 文档代号：P2FIX  
> 状态：待实施；`P2 FIX CONSTRUCTION GO / P2 TECHNICAL ACCEPTANCE NO-GO`  
> 制定日期：2026-08-17  
> 当前分支：`spike/official-anki-core-android`  
> 审计基线 HEAD：`cc1484b30739bceeba07fe1a3be98b8b0e11018d`  
> 上游 Anki pin：`967aa0d578fc75181e292e95326f9b58698da25c`  
> 首发平台：Android arm64  
> 输入文档：`07-phase-2-implementation-plan.md`、`08-phase-2-result-report.md`  
> 明确排除：License、AGPL 展示、源码要约、法律确认及其签字  
> 生产切流：全部 P2FIX 硬门禁通过前保持关闭

## 1. 目的

Phase 2 已经实现 contract 1.1、官方 Native render/typed-answer、Dart worker API、Android
Reviewer PlatformView、安全策略骨架、media handler、离线资源目录和内部预览入口。但当前
结果报告把一部分“源码存在”“Host 单测通过”“字符串断言通过”记成了“功能完成”。代码审计
和新 debug APK 内容检查确认，真实 Android 用户链路仍存在以下确定性缺口：

1. Reviewer shell 没有媒体 `<base>`，相对图片/字体会错误请求 `/assets/`。
2. 官方渲染结果没有统一执行 IRI path 编码，`#`、`?`、`%` 文件名仍可能失败。
3. MathJax 文件存在于工作树，但没有进入 debug APK。
4. 正式 Reviewer 使用测试用 `RecordingOfficialAnkiAvPlayer`，不会播放真实音频/TTS。
5. Android Range 响应、一次解码和二进制 encoding 实现不正确。
6. 缺少 `card1/card2/...` body class，部分模板 CSS 会失效。
7. 自定义卡片的 timer/listener/global 可以污染下一张卡。
8. PlatformView `present()` 没有等待 JS/MathJax 完成，height event 实际不可达。
9. PlatformView dispose 可能执行两次。
10. Session dispose 超时后的同步 `engineClose()` 可能重新阻塞 UI isolate。
11. Typed Answer 的 Android 输入、错误恢复和 FrontSide 位置没有闭合。
12. Android 安全测试主要是读取源码做字符串匹配，不是运行中的 WebView 测试。

本计划不推翻 P2 架构，而是将已有骨架修补为可以真机验收、可以形成可信结果报告的实现。

## 2. 当前决策

```text
P2 ARCHITECTURE GO
P2 FIX CONSTRUCTION GO
P2 TECHNICAL ACCEPTANCE NO-GO
P2 PRODUCTION NO-GO
```

允许继续修补和构建 debug 包；不允许：

- 把 `TURNA_OFFICIAL_ANKI_RENDERER` 作为 production 默认打开。
- 把 Host/Fake/源码字符串断言写成 Android 通过。
- 进入 Phase 3 后忽略 P2 原卡渲染的确定性缺陷。
- 删除 Legacy renderer 或用户数据。
- 用关闭媒体/JS/MathJax 的方式假装兼容性通过。

## 3. 审计证据

### 3.1 已通过

```text
dart analyze lib/application/anki_official lib/views/anki_official \
  test/application/anki_official
# 源码：No issues found

flutter test --no-pub test/application/anki_official
# 79 passed

flutter build apk --debug
# Built build/app/outputs/flutter-apk/app-debug.apk
```

审计构建的 debug APK：

```text
path: build/app/outputs/flutter-apk/app-debug.apk
bytes: 225637006
sha256: 9f2b4b0ef5afdb3156129131382a091c5b0af627e526bbd3013c30f2a8a80951
```

该 APK 只证明当前 Kotlin/Flutter 骨架可编译，不是设备验收证据，也不是 release 体积证据。

### 3.2 当前 Android native

```text
path: android/app/src/main/jniLibs/arm64-v8a/libturna_anki.so
bytes: 20207384
sha256: 111b0faee969d3766248a81189650b7ef4c10c975635f8766213ef541177a928
```

ELF 为 AArch64，strings 中存在：

```text
RENDER_CARD
COMPARE_TYPED_ANSWER
EXTRACT_CLOZE_FOR_TYPING
```

因此 `08` 中“Android `.so` 仍是 Phase 1 产物”的记录已过时；但当前 `.so` 尚未完成真机
render/typed-answer 验证。

### 3.3 APK 内容缺口

APK 已包含：

```text
assets/anki_reviewer/reviewer.html
assets/anki_reviewer/reviewer.css
assets/anki_reviewer/reviewer.js
assets/anki_reviewer/mathjax-config.js
assets/anki_reviewer/manifest.json
```

APK 未包含：

```text
assets/anki_reviewer/mathjax/tex-svg-full.js
```

所以“离线 MathJax 已完成”不能成立。

## 4. 修补范围

### 4.1 包含

- 修正 `08` 的事实状态和产物记录。
- 修复媒体 base、IRI、decode、Range、MIME 和 canonicalization。
- 把 MathJax 子目录真正打入 APK。
- 接入真实 AudioController/AudioPlayer/TTS。
- 返回并应用官方 card ordinal/body class。
- 隔离卡片脚本的跨卡状态。
- 让 PlatformView render ack、height、dispose 可验证。
- 修复 Session 超时清理线程。
- 完成 Typed Answer Android UI 和错误恢复。
- 添加 Kotlin JVM、Android instrumented、恶意卡、生命周期和真机测试。
- 新 debug/release APK、第二设备、clean CI、性能和结果报告。

### 4.2 排除

- Phase 3 课程投影。
- Phase 4 Scheduler、FSRS、revlog、Again/Hard/Good/Easy。
- Phase 5 Legacy 数据迁移和删除。
- AnkiWeb Sync。
- OHOS/iOS/桌面正式 Reviewer。
- License/法律工作。
- 完整复制 Anki Desktop Qt 或完整 AnkiDroid UI。

### 4.3 红线

- Native 官方 Collection 仍是唯一 Anki 内容事实源。
- Dart 不解析 Mustache、Cloze 或 Reverse 模板。
- official source 不 fallback Legacy renderer。
- WebView 不使用 `file://`/`content://`。
- 卡片脚本不能调用 Dart/Kotlin/Rust。
- P2FIX 不写任何 Scheduler 状态。
- production flags 保持默认 false。
- 不 reset/checkout/delete 当前用户工作树。

## 5. 目标实现

```text
Official Collection
        │
        ▼
RENDER_CARD + encode_iri_paths + typed hint + body class
        │ contract 1.2（或兼容的 1.1 optional field）
        ▼
OfficialAnkiSession worker isolate
        │
        ▼
OfficialAnkiReviewerController
        ├── OfficialAnkiAudioPlayerAdapter → AudioController/TTS
        └── Android PlatformView
                 │
                 ├── fixed outer reviewer shell
                 ├── sandboxed per-card runtime frame
                 ├── https://anki.local/assets/...
                 └── https://anki.local/media/...
                           │ strict single-decode/canonical/range
                           ▼
                    collection.media only
```

外层 WebView 和 shell document 在正反面之间保持不变；每张新 Card 创建新的卡片运行 frame，
隔离上一张卡的全局变量、timer 和 listener。正面/答案在同一个 card frame 中切换。

## 6. 优先级与严重度

| ID | 问题 | 严重度 | 当前影响 |
|---|---|---:|---|
| F-MEDIA-BASE | 无 `<base>` | P0 | 相对图片/字体确定性 404 |
| F-MATH-PACK | MathJax 未进 APK | P0 | 离线公式确定性失败 |
| F-AV-FAKE | 正式页面使用 recorder | P0 | 音频/TTS 确定性无声 |
| F-MEDIA-RANGE | Range/stream 不正确 | P0 | 音视频缓冲/seek 不可靠 |
| F-IRI | 特殊媒体名未统一编码 | P0 | `#/?/%` 文件名失败 |
| F-BODYCLASS | 缺 card ordinal class | P1 | `.card1/.card2` CSS 失效 |
| F-SCRIPT-LIFE | 跨卡脚本残留 | P1 | 后卡被前卡污染/DoS |
| F-PRESENT-ACK | present 不等完成 | P1 | UI 状态与真实 DOM 不一致 |
| F-DISPOSE | double destroy/同步 close | P1 | 崩溃、卡 UI、handle 风险 |
| F-TYPED-UI | 输入/错误/IME 未闭合 | P1 | Typed Answer 仅演示可用 |
| F-SEC-TEST | 无运行时 WebView 测试 | P1 | 安全结论不可验证 |
| F-REPORT | 结果报告过期/高估 | P2 | 施工决策失真 |

P0 全部关闭前不得开始真机验收签字；P1 全部关闭前不得写 Technical Go。

## 7. 工作分解

### P2FIX-000：重新冻结修补基线

任务：

- 记录完整 HEAD、branch、submodule SHA、`git status --short`。
- 记录当前 P2 修改文件清单和 diff hash。
- 记录 Host `.so`、Android `.so`、debug APK、reviewer assets hash。
- 将审计构建与后续修补构建分开命名。
- 不修改或删除既有无关 untracked 文件。

证据文件建议：

```text
docs/official-anki-migration/artifacts/p2fix/
  baseline.txt
  commands.txt
  artifact-manifest.txt
```

验收：任何后续测试结果都能回指 commit、平台、命令和 artifact SHA-256。

依赖：无。阻塞：全部 P2FIX 任务。

### P2FIX-001：修订结果报告的状态边界

任务：

- `08` 暂时改为 `P2 IMPLEMENTATION IN PROGRESS / TECHNICAL ACCEPTANCE NO-GO`。
- P2-021、030、032、051、052、053 按真实状态降级。
- 把当前 Android `.so`/debug APK 记为“可编译，未上设备”。
- 修正 manifest `assetVersion` 的 `p2-1`/`p2-2` 不一致。
- 结果报告不得提前记录本计划尚未执行的修补。

验收：报告中的每个“通过”都有命令或设备证据，而不是源码存在证明。

### P2FIX-010：媒体 base 与官方 IRI 编码

#### 代码修改

`assets/anki_reviewer/reviewer.html` 增加：

```html
<base href="https://anki.local/media/">
```

所有 shell 自身 CSS/JS 继续使用绝对 `/assets/` URL，防止 base 改变 shell asset 解析。

Rust `RENDER_CARD` 在 AV extraction 后，对 question/answer display HTML 使用官方
`encode_iri_paths()`。不得用 Dart/Kotlin 正则重写 HTML attribute。

需要验证：

- `<img src="hello world.png">`
- `<img src="中文图片.jpg">`
- `<img src="hash#tag.png">`
- `<img src="question?.png">`
- `<img src="percent%20literal.png">`
- CSS `url(...)`。
- `<script src="local library.js">`。
- audio/video/source relative URL。

如果官方 `encode_iri_paths()` 不处理 notetype CSS `url()`，在 Rust 增加独立官方 service
调用或安全 CSS URL transformer；不能把整个 CSS 当 HTML 正则替换。

#### Contract

保留 raw `questionHtml/answerHtml` 作为 golden；UI 只接收编码后的
`questionDisplayHtml/answerDisplayHtml`。增加 contract test 证明 raw/display 的区别。

#### 验收

- WebView 实际请求全部落到 `/media/`。
- fixture 图片在飞行模式可见。
- 特殊文件名不会被 fragment/query 截断。
- 没有 `file://`。

依赖：P2FIX-000。

### P2FIX-011：重写 Android media request 解析

#### 单次解码

从 `request.url.encodedPath` 开始：

1. 验证 scheme/host/port。
2. 验证 encoded path 只属于 `/assets/` 或 `/media/`。
3. 对 media filename 严格 percent decode 一次。
4. 拒绝 malformed percent encoding、NUL、separator、绝对路径和路径段 `..`。
5. 二次编码内容保持字面文件名或拒绝，不能再 decode。

不要使用 `uri.path` 后再 `Uri.decode()`。

#### 文件名规则

- 只允许 Collection media 根目录下的单个 Anki media filename。
- 不用 `rawName.contains("..")` 拒绝合法 `foo..bar.png`；按 path segment 判定。
- canonical root 和 candidate。
- 允许 root 内普通文件；拒绝目录和逃逸 symlink。
- Dart resolver 与 Kotlin 使用同一 JSON 测试向量，而不是分别手写近似测试。

#### 二进制响应

- 图片、音视频、字体 response encoding 使用 `null`。
- 文本资源才使用 UTF-8。
- MIME 表覆盖 png/jpeg/gif/webp/svg/mp3/ogg/wav/m4a/mp4/webm/css/js/html/woff/woff2/ttf/otf。
- 未知类型使用 `application/octet-stream` 和 `X-Content-Type-Options: nosniff`。
- 添加 `Access-Control-Allow-Origin`，只用于 sandbox card frame 加载受控媒体/字体。

验收：Dart/Kotlin 对同一 40+ 路径向量给出一致 allow/deny 结果。

### P2FIX-012：正确实现单 Range 响应

支持：

```text
bytes=0-99
bytes=100-
bytes=-500
```

规则：

- end clamp 到 `length - 1`。
- suffix range 取最后 N bytes。
- 空文件、越界、反向区间返回 416 和 `Content-Range: bytes */length`。
- 多 range 暂不支持，明确返回 416，不静默错误解析。
- 使用 bounded InputStream，只暴露 `[start, end]`，不能把剩余整文件继续返回。
- `Content-Length` 与真实可读 bytes 完全一致。
- `Accept-Ranges: bytes`。
- HEAD 如 WebView 请求到，返回 headers 不返回 body。

候选实现：新增 `LimitedInputStream` 或包装 `FileInputStream`，并测试 partial read、skip 不完整和
close 行为。

验收：Kotlin unit test 对 0/1/1000 bytes 文件覆盖所有边界；真机 audio/video seek 无错误。

### P2FIX-013：把 MathJax 真正打入 APK

修改 `pubspec.yaml`：

```yaml
flutter:
  assets:
    - assets/anki_reviewer/
    - assets/anki_reviewer/mathjax/
```

任务：

- 保留 manifest SHA-256 校验。
- 新增 APK 内容 gate，不能只检查工作树文件。
- `OfficialAnkiReviewerPlugin.loadReviewerAsset()` 对 MathJax 缺失返回稳定 render error。
- JS 不吞掉 MathJax load error；上报 `MATHJAX_ASSET_MISSING`。
- 飞行模式 typeset。
- 数学卡切换时 `typesetClear()`。

APK gate：

```text
unzip -l <apk> 必须包含
assets/flutter_assets/assets/anki_reviewer/mathjax/tex-svg-full.js
```

验收：飞行模式真机显示 inline/display MathJax，外部网络请求为 0。

### P2FIX-014：接入真实 AV/TTS player

新增：

```text
lib/application/anki_official/render/
  official_anki_av_player_adapter.dart
```

生产页面禁止再创建 `RecordingOfficialAnkiAvPlayer`。Recorder 仅留在 test 目录或明确 test-only
class。

建议接口实现：

- `playFile(path)`：使用专用 `AudioPlayer` 播放已由 `OfficialAnkiMediaResolver` 验证的本地文件。
- `speak()`：调用 `AudioController.speakWithResult(text, languageCode, speed)`。
- `stop()`：同时 stop 专用 AudioPlayer 和 `AudioController.stopSystemTts()`。
- `dispose()`：释放专用 AudioPlayer，不 dispose 全局 AudioController。

`voices` 和 `otherArgs`：

- 当前平台能够选择 voice 时按官方 voice 顺序尝试。
- 当前 AudioController 不支持时记录 capability-limited，不伪装已使用指定 voice。
- 不把 unsupported args 拼进朗读文本。

修正 coordinator：

- question→answer 先 stop question。
- answer→question 先 stop answer，即使 `autoplay=false`。
- next/dispose 必须 stop。
- 多 tag 明确串行或按官方播放队列完成事件推进，不能让多个 `play()` 重叠。
- generation 变化后旧播放 completion 不启动下一 tag。

验收：

- 设备可听到 question sound、answer TTS。
- 翻面/切卡/离页立即停止。
- replay 只播放当前 side。
- missing file/voice 显示受控错误。

### P2FIX-015：补齐 body class 和模板 ordinal

Native `RENDER_CARD` 增加：

```json
{
  "templateOrdinal": 0,
  "bodyClass": "card card1"
}
```

夜间 class 仍由 UI 添加；Native 不返回 Desktop 平台专用 `isWin/isMac/isLin`。

Reviewer setCard 必须原子设置：

```text
card
card{ordinal + 1}
nightMode/night_mode（按主题）
```

切卡前删除旧 `cardN`，避免 card1/card2 同时存在。

验收 fixture：

- `.card {}`。
- `.card1 {}`。
- `.card2 {}`。
- Reverse 的第二模板样式。
- dark mode class。

Contract minor：如果 `bodyClass/templateOrdinal` 是 optional additive field，可保留 1.1；如果修改
既有字段语义则升 1.2。必须更新 Rust/Dart/fixture/capability compatibility test。

### P2FIX-020：卡片脚本运行域隔离

当前直接把卡片 HTML 注入 outer shell，无法可靠清理 window timer/listener/global。修补采用：

```text
outer reviewer.html（长期存在，持有 native control）
    └── iframe src=https://anki.local/assets/card-frame.html
          sandbox="allow-scripts"
          不含 allow-same-origin/forms/popups/downloads/top-navigation
```

新增固定 assets：

```text
assets/anki_reviewer/card-frame.html
assets/anki_reviewer/card-frame.js
```

行为：

- 每张新 Card 创建一个全新的 sandbox frame。
- question/answer 在同一个 frame 中更新。
- 下一 Card 销毁旧 frame，自动回收其 globals/timers/listeners。
- outer shell 通过 `postMessage` 发送固定 schema。
- frame 只接受父 window、正确 generation 和随机 session nonce。
- frame 没有 native bridge。
- frame `<base href="https://anki.local/media/">`。
- MathJax 在 frame 内运行和清理。

outer CSP 调整为仅允许固定 `anki.local` card frame；仍禁止外部 frame。

兼容性门禁：

- 普通 inline JS。
- 本地 external JS media。
- DOM event handler。
- question→answer 共享同一卡状态。
- next card 不共享状态。
- 脚本访问 `window.top` 失败不能获得 shell/native 能力。

若 iframe 方案在目标 WebView 上导致官方基础 fixture 不兼容，本任务必须形成书面 No-Go/替代
设计；不得退回“同 document 但不清理”并宣称完成。

### P2FIX-021：让 present/render completion 可观测

定义 PlatformView 协议：

```text
setCard → cardAccepted
showQuestion → renderComplete{cardId,generation,side,height,durationMs}
showAnswer → renderComplete{...}
renderError{stableCode,cardId,generation,side}
```

Kotlin `evaluateJavascript` 必须等待 JS Promise 完成。可由 JS 将 completion 写入一个受控轮询
状态，或由 Kotlin evaluate 一个 async wrapper/Promise bridge；不能在调用 `present()` 后立即
`result.success()`。

注意：禁止为 completion 增加卡片可调用的 JavaScriptInterface。通信只允许 Flutter→Kotlin
主动 evaluate 和 Kotlin MethodChannel→Flutter。

任务：

- height 取真正的 frame/document scrollHeight。
- generation 不匹配的 completion 丢弃。
- MathJax 完成后才发最终 height。
- 2 秒无完成进入 recoverable render timeout。
- timeout 后可重建 card frame，不重建 Collection。

验收：快速切 50 张卡，没有旧 height/renderComplete 覆盖当前卡。

### P2FIX-022：PlatformView 生命周期与 WebChrome 策略

任务：

- Kotlin `dispose()` 增加幂等 guard；第二次调用直接返回。
- Dart 不依赖 fire-and-forget dispose 作为唯一回收；PlatformView framework dispose 是最终所有者。
- `onJsConfirm`、`onJsPrompt` 全部取消。
- file chooser 返回拒绝。
- geolocation prompt 明确 deny。
- popup/download 全拒绝并计数。
- WebView debugging 仅 `kDebugMode && reviewerDiagnostics` 开启；不能 debug build 自动开启。
- 清除 Reviewer 专用 WebStorage/cookies/service-worker state。
- 评估并设置全局 `ServiceWorkerController` 拦截/拒绝，避免绕过 WebViewClient。

验收：100 次创建/销毁无 crash、WebView 实例数回到基线、release debugging=false。

### P2FIX-023：Session 超时清理不阻塞 UI

当前 `_rpc('dispose')` 超时后同步调用 control `engineClose(handle)`。修补为：

1. 发 native cancel。
2. 标记 session rejecting new calls。
3. 在专用 cleanup isolate 调用 `engineClose()`。
4. UI isolate 只等待有上限的清理状态，不执行同步 FFI lock wait。
5. 超时后记录 orphan-cleanup 状态；进程退出前再次回收。

需要区分：

- graceful dispose。
- render timeout dispose。
- import busy dispose。
- worker crash dispose。
- engine handle 已被释放。

测试：

- Fake 100 reopen。
- Host real FFI 100 alloc/open/render/dispose。
- 模拟持锁 10 秒时 UI heartbeat 继续。
- double dispose 共用 future。
- cleanup isolate 不重复 free handle。

### P2FIX-024：Typed Answer Android 闭环

任务：

- 输入框位置和 frame placeholder 建立稳定方案。
- 首选 Flutter overlay；如果 frame 跨域导致坐标/滚动不可维护，则在 sandbox frame 内创建固定
  input，但只能由 Flutter 主动读取/写入，不能新增通用 native bridge。
- unknown field、empty field、empty cloze 显示官方兼容提示，不让整页永久停在 loading/comparing。
- `_flip()` 捕获 compare exception，进入 recoverableError 并允许重试/跳过。
- FrontSide 的 `<hr id=answer>` 和 comparison HTML 顺序对齐官方 Reviewer。
- 冻结 provided answer 后禁用输入。
- 返回 question 时定义是否恢复输入，行为写测试。

设备测试：

- 中文/希伯来语/组合字符。
- 软键盘 show/hide。
- 横竖屏。
- 长卡滚动。
- 普通/cloze/nc。
- 空字段和未知字段。

### P2FIX-030：Kotlin JVM 测试

新增：

```text
android/app/src/test/kotlin/me/dsdogs/turna/anki/reviewer/
  OfficialAnkiMediaHandlerTest.kt
  OfficialAnkiWebPolicyTest.kt
  RangeParserTest.kt
```

避免现有“Dart 读取 Kotlin 源码字符串”作为核心证明。源码结构断言可以保留为辅助 gate，但不
计入 Android 功能通过。

测试至少覆盖：

- 40+ 共享 path vectors。
- decode once。
- special Unicode filename。
- traversal/double encoding/symlink。
- MIME/encoding。
- Range 全边界。
- external scheme/host/port。
- asset allowlist。

### P2FIX-031：Android instrumented Reviewer 测试

新增 `android/app/src/androidTest/`：

- 创建真实 WebView/PlatformView。
- 加载 shell 并等待 ready。
- 注入 question/answer。
- 断言同一 WebView/outer document。
- 断言 per-card frame 在换卡时更换。
- 读取 DOM 结构和 body class。
- 加载 Unicode image、font、audio Range、MathJax。
- 统计所有 shouldInterceptRequest allow/deny。
- 验证 external network 成功数为 0。
- 验证 file/content/intent/popup/download/permission 被拒绝。

Gradle 只增加完成测试所需的最小 AndroidX test 依赖；不要引入完整浏览器框架。

### P2FIX-032：恶意卡 fixture

新增可重复生成的恶意卡集合：

```text
fetch/XHR/WebSocket/EventSource
external img/script/font/audio/video
file/content/intent/javascript URLs
iframe/form/popup/download
camera/microphone/geolocation/file chooser
path traversal/double encoding/symlink
window.top/parent access
overwrite OfficialReviewer
setInterval/infinite timer/console flood
large DOM/mutation observer
service worker registration
```

验收必须同时检查：

- 页面结果。
- interceptor allow/deny counters。
- Android log。
- native bridge 调用计数恒为 0。
- 外部网络成功请求恒为 0。
- 下一张正常卡不受污染。

### P2FIX-033：真实性能与生命周期

设备记录：

| 指标 | 门禁 |
|---|---:|
| warm Native render P95 | ≤ 50 ms Host；设备单独记录 |
| render→question visible P95 | ≤ 250 ms 中档 Android |
| question→answer visible P95（无首次 MathJax） | ≤ 120 ms |
| 100 张后 RSS 增量 | ≤ 80 MB 且无持续线性增长 |
| 100 次进出后 Native handle 增量 | 0 |
| 100 次进出后 WebView 实例增量 | 0 |
| 外部网络成功请求 | 0 |

同时测：

- 首次 MathJax。
- 后续 MathJax。
- 10 MB HTML 的受控失败。
- 1000 media ref。
- 前后台 20 次。
- 主题/旋转/进程重建。
- 恶意无限 timer 后恢复下一卡。

### P2FIX-040：真实 Android 构建和设备闭环

#### 重新构建 native

- 从当前 pin/contract 构建 Android arm64 `.so`。
- verify pin。
- 记录 `.so` SHA-256、size、symbols、contract capabilities。
- 禁止使用未记录来源的 jniLibs。

#### Debug APK

用完整内部 flags 构建：

```text
TURNA_OFFICIAL_ANKI_ENGINE=true
TURNA_OFFICIAL_ANKI_IMPORT=true
TURNA_OFFICIAL_ANKI_CATALOG=true
TURNA_OFFICIAL_ANKI_RUNTIME=true
TURNA_OFFICIAL_ANKI_PLATFORM=true
TURNA_OFFICIAL_ANKI_RENDERER=true
TURNA_OFFICIAL_ANKI_REVIEWER_DIAGNOSTICS=true
```

验证：

```text
import → reopen → list source → first/next card → question → answer
→ media → AV/TTS → typed answer → MathJax → exit → reopen
```

#### Release APK

- renderer 默认关闭的 release build 编译通过。
- 内部验收 release 可通过受控 defines 开启，但不得对外分发。
- R8 后 FFI symbols、PlatformView、reviewer assets、MathJax 均存在。
- WebView debugging=false。

### P2FIX-041：设备矩阵

至少：

| 设备 | 要求 |
|---|---|
| 设备 A | 当前主设备，完整功能/安全/生命周期 |
| 设备 B | 不同 Android API 或 WebView major，核心 fixture + MathJax + media |
| release build | 设备 A smoke，确认 R8/assets/native |

每次记录：

- 设备型号。
- Android API。
- Android System WebView version。
- APK SHA-256。
- `.so` SHA-256。
- backend commit。
- flags。
- 测试卡组 hash。

### P2FIX-042：Phase 1 遗留门禁

在 P2 技术签字前同时关闭：

- 真实 Native 5k import cancel→recover→open/check。
- clean CI runner 完整成功。
- 第二设备。
- debug/release APK。
- native 体积产品技术记录位置。

License 仍不在本计划内，不得把其未完成写成技术测试失败，也不得写成发布已获批准。

### P2FIX-050：修订 P2 结果报告

更新 `08-phase-2-result-report.md`：

- 分栏：Rust/Fake/Host FFI/Android JVM/Android instrumented/真机 debug/真机 release。
- 每个 P2/P2FIX ID 写 actual commit、命令、结果、artifact。
- 报告 APK 是否包含 MathJax。
- 报告 media allow/deny counters。
- 报告 AV/TTS 真机听测和自动化事件。
- 报告 Typed Answer IME。
- 报告 RSS、handle、WebView count。
- 未测项明确写未测。

允许的最终结论：

```text
P2 TECHNICAL GO
P2 TECHNICAL CONDITIONAL GO
P2 NO-GO
```

存在任一 P0/P1 功能或安全缺口时不得写 Technical Go。

## 8. 共享路径测试向量

建立：

```text
test/fixtures/anki_official/media_path_vectors.json
```

示例：

```json
[
  {"name":"hello world.png","allowed":true},
  {"name":"中文图片.jpg","allowed":true},
  {"name":"hash#tag.bin","allowed":true},
  {"name":"percent%20.txt","allowed":true},
  {"name":"foo..bar.png","allowed":true},
  {"name":"../secret","allowed":false},
  {"name":"%2e%2e%2fsecret","allowed":false},
  {"name":"%252e%252e%252fsecret","allowed":false},
  {"name":"/etc/passwd","allowed":false},
  {"name":"C:/secret","allowed":false},
  {"name":"a/b.png","allowed":false},
  {"name":"a\\b.png","allowed":false},
  {"name":"nul\u0000x","allowed":false}
]
```

Dart、Kotlin JVM、Android instrumented 必须读取同一份 vectors，避免规则漂移。

## 9. 测试矩阵

| 能力 | Rust | Dart | Kotlin JVM | Android instrumented | 真机 |
|---|---:|---:|---:|---:|---:|
| Contract/bodyClass/IRI | 必须 | DTO | n/a | DOM | 必须 |
| Media base/path | service | resolver | 必须 | 必须 | 必须 |
| Range/MIME | n/a | vector | 必须 | 必须 | 必须 |
| MathJax package | n/a | manifest/APK | asset load | 必须 | 飞行模式 |
| AV/TTS | tags | coordinator/adapter | n/a | event | 听测+日志 |
| Typed Answer | official | controller | n/a | IME/DOM | 必须 |
| Script isolation | n/a | state | n/a | 必须 | 必须 |
| Web security | n/a | vector | policy | 必须 | 必须 |
| Session dispose | handle | isolate | n/a | lifecycle | 必须 |
| 性能/RSS | benchmark | timing | n/a | 必须 | 必须 |

## 10. 依赖关系

```text
P2FIX-000 ── P2FIX-001
    │
    ├── P2FIX-010 ── P2FIX-011 ── P2FIX-012 ── P2FIX-030
    │                                      └── P2FIX-031
    ├── P2FIX-013 ───────────────────────────────┘
    ├── P2FIX-014 ───────────────────────────────┤
    ├── P2FIX-015 ── P2FIX-020 ── P2FIX-021 ────┤
    ├── P2FIX-022 ───────────────────────────────┤
    ├── P2FIX-023 ───────────────────────────────┤
    └── P2FIX-024 ───────────────────────────────┘
                                                   │
                             P2FIX-032 ── P2FIX-033
                                                   │
                             P2FIX-040 ── P2FIX-041
                                           │
                             P2FIX-042 ─────┤
                                           │
                                      P2FIX-050
```

允许并行：

- Native IRI/bodyClass。
- Kotlin media/Range。
- AV adapter。
- shell/frame isolation。
- Session cleanup。

禁止在 P0 修补未合流时开始结果签字。

## 11. 开工批次

### 批次 A：确定性功能阻断，2～4 工程日

- P2FIX-000。
- P2FIX-001。
- P2FIX-010。
- P2FIX-011。
- P2FIX-012。
- P2FIX-013。
- P2FIX-014。
- P2FIX-015。

完成标准：相对媒体、MathJax、真实声音和 cardN CSS 在 debug 设备上首次可见/可听。

### 批次 B：生命周期和隔离，3～6 工程日

- P2FIX-020。
- P2FIX-021。
- P2FIX-022。
- P2FIX-023。
- P2FIX-024。

完成标准：连续切卡、Typed Answer、dispose 和恶意脚本不污染下一卡。

### 批次 C：测试和设备门禁，3～5 工程日

- P2FIX-030～033。
- P2FIX-040～042。
- P2FIX-050。

完成标准：Android instrumented、两设备、release、CI 和结果报告闭合。

总计：**8～15 工程日**。如果 sandbox frame 与目标卡组存在兼容性冲突，增加 3～7 工程日。

## 12. 退出门禁

### 12.1 功能

- [ ] 相对图片/字体/脚本全部请求 `/media/`。
- [ ] `#/?/%/Unicode/组合字符` 文件名通过。
- [ ] Range 规范测试通过。
- [ ] MathJax 文件存在于 debug/release APK。
- [ ] 飞行模式 MathJax 显示。
- [ ] production Reviewer 使用真实 AV player。
- [ ] question/answer AV 可听，切面/切卡停止。
- [ ] `card1/card2` CSS 生效。
- [ ] Typed Answer 普通/cloze/nc/IME 通过。

### 12.2 生命周期

- [ ] question/answer 使用同一 outer WebView 和 card frame。
- [ ] 下一卡使用新 sandbox frame。
- [ ] 前卡 timer/listener/global 不影响后卡。
- [ ] render completion/height 真实可达。
- [ ] PlatformView double dispose 安全。
- [ ] Session cleanup 不阻塞 UI heartbeat。
- [ ] 100 次进出 handle/WebView 增量为 0。

### 12.3 安全

- [ ] file/content/intent/javascript 被拒绝。
- [ ] 外部 HTTP/HTTPS/WebSocket 成功请求为 0。
- [ ] popup/download/form/file chooser/permission 被拒绝。
- [ ] card script 无法访问 outer shell/native bridge。
- [ ] Service Worker 不能绕过 interceptor。
- [ ] traversal/double encoding/symlink 全拒绝。
- [ ] 恶意卡之后正常卡可恢复。

### 12.4 构建与证据

- [ ] Rust/Dart/Kotlin JVM 全绿。
- [ ] Android instrumented 全绿。
- [ ] 新 arm64 `.so` hash/size/contract 已记录。
- [ ] 新 debug APK hash/内容/设备证据已记录。
- [ ] 新 release APK hash/内容/设备证据已记录。
- [ ] 第二设备通过。
- [ ] clean CI 通过。
- [ ] 08 结果报告与实际 manifest/产物一致。

任何硬门禁未通过时：

```text
TURNA_OFFICIAL_ANKI_RENDERER remains false
```

## 13. 回滚

1. 关闭 renderer flag。
2. 保留 official Collection、catalog、media 和 import 结果。
3. official source 显示 renderer unavailable，不转换成 Legacy。
4. Legacy source 继续只读旧 renderer。
5. 回滚 Reviewer assets/UI 不回滚 Collection 数据。
6. Contract optional field 由旧 Dart 忽略；缺 capability 时新 Dart fail closed。
7. 不通过删除用户数据解决渲染失败。

## 14. 建议 commit 切分

```text
docs(anki): baseline Phase 2 renderer remediation
fix(anki): rebase official card media onto guarded origin
fix(anki): encode official media IRI paths before display
fix(android): decode reviewer media paths exactly once
fix(android): serve bounded HTTP range responses for anki media
fix(anki): package offline mathjax in Android artifacts
feat(anki): play official av and tts with production audio adapters
fix(anki): apply official card ordinal body classes
fix(android): isolate card scripts in a per-card sandbox frame
fix(android): acknowledge reviewer render completion and height
fix(android): make reviewer platform view disposal idempotent
fix(anki): clean native sessions without blocking the UI isolate
fix(anki): complete typed-answer error and IME behavior
test(android): exercise reviewer media and security policy
test(android): gate hostile cards and reviewer lifecycle
build(anki): produce verified Phase 2 debug and release artifacts
docs(anki): correct Phase 2 technical result
```

每个 commit 只暂存明确文件；禁止 `git add .`，禁止混入现有无关工作树改动或 submodule 改动。

## 15. 第一批施工票

立即开始的前五张票：

1. **P2FIX-000**：冻结当前 P2 工作树、native、APK 和 asset 证据。
2. **P2FIX-010**：增加 media base，并在 Rust 接入官方 IRI 编码。
3. **P2FIX-013**：把 MathJax 子目录打入 APK，增加 APK gate。
4. **P2FIX-014**：移除正式页面的 Recording player，接入真实 AV/TTS。
5. **P2FIX-011/012**：重写一次解码和 bounded Range。

这五项完成前，不应继续把 P2-021、P2-030、P2-032 标为完成，也不应开始 Phase 2 技术签字。

