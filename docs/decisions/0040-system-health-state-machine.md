# ADR 0040: 系统健康状态机替换累计扣分模型

日期：2026-08-24
状态：已实施（设置页一次性清理计划 Phase 8）

## 背景

旧模型把 24h 内异常日志累计成"分数"，用户点击"确定（-40分）"手工扣分
才能解锁被强制跳转并锁定的健康页。问题：

- 按钮扣分伪装故障恢复，"已确认"改写事实；
- 普通日志错误即可触发强制 push + PopScope 锁页；
- 分数只增不减，无系统证据的 resolve 路径。

## 决策

### 状态分离（`SystemHealthEvent` + `SystemHealthPolicy`）

- `detected`：活跃窗口（24h）内存在异常组，`effectiveScore`
  （error=3/组、warning=1/组、fatal 组钉住 critical）随组老化**自动衰减**；
- `acknowledged`：用户看过横幅（隐藏横幅，不改事实；新检测自动重开）；
- `safeMode`：缓解（运行时 overlay，不改用户设置）；
- `checkPassed`：上次自检通过（DB `PRAGMA integrity_check` + 分数重算）；
- `resolved = checkPassed && 活跃分 < 10`：只有系统证据能达成；
- `expired`：7 天无复发自动过期；
- `dataIntegrityBlock`：独立于日志分数的数据完整性风险通道
  （`reportDataIntegrityRisk(reason)`），展示强警告 + 备份/导出/安全模式
  建议，但**不锁页**。

### 告警行为

- App shell 不再自动 push SystemHealthRoute（强制跳转代码已删除）；
- 健康页 PopScope 锁页与"确定（-40分）"/`confirmAndDeductScore`/
  `markHandled` API 全部移除；
- attention/critical 以非阻断横幅呈现，可"我知道了"确认；
- 自检按钮运行 `runSelfCheck()`，通过且分数衰减后才标记 resolved。

## 后果

- 用户不会再被普通日志错误锁在健康页；
- 清空日志不再影响健康状态（分数来自持久化事件组，非日志文件）；
- 旧持久化事件的 `handled` 字段兼容读取为 acknowledged；
- 分数保留为严重度聚合/排序信号，但不存在任何用户驱动的扣分入口。

测试：`test/application/system_health_monitor_test.dart`（状态机全套），
`test/views/settings/system_health_page_test.dart`（无锁页、无扣分 UI、
确认不改事实、自检入口）。
