# Due 状态与单一写入口

> 状态：已完成（2026-08-25）
> 历史阶段：原 Wave 1
> 相关文档：[总入口](README.md) · [验收凭据](05-verification-receipt.md)

## 结果

Official formal due 已从“多个生产调用方通过静态 facade 分字段写入”收敛为：先收集完整状态，再向 `OfficialFormalDueRepository` 原子提交一个不可变 snapshot。一次逻辑刷新只产生一次 generation 变化和一次通知。

```text
Official Scheduler + Course placement + Introduction store
                  ↓ collect
          OfficialFormalDueSnapshotBuilder
                  ↓ one commit / generation CAS
          OfficialFormalDueRepository
                  ↓ read-only snapshot
      Home / Hub / Profile / Review / Stats
```

## 原始问题

迁移期虽然已经存在 `OfficialFormalDueRepository`，生产代码仍通过 `OfficialAnkiHomeDue` 的静态 setter 分别写入 scheduler due、placement、suspended、buried、retired 等字段。Router、Ledger、Browser 和 Play Hub 都能成为写入口。

这造成四类风险：

- 消费者可能观察到只更新部分集合的中间状态；
- generation 表示字段写次数，而不是完整同步版本；
- 写所有权散落在 UI、Router 和业务 adapter 中；
- Widget `build()` 可能产生全局副作用和重复通知。

## 设计决策

### 完整写模型

`OfficialFormalDueUpdate` 表示一次完整提交，包含：

- 按来源组织的 formal due 状态；
- raw due；
- Turna due 聚合值；
- 尚未 introduction 的新卡数量；
- unavailable 标记和错误信息。

`OfficialFormalDueSnapshotBuilder` 显式收集 scheduler、placement、introduced、suspended、buried 和 retired 六类知识。调用方必须区分：

- 已知为空；
- 未获取或未知；
- mutation 中保留上一代值。

缺失输入不能自动解释成“已知空集合”，否则一次局部失败会错误清空已有状态。

### Repository 契约

Repository 对生产写入只提供两类能力：

- `commit(update, basedOnGeneration)`：提交完整 update；
- `mutateSource(..., expectedGeneration, transform)`：复制完整 snapshot，只替换一个来源后提交。

两者都使用 generation CAS。若 expected/base generation 已过期，则返回 stale，不能以 last-write-wins 覆盖较新的完整状态。

`markUnavailable` 只给最后一份完整 snapshot 增加不可用信息，不落地半份刷新结果。所有 map/set 在 snapshot 边界转为不可变集合，消费者不能通过外部引用原地修改 repository 状态。

### 刷新数据流

`OfficialAnkiProductionRouter` 只负责收集并返回数据，不再写全局 due 状态。`OfficialAnkiHomeDueSync` 执行：

1. 读取 base generation；
2. 收集 catalog、deck tree、queue、placement 和状态集合；
3. 构造完整 update；
4. 原子 commit；
5. 遇到 stale 时有界重试一次，仍冲突则放弃旧结果。

异常发生在 commit 之前，因此无需从半更新状态回滚。

### Mutation 与 introduction

bury、suspend 和 restore 在 Official engine 写成功后，使用 `mutateSource` 更新对应来源，并在 CAS 冲突时执行一次有界重试或来源级 refresh。调用方不再手工 spread 静态 map。

`CardIntroductionStore` 仍拥有 introduction ledger 的持久化。DAO 写成功后才发布带真实 sourceId/cardId 的 `CardIntroductionChanged`；repository 将事件折叠进一个新 snapshot。失败写入不允许乐观标记为 introduced/retired。

冷启动由 `CardIntroductionStore.hydrateFromLedger()` 从 ledger 重建 introduced 状态：store 本体保持 write-through（写库后进内存，自身从不再读），`setupLocator` 注册后立即回灌一次，`OfficialAnkiHomeDueSync` 与 `OfficialFormalReviewProductionLoader` 在各自入口幂等重入同一合并式回灌（并发去重、失败吞掉待下次重试、不发 `CardIntroductionChanged`）。回灌修复了重启后内存 introduced 集合为空导致正式复习全被过滤的问题。getter 不再动态读取 `CardIntroductionStore`，避免消费者在同一 snapshot 上得到不同结果。

## 已实现内容

- 新增完整写模型和 snapshot builder；
- repository 实现完整 commit、generation CAS、`mutateSource`、`markUnavailable` 与测试 reset；
- due sync 改为 collect → build → single commit；
- Router 改成 `collectFormalDueCardIds` / `collectHomeDueFromDeckTree` 等纯数据收集接口；
- Ledger 与 source-aware Browser 改为 CAS mutation；
- introduction/retire 在持久化后通过 source-scoped 事件进入 snapshot；
- 删除 getter 的 introduction 动态旁路；
- 删除 `official_anki_home_due.dart` 静态 facade；
- Play Hub 只在 selector/view model 中计算聚合 due，不在 `build()` 写 repository；
- Home、Hub、Profile、Review 和 Stats 读取同一个 repository snapshot。

## 失败与并发语义

- refresh 失败：保留上一份完整数据并标记 unavailable；
- refresh 与 mutation 竞争：旧 generation 提交被拒绝，不能覆盖新状态；
- introduction 与后台 refresh 竞争：CAS 失败的一方触发来源级 refresh；
- 外部集合修改：不可变集合直接拒绝；
- 多次 UI rebuild：不会因此触发 repository mutation；
- 任何路径都不把 due repository 变成 scheduler writer。

## 测试与守卫

测试覆盖：

- 一次 refresh 只有一次通知和一次 generation 变化；
- 六集合不存在可见的中间状态；
- stale commit 被拒绝；
- refresh 与 bury/suspend、introduction/retire 的竞争；
- refresh 失败保留旧 snapshot；
- snapshot 集合对外不可变；
- introduction 写成功后立即反映，失败时不反映；
- 多来源状态隔离及所有消费者同代读取。

架构守卫禁止：

- `OfficialAnkiHomeDue` facade 复活；
- view 层直接写 due；
- Router 恢复全局 setter；
- Widget `build()` 调用 repository mutation。

精确命令和最终通过结果见[验收凭据](05-verification-receipt.md)。

## 剩余债务

- 真机上的大 catalog 刷新耗时与通知成本仍需在 release candidate 阶段采样；
- profile context 仍由更上层的 composition root 提供，多 profile 不在本轮解决；
- due 状态模型不承担 Official engine 调度算法或数据库格式演进。
