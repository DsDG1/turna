# ADR 0012 — `StudyLog` 追加策略（recent 队列）

> 状态：Accepted ｜ 日期：2026-07-11 ｜ 关联：future4 Phase 20、`StudyLogRepository`

## 决策

增量 recent 队列：

- `study.logs` — 主 90 天日志（键不变）；`study.logs.recent` — 待追加项，**上限 200**。
- `appendLog`：推入 recent、清过期行；`recent.length >= 200` 时并入主表、清空 recent、对主表做 90 天清理。每日统计更新仍在关键路径（小 map），不变。
- `readLogs`：主表 + recent 按 id 合并（recent 优先），按时间戳排序。
- `clearAll`：清两个键 + 每日统计。
- `_writeChain` 串行化所有写操作（不变）。

| Option | Pros | Cons |
|---|---|---|
| **Recent queue** (`study.logs.recent`, cap 200) | Small writes; simple JSON; merge on cap | Need dual-key read merge |
| Ring buffer single key | One key | Harder purge/merge; worse debug |

## 理由

`appendLog` 原先读全量 90 天日志列表、追加一条、清理、再整表写回——每次活动 O(n) 偏好 I/O。

## 影响与边界

- 追加一次典型学习会话只重写小的 recent JSON 数组。
- 全量重写成本摊到每 200 次追加（或 `flushRecent`）。
- 测试覆盖合并语义、上限 flush、清空、recent 损坏。
