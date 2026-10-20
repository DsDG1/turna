# Changelog

Turna 的完整更新历程，按时间倒序记录各版本的重要变化。

> 项目早期名为 Varnamala Plus（见 [ADR 0031](./docs/decisions/0031-turna-rebrand.md)），语种由斯瓦希里语转向土耳其语（见 [ADR 0020](./docs/decisions/0020-swahili-to-turkish-pivot.md)）。`## 0.` 一节记录转向之前的史实。

更简短的版本摘要 → 应用内 **设置 → 更新日志**；工程说明 → [`docs/decisions/`](./docs/decisions/) 与 [`README.md`](./README.md)。格式参考 [Keep a Changelog](https://keepachangelog.com/zh-CN/1.1.0/)，遵循 [Semantic Versioning](https://semver.org/lang/zh-CN/)。

---

## 0.9.1 AI 收敛与界面打磨 (2026-10-20)

### 新增

- **系统提示词可见可追加**：默认 prompt 单一来源，可按功能追加（上限 4000 字）并恢复默认；只追加不替换。
- **AI 生成内容显式标注**：页面级横幅 + 单条输出角标。
- **鸿蒙分层图标与独立 bundle 名**：图标前景 / 背景各 1024×1024（应用市场要求分层）；bundle 名 `me.dsdogs.turna.hmos` 与安卓区分（ADR 0051）；每日提醒无排程能力时开关置灰并说明原因。

### 变更

- **AI 服务商收敛（破坏性变更）**：`AiProvider` 由 `deepseek / kimi / qwen / mimo / custom` 收敛为 `deepseek / mimo / custom`；默认模型升至 DeepSeek `deepseek-v4.1-flash`（+ `-pro`）、MiMo `mimo-v2.6-pro` / `mimo-v2.6`。旧配置自动迁移（`schemaVersion: 2`；`kRetiredPresets` 把 `kimi` / `qwen` 转为 `custom` 并保留原 Base URL 与模型，`kRetiredModelAliases` 迁移旧模型别名），不会静默变成连不通的坏配置。
- **AI 面去蓝紫 + emoji 清零**：AI 面 11 处 `amethystLeague` 移出（该常量保留给词典 / 成就目录）；全库用户可见 emoji 清零。
- **「开发者实验室」（Fun Lab）整体删除**（不是隐藏）：设置分类、debug 入口、开发者设置页、FunLab 服务及 4 张表（schema 30→31，v31 纯 `DROP TABLE`）、66 条文案、备份清单移除。
- **AI 入口并入练习队列**：练习页「AI 助手」横幅移除，复习队列 2×2 增第四格「智能练习」（未配置挂「未配置」徽标）。
- **接口与责任标注**：AI 配置页常驻说明只接 OpenAI 兼容 `POST {Base URL}/chat/completions`，请求本机直达服务商。
- **鸿蒙探针 ability 注销 + 界面修正**：诊断 ability 不再注册进发布包（代码仍在 `ets/probe/`）；大字模式排版、开关 ON 态 thumb 改白。

### 修复

- 鸿蒙每日提醒开关无效（无排程能力时置灰并隐藏时间行）；大字模式（`TextScaler.linear(2)`）下成就卡、复习 streak 行、课时完成弹窗、添加课程卡文字溢出；Anki 官方引擎答题到期折叠。

### 验证

`flutter analyze` **No issues found**；`flutter test --exclude-tags golden` **2233 passed / 0 failed**；`python -m unittest discover -s test -p "*_test.py"` **Ran 60 tests / OK**；`test/golden/` 仅 `course_tree_expanded_light` 一项失败（既有渲染漂移）。新增 7 个测试文件，删 2 个（共 8 条）。

---

## 0.9 多端落地与可靠性 (2026-10-19)

### 新增

- **鸿蒙（HarmonyOS）伴生版**：课程、复习、词典、设置、备份可用；官方 Anki 复习器以原生 ArkUI 页面呈现（渲染 / 翻卡 / 评分落库 / 队列前进 / 强杀恢复全链路）；音频与朗读走自维护 ArkTS 通道，内置离线土耳其语语音（sherpa-onnx）。
- **iOS 官方 Anki 引擎**：静态链接 rslib 的 `TurnaAnki.xcframework` + WKWebView 复习器（`turna-anki://anki.local`），与 Android 同走 Official 路径。
- **多语言课程框架**：多门内置语言同库共存、随时切换与单独卸载；支持导入外部 `.turnapack` 课程包（重新导入先确认覆盖）。
- **体验改良批次 B1–B7 与 P0 备份一致性**：Splash 播种 / 校验阶段文案；自研 Markdown 子集聊天气泡；改课 JSON 快照可撤销一次；`StudyActivityGate` 学习 / 备份互斥门。

### 变更

- 四个主 tab 顶栏统一：共用 `TurnaTheme.tabAppBarHeight` token；设置页标题降为 `titleLarge`。
- **暗色模式统一为黑色背景**：脚手架纯黑 → 卡片 `#141414` → 抬升面 `#1E1E1E` → 分割线 `#2A2A2A`；Android 窗口色与鸿蒙调色板同步。
- **移除法语示例课程（破坏性变更）**：内置课程只保留土耳其语，法语资产移入测试 fixture。
- **架构收口（破坏性变更）**：DAO 接口化 + `application → data` 硬禁，Legacy 读路径退役，`course.db` 升 v27，语言切换失败改为三段式（拒绝切换 → 提交级联 → 整体回退）。
- **错题本与 SRS 改增量写入**，避免每答一题重写整队列 / 整表；关于页重新设计，删除「配套工具」入口。

### 修复

- 课时完成弹窗 / 统一复习完成态卡死（`PopScope(canPop: false)` 与 `maybePop` 形成无限微任务循环）；鸿蒙复习入口白屏与评分后卡住（页面不再预热，评分后原地装卡并 present 下一张）。
- 课程 `.turnapack` 导入：种子前清同 id 行、slug 冲突处理。
- 安全：日志脱敏、拒绝不安全的外部端点与重定向；`build_release.py` 新增 `--version` 与 pubspec 一致性断言。

---

## 0.8 Anki 导入重做与复习升级 (2026-09-04)

### 改进

- **导入改为「先试装、后确认」**：牌组先在独立试用库导入并生成预览，确认后才写入正式库；取消只删试用目录，正式库零写入。
- **导入设置随牌组走**：字段匹配与摆放选择改存 Anki 库配置区，备份 / 恢复 / 导出自动携带；课程树改为派生视图。
- **删除牌组真正回收**：先立即从课程树和复习隐藏，后台再清理卡片与空间。
- **大牌组导入不再卡界面**：导入全程后台进行并支持取消；「复习全部」支持跨多个 Anki 牌组连续续接；新增分节底部弹窗与朗读总开关。

### 修复

- 导入完成页可能卡死闪退（返回键死循环）的真机问题；上次导入未完成时仍发起新导入导致的重复卡片。
- 启动维护被整体跳过、导入前引擎未打开等接线问题；部分场景下课程树章节缺失。

---

## 0.7.5 导入识别器重做 (2026-08-29)

### 改进

- 卡片识别推倒重来：不再逐张卡跑内容猜规则，改为读牌组自己声明的结构（卡片类型、模板正反面引用、`{{type:}}` / tts 过滤器、字段词典、位置先验）一次判定整类卡片，识别开销与卡数解耦。
- 预览页每类卡片给出「为什么这么识别」的证据展开与置信带；`{{type:}}` 拼写模板、选项池字段、正面音频驱动可直接识别为拼写 / 选择 / 听音题型。


### 修复

- 挖空卡片多删除点时复习到第二张仍挖第一个空：按卡片序号选取对应 `{{cN::}}` 删除点；兼容存量，已确认的字段映射原样生效，旧映射 JSON 自动换算到新角色命名，零数据库迁移。

---

## 0.7.4 语言课与导入 Anki 分队列 (2026-08-29)

### 改进

- 练习页与个人页按课程类型切开复习入口：语言课只保留错题 / 单词 / 语法；自行导入的 Anki 课只保留 Anki 复习（并隐藏薄弱单词）。
- 导入 Anki 需先完成课程里的一课，该课卡片才进入 Anki 复习；课内第一遍不写官方排期、不进错题本，第一次「不认识 / 认识」发生在 Anki 复习。刚解锁的课当天新卡上限至少覆盖该课张数。

### 修复

- 修复 Anki 到期数长期显示「—」：队列拉取上限与原生 1–100 对齐。
- 修复 Anki 复习第二张卡报「当前卡片无法安全写入」：评分后实时重建队列，推进改由调度器刷新后的当前卡驱动。

---

## 0.7.3 练习页焕新 (2026-08-28)

### 改进

- 练习页主页全新信息架构：顶部「开始今日复习」主卡（今日总待复习大数字 + 四队列速览 chips），短按一键进入最高优先级队列；复习入口收敛为「复习队列」2×2 网格。
- AI 助手入口合并为单行卡片；「练习工具」改为薄弱单词 / 词典 / 复习进度三列紧凑格。- 新增长按浮窗交互：展示入口实时数据（待复习构成、最近错题、高频遗忘等）并可直达页面；支持屏幕阅读器长按语义。

### 修复

- 修复退出 AI API 配置页时偶发的 `widget tree was locked` 框架异常：dispose 补存草稿改为微任务延迟通知。

---

## 0.7.2 Anki 导入与复习体验优化 (2026-08-25)

> 本节记录 0.7.2 候选版本内容；正式发布仍以最终验收结果为准。

### 改进

- 每个 Anki 来源作为独立课程显示，多牌组管理更清晰；导入生成的课程树按牌组名称自然排序（Unit 2 在 Unit 10 之前），始终排在内置课程之后。
- 超过单 section 60 个 unit / 单 unit 40 课的导入自动按 "Part N" 拆分，避免生成损坏课程；「复习全部」可连续覆盖多个 Anki 来源，待复习数量与卡片顺序和实际复习保持一致。
- 课程管理页新增卡片浏览、牌组统计和旧数据迁移入口；导入、重新导入、删除和迁移支持更稳妥的中断恢复。

### 修复

- 修复课程切换、牌组定位和删除范围不准确；修复 Anki 课程与内置课程排序号冲突导致的顺序随机。
- 修复内容版本重置后已导入 Anki 课程消失且不再重建；减少导入或迁移中断后出现重复数据、残留数据和不可见课程。

---

## 0. 原型与上游 Varnamala (2024-04 → 2024-11)

[rshrc/Varnamala](https://github.com/rshrc/Varnamala) 上游项目最初的 6 个月。最早一次 commit `02cf739` 在 2024-04-26。

### 0.1 起步 (2024-04 → 2024-10)

- 目标是搭一个能跑通西班牙语 / 卡纳达语 625 词的语言学习 App；首个可运行版本直接读 JSON 词表清单。
- 路由 / DI / 资产：`get_it`、`auto_route`、SharedPreferences、Font Awesome、Duolingo 风格资产、课程树动态 JSON 渲染；游戏化含课程完成弹窗、退出关卡二次确认、字符画练习、Match Madness 配对页与音效。

### 0.2 接入 Firebase (2024-11)

- 引入 Firebase Auth / Firestore / Crashlytics / Analytics；Splash 自动登录、分数 / streak 自增。
- 社交化：连击维护、好友与推荐、排行榜 XP 排序、关注按钮。

### 0.3 多语言框架 (2024-11)

- 新增 `TargetLanguage` 与课程数据加载；Course / Game / Language / Lesson Provider；`Words625` 改名 **Varnamala**；多语言元音辅音映射与结构化课程数据。

### 0.4 缺失/待删(预告 2026-07)

这一阶段加入的社交化、付费、Firebase 同步功能在 2026-07-09 (commit
`e060c11`) 一次性全部删除,详见 §1。

---

## 1. 本地化分叉 (2026-03)

2026-03-04 上游仓库存活近 17 个月后,本分叉(dSDogs)导入,创建 `CLAUDE.md`（已删）宣告"再次开发"。UI 大改版（两次）、游戏化增强、成就章节、引导屏幕与调试导航、Linux 桌面构建支持。

### 引入后又被删除(2026-07-09 `e060c11`)

| 功能 | 原因 |
| --- | --- |
| Google 登录 | 改为本地用户,无后端 |
| 排行榜 / 段位 | 无社交化 |
| 商店 / 冻结 / 道具 | 无付费 |
| XP boost / 每日目标 | 与间隔重复逻辑冲突 |
| 连续冻结 / 周末护符 / 连击修复 | 引导用户持续学习,不应"修复" |
| 心数 / 生命 | 移除学习摩擦 |
| 钻石购买 / 道具 | 无付费 |
| 好友系统 / 社交成就 | 无社交化 |
| 推送通知 | 无后端 |
| 口语题 | TTS 已足够 |
| 外部 GUI 编辑器 | 改回 JSON-first |

---

## 2. 离线优先重写 (2026-07-07)

`f06849b` — Firebase 全部下线,改为 SQLite + Provider。

- **数据迁移**：移除 Firebase Auth / Firestore / Cloud Functions，`firebase_user` 改为 `local_user`；移除 League / 排行榜 / 社交登录 / 多语言字母表 / Node.js 依赖。
- **SRS 与课程模型**：引入 SM-2（`lib/core/sm2.dart`）与三类 SRS 队列 Provider；`lib/domain/course/` 新域模型，支持选择题 / 翻译 / 填空 / 连线 / 听力 / 口语 / 阅读题型。- **错误 / 性能 / 存储**：`b49602b` 统一 Result + 全局错误边界；卡纳达语词表与 SQLite 课程仓库。
- **课程结构与 Phase 7–13**：`0ed58ce` Section / Unit / Lesson 层级，`1e9035d` 重构课程与课时模型；`e060c11` 清掉 hearts / 商店 / 推送等 11 项；4 个 lesson 模板；新增 `Expressions` 表（schema v5）。

---

## 3. future1.0 内容骨架 (2026-07-09)

由 `[phase-7]` → `[phase-11]` 顺次铺好的骨架。

- **设置 / 音频 / 错题 / 工具**：SettingsProvider + AudioModule + 音效 / 触感开关；设置页重设计 + 关于页；`tool/course_cli.py` 课程内容 CLI。
- **CI / 错误 / DI / 品牌 / 性能**：全 Flutter CI + Makefile；Result + 全局错误边界；改名 `varnamala`；离线 TTS 升级与 espeak-ng-data 裁剪。

---

## 4. future4 框架收尾 (2026-07-11)

**future4 框架归档**，一次性完成 13 个 `[phase-N]`。

- **Phase 17–22**：卫生清理、版本降级守卫、内容更新提示；`AudioController` 注入 `SettingsProvider`（ADR 0010）；输入渲染器改 `ValueListenableBuilder`；SRS 规模与 StudyLog append ADR（0014 / 0015）；抽 `SrsQueueProvider` 基类。
- **Phase 23–26**：`ScoreProvider` / `StreakProvider` / `LessonProgressProvider` / `GameMilestoneProvider` 四件套拆分 + 纯 streak resolver；集成测试与 golden 基线；`tool/build_release.py` 一键构建 APK / AAB / Web 制品。

---

## 5. 1.0.0 土耳其语转向 (2026-07-12)

> 详细迁移背景见 [`docs/project-guide.md`](./docs/project-guide.md) §13 / §15。

- **一次性土耳其语迁移（破坏性变更）**：`389f453` 把目标语言由斯瓦希里语改为 **土耳其语**（assets / TTS / language code / course loader）。删除 `assets/courses/swahili/`、Piper 斯瓦希里语离线模型与 `lib/courses/alphabets/swahili.dart`；新增 `assets/courses/turkish/`；`index.json` 重命名。
- **课程树虚拟化与文档迁移**：`CourseTree` 课程列表扁平化 `SliverList`，支持 100+ 课 / 单元；删除 `dreamplan.md` / `future2.md` / `future3.md` / `future4.md`（已删，迁入 `docs/decisions/`），新增 ADR 0019 / 0020 与 4 套模板 JSON。
- **课程内容扩充**：Section 1「Merhaba」改为 15 张 productive intro 卡。
- **AI 与 GUI 工具**：应用内 AI 课程生成器与桌面 GUI 对齐；课内 AI 提示助手 + DeepSeek 默认配置；设置 Tab + 进度导出 / 导入；教材导入与 AI 生成大改。

---

## 6. 1.1.0 FSRS / AI / Anki 智能化 (2026-07-30)

> 历史实现规范见 [`docs/project-guide.md`](./docs/project-guide.md) §5、§6、§7（原 ADR 0027–0029）。

`980224e` feat(srs,anki,ai): FSRS engine, anki smart organization, AI engine refresh, app icon & l10n。

- **FSRS 引擎与 Anki 智能化**：`fsrs_engine.dart` / `fsrs_optimizer.dart` / `fsrs_relearn.dart` / `srs_scheduler.dart`（SM-2 保留作后备）、复习历史与 SRS 状态 DAO；智能牌组归类、牌型渲染，assembler / importer 全面重构。
- **AI 引擎重构**：`lib/application/ai/engine/` 整目录重构（缓存 / 取消令牌 / 引擎与配置 / HTTP 客户端 / 提供商预设 / 流式分块），全面接入各 AI Provider；新增 AI 中心与教材冲突预览视图，并新增课程管理页、AI 深度导师、Anki 媒体条、记忆曲线图等界面。
- **本地化（破坏性变更）**：删除 `l10n.yaml` 与 `lib/l10n/app_*.arb` / `app_localizations*.dart` 及 `locale_provider.dart`，改为手写 `lib/l10n/app_strings.dart`（无 codegen），全文中文化。
- **品牌 / 文档 / 测试**：应用图标在 Android / iOS / macOS / OHOS / Web / Windows 全面刷新并新增吉祥物资产；删陈旧 ADR 0021–0026；新增 AI 引擎 / 教材导入 / FSRS 测试。


---

## 7. 维护 (2026-07-30 → 2026-08-01)

- **settings 同步**：设置 Provider 增 14 行新配置项，`app_strings.dart` 增 242 行中文化；AI 中心与 Anki 导入屏大改。
- **OHOS gitlink 修复**：`9b5a172` — `ohos/.codegenie` 目录被作为 gitlink 提交,指向过期子 commit,导致每次 `git status` 输出大量致命错误并挂起所有 git 操作。修法:`git rm --cached ohos/.codegenie`；`.gitignore` 增 `**/.codegenie/`。

---

## 8. 1.2.0 伴学与内容扩充 (2026-08-05)

- AI 伴学工具链全面上线：自由问答、学习诊断、讲解收藏、词典扩展与 Anki 问答解析。
- 课内提示支持流式回复并注入学习者上下文（水平、错题本、讲解偏好）；土耳其语内置课程扩充为 A1→B2 八章（约 148 词 / 18 表达 / 8 语法 / 54 课）；宝石与装扮兑换支持、湿地鹤品牌色板锁定（ADR 0033/0035）。

---

## 9. 1.3.0 Anki 原生渲染、练习解耦与吉祥物升级 (2026-08-15)

- **展开式问答卡面**（`AnkiRevealScaffold`）：问题留在上方，答案在下方平滑展开，四档评分固定在底部，移除旧版 3D 翻转卡顿；卡面显示 Deck / Tags / 旗标，预热下一张卡。
- **Flutter 原生 HTML 渲染链**（`AnkiFacePaintEngine` + `AnkiFlutterHtmlView`）：默认走高效原生渲染，仅在复杂 MathJax / JS 脚本时降级 WebView。
- **复习与练习独立解耦**：复习仅走原卡四档评分，练习独立提供多种交互题型；`Cloze` / `{{type:}}` 映射为原生填空与选择，练习不污染 FSRS 复习调度。
- **导入体系与容错恢复**：`AnkiImportDiffPlanner` 支持 merge / forceReplace / appendAsNew 与差异预览；`AnkiImportOperationRecovery` 支持失败 / 取消恢复；`AnkiImportMappingEditor` 可视化调整字段映射。
- **Turna 湿地鹤吉祥物形象系统**：2D 扁平现代卡通风格；主页欢迎、课文阅读、听力沉浸、通关庆祝与全新 App 图标场景全覆盖。
- **系统健康与诊断**：`SystemHealthMonitor` 提供数据库、文件系统、AI 引擎与 Anki 兼容性诊断。

---

## 简版

以下为面向用户的版本摘要，应用内文案见 assets/changelog.md。

### [0.8] - 2026-09-04

- Anki 导入全面重做：牌组先完整试装、预览确认后才真正加入课程，中途取消不留残余；大牌组导入不再卡界面，删除牌组真正「删干净」。

### [0.7.2] - 2026-08-25

- Anki 来源现在会作为独立课程显示，多牌组管理更清晰；新增卡片浏览与牌组统计入口，导入与迁移的中断恢复更可靠。

### [0.7.1] - 2026-08-24

- 更新 AI 服务预设并加入可选的深度思考模式；AI 密钥改用系统安全存储，导出时不会携带敏感信息。

### [0.7] - 2026-08-15

- 改进 Anki 牌组导入、复杂卡片显示和复习体验；统一课程与复习入口，加入数据导入导出和远程备份。

### [0.6] - 2026-08-05

- AI 伴学新增自由问答、学习诊断、讲解收藏和词典扩展；土耳其语内置课程扩充为 A1 至 B2 八章。

### [0.5] - 2026-07-30

- 更新个性化记忆复习方式，改进 Anki 牌组识别和复杂卡片显示；AI 请求支持取消，回复和错误处理更稳定。

### [0.4] - 2026-07-29

- 界面全面中文化，学习目标语言调整为土耳其语；新增 Anki 导入与复习、课内 AI 提示和教材导入，支持学习进度导入导出。

### [0.3.x] - 2026-07-11

- 支持多种主题、字号、高对比度和阅读辅助选项；加入专注模式与本地学习提醒，移除不再使用的社交与付费功能。

### [0.3.0] - 2026-07-11

- 完成离线优先的课程与学习框架，支持多种课程结构与练习题型；整合学习统计、词典、弱词复习和提醒。

### [0.0.1] - 2024-04-26

- 完成最初的西班牙语与卡纳达语词汇学习原型，加入基础练习、动画、语音和配对玩法；建立课程导航与学习数据保存能力。
