# archive/ — 官方 Anki Core 迁移历史文档库

> **本目录只放历史记录，不放施工依据。任何波次都不得从这里开。**
> 现行状态唯一真源：[`../34-cutover-receipt.md`](../34-cutover-receipt.md)。
> 现行施工入口：[`../34-official-anki-production-cutover-and-ohos-retirement-plan.md`](../34-official-anki-production-cutover-and-ohos-retirement-plan.md)。

## 为什么保留

1. **审计与合规**：Anki 内核是 AGPL 依赖，迁移过程的 Go/No-Go 决策、验收撤销与豁免记录是发布合规证据链的一部分，不可因代码删除而抹除。
2. **门禁可复算**：Phase 0–4 与 P5 各阶段的真机/构建证据（日志、APK 采样、截图）以本目录为复算依据；主计划 §13.2 明确「历史 archive/test artifact 不因代码删除而抹除」。
3. **决策溯源**：多轮「验收撤销 → 复验 → 撤销过早 GO」的往复过程，是理解当前收口口径为何保守的必要背景。

**代价已知**：本目录约 12,600 行 + `artifacts/` 173 个文件，其中大量路径引用指向已删除的 Legacy 复刻层（`lib/application/anki/*`）。**这些失效引用是合规的历史陈述，不要逐条修**——判据是「是否仍在指导当前施工」，归档文档一律不是。

## 编号说明

- `00`–`29`、`31`、`32`、`33` 为 Phase 0–4 与 P5 的计划/报告/验货，按阶段顺序编号。
- **编号 30 不在此目录**：官方 Anki 卡按语言课体验投影与渲染（doc 30）原本留在根目录，2026-09-27 起已归档至本目录（见下表）。
- `p2fix.md` / `p3fix.md` 是阶段内插入的修补计划，不参与主编号序列，按惯例以 `p<阶段>fix` 命名。
- `34-*`（收口计划族）留��根目录，是现行文档，不归档。

## 目录内容

### 已标注 superseded 的

| 文档 | 状态 |
|---|---|
| [`28-p5d-remainder-construction-plan.md`](./28-p5d-remainder-construction-plan.md) | 由 doc 34 接管；「OHOS 继续 Legacy」作废（ADR 0041） |
| [`31-anki-product-experience-plan.md`](./31-anki-product-experience-plan.md) | 由 doc 34 接管 / superseded |
| [`32-official-anki-experience-parity-plan.md`](./32-official-anki-experience-parity-plan.md) | 由 doc 34 接管 / superseded |
| [`33-official-first-import-construction-plan.md`](./33-official-first-import-construction-plan.md) | 由 doc 34 接管 / superseded |

### 2026-09-27 新归档

| 文档 | 原位置 | 归档原因 |
|---|---|---|
| [`30-course-like-card-experience-plan.md`](./30-course-like-card-experience-plan.md) | 根目录 | 22/22 代码路径引用全部失效（`projection/` 子目录已解散）；「自动题型识别」部分已被 doc 37 取代；成果已由 CHANGELOG 记录 |
| [`36-projection-tree-ordering-and-limits.md`](./36-projection-tree-ordering-and-limits.md) | 根目录 | 7/7 落点全部失效；成果已由 CHANGELOG 记录 |
| [`34-remaining-construction-plan.md`](./34-remaining-construction-plan.md) | 根目录 | R0–R8 已由收据全部闭环；110 个未勾框 / 0 个已勾框，勾选框不代表施工状态；与主计划章节骨架重复 |

> 归档这三篇时同步改写了全部 24 处入链（README 索引、主计划、收据、37/38、project-guide、webview 计划、CHANGELOG、archive 内 31/32 的相对路径）。

### 其余各阶段

`00`–`29` 与 `p2fix` / `p3fix` 保持原样，逐篇清单见上级 [`../README.md`](../README.md) 的 Archived 表格。

## artifacts/

构建与真机证据随归档保留，**原文相对路径保持不变以方便回查**。共 173 个文件，主要子目录：

| 子目录 | 内容 |
|---|---|
| `p2-000-baseline/` `p2e-p3/` `p2fix/` `p3fix/` | Phase 2–3 证据 |
| `p3r-p4/` `p4/` `p4r2/` | Phase 4 返工证据 |
| `p5c/` `p5d/` `p5f/` | P5 各波次证据 |
| `cutover-once/` | ANKI-CUTOVER-ONE-SHIP 一次性施工门禁证据（含 APK sha256） |

## 给下一个读者的三条提醒

1. **不要用归档文档判断当前进度。** 读 [`../34-cutover-receipt.md`](../34-cutover-receipt.md) 的「Held」表与「架构简化批次」两节。
2. **不要按归档里的命令复跑门禁。** 大量测试文件已随 Legacy 退场删除，照抄会因文件缺失失败——那不代表回归。
3. **历史数字（catalog v11 / contract 1.11 / `kSchemaVersion` 22 / 测试 1852:0）一律已过期**，现行值见上级 README 的「准确口径」行。
