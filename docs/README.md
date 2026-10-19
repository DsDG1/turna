# 文档索引

> 按「找什么 → 去哪」组织。每篇只写它是干什么的，不复述内容。
>
> 三类文档的分工：**行为规范**在 [`../AGENTS.md`](../AGENTS.md)（改代码前必读）；**架构与设计**在 [`project-guide.md`](./project-guide.md)；**决策理由**在 [`decisions/`](./decisions/)（ADR，只提供理由，不覆盖上面两类）。

## 核心

| 文档 | 什么时候看 |
|---|---|
| [`project-guide.md`](./project-guide.md) | 想知道某个子系统怎么实现的、为什么这么设计 |
| [`../AGENTS.md`](../AGENTS.md) | 要改代码：落点、禁则、门禁、收据锚点 |
| [`../README.md`](../README.md) | 项目是什么、能做什么、怎么跑起来 |
| [`../test/BASELINE.md`](../test/BASELINE.md) | 查最近某次改动的测试基线与收据（更早见 [`../test/archive/BASELINE-pre-2026-09-20.md`](../test/archive/BASELINE-pre-2026-09-20.md)） |

## 构建与发布

| 文档 | 说明 |
|---|---|
| [`android-build-setup.md`](./android-build-setup.md) | Android 构建环境（JDK 17）、常见错误速查、arm64 发布约束 |
| [`ios-build-setup.md`](./ios-build-setup.md) | iOS 构建（静态链接 rslib xcframework + WKWebView 复习器） |
| [`firebase-app-distribution.md`](./firebase-app-distribution.md) | 内测分发的一次性 Console / Secrets 配置 |

## 课程内容

| 文档 | 说明 |
|---|---|
| [`content_inventory_current.md`](./content_inventory_current.md) | 土耳其语内容清单（**自动生成，勿手改**；用 `python tool/export_content_inventory.py` 重新生成） |
| [`authoring/`](./authoring/) | 写课程要遵守的格式契约 |
| [`authoring/course-layout.md`](./authoring/course-layout.md) | Section / Unit / Lesson 的层级与字段 |
| [`authoring/course-pack-format.md`](./authoring/course-pack-format.md) | 外部课程包 `.turnapack` 的 v1 / v2 格式 |
| [`authoring/lesson-type-templates.md`](./authoring/lesson-type-templates.md) | 7 种课时模板与 14 种题型的写法 |
| [`authoring/listening-show-format.md`](./authoring/listening-show-format.md) | 听力课的广播式音频结构与生成命令 |
| [`authoring/textbook-import.md`](./authoring/textbook-import.md) | 从教材批量导入课程 |
| [`authoring/teacher-guide.md`](./authoring/teacher-guide.md) | 给课程作者的上手指南与排错 |
| [`audio-recording-guidelines.md`](./audio-recording-guidelines.md) | 人工录音替换 TTS 的规范 |

## 架构决策（ADR）

`decisions/` 下的编号**不复用**；`0021` 和 `0043` 各有两篇，是历史编号复用，不是错号。

| 编号 | 主题 | 编号 | 主题 |
|---|---|---|---|
| [0001](./decisions/0001-tts-language-code.md) | TTS 语言码 | [0031](./decisions/0031-turna-rebrand.md) | 改名 Turna |
| [0002](./decisions/0002-content-replacement-progress-policy.md) | 内容替换进度口径 | [0032](./decisions/0032-about-page-tool-gui-content.md) | 关于页加入课程编辑器 |
| [0007](./decisions/0007-di-consolidation-and-refactors.md) | 依赖注入整合 | [0033](./decisions/0033-turna-wetland-crane-palette.md) | 「湿地鹤」色板 |
| [0010](./decisions/0010-audio-content-decoupling.md) | 音频与内容解耦 | [0034](./decisions/0034-ai-companion-hardening.md) | AI 伴学加固 |
| [0011](./decisions/0011-srs-persistence-scaling.md) | 复习状态持久化扩容 | [0035](./decisions/0035-reed-reanchor-and-scaffold-cooling.md) | 去绿化：主色重锚 |
| [0012](./decisions/0012-study-log-append-strategy.md) | 学习日志追加策略 | [0036](./decisions/0036-official-anki-core-migration.md) | 官方 Anki 内核作为唯一事实源 |
| [0013](./decisions/0013-srs-queue-base-class.md) | 复习队列基类 | [0037](./decisions/0037-anki-course-review-unification.md) | Anki 课程与复习大一统 |
| [0014](./decisions/0014-dictionary-and-weak-word-review.md) | 词典与弱词复习 | [0038](./decisions/0038-ai-cache-memory-only.md) | AI 缓存只存内存 |
| [0015](./decisions/0015-gameprovider-split.md) | GameProvider 拆分为门面 | [0039](./decisions/0039-webdav-secure-credential-migration.md) | WebDAV 凭据迁移到安全存储 |
| [0020](./decisions/0020-swahili-to-turkish-pivot.md) | 目标语从斯瓦希里语转向土耳其语 | [0040](./decisions/0040-system-health-state-machine.md) | 系统健康状态机 |
| [0021a](./decisions/0021-git-resource-library-architecture.md) | Git 资源库架构 | [0041](./decisions/0041-ohos-product-eol.md) | 鸿蒙产品级退役 |
| [0021b](./decisions/0021-tool-gui-functional-lesson-wizard-and-blueprint.md) | 编辑器功能课向导与蓝图 | [0042](./decisions/0042-staging-first-official-import.md) | Staging-first 官方导入 |
| [0026](./decisions/0026-local-resource-editor-enhancements.md) | 本地资源编辑器增强 | [0043a](./decisions/0043-anki-v2-single-source-of-truth.md) | Anki 底座 v2 单一事实源 |
| [0028](./decisions/0028-fsrs-continuous-memory-model.md) | FSRS 连续记忆模型 | [0043b](./decisions/0043-turnapack-external-courses.md) | 外部课程经 `.turnapack` 进入 |
| [0029](./decisions/0029-fsrs-relearn-and-local-weights.md) | FSRS 重学阶梯与本地权重 | [0044](./decisions/0044-anki-v2-revival.md) | Anki 底座 v2 复活 |
| [0030](./decisions/0030-anki-deep-adaptation-review-fixes.md) | Anki 深度适配的代码评审修复 | [0045](./decisions/0045-gui-course-delivery.md) | 编辑器把课程交给 App |
| | | [0046](./decisions/0046-ohos-anki-core-probe.md) | Anki 引擎层在 OpenHarmony 上可行 |
| | | [0047](./decisions/0047-ohos-companion-lite-build.md) | 鸿蒙伴生轻量版 |
| | | [0048](./decisions/0048-ohos-companion-audio-tts.md) | 鸿蒙伴生版音频与 TTS |
| | | [0049](./decisions/0049-ohos-turkish-tts-sherpa-feasibility.md) | 土耳其语 TTS 构建可行性 |
| | | [0050](./decisions/0050-ohos-official-anki.md) | 鸿蒙启用 Official Anki 全档 |

## Anki 官方内核迁移

| 文档 | 说明 |
|---|---|
| [`official-anki-migration/README.md`](./official-anki-migration/README.md) | 该目录的索引与阶段命名 |
| [`official-anki-migration/34-cutover-receipt.md`](./official-anki-migration/34-cutover-receipt.md) | **状态唯一真源**：进度、收据、证据台账、Held 表、活跃文档分工（41/42/44 的权威边界） |
| [`official-anki-migration/34-official-anki-production-cutover-and-ohos-retirement-plan.md`](./official-anki-migration/34-official-anki-production-cutover-and-ohos-retirement-plan.md) | 生产收口施工入口 |
| [`official-anki-migration/41-official-anki-lifecycle-and-storage-remediation-plan.md`](./official-anki-migration/41-official-anki-lifecycle-and-storage-remediation-plan.md) | 删除与物理回收、存量善后 |
| [`official-anki-migration/42-staging-first-official-import-lifecycle-plan.md`](./official-anki-migration/42-staging-first-official-import-lifecycle-plan.md) | 导入生命周期重设计 |
| [`official-anki-migration/44-ohos-review-entry-latency-and-parity-audit.md`](./official-anki-migration/44-ohos-review-entry-latency-and-parity-audit.md) | 鸿蒙复习入口时延与对齐审查 |
| [`official-anki-migration/archive/`](./official-anki-migration/archive/README.md) | 已闭环历史施工文档的**结论速查**（原文已删；**勿按其施工**） |

## 历史复盘

| 文档 | 说明 |
|---|---|
| [`ankiUpdate/v2-revival-story.md`](./ankiUpdate/v2-revival-story.md) | Anki 底座 v2 的失败与复活复盘（[ADR 0044](./decisions/0044-anki-v2-revival.md) 的叙事版） |
| [`ankiUpdate/v2-first-device-findings.md`](./ankiUpdate/v2-first-device-findings.md) | v2 首个真机之夜的逐项定性（F1–F6） |

## 设置

| 文档 | 说明 |
|---|---|
| [`advanced-settings-system-health.md`](./advanced-settings-system-health.md) | 高级设置四个入口的实现边界；系统健康状态机（[ADR 0040](./decisions/0040-system-health-state-machine.md)） |

## 其它位置

| 文档 | 说明 |
|---|---|
| [`../tool/gui/README.md`](../tool/gui/README.md) | 课程编辑器（独立 Python 工程）与其自己的文档索引 |
| [`../tool/gui/docs/README.md`](../tool/gui/docs/README.md) | 编辑器文档索引，有门禁强制每篇都在册 |
| [`../SECURITY.md`](../SECURITY.md) | 安全策略 |
| [`../CHANGELOG.md`](../CHANGELOG.md) | 版本变更记录 |
