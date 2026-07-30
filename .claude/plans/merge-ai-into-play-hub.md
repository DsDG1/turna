# 合并 AI 页到练习 Hub + 重设计 AI 页

## 目标
1. 移除底部 AI 独立标签（5 -> 4 标签：学习 / 练习 / 我的 / 设置）。
2. 在「练习」Hub 加入紧凑的「AI 助手」分区：2 个快捷入口 + 引擎状态提示 +「全部」链接。练习页保持「入口」定位，不臃肿。
3. 完全重设计 AI 页（改为 push 路由），复用练习 Hub 的 `_SoftCard` 设计语言，达到美观、流畅、风格一致。

确认的方案（用户已选）：**混合**——练习页放快捷入口 + 独立 AI 页（push）；**4 标签导航**。

---

## 关键事实（已勘查）
- 底部导航 5 标签：学习(0)/练习(1)/我的(2)/设置(3)/AI(4)。`TabDestination` **没有** AI 常量，也无深链指向 tab 4（仅 `new_lesson_screen.dart` 用 `switchTo(settings)`）。移除安全。
- 练习 Hub 的精美组件全在 `play_hub_screen.dart` 内私有：`_SoftCard` / `_AccentIconChip` / `_CountBadge` / `_SectionTitle` / `_QuickPlayHero` / `_FocusTile` / `_ReviewTile` / `_ToolsTile`，基于主题感知 `softTint` / `softBorder` / `softCardShadow`。
- 现 AI Hub（`ai_hub_page.dart`）是旧朴素风格：`cardBg`+`dividerBg` 描边、`_Chip`、`ListTile`、`_StartTile`——与练习页风格脱节。它是 `StatelessWidget` + `SafeArea`+`CustomScrollView`，**无 Scaffold**（因为是 tab）。`@RoutePage()` 已在。
- `AiHubRoute` 是 `routing.dart` 里独立的受保护路由（push 用），保留即可，无需 codegen。
- 引擎状态源：`AiEngineConfigHolder`（`@lazySingleton`+`ChangeNotifier`），`config.isComplete` / `config.preset.label` / `modelChat` / `modelJson` / `apiKey`。配置入口 `AiApiConfigSheet(provider: AiCourseProvider)`（`AiCourseProvider` 已在 `providers.dart` 注册）。
- 深度讲解可用性门控：`AiHintProvider.context != null`。
- 无测试引用 AI tab / `AiHubAppBar` / 标签数——测试零改动预期。

---

## 实施步骤

### Step 1 — 抽取共享组件到 `lib/views/play/components/play_tiles.dart`
把练习 Hub 私有组件**转为 public**搬到共享文件，供两页复用，保证风格完全一致：
- `SoftCard`、`AccentIconChip`、`CountBadge`、`SectionTitle`（去 `_`）
- `QuickPlayHero`、`FocusTile`、`ReviewTile`、`ToolsTile`（去 `_`）
- API 保持不变（参数签名一致）；`play_hub_screen.dart` 改为 import 这些。

### Step 2 — 练习 Hub 新增「AI 助手」分区（`play_hub_screen.dart`）
在「复习中心」与「工具」之间插入 sliver 分区：
- `SectionTitle`：`playAiAssistantTitle`（「AI 助手」）
- 2 列 `ReviewTile` 行：
  - 设计课程 -> `AiWishChatRoute`（accent: `amethystLeague` 紫，给 AI 独立宝石色身份）
  - 导入教材 -> `TextbookImportRoute`（accent: `peacockCyan`）
- 引擎状态 + 「全部」行（`SoftCard`，accent `peacockTeal`）：
  - 左：齿轮 icon + 状态文本（`Selector<AiEngineConfigHolder,bool>` on `isComplete`）：就绪显示「引擎就绪」+ success 对勾；未配置显示「未配置 · 点击设置」+ warning，点击 -> `AiApiConfigSheet`
  - 右：「全部 AI 功能 ›」文字按钮 -> `context.router.push(const AiHubRoute())`

### Step 3 — 重设计 AI 页（重写 `lib/views/ai/ai_hub_page.dart`）
改为 push 路由，外包 `Scaffold` + 返回按钮 `AppBar`（仿 `PlayAppBar`：icon + 「AI 助手」标题）。`CustomScrollView` 三段：
1. **Hero** — `QuickPlayHero` 风格渐变卡（teal->cyan）：展示 preset + chat/json 模型 + 脱敏 key；`!isComplete` 时叠 warning chip「未配置」可点 -> `AiApiConfigSheet`；整卡可点 -> 打开配置 sheet。替代原朴素 card+chips。
2. **继续** — `SectionTitle` + 最近任务渲染为 `ToolsTile` 风格行（accent icon chip + summary + kind 标签 + chevron）；空态用 `SoftCard` + `aiHubContinueEmpty`。
3. **开始新的** — `SectionTitle` + 2×2 `ReviewTile` 宫格（设计课程 / 导入教材 / 按错题复习 / 弱词专项）+ 深度讲解 tile（`AiHintProvider.context == null` 时置灰）。保留现有 `_openSheet`（`TutorLaunchSheet` / `AiDepthTutorSheet`）与 `_navigateByRoute` 逻辑。

保留全部既有行为：`AiRecentTasksProvider` 续学列表、`AiHintProvider` 深度讲解门控、tutor sheet 启动、route 续跳。

### Step 4 — 移除底部 AI 标签（5 -> 4）
- `lib/views/home/home_page.dart`：`screens` 删 `AiHubPage`，`appBars` 删 `AiHubAppBar`，删对应 import。
- `lib/views/home/components/bottom_navigator.dart`：删第 5 个 `_NavItem`（AI）。索引自然回落 学习(0)/练习(1)/我的(2)/设置(3)，与 `TabDestination` 常量一致。
- `lib/views/ai/components/ai_hub_app_bar.dart`：删除（仅 home_page 引用，已确认）。
- `routing.dart`：`AiHubRoute` 保留（仍被练习页 push）。无需 codegen。

### Step 5 — 文案（`lib/l10n/app_strings.dart`）
新增：
- `playAiAssistantTitle` -> 'AI 助手'
- `playAiEngineReady` -> '引擎就绪'
- `playAiEngineNotConfigured` -> '未配置 · 点击设置'
- `playAiViewAll` -> '全部 AI 功能'
- `aiHubSubtitle` -> 'AI 辅助学习中心'

复用既有：`aiHubStartWish` / `aiHubStartTextbook` / `aiHubStartTutorMistakes` / `aiHubStartTutorWeak` / `aiHubStartDepthTutor` / `aiHubContinue` / `aiHubContinueEmpty` / `aiHubNew` / `aiHubHeroIncomplete`。

---

## 涉及文件
- **新增**：`lib/views/play/components/play_tiles.dart`（抽取共享组件）
- **改**：`lib/views/play/play_hub_screen.dart`（import 组件 + 新增 AI 分区）
- **重写**：`lib/views/ai/ai_hub_page.dart`（共享组件重设计 + Scaffold）
- **改**：`lib/views/home/home_page.dart`（删 AI tab）
- **改**：`lib/views/home/components/bottom_navigator.dart`（删 AI 导航项）
- **删**：`lib/views/ai/components/ai_hub_app_bar.dart`
- **改**：`lib/l10n/app_strings.dart`（新增文案）
- **无 codegen**（路由/模型未变）

## 验证
- `flutter analyze`
- `flutter test`（既有 AI/play 测试；预期零改动，若有引用按需更新）
- 手测：4 标签导航；练习页 AI 分区；push 进 AI 页；引擎就绪/未配置两态；tutor sheet 仍可启动；深浅色模式观感。

## 风险/备注
- `amethystLeague` 紫作 AI accent：与复习宫格区分，仍属宝石色板；实现时确认 `softTint` 暗色下可读。
- AI 页改为带 Scaffold 的 push 页后，`AiHubAppBar`（zero-height stub）不再需要——删除。
- 配置 sheet 入口在 Hero 与练习页状态行两处均可达，确保未配置态有清晰引导。
