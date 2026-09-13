# Anki 课程与复习大一统合同（原施工计划，兼容入口）

> 状态：**P0–P10 已落地**（合同、ACK、一卡一 presentation、introduction/queue、StudySessionController 等，2026-08-21 起；后续演进见下方现行事实入口）
> 文档状态：兼容入口，不再维护正文。原《Anki 课程与复习大一统实施计划》（2026-08-20，2169 行）正文由 Git 保存：`git log --follow --'# Anki 课程与复习大一统实施计划.md'`（在 docs/ 下）。
> 决策记录：[ADR 0037](./decisions/0037-anki-course-review-unification.md)

## 核心目标（长期有效）

以课程为产品主线，让同一张 Anki 卡在课程与复习中拥有唯一身份、唯一题型、唯一学习状态和唯一调度写入者。Official collection/scheduler 是官方卡排期唯一事实；Turna FSRS 只服务 Turna-owned / Legacy 卡；禁止双写；新代码不得用 id 前缀推断 backend。

## 现行事实入口

- 子系统设计（due 单一写入口、正式复习不可渲染错误、Review All 来源模型、导入向导 Controller 化）：[`anki-maintainability-cleanup/`](./anki-maintainability-cleanup/README.md)
- 官方卡题型识别、语言课渲染与翻面动画：[`official-anki-migration/30`](./official-anki-migration/30-course-like-card-experience-plan.md)
- 生产收口、W 分波与真机门禁（唯一活跃施工入口）：[`official-anki-migration/34`](./official-anki-migration/34-official-anki-production-cutover-and-ohos-retirement-plan.md)
- Legacy 复刻层清理（L0–L3 已施工）：[`official-anki-migration/35`](./official-anki-migration/35-duplicate-legacy-layer-cleanup-plan.md)
