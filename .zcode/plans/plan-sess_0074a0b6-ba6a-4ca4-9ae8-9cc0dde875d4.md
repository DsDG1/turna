# 修复：导入自带复习历史（reps≥1）的卡应算 introduced

## 根因回顾

`CardIntroductionStore.seedOfficialProjection` 对所有卡硬编码 seed `unintroduced`（card_introduction_store.dart:188-207），从不看 reps；`ensureInitial` 是 `ON CONFLICT DO NOTHING`，全库没有按 reps 回填的写方。正式复习与 due 快照都是 `schedulerDue ∩ activePlacement ∩ introduced − …` 纯集合交集，`introduced` 只含 ledger 中 status='introduced' 的行——所以 reps>0 的导入卡永远不可见。规则层 `initialStatus(reps:)`（应返回 introduced）和 `CardIntroducedBy.importedHistory` 枚举已存在但零调用。

关键可行性事实（已核实）：原生搜索支持 `prop:reps>=1`（vendored anki parser.rs:472/497、sqlwriter.rs:405），现有 `searchCardsPage` 分页通道可直接用（home sync 已用它抓 suspended/buried）——**不需要动原生 ABI/FFI**。

## 改动清单

### 1. 发布时正确 seed（修新导入）

- **`card_introduction_store.dart` · `seedOfficialProjection`**：签名加 `Set<int> studiedCardIds = const {}`。每卡状态 = `eligibility.initialStatus(reps: studied ? 1 : 0)`；introduced 的行传 `introducedBy: CardIntroducedBy.importedHistory` + `introducedAt`（`ensureInitial` 已有这些参数）。种子为 introduced 的卡同时折入内存（`_introduced` 加 card token + recount，不发 change 事件——导入时 repository 还没跟踪该 source，后续入口 hydration 会兜底）。
- **`official_anki_projection_store.dart` · `replaceOfficialProjection`**：加 `Set<int> studiedCardIds = const {}` 透传给 seed。
- **`official_anki_projection_service.dart` · `_project`**：在调 `replaceOfficialProjection` 前（collection 已开），用共享 helper 分页搜索 `prop:reps>=1` 得 studiedCardIds，与 plan cardIds 取交集后传入。

### 2. 存量自愈回填（用户已选定：home sync 内采纳）

- **新文件 `lib/application/anki_official/introduction/imported_history_introducer.dart`**：
  - `fetchStudiedCardIds(searchPage)`：分页 `prop:reps>=1`（接收搜索回调，session/fake 皆可插，镜像 home sync 的 `fetchByQuery`）。
  - 采纳入口：按 source 交集后调 store。
- **`AnkiUnificationDao` 新方法 `adoptImportedHistory`**：单条条件 upsert（`customUpdate` 取 affected 数）：INSERT introduced(importedHistory) ON CONFLICT DO UPDATE SET status='introduced', introduced_by=COALESCE(introduced_by,'importedHistory'), introduced_at=COALESCE(introduced_at,?), last_studied_at=?, version=version+1 **WHERE status='unintroduced'**。缺行→插入 introduced；unintroduced→升级；**retired 与已 introduced 的行一律不动**。
- **`CardIntroductionStore.adoptImportedHistory({sourceId, cardIds})`**：先持久化（§7.4 纪律），仅对实际变更的卡折内存 + 发 `CardIntroductionChanged(introduced)`（repository 已有 pendingIntroductionSources/generation 机制处理刷新中竞争）。
- **`OfficialAnkiHomeDueSync._refreshOnce`**：collection 打开后、`collectFormalDueCardIds` 之前，跑一次全库 `prop:reps>=1` 分页查询，按 catalog 源（与各源卡集/投影索引）交集后逐源 adopt；adopt 自带 try/catch，回填失败不拖垮整个刷新。无 prefs 标记，失败自然重试、自我收敛。

### 3. 测试与文档

- **FakeOfficialAnkiEngine**：加 `studiedCardIds` 种子集；`searchCardsPage` 识别 `prop:reps>=1` 并从 needle 剥离（当前会把 prop: 当字面量）。
- **新测试**：
  - `card_introduction_store_seed_test.dart`（内存 CourseDatabase + 真实 DAO，GetIt 模式照抄 official_first_projection_anchor_test.dart）：studied→introduced(importedHistory)、其余 unintroduced；重 seed 不覆盖 course-introduced（DO NOTHING）。
  - adopt 测试：只升级 unintroduced/缺行；course-introduced 行 `introduced_by` 保留；retired 不动；仅对变更卡发事件。
  - 发布链路测试：plan + studiedCardIds 端到端落 ledger。
  - home sync adopt 测试：fake session → ledger 采纳 + snapshot 含新 introduced。
  - **回归主测试**（扩展 official_formal_review_loader_hydration_test.dart 模式）：ledger 行 introducedBy=importedHistory → loader 批次包含该卡（原 bug 的直接断言）。
  - eligibility 的 `initialStatus` 语义已有测试覆盖，无需改。
- **文档**：`docs/anki-maintainability-cleanup/01-due-state.md` 加小节：导入历史（reps≥1）计为 introduced；发布种子 + home sync 自愈采纳；introducedBy=importedHistory。

### 范围外

原生 ABI、`unintroducedNew` 计数、六集合交集读取路径的资格数学（不动）。

## 验证

`flutter analyze`；`flutter test` 跑新增/受影响文件（store/seed/adopt、projection publish、home sync、loader 回归）。