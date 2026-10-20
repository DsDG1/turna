# ADR 0028 — FSRS Continuous Memory Model for SRS

> 状态：Accepted ｜ 日期：2026-07-29

## 决策

1. 引入 `SrsScheduler` 抽象，含 `review`、`previewIntervalDays`、`retrievability`、`masteryScore`。
2. 默认实现：**FSRS** via `package:fsrs`（默认权重、`desiredRetention = 0.9`、最大间隔 730d、relearn ~10m）。
3. 保留 `Sm2Engine` 作 legacy scheduler 供测试/兼容；生产队列用 FSRS。
4. 扩展 `SrsWord` + `srs_states`（schema **v8**），加 `stability`、`difficulty`、`fsrsState`、`learningStep`。
5. **二元评分（锁死）：** 唯一面向用户的结果是 **pass / fail**（记住·做对 / 没记住·做错），映射到 FSRS Again / Good。四键 Again/Hard/Good/Easy UI **不在范围内**（不是推迟）。
6. 记忆曲线用 FSRS \(R(t,S)\)，不用 `exp(-Δt / intervalDays)`。
7. 成熟度 chip 文案：新卡 / 巩固中 / 长期记忆 / 顽固——**没有「毕业掌握」**。
8. 课时练习评级（对/错）在词条/语法点 id 已知时走同一条 pass/fail 管线。

## 理由

SRS 核心原是调参过的 **SM-2**（`lib/core/sm2.dart`），二元评分（认识/不认识）；Profile 成熟度 chip 依据 `intervalDays >= 21` 把卡标为 `new / young / mature / leech`——这套 UI 读起来像 **Leitner 式四盒「毕业」**，但：

1. SM-2 不预测召回概率 \(R(t)\)。
2. 「Mature」只是工作负载分桶，不是「掌握后永不再复习」。
3. 失败仍走粗糙规则（young → 1 天；mature ×0.2）。
4. 本地已有逐卡 `review_events` 历史，概率模型可直接用真实历史。

**掌握的产品定义（本文）**：连续信号 \(R_{\text{now}}\) 与稳定度 \(S\)（预测 \(R \approx 0.9\) 前的天数），**不是**「过了第 4 阶段 / 永不再复习」。

| Source | Role |
|--------|------|
| Ebbinghaus (1885) | Forgetting curve foundation |
| Leitner | Fixed boxes / multi-stage “graduation” — **rejected** as primary scheduler |
| SM-2 (Wozniak, 1987) | Prior implementation; ease + exponential intervals |
| Settles & Meeder, ACL 2016 (Duolingo HLR) | Trainable half-life for L2 vocab; continuous \(h\), not discrete stages |
| Ye et al., KDD 2022 (DHP / FSRS lineage) | DSR model + cost-optimal scheduling under target retention |
| FSRS (open-spaced-repetition; Anki 23.10+) | Production D/S/R scheduler; open benchmark superiority vs Anki SM-2 |

## 影响与边界

- 调度优化目标留存率，不是 ease-factor 启发式。
- 遗忘（lapse）用 post-lapse stability，不永远硬重置到「stage 1」；卡不会仅因阶段计数离开队列，长间隔仍然存在。
- 一次性迁移在 FSRS 字段为空时从 SM-2 `intervalDays`/`ease` 播种 \(S,D\)。
- Anki revlog 的 Hard/Easy 导入时折叠为 pass；UI 从不暴露四档。
- 目标留存率 \(R_{\text{desired}}\) 可由用户调节（默认 0.9），不需要新增评分按钮。
- 个性化权重优化部分已由 [ADR 0029](./0029-fsrs-relearn-and-local-weights.md) 修订。
