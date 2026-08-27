# Plan 2 + Plan 3：设置与产品体验重构、复习与 AI/Playground 性能治理

> 状态：**第一轮核心工程项已实施（2026-08-23）；代码级尾项已由第二轮 R1–R11 交付完毕（2026-08-23）**
> 文档状态：兼容入口，不再维护正文。历史版本由 Git 保存（`git log --follow docs/plan-2-and-3-settings-review-ai-performance.md`）。

## 结论

第一轮完成：设置页重构与实验室退场、高级页信息架构、宝石/装扮体系基座、复习进度页、AI 助手链路、Playground 融合、内容创作退场与全局性能治理的核心工程项。已确认的产品决策（§0）仍在约束后续演进：趣味实验室对普通用户隐藏、高级页为正式一级页面、危险操作必须解释影响范围并确认。

第二轮（R1–R11）收掉了本计划 §35.4 列出的全部代码级尾项，见
[plan-2-and-3-round2-remaining-features.md](./plan-2-and-3-round2-remaining-features.md)。

## 现行事实入口

- 高级设置与系统健康的实现边界与验收证据：[advanced-settings-system-health.md](./advanced-settings-system-health.md)
- WebDAV 凭据安全迁移：[ADR 0039](./decisions/0039-webdav-secure-credential-migration.md)
- 系统健康状态机替换累计扣分模型：[ADR 0040](./decisions/0040-system-health-state-machine.md)
- AI 缓存只留内存 LRU：[ADR 0038](./decisions/0038-ai-cache-memory-only.md)
- 无障碍矩阵审计结论：[accessibility-round2-audit.md](./accessibility-round2-audit.md)
- AI 流式会话基座：`lib/application/ai/ai_streaming_session_base.dart`（tutor/hint/card-explain 共用 80ms 合批）

## 仍开放的尾项

- 真机性能基线（P3-0/P3-9：Android 中低端 + profile 构建采 §24 预算 before 数据）；
- 宝石 UI 钱包快照（`LocalStateKeys.gems`）到账本投影的完全切换。

以上已并入 [project-guide §17 下一轮](./project-guide.md#17-下一轮计划与致谢)。
