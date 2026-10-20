# ADR 0042 — Staging-first Official 导入（先暂存、确认后写正式 Collection）

> 状态：已接受｜日期：2026-08-31
>
> 关联：[ADR 0037](./0037-anki-course-review-unification.md)；施工计划与门禁档（原 `docs/official-anki-migration/42-staging-first-official-import-lifecycle-plan.md`，已随文档精简删除）。
>
> 取代：原 doc 41（已随文档精简删除）的导入链路修复部分（S1 / S2 导入分支 / S6）。## 决策

1. **导入先落 staging collection**：APKG 导入到一次性 profile 目录 `official_anki/staging/<attemptId>/`（独立 worker isolate），预览与映射确认全部在 staging 上执行；用户确认后才对 live Collection 执行唯一一次 `IMPORT_PACKAGE`。
2. **取消 = 删 staging 目录**：preview 前的任何取消/退出/强杀对 live Collection 零写入；staging 资产可整体删除，不需要 checkpoint、不需要 restore、不存在无主卡。
3. **live 写窗口唯一且 receipt 先行**：commit 窗口内只有一次 native 写，返回后 receipt（note ids / card descriptors / generation）同一 catalog 事务落库，再进入投影与发布；发布沿用 identity+authority 单事务。
4. **preview 与 publish 同一份 source scope**：`projectSource` 收必传 `notetypeIds` 参数；scope 外 notetype 不得触发 needsMapping；mapping 确认在 commit 成功时才晋升全局 `anki_projection_mappings`。
5. **导入路径不再做整份 `create_backup`**：rollback checkpoint 体系对新导入作废；存量 checkpoint/unfinished 数据按原 doc 41（已随文档精简删除）§7.4 一次性善后，善后完成后 restore 分支退役。
6. **直接切换，不保留双轨**：旧「先写 live 后预览」路径同波删除（README 维护规则：不保留被否决的并行实现作为默认路径）。
## 理由

Official-first 导入原设计为「先把 APKG 写进 live Collection，再预览，用户确认后投影发布」。2026-08-31 实测该链路以四个用户可见症状失败——取消后数据仍落盘、放弃并清理卡死且无补偿、needsMapping 死循环、映射确认按钮不可用。
## 影响与边界

- 原方案的 S1（控制权）、S2 导入恢复分支、S6（checkpoint 体系）对新导入作废；S3/S4/S5/S7/S8（verified uninstall、source-scoped metadata、media GC、compact、存量 census）保留且与本决策正交。
- `AnkiImportController` 退化为 UI adapter；导入控制面唯一持久化载体是 attempt ledger。
