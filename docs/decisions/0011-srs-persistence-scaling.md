# ADR 0011 — SRS 持久化扩展（分片阈值）

> 状态：Accepted ｜ 日期：2026-07-11 ｜ 关联：future4 Phase 20、`SrsProvider._persist`
## 决策

1. **先测量**：`SrsProvider.encodeStateForPersist` + `test/application/srs_persist_benchmark_test.dart`（500 / 2000 / 10000 行）。
2. **分片阈值**（future4）：若在有代表性的宿主上 **n > 2000** 时编码耗时 **> 5 ms**，则实现 `srs.state.shard.<i>`，每次复习只重写受影响的分片。
3. **Phase 20 结论**：基线测试落地；**分片推迟**——在典型开发机 Linux / CI 宿主上，1 万条的全量编码远低于 5 ms（2 千条时常常是亚毫秒），当前课程规模远低于 2 千条 SRS 词条。
4. 生产路径仍是**单 blob** 键 `LocalStateKeys.srsState`；等真实斯瓦希里语内容（future5）或用户历史逼近实测阈值时再重新评估。
## 理由

每次 SRS 复习都把整个 `Map<String, SrsWord>` 重新编码进单个偏好键（`srs.state`），是 O(n) JSON 工作；词表规模上去后可能成为卡顿来源。
## 影响与边界

- 既有偏好不需要迁移。
- 基准测试记录规模，但不含易抖的墙钟断言。
- 若将来实测超过阈值，实现分片而不改 `SrsProvider` 的公开 API。