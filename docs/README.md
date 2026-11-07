# 文档索引

> 按「找什么 → 去哪」组织。每篇只写它是干什么的，不复述内容。
>
> **四类文档，各管一件事，不得混写：**

| 类 | 在哪 | 回答什么 |
|---|---|---|
| 行为规范 | [`../AGENTS.md`](../AGENTS.md) | 改代码前必读的落点、禁则、门禁 |
| 当前状态 | [`status.md`](./status.md) | 现在是什么样：迁移口径、平台档位、Held 项 |
| 架构叙述 | [`project-guide.md`](./project-guide.md) | 子系统怎么设计、为什么这么设计 |
| 决策理由 | [`decisions/`](./decisions/) | 某项决策为什么这么定（只给理由） |

> 索引由 `test/architecture/docs_hygiene_test.dart` 强制：漏登记新文档、索引指向已删文件、文档之间断链，都会让这条门禁变红。增删文档后跑
>
> ```bash
> flutter test test/architecture/docs_hygiene_test.dart
> ```

## 核心

| 文档 | 什么时候看 |
|---|---|
| [`../AGENTS.md`](../AGENTS.md) | 要改代码：落点、禁则、门禁、文档锚点 |
| [`status.md`](./status.md) | 要写"鸿蒙支持了吗""迁移完了吗""哪条还没验" |
| [`project-guide.md`](./project-guide.md) | 想知道某个子系统怎么实现的、为什么这么设计 |
| [`app-design-refresh-plan.md`](./app-design-refresh-plan.md) | 全 App「湿地雾光」版面重设计与页面重构：逐页蓝图、线框与视觉稿、新版组件、实施顺序和结构差异验收；不代表当前实现状态 |
| [`../README.md`](../README.md) | 项目是什么、能做什么、怎么跑起来 |
| [`../test/BASELINE.md`](../test/BASELINE.md) | 查最近某次改动的测试基线与收据 |

## 设计翻新（全 App 重设计）

P0 清点产物，服务于 [`app-design-refresh-plan.md`](./app-design-refresh-plan.md) 的逐页重设计；随实施阶段推进继续在此登记。

| 文档 | 说明 |
|---|---|
| [`design-refresh/p0-coverage.md`](./design-refresh/p0-coverage.md) | 页面覆盖表：全部路由 / Tab 内嵌页 / 非路由页 / 弹层清单，处置分类含断链与死入口标注 |
| [`design-refresh/p0-structure.md`](./design-refresh/p0-structure.md) | 逐页旧版结构：首屏模块顺序、交互区、状态覆盖与各页面族共性问题 |
| [`design-refresh/p0-assets.md`](./design-refresh/p0-assets.md) | 资产清单：栅格资产、代码品牌系统、教学与记忆卡资产的重绘边界 |
| [`design-refresh/p0-issues.md`](./design-refresh/p0-issues.md) | 问题列表（按是否阻断设计分级）与截图场景采集口径 |
| [`design-refresh/p1-language-and-wireframes.md`](./design-refresh/p1-language-and-wireframes.md) | P1 定型：品牌规则要点、全局版面模式、R01–R18 逐族线框决定与 P2 组件输入 |
| [`design-refresh/p2-components.md`](./design-refresh/p2-components.md) | P2 产物：版面 token 增量与五组公共组件（会话骨架 / 报告套件 / 目录行族 / 全局弹层 / 搜索基元 / 外壳）的文件地图、接缝与接线状态 |

## 构建与发布

| 文档 | 说明 |
|---|---|
| [`android-build-setup.md`](./android-build-setup.md) | Android 构建环境（JDK 17）、常见错误速查、arm64 发布约束 |
| [`ios-build-setup.md`](./ios-build-setup.md) | iOS 构建（静态链接 rslib xcframework + WKWebView 复习器） |
| [`ohos-build-setup.md`](./ohos-build-setup.md) | 鸿蒙构建与签名（fork SDK、签名材料五条硬规则、签名排错速查；**不含口令**） |
| [`firebase-app-distribution.md`](./firebase-app-distribution.md) | 内测分发的一次性 Console / Secrets 配置 |
| [`tester-guide.md`](./tester-guide.md) | 发给测试员的内测说明：安装、主流程、反馈模板、已知限制 |

## 课程内容

| 文档 | 说明 |
|---|---|
| [`content_inventory_current.md`](./content_inventory_current.md) | 主线土耳其语课程（NouveauTurkish）的内容清单（**自动生成，勿手改**；用 `python tool/export_content_inventory.py` 重新生成，目录跟随 `assets/courses/manifest.json`） |
| [`authoring/nouveau-turkish-course-map.md`](./authoring/nouveau-turkish-course-map.md) | 8 章真实主题、CEFR、can-do、词量预算与官方大纲参照 |
| [`authoring/course-layout.md`](./authoring/course-layout.md) | Section / Unit / Lesson 的层级与字段 |
| [`authoring/course-pack-format.md`](./authoring/course-pack-format.md) | 外部课程包 `.turnapack` 的 v1 / v2 格式 |
| [`authoring/lesson-type-templates.md`](./authoring/lesson-type-templates.md) | 课时模板、情景对话、复习题池与题型的写法 |
| [`authoring/listening-show-format.md`](./authoring/listening-show-format.md) | 听力课的广播式音频结构与生成命令 |
| [`authoring/textbook-import.md`](./authoring/textbook-import.md) | 从教材批量导入课程 |
| [`authoring/teacher-guide.md`](./authoring/teacher-guide.md) | 给课程作者的上手指南与排错 |
| [`authoring/teacher-usability-checklist.md`](./authoring/teacher-usability-checklist.md) | 教师可用性的人工验收清单 |
| [`audio-recording-guidelines.md`](./audio-recording-guidelines.md) | 人工录音替换 TTS 的规范 |

## 设置

| 文档 | 说明 |
|---|---|
| [`advanced-settings-system-health.md`](./advanced-settings-system-health.md) | 高级设置四个入口的实现边界；系统健康状态机（[ADR 0040](./decisions/0040-system-health-state-machine.md)） |

## 架构决策（ADR）

编号**不复用**。每篇只给决策与理由，不复述实现状态。

| 编号 | 主题 | 编号 | 主题 |
|---|---|---|---|
| [0007](./decisions/0007-di-consolidation-and-refactors.md) | 依赖注入整合 | [0043](./decisions/0043-anki-v2-single-source-of-truth.md) | Anki 底座 v2 单一事实源 |
| [0010](./decisions/0010-audio-content-decoupling.md) | 音频与内容解耦 | [0044](./decisions/0044-anki-v2-revival.md) | Anki 底座 v2 复活 |
| [0011](./decisions/0011-srs-persistence-scaling.md) | 复习状态持久化扩容 | [0045](./decisions/0045-gui-course-delivery.md) | 编辑器把课程交给 App |
| [0012](./decisions/0012-study-log-append-strategy.md) | 学习日志追加策略 | [0047](./decisions/0047-ohos-companion-lite-build.md) | 鸿蒙伴生轻量版 |
| [0013](./decisions/0013-srs-queue-base-class.md) | 复习队列基类 | [0048](./decisions/0048-ohos-companion-audio-tts.md) | 鸿蒙伴生版音频与 TTS |
| [0014](./decisions/0014-dictionary-and-weak-word-review.md) | 词典与弱词复习 | [0049](./decisions/0049-ohos-turkish-tts-sherpa-feasibility.md) | 土耳其语 TTS 构建可行性 |
| [0015](./decisions/0015-gameprovider-split.md) | GameProvider 拆分为门面 | [0050](./decisions/0050-ohos-official-anki.md) | 鸿蒙启用 Official Anki 全档 |
| [0020](./decisions/0020-swahili-to-turkish-pivot.md) | 目标语从斯瓦希里语转向土耳其语 | [0051](./decisions/0051-ohos-bundle-name-unique-vs-android.md) | 鸿蒙包名必须与安卓错开 |
| [0021](./decisions/0021-git-resource-library-architecture.md) | Git 资源库架构 | [0052](./decisions/0052-tool-gui-functional-lesson-wizard-and-blueprint.md) | 编辑器功能课向导与蓝图 |
| [0026](./decisions/0026-local-resource-editor-enhancements.md) | 本地资源编辑器增强 | [0053](./decisions/0053-turnapack-external-courses.md) | 外部课程经 `.turnapack` 进入 |
| [0028](./decisions/0028-fsrs-continuous-memory-model.md) | FSRS 连续记忆模型 | [0054](./decisions/0054-ai-practice-library.md) | AI 练习库与后台生成 |
| [0029](./decisions/0029-fsrs-relearn-and-local-weights.md) | FSRS 重学阶梯与本地权重 | [0055](./decisions/0055-ai-credential-persistence-ohos.md) | AI 凭据在鸿蒙上真正落盘 |
| [0031](./decisions/0031-turna-rebrand.md) | 改名 Turna | [0056](./decisions/0056-ohos-remove-ai-compliance.md) | 鸿蒙伴生版移除 AI 生成（合规） |
| [0032](./decisions/0032-about-page-tool-gui-content.md) | 关于页加入课程编辑器 | [0057](./decisions/0057-card-adaptation-plan.md) | 记忆卡适配方案与统一展示解析 |
| [0033](./decisions/0033-turna-wetland-crane-palette.md) | 「湿地鹤」色板 | [0058](./decisions/0058-builtin-course-content-source.md) | 内置课程统一选择内容来源 |
| [0034](./decisions/0034-ai-companion-hardening.md) | AI 伴学加固 | [0059](./decisions/0059-course-release-feed.md) | 内置课程离线打包与发布清单 |
| [0037](./decisions/0037-anki-course-review-unification.md) | Anki 课程与复习大一统 | [0060](./decisions/0060-textbook-syllabus-adaptation-and-tts-alignment.md) | 教材/纲领适配与 TTS 参数对齐 |
| [0038](./decisions/0038-ai-cache-memory-only.md) | AI 缓存只存内存 | [0061](./decisions/0061-read-aloud-word-matching.md) | 跟读识别：词面匹配（音素级评分维持不做） |
| [0039](./decisions/0039-webdav-secure-credential-migration.md) | WebDAV 凭据迁移到安全存储 | [0062](./decisions/0062-colored-glass-material.md) | 彩色玻璃材质：白纸上的淡彩玻璃 |
| [0040](./decisions/0040-system-health-state-machine.md) | 系统健康状态机 | [0063](./decisions/0063-settings-glass-quiet-tier.md) | 设置域深层页的弱化玻璃档 |
| [0042](./decisions/0042-staging-first-official-import.md) | Staging-first 官方导入 | [0064](./decisions/0064-sub-lesson-tree-nodes-and-sessions.md) | 子课提升为课程树节点与独立会话 |
| [0065](./decisions/0065-glass-chroma-and-surface-roles.md) | 玻璃降彩度，并分开玻璃对象与扁平纸面 | [0067](./decisions/0067-memory-card-returns-to-course-domain.md) | 记忆卡回归课程域：牌组即课程，练习台无记忆卡入口 |
| [0068](./decisions/0068-ambient-light-and-frosted-glass.md) | L0 环境天光与真毛玻璃档 | [0069](./decisions/0069-course-draft-web-preview.md) | 课程网页目录、草稿预览与反馈修订 |
| [0070](./decisions/0070-scenario-dialogue-lessons.md) | 情景对话场景与既有题型组合 | [0071](./decisions/0071-review-question-pool.md) | 复习题池与课内错题权重 |
| [0072](./decisions/0072-phase-two-authoring-and-release-contract.md) | Phase Two 作者契约、媒体与版本边界 | — | — |

## 其它位置

| 文档 | 说明 |
|---|---|
| [`../tool/gui/README.md`](../tool/gui/README.md) | 课程编辑器（独立 Python 工程）与其自己的文档索引 |
| [`../tool/gui/docs/README.md`](../tool/gui/docs/README.md) | 编辑器文档索引，有门禁强制每篇都在册 |
| [`../CHANGELOG.md`](../CHANGELOG.md) | 版本变更记录 |
