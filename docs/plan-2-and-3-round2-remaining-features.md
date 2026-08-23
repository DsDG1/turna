# Plan 2+3 第二轮：剩余功能收尾（宝石经济、装扮与保护券、洞察聚合、AI 流式收尾、可观测性与无障碍审计）

> 状态：已实施（R1–R11 全部完成，2026-08-23）；本文是 Plan 2+3 第一轮（见
> [plan-2-and-3-settings-review-ai-performance.md](./plan-2-and-3-settings-review-ai-performance.md) §35）
> 已完成核心工程项之后，针对"功能尚未落地"清单的施工基线。
> 编写日期：2026-08-23
> 前置条件：Plan 2+3 第一轮全部核心工程项（已交付）；R11 另需 Plan 1 source 元数据列
> 总优先级：R1–R3（经济与装扮）为 P1；R4–R6（洞察与 AI 收尾）为 P1/P2；R7–R10（可观测性/审计/演练）为 P2；R11 为 P2（被 Plan 1 硬门控）
> 主要目标平台：Android 中低端设备；桌面端不得回退

---

## 0. 范围与非范围

### 0.1 本轮范围（代码层面可完成的未落地功能）

第一轮 §35.4 列出的全部代码级遗留项：

1. 宝石 earn 事件全面入账（账本成为事实源）；
2. 装扮槽位/目录/表面扩充（至少三类商品在主流程真实可见）；
3. 连续学习保护券（不改真实复习数据）；
4. 学习洞察页固定桶聚合 + 来源详情页；
5. AI hint/explain providers 接入流式合批；
6. AI 磁盘缓存去留决策落地；
7. 高频写路径写放大治理 + 缓存注册表 + 运行内存口径；
8. 性能 trace / 诊断事件埋点；
9. 无障碍 §4.3 矩阵逐表面审计与补齐；
10. 备份/恢复后迁移规范化演练；
11. （Plan 1 门控）复习统计 source identity 替换 wordId 前缀推断。

### 0.2 非范围（沿用第一轮结论，另行推进）

- 真机性能基线、灰度、发布 CI（需设备与发布流程，见主计划 §24/§34）；
- GUI/项目/反馈/发布/隐私正式 URL（产品决策缺失时保持 `ExternalLinkRegistry` 禁用态）；
- 三类装扮的美术素材产出（目录模型与表面契约先就绪，素材可分批填充）。

---

## 1. 现状基线（第一轮交付锚点）

| 能力 | 现状 | 文件 |
| --- | --- | --- |
| 宝石账本 | schema v19 `gem_ledger`/`cosmetic_entitlements`；事务购买、事件幂等、prefs 幂等迁移、余额投影 | `lib/data/gem_ledger_dao.dart` |
| 钱包 | prefs 快照 `LocalStateKeys.gems`；`earnGems/addGems` **未写账本** | `lib/application/gems_provider.dart` |
| 装扮目录 | 仅 3 个头像环（mist 免费 / reed 40 / lake 80）+ 12 头像；商店为极简列表 | `lib/domain/cosmetics/avatar_ring.dart`、`lib/views/settings/avatar_rings_page.dart` |
| 购买链路 | `CosmeticProvider.unlockAndEquip` 已走账本（失败退款补偿），prefs 解锁列表仍为镜像 | `lib/application/cosmetic_provider.dart` |
| 连续学习 | `StreakProvider.applyPracticeDay`/`checkStreakOnAppOpen`；Dashboard `StreakSummary.protectedByVoucher` 字段已预留未消费 | `lib/application/streak_provider.dart`、`review_dashboard_models.dart` |
| 洞察页 | `LearningInsightsPage` 承载筛选/KPI/曲线/来源，但内部仍经 `ReviewProgressProvider.snapshot()`（含 `allEvents()`） | `lib/views/review/learning_insights_page.dart`、`lib/application/review_progress_provider.dart` |
| 复习 DAO | 已有 `eventsBetween` / `dailyActivityBetween`（按本地日 GROUP BY）有界查询 | `lib/data/review_history_dao.dart` |
| AI 流式 | `StreamDeltaCoalescer` + `ChatAutoScrollCoordinator` 已落地，仅 tutor 链路接入 | `lib/application/ai/stream_delta_coalescer.dart` 等 |
| AI 缓存 | 内存 LRU 200；磁盘镜像 `enableDiskMirror` 生产从未调用，`ai_cache_disk_io.dart` 为同步文件 IO；stats 含 `diskWrites` 字段 | `lib/application/ai/engine/ai_cache.dart` |
| 错题/日志存储 | MistakeProvider 每次全量 JSON 重写（有条目上限）；StudyLog recent 队列(200)+90 日主 blob 合并 | `lib/application/mistake_provider.dart`、`lib/data/study_log_repository.dart` |
| 无障碍 | `AccessibilityCapabilities` 契约 + provider 实现已建；逐表面消费未审计 | `lib/application/accessibility_capabilities.dart` |
| 来源识别 | Dashboard/进度统计 legacy 卡用 `anki-<importId>-c…` 前缀推断；`LearningSourceRef` 模型已就绪 | `review_dashboard_repository.dart`、主计划 §14.4/§28.1 |

---

## 2. Phase R1：宝石经济收口——earn 全量入账，账本成为事实源

### 背景

第一轮偏差 §35.3-5：账本目前只承载购买/退款/迁移，earn（课程完成、里程碑、成就、复习会话）仍只写 prefs。
钱包（prefs）与账本投影（DB）长期并行必然漂移，装扮商店上线前必须先统一事实源。

### 任务

1. `GemsProvider` 增加账本依赖（`GemLedgerDao`，可空解析保持测试可用）：
   - `earnGems(event, {String? eventId})` → `ledger.record(kind: earn, amount, reason, eventId)`；
   - 有自然幂等键的调用点必须传 eventId：
     - 成就解锁 → `earn:achievement:<achievementId>`；
     - 连续里程碑 → `earn:streak7:<firstDayOfStreak>` 等（同一轮连续只发一次）；
     - 课程完成 → `earn:lesson:<lessonId>:<completionDate>`（同日同课重玩不重复入账）；
     - SRS/语法会话奖励 → `earn:srsSession:<localDay>:<sessionSeq>` 由调用方生成会话序号；
   - `addGems`/`spendGems`（无自然键的手动操作）用随机 transactionId 直接入账。
2. 冷启动对账：`ensureGemsInitialized` 时计算账本投影并与 prefs 比较：
   - 一致 → 正常；
   - prefs > 投影 → 以 prefs 为准补一条 `adjustment`（说明来源 `reconcile`），不扣减用户余额；
   - prefs < 投影 → 以账本为准回写 prefs，并记 `adjustment`；
   - 对账结果（差异额）进诊断摘要，不进日志正文。
3. 备份/恢复与 Fun Lab 快照恢复路径调用既有 `migrateFromPrefs`（幂等），恢复后立即对账。
4. `GemEvent` 每档奖励金额进常量表（供商店与账单页展示来源说明）。

### 出口条件

- 任一 earn 路径重放（同 eventId 重复调用）不重复入账（测试）。
- 人为篡改 prefs 余额后冷启动，账本投影与 prefs 收敛且差异以 `adjustment` 显式留痕（测试）。
- 全部 earn 调用点（课程完成协调器、成就服务、SRS/语法会话、Fun Lab 恢复）传幂等 eventId（代码审查清单）。

---

## 3. Phase R2：装扮目录扩充与表面契约（三类商品主流程可见）

### 背景

主计划 §4.9/§8.2/§8.3：用户"装扮没有效果"的根因是商品维度少 + 展示面窄。账本与原子购买已就绪，
本轮补齐目录模型、槽位、表面契约与首批商品，让已购装扮在主流程真实可见。

### 任务

1. **目录模型**（`lib/domain/cosmetics/`）：
   - `CosmeticSlot` 枚举：`avatarRing / profileTheme / cardBack / completionEffect / soundPack / mascotAccessory`（保护券为消耗品，走 R3 不占槽位）；
   - `CosmeticItem`：`id / slot / catalogVersion / price / surfaces: Set<CosmeticSurface> / accessibilityVariant`（§8.3 字段）；
   - 保留旧 `AvatarRing` 作为 `avatarRing` 槽的兼容视图（旧 id 不变，价格/解锁历史无缝）。
2. **首批商品**（素材可占位，模型先行）：
   - 头像环扩充（≥6 个，含 2 个新增付费档）；
   - 个人页主题 ≥2（背景/统计卡着色，不降低对比度）；
   - 完成效果 ≥2（课程/复习完成页徽章动效，reduceMotion 时替换静态徽章）。
3. **表面契约**：`CosmeticSurface` 枚举（settings、profile、lessonComplete、reviewComplete、playground 等）；
   - 目录注册期校验：**每个付费商品至少声明一个主流程表面**，违反即测试失败（§8.3"不允许可购买但无处使用"）；
   - 消费点接入：设置账户预览（已有）、个人页（主题+环）、完成页（效果+环）。
4. **装备状态**：`CosmeticProvider` 从"单 ring id"升级为 `Map<CosmeticSlot, String>`（prefs 键
   `cosmetics.equipped.<slot>`）；旧 `cosmeticsEquippedRing` 键迁移到新键（一次性、幂等）。
5. **商店页改造**：`avatar_rings_page.dart` → 分槽位 Tab 的装扮商店；价格/已购/装备态走账本
   `entitledItemIds()`；购买按钮防重（复用账本幂等）。
6. **无障碍变体**：动态商品提供静态版本（§8.1-3）；高价高动效商品在 reduceMotion 下的预览即静态态。

### 出口条件

- 断言测试：目录内每个付费 item 的 `surfaces` 非空且至少一个主流程表面（测试）。
- 购买→装备→在个人页/完成页/设置预览三处可见（widget 测试各一处）。
- 旧用户（已购 ring_reed + 已装备）升级后装备态与解锁态不丢（迁移测试）。
- reduceMotion 下完成效果渲染静态徽章（golden/widget 测试）。

---

## 4. Phase R3：连续学习保护券（不改真实复习数据）

### 背景

主计划 §8.5：保护券是消耗品，只保护**连续天数显示**，绝不生成 StudyLog、不改 reviewedAt/dueAt。
账本已可承载消耗品：授予/消耗都记 ledger 行，持有量 = 授予 − 消耗（投影，无独立计数器可漂移）。

### 任务

1. **持有量模型**：`gem_ledger` 中 `item_id = 'voucher_streak'` 的 `earn`（购买/赠送）与 `spend`（消耗）行；
   持有量与"本自然月已用/已获"均由账本按月聚合计算（月度上限由此天然可查）。
2. **购买**：商店上架（R2 目录追加消耗品条目，价格透明，月购上限 N=2 起步，常量可调）。
3. **消耗规则**（全部落在 `StreakProvider`，复习侧零改动）：
   - `checkStreakOnAppOpen` 判定 `StreakCheckResult.broken` 时：
     - 自动使用开启（默认关）且持有量>0 且缺口为恰好 1 天 → 自动消耗；
     - 否则弹现有 `StreakBrokenDialog` 的扩展版：显示"使用保护券保留 N 天连续（不修改学习记录）"按钮；
   - `applyProtectedDay(day)`：记录保护标记（prefs `streak.protectedDays`：日期集合，滚动窗口 90 天），
     保持 streak 计数与 `lastStreakDate` 前进；**不写 StudyLog、不触 SRS、不进 dailyStats**；
   - 同一天只能消耗一张（幂等键 `voucher:use:<day>`）。
4. **显示与诚实标注**：
   - Dashboard `StreakSummary.protectedByVoucher`：当前连续链包含保护日 → 显示"本次连续记录由保护券保留"角标（数据从 protectedDays 计算）；
   - 成就判定使用**真实连续**（链长 − 保护日），保护日不触发连续里程碑成就（默认不伪造，主计划 §8.5-6）；
   - 诊断摘要能区分真实/保护天数。
5. **设置开关**：学习或账户页新增"自动使用保护券"开关（默认关，主计划 §8.5-4）。

### 出口条件

- 消耗保护券前后：`StudyLogRepository` 日聚合、SRS due/reviewedAt、复习事件表**逐字段不变**（测试快照对比）。
- 连续里程碑成就（7/30/100）在含保护日的链上不触发（成就服务测试）。
- 无券/关自动使用/缺口≥2 天三种情况均不消耗（测试）。
- 月度上限：同月第三次购买被拒且 UI 说明（测试）。
- Dashboard 角标在含保护链时出现（widget 测试）。

---

## 5. Phase R4：学习洞察固定桶聚合与来源详情页

### 背景

主计划 §15.2/P3-3 出口：洞察页允许更重，但不能读取全历史事件实体。当前
`LearningInsightsPage` 经 `ReviewProgressProvider.snapshot()` 仍调用 `allEvents()` 并在 Dart 端过滤。

### 任务

1. **DAO 固定桶查询**（`ReviewHistoryDao`）：
   - `activityBuckets(from, to, granularity)`：day/week/month 三档，SQL `strftime` 分组，返回行数 ≤ 桶数（365 日按日 ≤366、按周 ≤53、全部按月受起始月约束）；
   - `retentionByIntervalBucket(from, to)`：`GROUP BY` prev_interval_days 的桶化（桶界复用 `MemoryCurveProvider.intervalBuckets`），替代全量事件在 Dart 分桶；
   - `sourceReviewCounts(from, to)`：按 cardId 前缀来源的一次 `GROUP BY`（R11 后改 source 列）。
2. **InsightsRepository**（`lib/application/review_dashboard/insights_repository.dart`）：
   - `InsightsQuery {range: d7|d30|d90|d365|all, source?, type?}`；
   - 快照 = 卡片状态聚合（provider 单遍，复用 Dashboard 分类器）+ 上述固定桶查询；
   - generation id 防晚到覆盖；缓存 key `insights:<range>:<source>:<revision>`（复用 `ReviewDataRevision`）。
3. **页面切换**：`LearningInsightsPage` 改读 InsightsRepository；`ReviewProgressProvider` 保留
   `listSources`/前缀工具供过渡，`snapshot()` 标注 `@Deprecated("insights path")`（R11 后删除）。
4. **热力图**：365 日按日用 `activityBuckets`（≤366 行）；格子色阶不只靠颜色（数值文本摘要 + 高对比变量）。
5. **来源详情页**（§15.3，新路由 `ReviewSourceDetailRoute`）：来源 due/new、今日完成、7/30 日趋势、
   "开始该来源复习"入口；Anki 来源显示导入名不暴露 importId；source 已删但历史在 → "已删除来源"态。
6. **空/回填/错误态**：沿用 §16.6 表格。

### 出口条件

- medium fixture（1 万卡/10 万事件）：洞察 d365 加载的 SQL 返回行 ≤ 桶数上限，全程不调用 `allEvents()`（查询计数测试）。
- 快速切 range：晚到结果不覆盖新 range（generation 测试）。
- 来源详情页对已删除来源显示正确态（widget 测试）。
- 热力图有文本语义摘要（无障碍测试纳入 R9 矩阵）。

---

## 6. Phase R5：AI hint/explain 流式收口（共享 streaming 基座）

### 背景

主计划 §18.4/§21/§27.1：tutor 链路已接入 coalescer + 局部重建 + dispose 契约；
`AiHintProvider`（课内提示）与卡片讲解（`ai_card_explain_sheet` 路径）仍是逐分片 notify。

### 任务

1. 抽共享基座 `AiStreamingSessionBase`（mixin 或抽象类，`lib/application/ai/`）：
   - generation id、cancelToken 生命周期、`StreamDeltaCoalescer` 创建/flush/cancel、
     `_disposed` 防护、`streamingRevision` 计数、统一 `dispose()` 契约（主计划 §21.4 七条）；
   - `AiTutorChatProvider` 重构为使用该基座（行为不变，既有 30 项测试作回归网）。
2. `AiHintProvider` 接入基座（提示链路同样 80ms 合批 + dispose 取消）。
3. 卡片讲解 sheet（`ai_card_explain_sheet` 及其 provider，含词典扩展）接入基座；
   上下文一律来自 `AiCardContextResolver`（第一轮已建），reveal 门控不回退。
4. 页面侧按 tutor 页模式拆 Selector：仅流式文本区监听 `streamingRevision`；
   `ai_hint_chat_page` 的滚动改用 `ChatAutoScrollCoordinator`。
5. 长会话上下文（§21.5）：发送侧最近 N 轮 + 摘要（tutor 先做，hint 单轮天然满足）。

### 出口条件

- hint/explain 链路 1000 分片通知次数受合批上限约束（复用 `streaming_pipeline_test` 断言模式）。
- 三个 provider（tutor/hint/explain）dispose 后零 notify/零 late 写入（统一基座测试）。
- tutor 既有测试全绿（重构回归）。
- 讲解请求体包含的卡片上下文经 resolver 净化且答案遵守 reveal 门控（既有测试延续）。

---

## 7. Phase R6：AI 磁盘缓存退场（决策落地）

### 背景

主计划 §18.8/DoD："要么异步+限字节+限 TTL 且实际接入，要么删除误导性能力"。
第一轮审计结论：生产从未 `enableDiskMirror`，UI 无磁盘暗示，`ai_cache_disk_io.dart` 同步 IO 是潜在风险。

### 决策

**执行退场（选项 a）**：删除误导性能力，保留内存 LRU 为唯一缓存层。

### 任务

1. 删除 `ai_cache_disk_io.dart`、`AiCache.enableDiskMirror`、`AiEngine.attachDiskCache`、
   `AiCacheStats.diskWrites` 字段及消费点（存储诊断页文案核对）。
2. 更新 `ai_cache_test` 磁盘用例为内存语义；存储与性能页"AI 缓存条目（内存键）"文案保持准确。
3. 在架构决策记录（ADR）中登记：若未来需要磁盘缓存，按主计划 §21.6 表（异步/isolate、字节上限、
   TTL、createdAt/lastAccess、schema/prompt version、可清理）全新实现，不复活同步实现。
4. `CacheDiagnosticsAdapter` 注册表（R7）中 AiCache 以内存口径注册，消除"条目数当 MB"的歧义。

### 出口条件

- 代码库无磁盘镜像路径（结构测试：禁用符号列表扫描，防回潮）。
- 缓存统计 UI 与实现一致（存储页测试更新）。

---

## 8. Phase R7：写放大治理、缓存注册表与运行内存口径

### 背景

主计划 §23.4/§23.5/DoD：高频存储路径需要写次数/字节基线与上限策略；运行内存、磁盘、缓存需不同口径。
第一轮已消除 AI 配置逐字符写；错题全量重写与 StudyLog 合并成本未度量。

### 任务

1. **写计数器**：轻量 `StorageWriteTelemetry`（ring buffer，仅记 key 名 + 次数 + 估算字节，**绝不记 value**）；
   挂接 `MistakeProvider` 持久化、`StudyLogRepository` 写/合并、`AiEngineConfigHolder` 提交、
   `CosmeticProvider` 装备写。高级页可查看 Top-N 写放大键。
2. **错题存储迁移评估**：先采基线（写次数/编码字节/耗时），若确认高频全量重写为热点，
   将错题列表迁至 drift 表（append + 上限清理），prefs 仅留指针；迁移幂等（复用快照/恢复路径验证）。
   基线不成立则记录结论并只保留遥测。
3. **缓存注册表**（主计划 §23.5 接口）：
   ```dart
   abstract interface class CacheDiagnosticsAdapter {
     String get owner;                    // 'ai.responseCache' 等
     Future<CacheFootprint> inspect();    // entries + estimatedBytes?（无可靠字节则 null，不伪造）
     Future<CacheClearResult> clearRegenerable();
   }
   ```
   注册：AiCache（内存 LRU）、Playground 修订缓存、Dashboard 快照缓存、Flutter imageCache（条目口径）。
   "释放缓存"按钮仅调用已注册 regenerable 清理；文案明确"数值随系统回收变化"。
4. **运行内存快照**：存储与性能页拆分"运行内存（瞬时）"卡：`ProcessInfo.currentRss`、
   Dart heap（可用 API 范围内）、采样时间戳；磁盘与内存不相加（§6.4 红线）。

### 出口条件

- 写遥测无 value/正文泄漏（脱敏测试：缓冲区序列化结果不含任何 value 样本）。
- 各注册缓存的 entries 与实现内部计数一致（测试）。
- 运行内存与磁盘占用分卡展示，无相加总量的 UI（widget 测试）。
- 错题迁移决策有数据支撑并留档（基线数字写入本文档实施记录）。

---

## 9. Phase R8：性能 trace 埋点

### 背景

主计划 §23.1：全局"卡"的归因需要统一指标口径。第一轮各路径已有代码级复现，但无聚合遥测。

### 任务

1. `PerformanceTrace`（`lib/application/diagnostics/performance_trace.dart`）：
   - 字段：feature、operation、durationMs、resultSize（行数/字节数）、cacheStatus（hit/miss/stale）、
     outcome（ok/error/cancelled）；**不含**路径、正文、prompt、Key、卡片内容（§23.1 脱敏红线）；
   - 环形缓冲上限 200，release 只保留慢操作（阈值表）与聚合计数。
2. 埋点接入（首批）：dashboard 加载、insights 加载（桶数与耗时）、Playground 索引构建（候选数）、
   AI ask（首分片耗时、通知次数、总时长——不含内容）、存储扫描、Anki 导入主路径。
3. 系统健康页"复制诊断摘要"纳入 trace 摘要（P50/P95 + 慢操作 Top-N，全部脱敏）。
4. 慢查询阈值（50ms 起步，主计划 §24.3）在 DAO 层附加 query id + 扫描/返回行数（不含参数值）。

### 出口条件

- trace 序列化样本经敏感信息扫描（无路径/Key/正文模式）。
- 每个埋点路径有"慢路径可复现"的测试或手工脚本说明。
- 摘要可在高级页复制（widget 测试）。

---

## 10. Phase R9：无障碍 §4.3 矩阵逐表面审计与补齐

### 背景

第一轮已建 `AccessibilityCapabilities` 契约；主计划 DoD 要求"每个保留的开关都有跨页面效果和测试"。

### 任务

1. **审计表**：以主计划 §4.3 六能力 × 表面（设置、Home、复习概览、洞察、AI、Playground、装扮商店、完成页）
   逐格标注：已实现 / 缺口 / 不适用（含理由）；审计表随本文档落地为实施记录。
2. **已知缺口优先修**：
   - 专注模式：复习概览/洞察隐藏非必要推荐区；AI 隐藏推荐 chips；Playground 隐藏装饰区（主计划矩阵行）；
   - 高对比：装扮商店可用/禁用不只靠透明度；洞察图表色阶加形状/文本差异；
   - 200% 字号：Dashboard Hero、洞察筛选行、商店价格行不截断（golden 三档字号）；
   - 安静反馈：完成效果/商店购买无强音效触觉（与 R2/R3 联动落地）。
3. **测试**：高对比 + reduceMotion + 200% 字号的 golden 基线（新页面）；图表文本摘要的 Semantics 断言；
   关键按钮 label/state 可读（Semantics 测试）。
4. 无法在本轮兑现的格子明确标注"不适用+理由"，不留"有状态无效果"的开关（主计划 P2-5 出口）。

### 出口条件

- 审计表每格有结论；缺口项全部修复或显式豁免。
- 新增 golden（浅/深 × 高对比 × 200%）通过；TalkBack 语义测试通过。
- reduceMotion 下完成效果静态化（与 R2 出口重叠，一并验收）。

---

## 11. Phase R10：备份/恢复后迁移规范化演练

### 背景

主计划 §9/§34：备份恢复后必须重新运行必要的规范化，且不重复增加余额或 entitlement。
各迁移本身幂等（第一轮已测），缺的是**端到端链路**演练。

### 任务

1. 集成测试：本地导出 → 清空环境（prefs + 安全存储 + DB）→ 导入 → 启动迁移链：
   - AI Key：安全存储仍可读或明确要求重输；prefs blob 无明文 Key；
   - 宝石：`migrateFromPrefs` 不重复入账（opening 余额仅一条），R1 对账收敛；
   - 装扮：entitlement 集合与装备态恢复，无重复 entitlement 行；
   - Fun Lab：autoAnswer 仍为关；
   - 设置键（新拆分的外观/声音/无障碍）效果等价。
2. 远程备份路径同套断言（复用 `BackupSnapshotService` 测试设施）。
3. Fun Lab 快照恢复（debug）路径跑同一断言子集。
4. 演练发现的偏差修复合入对应迁移，并把"恢复后规范化"步骤固化到导入代码路径（而非仅测试中调用）。

### 出口条件

- 三条恢复路径（本地/远程/快照）的幂等断言全绿；
- 恢复后账本投影 = 恢复余额（无双重 opening）；entitlement 无重复行；
- 演练结果记录进本文档实施记录。

---

## 12. Phase R11（Plan 1 门控）：source identity 替换 wordId 前缀推断

### 背景

主计划 §14.4/§16.2/§28.1 硬依赖：Plan 1 落地 `srs_states` 的 source 元数据列后，
复习统计与来源归属停止从 `anki-<importId>-c…` 字符串前缀猜测。`LearningSourceRef` 已就绪待消费。

### 任务（Plan 1 source 列可用后执行）

1. 写入侧：卡片入队/导入时写 `source_kind/source_id/owner_id`（Plan 1 范畴，此处只对齐读取契约）。
2. 读取侧：`ReviewDashboardRepository` 与 R4 `InsightsRepository` 的来源分类改为读列；
   旧行无列 → 回填一次（后台分批，可中断可重复）；仍缺列的极旧数据走前缀解析兜底并计数进诊断。
3. 删除来源 → `LearningSourceRef.active=false`（§16.2）：当前队列不再 due，历史保留"已删除来源"标签。
4. Official Anki 卡来源归属校验：混合 Legacy/Official fixture 中分类逐一正确（主计划 §26.1 行）。
5. 清退：删除 `ReviewProgressProvider.importIdFromWordId` 的最后一个生产调用点与 `snapshot()` 旧路径。

### 出口条件

- 无前缀解析的生产调用（结构测试）；
- 混合来源 fixture 全部归类正确；删除来源语义正确；
- Dashboard/Insights 数值与前缀时代抽样一致（迁移对账测试）。

---

## 13. 依赖与推荐顺序

```text
R1 宝石 earn 入账 ──→ R2 装扮目录/表面 ──→ R3 保护券（依赖 R1 账本投影 + R2 商店上架）
R4 洞察聚合（独立，可与 R1–R3 并行）
R5 AI 流式基座（独立；tutor 重构先行作回归网）
R6 磁盘缓存退场（小，可随 R5 一并提交）
R7 写放大/缓存注册表/内存口径（R6 完成后注册 AiCache 最终口径）
R8 trace 埋点（R4/R5 落地后埋点口径最稳；也可先建骨架）
R9 无障碍审计（R2/R3 动效落地后审计一次到位）
R10 备份演练（R1/R2/R3 全部入位后执行才有意义）
R11 source 替换（严格等 Plan 1）
```

硬依赖：R3→R1、R3→R2、R7→R6、R10→R1/R2/R3、R11→Plan 1。其余可并行。

## 14. 测试矩阵汇总

| 层级 | 重点 |
| --- | --- |
| Unit | 账本幂等/对账收敛；保护日不触复习数据；桶查询行数上限；写遥测脱敏；trace 脱敏 |
| Widget | 商店三表面可见；装备迁移；保护角标；洞察 range 切换；来源详情；200%/高对比 golden |
| Integration | R10 三条恢复路径幂等；R11 混合来源对账 |
| Golden | 新增页面 ×（浅/深 × 高对比 × 200% × reduceMotion 静态态） |
| Performance | 1000 分片通知上限（hint/explain）；洞察 d365 桶行数与查询数；写放大 before 数字 |

## 15. 风险登记

| 风险 | 缓解 | 回滚 |
| --- | --- | --- |
| 账本切换后余额漂移 | 对账只补不扣 + adjustment 留痕；灰度观察差异额 | prefs 恢复为事实源，账本降级为审计日志 |
| 保护券误改真实数据 | 消耗路径仅触 StreakProvider；快照对比测试锁死 StudyLog/SRS | 移除商店条目，保留券不消耗 |
| 洞察桶查询慢于预期 | DAO 仅聚合列 + 索引核对；慢查询遥测 | 页面回退 `snapshot()` 一个版本 |
| 错题表迁移丢数据 | 迁移前导出校验 + 幂等 + 演练路径覆盖 | 保留 prefs 读写双轨一版 |
| 磁盘缓存删除后需求回归 | ADR 记录新实现门槛 | 按 §21.6 全新异步实现（不复活旧码） |
| 无障碍豁免被滥用 | 豁免必须写理由并入库评审 | — |

## 16. Definition of Done

- [x] earn 事件全部入账且幂等；账本与钱包冷启动收敛并有 adjustment 留痕。
- [x] 目录中每个付费装扮至少一个主流程表面（测试强制），三类商品（环/主题/完成效果）真实可见。
- [x] 保护券消耗前后 StudyLog/SRS/复习事件逐字段不变；月度上限与自动使用开关生效。
- [x] 洞察 d365 不调用 `allEvents()`，返回行 ≤ 桶数上限；range 切换无晚到覆盖。
- [x] hint/explain 与 tutor 共享流式基座；三链路 dispose 零泄漏；合批上限一致。
- [x] AI 磁盘镜像代码删除且结构测试防回潮；缓存统计与实现一致。
- [x] 写遥测上线且无 value 泄漏；注册缓存条目一致；运行内存/磁盘分卡展示。
- [x] trace 埋点覆盖首批路径，摘要脱敏可复制。
- [x] §4.3 矩阵每格有结论；缺口修复或显式豁免；新增 a11y golden 通过。
- [x] 三条恢复路径幂等演练通过，恢复后账本/entitlement/凭据语义正确。
- [x] （Plan 1 后）来源识别无前缀解析生产调用，混合来源归类与删除来源语义正确。

## 17. 明确不接受的"伪完成"

- 只给商店加商品图，但表面契约测试缺失或商品仍不在主流程显示。
- 只给保护券加购买按钮，但消耗路径触碰 StudyLog/dueAt/复习事件任一字段。
- 只把 `allEvents()` 换成大窗口查询（未分组、行数仍随事件数增长）。
- 只把 hint provider 挂上 coalescer，但页面仍整页 Consumer 重建、dispose 仍不取消。
- 只删磁盘缓存入口但保留同步 IO 代码路径，或缓存统计仍显示磁盘字段。
- 只加内存数字却与磁盘占用相加展示，或把 entries 伪装成 MB。
- 账本切换后对账差异被静默抹平（必须 adjustment 留痕）。
- 无障碍审计表只填"已实现"而无可运行测试对应。

## 18. 实施记录

完成日期：2026-08-23。R1–R11 在同一轮完成；以下记录以可运行测试和生产调用点为验收锚点。

| Phase | 实施结果 | 主要验证 |
| --- | --- | --- |
| R1 | `GemLedgerDao` 成为余额事实源；课程、成就、SRS、语法奖励均带自然幂等键；手工变更走独立事务；冷启动按“只补不扣”原则收敛并写 adjustment 审计事实。 | `gems_provider_ledger_test`、`gem_ledger_test`、调用点结构审查。 |
| R2 | 建成六槽目录和 surface contract；头像环扩至 6 个，个人页主题与完成效果各 2 个；按槽装备并迁移旧 ring key；商店分槽展示。个人页、设置预览、课程/复习完成页均消费装备态，reduceMotion 使用静态徽章。 | `gamification_providers_test`、`account_edit_name_test`、`cosmetic_completion_badge_test`、`avatar_rings_page_test`。 |
| R3 | 保护券库存、购买、月限与消费均由账本投影；只修改 streak prefs/protectedDays，不触 StudyLog、SRS 或 review events；自动使用默认关，Dashboard 诚实显示“已保护”，成就读取真实连续。 | `streak_voucher_test`、`gem_ledger_test`、`review_dashboard_page_test`、商店月限 widget 测试。 |
| R4 | `ReviewHistoryDao` 增加固定 day/week/month、interval 和 source 聚合；`InsightsRepository` 提供 generation/cache/revision 契约；d365 固定 365 行；新增来源详情路由和已删除来源态；洞察生产路径不再读 `allEvents()`。 | `review_history_dao_test`（含 10 万事件 fixture）、`insights_repository_test`、`review_progress_provider_test`、洞察无障碍测试。 |
| R5 | tutor/hint/card-explain 统一到 `AiStreamingSessionBase`，80ms 合批、generation/cancel/dispose 契约一致；页面用局部 Selector 与共享自动滚动协调器；tutor 上下文有界。 | `ai_tutor_chat_streaming_test` 覆盖 1000 分片与三链路 dispose；既有 companion/provider 测试回归通过。 |
| R6 | 删除同步磁盘镜像文件、入口和 `diskWrites`；AI 缓存只保留内存 LRU；诊断口径同步。决策及未来重建门槛见 [ADR 0038](./decisions/0038-ai-cache-memory-only.md)。 | `ai_cache_test` 的禁用符号与文件结构测试、存储诊断 widget 测试。 |
| R7 | 新增仅记录 key/次数/估算字节/耗时的有界写遥测；挂接错题、StudyLog、AI 配置与装扮装备写；建立 AI/Playground/Dashboard/imageCache 注册表；RSS 与磁盘分卡。 | 脱敏与 adapter 一致性测试通过。错题 31 次连续写基线：31 次写、最大单次编码 13,384 bytes，未达到 64 KiB 迁移阈值，因此本轮保留有上限的 prefs 实现并持续遥测。 |
| R8 | 新增 200 条有界 `PerformanceTrace`，输出 P50/P95 与慢操作 Top-N；覆盖 Dashboard、Insights、Playground、AI、存储扫描、Anki 与 DAO 首批路径；健康页摘要可复制且不含正文/路径/Key。 | `performance_trace_test`、系统健康与存储诊断 widget 测试。 |
| R9 | 六能力 × 八表面的逐格结论见 [无障碍审计表](./accessibility-round2-audit.md)；补齐 focus/highContrast/200%/reduceMotion/语义摘要。 | 新增浅色、深色高对比 200% 洞察 golden 均通过；Dashboard、洞察、AI、Playground、商店和完成效果 widget/semantics 测试通过。 |
| R10 | `RestoreNormalizationService` 统一本地导入、远程恢复后启动及 Fun Lab 快照的规范化：AI 凭据安全迁移/脱敏、宝石对账、entitlement/装备迁移、autoAnswer 强制关闭；可重复执行。 | 本地、远程、Fun Lab 三条链路测试通过；重复运行后 opening/entitlement 各仅一条，余额与装备收敛，prefs 无 API Key 明文。 |
| R11 | schema v20 为 `srs_states`、`review_events` 与 Fun Lab 镜像增加 `source_kind/source_id/owner_id` 并一次性回填、建索引；所有新写入显式带 source；Dashboard/Insights 只读列，Official/Legacy/课程/语法及删除来源语义统一。 | v19→v20 混合迁移、opaque card id、Official/Legacy、已删除来源和结构守卫测试通过。 |

### R11 实施偏差说明

原任务允许“后台分批回填 + 极旧数据运行期前缀兜底”。实际实现选择 schema v20 升级事务中的一次性、幂等回填；因此升级完成后不存在运行期前缀解析或兜底计数。迁移 SQL 是生产代码中唯一允许读取旧 id 形态的位置，结构测试锁定 Dashboard、Insights 与 DAO 读取侧不得恢复 `wordId`/`cardId` 前缀推断。

### 最终验证

- `flutter pub run build_runner build`：成功，生成的 Drift/Freezed/JSON/路由代码与 schema v20 一致。
- `flutter analyze`：无编译错误；全仓剩余 133 条既有 warning/info，本轮改动未新增错误。
- `flutter test --exclude-tags golden`：1,580 passed / 2 failed；失败仅为基线已记录的 `wetland_palette_contract_test` 与 `dark_mode_text_contrast_test`，均不在本轮改动表面且本轮新增/修改测试全绿。
- `flutter test test/views/review/round2_accessibility_golden_test.dart`：2 passed；浅/深高对比 200% golden 均匹配。
- `git diff --check`：通过。
