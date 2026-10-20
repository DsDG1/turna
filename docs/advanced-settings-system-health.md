# 高级设置与系统健康实现

Turna 的高级设置是一个四入口的中枢页（AI 连接 / 存储与性能 / 系统健康与诊断 / 旧版与兼容性），不再拆「Anki 引擎」与「系统与实验」两个并列入口。本文记录实现边界与验收证据，避免后续维护把安全开关退化成只影响界面的装饰选项。

## 设置信息架构

设置首页「高级」组（路由 `/settings/advanced`，页面 `lib/views/settings/pages/advanced_settings_page.dart`）只做导航，正文由 `SettingsAdvancedSection` 渲染：

| 入口 | 落地路由 | 本页内容 |
|---|---|---|
| AI 连接 | `AiApiConfigRoute` | AI 端点、模型、凭据与连接测试 |
| 存储与性能 | `StorageDiagnosticsRoute` | 占用统计与缓存清理 |
| 系统健康与诊断 | `SystemHealthRoute` | 健康状态机、自检、安全模式、脱敏报告 |
| 旧版与兼容性 | `LegacyCompatibilityRoute`（`/settings/advanced/legacy`） | 强制禁用 WebView JavaScript、实验性兼容开关、恢复默认值 |

旧版与兼容性页内的「实验性兼容开关」目前只承载 AI 引擎层开关（响应缓存开关、严格 schema 模式），**不再有** WebView 复用 / 后台诊断开关。恢复默认值调用 `SettingsProvider.resetLegacyCompatibilityDefaults()`；系统健康脱敏报告会带上 `ankiForceDisableJs` 开关值。

## 首期高级能力

- 卡片渲染模式：全局默认「自动选择」= Flutter HTML；仅 `allowJs` 现场解密、MathJax 或用户强制「优先 WebView」才开 WebView。也可选纯文本兼容。无 WebView 的平台走同一套 Flutter HTML，再不行才文本降级。
- WebView 网络策略：默认完全离线；离线与询问模式会向页面注入 CSP，拦截外部连接和远程资源。询问模式先阻断，再由用户决定是否仅本次放行。
- 解密缓存管理：展示成功缓存数、实际字节数、最近抓取时间和真实抓取失败数；可清除全部或单个牌组，重新生成采用下次复习懒生成。
- 单牌组覆盖：渲染、JavaScript、智能去解密、抓取延时和网络策略均可覆盖；删除覆盖后即时继承全局值。
- 恢复默认值：只重置高级偏好和牌组覆盖，不修改 SRS、复习历史、导入数据、AI 配置、主题和无障碍设置。

> 「兼容性诊断」（缺失媒体 / 字段数量 / 空模板 / 平台能力的只读扫描）已从正式高级中心移除：原实现目录 `lib/application/anki/` 整体删除，`lib/` 内已无对应实现。官方 Anki 的导入诊断入口是 debug-only 的 `OfficialAnkiReviewerRoute`（`DiagnosticsReleaseGuard` / `TURNA_OFFICIAL_ANKI_DIAGNOSTICS` 门控）；原「开发者实验室」设置分类已整体删除。

主要入口与运行时连接点：

- `lib/views/settings/pages/advanced_settings_page.dart`（`AdvancedSettingsPage` / `LegacyCompatibilityPage`）
- `lib/views/settings/widgets/settings_advanced_section.dart`（`SettingsAdvancedSection`）
- `lib/views/settings/system_health_page.dart`（`SystemHealthPage`）
- `lib/views/settings/storage_diagnostics_page.dart`
- `lib/application/settings_provider.dart`
- `lib/application/system_health_monitor.dart` + `lib/application/diagnostics/system_health_policy.dart`
- `lib/views/anki/anki_html_card_view.dart`
- `lib/core/theme.dart`（`TurnaTheme`，配色真源）

## 第二阶段与专业能力

### 渲染、媒体与导入性能

- 默认卡面是 Flutter HTML + `AnkiRevealScaffold`。若走了 WebView，主页面、模板脚本或解密抓取失败后会降到 Flutter HTML / 纯文本，错误详情保留在可展开入口中，复习不会停在空白页。解密进缓存后下一张回 Flutter。
- 媒体策略会真实参与导入和显示：已有文件可去重；缺失图片显示占位；超过 2 MB 的 JPEG/PNG 可压缩并限制最长边为 2048 像素；可跳过未被字段、模板或 CSS 引用的媒体；原音频失败时可使用当前卡片文字进行系统朗读。
- 为保持旧牌组行为，“导入未引用媒体”默认开启；只有用户主动关闭后才进行引用筛选。
- 节能、均衡和快速档位分别使用 250、500、1000 行解析批次，不向用户暴露底层批次参数。
- 「导入时生成结构化练习」已接入 `assemble(forceCardRefs:)` 与导入预览开关，默认关。按已交付的 anki-completion-and-render-plan（正文在 Git 历史），这些题只应出现在**练习入口**。牌组页已有独立「练习」；复习仍走原卡。映射在打开练习时消费，不必再写入课树。不要再加题型开关。已导入牌组不改写。安全模式运行时视为关，不改写偏好。开关 ON 仍写课树题（补齐计划不把它改成空操作）。
- 实验性的 WebView 复用与后台诊断开关**已从设置树移除**（`lib/` 内无对应偏好键与 UI）。安全模式仍会临时停用实验区。接入运行时之前，不要把它们写成已生效能力。

### 调度实验室

- 导入预览提供“保留 Anki”“复习历史 + Turna FSRS”“全部新卡”三种方式，并在选择旁展示受影响卡片数和历史条数。
- 同胞卡按 `importId + noteId` 批量归组。新卡与复习卡可分别设置当天隐藏；当天已经复习过同笔记的卡也会被过滤，不执行逐卡数据库查询。
- 难卡阈值为 2–20 次失败；达到阈值后写入难卡标记，可仅提醒、进入现有难卡专项视图，或自动暂停。默认 5 次且不自动暂停。
- FSRS 专业区默认折叠，最大间隔、间隔抖动和失败重学阶梯会重建运行中的 FSRS 调度器；新卡/复习卡顺序会参与 Anki 批次选择。页面使用当前卡片状态提供四档结果预览。
- 目标保持率与参数优化仍留在学习设置，高级页只提供去向说明，避免同一配置出现两份。

### 维护与实验功能

- 存储维护页按课程数据库、Anki 媒体、解密缓存、AI 缓存和日志展示占用；缓存清理只删除可重新生成的解密与 AI 缓存。
- 数据库完整性使用只读 `PRAGMA integrity_check`；索引维护使用 `REINDEX` 与 `PRAGMA optimize`，不会混入清除学习数据操作。
- 脱敏报告在导出前预览，使用内存文件分享，不依赖个人临时路径；报告包含版本、结构版本、平台、WebView/TTS、错误摘要及高级设置，但不包含原始错误正文、密钥、卡片正文、用户输入或 AI 对话。
- 实验性兼容开关内联在「旧版与兼容性」页的「实验性兼容开关」分组，逐项显示用途、风险与是否已接入运行时；当前只承载 AI 引擎层开关。安全模式临时停用实验区而不改写用户选择。

## 系统健康

`SystemHealthMonitor` 在应用启动时安装，直接监听 `LogCapture` 的全局日志流，不依赖用户打开透明度报告。状态通过本机偏好持久化。

> 本节口径 = ADR 0040（`docs/decisions/0040-system-health-state-machine.md`，2026-08-24）。旧的「累计扣分 + 强制跳转 + 锁页」模型已整体废弃，下文不再描述。

### 状态机

`SystemHealthEvent`（`lib/application/system_health_monitor.dart`）把「检测事实」与「用户动作」严格分开，六个概念互不冒充：

| 状态 | 含义 | 谁能改 |
|---|---|---|
| `detected` | 活跃窗口（24h）内存在异常组，`effectiveScore` 随组老化**自动衰减** | 只有新日志 |
| `acknowledged` | 用户看过横幅（隐藏横幅，**不改事实**；新检测自动重开） | 用户点「我知道了」 |
| `safeMode` | 缓解（运行时 overlay，不改用户设置） | 用户开关 |
| `checkPassed` | 上次自检通过（DB `PRAGMA integrity_check` + 分数重算） | `runSelfCheck()` |
| `resolved` | `checkPassed && 活跃分 < 10`，**只有系统证据能达成** | 自检 |
| `expired` | 7 天无复发自动过期 | 时间 |

另有一条独立通道 `dataIntegrityBlock`：只由 `reportDataIntegrityRisk(reason)` 置位，独立于日志分数，展示强警告 + 备份/导出/安全模式建议，但**不锁页**。

### 评分与告警行为

- 分数是**严重度聚合信号**，不是可被按钮改写的结果：`SystemHealthPolicy` 明确 "nothing in the UI may deduct points"。warning 组计 1 分、error 组计 3 分，`fatal` 组在窗口内把结果钉到 critical（≥ 40）。阈值：10 分 attention、40 分 critical。
- 同一指纹聚成一组并保留真实发生次数；组随 `lastAt` 移出 24h 窗口自然不计分，**不需要任何用户点击**。
- App shell 不再自动 push `SystemHealthRoute`；`PopScope` 锁页与「确定（-40分）」/`confirmAndDeductScore`/`markHandled` API 全部移除。`SystemHealthPage` 任何时候都可自由离开。
- attention/critical 以**非阻断横幅**呈现于系统健康页，可「我知道了」确认；确认只隐藏横幅，不改检测事实。
- 「运行自检」执行 `runSelfCheck()`：完整性探针通过 **且** 分数衰减到 10 分以下，才标记 `resolved`。点任何按钮都无法伪造恢复。
- 旧持久化事件的 `handled` 字段兼容读取为 `acknowledged`；清空日志不影响健康状态（分数来自持久化事件组，不是日志文件）。

### 系统健康页提供的动作

- 运行自检 / 确认横幅（仅在有未确认告警时出现）/ 只读建议 / 脱敏报告预览与导出 / 复制摘要 / 安全模式开关 / 原始日志 / 独立清空日志。
- 安全模式是运行时覆盖，不重写用户设置；退出后自然恢复进入前配置。它强制模板脚本和外部网络保持关闭。
- 导出报告省略全部原始错误正文，只保留等级、模块、次数、版本、平台和关键设置，因此不会携带卡片正文或 AI 对话。
- 监控器内部异常不写回应用 logger，避免形成递归告警风暴。

## 自动化验收

相关测试覆盖：

- 高级默认值、覆盖持久化、删除回退和完整默认值恢复。
- CSP 离线拦截、询问桥和显式允许。
- 缓存统计、失败标记、按牌组清理，以及清理不影响 NoteStore、导入记录和 SRS。
- 状态机全套：`test/application/system_health_monitor_test.dart`（fatal 立即严重、相同循环错误聚合、10 分预警、自动衰减、7 天过期、新检测重开确认、自检才可 resolved、安全模式退出、重启持久化、清空日志不自动恢复健康状态）。
- 页面无锁页、无扣分 UI、确认不改事实、自检入口：`test/views/settings/system_health_page_test.dart`。
- 既有 Anki 高保真渲染和解密缓存回归。
- 三种排程继承中“仅历史”会保留 revlog、同时创建全新 FSRS 状态。
- 同笔记卡片的同批次隐藏、难卡阈值与自动暂停、FSRS 短阶梯/次日阶梯。
- 缺失媒体占位和音频 TTS 兜底。
