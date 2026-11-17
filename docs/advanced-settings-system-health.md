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

## 现行高级设置与兼容边界

- **AI 连接**（`AiApiConfigRoute`）：管理 AI 端点、模型、凭据与连接测试；鸿蒙伴生版因合规不随包 AI 模块（`isDegraded(OhosDegradation.aiGeneration)`，见 [`decisions/0056-ohos-remove-ai-compliance.md`](./decisions/0056-ohos-remove-ai-compliance.md)），高级中枢页同步隐藏「AI 连接」入口与「实验性能力」分组。
- **存储与性能**（`StorageDiagnosticsRoute` / `StorageDiagnosticsPage`）：基于 `StorageInventoryService`、`CacheDiagnosticsRegistry`、`DatabaseDoctorService`、`OfficialStorageOptimizeService` 与 `OfficialAnkiGhostPurgeService` 提供总占用统计、分类卡片、安全缓存清理与数据库压缩/优化，仅清可重建缓存而不删除 SRS、复习历史或导入记录。
- **旧版与兼容性**（`LegacyCompatibilityRoute` / `LegacyCompatibilityPage`）：
  - **强制禁用 WebView JavaScript**：全局 `SettingsProvider.ankiForceDisableJs`（通过 `setAnkiForceDisableJs` 持久化），写入系统健康脱敏报告。
  - **实验性兼容开关**（仅非鸿蒙伴生版显示）：内联 AI 引擎层开关（`AiEngineConfigHolder` 的响应缓存 `cacheEnabled` 与 `StrictSchemaMode` 循环切换）及只读 `AiUsageMeter` 统计。
  - **恢复默认值**：调用 `SettingsProvider.resetLegacyCompatibilityDefaults()`，仅还原兼容性开关，不删除学习进度、SRS、牌组或 AI 凭据。
- **Official Anki 边界**：卡片浏览/复习与包诊断走 `libturna_anki.so` 仓内原生链路及 debug-only 的 `OfficialAnkiReviewerRoute`（`DiagnosticsReleaseGuard` / `TURNA_OFFICIAL_ANKI_DIAGNOSTICS` 门控）；旧版 v1 渲染模式切换、解密缓存、单牌组覆盖与独立调度实验室页面已退出主链路。

主要入口与运行时连接点：

- `lib/views/settings/pages/advanced_settings_page.dart`（`AdvancedSettingsPage` / `LegacyCompatibilityPage`）
- `lib/views/settings/widgets/settings_advanced_section.dart`（`SettingsAdvancedSection`）
- `lib/views/settings/system_health_page.dart`（`SystemHealthPage`）
- `lib/views/settings/storage_diagnostics_page.dart`（`StorageDiagnosticsPage`）
- `lib/application/settings_provider.dart`
- `lib/application/system_health_monitor.dart` + `lib/application/diagnostics/system_health_policy.dart`
- `lib/core/theme.dart`（`TurnaTheme`，配色真源）

### 存储维护与脱敏报告约定

- 存储维护页通过 `StorageInventoryService` 汇总课程数据库、记忆卡包、缓存与日志占用；缓存清理仅清除可重建缓存，不触碰用户学习历史与 SRS 账本。
- 数据库维护保持诊断与清理分离：健康自检执行只读完整性探针，存储页提供显式数据库优化入口（`OfficialStorageOptimizeService`）。
- 脱敏报告在导出前预览并使用内存文件分享；报告保留版本、平台、错误摘要及关键开关（含 `ankiForceDisableJs`），不携带原始错误正文、密钥、卡片正文、用户输入或 AI 对话。

## 系统健康

`SystemHealthMonitor` 在应用启动时安装，直接监听 `LogCapture` 的全局日志流，不依赖用户打开透明度报告。状态通过本机偏好持久化。

> 本节口径 = ADR 0040（[`decisions/0040-system-health-state-machine.md`](./decisions/0040-system-health-state-machine.md)）。状态机取代了旧的「累计扣分 + 强制跳转 + 锁页」模型，下文只描述状态机。

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

- 高级设置与 `ankiForceDisableJs` / `resetLegacyCompatibilityDefaults()` 等偏好持久化：`test/application/settings_provider_test.dart`。
- 存储统计、缓存清理与数据库优化：`test/views/settings/storage_diagnostics_page_test.dart`、`test/application/maintenance/storage_inventory_service_test.dart`、`test/application/maintenance/official_storage_optimize_service_test.dart`。
- 诊断遥测脱敏与计数：`test/application/diagnostics/diagnostics_telemetry_test.dart`。
- 状态机全套：`test/application/system_health_monitor_test.dart`（fatal 立即严重、相同循环错误聚合、10 分预警、自动衰减、7 天过期、新检测重开确认、自检才可 resolved、安全模式退出、重启持久化、清空日志不自动恢复健康状态）。
- 系统健康页面无锁页、无扣分 UI、确认不改事实、自检入口：`test/views/settings/system_health_page_test.dart`。
