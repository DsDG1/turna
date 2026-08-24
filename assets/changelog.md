# Changelog

Turna 的更新日志。本文件随发布打包到 App 资产中,由应用读取渲染。
完整工程说明见仓库根 `CHANGELOG.md` 与 `docs/decisions/`。

版本编号统一为 0.x 序列（与 pubspec 一致）：1.3.0→0.7、1.2.0→0.6、
1.1.0→0.5、1.0.0→0.4、0.4.x→0.3.x、0.4.0→0.3.0。首个 release id 必须
等于当前发布版本（见 lib/application/settings/release_manifest.dart）。

---

## 0.7.1 — 数据治理、AI 安全与体验打磨 (2026-08-24)

- AI 服务商预设刷新为 DeepSeek / Kimi / Qwen / MiMo，新增深度思考开关（推理字段默认关闭，由用户显式开启）
- AI API Key 迁移至平台安全存储（iOS Keychain / Android Keystore），不再写入明文偏好
- AI 讲解 / 提示 / 陪练三个 Provider 收敛到 `AiStreamingSessionBase`，统一流式取消、代际与增量应用；新增 `StreamDeltaCoalescer` 合并响应降低 UI 重建
- 移除 AI 磁盘缓存镜像，仅保留内存 LRU
- 宝石入账改为幂等账本（`earnGems`），成就解锁按幂等键入账避免重复发放；成就连续天数改用真实学习 streak
- `CardRecognitionPipeline` 取代 `anki_notetype_ai`：签名版本化、去隐私样本特征、持久化规则与 AI 结果形状校验
- `StorageInventoryService` 只读扫描与存储诊断页，支持分类 / 孤儿检测及可再生缓存清理
- 存储诊断页面重构为面向用户的"存储与性能"仪表板（使用率环图 + 分类卡片）
- 卸载 / 删除以 `legacy_anki_migrations` 判定归属，清理失败标记 `pending_cleanup` 并启动时自动重试
- 备份恢复后无需重启：Accessibility / Language / Settings Provider 新增 reload 方法刷新状态
- 设置导航引入 `SettingsDestination` 描述符集中管理页面元数据；`SystemHealthMonitor` 重构为状态机模型
- `CacheDiagnosticsRegistry` 支持按所有者隔离执行缓存清理并保留各自结果
- 牌组组装新增 section beta 语义分组（默认关闭，仅影响新导入）
- 统一版本编号至 0.x 序列，移除 quick_start.md，以 ReleaseManifest 作为版本单一事实来源
- 移除无入口的配对游戏、字母描红，以及未使用的旧品牌图（Mala / 卡纳达语 / Duolingo 贴纸）

---

## 0.7 — Anki 官方 Core 整合与课程/复习大一统 (2026-08-15)

- 官方 Anki rslib 通过 Dart FFI 整合并默认切到官方 Core（ADR 0036/0037 落地）
- 课程与复习大一统：统一复习 ledger、卡片引入资格（`CardIntroductionStore`）与二元 recall flow
- 大型牌组导入走 worker isolate + 流式解压 + 500 条批次写入，内存占用不随牌组大小增长
- 官方导入事务恢复：dry-run 演练、物理备份、逐源 allowlist 与独立 commit 边界（CI 拦截 BACKEND_COMMIT 漂移）
- 新增 deleteNotes 操作硬删除笔记与关联数据
- 课程页大改版：课程树扁平化、滚动隐藏栏、状态角标与 section switcher 翻新
- 数据导入导出 + WebDAV 远程备份同步（manifest / snapshot / restore / 演练）
- 个人页精简：今日概览卡 + 成就 showAll 独立路由 + 学习统计瘦身
- 成就系统重构：evaluator / state repository / migration service / 详情 sheet / 徽章卡
- 路由统一：RouteType.adaptive + Android 预测性返回 + 全 AutoRoute 推送（移除手写 MaterialPageRoute）
- AI 伴学打磨：移除成熟度象限、interaction renderer 调整、AI 深度导师 / ShowWord 翻面
- 系统健康监控中心（`SystemHealthMonitor`）+ AI 伴侣 stack（profile / retriever / 预算 / 凭据）
- 教学 Playground 新增：language_playground_eligibility / 装配器 / 内容源 / 入口页
- 少量 bug 修复与 play_hub 黄金图更新

---

## 0.6 — AI 伴学与土耳其语内容扩充 (2026-08-05)

- AI 伴学全面升级：自由问答、学习诊断、讲解收藏、词典 AI 扩展、Anki 卡片讲解
- 课内提示支持流式回复，并注入学习者上下文（水平、错题、讲解偏好）
- AI Hub 重组为伴学优先：自由问答 / 诊断 / 收藏讲解与创作类入口分区更清晰
- 统一讲解偏好（回复语言、深度、是否允许给答案）与友好错误提示
- 土耳其语内置课程大幅扩充：约 148 词、18 表达、8 语法点、54 课（A1→B2 八章）
- 进度导出不再包含 API Key；移除小艺（Xiaoyi）桥接，统一走本地 AI 引擎

---

## 0.5 — 间隔重复与 AI 引擎升级 (2026-07-30)

- FSRS 连续记忆模型与本地参数优化，复习曲线更贴合个人记忆
- Anki 智能牌组归类与牌型渲染重构，支持复杂 .apkg / .colpkg
- AI 引擎刷新：内存与磁盘缓存、可取消令牌、统一 HTTP 客户端
- 课程管理页、AI 中心、应用图标、文案与本地化整体重写
- 记忆曲线、复习进度与 SRS 学习导师等新面板
- 课程总览、设置、关于、AI 中心、复习页 UI 同步迭代
- 手写 `lib/l10n/app_strings.dart` 取代 `flutter_localizations` 代码生成
- 取消跟踪 `ohos/.codegenie` gitlink,消除 git 状态致命错误

---

## 0.4 — 土耳其语转向 (2026-07-29)

- 界面文案全面中文化，设置与关于页统一体验
- Anki 牌组导入（.apkg / .colpkg）与 Anki 复习入口
- 课内 AI 提示助手，支持 DeepSeek 等兼容接口
- AI 课程设计器、教材导入与进度导出/导入
- 独立设置页：主题、提醒、音效、无障碍与账户数据
- 词典搜索、弱词复习、每日挑战与学习统计仪表盘
- 暗色 / 亮色 / 跟随系统主题
- 目标语言由斯瓦希里语迁移为土耳其语（TTS 代码 tr）
- 移除 Piper 离线 Swahili TTS 模型 + `sherpa_onnx` 依赖

---

## 0.3.x — 体验与可访问性 (2026-07-11)

- 路由守卫、SettingsProvider、版本降级守卫
- 暗色 / 亮色 / 跟随系统主题，主题感知语义颜色助手
- 字体大小、减弱动效、高对比度、阅读障碍友好字体
- 感官减弱与专注模式等神经多样性友好选项
- 本地每日学习提醒（无 streak 修复付费逻辑）
- 课程树完成 / 薄弱 / 待复习状态角标
- 课程内容版本变更提示与进度重置选项
- 一键 release 流水线 + APK / AAB / Web 制品 + 内容清单
- 移除 11 项社交化、游戏化、付费功能（hearts / leagues / 好友 / 商店 / 推送等）

---

## 0.3.0 — future4 框架 (2026-07-11)

- 整洁架构收尾：DI 整合、音频与内容解耦、路由守卫
- SRS 队列基类 `SrsQueueProvider`、GameProvider 拆分 + 外观模式
- 集成测试、Golden 基线、一键发布流水线
- 学习统计、词典、弱词、提醒等能力合入主线

---

## ADR 0020 — 土耳其语转向 (2026-07-12)

- 目标语言由斯瓦希里语迁移为土耳其语（TTS：tr）
- 移除 Piper 离线模型，改用系统 / Google TTS
- 第 1 章问候语真实内容（词汇 + 表达），2–8 章占位待填充
- 8 个 CEFR 分区（A1→B2）与区间前置依赖

---

## 核心能力 — 课程与复习引擎 (2026-07-09)

- Section → Unit → Lesson 层级与 13 种交互题型
- 6 种课型模板：intro / practice / listening / reading / review / mastery
- SM-2 间隔重复（词汇 + 语法）与错题本 FIFO
- Match Madness 配对小游戏、纯本地 SQLite，无云端账号

---

## 0.0.1 — 原型 (2024-04-26)

- 最初原型：basic app to go through 625 words in spanish and kannda
- 路由 (`auto_route`) + 依赖注入 (`get_it`) + `streaming_shared_preferences`
- 字符画练习 + TTS 卡纳达语转写
- MIT LICENSE、Discord 链接、INSTRUCTIONS、CONTRIBUTING
