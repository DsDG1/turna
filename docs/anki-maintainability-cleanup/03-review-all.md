# Review All 单一来源模型

> 状态：已完成（2026-08-25）
> 历史阶段：原 Wave 3
> 相关文档：[总入口](README.md) · [正式复习错误](02-formal-review-errors.md) · [验收凭据](05-verification-receipt.md)

## 结果

Review All 现在只有一种生产模型：`FormalReviewSourceCoordinator` 冻结真实来源列表，并逐来源启动 owner-specific live session。原先把多个 Official 来源合并成 `official-all` 的 synthetic batch、plan 和空 source loader 分支已经删除。

```text
FormalReviewSourceCoordinator
  source A → owner-specific live session → record result
  source B → owner-specific live session → record result
  source C → load/render failure → explicit retry or continue
  completion → aggregate counts + failure summary
```

## 原始问题

迁移期同时存在两套跨来源策略：

- coordinator 按真实来源顺序逐个复习；
- production loader 在收到空 importId 时 union 所有来源，并生成 `sourceId = official-all` 的 batch。

第二条路径虽然没有稳定的产品消费者，却被测试固化成“合法 API”。它混淆了真实 owner，使 bury/suspend、quota、analytics 和 `CanonicalCardKey` 无法可靠回答一张卡属于哪个来源。

## 设计决策

### 唯一执行策略

`FormalReviewSourceCoordinator` 是 Review All 的唯一 owner：

1. 启动时发现并冻结 `List<FormalReviewSourceTarget>`；
2. 每次只把一个非空真实 sourceId 交给对应 loader；
3. 每个来源维护独立 live scheduler session；
4. 记录成功、无卡或失败结果后，再根据明确规则推进；
5. 完成页聚合统计，但不改变来源身份。

session 启动后，即使后台 due refresh 改变来源集合，也不修改本次冻结顺序。

### 来源发现与 fallback

来源发现顺序固定为：

1. Course catalog 中的非 builtin entry；
2. Due repository snapshot 中的真实 source ids；
3. 两者都无来源时显示 NoDue 或 Unavailable。

fallback 始终先构造真实 `FormalReviewSourceTarget`。任何路径都不能向 loader 传空 sourceId，也不能退回 synthetic aggregate loader。

### Loader 契约

`OfficialFormalReviewProductionLoader.load` 的 source/import id 必填且非空。一次调用只：

- resolve 一个真实 target；
- 读取该来源的 placement、introduced、suspended、buried 和 retired；
- 建立该来源自己的 allowed card ids 和 live session；
- 生成 sourceId 与 routed target 完全一致的 `CanonicalCardKey`。

loader 不 union 多来源集合，也不拥有 Review All 规划职责。

### 失败与完成汇总

`FormalReviewSourceFailure` 保存：

- 真实 source target；
- load、render 或 runtime failure kind；
- retryable；
- stable code。

`NoDue` 可自动推进。`Blocked` 必须等待用户重试或明确选择延后当前来源。失败来源不计入完成来源数，并在完成页列出及提供重试入口。

汇总可以统计完成来源数、记住、忘记和总数；这些统计不能创建 synthetic card identity。

## 已实现内容

- 删除 `OfficialReviewAllPlan`；
- 删除 `OfficialFormalReviewBatch.reviewAllPlan`；
- 删除 `_resolveAnyProductionTarget`、`_planReviewAll` 和 aggregate loader 分支；
- loader 对空 importId 抛出 `ArgumentError`；
- coordinator 按冻结的真实来源顺序逐个加载；
- catalog fallback 只生成真实 target；
- mixed Legacy + Official 继续按同一 coordinator 顺序执行；
- source failure 增加 kind、retryable 和 code；
- 完成页区分成功与失败来源并支持重试失败来源；
- 旧 aggregate 测试替换为逐来源真实身份测试。

## 不变量

- `lib/` 中不存在 `official-all` 产品字符串；
- `CanonicalCardKey.sourceId` 必须来自 routed target；
- Review All 聚合结果，不聚合 owner 或 card identity；
- 每个来源拥有独立 scheduler session 和 ledger 结果；
- 一个来源失败不污染其他来源；
- 失败来源不计入完成数量；
- session 内来源列表冻结，不随刷新动态插入或重排。

## 测试与守卫

测试覆盖：

- 两个 Official 来源逐个调用 loader；
- Legacy 与 Official 混合来源按冻结顺序执行；
- 每张 card key 保留真实 sourceId；
- 空 sourceId 被拒绝；
- catalog 缺失时从 due snapshot 建立真实来源；
- NoDue 自动推进，Blocked 等待明确操作；
- 一个来源失败不影响其他来源 ledger；
- 完成统计和失败来源列表准确；
- 生产代码不存在 synthetic source 或 Review All plan。

架构守卫禁止：

- `lib/` 重新出现 `official-all`；
- production loader 接受空 sourceId；
- 新的 aggregate Review All plan；
- 绕过 coordinator 启动跨来源正式复习。

精确命令和最终通过结果见[验收凭据](05-verification-receipt.md)。

## 剩余债务

- 真机上的大量来源切换耗时尚需 release candidate 样本；
- profile context 和来源 catalog 生命周期仍属于 composition-root 后续工作；
- 未来新增跨来源统计时，仍必须保持 card identity 为真实 sourceId。
