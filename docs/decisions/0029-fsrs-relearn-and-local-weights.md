# ADR 0029 — FSRS Relearn Ladder + Local Weight Fitting

> 状态：Accepted ｜日期：2026-07-29

## 决策

### 1. 当日重学阶梯（规则式）

失败连击按**每卡每本地日历日**计（`ReviewHistoryDao.countFailsOnLocalDay`），不是终身 `lapses`：

| Today’s fail # | Next due |
|----------------|----------|
| 1 | +10 min (or +30 min if mature, S≥21) |
| 2 | +30 min |
| 3 | +2 h |
| ≥4 | next local day |

在包调度器之后由 `FsrsEngine.reviewWithFailContext` 应用。

### 2. 本地权重拟合（轻量）

- 21 个权重持久化在偏好（`srs.fsrsParameters`）；为空即用默认值。
- `FsrsLiteOptimizer`：纯 Dart 投影式 SGD，在 `review_events` 构造的按时间排序 pass/fail 序列上做二元交叉熵。
- 最少 **300** 条复习记录；仅当训练损失相对改善 ≥0.5% 才接受。
- 设置页手动触发（「根据学习记录优化」）；绝不静默自动训练。
- 不保证与 `fsrs-rs` 数值一致；优先本地优先的移动端。

### 3. 二元契约不变

仍然只有 pass/fail；Anki 的 Hard/Easy 仍折叠为 pass。

## 理由

ADR 0028 引入 FSRS 与**二元** pass/fail 评分后剩两处缺口：

1. 失败后的重学是固定 10 分钟（外加一个粗糙的终身失败上限）。
2. 所有用户共用默认 FSRS 权重；`review_events` 有完整本地历史表却无个性化。

四档 UI 仍**不在范围内**。

## 影响与边界

- 连刷失败比「永远 10 分钟」惩罚轻，也比终身上限安全。
- 个性化权重可选且可回退。
- 优化器是近似实现；重度用户后续可迁到 FFI `fsrs-rs`。
