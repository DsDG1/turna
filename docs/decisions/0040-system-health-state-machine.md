# ADR 0040 — 系统健康状态机替换累计扣分模型

> 日期：2026-08-24 ｜ 状态：已实施（设置页一次性清理计划 Phase 8）
## 决策

### 状态分离（`SystemHealthEvent` + `SystemHealthPolicy`）

- `detected`：活跃窗口（24h）内存在异常组，`effectiveScore`（error=3/组、warning=1/组、fatal 组钉住 critical）随组老化**自动衰减**；
- `acknowledged`：用户看过横幅（隐藏横幅，不改事实；新检测自动重开）；
- `safeMode`：缓解（运行时 overlay，不改用户设置）；
- `checkPassed`：上次自检通过（DB `PRAGMA integrity_check` + 分数重算）；
### 告警行为

- App shell **不再**自动 push SystemHealthRoute（强制跳转代码已删除）；健康页 PopScope 锁页与「确定（-40分）」/`confirmAndDeductScore`/`markHandled` API 全部移除；
## 理由

旧模型把 24h 内异常日志累计成「分数」，用户点「确定（-40分）」手工扣分才能解锁被强制跳转并锁定的健康页。
## 影响与边界

- 用户不会再被普通日志错误锁在健康页；清空日志不再影响健康状态（分数来自持久化事件组，非日志文件）。
- 旧持久化事件的 `handled` 字段兼容读取为 acknowledged；分数保留为严重度聚合/排序信号，但**不存在任何用户驱动的扣分入口**。
