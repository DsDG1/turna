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
- **`30`、`34-remaining`、`35`、`36`、`37`、`38`、`39`、`40` 原本留在根目录，2026-09-27 起已归档至本目录**（见下表）。归档后根目录只剩 34 收据 / 34 主计划 / 41 / 42 四篇活跃文档。
- `p2fix.md` / `p3fix.md` 是阶段内插入的修补计划，不参与主编号序列，按惯例以 `p<阶段>fix` 命名。
- `34-*`（收口计划族）留在根目录，是现行文档，不归档。

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
| [`34-remaining-construction-plan.md`](./34-remaining-construction-plan.md) | 根目录 | R0–R8 已由收据全部闭环；110 个未勾框 / 0 个已勾框，勾选框不代表施工状态；与主计划章节骨架重复 |
| [`35-duplicate-legacy-layer-cleanup-plan.md`](./35-duplicate-legacy-layer-cleanup-plan.md) | 根目录 | L0–L3 四波已施工（2026-08-27）；被复制的 Legacy 复刻层已物理删除，自研资产保留；W9-A..E 收口由收据承载 |
| [`36-projection-tree-ordering-and-limits.md`](./36-projection-tree-ordering-and-limits.md) | 根目录 | 7/7 落点全部失效；成果已由 CHANGELOG 记录 |
| [`37-generic-card-recognizer-plan.md`](./37-generic-card-recognizer-plan.md) | 根目录 | P1–P5 已施工（2026-08-29），diff 门禁 16/16；识别器现行实现见 `lib/application/anki_import/recognition/` |
| [`38-debt-and-perf-batch-1-plan.md`](./38-debt-and-perf-batch-1-plan.md) | 根目录 | P1–P5 已施工并验货（2026-08-30，零回归）；P4-B 按计划条件推迟，其待办登记在收据 Held 表 |
| [`39-debt-and-perf-batch-2-plan.md`](./39-debt-and-perf-batch-2-plan.md) | 根目录 | 余项已全部移交并由 40 收口 |
| [`40-doc39-remainder-completion-plan.md`](./40-doc39-remainder-completion-plan.md) | 根目录 | 自述「已经全部施工」（2026-08-30）；Rust 四波的 `cargo test` + fixture regen 复验仍未跑，登记在收据 Held 表 |

> 归档这 8 篇时同步改写了全部入链（README 索引与目录布局说明、project-guide §3/§6.1 的 doc 35 引用、doc 42 前置阅读的 doc 37 引用、archive 内 `34-remaining` §18.3 的 WebView 矩阵条目）。

> **Rust 侧复验尚未完成**：doc 37/38/39/40 的 Rust 四波均为「本机无 cargo/protoc 静态编写」，统一待工具链主机 `cargo test -p turna_anki_bridge` + `gen_fixtures` 复验。归档不影响该待办的权威登记处（[`../34-cutover-receipt.md`](../34-cutover-receipt.md) 的 Held 表）。

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
