# P2 组件系统清单（设计翻新 · 全 App 重设计）

> 「湿地雾光」P2 产物：新版版面 token 扩展与五组公共组件的文件地图、接缝与接线状态。P3 / P4 逐域重构时按此消费；组件内部规格以源码 doc comment 为准，本文不复述。上游输入见 [p1-language-and-wireframes.md](./p1-language-and-wireframes.md) 的「P2 输入」；总计划见 [app-design-refresh-plan.md](../app-design-refresh-plan.md) §9 P2。

## 状态口径

**组件已建成、已测试、已接线（P3 / P4 主体落地）。** 会话骨架进入课时 / 每日挑战 / 统一复习 / 语法 / 记忆卡会话与 AI 各页；报告套件进入进度 / 洞察 / 错题仪表盘 / 牌组中枢 / 系统健康 / 存储诊断；目录行族与全局弹层被六个域消费；搜索基元收口词典、卡牌浏览器与 AI 保存列表；外壳两件替换了 StatAppBar 胶囊行与 BottomNavigator 镜片导航。`review/components` 的 `binary_recall_bar` 与 `review_progress_header` 已随迁移删除；课时域 `BinaryGradeRow` 委托 `SessionRatingBand`。**未接线尾项**：设置六个深页、远程备份页、关于 / 隐私长文与章节切换弹层容器仍用旧 primitives（见 `docs/status.md` §8 P4 尾项清单）。

## Token 增量（`lib/core/`）

| 文件 | 增量 | 说明 |
|---|---|---|
| `spacing.dart` | `xxxl = 48`；`pageMargin`(24) / `pageMarginCompact`(16)；`pageGutterMist`；`studyColumnMaxWidth`(720) / `formColumnMaxWidth`(840) | P1 栅格行（主边距 24 / 紧凑 16、节奏至 48、学习主列 ≤720、统计表单 ≤840）。既有 `pageGutter`(20) 是旧页面在用的兼容值，不动 |
| `text_styles.dart` | 版面文字角色：`pageTitle`(30/700) `sectionTitle`(19/600) `cardTitle`(16/600) `bodyText`(16/400) `captionSm`(13/500) `metricHero`(34/700) | P1 排版表。做题域既有 `caption` / `promptLg` / `promptMd` / `buttonLabel` 角色不变 |

品牌 hex、语义色、玻璃四档浓度与纸面 / 控件 / 磨砂三表面角色未动——ADR 0062 / 0063 / 0065 继续有效，P2 组件全部消费既有表面（纸面 `flatPaperDecoration`、主题感知色 helpers），不新增材质档。

## 组件地图

### 会话骨架 `lib/views/widgets/session_shell.dart`

沉浸作答模式的四件套，吸收 `review/components` 三套平行实现的共性：

| 组件 | 替换目标 |
|---|---|
| `SessionProgressBand`（`PreferredSizeWidget`，退出 + 进度 + 计数 + 上下文动作键） | `ReviewProgressHeader` + 语法页手写 `AppBar(actions)`；圆点 >16 题自动落回细条 |
| `SessionRecallCanvas`（纸面回忆画布） | 复习主卡 / 课时大题面的中性容器；第三方卡片宿主不加包装（ADR 0066 保真边界） |
| `SessionActionBand` + `SessionPrimaryAction`（52 高 teal 主操作） | 各页手写的底部动作区与「显示答案」内联按钮（两份逐字段重复） |
| `SessionRatingBand`（`outline` / `primary` 双调性 + 间隔小字） | `BinaryRecallBar` 与 `ReviewRatingBar` 两套平行评分条 |

`SessionSourceLine`（来源行）是三相位会话唯一的上下文差异位。评分「负档」按评审稿用天光蓝描边而非错误红——评分不是错误。

### 报告套件 `lib/views/widgets/report_kit.dart`

学习报告构图（R09 / R10 / R13）：`ReportMetricHeader`（核心指标头）、`ReportCompositionBar`（构成条 + 图例）、`ReportBarChart` / `ReportLineChart`（CustomPaint 自绘，无图表依赖）、`ReportHeatmap`（0–4 档主题感知色阶）、`ReportDefinitionList`（定义列表）、`ReportSectionHeading`。图表的 `semanticsLabel` 必填——像素图对屏幕阅读器是空的，朗读稿由数据侧生成。

### 目录行族 `lib/views/widgets/directory_rows.dart`

「行不是卡」：排版 + 发丝线组织，状态用轮廓表达（实心 = 完成、环 = 当前、淡 = 未达 / 锁定）。

| 行 | 用途 |
|---|---|
| `DirectoryLessonRow` / `DirectorySubLessonRow` / `DirectoryGroupHeader` | 课程目录三层（课时 / 子课 / 吸顶单元头；缩进线与吸顶由父级 Sliver 做） |
| `DirectoryTaskRow` | 任务台队列行（色条 + 计数，顺序即优先级） |
| `DirectoryEntryRow` | 阅读目录条目（词典词条、收藏讲解、更新日志） |
| `DirectoryLinkRow` | 偏好目录分类入口（图标井 + 一句说明） |
| `DirectoryValueRow` | 偏好目录表单行（值右对齐；给了 `control` 行不抢点按） |

### 全局弹层 `lib/views/widgets/turna_sheet.dart`

`showTurnaSheet`（拖手 + 标题 + 一句说明 + 正文 + 操作区，次左主右、危险红动词、键盘 viewInsets 让位）与 `showTurnaConfirmDialog`。统一的是**容器形状**；正文与文案由调用方给。迁移对象是 21 处 `showModalBottomSheet` 与退出确认 / 设置确认类 dialog 的手写容器。

### 搜索基元 `lib/views/widgets/search_field.dart`

`TurnaSearchField`：输入 + 内建 250ms 防抖（`onDebouncedChanged` 只给终值，清除键立即回调）。收口词典与卡牌浏览器两份相同的 Timer 复制；懒行（`ListView.builder` + 分页）留在各域——那是数据装配，不是输入件的事。

### 外壳 `lib/views/home/components/`

R01 决定的两件：`LightTopBar`（课程名 + 切换 + 连胜；状态数字离开顶栏）与 `TextTabBar`（水平文字导航 + 16×4 芦苇青受光短条，字号封顶 1.4）。接线在 P3 外壳重构：`StatAppBar` 状态胶囊退役、`BottomNavigator` 镜片动画退役、状态数字回各自页面概览区。

## 测试与预览

- 行为契约测试六个文件（会话骨架 / 报告 / 目录行 / 弹层 / 搜索 / 外壳），登记见 `test/BASELINE.md` 当日条目。
- 每个组件文件尾有 `@Preview`（light + dark 双注解，group `Wetland mist`），走 Flutter 官方 widget previews 设施。

## P3 / P4 接线注意

1. **删旧件**：会话域迁移完成后删 `binary_recall_bar.dart` / `review_progress_header.dart`（`ReviewRatingBar` 在 `review_components.dart` 内）；词典 / 卡浏览器换 `TurnaSearchField` 后删两份 Timer；sheet 迁移一处删一处的自写拖手 / 顶圆角容器。
2. **弹层文案**：`showTurnaSheet` 不带任何域内文案；调用方传。面向用户文案继续走 `AppStrings`，术语守「记忆卡」口径（AGENTS §7.2）。
3. **评分带鸿蒙侧**：正式记忆卡宿主的评分带在鸿蒙由原生 ability 承担同一构图（P0-issues A3 契约），本组件是 Android / iOS 侧的同一基准。
4. **状态胶囊退役**是破坏性信息架构变更（积分 / 宝石 / 待复习数去所属页面），属 P3 外壳重构批次，不在组件接线里顺手做。
