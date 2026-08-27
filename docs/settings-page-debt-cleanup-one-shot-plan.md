# 设置页“屎山”一次性清理与完整优化计划

> 状态：**已实施（2026-08-24，一次性窗口完成全部 Phase）**——原头部“待执行”标记已过时，本页为修正后的兼容入口。
> 文档状态：不再维护正文。历史版本由 Git 保存（`git log --follow docs/settings-page-debt-cleanup-one-shot-plan.md`）。

## 结论

设置存储契约、备份清单与恢复校验、WebDAV 凭据安全迁移、业务操作协调器、设置导航与页面生命周期、组件/无障碍/性能收口、系统健康机制替换、全量迁移回归，已按原计划的依赖顺序一次性完成。交付 commits：9e316132（设置重构与 AI 凭据安全迁移）、98d9bf63（应用状态恢复、设置导航与系统健康监控）、86f74ba1（存储诊断页重构）。

## 现行事实入口

- 高级设置与系统健康的现行实现边界与验收证据：[advanced-settings-system-health.md](./advanced-settings-system-health.md)
- WebDAV 凭据迁移至平台安全存储（原 Phase 2）：[ADR 0039](./decisions/0039-webdav-secure-credential-migration.md)
- 系统健康状态机替换累计扣分模型（原 Phase 8）：[ADR 0040](./decisions/0040-system-health-state-machine.md)
