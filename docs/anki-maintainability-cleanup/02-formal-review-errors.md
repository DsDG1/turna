# 正式复习不可渲染错误

> 状态：已完成（2026-08-25）
> 历史阶段：原 Wave 2
> 相关文档：[总入口](README.md) · [Due 状态](01-due-state.md) · [验收凭据](05-verification-receipt.md)

## 结果

正式复习不再用 `catch (_) { continue; }` 静默丢弃不可渲染卡。loader 和 live queue 现在返回结构化失败；页面显示安全错误信息，并提供重试或在 Review All 中明确延后当前来源的操作。

最重要的产品语义是：Scheduler queue 非空但没有任何卡成功渲染时，结果是 `Blocked`，不是 `NoDue` 或“复习完成”。

## 原始问题

旧 loader/live queue 在单卡 render 失败后继续遍历。失败卡从页面 batch 中消失，却没有从 Official Scheduler queue 中移除，也没有被评分、bury 或 suspend。

当当前队列全部不可渲染时，页面会得到空 items，把错误误判成无卡，然后结束或推进下一来源。用户看不到失败原因，同一卡下次仍会再次出现。

## 设计决策

### 加载结果

loader 使用三个互斥结果：

- `OfficialFormalReviewReady`：至少一张当前 queue 中的卡成功渲染；batch 可携带非阻断 failures；
- `OfficialFormalReviewNoDue`：Scheduler queue 本身为空；
- `OfficialFormalReviewBlocked`：queue 非空但零张成功，包含真实 sourceId、失败列表和 scheduler card count。

engine/session 级错误继续映射或抛出 `OfficialAnkiException`，不能伪装成 `NoDue`。

### 结构化渲染失败

`OfficialCardRenderFailure` 保存维护和恢复所需的最小信息：

- 真实 sourceId 和 cardId；
- 稳定 code；
- question、answer、load 或 rebuild 阶段；
- recoverable 标记；
- queue epoch/render generation；
- 仅供 debug 的受控详情。

未知异常映射为稳定的内部错误 code。审计记录不保存卡片正文、HTML、typed answer 或媒体路径。

### Live queue 重建

`OfficialFormalReviewLiveQueue.rebuildFromLiveQueue` 返回 sealed result，至少区分 rebuilt、blocked on current card、stale 和 failed。

当前卡不可渲染时：

- 保留上一份可显示的 UI snapshot；
- 通过 `currentBlockedFailure` 锁定评分；
- 不清空 items 后宣告完成；
- `retryCurrentCard` 在同一 scheduler session、同一 card 和当前 generation 上重试。

加载级重试会先释放旧 session，防止同时存在两个 scheduler session；会话内重试不重复评分。

### 页面交互

共享复习页提供两类错误面：

- 来源加载被阻断：显示“此卡暂时无法显示”，允许重试当前来源；
- 会话中当前卡被阻断：禁用评分区，只允许重试当前卡。

Review All 可由用户明确选择“稍后处理此来源并继续”，但该来源必须进入完成页的失败列表。单来源复习不能静默结束，也不提供会暗中修改 Scheduler 的“跳过卡片”操作。

release 只显示安全文案；debug 可以显示 cardId、sourceId 和稳定 code。

## 已实现内容

- 新增 formal-review 结构化结果和 `OfficialCardRenderFailure`；
- loader 返回 Ready、NoDue 或 Blocked，且 Blocked 释放已创建 session；
- 部分渲染成功时，batch 保留非阻断 failures；
- live queue rebuild 对当前卡返回 blocked，并保留旧 items；
- `retryCurrentCard` 在原 session 中重试同一卡；
- 页面增加来源级和当前卡级错误面；
- Review All 完成页展示失败来源并提供重试入口；
- `OfficialFormalReviewRenderAudit` 以有界记录保存身份、code、stage 和 recoverable；
- 裸 catch/continue 不再承担错误处理。

## 不变量和失败语义

- 只有 queue 真正为空才能返回 `NoDue`；
- render failure 不是完成、评分失败或无 due；
- 失败不会调用 answer、bury 或 suspend；
- current card 失败时不能移动 controller 指针后继续评分；
- batch 只包含成功渲染且仍属于当前 queue 的卡；
- retry 不创建重复 session、不改变 card identity；
- 一个来源失败不能污染另一来源的 session 或 ledger；
- telemetry 不记录用户卡片内容。

## 测试与验收

测试覆盖：

- queue 非空且全部 render 失败返回 Blocked；
- 部分失败返回 Ready 并携带 failures；
- retry 后能够进入同一来源或恢复当前卡；
- live rebuild 新出现的不可渲染 current 不被吞掉；
- blocked 时评分按钮不可用；
- retry 不重复评分或创建第二个活动 session；
- failure 不触发 answer、bury、suspend；
- failure audit 不包含卡片内容；
- 来源失败在 Review All 完成页可见。

精确命令和最终通过结果见[验收凭据](05-verification-receipt.md)。

## 剩余债务

- `OfficialAnkiSession` RPC 仍可进一步改为端到端 typed error；
- 大样本 render failure retry 延迟需在真机环境采样；
- 新增错误 code 时必须保持稳定、安全且不携带卡片内容。
