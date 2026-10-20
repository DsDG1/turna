# ADR 0013 — SRS 队列基类

> 状态：Accepted ｜日期：2026-07-11 ｜关联：future4 Phase 21、ADR 0007

## 决策

`SrsQueueProvider`（`lib/application/srs_queue_provider.dart`）：

| Concern | Owner |
|---|---|
| Prefs key / log tag | Subclass abstract getters |
| State load / `persist` / `clear` | Base |
| `registerItem` / `registerAllItems` / `reviewItem` | Base |
| Primary due cache (`getDueItems`) | Base |
| Public API names (`registerWord`, `reviewGrammarPoint`, …) | Subclass wrappers |
| Dual expression due cache (Phase 20) | `SrsProvider` only |
| `markDueNow` | `GrammarReviewProvider` only |

## 理由

`SrsProvider`/`GrammarReviewProvider` 重复状态加载/持久化、SM-2 复习、到期缓存、课时关联——约 500 行近同构代码，公开方法名各异。

## 影响与边界

- **不做**：把词/表达拆成两个 provider（破坏单 blob 偏好与公开 API）。
- 子类为薄门面，行为由既有单测覆盖；`encodeStateForPersist` 在基类上（benchmarks import base）。
- 调用点不变。
