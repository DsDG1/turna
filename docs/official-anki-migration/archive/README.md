# archive/ — 官方 Anki Core 迁移历史索引（2026-10-19 精简后）

> **本目录只放历史记录，不放施工依据。任何波次都不得从这里开。**
> 现行状态唯一真源：[`../34-cutover-receipt.md`](../34-cutover-receipt.md)。
> 现行施工入口：[`../34-official-anki-production-cutover-and-ohos-retirement-plan.md`](../34-official-anki-production-cutover-and-ohos-retirement-plan.md)。

## 2026-10-19 精简说明

本目录原有 **44 篇** Phase 0–4 / P5 施工计划与结果报告 + **173 个**构建与真机证据文件（8.08 MB），全部只被本目录内部互引，无一被 CI、门禁脚本或活跃文档依赖。本批删除：

- **44 篇**已闭环的历史施工文档（阶段计划 / 结果报告 / 施工手册 / 验货报告）。它们记录的结论均已被 [`../34-cutover-receipt.md`](../34-cutover-receipt.md) 的现行口径取代；文中的阶段性 NO-GO 措辞只对当时有效，**不可当作今天的进度**。
- **169 个**构建与真机证据文件（真机截图、uidump XML、构建日志、hash 快照）。其中 52 张 PNG 无人引用，117 个 txt/xml/json 仅被已删除的同目录文档引用。

**保留 4 个文件**（有仓库内真实引用方）：

| 文件 | 引用方 |
|---|---|
| `artifacts/cutover-once/apk-sha256.txt` | [`../34-cutover-receipt.md`](../34-cutover-receipt.md) R8 行 · `test/archive/BASELINE-pre-2026-09-20.md` |
| `artifacts/p4r2/native-hash-manifest.txt` | `tool/official_anki_native_hash_manifest.sh` 默认输出路径 |
| `artifacts/recognizer-diff-report-2026-08-29.md` | `test/archive/BASELINE-pre-2026-09-20.md`（doc 37 识别器 diff 报告，16/16 一致或改进） |
| `artifacts/p5f/README.md` | P5-F 灰度回执归档约定（文件名清单） |

> **发布合规证据链不在本目录**——在 [`../../../native/turna_anki_core/licenses/`](../../../native/turna_anki_core/licenses/)（ANKI-LICENSE / SOURCE-OFFER.md / THIRD-PARTY-NOTICES-DRAFT.md），门禁为 `test/application/anki_official/official_anki_license_test.dart`。本目录从来不是合规证据的载体。

## 已删除文档的结论速查（决策溯源保留）

下表是 2026-10-19 前本目录 44 篇文档的**结论摘要**。原始全文已随本批删除（可经 git 历史 `docs-cleanup-backup-2026-10-19` tag 恢复）；**结论本身已沉淀到 [`../34-cutover-receipt.md`](../34-cutover-receipt.md) 与 `CHANGELOG.md`**。

| 编号 | 主题 | 当时的结论（均已被收据取代） |
|---|---|---|
| 00 | 总体迁移方案 | 提案；141 个未勾选框是计划状态，非未施工 |
| 01 | Phase 0 实施方案（Android arm64 技术 Spike） | Phase 0 已收口，Conditional Go |
| 02 | Phase 0 结果报告 | Conditional Go（P0-004 真机仍缺） |
| 03 | Phase 1 实施方案（稳定 Engine 与官方导入） | 生产切流状态：禁止 |
| 04 | Phase 1 结果报告 | 已降级；以 06 为准 |
| 05 | Phase 0+1 技术修补与收口计划 | 已实施 |
| 06 | Phase 0+1 技术修补结果 | TECHNICAL CONDITIONAL GO |
| 07 | Phase 2 官方原卡渲染实施计划 | 已施工；TECHNICAL CONDITIONAL GO / PRODUCTION NO-GO |
| 08 | Phase 2 结果报告 | IMPLEMENTATION IN PROGRESS / TECHNICAL ACCEPTANCE NO-GO |
| 09 | P2 补齐 + Phase 3 课程投影实施计划 | HOST CONSTRUCTION GO / P3 STRICT ENTRY NO-GO |
| 10 | Phase 3 课程投影修补结果 | P3 TECHNICAL / PRODUCTION NO-GO |
| 11 | P3 阻断修补 + Phase 4 Scheduler 计划 | 计划冻结；P4 ENTRY NO-GO |
| 12 | Phase 4 官方 Scheduler 实施计划 | 计划冻结；P4 TECHNICAL / PRODUCTION NO-GO |
| 13 | Phase 4 结果报告 | P4 HOST GO / TECHNICAL ACCEPTANCE NO-GO |
| 14 | Phase 4 验货 + Phase 5 Legacy 迁移计划 | P5 CUTOVER/DELETE 仍 NO-GO |
| 15 | P5-A01 Legacy dependency inventory | 已闭环 |
| 16 | P4 生产门禁收口 + P5-B 准备 | 已闭环 |
| 17 | P4R3 结果报告与 P5-B 验收 | 已闭环 |
| 18 | P4R3 验货报告 | 已闭环 |
| 19 | P4R3 / P5-B 实施手册 | 已闭环 |
| 20 | P4 其余完善计划 | 已闭环 |
| 21 | P5-C Fixture Pilot 施工手册 | 已闭环 |
| 22 | P5-C 实施验收与结果报告 | 已闭环 |
| 23 | P5-C 验货报告 | 已闭环（只保留作废 GO 记录） |
| 24 | P5 收口、生产切换与 P6 AnkiWeb 计划 | P5-C §4 已收口 |
| 25 | P5-C 收口结果报告 | 已闭环 |
| 26 | P5-D Sprint D1 生产路由施工手册 | 已闭环 |
| 27 | P5-D Sprint D1 验货报告 | 已闭环 |
| 28 | P5-D 后续大施工计划 | 已收口（OHOS 继续 Legacy 已由 ADR 0041 作废） |
| 29 | P5-E Wave 1 生产解耦与架构约束 | HOST CONDITIONAL GO（断生产引用、隔离 Legacy、无数据删除） |
| 30 | 官方 Anki 卡按语言课体验投影与渲染 | Host / Unit 已通过；生产默认未翻。成果由 CHANGELOG 承载 |
| 31 | Anki 产品体验收口 | 历史规格，勿按本文开波次 |
| 32 | 官方 Anki 与自研体验对齐 | 历史规格，勿按本文开波次 |
| 33 | P5-F 官方先行导入施工计划 | 历史规格，勿按本文开波次 |
| 34-remaining | 一次性验收返工与生产收口实施计划 | R0–R8 已由收据全部闭环 |
| 35 | Legacy 复刻层清理（L0–L3） | 已施工（2026-08-27），被复制的 Legacy 层已物理删除 |
| 36 | 投影课程树顺序与限额修复 | 已施工（2026-08-28），成果由 CHANGELOG 承载 |
| 37 | 通用卡片识别器重设计 | 已施工（2026-08-29），diff 门禁 16/16；现行实现见 `lib/application/anki_import/recognition/` |
| 38 | Anki 集成减负与性能批次一 | 已施工并验货（2026-08-30，零回归） |
| 39 | Anki 集成减负与性能批次二 | 已施工（2026-08-30），余项移交 40 收口 |
| 40 | doc 39 收尾施工计划 | 部分收口（2026-08-30），Rust 四波复验待工具链主机 |
| p2fix | Phase 2 官方原卡渲染修补 | 已实施完毕 |
| p3fix | Phase 3 课程投影修补 | Host 施工已落地 |

## 编号断档说明

- `00`–`29`、`31`–`33`、`34-remaining`、`35`–`40` 为 Phase 0–4 与 P5 的计划 / 报告 / 验货。
- `p2fix.md` / `p3fix.md` 是阶段内插入的修补计划，不参与主编号序列。
- 编号不复用；`0021` 与 `0043` 各有两篇是历史编号复用，不是错号。
- **原文可经 git 恢复**：`git show docs-cleanup-backup-2026-10-19:docs/official-anki-migration/archive/<文件名>`。

## 给下一个读者的三条提醒

1. **不要用归档文档判断当前进度。** 读 [`../34-cutover-receipt.md`](../34-cutover-receipt.md) 的「Held」表与「架构简化批次」两节。
2. **不要按归档里的命令复跑门禁。** 大量测试文件已随 Legacy 退场删除，照抄会因文件缺失失败——那不代表回归。
3. **历史数字（catalog v11 / contract 1.11 / `kSchemaVersion` 22 / 测试 1852:0）一律已过期**，现行值见上级 README 的「准确口径」行。
