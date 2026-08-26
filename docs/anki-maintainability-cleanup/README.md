# Anki 可维护性债务收口

> 状态：已完成（2026-08-25）
> 适用范围：Varnamala Plus / Turna Flutter 客户端
> 文档性质：已落地设计记录与维护导航

## 结论

当前 Anki 设计已经从迁移期的多入口、重复策略和巨型页面，收敛为边界较清晰的四个子系统：

1. Official formal due 通过一个 repository 原子提交完整 snapshot；
2. 正式复习将不可渲染卡表示为结构化、可见、可恢复的错误；
3. Review All 只按真实来源顺序执行，不再合成 `official-all` 身份；
4. 导入流程由 controller 和两个 flow 持有，Widget 只负责显示与导航。

这次收口解决的是可维护性债务，不代表 Official Anki 迁移整体完成，也不改变发布、设备或 Legacy 删除门禁。

## 阅读导航

| 主题 | 适合何时阅读 | 文档 |
| --- | --- | --- |
| Due 所有权、原子更新和并发 | 修改首页数量、bury/suspend、introduction 或 due sync | [Due 状态与单一写入口](01-due-state.md) |
| 卡片渲染失败和复习恢复 | 修改 formal-review loader、live queue 或错误 UI | [正式复习不可渲染错误](02-formal-review-errors.md) |
| 跨来源复习和来源身份 | 修改 Review All、来源发现或完成汇总 | [Review All 单一来源模型](03-review-all.md) |
| 导入状态机和页面分层 | 修改 Legacy/Official 导入、映射、清理或完成导航 | [导入向导 Controller 化](04-import-wizard.md) |
| 测试命令和最终结果 | 核对本轮是否完成、复用回归矩阵 | [验收凭据](05-verification-receipt.md) |

## 依赖关系

```text
Due 完整 snapshot
  ├─ 正式复习错误恢复与调度状态一致性
  └─ Review All 的真实来源发现和逐来源推进

导入向导 Controller
  └─ 独立复用既有 Legacy / Official 执行服务
```

Due 是正式复习和 Review All 的基础。导入向导与复习链路没有数据库实现依赖，但必须遵守相同的 owner、fail-closed 和真实来源身份约束。

## 全局不变量

### 所有权

- Official owner 的评分、undo、redo、bury 和 suspend 只写 Official engine。
- Legacy owner 的正式复习不能误写 Official scheduler。
- projection、due repository 和 UI 不是 scheduler writer。
- 不可渲染错误不能通过自动评分、bury 或 suspend 隐式消除。

### 身份

- `CanonicalCardKey.sourceId` 始终是真实 import/source id。
- Review All 可以聚合结果，但不能聚合卡片身份。
- sourceId、cardId 和 profileId 必须在 loader、presentation、ledger receipt 与 analytics 中保持一致。

### 状态和生命周期

- due 的 scheduler、placement、introduced、suspended、buried、retired 集合必须同代提交。
- refresh 失败保留上一份完整 snapshot；stale generation 不得覆盖较新结果。
- Widget `build()` 不写 repository、prefs、数据库或 engine。
- 异步 controller 使用 operation generation 丢弃过期回调。
- 页面 dispose 后不更新状态；取消和失败遵守临时资源清理及回滚语义。

## 本轮未改变的边界

- 不删除 Legacy schema、importer、renderer、scheduler 或恢复能力；W9 物理删除继续 HOLD。
- 不修改 Official Anki native/rslib 调度算法、数据库格式或 session RPC 协议。
- 不完整拆分 `OfficialAnkiCourseProjectionService`。
- 不引入多 profile 产品功能，也不更换 Provider/GetIt 全局 DI 方案。
- 不重做导入页视觉、品牌文案、mapping 算法或用户卡片数据。

## 与迁移和发布文档的关系

- 本组文档不替代 `docs/official-anki-migration/34-*`。
- 本轮没有合入文档 34 的 release candidate，因此 native、APK 和真机门禁未被本轮 host 验收覆盖。
- 如果这些改动将来进入 release candidate，必须重新执行文档 34 指定的设备与发布检查。
- W9 保持 HOLD：生产 `planFor` 链路没有 `allowLegacyOnly`，但 Legacy 的物理删除仍需独立观察期、备份恢复和真实用户数据门禁。

## 后续债务

以下事项不应顺手扩进本轮，应分别立项：

1. `OfficialAnkiSession` 客户端、worker 和 dispatcher 的 typed RPC 拆分；
2. `OfficialAnkiCourseProjectionService` 的 mapping DAO、job runner、reader 和 publisher 拆分；
3. `OfficialAnkiCompositionRoot` 生命周期、catalog close/reset 和 profile context 注入；
4. `profile-default-01` 集中化及真正的多 profile 支持；
5. `official_anki_internal_page.dart` 迁到 diagnostics/views，并删除架构守卫 allowlist；
6. W9 Legacy importer、scheduler 和 schema 的物理删除。

## 文档维护规则

- 跨系统约束只在本页维护；专题文档仅记录自身特有规则。
- 精确测试数量、命令和验收日期只在[验收凭据](05-verification-receipt.md)维护。
- 新问题放入对应专题的“剩余债务”；跨系统的新债务才进入本页。
- 原路径 `docs/anki-maintainability-debt-cleanup-plan.md` 只保留导航，不恢复完整正文。
