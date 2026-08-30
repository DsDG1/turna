# ADR 0042 — Staging-first Official 导入（先暂存、确认后写正式 Collection）

- 状态：已接受
- 日期：2026-08-31
- 关联：[`docs/official-anki-migration/42-staging-first-official-import-lifecycle-plan.md`](../official-anki-migration/42-staging-first-official-import-lifecycle-plan.md)（施工计划与门禁）；[ADR 0036](./0036-official-anki-core-migration.md)、[ADR 0037](./0037-anki-course-review-unification.md)；取代 [doc 41](../official-anki-migration/41-official-anki-lifecycle-and-storage-remediation-plan.md) 的导入链路修复部分（S1/S2 导入分支/S6）

## 背景

Official-first 导入原设计为「先把 APKG 写进 live Collection，再预览，用户确认后投影发布」。2026-08-31 实测该链路以四个用户可见症状失败（取消后数据仍落盘、放弃并清理卡死且无补偿、needsMapping 死循环、映射确认按钮不可用），根因集中在：跨库事务的所有者是页面级 Controller、preview 与 publish 读取的 notetype 集合不对称、以及「取消」被迫等价于「回滚已提交事务」。doc 41 的修复方案（checkpoint restore + ambiguous commit 三态 + 无主卡普查）是在这个设计轴上继续打补丁，施工量与证明负担大，且其核心操作（独占 lease 下整文件替换 collection.anki2）与 UI 线程模型冲突。

## 决策

1. **导入先落 staging collection**：APKG 导入到一次性 profile 目录 `official_anki/staging/<attemptId>/`（独立 worker isolate），预览与映射确认全部在 staging 上执行；用户确认后才对 live Collection 执行唯一一次 `IMPORT_PACKAGE`。
2. **取消 = 删 staging 目录**：preview 前的任何取消/退出/强杀对 live Collection 零写入；staging 资产可整体删除，不需要 checkpoint、不需要 restore、不存在无主卡。
3. **live 写窗口唯一且 receipt 先行**：commit 窗口内只有一次 native 写，返回后 receipt（note ids / card descriptors / generation）同一 catalog 事务落库，再进入投影与发布；发布沿用 doc 41 §4.5 的 identity+authority 单事务。
4. **preview 与 publish 同一份 source scope**：`projectSource` 收必传 `notetypeIds` 参数；scope 外 notetype 不得触发 needsMapping；mapping 确认在 commit 成功时才晋升全局 `anki_projection_mappings`。
5. **导入路径不再做整份 `create_backup`**：rollback checkpoint 体系对新导入作废；存量 checkpoint/unfinished 数据按 doc 41 §7.4 一次性善后，善后完成后 restore 分支退役。
6. **直接切换，不保留双轨**：旧「先写 live 后预览」路径同波删除（README 维护规则：不保留被否决的并行实现作为默认路径）。

## 后果

- doc 41 S1（控制权）、S2 导入恢复分支、S6（checkpoint 体系）对新导入作废；S3/S4/S5/S7/S8（verified uninstall、source-scoped metadata、media GC、compact、存量 census）保留且与本决策正交。
- `AnkiImportController` 退化为 UI adapter；导入控制面唯一持久化载体是 attempt ledger。
- 代价（已接受）：大牌组 native import 执行两次（时间 ≈2×、临时磁盘一份）；staging 期多一个 isolate 的 native 内存；preview 计数与 commit 计数因去重可不同，UI 须如实区分。
- 测试门禁前置：四条症状必须先写成失败测试（doc 42 §10.1）再施工。
- 生产验收口径不变：doc 41 的删除/回收残留（S3–S7）与存量善后未完成前，仍为 NO-GO。
