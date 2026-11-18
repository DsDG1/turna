# ADR 0073 — 记忆卡引擎生命周期收口与共享来源所有权

> 状态：已接受 ｜ 日期：2026-11-18
>
> 衔接：[ADR 0043](./0043-anki-v2-single-source-of-truth.md)、[ADR 0044](./0044-anki-v2-revival.md)、[ADR 0057](./0057-card-adaptation-plan.md)、[ADR 0067](./0067-memory-card-returns-to-course-domain.md)

## 背景

`docs/status.md` 长期悬置两项工程尾债（开放决策①②）及 `ADR 0057` 的收尾清理项：

1. **引擎开库时序与退场配置清理**：`OfficialAnkiCompositionRoot.requireImporter()` 只拉起会话而未保证 `openProfile` 已落地，启动恢复、后台维护、卸载清理与 v2 课时正文派生各有各的开库写法或直接漏掉 `openProfile`，且 `collectionAlreadyOpen` / 瞬时 `schedulerBusy` / `collectionLocked` 缺少统一处理。此外，卸载大包时若引擎当时不可达，`AnkiDeckManager` 只能告警留尾，随后的延迟 `OfficialAnkiV2RetireService.runRetireJob` 并未补偿清理 `OfficialAnkiAdaptationStore` 命名空间。
2. **共享 Collection 上的来源所有权与分层抽样**：`OfficialAnkiImportLog` 虽已传回 `newNoteIds`、`updatedNoteIds`、`duplicateNoteIds` 与 `conflictingNoteIds`，但 `absorbReceipt` 全量吸收了 `associatedNoteIds`，导致未实际导入的冲突笔记也被写入 `anki_source_cards`；`OfficialAnkiV2RetireService.runRetireJob` 删除卡片时未过滤兄弟活跃来源仍在使用的共享卡；替换重导在大牌组上未等待旧源引擎删卡完成就开始新导入；同时 `AdaptationInputBuilder` 仅在截取后的前 3 条样本上统计媒体分布，无法反映整组 30 条样本的题型与长度多样性。

## 决策

### 1. 开放决策①：按需懒开边界 + 确定性 `ensureOfficialProfileOpen` + 延迟命名空间清理

1. **统一开库原语**：在 `lib/application/anki_official/official_anki_composition.dart` 提供 `ensureOfficialProfileOpen(engine, paths)`，调用 `engine.openProfile(paths)`，将 `OfficialAnkiErrorCode.collectionAlreadyOpen` 视作幂等成功，并对 `schedulerBusy` / `collectionLocked` 做有限次线性退避重试后再透传其余错误。
2. **全恢复与读/写挂点接入**：在 `OfficialAnkiStartupRecovery`、`AnkiDeckManager._resolveOfficialEngine`、`OfficialAnkiMaintenanceRunner`（涵盖 `mediaGc`、`metadataPrune`、`compactCollection`、`v2SourceDelete`、`v2ViewRebuild`）、`OfficialAnkiRepairExecutor`、`OfficialAnkiV2LessonContent._engineOrNull`、`OfficialAnkiV2ImportService.commit` 与 `OfficialAnkiV2UnownedCardReclaimer.purge` 统一经由 `ensureOfficialProfileOpen` 保证集合已打开。同时保持懒启动前提：仅当目录账本存在待办工作或用户主动进入记忆卡功能时才拉起引擎，无记忆卡用户冷启动零开销。
3. **延迟命名空间补偿清理**：`OfficialAnkiAdaptationStore.deleteSourceNamespace` 改为返回 `Future<bool>`，逐键聚合删除结果（任一键删除失败或抛出异常均记录告警并继续其余键，最终返回 `false`）。`AnkiDeckManager` 维持「先 `beginRetire` 使课程树即刻不可见，再清理适配命名空间」的顺序；`OfficialAnkiV2RetireService.runRetireJob` 步骤 ③ 在删除账本与映射决策时同步补偿调用 `deleteSourceNamespace(sourceId)`，确保引擎曾缺席时的延迟清理最终收敛。

### 2. 开放决策②：冲突隔离 + 共享卡保护 + 替换同步等待 + Dart 侧分层抽样

1. **冲突笔记隔离与摘要可观测**：`OfficialAnkiImportLog.importedOrSharedNoteIds` 仅包含 `newNoteIds`、`updatedNoteIds` 与 `duplicateNoteIds`，显式排除 `conflictingNoteIds`。`OfficialAnkiV2ImportService` 将该集合写入 `OfficialAnkiImportAttemptDao.absorbReceipt`，避免冲突笔记污染 `anki_source_cards` 所有权表；同时将 `updatedNoteCount` 与 `conflictingNoteCount` 经 `OfficialAnkiV2CommitResult` 与 `AnkiImportSummary` 传至导入完成页按非零条件展示。
2. **退场共享卡保护**：`OfficialAnkiV2RetireService.runRetireJob` 步骤 ② 在分批删除前调用 `OfficialAnkiSourceDao.retainingSharedCardIds(sourceId)`，跳过仍被活跃或进行中兄弟来源持有的卡片（保持分页偏移按源全量卡递增，过滤后为空的分批跳过 `deleteCards` RPC）。
3. **替换重导显式同步等待**：`AnkiDeckManager.uninstall`、`uninstallOfficialSource` 与 `_uninstallV2Source` 增加可选参数 `awaitEnginePass = false`。常规卸载大源仍后台分批删卡不阻塞界面；`AnkiImportController.replaceExisting` 传入 `awaitEnginePass: true`，确保旧来源在 Collection 与账本侧删除收敛后再开始同包替换导入。
4. **Dart 侧分层抽样与全样本媒体直方图**：保持 Rust C ABI 与 `recognitionSampleLimit`（30 条）不变，`AdaptationInputBuilder` 在全部 `schema.samples` 上计算 `mediaByField`，并按确定性优先级（① 音频 → ② 图片 → ③ Cloze 或多非空拓展字段 → ④ 短/中/长文本长度分桶 → ⑤ 原始顺序补齐）去重挑选预算样本，按原样本顺序稳定序列化输出。
5. **视图提示列与仓储接口收口**：配合 `CourseDatabase` 移除 `anki_course_tree_view.presentation_kind`，删除 `OfficialCardPresentationResolver` 的 `storedKindName`、`PresentationReason.unknownStoredKind` 与 `PresentationReason.storedKindDrift`；v2 视图与导入/退场链路切换为依赖 `IOfficialAnkiV2ViewStore` 与 `IAnkiUnificationStore`。

## 理由

- 懒启动加确定性 `ensureOfficialProfileOpen` 既解决「会话已创建但 Collection 未打开」导致的各类隐性失败，又保住无记忆卡用户的冷启动性能。
- 将冲突笔记排除在 `anki_source_cards` 之外、退场前查询 `retainingSharedCardIds` 并让替换重导显式等待引擎删卡完成，从数据所有权与并发时序两端消除跨来源误删风险。
- 在 Dart 侧直接对 Rust 返回的 30 条样本做分层挑选与全量媒体统计，无需改动原生 C ABI 即可为适配方案生成提供结构代表性样本。

## 边界

- 不在无待办任务或无记忆卡来源时提前拉起 native 引擎进程。
- 不修改 Rust 桥接层 C ABI，也不在 Dart 侧重写 Anki 上游导入去重/冲突判定逻辑。
- `AnkiDeckManager` 对常规大源卸载仍保留 `awaitEnginePass = false` 的后台分批策略，防止界面长时间阻塞；仅替换重导等需要前后状态串行化的调用方显式传 `true`。
