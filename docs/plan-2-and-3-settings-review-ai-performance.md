# Plan 2 + Plan 3：设置与产品体验重构、复习与 AI/Playground 性能治理

> 状态：**第一轮实施已完成核心工程项（2026-08-23，见 §35 实施状态核对）**；
> 性能基准/真机验收、洞察页深度聚合与部分二级交付仍待后续轮次  
> 编写日期：2026-08-23（实施核对更新：2026-08-23）  
> 所属总计划：三个计划中的第二、第三计划，合并为一个执行文件  
> 前置计划：[Plan 1：Anki 数据正确性、识别与存储治理](./plan-1-anki-data-integrity-and-storage.md)  
> 总优先级：Plan 2 为 P1，Plan 3 中性能与 AI 凭据安全项为 P0/P1  
> 主要目标平台：Android 中低端设备；桌面端不得回退

---

## 0. 已确认的产品决策

本文按需求澄清时确认的默认方案定稿。除非实施中发现数据安全或平台能力阻断，不再为以下方向重复做产品选择：

1. Plan 2 负责设置页重构、实验室退场、高级页、无障碍、关于/版本/链接以及装扮与宝石体系。
2. Plan 3 负责复习进度页、AI 助手、Playground 融合、内容创作退场和全局性能治理。
3. “趣味实验室”从普通用户界面完全隐藏：成熟设置迁移到正式页面，不稳定能力只允许开发环境使用。
4. 高级页成为正式一级页面，普通用户可以进入，但危险操作必须给出解释、影响范围和确认。
5. 高级首页只展示稳定、可理解的能力；旧 Anki 深度参数进入二级“旧版与兼容性”。
6. 设置中的“AI 工具”一级栏目删除；只在高级页保留 AI 连接配置。
7. AI 连接配置保留服务商、API Key、模型、折叠的自定义 Base URL、连接测试和清除凭据。
8. AI 助手保留与学习上下文紧密相关的能力；内容创作从移动端删除，并提示“请参考 GUI 平台”。
9. Playground 吸收一小部分轻量 AI 能力：自由提问、句子纠错、情景对话；不复制完整 AI 助手。
10. 复习进度首页优先展示今日进度、今日目标、待复习/新卡/逾期、连续学习、近 7 日、时间、准确率和课程/牌组。
11. 热力图、记忆曲线、成熟度等分析进入二级“学习洞察”页。
12. “阅读与感受”拆分：外观与声音保留在普通设置，无障碍成为独立一级页面。
13. 宝石只购买装扮和不影响学习结果的辅助物；不售卖答案、跳过学习、虚假进度或评分优势。
14. 连续学习保护可以作为消耗品，但只能保护展示连续天数，不能修改到期卡、复习历史或真实学习量。
15. Android 中低端设备作为性能验收主基线，桌面端做功能和性能不回退验证。

### 0.1 尚未给出、实现时必须配置而不能猜测的信息

以下内容不是阻塞计划编写的问题，但会阻塞对应功能上线：

- GUI 平台的生产访问地址；
- 项目主页、问题反馈、发布页、隐私政策等正式外链；
- Android 性能基准机型和最低支持系统版本；
- 应用当前对外发布版本与更新日志版本策略。

在这些信息缺失时，UI 必须显示明确的不可用说明或隐藏入口，不能继续使用未经确认的旧 GitHub 地址，也不能构造看似可点击但必然失败的链接。

---

## 1. 为什么把 Plan 2 与 Plan 3 放在同一个文件

两个计划的交付顺序仍然独立，但共享以下基础设施：

- 路由与页面生命周期：设置、AI、Playground、复习页都需要从“大组件常驻”转向按页面加载。
- 诊断与性能度量：卡顿、内存、缓存和存储必须使用同一套指标口径。
- 数据修订号：复习统计、Playground 题源和 AI 上下文都要知道数据何时真正变化。
- Anki 所有权模型：复习统计和 AI 卡片解释依赖 Plan 1 提供的 source/owner 信息。
- 无障碍契约：复习图表、流式 AI、装扮动画和 Playground 都必须尊重减少动态、高对比和屏幕阅读器。
- 外链注册表：关于页、GUI 迁移提示、问题反馈和文档都不能各自硬编码 URL。

因此本文使用一个总依赖图和一套验收门槛，避免 Plan 2 做完后，Plan 3 又重新修改相同的路由、设置存储和组件基础设施。

```text
Plan 1 数据正确性与 owner/source 元数据
        │
        ├── 存储清单 ───────────→ Plan 2 高级/存储与性能
        ├── 卡片识别与展示契约 ─→ Plan 3 AI 卡片上下文
        └── 统一导入来源 ───────→ Plan 3 复习统计来源筛选

Plan 2 设置 IA / 安全凭据 / 无障碍 / 外链注册表
        │
        ├── AI 连接配置 ────────→ Plan 3 AI 助手与 Playground
        ├── 无障碍能力契约 ─────→ Plan 3 图表、动画、流式输出
        └── 性能诊断入口 ───────→ Plan 3 性能基线与回归结果
```

---

## 2. 审计方法与结论可信度

本文基于当前仓库静态审计形成，所有成因按下列等级描述：

| 等级 | 定义 | 实施动作 |
| --- | --- | --- |
| 已确认 | 可以从当前代码直接读出调用链、状态或复杂度 | 可直接建立修复任务和回归测试 |
| 高概率 | 代码具备明确风险，但需要 Profile/真机数据确认占比 | Phase 0 埋点后决定优先级或阈值 |
| 待验证 | 用户感知成立，但当前代码不足以定位单一原因 | 不先重写，先采集时间、内存和磁盘证据 |

当前总判断如下：

- 设置页的主要问题不是绘制性能，而是信息架构和职责混乱。
- “实验室”并非普通实验功能，而是会改分数、宝石、成就和复习状态的调试/作弊入口。
- 关于页链接不可用和版本错乱都有明确的硬编码与双事实来源。
- 装扮“没效果”来自商品数量少、展示面少、购买事务不完整，不只是视觉样式不够华丽。
- 复习进度卡顿有明确的全量读取、重复扫描和重复计算路径。
- AI 页面卡顿有明确的逐分片通知与大范围组件重建路径。
- AI 配置页存在逐字符持久化，且 API Key 当前进入普通偏好存储，兼有性能和安全问题。
- 全局“总觉得卡”还不能归因到单一模块，必须以路由、帧、数据库、磁盘和内存的分层指标定位。

---

# 第一部分：Plan 2——设置、无障碍、高级、关于与个性化重构

## 3. Plan 2 的目标与非目标

### 3.1 目标

1. 把设置首页从八个职责重叠的栏目整理成稳定、可扩展、可深链的结构。
2. 让实验室完成退场，并安全迁移已有偏好和快照。
3. 建立正式高级页，容纳 AI 连接、存储与性能、系统健康、诊断和兼容性入口。
4. 将无障碍从“阅读与感官”中独立出来，并保证每个开关具有可测试的全局效果。
5. 修复关于页失效链接、重复入口、使用指南冗余和版本号不一致。
6. 建立可持续扩充的装扮商店和宝石账本，让装扮在足够多界面真实可见。
7. 不破坏现有用户设置、备份和恢复；敏感凭据必须迁移到平台安全存储。

### 3.2 非目标

- 不在 Plan 2 重写 Anki 导入、识别和删除逻辑；这些属于 Plan 1。
- 不在设置页提供 Official Anki 内部导入的新入口。
- 不把系统诊断包装成“自动优化大师”；只报告可解释、可验证的数据。
- 不建立付费商城、联网货币或真实货币购买。
- 不让装扮或宝石改变复习算法、准确率、课程完成度或成就真实性。
- 不在这一计划重做 AI 对话页面和复习进度页；只提供它们依赖的设置、安全与导航能力。

---

## 4. Plan 2 当前问题与实际成因

## 4.1 设置首页依赖整数索引，结构难以维护（已确认）

当前 `lib/views/settings/settings_page.dart` 通过 `_category` 的 `0..7` 整数控制子页面，并维护 `_mainIndexes`、`_dataAboutIndexes`、`_labIndexes` 和 `_advancedIndexes` 等数组。

这带来以下问题：

1. 类别身份是整数而不是类型；插入、删除或调整顺序时，展示数组和 `switch` 必须同时修改。
2. 设置子页不是正式路由，无法可靠深链到“API 配置”“存储与性能”或“无障碍”。
3. 页面状态只存在于 Settings tab 的本地 State 中，外部入口只能先切换 tab，再依赖额外逻辑选择页面。
4. 全部内容由一个设置页面管理，职责会随栏目增加继续膨胀。
5. 返回行为、页面标题、状态恢复都要由本地整数手工模拟。

根治方向不是仅重新排列 `_categories`，而是引入强类型 `SettingsDestination` 和正式子路由。设置首页仍可驻留在 Home tab，但子页面由嵌套路由或统一导航协调器管理。

### 目标不变量

- 类别的稳定身份不能依赖展示位置。
- 每个正式设置页有唯一 route name 和可测试的打开方式。
- 外部功能可以直接打开高级 → AI 连接或高级 → 存储与性能。
- 返回设置首页后保留滚动位置；系统返回键与页面返回键语义一致。
- 删除栏目不会让其他栏目索引错位。

## 4.2 “声音与无障碍”实际混入三类设置（已确认）

当前同一子页组合了：

- 声音与触觉反馈；
- 文字大小、高对比、减少动态、易读字体等无障碍能力；
- 外观/主题类选项。

这就是“阅读与感受”难以理解的根本原因。用户不是要改一个标题，而是要把“我喜欢怎样显示/播放”和“我需要怎样访问内容”拆开。

目标归类：

| 目标页面 | 应包含 | 不应包含 |
| --- | --- | --- |
| 外观与声音 | 主题、卡片外观、音量、自动播放、触觉、普通动画偏好 | 字号、高对比、屏幕阅读器辅助、认知减负 |
| 无障碍 | 文字缩放、减少动态、高对比、易读字体、安静反馈、专注模式及效果说明 | 装扮商店、API 配置、调试开关 |

## 4.3 无障碍开关存在“有状态、弱效果”的风险（已确认）

`lib/application/accessibility_provider.dart` 已保存以下设置：

- 文本缩放；
- 减少动态；
- 高对比；
- 易读字体；
- 感官减负/安静反馈；
- 专注模式。

其中一部分已经在应用根节点、声音控制器和底部导航使用，但覆盖并不均匀。例如专注模式目前只影响少数欢迎/导航表现，无法保证复习、AI、Playground、装扮动画和图表都遵守。用户会因此认为开关“没有效果”。

Plan 2 要把无障碍从“保存几个 bool”升级为能力契约：

```dart
abstract interface class AccessibilityCapabilities {
  double get textScale;
  bool get reduceMotion;
  bool get highContrast;
  bool get dyslexiaFriendlyTypography;
  bool get quietFeedback;
  bool get focusMode;
}
```

每个关键组件明确声明并测试自己消费哪些能力，而不是任意读取 Provider。

### 无障碍效果矩阵

| 能力 | 根应用 | 设置 | 复习 | AI | Playground | 装扮 |
| --- | --- | --- | --- | --- | --- | --- |
| 文字缩放 | MediaQuery/主题 | 不截断 | 图表标签降级 | 消息与输入可滚动 | 网格变列表 | 价格/名称可换行 |
| 减少动态 | 关闭过渡 | 页面切换无动画 | 数字/图表不补间 | 流式仍更新但不闪烁 | 无 Hero 动画 | 禁用粒子/光效 |
| 高对比 | 颜色令牌 | 开关边界清楚 | 曲线不用只靠颜色 | 用户/AI 消息可区分 | 可用/禁用不只靠透明度 | 预览提供高对比版 |
| 易读字体 | 全局字体策略 | 即时预览 | 数字保持等宽可读 | 代码/例句例外策略 | 题干完整显示 | 名称不溢出 |
| 安静反馈 | 声音/触觉总闸 | 可试听说明 | 作答不震动/不播音 | 无提示音 | 无成功音效 | 购买无强反馈 |
| 专注模式 | 降低装饰 | 隐藏非必要推荐 | 只保留题目与进度 | 隐藏推荐入口 | 隐藏装饰区 | 不展示动态装扮 |

## 4.4 实验室实际包含会破坏真实状态的作弊操作（已确认）

`lib/views/settings/widgets/settings_fun_section.dart` 当前提供：

- 建立、替换、恢复和删除快照；
- 自动答题；
- 延后全部复习；
- 分数改到极高值；
- 宝石改到极高值；
- 解锁全部成就。

这些操作会修改学习、经济和成就状态，因此不适合作为普通设置中的“趣味实验室”。它还会让后续性能和数据问题难以复现：一份被作弊功能改写的用户状态，可能看起来像调度器、成就或宝石账本故障。

### 退场策略

1. Release/Profile 构建不注册实验室页面，也不显示入口。
2. `autoAnswer` 在迁移时强制关闭；生产代码不再消费该开关。
3. 改分、改宝石、解锁成就只允许测试 fixture 或 debug-only 工具调用，不能存在可被生产路由打开的页面。
4. “延后全部复习”如果有真实产品价值，应另做正式的“休息日/计划调整”设计；本轮不直接迁移。
5. 快照能力如果对诊断仍有价值，迁移为开发者数据检查点，并明确不属于备份。
6. 旧快照不立即物理删除；先标记 legacy，提供一个版本的开发恢复/清理兼容期，再按 TTL 清理。

### 迁移后必须满足

- 普通用户无法通过设置、深链、最近任务或语义路由进入实验室。
- 旧用户升级后自动答题一定是关闭状态。
- 宝石和成就不因为迁移被重置。
- Release 包中不存在“改成 99999”等可触达操作。
- 测试仍可使用显式 fixture builder 建立边界状态，不依赖 UI 作弊入口。

## 4.5 高级页当前几乎等于 Anki 内部参数页（已确认）

`lib/views/settings/widgets/settings_advanced_section.dart` 当前集中展示：

- Anki 智能去解密；
- 捕获延迟；
- 强制禁用 JavaScript；
- System Health；
- Storage/Performance；
- Official Anki 内部导入/诊断入口；
- Lite 阈值等实现级参数。

这会让普通用户把“高级”理解为“Anki 开发者选项”，也使新增 AI Key、存储、诊断时继续堆叠。目标是把高级首页变成跨功能的稳定入口，把旧参数收进“旧版与兼容性”。

## 4.6 Official Anki 内部导入是重复且危险的入口（已确认）

普通 Anki 导入已经由统一流程接管，设置高级页仍暴露 Official 内部导入/诊断，会形成两条用户心智不同、底层所有权也可能不同的导入路径。这与 Plan 1 的“单一导入入口”冲突。

处理方式：

- 普通和高级正式页面删除 Official 内部导入入口。
- 如果 engine 诊断仍需保留，只在 debug developer page 暴露，并使用测试文件或只读探针。
- 路由先保留一个版本的 tombstone：旧深链进入时说明入口已合并，并跳转统一导入页；下一个大版本删除路由。
- 不允许设置搜索、最近访问或旧缓存继续展示该入口。

## 4.7 关于页外链失败是硬编码与静默失败共同导致（已确认）

`lib/views/settings/about_turna_page.dart` 硬编码了旧地址，例如：

- `https://github.com/rshrc/Varnamala`
- 对应 issues、releases、README anchor、GUI、CLI 和文档路径

当前仓库 remote 已不是上述地址。更重要的是，打开逻辑在 `canLaunchUrl` 或 `launchUrl` 失败时没有给用户可靠反馈，所以表面表现就是“很多链接点不了”。

根治需要 `ExternalLinkRegistry`，而不是逐个换字符串：

```dart
enum ExternalLinkId {
  projectHome,
  issueTracker,
  releaseNotes,
  privacyPolicy,
  guiPlatform,
  cliDocs,
}

class ExternalLinkDescriptor {
  final Uri? uri;
  final String label;
  final bool enabled;
  final String? unavailableReason;
}
```

外链注册表必须做到：

1. 只允许 `https` 等批准 scheme。
2. 生产 URL 由一处配置，测试可注入。
3. URL 缺失时入口禁用或隐藏，不渲染伪链接。
4. `launchUrl` 返回 false 或抛错时，显示失败原因，并允许复制地址。
5. GUI 平台迁移提示和关于页使用同一个 `guiPlatform` 定义。
6. 构建/测试检查所有生产链接非空、scheme 合法；联网可达性不作为离线构建硬阻塞。

## 4.8 更新日志版本号存在多个事实来源（已确认）

当前至少有三处版本：

- `pubspec.yaml`：`0.7.0+1`；
- `about_turna_page.dart` fallback：`0.7.0`；
- `assets/changelog.md` 顶部内容曾使用 `1.3.0` 系列，而 `ChangelogPage` fallback 又映射为 `0.7`、`0.6` 等。

因此“安装版本”“资源更新日志版本”和“资源加载失败时的 fallback 版本”会互相矛盾。

目标事实来源：

- 安装版本：只来自 `PackageInfo`，fallback 只允许显示“未知版本”，不能再硬编码发布号。
- 更新日志：资源文件的首个 release id 必须与当前发布策略一致。
- fallback：从同一结构化 release manifest 生成，而不是手写另一份版本列表。
- CI：校验 pubspec 版本、release manifest 当前版本和 changelog 首项。

“使用指南”tab 按需求删除；如果 `assets/quick_start.md` 不再有其他消费者，同时移除 asset 声明、解析器、字符串和测试，避免留下死资源。

## 4.9 装扮内容太少、展示面太窄（已确认）

`lib/domain/cosmetics/avatar_ring.dart` 当前只有三个头像环：一个免费、两个付费。装扮效果主要出现在头像环商店、设置账户预览和少数个人资料头像位置。

用户认为“装扮似乎没有效果”有两层真实原因：

1. 商品维度只有头像边框，选择空间不足。
2. 购买后只在少数表面出现，用户在主要学习流程中感知不到。

此外，`CosmeticProvider` 当前先扣宝石，再分别写解锁和装备偏好。如果扣费成功后偏好写入失败，存在宝石已扣但商品未解锁的风险。异常队列还可能吞掉失败，使 UI 难以解释结果。

这不是简单增加几十个 ring 的问题，需要先建立商品目录、槽位、钱包账本和原子购买语义。

## 4.10 API Key 当前存入普通偏好，且配置逐字符写入（已确认，P0）

`AiEngineConfigHolder` 当前序列化完整 `AiEngineConfig`，其中包含 API Key，并写入 SharedPreferences。已有的凭据抽象只提供内存级 fallback，当前行为与“安全存储”文档承诺不一致。

同时，`AiApiConfigPage` 的文本框在 `onChanged` 中调用 `_commitDraft()`；它会更新 Holder 并触发异步偏好写入。因为配置对象未提供可靠的值相等判断，即使内容没有语义变化，也很难跳过更新。用户输入 Base URL、模型或 Key 时，每一个字符都可能触发：

```text
TextField onChanged
  -> setState / 构建新 config
  -> holder.updateConfig
  -> notifyListeners
  -> JSON encode
  -> SharedPreferences setString
```

这既是配置页卡顿与写放大的明确成因，也是敏感数据落入普通偏好的安全问题。必须在 Plan 2 优先解决，不能等 Plan 3 AI 页面优化。

---

## 5. Plan 2 目标信息架构

## 5.1 设置首页

```text
设置
├─ 账户与个性化
│  ├─ 账户资料
│  ├─ 头像与装扮
│  └─ 宝石记录
├─ 学习
│  ├─ 每日目标
│  ├─ 复习偏好
│  └─ 提醒
├─ 外观与声音
│  ├─ 主题与显示
│  ├─ 声音
│  └─ 触觉反馈
├─ 无障碍
│  ├─ 阅读
│  ├─ 动态与反馈
│  └─ 专注与认知减负
├─ 数据与备份
│  ├─ 导出/恢复
│  ├─ 远程备份
│  └─ 数据重置
├─ 高级
│  ├─ AI 连接
│  ├─ 存储与性能
│  ├─ 系统健康与诊断
│  └─ 旧版与兼容性
└─ 关于 Turna
   ├─ 关于
   └─ 更新日志
```

首页明确删除：

- AI 工具；
- 趣味实验室；
- Official Anki 内部导入；
- 使用指南。

### 5.2 首页分组与排序

建议顺序如下：

| 分组 | 页面 | 理由 |
| --- | --- | --- |
| 个人 | 账户与个性化 | 高频身份、装扮和宝石入口 |
| 学习体验 | 学习、外观与声音、无障碍 | 普通用户最常调整 |
| 数据与系统 | 数据与备份、高级 | 风险较高、频率较低 |
| 产品 | 关于 Turna | 版本、日志和正式外链 |

首页不再用“主功能/数据与关于/实验室/高级”这种实现导向分组。

### 5.3 导航实现

建立强类型目标：

```dart
enum SettingsDestination {
  account,
  learning,
  appearanceAndSound,
  accessibility,
  dataAndBackup,
  advanced,
  about,
}
```

推荐以 AutoRoute 子路由实现。若当前 Home tab 约束使嵌套路由一次改造风险过高，可先使用强类型本地 navigator，但必须预留统一方法：

```dart
Future<void> openSettings(
  BuildContext context,
  SettingsDestination destination, {
  String? anchor,
});
```

禁止继续让业务方写 `category = 3`。

### 5.4 页面通用规则

- 一级页面最多 4 个区块；实现级参数进入二级页面。
- 危险操作不和普通 switch 混在一个 Card 中。
- 每项副标题说明“改变什么”，不能只是重复标题。
- 开关变化立即生效；文本/凭据类配置使用显式保存或防抖提交。
- 页面离开前处理未保存草稿，不能静默丢失。
- 每个页面支持文字放大 200%、横屏和桌面窄窗口。
- 列表使用稳定 key；不因 Provider 任意通知滚回顶部。

---

## 6. 高级页详细设计

## 6.1 高级首页

高级首页只展示四个稳定入口：

| 入口 | 摘要 | 风险级别 |
| --- | --- | --- |
| AI 连接 | 服务商、凭据、模型和连接测试 | 中：涉及密钥和网络 |
| 存储与性能 | 空间分类、缓存、垃圾和运行诊断 | 中：包含清理操作 |
| 系统健康与诊断 | 数据库状态、功能状态、导出诊断摘要 | 低/中 |
| 旧版与兼容性 | Anki 渲染、解密、JS、Lite 等旧参数 | 高：可能影响内容显示 |

首次打开高级页显示一次说明：高级设置可能影响兼容性，但不使用阻断式弹窗。只有真正危险的具体操作才二次确认。

## 6.2 AI 连接页

页面层级：

```text
AI 连接
├─ 服务商（预设）
├─ API Key（安全存储状态）
├─ 模型
├─ 自定义连接（折叠）
│  └─ Base URL
├─ 测试连接
└─ 清除凭据
```

具体规则：

- API Key 默认遮挡；只有按住或短时显示，不在截图/日志/诊断导出中出现。
- 页面初始化只显示“已配置/未配置”和末尾少量字符，不能把完整 Key 回填到普通 TextField。
- 修改使用草稿；点击保存后一次提交。若保留自动保存，至少 500 ms 防抖，且 Key 与普通字段分开写。
- 连接测试使用当前草稿，但不会先永久保存失败配置。
- 测试状态区分 DNS、TLS、鉴权、模型不存在、限流、超时和响应格式错误。
- 自定义 Base URL 默认折叠，并做 HTTPS、host、尾斜杠规范化；开发环境可允许本地 HTTP，生产默认拒绝。
- “清除凭据”只删除 Key，不删除服务商和模型偏好；另提供“恢复连接默认值”。
- 回复语言、解释深度、是否允许揭示答案、是否注入学习上下文不属于连接配置，移动到 AI 助手偏好页。
- strict schema、缓存调试和统计不在普通 AI 连接页，放诊断或旧版页。

## 6.3 凭据安全迁移

目标存储分层：

| 数据 | 存储位置 | 备份/导出 |
| --- | --- | --- |
| provider、model、Base URL | 普通偏好 | 可导出 |
| API Key | Android Keystore/平台安全存储 | 永不导出 |
| 会话 token | 内存或平台安全存储，按协议 | 永不导出 |
| 连接测试结果 | 内存，短 TTL | 不导出 |

迁移必须是可恢复的两阶段过程：

```text
读取旧 aiEngineConfig
  -> 若无 plaintext key：完成
  -> 写入 SecureCredentialStore
  -> 读回并验证存在
  -> 写入不含 key 的新 config
  -> 再删除旧 plaintext 字段
  -> 写 credentialMigrationVersion
```

任何一步失败时：

- 不提前删除旧 Key，避免用户凭据丢失；
- UI 提示“凭据安全迁移尚未完成”，允许重试；
- 日志只能记录阶段和错误类型，不能记录 Key、header 或完整配置 JSON；
- 成功后用测试确认 SharedPreferences、备份文件和诊断包均不含 Key。

Web 或没有持久安全存储的平台：

- 只提供本次会话保存；
- UI 明确说明关闭应用后需要重新输入；
- 不能悄悄回退到普通偏好。

## 6.4 存储与性能页

消费 Plan 1 的 `StorageInventoryService`，按用户可理解的口径展示：

```text
存储与性能
├─ 总占用
│  ├─ 学习数据
│  ├─ Anki 内容与媒体
│  ├─ 可再生成缓存
│  ├─ 日志/临时文件
│  └─ 可回收/待清理
├─ 安全清理
│  ├─ 图片/预渲染缓存
│  ├─ AI 响应缓存
│  └─ 过期日志/临时文件
├─ 数据问题
│  ├─ 孤儿 owner
│  ├─ 待重试删除
│  └─ 重复内容（只报告）
└─ 运行诊断
   ├─ 当前内存快照
   ├─ 最近慢页面/慢查询
   └─ 导出诊断摘要
```

必须坚持：

- “缓存”是可再生成数据；“垃圾”是经所有权证明可删除的数据；“重复”不一定是垃圾。
- 总磁盘占用和当前运行内存分开显示，不能相加。
- 运行内存显示采样时间和口径；GC 后下降不代表文件已清理。
- 默认一键清理只处理可再生成缓存和过期临时文件。
- 孤儿 Anki 数据必须走 Plan 1 清理事务，不能直接删目录或表行。
- SQLite freelist/WAL 只显示为“可回收数据库空间”；VACUUM/Checkpoint 要有电量、空间和中断策略。
- 扫描超过 100 ms 时放后台 isolate/原生线程，分批返回并可取消。

## 6.5 系统健康与诊断

建议只读信息：

- 应用版本、构建号、平台和数据库 schema 版本；
- 当前课程 scope、复习 owner 类型、Official engine 可用性；
- 上次备份、上次成功存储扫描、上次 pending cleanup 重试；
- AI 连接是否配置、凭据是否安全存储，不显示实际 Key；
- 最近 20 条结构化错误摘要；
- 慢查询计数、帧超时计数、缓存命中率和写失败计数；
- “复制诊断摘要”，默认脱敏 sourcePath、用户名、题目正文、API Key、URL query。

诊断页不是隐藏设置集合。可以执行的动作必须少且显式：重新扫描、重试 pending cleanup、复制摘要、恢复安全默认值。

## 6.6 旧版与兼容性页

迁入当前高级页的旧能力，但重新分组：

```text
旧版与兼容性
├─ Anki 显示兼容
│  ├─ 强制禁用 JavaScript
│  ├─ 捕获/渲染延迟
│  └─ Lite 渲染阈值
├─ 内容恢复
│  └─ 智能去解密（若仍有真实用途）
├─ 实验性兼容开关
└─ 恢复兼容性默认值
```

每个开关必须有：

- 适用症状；
- 可能副作用；
- 当前值与默认值；
- 是否需要重新打开卡片/重启；
- 一键恢复默认。

不迁入：Official 内部导入、改分、自动答题、改宝石、解锁成就。

---

## 7. 关于、更新日志与外链详细设计

## 7.1 页面结构

关于页只保留两个 tab：

1. 关于：产品简介、版本、许可证、隐私、项目/反馈等已配置链接。
2. 更新日志：离线 changelog、复制功能和当前版本定位。

设置首页的“关于 Turna”卡片与关于页内部避免重复。推荐设置首页只显示一个“关于 Turna”入口；版本号作为右侧摘要，不再额外放独立“版本”和“更新日志”行。

## 7.2 版本模型

```dart
class AppBuildInfo {
  final String versionName;
  final String buildNumber;
  final String channel;
  final String commit;
}

class ReleaseManifest {
  final String currentVersion;
  final List<ReleaseEntry> releases;
}
```

规则：

- UI 版本来自 `PackageInfo`；测试注入 fake。
- changelog asset 解析失败时从同一 manifest 构建 fallback。
- 发布脚本检查 semantic version 格式。
- `currentVersion` 与 pubspec 的 versionName 是否必须完全相等，由发布策略决定；若允许小版本聚合，必须写成明确映射，不能手工“降级”编号。
- 更新日志当前版本条目高亮；不存在对应条目时显示“本构建暂无单独说明”，不能冒充其他版本。

## 7.3 外链打开状态机

```text
未配置 -> 禁用 + 原因
已配置 -> 校验 scheme
         -> 不合法：禁用 + 诊断记录
         -> 合法：launch
                  -> 成功
                  -> false/异常：提示失败 + 复制链接
```

Widget 测试必须覆盖未配置、非法 scheme、launcher 返回 false、抛异常和成功五种状态。

---

## 8. 装扮与宝石体系详细设计

## 8.1 产品原则

1. 只改变表达和反馈，不改变学习结果。
2. 购买前可以完整预览，购买后在明确列出的界面可见。
3. 所有动态商品都提供减少动态版本。
4. 商品目录可扩充，但离线应用不能依赖远端目录才能解释本地已购商品。
5. 宝石收入与支出有账本、来源、时间和幂等 id。
6. 失败事务可恢复，不允许扣费成功但商品丢失。
7. 旧版三个头像环和已有余额无损迁移。

## 8.2 第一阶段商品槽位

| 槽位 | 示例 | 主要展示面 | 动效限制 |
| --- | --- | --- | --- |
| 头像环 | 芦苇、湖面、晚霞 | 设置、个人页、完成页、排行榜/成就摘要 | 可静态化 |
| 个人页主题 | 湿地晨雾、夜湖 | 个人首页背景与统计卡 | 不降低对比度 |
| 卡片背板 | 纸张、芦苇纹理、极简 | 普通课程卡片；Official HTML 卡只装饰外框 | 不覆盖卡片正文 |
| 完成效果 | 鹤羽、涟漪、星点 | 课程/复习完成页 | 减少动态时替换成静态徽章 |
| 声音包 | 木鱼、清水、静音主题 | 成功/完成反馈 | 遵守安静反馈 |
| 吉祥物配件 | 围巾、书包、帽子 | 首页/个人页吉祥物 | 无关卡提示作用 |
| 连续学习保护 | 单次保护券 | 连续学习状态页 | 不修改真实复习数据 |

第一版无需一次实现全部素材。建议先交付：头像环扩充、个人页主题、完成效果、连续保护券，验证目录和账本模型后再扩展。

## 8.3 展示契约

每个商品定义 `surfaces`，测试确保至少一个主流程表面消费：

```dart
class CosmeticItem {
  final String id;
  final CosmeticSlot slot;
  final int catalogVersion;
  final int price;
  final Set<CosmeticSurface> surfaces;
  final AccessibilityVariant accessibility;
}
```

不允许“目录可购买但任何页面都不使用”的商品进入 release catalog。

## 8.4 钱包账本与原子购买

目标模型：

```text
gem_ledger
  transaction_id  UNIQUE
  event_id        UNIQUE nullable
  kind            earn | spend | refund | migration | adjustment
  amount          signed integer
  reason
  item_id         nullable
  created_at
  status          pending | committed | rolled_back

cosmetic_entitlements
  item_id         PRIMARY KEY
  acquired_by_transaction
  acquired_at
  catalog_version
```

购买事务：

```text
BEGIN
  校验 item 存在且可购买
  校验 entitlement 不存在
  计算账本余额并校验足够
  INSERT spend ledger（幂等 transaction_id）
  INSERT entitlement
COMMIT
刷新钱包/装扮只读投影
```

若短期仍使用 SharedPreferences，必须先实现可恢复 purchase journal：pending -> 扣费 -> entitlement -> committed；启动时对 pending 做补发或退款。但推荐直接使用现有数据库事务，避免继续增加跨 key 一致性负担。

## 8.5 连续学习保护规则

- 只能在用户错过一天后消耗，或按明确规则自动消耗。
- 只保护连续天数显示，不生成 StudyLog，不改变 reviewedAt，不推迟卡片 dueAt。
- 每个自然月有持有/使用上限，价格透明。
- 设置中可以关闭自动使用。
- 状态页显示“本次连续记录由保护券保留”。
- 诊断和成就判定能区分真实连续与保护连续；是否允许特定连续成就由产品规则明确，默认不伪造学习量成就。

## 8.6 旧数据迁移

1. 读取现有 gems 余额，写一条 `migration_opening_balance`，幂等 id 固定。
2. 将已解锁头像环写入 entitlement；未知 id 保留为 legacy entitlement，不丢失。
3. 将当前装备 id 写入各 slot；商品不存在则暂时回退默认，但保留原 id 供未来恢复。
4. 校验账本余额等于旧余额后再标记迁移完成。
5. 迁移期间商店只读，避免购买和迁移并发。

---

## 9. Plan 2 数据与偏好迁移清单

建议新增统一迁移版本 `settingsSchemaVersion`，按顺序执行：

| 步骤 | 迁移 | 失败策略 |
| --- | --- | --- |
| S2-M01 | 关闭并废弃 autoAnswer | 重试；Release 启动仍强制 false |
| S2-M02 | 标记 Fun Lab snapshot 为 legacy | 不删除，记录待清理 |
| S2-M03 | 迁移 API Key 到安全存储 | 保留旧值并提示，绝不静默丢失 |
| S2-M04 | 从普通 AI config 删除 plaintext key | 仅在安全写入验证后执行 |
| S2-M05 | 拆分外观/声音/无障碍键 | 默认保持用户现有效果 |
| S2-M06 | 建立宝石 opening balance | 事务失败则商店保持只读 |
| S2-M07 | 迁移头像环 entitlement/equipped | 未知 id 保留 |
| S2-M08 | 删除旧设置入口的最近访问记录 | 旧 route 走 tombstone |

迁移基础要求：

- 每步可重复执行；
- 每步单独记版本或 completion marker；
- 不用“全部成功”一个 bool 掩盖中间状态；
- 迁移日志脱敏；
- 测试覆盖从至少最近两个公开版本升级；
- 备份恢复后重新运行必要的规范化，而不重复增加余额或 entitlement。

---

## 10. Plan 2 分阶段实施

## Phase P2-0：基线、冻结与保护网

任务：

- 为现有八个设置栏目、深链和偏好键建立 inventory。
- 记录设置页首次打开、切页、返回、文字输入和存储扫描耗时。
- 为 API Key 普通偏好泄漏建立失败测试，先让测试红。
- 为旧链接、版本一致性、实验室 Release 不可达建立契约测试。
- 对当前宝石余额、解锁、装备创建迁移 fixture。

出口条件：

- 所有旧入口都有“迁移、tombstone 或删除”去向。
- 敏感凭据测试能识别 prefs/导出/诊断中的明文。
- 有 Android 中低端基线和桌面基线，不以开发机主观感受代替。

## Phase P2-1：强类型设置导航与首页重排

任务：

- 引入 `SettingsDestination` 与统一打开 API。
- 新建七个一级目的地并迁移现有 section。
- 拆分外观与声音、无障碍。
- 删除设置首页 AI 工具和实验室栏目。
- 为旧整数入口/测试提供短期适配器，然后删除整数 switch。
- 保存首页和子页滚动状态。

出口条件：

- 首页结构与 §5 一致。
- 从 AI 未配置提示可直接到高级 → AI 连接。
- 从存储警告可直接到高级 → 存储与性能。
- 系统返回、深链和 tab 切换测试通过。

## Phase P2-2：实验室退场与旧路由 tombstone

任务：

- Release/Profile 不注册实验室 UI。
- 迁移 autoAnswer 为 false，并删除生产消费点。
- 将 fixture/作弊能力移动到 debug/test 支持代码。
- 给旧实验室和 Official 内部导入 route 添加一版 tombstone。
- 标记 legacy snapshot 并提供开发清理。

出口条件：

- Release route 表中无可执行作弊页面。
- 旧深链不会崩溃，也不会执行旧操作。
- 升级前后真实学习数据、余额和成就保持一致。

## Phase P2-3：高级首页与兼容性二级页

任务：

- 实现高级四入口。
- 把现有 Anki 参数迁移到“旧版与兼容性”。
- 为每个旧参数添加症状、副作用、默认值、重启需求。
- 移除 Official 内部导入。
- 增加恢复兼容性默认值。

出口条件：

- 高级首页不出现内部 engine/implementation 术语堆叠。
- 普通用户可以理解每个一级入口。
- 兼容性恢复默认不会删除用户数据。

## Phase P2-4：AI 连接精简与凭据安全

任务：

- 接入平台安全存储；不支持平台使用会话存储。
- 完成 plaintext Key 两阶段迁移。
- 将 API 配置从逐字符持久化改为草稿 + 保存或防抖。
- 精简配置项并将解释偏好移出。
- 完成连接错误分类、清除凭据和恢复默认。

出口条件：

- SharedPreferences、备份、诊断导出和普通日志中找不到 Key。
- 输入 100 个字符不会产生 100 次持久写。
- 连接测试不修改已保存可用配置，除非用户确认保存。
- 应用重启后可读取安全凭据；不支持平台明确说明会话限制。

## Phase P2-5：无障碍能力契约

任务：

- 建立能力接口、统一主题令牌和组件审计表。
- 覆盖设置、Home、复习、AI、Playground、完成页、装扮预览。
- 为高对比、减少动态、200% 字号和屏幕阅读器添加测试。
- 给弱效果开关补齐消费面；无法兑现的开关先删除或标 Beta。

出口条件：

- §4.3 矩阵每格有实现或明确“不适用”理由。
- 200% 字号无关键操作截断。
- 减少动态下无必须等待的装饰动画。
- TalkBack/语义测试可读出按钮用途、状态和图表摘要。

## Phase P2-6：关于、版本与外链

任务：

- 实现外链注册表。
- 配置正式链接；缺失链接按不可用策略处理。
- 删除使用指南 tab 和无消费者资源。
- 统一 AppBuildInfo/ReleaseManifest。
- 添加版本和外链 CI 检查。

出口条件：

- 不再硬编码旧仓库 URL。
- 链接失败有用户反馈和复制兜底。
- 安装版本与当前更新日志关系明确。
- 关于页只保留两个 tab，且无重复入口。

## Phase P2-7：装扮目录、账本与首批商品

任务：

- 建立 catalog、slot、surface、entitlement、ledger。
- 迁移余额和三个旧头像环。
- 交付至少三类可见商品和连续保护券。
- 让已装备装扮在定义表面生效。
- 增加购买恢复、退款/补发和无障碍变体。

出口条件：

- 断电/异常注入不能造成永久“扣费无商品”。
- 重复点击不会重复扣费。
- 每个上架商品至少有一个主流程展示面。
- 装扮不改变学习数据与调度。

## Phase P2-8：清理、灰度与发布

任务：

- 删除 tombstone 到期后的旧 route、字符串和死资源。
- 检查偏好键与 Provider 无剩余消费者。
- 完成 Android/桌面回归、无障碍与迁移演练。
- 灰度观察迁移失败、链接失败、凭据错误、购买恢复和页面耗时。

出口条件：

- Plan 2 Definition of Done 全部满足。
- 诊断能解释迁移失败而不泄露内容。
- 有回滚策略且不会把安全存储中的 Key 再写回普通偏好。

---

## 11. Plan 2 测试矩阵

| 层级 | 重点 |
| --- | --- |
| Unit | route 映射、偏好迁移、URL 校验、版本解析、钱包事务、余额幂等、无障碍能力组合 |
| Widget | 设置首页排序、深链返回、200% 字号、危险操作确认、Key 遮挡、链接失败、商品预览 |
| Integration | 旧版本升级、安全 Key 迁移、备份恢复后迁移、购买中断恢复、清理后重启 |
| Golden | 浅/深色、高对比、200% 字号、手机窄屏、桌面窄窗口、减少动态静态态 |
| Security | prefs/备份/日志/诊断无 Key，剪贴板提示，截图遮挡，自定义 URL scheme 限制 |
| Performance | 设置首次打开、类别切换、输入延迟、存储扫描、商品列表滚动 |

### Plan 2 建议验收预算

以下是实施前的临时预算，Phase P2-0 采集基线后可按基准机型收紧，但不能无证据放宽：

- 设置首页 warm 打开到可交互：P95 ≤ 300 ms。
- 普通类别切换：P95 ≤ 200 ms，过程中不出现整页空白 spinner。
- 文本输入 UI 响应：P95 ≤ 50 ms；持久化不阻塞输入帧。
- 简单存储摘要：≤ 300 ms；深度扫描后台执行并在 500 ms 内显示进度态。
- 列表滚动的 build/raster 帧在 60 Hz 设备目标下绝大多数 ≤ 16.7 ms；以 Flutter profile 数据为准。
- API Key 迁移失败率、宝石迁移不一致率：release gate 必须为 0（测试 fixture），灰度实际错误必须可恢复。

---

## 12. Plan 2 Definition of Done

- [x] 设置首页只有七个正式目的地，无 AI 工具和实验室栏目。（2026-08-23）
- [x] 外观与声音、无障碍完成拆分。（2026-08-23）
- [x] 所有设置目的地具有强类型身份和可测试导航。（SettingsDestination + SettingsNavController + openSettings；settings_category_list_test）
- [x] 普通 Release 用户无法执行实验室作弊能力。（kDebugMode 门禁 + autoAnswer release 强制关闭 + 生产消费点删除；fun_provider）
- [x] 高级首页形成 AI 连接、存储与性能、系统健康、旧版与兼容性四入口。（settings_advanced_section.dart）
- [x] Official Anki 内部导入从正式设置中删除。（迁入 debug-only 开发者实验室）
- [x] AI 配置输入不再逐字符持久写。（草稿 + 500ms 防抖 + 显式保存 + dispose 冲洗；ai_api_config_page_test）
- [x] API Key 不进入普通偏好、备份、日志或诊断。（两阶段迁移 + 分离持久化 + 备份既有 _stripApiKey 双保险；ai_credential_migration_test 7 例全过）
- [x] 关于页使用指南删除，版本单一事实来源建立。（quick_start 资源/解析器/字符串全删；AppBuildInfo 无硬编码 fallback；ReleaseManifest 单一来源；changelog.md 重编号对齐 0.x）
- [x] 失效/未配置链接不会伪装成可用，打开失败有反馈。（ExternalLinkRegistry：未配置禁用+原因、scheme 校验、失败+复制兜底；about_turna_page_test）
- [~] 每个保留的无障碍开关都有跨页面效果和测试。（能力契约 AccessibilityCapabilities + provider 实现 + 测试已建立；§4.3 矩阵各表面逐一消费审计为后续项）
- [x] 宝石账本幂等，购买具备原子性或可恢复性。（schema v19 gem_ledger + cosmetic_entitlements，事务购买 + 幂等迁移；gem_ledger_test 6 例全过）
- [ ] 至少三类装扮在主流程中真实可见。（目录仍为 3 个头像环；槽位/表面扩充为后续轮次）
- [ ] 连续保护不修改真实复习记录、到期时间和学习量。（保护券产品未实施——账本模型已可承载，规则见 §8.5）
- [ ] Android 中低端设备达成基线，桌面端无功能回退。（需真机基准，见 §24/§35）

---

# 第二部分：Plan 3——复习进度、AI 助手、Playground 与全局性能

## 13. Plan 3 的目标与非目标

### 13.1 目标

1. 把复习进度首页从“计算密集的科学统计页”重做为快速、清楚、可行动的今日学习仪表板。
2. 把热力图、记忆曲线等深度统计移到二级洞察页，并通过聚合查询避免全量加载。
3. 让 AI 助手适配 Plan 1 的新 Anki 卡片识别、展示与 owner/source 设置。
4. 删除移动端内容创作能力，给出明确的 GUI 平台迁移说明。
5. 将轻量 AI 练习入口放进 Playground，避免 AI Hub、Play Hub、设置和 Playground 四处重复。
6. 消除 AI 流式输出逐分片重建整页、滚动动画排队、页面退出后请求继续等卡顿路径。
7. 优化 Playground 题源分析和模式计数，避免重复扫描、顺序加载和无效重算。
8. 建立全应用性能基线、数据修订号、慢查询与帧监控，定位“整体卡卡的”真实来源。

### 13.2 非目标

- 不在移动端重新实现 GUI 课程编辑器。
- 不让 Playground 自动调用 AI，也不要求配置 AI 才能做普通练习。
- 不在首页一次性绘制完整年度热力图和所有科学曲线。
- 不为“看起来实时”而每个 token 都刷新整棵 Widget tree。
- 不在没有 profile 证据时把所有 Provider 重写成另一种状态管理框架。
- 不把系统 RSS、Dart heap、磁盘缓存和数据库空间合成一个没有意义的“垃圾总量”。
- 不用清理缓存掩盖数据重复；Anki owner 和孤儿治理仍以 Plan 1 为准。

---

## 14. 复习进度页：当前成因审计

## 14.1 同一请求重复构建全量卡片列表（已确认）

`lib/application/review_progress_provider.dart` 的 `snapshot()` 先调用 `_allTagged()`，随后 `listSources()` 又调用一次 `_allTagged()`。该方法会遍历 SRS 与 Grammar 的完整 state，并为每张卡构造 `_TaggedCard`。

这意味着一次页面加载至少先做两次全量卡片分类。数据量小时不明显，Anki 导入后卡片数快速增长，开销会线性放大，并制造大量短生命周期对象，增加 GC 压力。

修复不应只把第二次调用结果传进去，而应让数据层直接提供 source-aware 聚合，首页不再需要把所有卡片实体物化到 Dart。

## 14.2 每次筛选读取完整复习事件表（已确认）

当前进度 Provider 调用 `ReviewHistoryDao.allEvents()`，DAO 会读取并排序全部历史事件。随后页面逻辑才在 Dart 中按 card id 和 7/30/90 天范围筛选。

实际代价：

```text
任意筛选变化
  -> SELECT 全部 review events ORDER BY ...
  -> 创建完整 Dart event list
  -> 创建 filtered card id set
  -> Dart where 时间范围和 card id
  -> 再构造曲线桶
```

随着历史增长，即使用户只看近 7 天，也要承担全历史 I/O、解码、分配和排序成本。这是复习进度卡顿的首要已确认成因。

## 14.3 按来源统计存在重复扫描，复杂度随来源数放大（已确认）

当前实现先构造 `forSources`，随后对每个 source 再筛选卡片、聚合成熟度/记忆率，并扫描事件计算 review 数。粗略复杂度接近：

```text
O(C + E) 基础加载
+ O(S × C) 来源卡片筛选
+ O(S × E) 来源事件计数
+ 每次 aggregate 的 FSRS/记忆率计算
```

其中：

- `C` 为卡片数；
- `E` 为复习事件数；
- `S` 为课程/语法/Anki 导入来源数。

当用户导入多个 Anki 包时，来源数增加会让性能不再只是线性随数据增长。

## 14.4 来源识别仍依赖 Legacy wordId 规则（已确认）

当前 Anki 来源主要通过 `anki-<importId>-c...` 前缀推断。这只覆盖 Legacy 标识形式，Official Anki 的调度与结果未必使用同样的 `wordId`，可能造成：

- Official 卡没有出现在统计中；
- 被错误归入普通课程；
- 牌组名称和 owner 不一致；
- 删除/重导后统计留有不可解释的来源。

Plan 3 必须消费 Plan 1 的稳定 `sourceKind/sourceId/ownerId`，禁止继续从字符串前缀猜所有权。

## 14.5 空数据可能显示成 100% 记忆率（已确认）

当前聚合在没有 tracked card 时可能返回 `currentRetention = 1.0`。这在数学防除零上方便，但产品上会让新用户看到“100%”，误以为已经产生复习数据。

目标：无样本使用 nullable 指标或明确 empty state，显示“暂无数据”，而不是 0% 或 100%。

## 14.6 筛选会替换 Future，页面容易闪回整页加载态（已确认）

`lib/views/review/review_progress_page.dart` 在筛选变化时创建新 Future。初始或刷新状态使用居中的整页 spinner，旧数据不保留。快速切换筛选时会经历：

```text
已有数据
 -> 用户点筛选
 -> 丢弃当前 snapshot
 -> 整页 spinner
 -> 新 snapshot
```

这会放大真实查询延迟，让界面显得比后台工作更卡。目标是 stale-while-revalidate：保留旧快照，局部显示刷新状态，只有首次无缓存才用骨架屏。

## 14.7 下拉刷新没有等待实际加载完成（已确认）

当前 `onRefresh: () async => _reload()` 调用一个返回 `void` 的重载方法，因此 RefreshIndicator 的 Future 可能立即完成，而数据仍在后台加载。用户看到刷新动作结束却没有新数据，容易重复触发。

目标 API 必须返回被实际查询完成的 `Future<ReviewDashboardSnapshot>`。

## 14.8 页面信息优先级与用户任务不匹配（产品成因）

当前页面首先展示密集筛选、六个 KPI、曲线和多组统计，用户最需要的“今天还要学多少、现在能否开始、是否逾期”没有成为第一视觉层。`StudyStatsSection` 还使用独立 Future 和全局统计，与进度页的筛选口径可能不同，造成视觉上像同一统计、实际不是同一范围。

因此必须同时重做数据合同与视觉层级；只优化查询不会解决理解成本，只换 UI 不会解决卡顿。

---

## 15. 复习进度目标体验

## 15.1 一级页：“复习概览”

```text
┌──────────────────────────────────────┐
│ 今日复习                       8 月 23 日 │
│  42 / 60   ███████████░░░░  70%       │
│  预计还需 12 分钟        [继续复习]       │
└──────────────────────────────────────┘

┌────────┐ ┌────────┐ ┌────────┐
│ 待复习 28 │ │ 新卡 12  │ │ 逾期 4   │
└────────┘ └────────┘ └────────┘

连续学习  17 天       本周  5 / 7 天
[近 7 日轻量柱状图，不加载全年热力图]

今天
学习时间 24 分钟   准确率 86%
完成 42 张         重新学习 6 张

课程与牌组
土耳其语 A1       18 待复习      >
Anki · Vocabulary 10 待复习      >
语法               4 待复习      >

[查看学习洞察]
```

### 首页交互规则

- “继续复习”是主操作；如果没有到期卡，显示“开始新卡”或“今日已完成”。
- 逾期数为 0 时降低视觉权重，不用红色占据主屏。
- 今日目标为用户设置；没有目标时给轻量建议，不用 0/0。
- 预计时间来自最近样本中位数，不足样本时隐藏。
- 近 7 日图只加载 7 个聚合点，提供文本语义摘要。
- 课程与牌组默认显示前 5 个，按需要复习数和最近使用排序；其余进入完整来源页。
- 首页默认统计全局今日状态，不让复杂筛选挡在首屏前。
- 下拉刷新必须等待同一个 repository Future；刷新时保留数据。

## 15.2 二级页：“学习洞察”

包含：

- 30/90/365 日热力图；
- 记忆保持曲线；
- 新卡/年轻/成熟/疑难卡分布；
- 时间、准确率、复习量趋势；
- 来源、卡片类型、时间范围筛选；
- 指标解释与无数据说明。

二级页允许更重，但仍不能读取全历史实体。图表查询返回固定桶数：

- 7/30 日：按日；
- 90/365 日：按日或周；
- 全部：按月，或分页选择年份；
- 曲线：固定 interval buckets；
- 来源列表：分页或限制 Top N + 其他。

## 15.3 来源详情页

点击课程/牌组后展示：

- 当前 due/new/overdue；
- 今日完成、时间、准确率；
- 最近 7/30 日趋势；
- 开始该来源复习；
- Anki 来源显示导入名称和 owner 状态，但不暴露内部 import id。

如果 source 已删除但历史仍保留，显示“已删除来源”，不能把历史强行归入当前课程。

---

## 16. 复习统计目标数据架构

## 16.1 单一快照合同

```dart
class ReviewDashboardSnapshot {
  final DateTime generatedAt;
  final int dataRevision;
  final TodayProgress today;
  final DueSummary due;
  final StreakSummary streak;
  final List<DailyActivityPoint> last7Days;
  final StudyQuality todayQuality;
  final List<ReviewSourceSummary> sources;
  final bool isStale;
}
```

首页只订阅这一份一致快照。不要再由 `ReviewProgressProvider`、`StudyStatsSection`、`MemoryCurveProvider` 各自读取不同范围后拼在屏幕上。

### 口径要求

- `today` 使用用户本地日界线和明确 timezone。
- `due` 使用调度器的统一 now/cutoff。
- `accuracy` 明确是首次答案准确率、最终答案准确率还是 rating 分布；建议默认首次答案。
- `studyTime` 排除后台停留和超长异常会话。
- `streak` 使用 StudyLog/日聚合，保护券状态单独标注。
- filtered 与 global 指标不能在同一卡片中无标签混用。

## 16.2 来源身份

统一使用：

```dart
class LearningSourceRef {
  final LearningSourceKind kind; // course, grammar, ankiLegacy, ankiOfficial
  final String sourceId;
  final String ownerId;
  final String displayName;
  final bool active;
}
```

- 来源身份在写入卡片/事件时保存，不在查询时解析 `wordId`。
- 历史事件保存 source snapshot 或可解析的稳定 source ref。
- Plan 1 删除 source 后可保留历史标签，但 active=false。
- Legacy/Official 的显示名称来自统一 inventory/catalog projection。

## 16.3 查询接口

```dart
abstract interface class ReviewDashboardRepository {
  Future<ReviewDashboardSnapshot> loadDashboard({
    required DateTime day,
    required ReviewDashboardFilter filter,
    required bool forceRefresh,
  });

  Future<LearningInsightsSnapshot> loadInsights(
    InsightsQuery query,
  );

  Stream<int> watchDataRevision();
}
```

首页的 SQL/存储层查询目标：

- 按 dueAt 和 source 聚合当前队列；
- 按 reviewedAt 的日范围聚合今日事件；
- 从 daily aggregate 获取 7 日与 streak；
- 单次 group by 生成来源摘要；
- 不返回卡片正文、不返回全部 event list。

## 16.4 索引与聚合表

具体表名以当前 schema 为准，但能力上需要：

| 查询 | 所需索引/投影 |
| --- | --- |
| 今日到期/逾期 | `(owner_state, due_at)` 或 `(source_id, due_at)` |
| 今日完成 | `(reviewed_at)`、必要时 `(source_id, reviewed_at)` |
| 单卡历史 | `(card_id, reviewed_at)` |
| 来源摘要 | 稳定 source_id 列，不从字符串解析 |
| 近 N 日趋势 | `daily_review_stats(day, source_id, ...)` |
| streak | `daily_review_stats(day)` 连续日查询 |

推荐新增/统一每日聚合：

```text
daily_review_stats
  local_day
  source_kind
  source_id
  reviewed_count
  new_count
  relearn_count
  correct_first_count
  answer_time_ms
  active_time_ms
  PRIMARY KEY(local_day, source_kind, source_id)
```

写入复习事件的同一事务中 upsert 当日聚合。若现有数据需要回填：

- 后台按时间窗口分批；
- 记录 backfill cursor；
- 可中断、可重复；
- 回填期间首页可使用有限范围查询，不阻塞启动；
- 完成后比较聚合与原始事件抽样一致性。

## 16.5 数据修订号与缓存

建立 `ReviewDataRevision`：

- 复习事件提交成功后递增；
- 新增/删除卡片、导入/卸载来源后递增；
- 时区/日界线变化使 day-key 失效；
- 只在数据实际提交后递增，不因 Widget rebuild 变化。

缓存 key：

```text
dashboard:<profile>:<localDay>:<filterHash>:<dataRevision>
insights:<profile>:<range>:<source>:<type>:<dataRevision>
```

缓存策略：

- 内存只保留最近少量快照；
- 打开页面先展示同 day 的旧快照，并标记 stale；
- 后台刷新成功原子替换；
- 刷新失败保留旧数据并显示非阻断错误；
- 请求有 generation id，旧请求晚到不能覆盖新筛选；
- 页面 dispose 后取消可取消查询或忽略结果。

## 16.6 空状态与错误状态

| 状态 | UI |
| --- | --- |
| 新用户无卡 | 解释如何添加课程/Anki，不显示 100% |
| 有卡但今天无 due | 显示今日已完成，可进入洞察 |
| 有历史但来源已删 | 来源标“已删除”，历史仍可统计 |
| 聚合回填中 | 展示可用今日数据 + “历史统计整理中” |
| 刷新失败且有缓存 | 保留数据 + 小型重试提示 |
| 首次加载失败无缓存 | 完整错误态 + 诊断 id，不无限 spinner |

---

## 17. 复习页性能与渲染实现

### 17.1 Widget 分区

```text
ReviewDashboardPage
├─ TodayHeroSelector
├─ DueSummarySelector
├─ SevenDayActivitySelector
├─ TodayQualitySelector
├─ SourceListSelector
└─ RefreshStateSelector
```

每区只监听需要的不可变字段；刷新状态变化不应让所有图表和来源卡重建。

### 17.2 列表与图表

- 使用 `CustomScrollView` + sliver，避免多个 shrinkWrap Grid/List 嵌套。
- 来源列表按需构建，超过首屏分页。
- 7 日图使用轻量 painter，并放 `RepaintBoundary`。
- 动画只在数据语义变化且未开启减少动态时执行。
- 图表提供文本替代，如“最近 7 天学习 5 天，共 126 张”。
- 大数字计数不逐个从 0 动画，避免每次刷新产生无意义帧。

### 17.3 加载状态

- 首次无缓存：结构匹配的骨架屏。
- 有缓存刷新：内容保持，AppBar 或局部使用 2–3 px 进度条。
- 筛选切换：保留旧结果并降低透明度的方案仅在高对比可辨识时使用；更推荐固定内容 + 小刷新标记。
- 下拉刷新 Future 必须直到 repository 完成或失败才结束。

### 17.4 可测性能场景

建立固定 fixture：

| 数据集 | 卡片 | 事件 | 来源 | 用途 |
| --- | ---: | ---: | ---: | --- |
| small | 1,000 | 10,000 | 4 | 日常回归 |
| medium | 10,000 | 100,000 | 20 | 中低端主门槛 |
| large | 100,000 | 1,000,000 | 100 | 压力和增长趋势 |

测试记录：查询次数、扫描行数、返回行数、总耗时、Dart 分配、P50/P95 帧、首次可交互时间。首页查询返回量应与图表桶和来源数相关，而不是与全历史事件数等量增长。

---

## 18. AI 与 Playground：当前成因审计

## 18.1 AI 功能入口重复且产品边界冲突（已确认）

当前 AI 能力分散在：

- 设置“AI 工具”；
- Play Hub 的 AI 助手区；
- AI Hub；
- Playground；
- 复习卡片中的 AI 解释/提示。

Play Hub 当前 AI 快捷入口仍指向 AI 愿望/课程创作和教材导入；AI Hub 也有内容创作区域。与此同时 Playground 的八个练习模式大多仍只显示 coming soon。这形成了入口多、真正可执行内容少、产品方向又冲突的体验。

目标边界：

| 表面 | 保留职责 |
| --- | --- |
| 复习页 | 当前卡片解释、提示、针对当前错误追问 |
| AI 助手 | 自由学习问答、错题/薄弱诊断、保存的解释、带学习上下文的会话 |
| Playground | 练习模式 + 三个轻量 AI 语言工具入口 |
| 高级设置 | 只配置 AI 连接，不承载 AI 功能 |
| GUI 平台 | 内容创建、教材导入、课程结构生成与编辑 |

## 18.2 Playground 当前模式重复扫描候选集（已确认）

`lib/views/playground/language_playground_page.dart` 的 `_computeModeCounts()` 遍历八个模式。除单词匹配外，每个模式都会重新：

- `where` 整个候选集；
- 构造 list；
- 执行 `dedupeCandidates`；
- 计算长度。

复杂度和分配接近八次全量扫描。scope 改变、课程 Provider 通知后可能重新加载；whole-course source 还可能顺序确保多个 section 已加载。现有代码已经增加防无限重试的 guard，这说明 Provider 通知与异步加载互相触发曾经是实际风险。

目标：题源加载一次、索引一次、模式计数一次，后续按修订号复用。

## 18.3 Playground 监听整个 CourseProvider，失效粒度过大（已确认）

页面直接给 `_courseProvider` 添加 listener。CourseProvider 中任何通知都可能进入 `_onCourseChanged()`，即使课程 scope、section 内容和 Playground 所需数据没有变化。

目标引入细粒度 snapshot/revision：

```dart
class PlaygroundSourceRevision {
  final String courseId;
  final String? unitId;
  final int courseContentRevision;
  final int mistakeRevision;
}
```

只有 key 变化才重新分析 availability。

## 18.4 AI 流式输出每个分片都通知监听者（已确认）

`AiTutorChatProvider.ask()` 在每个 `onChunk(delta)` 中拼接字符串并调用 `notifyListeners()`。类似模式也存在于 AI Hint/Card Explain 等 Provider。

SSE/流式模型可能在一秒内产生很多小分片，因此当前路径是：

```text
每个 delta
  -> 读取旧完整字符串
  -> cur + delta 创建新字符串
  -> 替换 message 对象
  -> notifyListeners
  -> Widget rebuild
```

消息越长，字符串重复复制也越明显。实时输出不需要等同于网络分片频率；人眼可感知的 50–100 ms 批次足够流畅。

## 18.5 AI 聊天页一次通知重建大范围 UI（已确认）

`AiTutorChatPage` 的主体使用 `Consumer2<AiTutorChatProvider, AiEngineConfigHolder>`。每个分片通知会重新构建：

- 模式 tabs；
- roleplay chips；
- 整个消息 ListView 描述；
- 错误区；
- loading 条；
- 输入栏；
- disclaimer。

即使 Flutter 会复用部分 element，build 和消息对象读取仍在高频发生。目标是只有正在流式生成的那个 bubble 更新，其余 shell 和历史消息保持稳定。

## 18.6 自动滚动可能排队（已确认）

部分 AI 页面在流式构建期间反复调用 `_scrollToBottom()`，每次安排 post-frame callback 和 200 ms `animateTo`。如果分片间隔小于动画时长，多个滚动动画会不断被安排，造成抖动、抢夺用户手势或额外帧负担。

目标：

- 只在用户本来距离底部小于阈值时自动跟随；
- 每 80–120 ms 最多一次；
- 新请求开始可以 jump，一段内容后使用短 animate；
- 用户主动上滑后暂停自动跟随，并显示“回到底部”按钮；
- dispose 时取消 timer/post-frame 意图。

## 18.7 Provider 页面销毁后没有统一取消契约（已确认）

Provider 有 generation/cancel token，但未统一覆盖 `dispose()` 来取消正在进行的请求、批次 timer 和回调。页面虽然 dispose Provider，网络流仍可能继续到 engine 层，并依靠 generation/状态检查丢弃部分结果。

目标所有会话 Provider 实现：

```dart
@override
void dispose() {
  _disposed = true;
  _cancelToken?.cancel();
  _flushTimer?.cancel();
  super.dispose();
}
```

并保证任何 callback 在 `_disposed` 后不通知。

## 18.8 AI 缓存有同步磁盘 I/O 风险，且接入状态不清（已确认/待验证）

`AiCache` 的内存 LRU 上限为 200；可选 DiskCacheStore 使用同步文件 API 读取、写入、枚举和清理。当前仓库中没有明确看到生产启动调用 `enableDiskMirror`，所以可能出现两种问题：

1. 磁盘镜像实际未接入，但 UI/文档暗示存在，用户看见的缓存统计不完整；
2. 后续一旦直接接入，cache miss/read/write 可能在 UI isolate 同步读写文件。

实施前必须确认运行时接入。最终只能二选一：

- 明确只使用内存 LRU，并删除误导性磁盘能力；或
- 将磁盘缓存改为异步 repository/isolate，提供字节、TTL、上限和清理统计。

此外，cache key 会规范化并序列化完整对话消息；长会话下同步 JSON 规范化和 SHA 计算也应进入 profile。

## 18.9 新 Anki 卡片传给 AI 的上下文不足（已确认）

`UnifiedReviewPage._openAiTutor()` 对标准课程卡可以使用 front/back；对 `OfficialTemplateContent` 当前可能退化为使用 `schedulingKey.rawId` 作为 term、meaning 为空。这会让 AI 看见内部 id 而不是用户正在学习的内容。

另一个风险是：复习卡片尚未揭示答案时，如果 AI 上下文直接包含 back/answer，助手可能提前泄题。Plan 1 已经建立卡片识别和展示来源，Plan 3 必须据此生成统一、受 reveal 状态约束的上下文。

## 18.10 内容创作代码会继续占据产品和维护表面（已确认）

现有 AI Wish、Textbook Import、AI Course Provider、部分 Lesson Helper 和最近任务 route string 仍与内容创作相关。即使只把入口隐藏：

- 最近任务可能仍尝试打开旧 route；
- root provider/依赖图仍保留功能；
- 文案和测试仍把移动端描述为创作平台；
- 深链可绕过首页；
- AI prompt 仍需维护两套边界。

因此采用分阶段退场：先 tombstone 和数据迁移，再删除路由、Provider、页面、prompt、字符串和无消费者依赖。

---

## 19. AI 产品信息架构

## 19.1 AI 助手保留能力

```text
AI 助手
├─ 学习问答
│  ├─ 自由提问
│  ├─ 句子纠错
│  └─ 情景对话
├─ 我的学习
│  ├─ 错题诊断
│  ├─ 薄弱点建议
│  └─ 已保存解释
├─ 当前学习上下文
│  ├─ 当前课程/Unit
│  ├─ 当前卡片解释
│  └─ 当前错误追问
└─ AI 偏好
   ├─ 回复语言
   ├─ 解释深度
   ├─ 是否注入学习上下文
   └─ 是否允许在揭示前讨论答案
```

AI 首页不再出现：创建课程、按愿望生成内容、教材导入、生成课程 JSON。

## 19.2 Playground 中的 AI 小工具

在普通模式网格之后增加紧凑区，不抢占 Playground Hero：

```text
AI 语言工具
[问一问]  [句子纠错]  [情景对话]
```

行为：

- 三个入口都打开同一个 `AiTutorChatRoute`，使用强类型参数 `initialMode`。
- 可选传入当前语言、课程、Unit 的轻量上下文。
- 不在 Playground 首页嵌入完整聊天 Provider 或消息列表。
- 未配置 AI 时点击进入统一未配置说明，可直达高级 → AI 连接。
- Playground 普通模式和题源加载不依赖 AI 配置，也不会页面打开即请求 AI。

目标路由参数：

```dart
class AiTutorChatRouteArgs {
  final AiTutorChatMode initialMode;
  final LearnerContextRef? contextRef;
  final AiEntryPoint entryPoint;
}
```

解决当前 focus 参数传入但没有实际选择对应模式的问题。

## 19.3 Play Hub 的调整

当前 Play Hub 的 AI 区指向内容创作，应改成：

- 一个“AI 助手”入口；
- 可选一个根据当前状态推荐的学习动作，如“分析最近错题”；
- Playground Hero 保持进入普通练习；
- 不重复摆放句子纠错、情景对话三个按钮，避免首页过密。

同时 `PlayHubScreen.initState()` 当前会立即刷新 Official due。由于 Home 使用 IndexedStack，Play tab 即使从未打开也可能被挂载并触发刷新。该问题放到全局生命周期 Phase 处理。

## 19.4 内容创作退场 UX

旧入口 tombstone 页面：

```text
内容创作已迁移

移动端不再提供课程生成、教材导入和结构编辑。
请参考 GUI 平台完成内容创作，移动端继续负责学习与复习。

[打开 GUI 平台]   [复制地址]
```

如果 GUI URL 尚未配置：

- 按钮禁用；
- 显示“GUI 平台地址尚未在此构建中配置”；
- 可以提供“复制诊断信息/联系支持”，不能打开旧仓库猜测路径。

### 退场对象 inventory

实施时至少检查并分类：

- `AiWishChatRoute` / 页面 / Provider；
- `TextbookImportRoute` / 页面 / Provider；
- AI Course generator/provider/spec 的移动端消费者；
- Lesson Helper 中仅服务创作的能力；
- Recent Tasks 中的 route string 和历史记录；
- Play Hub、AI Hub、设置页快捷入口；
- 内容创作 prompt、缓存 namespace、字符串、图标、测试；
- 备份中对应草稿数据。

历史草稿处理：默认不删除。先提供一个版本的导出/说明；如果 GUI 能导入，定义稳定 schema。不能因为入口退场静默清除用户未导出的创作草稿。

---

## 20. 新 Anki 卡片与 AI 的上下文合同

## 20.1 `AiCardContextResolver`

新增统一解析器，输入统一复习 item 和 reveal 状态，输出去脚本、可解释的上下文：

```dart
class AiCardContext {
  final int schemaVersion;
  final LearningSourceRef source;
  final String cardId;
  final String? noteTypeSignature;
  final String presentationKind;
  final double? recognitionConfidence;
  final String questionPlainText;
  final String? answerPlainText;
  final List<String> tags;
  final String? language;
  final bool answerRevealed;
  final List<AiMediaDescriptor> media;
  final List<String> warnings;
}
```

### 安全与正确性规则

1. 上下文在复习装配阶段生成，不让 AI 层抓 DOM/WebView。
2. Official 卡从 catalog/note projection/renderer plaintext contract 取值，不能用 raw scheduling id 代替内容。
3. 不传原始 HTML、JavaScript、CSS、绝对媒体路径、数据库主键或解密中间数据。
4. 媒体默认只传类型与可读标签；如未来支持图像/音频模型，另做用户授权和大小限制。
5. 卡片未揭示时，`answerPlainText` 默认 null。用户允许揭示也应在发送前明确提示。
6. Cloze 根据当前 ordinal 只暴露题面允许显示的部分，不能把所有 cloze 答案一次发出。
7. 识别置信度低时把 warning 传给 prompt，让 AI 避免断言卡片类型。
8. plaintext 无法可靠生成时，UI 显示“此卡片暂不支持 AI 解释”，不能把密文、raw id 或空答案发送。

## 20.2 与 Plan 1 的依赖

| Plan 1 输出 | Plan 3 用途 |
| --- | --- |
| `NotetypeSignature` | 上下文和缓存版本身份 |
| 识别 mapping/confidence/evidence | 选择 question/answer/presentation |
| `sectionKey` / Unit / Lesson | 学习范围上下文 |
| owner/source inventory | 统计来源与上下文来源 |
| 删除/重导失效信号 | AI 上下文和缓存失效 |

如果 Plan 1 的某类 Official 渲染仍只能在 WebView 中得到最终文本，先定义 renderer 的只读 `extractAccessibleText()` 协议，并限制超时/长度。禁止直接把整段 HTML 当 prompt。

## 20.3 Answer reveal 策略

| 场景 | 可发送问题 | 可发送答案 |
| --- | --- | --- |
| 未揭示，普通“解释题目” | 是 | 否 |
| 未揭示，用户明确“给我答案”且设置允许 | 是 | 二次确认后是 |
| 已揭示 | 是 | 是 |
| 作答错误后的追问 | 是 | 是，并可包含用户答案的脱敏文本 |
| 卡片删除/owner pending cleanup | 否 | 否，提示来源不可用 |

## 20.4 AI 缓存失效

key 至少包含：

```text
provider/model
+ promptTemplateVersion
+ AiCardContext.schemaVersion
+ source owner/fingerprint
+ card content fingerprint
+ reveal policy
+ user AI preference hash
```

删除来源、重新识别 notetype、用户修改字段映射、卡片内容更新或 reveal policy 改变时必须失效。不能只按 card id 缓存，否则删后重导可能命中旧内容。

---

## 21. AI 流式渲染目标架构

## 21.1 分片合并器

```dart
class StreamDeltaCoalescer {
  final Duration interval; // 建议 50–100 ms，profile 后定
  void add(String delta);
  void flush();
  void cancel();
}
```

规则：

- 网络分片先写 `StringBuffer`，不立即创建完整 message 字符串。
- 一个 interval 最多提交一次 UI revision。
- 流结束、错误、取消时立即 final flush。
- 减少动态不关闭流式文本，但可以使用更低更新频率和无光标闪烁。
- 测试确保任何 delta 不丢失、不乱序，取消后不再 flush。

## 21.2 消息状态拆分

```dart
class ChatMessageViewModel {
  final String id;
  final ChatRole role;
  final String content;
  final int revision;
  final ChatMessageStatus status;
}
```

- 历史消息是不可变对象，id 稳定。
- 当前流式消息独立 ValueListenable/Selector，只更新对应 bubble。
- 模式、语言、输入状态、错误和消息列表分别选择。
- 输入框 Controller 保留在页面本地，不因 token 变化重建。
- `ChatBubble` 可缓存解析结果；Markdown/富文本按段落增量或低频解析，不对完整长文本每 token 重排。

建议组件树：

```text
AiTutorChatPageShell            // 只监听 config 是否完整
├─ ModeSelector                 // 只监听 mode
├─ RoleplaySceneSelector        // 只监听 mode + busy
├─ ChatMessageList              // 只监听 message ids/数量
│  ├─ StableMessageBubble       // 历史不变
│  └─ StreamingMessageBubble    // 监听当前 revision
├─ ChatErrorBanner              // 只监听 error
├─ ChatActivityIndicator        // 只监听 state
└─ ChatComposer                 // 只监听 busy
```

## 21.3 滚动协调器

建立单一 `ChatAutoScrollCoordinator`：

- 维护 `isNearBottom`；
- 用户向上拖动后锁定自动滚动；
- 合并多个内容更新；
- 页面退出取消计划任务；
- 键盘出现和消息增长共用一个调度点；
- 消息流结束时如果接近底部，执行一次最终定位。

验收：流式 1,000 个网络分片时，滚动动画调用次数受节流上限约束，而不是 1,000 次。

## 21.4 生命周期与取消

所有 AI feature provider 统一实现：

- 每次请求有 generation id；
- 新请求取消旧请求；
- 页面 dispose 取消 token、timer 和音频/文件资源；
- engine 回调在通知 UI 前检查 generation + disposed；
- 最近任务只在请求成功完成或产生可用部分结果后记录；
- 取消不显示为错误；
- route scoped provider，不把一次会话提升为全应用常驻对象。

## 21.5 长会话控制

- 只发送最近 N 轮 + 结构化摘要；N 由 token 预算而非消息条数单独决定。
- 摘要与原消息分开存，显示层不丢历史。
- 超过本地显示上限时消息分页/虚拟化。
- cache key 和请求 body 的 canonicalization 对超大 payload 放后台 isolate，或采用增量 hash。
- 日志不记录完整 prompt/response；诊断只记录字符数、消息数、耗时、首 token 时间和错误类型。

## 21.6 AI 缓存策略

建议目标：

| 层 | 容量/寿命 | 线程 | 内容 |
| --- | --- | --- | --- |
| 会话内 | 当前会话消息 | UI 内存，低频提交 | 生成中内容 |
| 内存 LRU | 字节上限 + entry 上限 | UI 可查，操作需轻量 | 完整成功响应 |
| 磁盘（可选） | 字节上限 + TTL | 异步/isolate | 可安全复用响应 |

磁盘缓存必须：

- 统计真实 bytes，不只 entries；
- 有 createdAt、lastAccess、schema/prompt version；
- LRU/TTL 清理不在 UI isolate 做目录全扫描；
- 不存 API Key、Authorization、完整可识别个人信息；
- 设置页可清理且说明会重新请求；
- 如果功能未正式接入，就从用户 UI 中删除磁盘缓存暗示。

---

## 22. Playground 数据与性能重构

## 22.1 单次索引

当前八次过滤改为一次遍历：

```dart
class PlaygroundIndex {
  final int sourceRevision;
  final Map<PlaygroundMode, List<String>> candidateIdsByMode;
  final Set<String> wordIds;
  final Map<String, PlaygroundCandidate> candidatesById;
}
```

构建算法：

```text
for candidate in bundle.candidates
  canonicalId = dedupeKey(candidate)
  if first occurrence
    candidatesById[canonicalId] = candidate
    for mode in classifier.modesFor(candidate)
      candidateIdsByMode[mode].add(canonicalId)
```

这样模式可用性、数量和开练都消费同一索引，避免计数与实际题目不一致。

## 22.2 scope 缓存

key：

```text
courseId + scope + unitId + courseContentRevision + mistakeRevision
```

- recent/currentUnit/weak 各自缓存一个最近索引。
- wholeCourse 使用分段增量索引，不要求进入页面就顺序加载全部 section。
- 切回已访问 scope 立即显示缓存，再验证 revision。
- CourseProvider 的无关通知不会使缓存失效。
- 失败缓存短 TTL，避免 notification storm 造成无限重试；同时提供显式重试。

## 22.3 whole-course 加载

建议流程：

1. 先用已加载 section 构建 partial index，立即展示可用模式。
2. 后台按受控并发（例如 2）加载其余 section。
3. 每完成一批合并索引，低频刷新计数。
4. 用户开始某模式后优先加载该模式所需题目，不等待无关 section。
5. 页面退出取消剩余预取。
6. 不在低内存设备保留整个课程正文的第二份复制；索引尽量保存 id/轻量特征。

## 22.4 页面状态

- 首次进入不显示八个都为 0 后又跳变；使用骨架数量或“正在分析”。
- 已缓存时立即可点，不因后台刷新禁用全部模式。
- 某模式无题时解释缺少何种内容。
- coming soon 的模式不应长期显示成可用；要么接上会话执行，要么标 Beta/即将推出并不可点。
- AI 工具与普通模式分别显示可用状态；AI 未配置不影响普通练习。

---

## 23. 全局性能治理

## 23.1 先建立可观测性

“整体卡顿”必须拆成：

| 类别 | 指标 | 例子 |
| --- | --- | --- |
| 首帧/路由 | 页面打开到骨架、到可交互、到数据完整 | 设置、复习、AI、Playground |
| 帧 | build/raster duration、jank count | 滚动、流式输出、图表动画 |
| 数据库 | query duration、rows scanned/returned、query count | review allEvents、source 聚合 |
| 存储 I/O | read/write bytes、同步 I/O、write amplification | 配置逐字符写、JSON blob |
| 内存 | Dart heap、external、RSS、图片/WebView 估算 | 大 Anki、长 AI 会话 |
| 缓存 | hit/miss、entries、bytes、eviction、TTL | AI、Playground、复习快照 |
| 生命周期 | 隐藏 tab 后台任务、未取消请求 | PlayHub Official due refresh |

实现 `PerformanceTrace`/`DiagnosticsEvent` 时：

- release 默认只保留聚合和慢操作，不记录内容；
- trace 有 feature、operation、duration、result size、cache status；
- source id 使用脱敏/稳定 hash；
- 不记录 API Key、卡片正文、prompt、用户文件路径；
- 环形缓冲有严格上限；
- 用户可在高级页复制摘要。

## 23.2 Home IndexedStack 的隐藏工作（已确认）

`HomePage` 当前使用 `IndexedStack` 常驻 CourseTree、PlayHub、Profile、Settings。它能保留 tab 状态，但所有 child 会挂载。`PlayHubScreen.initState()` 因此可能在用户从未进入 Play tab 时刷新 Official due。

目标采用 lazy visited tabs：

```text
首次只构建当前 tab
用户第一次访问某 tab -> 构建并保留
隐藏 tab -> Offstage + TickerMode(false)
可见性改变 -> feature onVisible/onHidden
重任务按 TTL 决定刷新
```

不能简单换成每次重建 tab，否则会丢课程滚动和设置状态。验收要同时检查：

- 未访问 Play 不触发 due refresh；
- 第一次访问正常加载；
- 10 秒内切回不重复刷新；
- 数据 revision 改变或 TTL 到期才刷新；
- 隐藏 tab 无动画 ticker 和无持续 stream rebuild。

## 23.3 Provider 作用域

先做订阅图审计，不全面换框架：

- 应用级：账户、主题、无障碍、稳定配置、当前课程引用。
- tab 级：Play Hub 摘要、设置导航状态。
- route 级：AI 会话、复习筛选、Playground index、存储深度扫描。
- operation 级：导入、连接测试、清理任务。

规则：

- 大型对象不因方便而放 root。
- root Provider 即使 lazy，也会在首次实例化后长期存活；需要明确释放缓存的方法。
- `context.watch` 改为 `select` 必须选择稳定、不可变、小字段。
- 返回新 List 的 getter 不适合作为 select 值，除非有值相等或 revision。
- Provider 通知原因在 debug profile 可记录，定位 notification storm。

## 23.4 JSON blob 与写放大

已确认风险：

- AI config 每字符写完整 JSON；
- MistakeProvider 每次持久化会编码完整错题列表；
- StudyLogRepository 已使用 recent queue 和日聚合，优于每次改写 90 日主 blob，但达到 cap 时仍有合并成本；
- SRS 热复习路径已采用单行数据库写，少数批量/兼容路径仍需保留监控，不能笼统认定 SRS 每次写全量。

任务：

- 记录每个 prefs key 的写次数、编码字节和 P95 时间，key 名可记录，value 禁止记录。
- 高频增长集合迁移到有索引的表或 append log。
- 偏好只保存小型配置，不保存无界历史。
- 批量合并设后台/空闲时机，避免复习答题后立即大 JSON encode。
- 为异常增长设置诊断阈值，但不自动删除用户数据。

## 23.5 内存诊断口径

高级页中的“内存检测”拆为：

```text
当前运行内存（瞬时）
  Dart heap used/capacity
  external/native（平台可用时）
  RSS（平台可用时）
  图片/WebView/引擎只能显示估算或不可用

持久存储（磁盘）
  数据库/媒体/缓存/日志/临时/孤儿/可回收
```

运行内存页面规则：

- 显示采样时间和“数值会随系统回收变化”。
- “释放缓存”只调用已登记的可释放缓存，不伪装成强制系统 GC。
- 每个 cache 注册 owner、entries、estimatedBytes、clear policy。
- 无可靠 bytes 的 cache 显示“条目数”，不能把 entries 当 MB。
- WebView/native 内存若平台 API 不可得，明确未知。

建议缓存注册表：

```dart
abstract interface class CacheDiagnosticsAdapter {
  String get owner;
  Future<CacheFootprint> inspect();
  Future<CacheClearResult> clearRegenerable();
}
```

## 23.6 图片、WebView 与 Anki 渲染

属于高概率项，需要真机确认：

- Official/HTML 卡的 WebView 生命周期是否跨卡片残留；
- 预渲染图片/HTML 是否存在无上限内存 cache；
- 大媒体 decode 是否按原图尺寸进入内存；
- 切换卡片是否创建新 controller 而旧 controller 延迟释放；
- Hero/动画是否持有大图层。

Profile 方法：

- 以大图片、大音频、MathJax、复杂模板 fixture 各复习 100 张；
- 每 10 张采样 heap/RSS/controller count；
- 离开页面后等待正常回收窗口再采样；
- 区分稳定 cache plateau 与持续线性增长；
- 只有证明 owner 无引用后才判泄漏。

## 23.7 Isolate 使用原则

适合后台：

- 大 JSON decode/encode；
- changelog/manifest 大文本解析（若实际需要）；
- 存储目录深度扫描和 hash；
- Playground 大候选索引；
- AI 长 prompt canonicalization；
- 历史统计 backfill。

不适合盲目 isolate：

- 小 SharedPreferences 读取；
- 单个数据库聚合查询（应由数据库索引解决）；
- 每个 token 启动 isolate；
- 需要复制巨大对象、复制成本超过计算的任务。

每次 isolate 优化都要比较消息复制、启动和总耗时。

---

## 24. 性能预算与发布门槛

以下为建议初始预算。Phase P3-0 必须绑定具体 Android 基准机型、系统版本、Flutter profile 构建和 fixture；正式门槛记录绝对值与相对上一版本变化。

## 24.1 交互预算

| 场景 | 建议目标 |
| --- | --- |
| Home tab 已访问切换 | P95 到可操作 ≤ 150 ms |
| Home tab 首次访问 | P95 骨架 ≤ 250 ms，warm 数据可用 ≤ 600 ms |
| 复习概览 warm 打开 | P95 可操作 ≤ 400 ms |
| 复习概览筛选/刷新 | 保留旧数据；主线程单次阻塞 < 16 ms |
| Playground cached scope 切换 | P95 ≤ 150 ms |
| Playground medium 首次索引 | 后台完成 P95 ≤ 800 ms，首帧不阻塞 |
| AI 输入 | P95 输入响应 ≤ 50 ms |
| AI 首个可见分片 | 主要由网络决定；收到分片后 UI 提交 ≤ 100 ms |
| AI streaming | UI 更新频率约 10–20 Hz 上限，不按网络分片无限刷新 |

## 24.2 帧预算

- 60 Hz 目标下 build + raster 单帧预算 16.7 ms。
- 对 120 Hz 设备不承诺全路径 8.3 ms，但不得人为固定低帧动画。
- 核心滚动场景 P95 帧不超过预算；P99 与最差帧单独记录。
- 5 秒流式 AI、复习首页滚动、Playground 网格滚动分别记录 jank count。
- 首次 shader/asset warm-up 单独记录，不用 warm 数据掩盖 cold 问题。

## 24.3 查询预算

- 复习首页固定数量聚合查询，建议 ≤ 5 次，不随 source 数线性发起 N+1。
- medium fixture 首页不调用 `allEvents()`，不返回全卡片正文。
- 7 日图返回至多 7 × source 聚合行；默认全局时仅 7 行。
- 来源摘要一次 group query，Top N 分页。
- 慢查询阈值初设 50 ms；超过记录 query id、参数类别和扫描/返回行数，不记录正文。

## 24.4 内存与缓存预算

绝对 MB 需基准机确定，先设趋势门槛：

- 复习 100 张后 heap/RSS 不持续近似线性上升；离开页面后回落到稳定平台。
- 1,000 AI 分片的 UI 消息更新次数受节流上限约束；临时字符串分配相对基线显著下降。
- Playground 切换四个 scope 后只保留受控数量的轻量索引。
- AI 磁盘缓存若启用，有硬字节上限和 TTL；存储诊断显示一致。
- 任一无界 List/Map/日志/最近任务必须给出 cap 或分页理由。

## 24.5 回归判定

- 绝对预算通过，且相对上一个稳定版本不能恶化超过预设比例（建议 10%）。
- 仅平均值改善但 P95/P99 恶化，不判通过。
- 桌面功能通过且 CPU/内存无显著回退。
- Debug 数据不用于性能结论；必须使用 profile/release-like 构建。

---

## 25. Plan 3 分阶段实施

## Phase P3-0：性能基线与数据合同冻结

任务：

- 确定 Android 中低端基准机和桌面基准环境。
- 为设置、Home、复习、Playground、AI 建立 trace。
- 建立 small/medium/large 数据 fixture。
- 记录 `allEvents`、`_allTagged`、Playground 模式扫描和 AI per-chunk 通知基线。
- 定义 LearningSourceRef、ReviewDataRevision、AiCardContext schema。
- 列出所有内容创作 route/provider/data。

出口条件：

- 每个用户报告的“卡”至少对应一个可复现脚本和指标。
- 数据合同评审完成，不在 UI 实现中临时猜 source。
- 确定 AI disk cache 当前究竟是否接入生产。

## Phase P3-1：复习聚合数据层

任务：

- DAO 增加 date/source 聚合查询，禁止首页调用 `allEvents()`。
- 写入稳定 source identity。
- 建立/复用 daily aggregate，并实现增量 backfill。
- 实现统一 Dashboard Snapshot 和数据修订号。
- 做缓存、请求 generation 和 stale-while-revalidate。
- 修正空数据 retention 语义。

出口条件：

- medium/large fixture 首页返回量不随全历史等量增长。
- Legacy、Official、课程、语法来源均准确分类。
- 删除来源后历史和当前队列语义正确。
- 查询数无按来源 N+1。

## Phase P3-2：复习概览 UI

任务：

- 实现今日 Hero、due/new/overdue、streak、7 日、时间/准确率和来源列表。
- 提供主 CTA 和空/错/回填状态。
- 使用 sliver、局部 selector 和 RepaintBoundary。
- 修复下拉刷新 Future。
- 移除首屏复杂筛选与记忆曲线。

出口条件：

- 首屏信息顺序与 §15.1 一致。
- 刷新和筛选不闪整页 spinner。
- 200% 字号、TalkBack、高对比和减少动态通过。
- medium fixture 达到页面预算。

## Phase P3-3：学习洞察二级页

任务：

- 迁移热力图、记忆曲线、成熟度和趋势。
- 统一筛选模型与 global/filtered 标签。
- 图表只查询固定 buckets。
- 增加来源详情页和已删除来源状态。

出口条件：

- 365 日热力图不加载 365 天全部事件实体。
- 图表有语义文本和无数据说明。
- 切换范围可取消旧请求，晚到结果不覆盖新筛选。

## Phase P3-4：内容创作退场与 AI IA 收敛

任务：

- Play Hub 和 AI Hub 删除创作卡片。
- 旧 route 改为 GUI 迁移 tombstone。
- 清理 Recent Tasks 旧 route；保留必要草稿导出。
- 从移动端 Provider/DI/prompt 移除无消费者创作能力。
- 接入 Plan 2 ExternalLinkRegistry 的 GUI 链接。

出口条件：

- 移动端没有可执行内容创作入口或深链。
- GUI URL 缺失时行为明确且不打开旧链接。
- 旧最近任务不崩溃，用户草稿不被静默删除。
- AI 助手 prompt 明确不输出课程 schema。

## Phase P3-5：Playground 融合与题源索引

任务：

- 增加三个 AI 语言工具入口和 typed route args。
- 修正初始模式/focus 参数未消费问题。
- 实现 PlaygroundIndex 单次扫描和 scope revision cache。
- wholeCourse 改为分段、受控并发、可取消加载。
- 连接可执行模式或明确禁用 coming-soon 模式。

出口条件：

- 打开 Playground 不自动调用 AI。
- 未配置 AI 只影响三个 AI 工具。
- medium fixture 模式分析只遍历一次候选主集合。
- 切换缓存 scope 达到交互预算，无无限重试风暴。

## Phase P3-6：Anki AI 上下文适配

任务：

- 实现 AiCardContextResolver 和 schema version。
- Standard/Legacy/Official/Cloze/媒体卡使用统一 contract。
- 实现 reveal 策略、低置信 warning 和 unsupported state。
- 更新 prompt/cache key/删除失效。
- 为用户映射调整和 Section Beta 上下文添加测试。

出口条件：

- Official 卡不再把 raw scheduling id 当学习术语。
- 未揭示答案默认不进入 prompt。
- 原始 HTML/JS/本地路径不进入模型请求。
- 删除、重导、重新识别不会命中旧卡片 AI 缓存。

## Phase P3-7：AI 流式与缓存性能

任务：

- 所有文本流 Provider 接入 delta coalescer。
- 拆分聊天 shell、消息列表、streaming bubble 和 composer 监听范围。
- 实现统一自动滚动协调器。
- dispose 取消请求、timer 和回调。
- 控制长会话上下文和显示分页。
- 决定磁盘缓存去留；若保留则全部异步、限字节和 TTL。
- 将大 prompt key 计算移出关键帧路径。

出口条件：

- 1,000 delta 不产生 1,000 次整页 rebuild/scroll animation。
- 退出页面后无继续通知、setState-after-dispose 或无意义网络流。
- 长回复滚动保持可操作，用户上滑不被拉回底部。
- AI 缓存统计的 entries/bytes 与高级页一致。

## Phase P3-8：Home 生命周期与全局热路径

任务：

- IndexedStack 改为 lazy visited tabs + TickerMode/可见性 hook。
- Play Hub Official due 刷新改为首次可见 + TTL/revision。
- 审计 root/route Provider 作用域。
- 处理高频 JSON blob、错题存储和后台合并。
- Profile Anki WebView、图片和媒体生命周期。
- 注册各 feature cache 到诊断页。

出口条件：

- 未访问 tab 无重 I/O/网络/engine 刷新。
- 隐藏 tab 无持续 ticker 或无关 rebuild。
- 100 张复杂 Anki 卡内存达到稳定平台，无确认泄漏。
- 高频 prefs 写显著下降且无数据丢失。

## Phase P3-9：压力、灰度与清理

任务：

- 跑 small/medium/large 基准和真机 100 卡/长 AI 会话。
- 比较 P50/P95/P99、查询、分配、RSS 和磁盘增长。
- 灰度新 dashboard repository 与 AI streaming pipeline。
- 验证 backfill 可暂停、恢复和回滚。
- 删除到期 tombstone、旧 progress provider/route 和死缓存。

出口条件：

- Plan 3 Definition of Done 全部满足。
- 性能报告包含设备、构建、fixture、前后数据和未解决项。
- 回滚不会破坏新写入的 source identity、聚合或安全凭据。

---

## 26. Plan 3 测试矩阵

## 26.1 复习统计

| 场景 | 验证 |
| --- | --- |
| 无卡/无历史 | 不显示 100%，显示正确引导 |
| 仅课程卡 | source、due、今日数据正确 |
| Legacy Anki | 使用稳定 source，不只靠前缀 |
| Official Anki | 当前队列和历史均归属正确 |
| 混合来源 | group by 无重复、总数等于分项或解释差异 |
| 来源删除 | 当前不再 due，历史显示已删除来源 |
| pending cleanup | 不伪装已删除，状态可解释 |
| 时区跨日/DST | 日聚合、streak 和 today 一致 |
| 快速切筛选 | 旧请求不覆盖新请求 |
| 下拉刷新失败 | Future 正确结束，旧数据保留 |
| backfill 中断 | 重启继续，无重复计数 |

## 26.2 AI 上下文

| 卡片类型 | 验证 |
| --- | --- |
| 标准 front/back | 问题与揭示后答案正确 |
| Cloze | 只处理当前 ordinal，不泄露其他答案 |
| Legacy Anki | mapping/confidence/source 正确 |
| Official template | 使用 plaintext contract，不使用 raw id |
| HTML/JS | script/style/path 被移除 |
| 图片/音频 | 只传允许的 descriptor |
| 低置信识别 | prompt 有 warning，UI 可见 |
| 未揭示 | 默认无 answer |
| 删除/重导 | cache 失效且新 fingerprint 生效 |

## 26.3 AI 流式

- delta 顺序、Unicode 边界、组合字符和 Markdown fence 不丢失；
- coalescer 结束立即 flush；
- cancel/dispose 后无通知；
- 网络错误保留可用部分文本或按明确规则回滚；
- 1,000/10,000 小 delta 的通知次数符合上限；
- 历史 bubble 不因当前 delta rebuild；
- 用户上滑暂停自动跟随；
- 键盘切换和旋转不产生滚动风暴；
- 长会话截断/摘要不改变显示历史。

## 26.4 Playground

- 同一 candidate 只按 canonical id 去重一次；
- counts 与实际可开练题目一致；
- recent/currentUnit/wholeCourse/weak 各 scope 正确；
- 课程无关通知不重建 index；
- wholeCourse 部分加载可先开练；
- 页面退出取消预取；
- 从三个 AI 入口分别进入正确 mode；
- AI 未配置时普通模式仍可用；
- Anki scope 的禁止逻辑不发生无限退出/重试。

## 26.5 全局性能

- Home 未访问 tab 不初始化重任务；
- tab 切换保留状态和滚动位置；
- hidden tab ticker 停止；
- prefs write counter 验证配置防抖；
- 错题/StudyLog/SRS 高频路径分别 benchmark，避免错误归因；
- WebView/媒体 100 卡场景无持续增长；
- cache registry 清理只删除 regenerable data；
- 诊断事件无正文、路径和凭据。

---

## 27. 代码落点建议

以下是建议结构，不要求一次性机械移动全部文件；每个迁移以可测试、可回滚为准。

```text
lib/
├─ application/
│  ├─ settings/
│  │  ├─ settings_destination.dart
│  │  ├─ settings_migration_service.dart
│  │  └─ external_link_registry.dart
│  ├─ security/
│  │  └─ secure_credential_store.dart
│  ├─ diagnostics/
│  │  ├─ performance_trace.dart
│  │  ├─ cache_registry.dart
│  │  └─ diagnostics_exporter.dart
│  ├─ review_dashboard/
│  │  ├─ review_dashboard_repository.dart
│  │  ├─ review_dashboard_models.dart
│  │  ├─ review_data_revision.dart
│  │  └─ insights_repository.dart
│  ├─ ai/
│  │  ├─ ai_card_context.dart
│  │  ├─ ai_card_context_resolver.dart
│  │  ├─ stream_delta_coalescer.dart
│  │  └─ chat_auto_scroll_coordinator.dart
│  └─ playground/
│     ├─ playground_index.dart
│     └─ playground_index_repository.dart
├─ data/
│  ├─ review_dashboard_dao.dart
│  ├─ daily_review_stats_dao.dart
│  ├─ gem_ledger_dao.dart
│  └─ cosmetic_entitlement_dao.dart
└─ views/
   ├─ settings/
   │  ├─ settings_landing_page.dart
   │  ├─ accessibility_settings_page.dart
   │  ├─ appearance_sound_settings_page.dart
   │  ├─ advanced_settings_page.dart
   │  ├─ legacy_compatibility_page.dart
   │  └─ ai_connection_settings_page.dart
   ├─ review/
   │  ├─ review_dashboard_page.dart
   │  ├─ learning_insights_page.dart
   │  └─ review_source_detail_page.dart
   ├─ ai/
   │  └─ content_authoring_moved_page.dart   // 临时 tombstone
   └─ playground/
      └─ language_playground_page.dart
```

### 27.1 现有文件处置表

| 当前文件/区域 | 计划动作 |
| --- | --- |
| `settings_page.dart` | 强类型路由化，最终删除整数 category |
| `settings_fun_section.dart` | Release 删除；测试能力移 fixture |
| `settings_advanced_section.dart` | 拆为高级首页和兼容性页 |
| `about_turna_page.dart` | 删除使用指南、接 LinkRegistry/BuildInfo |
| `changelog_page.dart` | 接 ReleaseManifest，删除双版本事实源 |
| `ai_api_config_page.dart` | 精简为 AI 连接；草稿保存；安全 Key |
| `review_progress_provider.dart` | 被 Dashboard/Insights repository 替代 |
| `review_progress_page.dart` | 重做为概览；重统计迁二级 |
| `ai_tutor_chat_provider.dart` | 接 coalescer、稳定 message、dispose cancel |
| AI hint/explain providers | 使用同一 streaming base contract |
| `ai_cache.dart` | 明确内存/磁盘策略，异步化或删死能力 |
| `language_playground_page.dart` | revision cache、一次索引、AI 小工具 |
| `play_hub_screen.dart` | 删除创作入口，可见时刷新 due |
| `home_page.dart` | lazy visited tab 生命周期 |
| `cosmetic_provider.dart` | 迁到 entitlement + ledger 事务 |
| `gems_provider.dart` | 余额改为账本投影、幂等事件 |

---

## 28. 跨计划依赖与推荐执行顺序

## 28.1 硬依赖

1. Plan 1 owner/source identity 完成后，才能最终替换复习来源字符串推断。
2. Plan 2 安全凭据完成后，才能把新 AI 入口正式发布。
3. Plan 2 ExternalLinkRegistry 完成后，内容创作迁移提示才能上线可用 GUI 链接。
4. Plan 2 无障碍能力契约完成后，Plan 3 新复习图表与装扮动效才能通过最终验收。
5. ReviewDataRevision 完成后，复习 dashboard cache 和 Playground/AI 的相关失效才能统一。

## 28.2 可并行但需合并门槛的工作

- 设置 IA 与复习 DAO 聚合可以并行。
- 关于/外链与 AI streaming 可以并行。
- 装扮账本与 Playground 索引可以并行。
- 内容创作 route tombstone 可先于底层代码删除。
- 性能埋点必须先进入主干，后续各模块使用同一口径。

## 28.3 推荐总顺序

```text
P2-0 / P3-0 基线与合同
  -> P2-1 设置导航
  -> P2-2 实验室退场
  -> P2-4 安全 AI 连接
  -> P3-1 复习聚合数据
  -> P3-2 复习概览
  -> P2-5 无障碍收口
  -> P2-6 外链与版本
  -> P3-4 内容创作退场
  -> P3-5 Playground 融合
  -> P3-6 Anki AI 上下文
  -> P3-7 AI 流式性能
  -> P3-3 洞察页
  -> P2-7 装扮与宝石
  -> P3-8 全局生命周期/内存
  -> P2-8 / P3-9 灰度、清理和发布
```

其中安全 Key、复习全量查询和 AI 流式整页重建是明确热/风险路径，应优先于纯视觉丰富。

---

## 29. 风险登记与回滚

| 风险 | 影响 | 缓解 | 回滚 |
| --- | --- | --- | --- |
| 设置路由改造破坏 tab 返回 | 用户迷路/崩溃 | typed route + 集成测试 | 保留一版适配器 |
| Key 安全迁移失败 | AI 不可用或凭据丢失 | 两阶段验证、不先删旧值 | 重试迁移；绝不回写明文新值 |
| daily stats 回填错误 | 统计不准确 | cursor、抽样对账、版本列 | 停用新投影，原事件保留 |
| source identity 不完整 | Official 统计错归 | Plan 1 inventory、unknown source | unknown 单列，不猜课程 |
| 内容创作草稿丢失 | 用户资产损失 | tombstone + 导出期 | 恢复只读旧页面/导出器 |
| coalescer 丢 token | AI 内容缺字 | 顺序/Unicode/property test | feature flag 回旧流，但保留局部 rebuild |
| lazy tab 丢状态 | 体验回退 | visited cache + restoration test | 回 IndexedStack，先禁隐藏重任务 |
| 钱包迁移重复 | 宝石异常 | 幂等 opening transaction | 账本校验/人工 adjustment |
| 动态装扮影响低端帧 | 主流程卡顿 | surface budget、减少动态变体 | 远端/本地 feature flag 禁动效 |
| 磁盘 cache 清错数据 | 数据损失 | cache registry + cleanupPolicy | 默认仅内存；磁盘功能后上 |

回滚原则：

- schema 变化只增量，不在灰度期删除原始事件或创作草稿。
- 新聚合是投影，可以重建；原复习历史是事实，不能为回滚删除。
- 新 source identity 写入后旧版若忽略也应可运行。
- 凭据一旦迁入安全存储，回滚版本不得自动导出为明文；必要时让用户重新输入。
- 商品 entitlement/ledger 是事实，回滚 UI 可以隐藏新商品，但不能丢购买记录。

---

## 30. 交付物清单

## 30.1 Plan 2 交付物

- 新设置 IA 和 typed navigation；
- 实验室退场与迁移报告；
- 高级/兼容性/AI 连接/存储诊断页面；
- 平台安全凭据实现与泄漏测试；
- 无障碍能力矩阵和测试报告；
- ExternalLinkRegistry、AppBuildInfo、ReleaseManifest；
- 使用指南与死资源删除清单；
- 商品目录、宝石账本、旧数据迁移；
- Android/桌面性能与无障碍报告。

## 30.2 Plan 3 交付物

- ReviewDashboardRepository、聚合 schema 和 backfill；
- 新复习概览、洞察与来源详情页；
- AI 产品 IA 收敛和内容创作退场清单；
- GUI 迁移 tombstone；
- PlaygroundIndex、scope cache 和 AI 三入口；
- AiCardContextResolver 与 Anki/Reveal 测试；
- 流式 coalescer、局部 rebuild、滚动协调器和取消契约；
- AI cache 明确实现与诊断统计；
- lazy Home tabs、Provider 作用域与 JSON 写放大治理；
- small/medium/large benchmark 与真机性能报告。

---

## 31. Plan 3 Definition of Done

- [x] 复习概览首页不调用全量 `allEvents()`。（ReviewDashboardRepository 仅用 eventsBetween/dailyActivityBetween 有界查询）
- [x] 一次 dashboard 加载不重复物化全部卡片，也不存在按来源 N+1 全扫描。（单遍分类；旧 provider 双 _allTagged 已修）
- [x] 首页优先展示今日目标、due/new/overdue、streak、7 日、时间/准确率和来源。（review_dashboard_page + LearningInsightsRoute 二级页）
- [~] 热力图与记忆曲线进入二级洞察页，并使用固定桶聚合。（已移入学习洞察页；洞察页内部固定桶聚合优化仍待做）
- [x] 空数据不显示虚假的 100% 记忆率。（accuracy null → 暂无数据；洞察 KPI tracked==0 显示 —）
- [x] 下拉刷新等待真实 Future；筛选/刷新保留旧数据。（_refresh 返回真实 loadDashboard future；缓存快照先行）
- [~] Legacy/Official/课程/语法使用稳定 source identity。（LearningSourceRef 已建立并被 Dashboard/AiCardContext 消费；legacy 卡片分类仍依赖 wordId 前缀——待 Plan 1 source 元数据落地后替换，见 §28.1 硬依赖）
- [x] AI 助手保留学习能力，移动端内容创作入口和深链完成退场。（wish/textbook 路由 tombstone；play/ai hub/课程管理入口删除）
- [x] GUI 地址缺失时不生成伪链接。（tombstone + 关于页均走 ExternalLinkRegistry 未配置禁用态）
- [x] Playground 提供自由提问、句子纠错、情景对话三个 typed AI 入口。（AiTutorChatRoute(initialMode:) 已消费，直达对应模式）
- [x] Playground 普通练习不依赖 AI，候选主集合只需一次索引。（PlaygroundIndex 单遍 + 与 assembler 一致性测试；打开页面零 AI 请求）
- [x] Official Anki AI 上下文不使用 raw scheduling id，不传原始 HTML/JS/path。（AiCardContextResolver 净化 + raw id 禁用；ai_card_context_resolver_test）
- [x] 未揭示卡片默认不向 AI 发送答案。（resolver answerRevealed 门控 + prompt 摘要不泄露）
- [x] AI delta 合批，只有 streaming bubble 高频更新。（StreamDeltaCoalescer 80ms + streamingRevision 选择器；1000 delta < 50 次通知实测）
- [x] 自动滚动不排队、不抢夺用户上滑，页面销毁会取消请求与 timer。（ChatAutoScrollCoordinator 节流+锁定；dispose 取消含流/coalescer/timer——测试曾抓到真实 dispose-notify 缺陷并已修）
- [~] AI 磁盘缓存要么异步、限字节、限 TTL 且实际接入，要么删除误导性能力。（审计确认生产从未 attach 磁盘镜像，UI 无磁盘暗示——现状等价于"只使用内存 LRU"；异步化或删除决策留待后续）
- [x] Home 未访问 tab 不执行重刷新；隐藏 tab 无 ticker。（lazy visited tabs + Offstage + TickerMode；Play Hub due 刷新首次可见 + 5 分钟 TTL）
- [ ] 配置、错题、日志等高频存储路径有写次数/字节基线和上限策略。（AI 配置写放大已消除；错题/日志写计数与上限待做）
- [~] 运行内存、磁盘存储、缓存和垃圾使用不同口径。（存储与性能页沿用 Plan 1 StorageInventoryService 分类口径；运行内存拆分待做）
- [ ] Android medium fixture 和真机场景达到批准预算，桌面端无回退。（需基准机型与 profile 构建，见 §24/§35）

---

## 32. 最终发布验收场景

以下场景必须在同一候选版本完整走通，不能只分别通过单元测试：

### 场景 A：旧用户升级

1. 用户旧版已有课程、Anki、复习历史、宝石、头像环、AI Key 和实验室偏好。
2. 升级后设置首页结构正确，实验室消失，autoAnswer 关闭。
3. AI Key 迁移安全存储且 AI 连接仍可测试。
4. 宝石余额和已购头像环一致。
5. 复习概览数据与旧历史抽样一致。
6. 关于版本和更新日志匹配。

### 场景 B：大 Anki 用户

1. medium/large Anki 数据存在 Legacy/Official 混合来源。
2. 打开复习概览不读取全历史实体、不长时间空白。
3. 牌组来源、due、今日完成正确。
4. 打开一张 Official 卡，揭示前 AI 不含答案，揭示后解释有真实卡片文本。
5. 连续复习 100 张，内存趋于平台而不是持续线性上涨。
6. 存储诊断能区分内容、媒体、缓存、待清理和可回收空间。

### 场景 C：AI 长会话

1. 从 Playground 的句子纠错进入正确模式。
2. 模型输出大量细碎 delta。
3. 输入、滚动和返回仍可操作，历史消息不重复重建。
4. 用户上滑后页面不强拉到底部。
5. 退出页面立即取消流和 timer。
6. 高级页缓存统计与实际实现一致，诊断无 prompt/Key。

### 场景 D：无障碍

1. 开启 200% 字号、高对比、减少动态、安静反馈。
2. 设置、复习概览、洞察、AI、Playground 和装扮商店均可完成主任务。
3. 图表有文本摘要；按钮和商品状态可被 TalkBack 读出。
4. AI 流式无闪烁装饰，装扮动画静态化，声音/触觉不触发。

### 场景 E：离线与链接失败

1. 无网络时普通课程、Playground 普通模式、复习概览缓存可用。
2. AI 显示可解释网络错误，不清除已保存配置。
3. GUI/项目链接打不开时提示失败并允许复制。
4. GUI 地址未配置时入口禁用，不打开旧仓库地址。

---

## 33. 明确不接受的“伪完成”

以下做法即使界面看起来变化，也不算完成：

- 只把实验室入口隐藏，但 Release 深链仍能打开并执行作弊操作。
- 只把 AI 工具从设置首页删除，但 API Key 仍明文存 prefs。
- 只给高级页换标题，旧 Anki 参数仍全部铺在一级页面。
- 只修改关于页显示版本，changelog 与 fallback 仍有另一套编号。
- 只增加宝石商品图片，但购买仍可能扣费不解锁，或商品不在主流程显示。
- 只给复习页换卡片样式，后台仍调用 `allEvents()` 并多次全量扫描。
- 只给 Future 加缓存，但数据变化后没有 revision，导致统计长期过期。
- 只把 AI 按钮放进 Playground，但没有消费 `initialMode`，三个按钮进入同一状态。
- 只对 AI token 更新做 debounce，却仍让整个页面 Consumer rebuild。
- 只调用 `imageCache.clear()` 或 GC 就宣称解决内存问题。
- 只统计目录大小就把所有重复内容称为垃圾并一键删除。
- 只在开发机 Debug 模式感觉流畅就通过性能验收。

---

## 34. 实施开始前的最终检查表

- [x] GUI、项目、反馈、发布与隐私正式 URL 已确认或决定暂不上线。（决定：全部暂不上线，ExternalLinkRegistry 全部置 null + 禁用态）
- [ ] Android 基准机型、系统版本和最低内存已记录。（待产品确认）
- [~] 当前对外版本和 changelog 编号策略已确认。（编号已统一 0.x：pubspec 0.7.0+1 ↔ changelog 首项 0.7 ↔ ReleaseManifest；发布 CI 校验未加）
- [~] Plan 1 source/owner、存储清单和 AiCardContext 所需字段可用。（存储清单与卡片识别已就绪；复习统计的 legacy 前缀替换仍待 Plan 1 source 列落地）
- [~] 旧版本升级 fixture 包含 API Key、Fun Lab、宝石、装扮、Legacy/Official Anki 和复习历史。（AI Key 迁移与宝石/装扮迁移各有专属测试 fixture；完整升级链路演练未做）
- [x] 所有内容创作数据都有保留/导出/删除决定。（决定：保留不删——tombstone 明示"草稿不会删除"）
- [~] 所有性能优化都有 before 数据、复现步骤和 after gate。（代码级复现与测试已建：1000-delta 通知上限、单遍索引一致性、有界查询；真机 before/after 基准未采）
- [x] 所有删除旧入口的变更都有 route/recent-task/backup 兼容策略。（wish/textbook 路由→tombstone；recent-task 按 route 名打开 tombstone 不崩溃；备份数据不动）

完成以上检查后，按 §28 的顺序实施。若过程中出现与本文不同的新证据，应先更新“成因等级、数据合同和验收门槛”，再修改实现；不能用临时 UI workaround 掩盖数据或生命周期问题。

---

## 35. 实施状态核对（2026-08-23 第一轮实施）

第一轮实施按 §28.3 推荐顺序完成了全部核心工程项，每一项都有对应测试。
本节逐 Phase 记录交付物、验证方式与遗留项，作为下一轮的基线。

### 35.1 Phase 完成度

| Phase | 状态 | 关键交付 | 验证 |
| --- | --- | --- | --- |
| P2-1 设置导航 | ✅ 完成 | `SettingsDestination`/`SettingsNavController`/`openSettings`；7 目的地 4 分组首页；已访问子页保状态；AI 工具/实验室栏目删除 | `settings_category_list_test`（4 例） |
| P2-2 实验室退场 | ✅ 完成 | Lab 页 kDebugMode 门禁；autoAnswer release 强制关闭 + setAutoAnswer 防护；new_lesson_screen 生产消费点删除 | fun_provider 内联防护 + 手工核对 |
| P2-3 高级页 | ✅ 完成 | 四入口 hub + 旧版与兼容性二级页（症状/副作用/默认值/重启需求标注 + 恢复默认）；Official 内部导入迁入开发者实验室 | settings_category_list_test |
| P2-4 AI 连接安全 | ✅ 完成 | flutter_secure_storage 接入（含会话级降级）；两阶段明文迁移；prefs/密钥分离持久化；草稿+500ms 防抖+显式保存+dispose 冲洗；密钥不回填只显掩码；清除凭据/恢复默认；探测错误分类；Base URL 规范化（https-only，debug 放行 localhost）；解释偏好迁至 AI Hub | `ai_credential_migration_test`（7）+ `ai_api_config_page_test`（3） |
| P2-5 无障碍契约 | ✅ 接口完成 | `AccessibilityCapabilities` 契约 + provider 实现 + `accessibilityOf` | `accessibility_capabilities_test`（2） |
| P2-6 关于/版本/外链 | ✅ 完成 | `ExternalLinkRegistry`（未配置禁用+原因、scheme 校验、失败+复制）；使用指南 tab/asset/解析器/字符串全删；`AppBuildInfo`（无硬编码版本 fallback）；`ReleaseManifest` 单一事实源；changelog.md 重编号 0.x 对齐 | `about_turna_page_test`（5）+ `changelog_page_test` |
| P2-7 装扮宝石账本 | ✅ 核心完成 | schema v19 `gem_ledger`+`cosmetic_entitlements`；`GemLedgerDao` 事务购买（幂等 key）+ 事件幂等 + prefs 幂等迁移；CosmeticProvider 走账本（失败退款补偿） | `gem_ledger_test`（6） |
| P3-1 复习聚合数据层 | ✅ 完成 | `ReviewDashboardRepository`（单遍分类 + `eventsBetween`/`dailyActivityBetween` 有界查询）；`ReviewDashboardSnapshot` 合同；`ReviewDataRevision`（复习写入处 bump）；缓存 + generation 防晚到覆盖 | `review_dashboard_repository_test`（7） |
| P3-2 复习概览 UI | ✅ 完成 | 今日 Hero（目标/进度/CTA）+ due/new/overdue（逾期 0 降权）+ 连续学习 + 7 日轻量图（含文本摘要）+ 今日时间/准确率（空数据=暂无数据）+ 来源 Top5；骨架屏；stale-while-revalidate；下拉刷新等待真实 Future | `review_dashboard_page_test`（4） |
| P3-3 学习洞察页 | 🔶 部分完成 | 二级页 `LearningInsightsRoute` 承载筛选/KPI/曲线/来源（从首页移除）；空数据显示 `—` 不再 100%；旧 provider 双扫描已修 | 洞察页内部固定桶聚合与热力图查询优化待做 |
| P3-4 内容创作退场 | ✅ 完成 | wish/textbook 路由→`ContentAuthoringMovedBody` tombstone（GUI 链接注册表驱动，未配置禁用+说明）；play hub 改单一 AI 助手入口；AI hub 创作区删除；课程管理"AI 设计"退场；草稿保留 | play/ai hub 视图测试更新后全过 |
| P3-5 Playground 融合 | ✅ 核心完成 | `PlaygroundIndex` 单遍可用性+计数（与 assembler 逐模式结果一致性测试）；`PlaygroundSourceRevision` 修订缓存（无关 CourseProvider 通知不重建）；AI 三入口 typed `initialMode`（已消费）；coming-soon 模式禁用态+「即将推出」 | `playground_index_test`（3）+ 页面测试（8） |
| P3-6 Anki AI 上下文 | ✅ 完成 | `AiCardContextResolver`：HTML/JS/path/模板指令净化、reveal 门控（未揭示不送答案）、official 卡 raw-id 禁用、unsupported 态；接入统一复习 AI 入口 | `ai_card_context_resolver_test`（6） |
| P3-7 AI 流式性能 | ✅ 核心完成 | `StreamDeltaCoalescer`（80ms 合批，顺序/Unicode/无损/取消契约）；tutor provider 接入 + `streamingRevision`；页面 Selector 拆分（仅 streaming bubble 高频重建）；`ChatAutoScrollCoordinator`（节流+用户上滑锁定+dispose 取消）；dispose 全面取消（测试抓到并修复真实 dispose-notify 缺陷） | `streaming_pipeline_test`（7）+ `ai_tutor_chat_streaming_test`（2，含 1000 delta < 50 通知实测） |
| P3-8 Home 生命周期 | ✅ 完成 | lazy visited tabs（Offstage + TickerMode）；Play Hub Official due 刷新首次可见 + 5 分钟 TTL | 结构核对（未访问 tab 不挂载） |
| P2-0/P3-0/P2-8/P3-9 | 🔶 部分 | 契约测试随各 Phase 建立（凭据泄漏/版本/外链/实验室不可达）；真机基线、trace 埋点、灰度未做（需设备与发布流程） | — |

### 35.2 测试回归状态

全量 `flutter test`：**1537 通过，本轮新增测试全部通过（55+ 例）**。
确定性失败共 8 个，经 HEAD 干净 worktree 复跑验证**全部在本轮实施开始前即存在**：

- 6 个 golden 基线漂移（dictionary / settings_reminder / srs × light/dark，
  宿主字体渲染差异）；
- 2 个课程树契约测试（dark_mode_text_contrast / wetland_palette 的结构性
  断言，针对"课程页面大改版"前的 course_tree 源码形态）。

另有个别集成测试在并行全量跑时偶发超时、单独运行必过（与本次改动无关）。
play_hub golden 因 AI 助手入口改版已按新 UI 重新生成。

### 35.3 与计划的偏差记录

1. **daily_review_stats 聚合表未新增**（§16.4）：首页今日/7 日数据改由
   有界 SQL 窗口查询（`eventsBetween` + `dailyActivityBetween` GROUP BY
   local day）+ 既有 StudyLog 日聚合承担，查询数固定为 2 条，满足
   "首页返回量不随全历史增长"的出口条件。当洞察页需要 30/90/365 日桶时
   再评估落表与回填。
2. **设置子页仍为页内导航**（§5.3 允许的备选）：SettingsPage 位于 Home
   IndexedStack 内，采用强类型目的地 + 已访问页面保状态（IndexedStack），
   并预留 `openSettings(context, destination, anchor:)` 统一入口；未引入
   AutoRoute 嵌套子路由。
3. **Playground 模式格整体禁用**（§22.4）：会话执行（P2 会话层）未接入前，
   全部模式显示"即将推出"禁用态而非"可用但点击弹 toast"；可用性/计数数据
   仍在后台计算并被索引测试守护。
4. **AI hint/explain providers 尚未接入 coalescer**：本轮完成 tutor 主链路
   （用户报告的卡顿主路径）；hint/explain 复用同一 `StreamDeltaCoalescer`
   为小步后续。
5. **宝石账本与旧 prefs 并行**：账本为购买/解锁的事实源（原子性目标达成），
   旧 `LocalStateKeys.gems` 仍是 UI 钱包快照；earn 事件全面入账与
   "余额=账本投影"的完全切换留待装扮商店扩充时一并做。

### 35.4 下一轮优先级建议

1. 真机性能基线（P3-0/P3-9）：Android 中低端机型 + profile 构建，先采
   §24 预算的 before 数据；
2. 洞察页聚合优化（P3-3 收尾）：固定桶查询 + 365 日热力图不加载全量事件；
3. AI hint/explain 接入 coalescer + 磁盘缓存去留决策（§18.8）；
4. 装扮商店扩充（P2-7 收尾）：槽位/表面/保护券产品化 + earn 事件全面入账；
5. §4.3 无障碍矩阵逐表面审计（P2-5 收尾）；
6. Plan 1 source 元数据落地后替换复习统计的 wordId 前缀推断（§28.1 硬依赖）。
