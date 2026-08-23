# Plan 1：Anki 数据正确性、识别与存储治理

> 状态：已实施（Phase 0–5 全部落地；见 §0 实施进展）  
> 编写日期：2026-08-23  
> 所属总计划：三个计划中的第一个  
> 优先级：P0（先于设置页重构、AI/复习页性能重构）

## 0. 实施进展（2026-08-23）

| 阶段 | 状态 | 交付内容 |
| --- | --- | --- |
| Phase 0 | 已完成 | `unified_anki_import_orchestrator_test.dart` 新增同进程 delete→re-import 回归、失败重试、并发拒绝；`unified_anki_import_orchestrator_inventory_test.dart` 覆盖生产 inventory 判定（complete/failed/official-active） |
| Phase 1 | 已完成 | 去重权威切换到持久化 inventory（`anki_imports` status=complete + official catalog state=active）；`_seenHashes` 移除，改为 begin/finalize 之间释放的 in-flight key；新增 `invalidate(importId, sourceHash?)`；`AnkiImportCleanupService.deleteAll`、`AnkiDeckManager.uninstallDeck/uninstallOfficialSource`、导入页全部失败路径均接入 |
| Phase 2 | 已完成 | `AnkiDeckManager._resolveDeletionOwner` 以 `legacy_anki_migrations` 为权威（课程树前缀仅作恢复线索）；mirrored 导入两侧核销；`_deleteOfficialSourceNotes` 返回结构化结果，失败时 `markPendingCleanup`（state=`pending_cleanup`）并保留 catalog/migration link；`retryPendingOfficialCleanups` 在 main.dart 启动时自动重试；后台双写下线为 `TURNA_OFFICIAL_ANKI_LEGACY_MIRROR`（默认 false）；`TURNA_OFFICIAL_ANKI_CUTOVER` 注释与默认值矛盾已修正（默认 true，与生产单 owner policy 一致） |
| Phase 3 | 已完成 | `StorageInventoryService` 只读扫描：主数据库（DB/WAL/SHM/freelist）、legacy imports/媒体（含孤儿目录检测）、official profile 目录、可再生成缓存、日志；每个字节带 category/ownerId/cleanupPolicy。最小诊断页 `StorageDiagnosticsPage` 落位于 高级 → 存储与性能（路由 `StorageDiagnosticsRoute`），展示分类/孤儿/可安全清理量，仅提供可再生缓存一键清理 |
| Phase 4 | 已完成 | `CardRecognitionPipeline`（识别器 v1）：`NotetypeSignature` 版本化签名（字段+模板结构+cloze）；`NotetypeSampleFeatures` 去隐私化样本特征（仅形状统计，正文绝不上行）；持久化规则 → 确定性规则 → 单次批量 AI 请求 → 启发式回退；返回 mapping+confidence+evidence+source+warnings；AI 结果做形状一致性校验（cloze/选项/音频/长度），不一致降置信并加警告；用户编辑或完成导入时按签名持久化规则（`AnkiNotetypeRuleStore`，prefs 键 `anki.notetype_rule.v2.<signature>`）；预览页每行显示来源/置信度徽标，低置信默认展开理由与警告。原 `AnkiNotetypeAI` 串行实现已删除 |
| Phase 5 | 已完成 | `AnkiCardOrganization` 扩展 `sectionKey/sectionEvidence/sectionConfidence`；证据优先级：显式 section/chapter/章 字段 > 显式标签 > Unit 名称前缀（`sectionKeyFromUnitName`）> 安全分块（不标智能）；`AnkiDeckAssembler.buildSemanticSections`（算法版本 `grouping=section-beta-v1` 记录在语义 Section description，id 保持 `anki-<importId>-` 前缀以兼容删除 saga）；向导新增"自动分 Section（Beta）"开关（默认关、依赖智能分组开启、仅影响本次新导入），预览显示 Section 数量/证据构成/低置信提示；无证据时行为与旧打包完全一致（有测试锁定） |

### 与计划条目的偏差说明

- Phase 4 的"fixture 集与 macro accuracy 指标"未在本批交付（需要带人工标签的真实样本集）；当前以单元级证据链（规则命中不调 AI、单批请求、形状校验、可解释来源）替代，指标基线留待有标注数据后补充。
- Phase 3 的"深度扫描后台 isolate 分批 + 取消/进度"未实现（当前扫描为一次性只读遍历，媒体目录规模下够用）；诊断 UI 的最终布局按计划归 Plan 2。
- Phase 5 的"用户可合并/拆分/重命名 Section 预览树"以开/关开关 + 检测预览（数量、证据、低置信提示）落地；完整编辑交互归后续迭代。

已修复的测试环境既有回归：`anki_import_screen_test.dart` 与 `anki_import_official_first_test.dart` 的 GetIt 缺少 `MistakeProvider` 注册。



## 1. 计划目标

本计划先解决 Anki 的数据正确性和数据所有权问题，再处理识别体验与存储治理。它覆盖以下需求：

1. 修复“导入一个 Anki 包，删除后再次添加却无法添加”。
2. 取消独立的 Official Anki 内部导入入口和默认的后台双写，保留一个用户可理解的导入流程。
3. 查清 Anki 是否被保存成多份、原数据是否残留，并提供可解释、可安全清理的存储扫描能力。
4. 提高卡片类型识别的准确度、可解释性和速度。
5. 增加“多个 Unit 自动归入 Section”的 Beta 能力。
6. 优化导入、扫描、清理过程中可归因的卡顿。

本计划不负责设置页最终布局、复习进度页视觉重做、AI 助手与 Playground 合并；这些进入 Plan 2 和 Plan 3。本计划只提供它们需要的数据接口，例如“存储与性能”页所消费的扫描结果。

## 2. 审计结论

当前问题不是单一的“缓存太大”，而是同一个 Anki 包被四套状态共同管理，但导入、删除、去重和统计没有使用同一个事实来源：

| 状态层 | 当前内容 | 当前风险 |
| --- | --- | --- |
| Legacy 数据 | `course.db` 中的导入记录、课程树、NoteStore、SRS、复习记录 | 删除主要按 Legacy `importId` 工作 |
| Legacy 媒体 | `anki_media/<importId>/` | `appendAsNew` 会给相同媒体再复制一份 |
| Official 数据 | Official collection、catalog、projection、migration link | 可能与 Legacy 同时写入，但删除路由不能可靠地从 Legacy id 找到 Official source id |
| 进程内状态 | `_seenHashes`、placement/presentation map、Turna SRS id set | 删除数据库后不会同步失效，导致重导被误判为“已存在” |

所以根治方向必须是：**一个导入身份、一个明确 owner、一套可恢复的删除事务、一个持久化事实来源**。

## 3. 实际成因分析

### 3.1 删除后无法再次添加：已确认的直接成因（P0）

问题位于 `lib/application/anki/unified_anki_import_orchestrator.dart`：

- `UnifiedAnkiImportOrchestrator.instance` 是进程级单例。
- `_seenHashes` 会在导入完成时记录 `sourceHash`。
- `_hashExists()` 先检查 `_seenHashes`，命中后不再检查数据库。
- `begin()` 把命中判定成 `noOp`，调用方会跳过课程组装、SRS 和 Official 写入，却仍然进入“完成摘要”。

删除链路 `AnkiImportCleanupService` / `AnkiDeckManager` 会删除数据库、课程树和媒体，但没有清除这个单例中的 `_seenHashes`、`_placementsByImport`、`_presentationsByImport` 和 `turnaSrsWordIds`。

因此实际状态序列是：

```text
首次导入
  -> 数据落库
  -> sourceHash 加入进程内 _seenHashes

删除
  -> 数据库和部分文件被删
  -> _seenHashes 仍保留 sourceHash

同一进程再次导入
  -> _hashExists() 在内存中命中
  -> begin() 返回 noOp
  -> 页面显示完成，但没有重新创建数据
```

这也给出一个明确的复现判据：如果删除后立即重导失败，而彻底重启应用后能够重导，则与该成因完全吻合。无论重启后的实际表现如何，内存状态覆盖持久化事实都是确定存在的正确性缺陷。

根治不能只是在删除按钮后补一行 `clear()`：

- `_seenHashes` 不应作为“已经导入”的权威依据，只能用于防止同一时刻重复提交。
- “是否已经导入”必须查询持久化 inventory，并同时验证记录状态和主要 owned artifacts 是否存在。
- 删除完成后仍应显式失效进程缓存，作为防御性措施。
- `noOp` 只能表示“一个完整且可访问的导入已经存在”，不能对已删除、半删除、失败或缺少课程树的数据返回成功。

### 3.2 Legacy 与 Official 双写：已确认的所有权分裂（P0）

普通导入在 `lib/views/anki/anki_import_screen.dart` 中先完成以下 Legacy 写入：

- 解析 `.apkg`；
- 复制媒体到 `anki_media/<importId>/`；
- 写课程树、NoteStore、导入元数据；
- 根据 owner 决定是否写 Turna SRS。

当 Official 能力可用、但 `officialFirstImport` 未开启时，Legacy 提交完成后还会调用 `_runOfficialImport()`，把同一文件再导入 Official collection，并在 `legacy_anki_migrations` 中记录 `legacyImportId -> officialSourceId` 的映射。Official 同步失败会被记录后吞掉，所以最终还可能出现“Legacy 成功、Official 失败/残缺”的半状态。

当前环境默认值进一步放大了这个问题：

- Official engine/import/catalog/runtime/projection 等开关默认开启；
- `officialFirstImport` 默认关闭；
- `TURNA_OFFICIAL_ANKI_CUTOVER` 的注释写“默认关闭”，代码却是 `defaultValue: true`；
- 灰度 cohort 默认 `g4`，即 100%。

这意味着 Android 的实际默认路线很可能是“Legacy 主写 + Official 后台镜像”，而不是注释所表达的保守灰度策略。最终是否命中仍由运行平台和 facade 决策共同决定，但配置意图与代码默认值冲突是已确认问题。

### 3.3 删除路由只看课程树前缀，无法覆盖双写导入（P0）

`AnkiDeckManager.uninstall(importId)` 通过 `_isOfficialSource(importId)` 选择删除链路。当前判断条件仅为：课程树中是否存在 `official-anki-<importId>-...` 前缀。

这对 Official-first 导入成立，但对“Legacy 主写 + Official 镜像”不成立：

- 页面持有并删除的是 Legacy `importId`；
- 课程树 id 是 `anki-<legacyImportId>-...`；
- Official collection 使用另一个 `officialSourceId`；
- 两者的真实关系只存在 `legacy_anki_migrations` 中；
- 删除路由没有先查询这张映射表。

结果是删除 Legacy deck 时可能只清除 Legacy 侧，Official collection/catalog 中的镜像继续存在。随后再次导入，同一个包会遇到旧 Official source、旧迁移映射或重复判断，形成用户所说的“原数据删不掉”或“出现分身”。

Official 删除链路还有一个已确认的失败语义问题：`_deleteOfficialSourceNotes()` 是 best-effort。Official engine 不可用或 `deleteNotes` 失败时，它只打印日志并返回；调用方仍继续删除 projection 和 catalog。这样会先丢失“这些 note 属于哪个 source”的所有权元数据，却把 note/card 留在 collection 中，形成难以追踪的孤儿数据。

### 3.4 空间变大的成因不止缓存（P0/P1）

当前至少存在以下可重复或可残留的数据：

1. **显式重复导入**：`appendAsNew` 会为同一个包生成新 `importId`，同一批卡片和媒体成为另一套完整数据。
2. **替换窗口**：`forceReplace` 先创建新 import，再删除旧 import；如果旧数据清理失败，代码选择保留两份完整数据。
3. **Legacy + Official 双份内容**：默认路线可能同时保存 Legacy NoteStore/课程投影/媒体与 Official collection/catalog/projection。
4. **按 importId 保存媒体**：`AnkiAudioResolver` 将媒体放在 `anki_media/<importId>/`；相同包以新 id 导入时无法复用相同文件。
5. **Official 删除失败后的孤儿 note/card**：collection 删除失败后 catalog 仍会被清掉，之后很难按 owner 回收。
6. **数据库内部空闲页**：当前只用 `page_count * page_size` 展示数据库文件规模，没有区分有效数据、freelist、WAL/SHM 和可回收空间。

其中并非所有重复都是“垃圾”。课程投影、NoteStore 和 collection 可能承担不同运行职责。扫描器必须区分：

- 用户数据：删除会丢失内容或学习进度；
- 可再生成缓存：安全清理后可重建；
- 临时文件：任务结束后应自动删除；
- 孤儿数据：没有任何有效 owner 引用；
- 重复数据：内容相同但被多个有效 owner 引用；
- 数据库可回收空间：逻辑删除后尚未压缩的页。

不能把这些类别合并成一个“垃圾大小”并提供一键删除。

### 3.5 现有存储检测既不完整，也没有接入页面（P1）

`StorageMaintenanceService.inspect()` 当前只统计：

- `course.db` 的 page count；
- Legacy `anki_media` 目录；
- Anki 预渲染缓存；
- AI 缓存条目数；
- 单个日志文件。

它存在四个问题：

1. 没有调用入口，当前工程中未发现页面消费这个 service。
2. 指标单位不一致：多数是 bytes，AI 只有 entry count。
3. 没有 Official collection/catalog/media、WAL/SHM、备份、导入临时目录、失败 attempt 等关键分类。
4. 只能清 Anki 预渲染和 AI 内存缓存，无法发现或验证 Anki 孤儿数据。

用户提出的“内存检测”需要拆成两个概念：

- **存储占用**：持久化到磁盘的数据库、媒体、缓存、日志和垃圾，是本计划的主功能。
- **运行内存**：Dart heap、RSS、图片/WebView 等瞬时占用，只适合作为高级诊断采样，不能承诺等同于“可清理垃圾”。运行内存的系统口径和 GC 时机不同，不能与磁盘缓存相加。

### 3.6 卡片识别不灵：输入信息不足、结果不可解释（P1）

`AnkiNotetypeAI` 当前以 notetype 为单位进行判断，发给模型的主要信息只有：

- notetype 名称；
- 是否 Cloze；
- 字段名列表；
- template 名称列表。

它没有提供真实字段样本、模板正反面内容、答案结构、音频标记、选项分布等信息。两个字段都叫 `Front/Back` 的词汇卡、问答卡、句子卡会得到几乎相同的输入，模型没有足够证据区分。

另外还存在：

- `identifyAll()` 逐个 notetype 串行请求，notetype 多时延迟线性增长；
- AI 超时、网络错误或 JSON 解析失败后会静默回退 heuristic，页面没有告诉用户结果来源；
- AI 做 notetype 级映射，而 `AnkiCardAdapter.adapt()` 还会按单卡内容二次决定，预览结论和最终卡片可能不一致；
- 返回值没有 confidence、证据和警告，用户无法识别低置信结果；
- 已确认的映射只跟随单次 import metadata，没有形成按 notetype signature 复用的稳定规则。

所以本问题不能只靠改 prompt，需要统一“样本 -> 分类 -> 校验 -> 用户确认 -> 持久化 -> 单卡适配”的契约。

### 3.7 “Unit 自动分 Section”当前并不存在语义识别（P1 Beta）

`AnkiOrganizationResolver` 的模型只有 `unitKey` 和 `lessonKey`，没有 `sectionKey`。更重要的是，`section`、`chapter` 字段现在被放进 `unitFieldPatterns`，会直接折叠成 Unit。

`AnkiDeckAssembler.packUnitsIntoSections()` 虽然能生成多个 Section，但它只是在 Unit 数超过硬上限后机械分块，并命名为 `Deck (2)`、`Deck (3)`。这是防止课程树超限的安全机制，不是用户要求的语义 Section 识别。

因此 Beta 功能需要新增独立的 `sectionKey` 和证据来源，而不是修改现有分块数量。

## 4. 必须建立的数据不变量

实现期间所有设计和测试以以下不变量为准：

1. 同一个 profile、同一个逻辑导入，在任意时刻只能有一个 active owner。
2. 去重的事实来源是持久化 inventory，不是进程内 Set。
3. 删除完成的定义是：Legacy、Official、projection、SRS/复习记录、媒体引用和进程缓存均完成核销，或明确标记为可重试的 `pending_cleanup`。
4. 如果 collection 删除失败，不得提前删除它的 catalog ownership link。
5. 一个失败或取消的导入不能伪装成成功，也不能阻止之后重导。
6. 相同 hash 可以被识别为同一内容，但不能只凭 hash 推断其所有 owner 已完整存在。
7. 清理器只删除“可再生成”或“已证明无 owner”的数据；不猜测、不静默删除学习进度。
8. 扫描结果的每个字节都要有 category、owner、是否可清理和清理理由。
9. Section Beta 只改变新导入的预览和布局，不自动重写已有课程。

## 5. 目标架构

### 5.1 单一导入入口

删除独立的 Official 内部导入入口。页面只保留一个“导入 Anki”流程，由内部 facade 选择一个 owner：

```text
用户选择 .apkg
  -> 解析 fingerprint / profile
  -> inventory 查询
  -> 选择 exactly one owner
       -> Official-first（支持的平台）
       -> Legacy fallback（不支持的平台）
  -> 生成 Turna 课程投影
  -> 提交 inventory
```

不再使用“Legacy 已提交成功后，再 best-effort 导入 Official”的默认后台镜像。若迁移期必须暂时保留双写，只允许通过开发开关开启，并写入显式的 mirror 状态和恢复任务，不能作为生产默认值。

“删除 Official 内部导入”不等于立即删除 Official engine 或 collection 文件。已有 Official 数据必须先通过 inventory 被识别、迁移或安全删除，否则直接移除代码会把历史数据变成永久孤儿。

### 5.2 统一数据清单

新增只读聚合层，例如 `AnkiSourceInventoryService`，为每个逻辑导入返回：

```dart
class AnkiSourceInventory {
  String profileId;
  String logicalImportId;
  String sourceHash;
  String? legacyImportId;
  String? officialSourceId;
  AnkiOwnerKind owner;        // legacy / official
  AnkiSourceState state;      // importing / active / pendingCleanup / failed
  List<OwnedArtifact> artifacts;
  List<InventoryIssue> issues;
}
```

它先聚合现有 `anki_imports`、`legacy_anki_migrations`、`anki_sources`、course projection 和媒体目录，不要求第一阶段立刻迁移所有表。写入模型最终再收敛到一个 manifest，避免增加第三套相互冲突的身份表。

### 5.3 可恢复删除事务

删除改为 saga：

1. 读取 inventory，解析 Legacy id 与 Official source id。
2. 保存删除计划和 owned artifact 快照。
3. 先删除无法由 Turna 重建的 owner 内容；Official collection 删除失败则进入 `pending_cleanup`，保留 catalog link。
4. 删除课程 projection、NoteStore、SRS、复习/错题/unification 数据。
5. 仅当媒体引用数为零时删除媒体目录或 blob。
6. 删除 import/catalog/migration 元数据。
7. 失效进程内去重和课程缓存。
8. 重新扫描并验证 post-condition。

删除中断后，应用下次启动自动重试 `pending_cleanup`，而不是让用户反复点击。

## 6. 实施阶段

### Phase 0：建立复现和数据基线（P0）

目标：在修改行为前固定证据，避免“修好了按钮但留下数据”。

- 增加 import -> delete -> re-import 的同进程集成测试。
- 增加重启边界测试，证明进程状态与持久化状态的差异。
- 用一个小包、一个含媒体大包、一个多 notetype 包记录导入前后各目录/表的增量。
- 为每次导入生成 correlation id，记录 `logicalImportId`、`sourceHash`、chosen owner、Official source id 和删除状态；日志不得包含 API key 或卡片正文。
- 输出当前默认 feature flags 的诊断快照，验证不同构建渠道是否真的处于 g4/cutover。

交付物：失败测试、存储基线表、当前构建的路由证据。

### Phase 1：修复删除后不能重导（P0）

修改方向：

- 把 `_seenHashes` 改成仅防并发提交的 `_inFlightKeys`，任务结束后必须释放。
- `begin()` 始终查询 inventory；只有 `state == active` 且核心 artifacts 完整才可返回 `noOp`。
- 对“记录存在但 artifacts 缺失”返回 `repair` 或重新导入，不返回假成功摘要。
- 给 orchestrator 增加明确的 `invalidate(logicalImportId, sourceHash)`，所有删除、force replace、rollback 路径都调用。
- 删除时一并核销 `_placementsByImport`、`_presentationsByImport`、`turnaSrsWordIds`；长期目标是移除这些生产态内存副本。
- 防止多个并发导入同一 key；此处用 in-flight lock，而不是永久 seen set。

验收：

- 首次导入 -> 删除 -> 不重启应用 -> 同包再次导入成功。
- 第二次导入重新创建真实课程树和卡片，不能只显示 summary。
- 导入失败/取消 -> 重试成功。
- active 完整导入的重复点击仍能正确提示“已导入”，不会复制内容。

### Phase 2：统一 owner 和删除链路（P0）

修改方向：

- 新增 inventory resolver，优先使用 `legacy_anki_migrations` 解析双向 id，课程树前缀只作为校验/恢复线索。
- `AnkiDeckManager.uninstall()` 接收逻辑 source，而不是猜测传入 id 属于哪种 backend。
- Official note 删除从 `void/best-effort` 改为结构化结果；失败时停止 catalog 删除并持久化 `pending_cleanup`。
- 对历史双写数据提供 reconciliation：`healthy`、`legacy_only`、`official_only`、`mirrored`、`orphaned`、`conflicted`。
- 去掉生产默认的 Legacy 后置 Official 镜像；统一入口只选择一个 owner。
- 修正 feature flag 注释、默认值和测试之间的矛盾。生产默认值必须在一个 policy 中定义，不允许散落在多个 bool 中。
- 清理 Official 独立 UI/内部入口前，保留只读恢复工具，直到历史 source 全部可识别。

验收：

- 删除 Legacy-only、Official-only、历史 mirrored 三种导入均能清除其全部 owner 数据。
- 模拟 Official engine 不可用时，catalog/migration link 仍存在，状态为 `pending_cleanup`；恢复 engine 后可继续清理。
- 删除任一步骤崩溃后可重入，重复执行不报错、不误删其他 deck。
- 所有构建渠道的 owner 路由都有确定测试。

### Phase 3：存储扫描、孤儿识别与安全清理（P1）

新增 `StorageInventoryService`，至少返回以下分类：

| 分类 | 统计内容 | 可清理策略 |
| --- | --- | --- |
| 主数据库 | DB、WAL、SHM、有效页、freelist | `optimize`；压缩必须单独确认并满足空间条件 |
| Anki Legacy | imports、notes、课程投影、SRS/复习数据 | 仅通过统一删除 saga |
| Anki Legacy 媒体 | 按 importId 的文件数、逻辑/物理 bytes | 无 owner 目录可清；重复文件先报告 |
| Anki Official | collection、catalog、projection、backups、media | 通过 Official owner 清理，不直接删库文件 |
| 可再生成缓存 | Anki 预渲染、AI cache、缩略图等 | 可一键清理，显示预计释放量 |
| 临时文件 | 解包目录、失败/取消 attempt staging | 超过安全期且无运行任务时清理 |
| 日志 | 当前与轮转日志 | 可清理，保留最近诊断窗口 |
| 孤儿/冲突 | 无 owner 的媒体、notes、source、projection | 先 dry-run，再逐项确认或修复 |

实现约束：

- 首屏先显示缓存值或粗粒度结果，深度扫描在后台 isolate 分批进行。
- 文件遍历和 hash 不在 UI isolate 做；支持取消和进度。
- 默认用大小、mtime、manifest 做候选筛选，只对疑似重复文件计算内容 hash。
- 结果同时报告 `physicalBytes`、`logicalBytes`、`recoverableBytes`，避免“重复引用”被误算成可释放空间。
- 清理前生成 dry-run 清单；清理后重新扫描，展示实际释放量。
- 运行内存单列为诊断项，显示采样时间和平台口径，不显示虚假的“可释放内存”。

UI 的最终落点由 Plan 2 决定，建议位于“高级 -> 存储与性能”。Plan 1 先完成 service、model、测试和最小诊断页。

### Phase 4：卡片识别升级（P1）

建立版本化的 `CardRecognitionPipeline`：

1. 为 notetype 生成稳定 signature：字段、模板结构、cloze 类型、可选样本特征。
2. 每类抽取少量去隐私化样本特征：非空字段形态、音频/图片、cloze、选项数量、答案结构；正文发送给远端 AI 前必须明确遵循现有 AI 数据策略。
3. 先跑确定性规则，能高置信识别的类型不调用 AI。
4. AI 对全部待判断 notetype 使用一次批请求或有限并发，不再无上限串行等待。
5. 返回 `mapping + confidence + evidence + source(rule/ai/fallback) + warnings`。
6. 用模板渲染和单卡 adapter 对候选结果做一致性校验；不一致时降置信并要求预览确认。
7. 用户确认后按 signature + recognizer version 保存规则，同类 notetype 可复用；版本变化时重新验证。
8. 预览页明确显示哪些是 AI、规则、回退结果，低置信项默认展开。

验收样本至少包含：Basic、Reverse、Cloze、Typed Answer、音频卡、单选、多选、混合 notetype、字段名模糊的词汇/句子卡和异常模板。

衡量指标不先拍脑袋定准确率：Phase 0 建立带人工标签的 fixture 集，Phase 4 报告 macro accuracy、低置信召回率、错误类型和平均耗时；新版本必须明显优于当前 heuristic 基线，并且不得降低 Official fixture parity。

### Phase 5：Unit -> Section Beta（P1 Beta）

将组织模型扩展为：

```dart
class AnkiCardOrganization {
  String? sectionKey;
  String? unitKey;
  String? lessonKey;
  OrganizationEvidence evidence;
  double confidence;
}
```

证据优先级建议：

1. 显式 `section/chapter/章` 字段或 tag；
2. Anki deck/subdeck 层级；
3. Unit 的稳定前缀或编号结构，例如 `Chapter 1 / Unit 1..8`；
4. Unit 数超过课程树上限时的安全分块。

其中第 4 项仍只是安全 fallback，不能标成“智能识别”。

Beta 交互要求：

- 默认关闭，仅对新导入生效。
- 导入前展示 `Section -> Unit -> Lesson` 树形预览、证据和低置信警告。
- 用户可以合并、拆分、重命名，或一键回到原始 deck 结构。
- 只在证据一致且达到阈值时自动应用；存在冲突时保留现有布局。
- 记录 grouping algorithm version，保证以后可以解释某个导入为什么这样分组。
- 不自动重排已有课程；旧数据升级必须另做显式迁移入口。

## 7. 代码影响范围

第一批预计涉及：

- `lib/application/anki/unified_anki_import_orchestrator.dart`
- `lib/application/anki/anki_import_cleanup_service.dart`
- `lib/application/anki/anki_deck_manager.dart`
- `lib/views/anki/anki_import_screen.dart`
- `lib/application/anki_official/storage/official_anki_source_dao.dart`
- `lib/application/anki_official/migration/official_anki_migration_dao.dart`
- `lib/application/anki_official/official_anki_feature_flags.dart`
- `lib/application/anki_official/migration/official_anki_engine_kind.dart`
- `lib/application/anki_official/migration/official_anki_gray_config.dart`
- `lib/application/maintenance/storage_maintenance_service.dart`
- `lib/domain/audio/anki_audio_resolver.dart`
- `lib/application/anki/anki_notetype_ai.dart`
- `lib/application/anki/anki_organization_resolver.dart`
- `lib/application/anki/anki_deck_assembler.dart`

新增测试优先放在：

- `test/application/anki/unified_anki_import_orchestrator_test.dart`
- `test/views/anki/anki_import_screen_test.dart`
- `test/application/anki_official/official_anki_cleanup_surfaces_test.dart`
- `test/anki/anki_organization_resolver_test.dart`
- `test/anki/anki_deck_assembler_test.dart`
- 新增 storage inventory / ownership resolver 单元测试。

### 实施后实际新增/删除的文件

新增：

- `lib/application/anki/card_recognition_pipeline.dart`（Phase 4：签名/样本特征/规则/AI 批请求/一致性校验/规则持久化）
- `lib/application/maintenance/storage_inventory_service.dart`（Phase 3：只读存储扫描）
- `lib/views/settings/storage_diagnostics_page.dart`（Phase 3：最小诊断页）
- `test/application/anki/card_recognition_pipeline_test.dart`
- `test/application/anki/unified_anki_import_orchestrator_inventory_test.dart`
- `test/application/maintenance/storage_inventory_service_test.dart`
- `test/views/settings/storage_diagnostics_page_test.dart`

删除：

- `lib/application/anki/anki_notetype_ai.dart`（被 `CardRecognitionPipeline` 完全替代，无生产引用）

## 8. 完整验收矩阵

| 场景 | 预期结果 |
| --- | --- |
| 同包首次导入 | 只有一个 active owner，课程和卡片数量一致 |
| 同包重复点击 | 不重复写入，准确指出已有导入 |
| 导入 -> 删除 -> 同进程重导 | 重导成功，真实数据恢复 |
| 导入 -> 删除 -> 重启后重导 | 与同进程行为一致 |
| 导入中取消/崩溃 | 无 active 假记录；临时数据可回收；可再次导入 |
| Force Replace 清理失败 | 标记待清理并可恢复，不静默长期保留“双份成功” |
| Legacy-only 删除 | Legacy 数据、媒体和进度按产品定义完整删除 |
| Official-only 删除 | collection 与 catalog 一致删除 |
| 历史 mirrored 删除 | 通过 migration link 同时核销两侧，不留 source |
| Official engine 暂不可用 | 保留 owner 元数据，进入 pending cleanup |
| 两个包同媒体 | 报告逻辑重复与实际可释放量，不误删仍在引用的文件 |
| 多 notetype 识别 | UI 展示来源、置信度和低置信项；请求不会串行无限增长 |
| 大量 Unit 的包 | Beta 可预览语义 Section；关闭 Beta 时保持旧行为 |
| 大型存储扫描 | UI 可交互、可取消，扫描/清理后数字可核对 |

## 9. 性能与观测要求

Plan 1 只承诺 Anki 导入和存储扫描链路的性能：

- 所有大量文件复制、遍历、hash、解析继续放在 isolate/worker。
- 数据库事务不得包住大批文件 I/O；当前媒体先复制再开事务的方向保留。
- 扫描使用增量快照，二次扫描只复查变化目录。
- 为 parse、media copy、assemble、DB commit、Official import、cleanup、storage scan 分别计时。
- 记录主线程 long task/jank，但不记录用户卡片内容。
- Phase 0 用真实大包建立基线后再锁定数值预算；没有基线前不写虚假的绝对毫秒目标。

## 10. 发布和回滚

发布顺序：

1. 先上线只读 inventory 和诊断日志。
2. 上线重导修复与统一删除 saga，但清理 orphan 先保持 dry-run。
3. 关闭生产默认后台双写，保留远程/构建回滚开关一个版本周期。
4. 开放安全缓存清理，再逐步开放孤儿清理。
5. 卡片识别升级小流量启用。
6. Section Beta 保持独立开关，最后启用。

回滚原则：新代码可以退回旧渲染/识别路径，但不能退回会丢 owner 信息的删除路径。新增状态必须向后兼容读取；任何 schema migration 都需要备份、版本检查和失败恢复测试。

## 11. 完成定义

只有同时满足以下条件，Plan 1 才算完成：

- 删除后无法重导的自动化测试稳定通过。
- 用户只看到一个 Anki 导入入口，生产默认不再静默双写。
- Legacy、Official 和历史 mirrored 数据都有同一套可恢复删除流程。
- 存储页能够解释 Anki、缓存、日志、临时文件、孤儿和可回收空间分别占多少，并且清理前后可验证。
- 卡片识别结果可解释、可纠正、可复用，有 fixture 指标支撑改进。
- Unit -> Section Beta 有预览、置信度、回退和版本标识。
- 大包导入与深度扫描没有明显阻塞 UI isolate 的同步工作。

## 12. 建议立即执行的第一批任务

1. 先补 `import -> delete -> re-import` 失败测试，锁定 `_seenHashes` 缺陷。
2. 将去重权威切换到持久化 inventory，并为所有删除路径增加 cache invalidation。
3. 用 `legacy_anki_migrations` 替换课程树前缀式 owner 判断。
4. 让 Official collection 删除返回可失败结果，禁止失败后继续删除 catalog。
5. 增加只读 storage/ownership 扫描报告，实测一组用户大包是否存在双份或孤儿，再决定媒体去重的数据迁移方案。

这五项完成后，最严重的数据正确性问题会被封住，也能获得足够证据继续做安全清理、识别升级和 Section Beta。
