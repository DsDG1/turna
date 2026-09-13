# Turna 成就系统整体焕新实施计划

> 状态：**已实施（2026-08-22，P0→P6 一次性完成）**
> 文档状态：兼容入口，不再维护正文。历史版本由 Git 保存（`git log --follow docs/achievement-system-revamp-plan.md`）。

## 结论

把分散的“可见成就、隐藏 XP/连续学习里程碑、宝石奖励、个人页统计”统一成一套可信、可迁移、可扩展的成就系统：七个系列唯一目录、纯函数评估器、指标投影器（持久化 `achievements.metric_projection.v1`）、v2 版本化状态仓库与 v1→v2 一次性迁移、唯一写入者 `AchievementService`（评估→持久化→发奖→两阶段反馈）、个人页成就主页与完成页反馈横幅队列。

> 硬约束（长期有效）：**课程成就最终目标保持 500 课，完美课程最终目标保持 100 课，不得下调或删除。**

## 现行事实入口

- 领域/应用/UI 落地文件清单与逐项偏差记录（原 §15）：Git 历史中的原文。
- 宝石奖励入账：`GemLedgerDao` 为事实源（Plan 2+3 第二轮 R1，见 [plan-2-and-3-round2-remaining-features.md](./plan-2-and-3-round2-remaining-features.md)）。
- 数据导入导出含成就状态与投影。

## 验证口径（2026-08-22）

成就相关领域/应用/集成/组件测试 70 项全部通过；`flutter analyze` 零 error；全量仅存失败为与本轮无关的存量 golden 像素差与 Anki 导入界面 GetIt 注册问题。
