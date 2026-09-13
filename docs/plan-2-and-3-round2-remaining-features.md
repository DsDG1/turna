# Plan 2+3 第二轮：剩余功能收尾（宝石经济、装扮与保护券、洞察聚合、AI 流式收尾、可观测性与无障碍审计）

> 状态：**已实施（R1–R11 全部完成，2026-08-23）**
> 文档状态：兼容入口，不再维护正文。历史版本由 Git 保存（`git log --follow docs/plan-2-and-3-round2-remaining-features.md`）。

## 交付摘要（R1–R11）

| 阶段 | 交付 |
| --- | --- |
| R1 | `GemLedgerDao` 成为宝石余额事实源；earn 带自然幂等键；冷启动"只补不扣"收敛 + adjustment 审计。 |
| R2 | 六槽装扮目录与 surface contract；按槽装备并迁移旧 ring key；商店分槽展示。 |
| R3 | 保护券库存/购买/月限/消费由账本投影；只改 streak prefs，不触复习数据。 |
| R4 | `ReviewHistoryDao` 固定 day/week/month、interval、source 聚合；洞察生产路径不再读 `allEvents()`；新增来源详情路由。 |
| R5 | tutor/hint/card-explain 统一 `AiStreamingSessionBase`（80ms 合批、generation/cancel/dispose 契约一致）。 |
| R6 | AI 磁盘缓存退场，只留内存 LRU；决策见 [ADR 0038](./decisions/0038-ai-cache-memory-only.md)。 |
| R7 | 有界写遥测（key/次数/估算字节/耗时）+ AI/Playground/Dashboard/imageCache 缓存注册表；错题 31 次连续写未达 64 KiB 迁移阈值，保留有上限 prefs。 |
| R8 | 200 条有界 `PerformanceTrace`（P50/P95/慢操作 Top-N），健康页摘要可复制且脱敏。 |
| R9 | 无障碍六能力 × 八表面逐格审计：[accessibility-round2-audit.md](./accessibility-round2-audit.md)；补齐 focus/highContrast/200%/reduceMotion。 |
| R10 | `RestoreNormalizationService` 统一本地导入/远程恢复/Fun Lab 快照规范化（凭据迁移、宝石对账、装备迁移、autoAnswer 关闭），可重复执行。 |
| R11 | schema v20 source 身份列一次性回填；读侧禁止恢复 `wordId` 前缀推断（结构测试锁定）。 |

## 验证口径（2026-08-23）

`flutter analyze` 无 error；全量 `flutter test --exclude-tags golden` 1,580 passed / 2 failed（失败为基线已记录的 `wetland_palette_contract_test` 与 `dark_mode_text_contrast_test`，不在本轮表面）。精确命令与逐项测试名单见 Git 历史中的原文。

## 遗留尾项

已并入 [project-guide §17 下一轮](./project-guide.md#17-下一轮计划与致谢)（真机性能基线、宝石 UI 钱包快照到账本投影的完全切换）。
