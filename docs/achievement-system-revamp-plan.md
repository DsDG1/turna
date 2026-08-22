# Turna 成就系统整体焕新实施计划

> 状态：**已实施（2026-08-22，分支 spike/official-anki-core-android）**
> 日期：2026-08-22
> 范围：成就定义、学习指标、解锁与奖励、历史迁移、个人页入口、成就主页、达成反馈、测试与数据导入导出
> 硬约束：**课程成就最终目标保持 500 课，完美课程最终目标保持 100 课，不得下调或删除。**
> 实施记录见文末「§15 实施记录」；各阶段完成情况、偏差与遗留事项都在该节。

## 0. 结论先行

本轮不是只重画成就页，而是把当前分散的“可见成就、隐藏 XP/连续学习里程碑、宝石奖励、个人页统计”统一成一套可信、可迁移、可扩展的成就系统。

目标产品合同：

```text
所有正式学习行为
  -> 更新唯一的权威学习指标
  -> 由同一个成就引擎评估所有层级
  -> 原子化记录新解锁、奖励发放和待展示状态
  -> 在当前完成页或全局反馈队列中告知用户
  -> 成就主页、个人页摘要和导出数据读取同一份状态
```

必须先修复规则和数据，再施工视觉。视觉层不得继续自行推导“是否解锁”，也不得把“当前正在冲刺的等级”当成“已经完成的等级”。

## 1. 不再摇摆的产品决策

1. 课程完成系列的最终层级是 **500 个唯一完成课时**。
2. 完美课程系列的最终层级是 **100 个唯一完美课时**。
3. 上述两个最终目标不因为当前内置课程规模较小而下调；导入课程、未来扩充内容和长期使用均计入同一指标。
4. 中间层级允许调整，以提供早期反馈；调整不得改变 500/100 两个终点。
5. 每个层级都是一枚可解锁徽章；“系列等级”和“已获得徽章数”必须分开表达。
6. 页面展示、奖励发放、已解锁数量必须读取持久化后的统一成就状态，不再各自计算。
7. 解锁自动生效、奖励自动发放，不增加“手动领取”负担；系统需要记录奖励是否已发，保证幂等。
8. 当前连续天数下降不会让历史徽章重新锁定。
9. 同一天 XP 成就读取真实的单日 XP；累计 XP 成就读取总 XP，两者不再混用。
10. “词汇学习”必须以唯一词条或明确的 FSRS 掌握规则为依据，不能继续读取一个没有生产写入者的计数器。
11. 普通成就奖励保持克制；长期终阶优先提供称号、头像环等纪念性奖励，不用巨额宝石替代成就价值。
12. Fun Lab 的“全成就解锁”继续只改变展示效果，不预先消费真实解锁和真实奖励。

## 2. 当前问题与本轮处置

| 当前问题 | 影响 | 本轮处置 |
| --- | --- | --- |
| `AchievementsProvider` 与 `GameMilestoneProvider` 各自解锁 | 同一存储里混有两套 ID，UI 看不到隐藏里程碑 | 合并为一个成就服务和一个版本化仓库 |
| 等级函数在进度为 0 时返回 Lv.1 | 单目标成就可被误判为完成，最终层级提前完成 | 改用 `completedTierCount: 0..N` |
| UI 临时根据计数器判断完成 | 与已发奖励、历史解锁记录不一致 | UI 只消费 `AchievementSeriesProgress` |
| Sage 文案是单日 XP，实际使用累计 XP | 用户看到错误进度 | 拆成“单日专注”和“经验积累”两个指标 |
| Winner 与 Sage 都读取累计 XP | 重复、目标过低 | Winner 重命名并接管统一累计 XP 系列 |
| `wordsLearned` 只初始化/清零 | Scholar 永远不能可靠推进 | 建立唯一词条投影器；未接通前不发布该系列 |
| 课程只在 10 课、完美只在 1 课时写系列 ID | 后续层级没有真实解锁事件和奖励 | 全部层级由统一评估器处理 |
| 无解锁反馈消费者 | 用户获得奖励但不知道原因 | 增加待展示队列和完成页反馈 |
| 成就标题、描述硬编码英文 | 与中文产品界面割裂 | 全部迁入 `AppStrings` |
| 最高旧里程碑奖励远高于当前装饰价格 | 宝石快速失去价值 | 重做奖励表并增加非货币终阶奖励 |

## 3. 新成就目录

### 3.1 层级命名

统一使用以下展示层级；系列不必全部包含八档：

| 层级 | 展示名 | 默认宝石 | 视觉材质 |
| --- | --- | ---: | --- |
| 1 | 萌芽 | 5 | Mist / Reed |
| 2 | 青铜 | 8 | Bronze |
| 3 | 白银 | 12 | Silver |
| 4 | 黄金 | 18 | Gold |
| 5 | 翡翠 | 25 | Emerald |
| 6 | 红宝石 | 35 | Ruby |
| 7 | 紫晶 | 45 | Amethyst |
| 8 | 钻石 | 60 | Diamond |

规则：

- 这是默认奖励，不直接按数组下标硬编码；每个 `AchievementTierDefinition` 明确存储奖励。
- 最终层级可追加称号、头像环或分享卡片样式，但不再额外发放 500～1000 宝石。
- 上线前对完整目录做一次经济模拟；若装饰目录仍只有 40/80 宝石两档，首版成就宝石总投放应设置全局上限或同步扩充装饰。

### 3.2 推荐系列与目标

#### A. 课程行者 `course_journey`

- 指标：`uniqueLessonsCompleted`
- 推荐目标：`[1, 10, 25, 50, 100, 250, 500]`
- 最终目标：**500，不变**
- 计数规则：按稳定的课程/导入课时 ID 去重；重复学习同一课不增加数量。
- 终阶奖励建议：“远行者”称号 + 专属头像环，宝石只按第 7 档默认值发放。

当前目标 `[10, 50, 100, 250, 500]` 的终点保留；新增 1 和 25 是为了让新用户更早看到第一次解锁，以及缩小 10 到 50 之间的反馈空窗。

#### B. 完美主义者 `perfect_journey`

- 指标：`uniquePerfectLessons`
- 推荐目标：`[1, 5, 10, 20, 50, 100]`
- 最终目标：**100，不变**
- 计数规则：同一课从普通完成升级为完美时只增加一次；重复完美不重复累计。
- 终阶奖励建议：“百课无瑕”称号 + 专属徽章光环。

该阶梯保留当前 1、5、20、50、100，仅增加 10，避免 5 到 20 的过长空窗。

#### C. 烈焰不息 `streak_journey`

- 指标：`currentStreakDays` 用于推进，持久化解锁用于保留历史。
- 目标：`[3, 7, 14, 30, 75, 125, 200, 365]`
- 迁移：兼容旧 `streak_3`、`streak_7`、`streak_30`、`streak_100`、`streak_365`。
- 特殊规则：连续中断只改变当前进度，不回收已经获得的层级。
- 365 天终阶建议提供纪念性装饰，不再发放旧版 1000 宝石。

#### D. 经验积累 `xp_journey`

- 指标：`totalXp`
- 目标：`[100, 500, 1000, 5000, 10000, 50000]`
- 处置：合并当前 Winner、Sage 的累计 XP 部分以及隐藏 `xp_*` 里程碑。
- 迁移：精确保留 `xp_1000`、`xp_10000`、`xp_50000` 的已奖励状态。
- 50,000 XP 为长期终阶；不再保留 `[1, 5, 10, 25]` 这种一次课程即可完成的 XP 阶梯。

#### E. 今日专注 `daily_focus`

- 指标：`maxDailyXp`，即历史单日最高 XP，而不是累计 XP。
- 目标：`[50, 100, 250, 500, 1000, 2000]`
- 数据来源：优先从 `StudyLogRepository.readAllDailyStats()` 回填；之后每次记录学习日志时增量更新。
- 特殊规则：跨日按用户本地时区切分；修改系统时间不应重复发奖。
- 文案必须明确“单日获得”，详情页显示个人最高纪录。

#### F. 复习达人 `review_journey`

- 指标：`totalReviewedCards`
- 目标：`[10, 50, 200, 500, 1000, 5000]`
- 计数规则：累计实际提交的卡片作答数，不按“复习会话次数”计数。
- 来源：Turna SRS、语法复习、旧 Anki 和官方 Anki 均应通过统一统计投影计入；撤销正式作答时按账本能力修正。
- 目的：让以 Anki/复习为主的用户也能持续推进成就，而不是只有课程用户能获得反馈。

#### G. 词海拾贝 `vocabulary_journey`

- 指标：第一阶段使用 `uniqueWordsStudied`；未来可迁为更严格的 `masteredWords`。
- 推荐目标：`[10, 25, 50, 100, 250, 500, 1000]`
- “学习过”的定义：词条首次出现在已完成课程或已正式提交的复习中，并按稳定词条 ID 去重。
- 课程完成日志必须携带实际 `wordIds`；当前没有词条 ID 的旧日志不猜测、不伪造。
- 若该投影器在 P2 结束时仍无法覆盖所有正式学习路径，该系列推迟发布，不能继续依赖旧 `wordsLearned`。

### 3.3 首次体验徽章

以下为独立徽章，不形成无限任务列表，也不参与 500/100 两个长期系列的终点：

- `first_lesson`：首次完成课程。
- `first_perfect`：首次完美完成课程。
- `first_review`：首次提交正式复习。
- `first_comeback`：连续中断后重新开始学习。

其中 `first_lesson` 与课程行者第 1 档可选择合并。默认建议合并，避免同一事件弹出两枚含义相同的徽章；`first_perfect` 同理。

## 4. 目标领域模型

### 4.1 成就定义

```dart
enum AchievementMetric {
  uniqueLessonsCompleted,
  uniquePerfectLessons,
  currentStreakDays,
  totalXp,
  maxDailyXp,
  totalReviewedCards,
  uniqueWordsStudied,
}

class AchievementTierDefinition {
  final String id;          // course_journey_001
  final int ordinal;        // 1-based display order
  final int target;
  final int gemReward;
  final String? cosmeticRewardId;
  final AchievementRarity rarity;
}

class AchievementSeriesDefinition {
  final String id;
  final AchievementMetric metric;
  final String titleKey;
  final String descriptionKey;
  final String iconKey;
  final List<AchievementTierDefinition> tiers;
}
```

领域定义不得继续依赖 `IconData`、`Color` 或硬编码界面文案。Flutter 图标、颜色和图片资源由 UI catalog 根据 `iconKey`、`rarity` 解析。

### 4.2 指标快照

```dart
class AchievementMetricSnapshot {
  final int uniqueLessonsCompleted;
  final int uniquePerfectLessons;
  final int currentStreakDays;
  final int totalXp;
  final int maxDailyXp;
  final int totalReviewedCards;
  final int uniqueWordsStudied;
  final DateTime calculatedAt;
}
```

每项指标必须有唯一事实来源：

| 指标 | 权威来源 |
| --- | --- |
| 唯一完成课时 | `completedLessonIds` |
| 唯一完美课时 | `perfectLessonIds` |
| 当前连续天数 | `StreakProvider` |
| 累计 XP | `ScoreProvider` |
| 历史单日最高 XP | `StudyLogRepository` 的每日聚合 |
| 累计正式复习卡数 | 学习日志/正式 review receipt 投影 |
| 唯一学习词条 | 完成课程与复习日志中的稳定 `wordIds` 集合 |

旧的 `lessonsCompleted`、`perfectLessons` 仅用于迁移校验，不能重新成为权威来源。

### 4.3 持久化进度

```dart
class AchievementTierState {
  final String tierId;
  final DateTime unlockedAt;
  final bool rewardGranted;
  final DateTime? rewardGrantedAt;
  final bool seen;
  final DateTime? seenAt;
  final AchievementUnlockOrigin origin; // live / migration / funPreview
}

class AchievementStateDocument {
  final int schemaVersion;
  final Map<String, AchievementTierState> unlockedTiers;
  final DateTime updatedAt;
}
```

必须区分：

- `completedTierCount`：已达到目标的层级数量，范围 `0..tiers.length`。
- `currentProgress`：当前指标值。
- `nextTier`：第一个目标大于当前指标的层级；满级时为空。
- `isSeriesComplete`：只有 `completedTierCount == tiers.length`。

硬性边界：

```text
课程 499 课 -> 最终层级锁定
课程 500 课 -> 最终层级解锁
完美 99 课 -> 最终层级锁定
完美 100 课 -> 最终层级解锁
```

### 4.4 统一评估结果

```dart
class AchievementUnlockResult {
  final String seriesId;
  final String tierId;
  final int target;
  final int gemReward;
  final String? cosmeticRewardId;
  final DateTime unlockedAt;
}
```

评估器是纯函数：输入定义、旧状态和指标快照，输出新解锁列表。持久化、宝石发放、UI 展示分别由服务层负责。

评估必须支持一次跨越多档。例如导入历史数据后课程数从 0 变为 63，应一次解锁 1、10、25、50 四档，但奖励策略由迁移规则决定，不能重复发放。

## 5. 服务与数据流设计

### 5.1 单一写入者

新增统一的 `AchievementService`，职责包括：

1. 从指标投影器读取一致快照。
2. 串行执行评估，防止课程完成、XP、连续天数同时更新时互相覆盖。
3. 先持久化新解锁状态，再通过 `GemsProvider` 和 `CosmeticProvider` 发奖励。
4. 记录 `rewardGranted`，失败时可在下次启动安全重试。
5. 将未展示结果加入反馈队列。
6. 向个人页、成就页和全局反馈宿主发出同一状态流。

串行化可复用 `GemsProvider` 当前 `_writeChain` 模式，但成就状态和奖励需要显式的恢复步骤：

```text
evaluate
  -> persist unlocked tier with rewardGranted=false
  -> grant reward through single writer
  -> persist rewardGranted=true
  -> enqueue unseen result
```

若进程在中间退出，重启恢复器只补发 `rewardGranted=false` 的奖励。

### 5.2 触发点

| 正式行为 | 现有位置 | 新动作 |
| --- | --- | --- |
| 课程完成 | `LessonCompletionCoordinator.complete` | 所有进度、XP、日志写完后评估一次 |
| 通用 SRS 完成 | `UnifiedReviewPage` 完成回调 | 正式 receipt 和日志提交后评估 |
| 语法复习完成 | `GrammarReviewScreen` 奖励结算 | 日志提交后评估 |
| Anki 正式复习 | 统一复习 ledger 成功回执 | 仅对已提交卡计数并评估 |
| App 启动 | 初始化流程 | 执行迁移、未发奖励恢复和一次 reconcile |
| 数据导入/检查点恢复 | import/Fun Lab refresh | 重建指标、评估状态，不重复奖励 |

课程完成流程中，当前成就检查位于学习日志写入之前。新流程应调整为：

```text
XP / 宝石基础奖励
  -> 完成/完美课时 ID
  -> 学习日志（含 wordIds）
  -> 生成一致指标快照
  -> 成就评估与奖励
  -> 完成页展示本次新成就
```

### 5.3 一致性与对账

- 每次启动执行轻量 reconcile：根据权威指标补齐缺失解锁，但绝不重新锁定历史成就。
- state 文档包含 `schemaVersion`；定义目录改变时执行显式迁移。
- 同一 `tierId` 永远只对应一个目标和语义。若目标语义改变，创建新 ID，不复用旧 ID。
- 指标可能下降时，进度条显示当前值；已解锁徽章保持解锁。
- 导出、导入、账户重置和 Fun Lab 快照必须同时覆盖新状态、指标投影和待展示队列。

## 6. 旧数据迁移

### 6.1 新旧存储

- 保留旧键：`achievements.unlocked`，作为 v1 只读迁移输入。
- 新键：`achievements.state.v2`，保存版本化 JSON 文档。
- 新键：`achievements.metric_projection.v1`，只保存无法从现有权威数据低成本重建的集合或累计投影。
- 新键：`achievements.migration.version`，保证迁移只执行一次。
- 至少保留一个稳定版本后再考虑删除 v1 数据；迁移期间不得直接覆写旧列表。

### 6.2 ID 映射

| 旧 ID | 新状态 |
| --- | --- |
| `champion` | 根据实际完成课时回填 `course_journey` 已达层级 |
| `sharpshooter` | 根据实际完美课时回填 `perfect_journey` 已达层级 |
| `xp_1000` | `xp_journey_1000`，已解锁且已发奖励 |
| `xp_10000` | `xp_journey_10000`，已解锁且已发奖励 |
| `xp_50000` | `xp_journey_50000`，已解锁且已发奖励 |
| `streak_3` / `7` / `30` / `365` | 映射对应新连续层级，已发奖励 |
| `streak_100` | 记录为 legacy 100 日纪念状态；新目录若无精确 100 档，不得错误映射到 125 日 |
| `scholar` / `sage` / `wildfire` / `winner` | 不直接视为全系列完成，按权威指标重新计算 |
| 未知 ID | 保存在迁移诊断列表，不发奖励、不导致迁移失败 |

### 6.3 历史回填奖励

默认策略：

1. 根据现有权威数据补记所有已达到的新层级。
2. 所有迁移回填层级标为 `origin=migration`、`rewardGranted=true`，不逐档补发宝石，避免更新后突然注入大量货币。
3. 若产品希望感谢老用户，可统一发放一次有上限的“历史学习纪念礼包”，而不是按所有层级逐项补发。
4. 更新后首次新达到的层级按新奖励表正常发放。
5. 迁移回填徽章可在成就页显示“根据历史学习记录补记”，但不逐个弹出阻塞式庆祝。

### 6.4 500/100 边界迁移

- 完成课时计数优先读取 `completedLessonIds.length`。
- 完美课时计数优先读取 `perfectLessonIds.length`。
- 旧整数计数较大但 ID 集合较小时，不直接采用较大的旧值；记录诊断并以 ID 集合为准。
- 只有实际去重集合达到 500/100 时才迁移为最终层级完成。

## 7. 页面与交互焕新

### 7.1 个人页入口

当前“已解锁 X/6”改为徽章层级统计，例如：

```text
成就
已获得 12/46 枚 · 2 项接近完成
```

入口增加：

- 最近获得徽章的小图标。
- 有未查看成就时显示暖陶土色圆点。
- Fun Lab 全解锁时显示“预览全部”，不得伪装成真实奖励状态。

### 7.2 成就主页结构

从上到下：

1. **收藏概览 Hero**：已获徽章数、总徽章数、完成比例、最近解锁日期。
2. **距离最近**：按 `current / nextTarget` 比例选 1～2 个未完成层级；零进度系列不抢占推荐位。
3. **筛选条**：全部、进行中、已获得；可追加课程、坚持、复习等类别筛选。
4. **两列徽章网格**：展示系列徽章、当前已完成层级和下一目标。
5. **最近获得**：按 `unlockedAt` 倒序；迁移回填与实时解锁可用轻量标签区分。

排序规则：

- “进行中”：接近完成比例降序，再按目录顺序。
- “已获得”：实时解锁时间降序；迁移数据排在实时数据之后。
- “全部”：产品目录顺序固定，避免每次进入页面跳动。

### 7.3 徽章卡片

每张卡至少包含：

- 系列图形和当前材质层级。
- 中文名称。
- 当前进度与下一目标，例如 `63 / 100 课`。
- 已完成层级数量，例如 `4/7`。
- 锁定、进行中、已获得、满级四种明确状态。
- 未查看徽章的 `NEW` 标记。

禁止：

- 满级时显示伪造的 `current/current`。
- 把未达到最终目标的最后进行中层级画成满级。
- 仅靠颜色表达状态。
- 为所有锁定徽章完全隐藏目标；只有真正的彩蛋成就可以隐藏条件。

### 7.4 详情底部面板

点击卡片打开详情：

- 系列故事与学习意义。
- 当前指标。
- 完整层级阶梯。
- 每档目标、奖励和状态。
- 解锁日期。
- 下一步还差多少，例如“再完成 37 课”。
- 最终层级的称号或装饰预览。

### 7.5 达成反馈

反馈分级：

| 场景 | 表现 |
| --- | --- |
| 单个普通层级 | 完成页中的徽章横幅或 2 秒胶囊提示 |
| 同次解锁多个层级 | 一张可展开的“本次获得 N 枚徽章”卡片 |
| 系列最终层级 | Turna 庆祝插画、徽章放大动画、奖励明细 |
| 迁移回填 | 成就页一次性摘要，不逐个弹窗 |

完成页已经存在课程庆祝对话框，新成就应成为该总结的一部分，不能在关闭课程完成弹窗后继续连弹多个模态框。

交互要求：

- 轻触反馈和声音服从系统/应用设置。
- 尊重系统“减少动态效果”；关闭缩放、旋转、粒子，只保留淡入。
- 反馈队列必须在安全的导航宿主上消费，页面销毁不能丢失 `seen=false` 状态。
- 用户点击“查看成就”后定位并高亮刚解锁的层级。

## 8. 视觉规范

### 8.1 品牌角色

- 结构色：`brandTeal` / `brandReed`。
- 成就与完成：`anatolianClay` / `warmSand`。
- 稀有度材质：使用现有 Bronze、Silver、Gold、Emerald、Ruby、Amethyst、Diamond 徽章资产语义。
- 成功绿只用于即时成功反馈，不作为整页成就主色。
- 深色模式使用同一材质层级，但重新校验徽章文字、描边和锁定蒙层对比度。

### 8.2 资产策略

现有 `badge_*_blank.png`、`achievement-scholar.png`、`achievement-sage.png` 尚未形成统一页面语言。实施时：

1. 先确认采用“统一徽章底座 + 系列中心图形”方案。
2. 每个系列只维护一个中心图形；稀有度由底座材质变化，不为每一级重画整套插画。
3. 锁定态使用轮廓、锁图标和文字共同表达，不简单把彩色图降透明度。
4. 终阶可增加克制光环，普通层级不使用持续动画。
5. Turna 只出现在页面 Hero、空状态和终阶庆祝，不占据每张徽章卡片。

## 9. 文件级施工清单

### 9.1 领域层

新增建议：

- `lib/domain/achievements/achievement_metric.dart`
- `lib/domain/achievements/achievement_definition.dart`
- `lib/domain/achievements/achievement_state.dart`
- `lib/domain/achievements/achievement_unlock_result.dart`
- `lib/domain/achievements/achievement_catalog.dart`

修改/淘汰：

- 将 `lib/domain/achievement.dart` 的等级算法替换为明确的完成层级语义；迁移结束后删除旧模型。
- 领域层去除 Flutter `IconData` 和 `Color` 依赖。

### 9.2 应用层

新增建议：

- `lib/application/achievements/achievement_service.dart`
- `lib/application/achievements/achievement_evaluator.dart`
- `lib/application/achievements/achievement_metric_projector.dart`
- `lib/application/achievements/achievement_migration_service.dart`
- `lib/application/achievements/achievement_feedback_queue.dart`

合并/替换：

- `AchievementsProvider` 收敛为统一只读状态入口或被 `AchievementService` 取代。
- `GameMilestoneProvider` 的 XP/streak 定义迁入统一 catalog，迁移完成后删除。
- `AchievementConfig` 只保留临时 v1 迁移常量，随后删除。
- `GameProvider.incrementScore` 不再直接持久化成就列表。
- `LessonCompletionCoordinator` 在所有权威写入结束后统一评估。
- `StudyStatsProvider.recordActivity` 提供足够的卡数、词条 ID 和单日 XP 数据。

### 9.3 存储与系统功能

修改：

- `LocalStateKeys` 增加 v2 状态、投影和迁移版本键。
- `ExportService` 纳入 v2 状态及必要投影。
- `FunLabSnapshotService` 纳入 v2 键并保持预览语义。
- 账户重置清除 v2 状态、投影、反馈队列和迁移标记。
- DI 注册统一服务，重新生成 `injection.config.dart`。

### 9.4 UI

重构建议：

- `lib/views/profile/achievements_page.dart`
- `lib/views/profile/widgets/achievements.dart`
- `lib/views/profile/profile_screen.dart`

新增建议：

- `achievement_overview_header.dart`
- `achievement_nearest_card.dart`
- `achievement_filter_bar.dart`
- `achievement_badge_grid.dart`
- `achievement_badge_card.dart`
- `achievement_detail_sheet.dart`
- `achievement_unlock_banner.dart`
- `achievement_finale_dialog.dart`

文案：

- 所有系列名、说明、进度单位、奖励、迁移提示、空状态和无障碍标签进入 `AppStrings`。

## 10. 分阶段施工计划

### P0：冻结产品合同与建立回归网

目标：先让 500/100 等关键含义不可被后续修改破坏。

任务：

1. 将本文目录和目标作为代码 catalog 的唯一来源。
2. 新增纯领域边界测试，明确完成层级数量从 0 开始。
3. 为当前 v1 ID、存储和奖励建立迁移 fixture。
4. 记录现有账户在 0、1、10、99、100、499、500 等边界的预期状态。
5. 建立现有成就页的 light/dark 基线截图，作为重做前对照，不作为新设计约束。

退出标准：

- 499/500 和 99/100 边界测试存在且语义无歧义。
- 新目录 ID 唯一、目标严格递增、奖励非负、文案键和资源键可解析。

### P1：统一领域模型与纯评估器

目标：在不接 UI 的情况下得到正确、幂等的解锁结果。

任务：

1. 实现 definition、tier state、metric snapshot 和 unlock result。
2. 实现 `completedTierCount`、`nextTier`、`isSeriesComplete`。
3. 实现一次跨多级、重复评估、指标下降不回锁。
4. 实现 catalog contract tests。
5. 保留 v1 代码路径但停止新增功能。

退出标准：

- 纯评估器不依赖 Flutter、Prefs、Provider 或 GetIt。
- 相同快照重复评估返回零个新解锁。
- 跳跃式增长准确返回所有中间层级。

### P2：指标投影和正式学习路径接入

目标：所有发布成就都有真实、唯一、可重建的指标来源。

任务：

1. 接入唯一完成课时、唯一完美课时、当前 streak、总 XP。
2. 从每日统计实现历史单日最高 XP。
3. 从正式复习回执/日志实现累计复习卡数。
4. 让课程日志携带实际 `wordIds`，实现唯一学习词条集合。
5. 课程、SRS、语法复习、Anki 正式路径在提交完成后触发统一评估。
6. 对统计不可用的来源 fail closed，不伪造 0 或猜测数量。

退出标准：

- 每个公开系列都有文档化权威来源。
- 重复课程、重复完美、重复回调不会增加去重指标。
- “单日专注”不再读取累计 score。
- Scholar 若无法可靠投影则保持未发布状态。

### P3：v2 仓库、奖励和迁移

目标：安全保存新状态，并无重复奖励地承接所有旧账户。

任务：

1. 实现 versioned repository 和串行写入。
2. 实现 v1 -> v2 ID 映射与未知 ID 诊断。
3. 实现奖励两阶段状态和启动恢复。
4. 更新导出、导入、账户重置、Fun Lab 快照。
5. 加入启动 reconcile。
6. 验证旧 `champion`、`sharpshooter`、`xp_*`、`streak_*` fixture。

退出标准：

- 迁移重复执行不会改变余额或重复插入层级。
- 在“记录解锁”和“完成奖励”之间模拟崩溃，重启只补发一次。
- v1 数据仍可恢复，未知 ID 不丢失也不阻断启动。

### P4：成就主页与个人页焕新

目标：把系统从统计列表升级为可浏览的徽章收藏。

任务：

1. 实现收藏概览、距离最近、筛选和徽章网格。
2. 实现系列详情与完整阶梯。
3. 个人页改为徽章数和未查看状态。
4. 接入中文文案、单位、复数和无障碍标签。
5. 完成 light/dark、小屏、横屏、文字放大 200% 的布局适配。
6. 为减少动态效果和屏幕阅读器补齐语义。

退出标准：

- UI 不直接读取原始 prefs，也不自行判断解锁。
- 满级和进行中的最后一档视觉不会混淆。
- 500/100 系列详情准确展示最终目标。

### P5：即时反馈与纪念奖励

目标：让用户清楚感知“为什么解锁、获得了什么、下一步是什么”。

任务：

1. 实现 unseen feedback queue。
2. 课程完成页内嵌成就横幅。
3. 复习完成页接入同一反馈组件。
4. 多层级合并展示，终阶使用独立庆祝表现。
5. 接入宝石、称号和头像环奖励明细。
6. 完成反馈被打断、页面销毁、应用重启后的恢复测试。

退出标准：

- 解锁不会静默发生。
- 同一层级最多展示一次“新获得”，但用户仍可在成就页永久查看。
- 一次跨多档不会连续弹出多个阻塞对话框。

### P6：删除旧路径与经济校准

目标：结束双系统并完成发布前收口。

任务：

1. 删除 `GameMilestoneProvider`、旧 `AchievementConfig` 和未使用 stream。
2. 删除 `AchievementType` 中无实际语义的旧分支。
3. 清理旧硬编码英文和未使用图标/资产。
4. 模拟新用户、课程型用户、复习型用户和高历史用户的奖励总量。
5. 根据装饰价格校准宝石，必要时同步扩充装饰目录。
6. 更新 changelog、测试基线和架构说明。

退出标准：

- 仓库内只有一套生产成就定义、一套解锁引擎和一个状态写入者。
- 不再有任何生产代码写入 v1 `achievements.unlocked`。
- 全量测试和静态分析不新增错误。

## 11. 测试计划

### 11.1 领域测试

每个系列至少覆盖：

- 0 进度时完成层级为 0。
- 目标前一值不解锁。
- 正好达到目标时解锁。
- 超过目标时保持解锁。
- 一次跨越多个目标。
- 重复评估幂等。
- 指标回退不重新锁定。
- 空层级、重复 ID、非递增目标在 catalog contract 中失败。

两个固定终点必须有显式命名测试：

```text
course journey does not complete at 499
course journey completes exactly at 500
perfect journey does not complete at 99
perfect journey completes exactly at 100
```

### 11.2 应用与并发测试

- 课程完成、完美、XP 和 streak 同一流程更新时不丢层级。
- 两个并发完成回调不会重复发奖励。
- 奖励失败后可恢复，成功后不重放。
- 重复课程 ID 不增长课程指标。
- 同一课程后续升级为完美只增长一次完美指标。
- streak 中断后旧层级保留。
- 本地跨日后 daily XP 正确切换。
- 撤销复习后卡数投影符合账本合同。

### 11.3 迁移测试

- 空账户。
- 只有 `champion` / `sharpshooter` 的旧账户。
- 拥有全部 `xp_*` / `streak_*` 的高进度账户。
- 混合未知 ID。
- 旧整数计数与 ID 集合冲突。
- 迁移中断后重启。
- 迁移后导出再导入。
- Fun Lab 全解锁不污染真实状态或奖励。

### 11.4 Widget 与 Golden

- 未开始、进行中、刚解锁、满级、迁移回填。
- 一次获得多枚徽章。
- light/dark。
- 320px 小屏和大屏。
- 文本缩放 1.0、1.5、2.0。
- 减少动态效果。
- 中文长文案无截断。
- 屏幕阅读器可读出名称、状态、进度、下一目标和奖励。

### 11.5 集成测试

- 完成第 1、10、25、50、100、250、500 个唯一课时。
- 完成第 1、5、10、20、50、100 个唯一完美课时。
- 复习完成后同一成就在完成页与成就页一致。
- 重新启动应用后 unseen 状态和奖励余额一致。
- 账户重置后所有真实状态清零，默认装饰恢复。

## 12. 发布与回滚

### 12.1 发布策略

建议分两个版本：

1. **数据版本**：先上线 v2 仓库、迁移、统一评估器和双读校验，旧 UI 暂时读取 v2 adapter。
2. **体验版本**：确认迁移稳定后上线新成就主页、反馈队列和终阶奖励，再删除 v1 写路径。

双读期只用于诊断：若 v1 与 v2 不一致，记录日志但以 v2 权威状态为准；不得同时发两套奖励。

### 12.2 回滚原则

- 回滚 UI 不回滚 v2 数据。
- v1 旧键在稳定期内保留，因此旧版本仍可启动，但不会认识新增层级。
- 新版本再次启动时从 v2 恢复，不重复迁移和奖励。
- 任何迁移异常都不能阻止课程或复习主流程；成就评估失败应记录错误并在 reconcile 时补偿。

## 13. 完成定义

只有同时满足以下条件，才能称为“成就系统整体焕新完成”：

1. 500 课和 100 完美课两个最终目标保持不变，边界测试通过。
2. 所有可见成就都有真实数据来源，没有永远为 0 的伪指标。
3. 页面、奖励和个人页摘要读取同一状态。
4. 旧 XP/streak 隐藏里程碑已迁入可见目录或明确兼容，不再静默发奖。
5. 解锁、奖励和反馈在并发、重启、迁移后仍严格一次。
6. 课程用户、复习用户和 Anki 用户都有长期可推进系列。
7. 成就页具备收藏概览、最近解锁、距离最近、筛选、徽章网格和系列详情。
8. 中文、深色模式、文字放大、减少动态效果和屏幕阅读器均通过验证。
9. v1 生产写路径被删除，仓库中只剩一套成就引擎。
10. 全量 `flutter test`、相关 golden 和 `flutter analyze` 不新增失败。

## 14. 建议的首个施工切片

第一批只做正确性，不碰大规模视觉：

1. 建立新 catalog，固定本文推荐目标。
2. 实现 `completedTierCount` 纯函数与 500/100 边界测试。
3. 实现 v2 state repository 和 v1 migration fixture。
4. 接入课程完成、完美、总 XP、streak 四个已有可靠指标。
5. 用临时 adapter 让旧成就页读取 v2 状态。

该切片完成后，系统已经不再提前满级、不会重复发奖励、旧数据可迁移；随后再接单日 XP、复习卡数、词汇投影和全新 UI，风险最低。

## 15. 实施记录（2026-08-22）

本轮按 P0→P6 一次性完成施工。验证状态：`flutter analyze` 零 error（新代码零新增告警）；成就相关的领域/应用/集成/组件测试（70 项）全部通过；全量 `flutter test` 中仅存的失败为与本轮无关的存量问题——8 个 golden 像素差（基线 HEAD 上同样失败，环境字体渲染差异）与 2 个 Anki 导入界面测试（并行 anki 工作流的 GetIt 注册问题，对应文件在本轮开始前已处于修改状态）。以下记录落地情况、与计划的偏差和遗留事项。

### 15.1 落地文件清单

领域层（新增，无 Flutter 依赖）：

- `lib/domain/achievements/achievement_definition.dart` — 指标枚举、稀有度材质（含默认宝石表）、层级/系列定义、`completedTierCount` / `nextTierAfter` 纯函数。
- `lib/domain/achievements/achievement_state.dart` — `AchievementTierState`（两阶段奖励 + seen 标记 + origin）、版本化 `AchievementStateDocument`（schemaVersion=2，含迁移诊断）、`AchievementSeriesProgress` UI 只读视图。
- `lib/domain/achievements/achievement_unlock_result.dart` — 评估器输出的解锁结果。
- `lib/domain/achievements/achievement_catalog.dart` — 七个系列的唯一目录（含目标阶梯与终阶纪念奖励 ID）。

应用层（新增）：

- `lib/application/achievements/achievement_evaluator.dart` — 纯评估器 + `AchievementMetricSnapshot` + `AchievementCatalogContract` 契约校验。
- `lib/application/achievements/achievement_metric_projector.dart` — 指标投影器 + 持久化投影（`achievements.metric_projection.v1`：复习卡数单调计数、历史单日最高 XP、已学词条集合）。
- `lib/application/achievements/achievement_state_repository.dart` — v2 状态仓库，写链序列化。
- `lib/application/achievements/achievement_migration_service.dart` — v1→v2 一次性迁移（精确 ID 映射 + 权威回填 + 未知 ID 诊断）。
- `lib/application/achievements/achievement_service.dart` — 唯一写入者：评估→持久化→发奖→标记两阶段流、启动恢复、reconcile、反馈队列（由 `seen=false && origin=live` 派生）、账户重置。

UI（新增 `lib/views/profile/achievements/`）：

- `achievement_ui_catalog.dart` — 图标/颜色/文案/单位/纪念奖励解析（领域层零 Flutter 依赖）。
- `achievement_badge_card.dart` — 徽章卡片（锁定=轮廓+锁、四态明确、NEW 标记、满级不伪造 current/current）。
- `achievement_overview_header.dart` — 收藏概览 Hero + 距离最近卡片。
- `achievement_filter_bar.dart` — 全部/进行中/已获得筛选。
- `achievement_detail_sheet.dart` — 详情底部面板（完整阶梯、每档目标/奖励/状态、解锁日期、下一步、终阶纪念预览、历史补记标签）。
- `achievement_unlock_banner.dart` + `achievement_feedback_banner.dart` — 完成页反馈横幅与队列消费者（监听式，页面销毁不丢 seen 状态）。

修改：

- `LessonCompletionCoordinator` — 顺序改为 XP/宝石 → 课时 ID → 学习日志（含 wordIds）→ 词条投影 → **唯一评估点**。
- `LessonViewModel` — 提取 `lessonWordIds()`，完成时传递真实词条 ID。
- `UnifiedReviewPage` / `GrammarReviewScreen` — 复习完成后按卡片数记录投影并评估。
- `MatchWordsPage` — 匹配游戏得分后触发评估。
- `GameProvider.incrementScore` — 移除里程碑双写；不再有任何生产代码写 v1 `achievements.unlocked`。
- `main.dart` — 启动序列：迁移 → 恢复未发奖励 → reconcile（失败不阻塞主流程）。
- `ExportService` / `FunLabSnapshotService` / 账户重置 — 纳入 v2 状态、投影、迁移标记；Fun Lab 恢复后 reload。
- `profile_screen.dart` — 入口改为「已获得 X/Y 枚徽章 · N 项接近完成」+ 陶土色未读圆点。
- `LocalStateKeys` — 新增 `achievementsStateV2` / `achievementsProjectionV1` / `achievementsMigrationVersion`；v1 键保留为只读迁移输入。

删除（P6）：

- `lib/application/achievements_provider.dart`、`lib/application/game_milestone_provider.dart`、`lib/core/achievement_config.dart`、`lib/domain/achievement.dart`、`lib/views/profile/widgets/achievements.dart`。
- 仓库中只剩一套生产成就定义、一个解锁引擎、一个状态写入者。

### 15.2 测试

- `test/domain/achievement_domain_test.dart` — 重写为目录契约（ID 唯一、目标严格递增、宝石=稀有度默认且 ≤60、500/100 硬约束、词海拾贝未发布、契约拒绝重复/平坦/空目录）+ 纯评估器（0 进度、边界不解锁、恰好解锁、跨档、幂等、回退不回锁）。
- `test/application/achievements/achievement_migration_service_test.dart` — 空账户、权威回填（63/499/500）、旧计数冲突以 ID 集为准、xp_*/streak_* 精确映射、streak_100 不误映射 125、旧系列名按指标重算、未知 ID 诊断、强制重跑幂等。
- `test/application/achievements/achievement_service_test.dart` — 首课解锁+恰好一次发奖、重复评估幂等、跨档一次通过、streak 回退保留、重复课时去重、XP 里程碑、复习增量、两阶段崩溃恢复（补发一次且幂等）、并发不重复解锁/发奖、反馈队列一次性消费、resetAll、词条集合累积。
- `test/helpers/achievement_test_stack.dart` — 真实 v2 组件栈测试辅助（共享 LessonProgressProvider 实例，镜像 DI 单例语义）。
- 修复既有测试：`game_provider_test`（v1 不再写入）、`lesson_viewmodel_flow_test`（真实服务 + 13=5+8 宝石断言）、`mastery_dialog_stats_test`、`fun_lab_snapshot_service_test`（v2 键 + 预览不消费真实状态）、`wetland_palette_contract_test`。

### 15.3 与计划的偏差

1. **反馈队列无独立存储键**：队列由状态文档中 `seen=false && origin=live` 派生，导出/快照天然覆盖（比独立键少一份需要同步的状态）。
2. **徽章视觉**：首版以「系列图标 + 稀有度材质色环」实现 §7.3/§8.2 的状态语义；统一徽章底座插画资产（§8.2）留待设计资源到位后替换，`iconKey`/`rarity` 抽象已就位。
3. **词海拾贝（vocabulary_journey）按计划条件保持未发布**（`published: false`）：课程日志已开始携带 wordIds 并累积投影，但复习路径尚未携带词条 ID，覆盖率不满足发布条件；不读取旧 `wordsLearned`。
4. **发布策略**：§12.1 的双版本灰度在本仓库直接一步到位（数据层与体验层同批落地）；v1 键保留只读，回滚旧版本仍可启动。
5. **今日专注详情页**显示「个人最高纪录」数值；每日跨日切分沿用 `StudyLogRepository` 的本地日期键。

### 15.4 遗留事项（后续迭代）

- 复习日志携带词条 ID 后发布词海拾贝系列（投影数据已在累积）。
- 徽章底座/系列中心图形插画资产与终阶光环动画（§8.2）。
- Golden 基线与 light/dark、文字放大 200% 的截图回归（§11.4）。
- 上线前的奖励经济模拟脚本与装饰目录扩充评估（§3.1、P6 任务 4）。
- 称号/头像环的佩戴 UI（`cosmeticRewardId` 已持久化并在详情面板展示预览）。
- 双读期诊断日志（§12.1）在确认迁移稳定后移除。
