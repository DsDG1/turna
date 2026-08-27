# Plan 1：Anki 数据正确性、识别与存储治理

> 状态：**已实施**（Phase 0–5 全部落地，2026-08-23；主体交付见 commit 8b1e5534）
> 文档状态：兼容入口，不再维护正文。历史版本由 Git 保存（`git log --follow docs/plan-1-anki-data-integrity-and-storage.md`）。

## 结论

- 导入编排统一为 `unified_anki_import_orchestrator`：同进程 delete→re-import 回归、失败重试、并发拒绝、生产 inventory 判定（complete/failed/official-active）均有测试守护；去重权威切换到持久化 inventory，`_seenHashes` 移除。
- 删除所有权以 `legacy_anki_migrations` 为权威；Official 删除失败走 `pending_cleanup` + 启动自动重试；后台双写下线（`TURNA_OFFICIAL_ANKI_LEGACY_MIRROR` 默认 false）。
- `StorageInventoryService` 只读扫描 + `StorageDiagnosticsPage`（高级 → 存储与性能）落地。
- `CardRecognitionPipeline` 识别器 v1：版本化签名 → 持久化规则 → 确定性规则 → 单批 AI → 启发式回退，带置信度/证据/警告，用户确认后按签名持久化规则。
- Unit → Section Beta（`grouping=section-beta-v1`）：显式字段 > 标签 > Unit 前缀 > 安全分块，向导开关默认关。
- 卡片来源身份：schema v20 `source_kind/source_id/owner_id` 一次性回填（Plan 2+3 第二轮 R11 交付），读侧禁止恢复 `wordId` 前缀推断（结构测试锁定）。

## 与计划条目的遗留偏差

1. Phase 4 的 fixture 集与 macro accuracy 指标未交付（需人工标注样本集）；以单元级证据链替代。
2. Phase 3 的深度扫描后台 isolate 分批 + 取消/进度未做（当前一次性只读遍历够用）。
3. Phase 5 的 Section 预览树完整编辑交互（合并/拆分/重命名）归后续迭代。

## 现行事实入口

- 可维护性设计（due 单一写入口、Review All 来源模型、导入向导 Controller 化）：[`anki-maintainability-cleanup/`](./anki-maintainability-cleanup/README.md)
- 生产收口与真机门禁：[`official-anki-migration/34`](./official-anki-migration/34-official-anki-production-cutover-and-ohos-retirement-plan.md)
- 架构决策：[`decisions/`](./decisions/)（ADR 0036–0041）

后续债务不再在本页维护：跨系统新债务进 [`anki-maintainability-cleanup/README.md`](./anki-maintainability-cleanup/README.md)「后续债务」；专题债务进对应专题文档。
