# WebView 卡片渲染与复习页面体验优化计划

> 文档代号：WEBVIEW-UX-2026-08  
> 状态：**已实施（阶段 A–F 代码落地，2026-08-23；单元/组件/协议/资产测试通过）**；仅剩 Android 真机矩阵验收，权威条目与执行入口见 [`official-anki-migration/archive/34-remaining-construction-plan.md` §18.3 第 7 项](./official-anki-migration/archive/34-remaining-construction-plan.md)（该文件已归档），随下一次真机会话一并执行。  
> 文档状态：兼容入口，不再维护正文。历史版本由 Git 保存（`git log --follow docs/webview-rendering-optimization-plan.md`）。
> **补记（2026-09-27）：** iOS 官方 Anki 引擎启用（提交 `ec0170ae`，2026-09-26）后，本文的卡面缩放轨道新增 iOS 一支，见 §「iOS 卡面缩放轨道」。

## 结论

课程中的 Anki HTML 卡、统一复习保真卡、Anki 正式复习与官方预览/复习：扩大有效卡片区域、卡片窗口随设备和内容自适应、移除应用额外生成的语音播报、统一页面视觉与交互。不改动 Anki 调度、评分和卡片数据语义。

> 原 §5.3"注入 CSS 从不触碰作者字体/字号"约定修订（2026-08-28）：新增 opt-in 卡面缩放层——用户在无障碍设置开启"卡面文字大小"（`settings.cardTextScale`）且 >100% 时，Dart WebView 轨道注入 `html{zoom:N}`、Android 原生 reviewer 轨道设置 `WebSettings.textZoom`；默认 100% 时不注入任何字节，保真约定不变。**iOS 侧走另一条实现路径（`webkitTextSizeAdjust`），见文末 iOS 小节。**

## iOS 卡面缩放轨道（2026-09-27 补记）

iOS 官方 reviewer 是 WKWebView，**没有** `WebSettings.textZoom`，因此缩放走独立的四段链路：

1. **缩放值来源**：`official_anki_reviewer_stage.dart` 用 `cardTextScaleOf(context)` 读 `cardTextScale`，随 `setTextZoom` 通道下发给原生侧。
2. **原生侧**：`ios/Runner/AnkiReviewer/OfficialAnkiReviewerView.swift` 通过 `WKUserScript`（`.atDocumentStart`、`forMainFrameOnly: false`）注入，并在 MethodChannel `setTextZoom` 上把值钳制在 100–200。
3. **壳 → iframe 中继**：`assets/anki_reviewer/reviewer.js` 的 `OfficialReviewer.setTextZoom` 向内层 iframe 派发 `turnaTextZoom` 消息。
4. **iframe 侧**：`card-frame.js` 校验 nonce 后写 `webkitTextSizeAdjust`。

与 Android 的分工：Android 改 WebView 级 `textZoom`；iOS 改文档级 `webkitTextSizeAdjust`（壳与 iframe 都要写）。两条轨道共用同一个 `cardTextScale` 设置项，默认 100% 时均不注入任何字节。

## 待真机验收矩阵（原 §10.3，随 doc 34 真机会话执行）

> 权威矩阵与执行入口见 [`official-anki-migration/archive/34-remaining-construction-plan.md` §18.3 第 7 项](./official-anki-migration/archive/34-remaining-construction-plan.md)（已归档）。下表是本文自留的快照，仅供对照，**不作为执行依据**。

| 设备形态 | 页面 |
|---|---|
| 360 × 640 小屏竖屏 | 课程、统一复习、官方复习 |
| 412 × 915 常规手机 | 同上 |
| 手机横屏 | 同上，特别检查评分栏与键盘 |
| 800 × 1280 平板 | 内容居中、宽度和高度利用率 |
| Android 深色模式 | 普通 HTML、官方 iframe、媒体卡 |
| 系统字体 1.3×/1.5× | 长文本、打字卡、按钮区域 |

测试卡类型至少包括：短文本、长段落、大图、表格、音频、视频、MathJax、Cloze、自定义 CSS、允许 JS 的模板、打字答案卡。

## 验收标准摘要（原 §11）

- 课程 WebView 卡不再固定 300dp；短卡窗口明显变大、不局促；长卡/图片/公式不被 iframe 高度裁切；旋转或弹键盘后布局重算；正式复习把评分栏上方剩余空间交给卡片。
