# WebView 卡片渲染与复习页面体验优化计划

> 文档代号：WEBVIEW-UX-2026-08  
> 日期：2026-08-23  
> 状态：已实施（阶段 A–F 代码落地，单元/组件/协议/资产测试通过；待 Android 真机矩阵验收，见 §10.3）  
> 范围：课程中的 Anki HTML 卡、统一复习中的保真卡、Anki 正式复习与官方 Anki 预览/复习  
> 核心目标：扩大有效卡片区域、让窗口随设备和内容自适应、移除应用额外生成的语音播报，并统一页面视觉与交互。

本文是可分阶段执行的施工计划。每一阶段都应能独立测试、独立提交、独立回滚，不改动 Anki 调度、评分和卡片数据语义。

---

## 0. 一句话方案

把「页面可用空间」「HTML 实际内容高度」「卡片自身媒体」作为三条独立能力处理：Flutter 负责分配尽可能大的响应式卡片区域，WebView 在允许 JavaScript 的前提下回传真实内容高度，官方 Anki iframe 自己跟随内容扩展；应用层自动 TTS 全部从 WebView 卡片路径移除，但卡片原生音频、视频和 `[anki:tts]` 等模板媒体继续保留。

---

## 1. 当前问题与根因

### 1.1 课程 HTML 卡片被固定为 300px

文件：`lib/views/lesson/components/interactions/anki_html_card_renderer.dart`

当前卡片外层使用：

```dart
SizedBox(height: 300)
```

后果：

- 大屏设备只使用很小一块区域；
- 长内容、表格、图片和输入框容易出现内部滚动或裁切感；
- 横竖屏、平板和系统字体缩放下仍保持同一高度；
- 正面与答案内容长度不同，但翻面后窗口不会调整。

### 1.2 通用 WebView 没有内容高度协议

文件：`lib/views/anki/anki_html_card_view.dart`

`AnkiHtmlCardView` 目前只负责加载 HTML，没有把 `document.scrollHeight` 回传给 Flutter，也没有监听页面内图片、MathJax、字体或异步模板造成的后续尺寸变化。

现有两类行为需要分别处理：

1. `allowJs == true` 或打字卡：可以安装受控的高度观察器；
2. `allowJs == false`：不能为了测量高度而放宽 JavaScript 策略，只能根据设备可用空间分配响应式初始高度。

### 1.3 官方 Anki 的 iframe 高度没有真正跟随内容

相关文件：

- `assets/anki_reviewer/reviewer.css`
- `assets/anki_reviewer/reviewer.js`
- `assets/anki_reviewer/card-frame.js`
- `lib/views/anki_official/official_anki_reviewer_view.dart`

`card-frame.js` 已在 `renderComplete` 中计算并返回高度，Android 原生层也会发出 `pageHeightChanged`，但：

- 外层 `iframe` 只有 `min-height: 100%`，没有明确的可用视口高度；
- iframe 的默认高度可能成为实际的小窗口；
- 图片、字体和 MathJax 在首次完成后继续改变尺寸时，没有持续更新 iframe；
- Flutter 的 `onHeight` 目前没有被页面布局使用。

### 1.4 WebView 卡片混入了应用额外生成的 TTS

文件：`lib/views/lesson/components/interactions/anki_html_card_renderer.dart`

当前路径会：

- 首次显示正面时按课程设置自动朗读；
- 揭示答案时自动朗读背面；
- 显示额外的系统朗读按钮；
- 先剥离 HTML，再调用 `AudioController.speak()` 合成语音。

这与卡片自身的媒体不是同一件事。需要移除的是上述应用层合成播报，不应删除：

- `[sound:xxx.mp3]` 转换出的 `<audio>`；
- `AnkiMediaStrip` 中的卡片音频和图片；
- 官方 Anki AV tag；
- 卡片模板明确声明的 `[anki:tts]`；
- 视频、MathJax、图片及用户主动点击的卡片媒体重播。

### 1.5 页面壳和 HTML 内容缺少统一设计规则

目前课程卡、统一复习卡和官方卡分别维护边距、圆角、阴影、背景和滚动行为。结果是在同一应用中出现不同的内容宽度、双层 padding、过小卡窗和嵌套滚动。

---

## 2. 实施边界

### 2.1 本轮包含

1. 课程 `AnkiHtmlCardRenderer`。
2. `OfficialTemplateWebViewBody` 与 `StudyCardSurface` 使用的保真 HTML 卡。
3. `UnifiedReviewPage` 与 `AnkiReviewSessionPage` 中的 WebView 卡片布局。
4. Android 官方 Anki reviewer shell、iframe 和卡片 frame。
5. 官方 Anki 预览页和正式复习页的卡片视觉壳。
6. WebView 卡片路径中的应用层自动/手动系统 TTS。

### 2.2 本轮不包含

1. 不修改官方 Anki Scheduler、FSRS、revlog 或评分按钮含义。
2. 不修改导入格式、Note/Card 数据和模板内容。
3. 不用 Flutter 重写复杂 Anki 模板。
4. 不移除卡片作者提供的音频、视频或 Anki TTS tag。
5. 不为了测量高度给原本禁用 JavaScript 的卡片开启 JavaScript。
6. 不统一删除普通语言课程中非 WebView 题型的发音学习能力。

---

## 3. 目标架构

```text
设备 SafeArea / 键盘 / 横竖屏变化
                  │
                  ▼
        Flutter 响应式尺寸策略
        ├─ 课程：给出较大的初始高度，并允许外层页面滚动
        ├─ 正式复习：占满按钮上方的全部剩余空间
        └─ 平板：限制最大内容宽度，增加有效卡片高度
                  │
                  ▼
              WebView 卡面
        ├─ JS 已获准：ResizeObserver 回传真实高度
        ├─ JS 未获准：保持安全策略，按视口自适应
        └─ 内容超上限：只在必要时启用 WebView 内部滚动
                  │
                  ▼
       卡片自身媒体继续独立播放
       应用生成的额外系统 TTS 不再进入此链路
```

需要建立一个稳定原则：**短内容不缩成小窗口，长内容尽量扩展，超过安全上限后才滚动。**

---

## 4. 阶段 A — 建立响应式尺寸策略

### 4.1 新增纯尺寸策略

建议新增：

```text
lib/views/anki/anki_webview_sizing.dart
test/views/anki_webview_sizing_test.dart
```

输入至少包含：

- 当前页面可用宽高；
- SafeArea；
- 横屏/竖屏；
- 使用场景：课程、统一复习、官方预览；
- WebView 回传的可选内容高度；
- 键盘 `viewInsets.bottom`。

输出至少包含：

- 卡片目标高度；
- 最小高度和最大高度；
- 是否需要内部滚动；
- 页面水平 padding 和最大内容宽度。

### 4.2 初始尺寸建议

数值需要通过真机微调，第一版建议：

| 场景 | 初始策略 | 内容高度策略 |
|---|---|---|
| 课程竖屏 | SafeArea 高度的 48%–55% | 不小于 320dp，按内容增长，建议上限 720dp |
| 课程横屏 | 优先保证底部操作可见 | 不小于 240dp，页面外层可滚动 |
| 统一/Anki 正式复习 | 使用评分栏上方全部剩余空间 | WebView 填满，不额外套固定高度 |
| 官方预览 | 使用 AppBar 与预览控制栏之间全部空间 | iframe 至少等于可见视口 |
| 平板/桌面降级视图 | 内容居中 | 最大宽度建议 760dp，保留足够垂直空间 |

### 4.3 约束

1. 不在 `build()` 中根据细微高度波动无限 `setState()`。
2. 高度变化小于 2dp 时忽略。
3. 频繁媒体 resize 需要节流到一帧或约 50–100ms。
4. 高度变化不能重建 `WebViewController` 或重新加载当前卡。
5. 打开键盘时优先保证输入框和底部操作可达，不强行维持竖屏最小高度。

---

## 5. 阶段 B — 改造通用 `AnkiHtmlCardView`

文件：`lib/views/anki/anki_html_card_view.dart`

### 5.1 增加内容高度回调

新增可选参数：

```dart
final ValueChanged<double>? onContentHeightChanged;
```

仅当页面本来就允许 JavaScript（`allowJs` 或打字卡）时：

1. 注册仅用于高度上报的 JavaScript channel；
2. `onPageFinished` 后读取 `documentElement`、`body` 的最大 `scrollHeight`；
3. 安装 `ResizeObserver`；
4. 监听图片、视频、字体和 MathJax 完成后的高度变化；
5. 回传去抖后的 CSS pixel 高度。

### 5.2 保持 JavaScript 安全边界

必须保留当前行为：

- `allowJs == false` 时仍为 `JavaScriptMode.disabled`；
- 不为测量高度临时开启 JavaScript；
- 不放宽本地文件根目录校验；
- 不允许外部 URL 导航；
- 不增加 `addJavascriptInterface` 一类原生桥；
- 高度消息只接受有限、非 NaN、正数值，并设置合理上限。

对于禁用 JavaScript 的页面，使用阶段 A 的视口尺寸策略，不追求 DOM 级实时测量。

### 5.3 注入统一的响应式基础 CSS

在不破坏 notetype CSS 的前提下补充：

- `box-sizing: border-box`；
- `max-width: 100%` 的图片、视频、SVG、canvas 和音频；
- 表格横向溢出保护；
- 长单词与 URL 换行；
- 输入框最大宽度与触控高度；
- light/dark `color-scheme`；
- 移动端安全 padding；
- 禁止页面背景与 Flutter 卡片壳出现明显色块断层。

不要强制覆盖卡片作者定义的字号、字体、文本对齐和主要配色，以免失去保真渲染。

### 5.4 加载体验

1. 页面切换正反面时保留卡片壳，避免白屏闪烁。
2. 加载期间只显示轻量顶部进度条，不用居中转圈遮挡旧卡。
3. 失败时保留现有文本降级或错误恢复路径。
4. WebView 背景色随 Flutter 主题同步，避免暗色模式闪白。

---

## 6. 阶段 C — 课程与统一复习布局改造

### 6.1 课程 HTML 卡

文件：`lib/views/lesson/components/interactions/anki_html_card_renderer.dart`

改造项：

1. 删除 `SizedBox(height: 300)`。
2. 使用阶段 A 的课程尺寸策略提供较大的初始高度。
3. 接收 `onContentHeightChanged`，在正面/答案切换后平滑调整高度。
4. 正反面内容高度不同时使用短时 `AnimatedSize` 或 `AnimatedContainer`，但动画期间不重新加载 WebView。
5. 课程外层 `SingleChildScrollView` 继续拥有页面级滚动；只有内容超过卡片最大高度时 WebView 才内部滚动。
6. 保留明确的「显示答案/返回正面」操作，不用语音按钮占据工具栏。

### 6.2 统一复习和 Anki Review Session

相关文件：

- `lib/views/review/components/official_template_webview_body.dart`
- `lib/views/review/components/study_card_surface.dart`
- `lib/views/review/unified_review_page.dart`
- `lib/views/anki/anki_review_session_page.dart`

改造项：

1. WebView 卡片继续占满 `Expanded`，不缩成内容高度很小的卡片。
2. 将页面固定的 20/24dp 间距改为按可用高度收缩的响应式间距，矮屏和横屏优先留空间给卡面。
3. 评分栏、显示答案按钮固定在可达区域，不被长卡片推到屏幕外。
4. 平板上对卡片最大宽度做限制并居中，手机上保持全宽。
5. 避免 `SingleChildScrollView`、WebView 和评分区域形成三层竞争滚动。

---

## 7. 阶段 D — 修复官方 Anki iframe 自适应

### 7.1 CSS 调整

文件：`assets/anki_reviewer/reviewer.css`

需要区分外层 shell 与卡片 frame：

1. `html`、shell `body`、`#card-host` 明确占满可见视口；
2. `#card-frame` 初始高度至少为 `100vh/100dvh`，不依赖 iframe 默认高度；
3. shell 不重复增加 12dp padding，卡片内容只保留一层响应式 padding；
4. 媒体、表格和长文本遵循与通用 WebView 一致的溢出规则；
5. 暗色模式背景从 shell 到 frame 连续一致。

建议在 `reviewer.html` 给外层 body 增加明确的 shell class，避免同一份 CSS 对 shell 和卡片正文产生双重 padding。

### 7.2 持续高度协议

文件：`assets/anki_reviewer/card-frame.js`

1. 保留现有 `renderComplete.height`。
2. 对 `#qa` 安装 `ResizeObserver`。
3. 图片、视频、字体或 MathJax 改变内容高度后发送 `contentHeightChanged`。
4. 消息携带当前 `nonce`、`generation`、`cardId` 和 `side`，旧卡消息必须被丢弃。
5. 高度消息节流并去重。

文件：`assets/anki_reviewer/reviewer.js`

1. 接收当前 generation 的高度消息；
2. 把 iframe 高度设为 `max(可见视口高度, 实际内容高度)`；
3. 监听外层视口 resize 和横竖屏变化；
4. 切换新卡时重置旧高度，先恢复为视口高度；
5. 长内容由外层 WebView 统一滚动，避免 iframe 内外双滚动。

### 7.3 Flutter 与 Android 层

相关文件：

- `lib/views/anki_official/official_anki_reviewer_view.dart`
- `lib/views/anki_official/official_anki_reviewer_stage.dart`
- `android/app/src/main/kotlin/me/dsdogs/turna/anki/reviewer/OfficialAnkiReviewerPlatformView.kt`

原则：

1. Flutter 的 PlatformView 仍占满复习区域，不按短内容缩小。
2. `pageHeightChanged` 用于校验 generation、调试和必要的布局通知，不作为把正式复习卡缩小的依据。
3. 如果需要把持续高度通知传到 Flutter，Android 只转发经过 `PresentAckCoordinator` 校验的当前 generation。
4. 不改变现有 CSP、媒体拦截、导航阻止和 iframe sandbox。

修改 reviewer 资产后必须同步更新 `assets/anki_reviewer/manifest.json` 的字节数与 SHA-256。

---

## 8. 阶段 E — 移除额外语音播报，保留卡片媒体

### 8.1 从 WebView 卡片路径删除

文件：`lib/views/lesson/components/interactions/anki_html_card_renderer.dart`

删除：

- `_maybeAutoSpeakFront()`；
- `_onRevealBack()` 中的系统 TTS；
- `_speakFront()` / `_speakBack()`；
- HTML 文本剥离与语言检测缓存；
- `record_voice_over` 系统朗读按钮；
- 仅为上述能力引入的 `AudioController`、`smart_speech`、`html_stripper` 和 `language_detector` 依赖。

统一复习中的 WebView 卡片也不得新增 `onSpeak` 或剥离 HTML 后播报的旁路。

### 8.2 明确保留

| 内容来源 | 行为 |
|---|---|
| 卡片 `<audio>` / `[sound:...]` | 保留，可由用户播放 |
| `AnkiMediaStrip.audioAssets` | 保留 |
| 官方 AV sound tag | 保留 |
| 卡片模板 `[anki:tts]` | 保留，视为卡片作者定义的多媒体 |
| 官方卡片媒体重播按钮 | 卡片确有 AV tag 时保留 |
| 应用从 HTML 纯文本临时生成的 TTS | 删除 |
| 显示正面/答案时的自动系统播报 | 删除 |

为避免重播按钮被误解为系统朗读，建议只在当前卡确有可重播 AV 内容时显示；无媒体时不显示空操作按钮。

---

## 9. 阶段 F — 页面视觉与交互统一

### 9.1 卡片壳

课程、统一复习和官方复习使用同一组视觉规则：

- 大圆角，建议 20–24dp；
- 1dp 低对比度边框；
- 轻量双层阴影，暗色模式降低阴影并增强边框；
- WebView 背景与卡片 surface 一致；
- 外层只保留一层 padding；
- 平板居中并限制最大宽度；
- 点击揭示区域具有明确语义和触控反馈，但不覆盖 WebView 内部链接、音频和输入控件。

### 9.2 操作区

1. 正面时主操作只有「显示答案」。
2. 答案时主操作为评分，翻回正面作为次要操作。
3. 媒体播放放在卡片内容附近，不与翻面、评分混成一排。
4. 矮屏下缩短卡片与评分栏之间的间距，不缩小按钮触控高度。
5. 打字卡弹出键盘后，输入框和提交/显示答案按钮都能通过滚动到达。

### 9.3 HTML 基础排版

仅提供兜底，不覆盖卡片作者设计：

- 默认正文 18px 左右、行高 1.45–1.6；
- 长文本可换行；
- 图片按原比例缩放；
- 表格必要时横向滚动；
- 音频控件宽度不超过卡片；
- `#answer` 分隔线与当前主题协调；
- `prefers-reduced-motion` 下关闭非必要高度动画。

---

## 10. 测试计划

### 10.1 单元与 Widget 测试

新增或扩展：

```text
test/views/anki_webview_sizing_test.dart
test/views/anki_html_card_renderer_test.dart
test/application/anki_official/official_anki_reviewer_assets_test.dart
test/application/anki_official/js/card_frame_protocol_test.mjs
```

必须覆盖：

1. 课程卡不再出现硬编码 `height: 300`。
2. 竖屏、横屏、平板和键盘弹出时目标高度都在约束内。
3. 高度回传只接受当前卡、当前 side 和有效数值。
4. 小于阈值的高度抖动不触发重布局。
5. 正面与答案高度不同会更新窗口，但不会重建控制器。
6. JS 禁用卡不会为了测量被改成 unrestricted。
7. HTML 卡显示、翻面、打字答案和评分流程保持可用。
8. WebView HTML 卡不再出现额外系统朗读按钮。
9. 显示正面和答案不会调用应用层 `AudioController.speak()`。
10. 卡片音频控件和 `AnkiMediaStrip` 仍存在。
11. 官方 iframe 在首次渲染、图片后加载和 MathJax 后加载时更新高度。
12. 旧 generation 的 resize 消息不会改变当前卡。
13. reviewer 资产 manifest 哈希与实际文件一致。

### 10.2 回归命令

```bash
flutter test --no-pub test/views/anki_html_card_renderer_test.dart
flutter test --no-pub test/application/anki_official/official_anki_reviewer_assets_test.dart
flutter test --no-pub test/application/anki_official/official_anki_card_frame_protocol_test.dart
flutter test --no-pub test/application/anki_official/official_anki_present_ack_test.dart
flutter analyze
```

如果修改 Android 原生高度转发，再运行：

```bash
./gradlew :app:testDebugUnitTest
```

### 10.3 真机矩阵

至少检查：

| 设备形态 | 页面 |
|---|---|
| 360 × 640 小屏竖屏 | 课程、统一复习、官方复习 |
| 412 × 915 常规手机 | 同上 |
| 手机横屏 | 同上，特别检查评分栏与键盘 |
| 800 × 1280 平板 | 内容居中、宽度和高度利用率 |
| Android 深色模式 | 普通 HTML、官方 iframe、媒体卡 |
| 系统字体 1.3×/1.5× | 长文本、打字卡、按钮区域 |

测试卡类型至少包括：短文本、长段落、大图、表格、音频、视频、MathJax、Cloze、自定义 CSS、允许 JS 的模板、打字答案卡。

---

## 11. 验收标准

### 11.1 尺寸

- 课程 WebView 卡不再固定为 300dp。
- 短卡片窗口在常规手机上明显大于当前版本，不出现局促的小框。
- 长卡片、图片和公式加载后不会被 iframe 默认高度裁切。
- 旋转设备或弹出键盘后布局会重新计算。
- 正式复习优先把评分栏上方的剩余空间交给卡片。
- 平板不会把内容无上限拉宽。

### 11.2 语音

- WebView 卡出现、揭示答案或点击空白卡面时，不触发应用层系统 TTS。
- WebView 卡面不再显示额外的系统朗读按钮。
- 卡片自带音频、官方 sound/tts tag 和有媒体时的重播能力仍正常。

### 11.3 设计与交互

- 课程、统一复习和官方复习的卡片圆角、边框、背景与间距一致。
- 页面只有一个主要垂直滚动区域；必要的表格横向滚动不影响页面翻面。
- 显示答案、评分和输入控件在小屏上始终可达。
- 暗色模式不闪白，内容和卡片壳无明显背景断层。

### 11.4 安全与性能

- 不放宽 CSP、导航、文件访问和 iframe sandbox。
- JS 禁用卡仍保持禁用。
- 高度变化不会造成无限布局循环、频繁 HTML reload 或 WebView 重建。
- 连续复习 50 张卡无明显高度残留、旧卡闪现和内存持续增长。

---

## 12. 推荐提交顺序

| PR | 内容 | 风险 | 回滚方式 |
|---|---|---|---|
| 1 | 尺寸策略、通用 WebView 高度回调、响应式 CSS、测试 | 中 | 恢复旧固定尺寸调用，不影响数据 |
| 2 | 课程与统一复习布局、移除额外系统 TTS | 低 | 恢复 UI 层调用，不影响卡片媒体 |
| 3 | 官方 reviewer shell/iframe 高度协议、manifest | 中高 | 单独回滚 reviewer 资产 |
| 4 | 视觉统一、横屏/键盘与可访问性收口 | 低 | 逐组件回滚样式 |

不要把官方 iframe 协议改造和课程 UI 改造放进同一个提交；前者需要 Android 真机验证，后者可先通过 Host Widget 测试稳定下来。

---

## 13. 完成定义

只有同时满足以下条件才视为完成：

1. 四类入口均完成尺寸与设计验证；
2. WebView 额外系统 TTS 已移除，卡片媒体回归通过；
3. JS/CSP/导航安全测试通过；
4. 相关 Flutter、JS 协议和 Android 测试通过；
5. reviewer manifest 已更新；
6. 至少一台小屏 Android 手机和一台常规尺寸 Android 手机完成真实课程与正式复习验收；
7. 没有把当前工作区中与本计划无关的改动带入提交。
