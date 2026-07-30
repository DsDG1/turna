# 练习页 (PlayHub) 视觉重构方案

## 背景

当前 `lib/views/play/play_hub_screen.dart` 走的是「半拟物彩色玻璃 + 极光底层 + BackdropFilter 模糊」路线：底层有 3 个径向光斑、整页一层模糊、上层是 4 层结构的 `_GlassCard`（基座 + 描边 + 着色渐变 + 顶部高光条）。视觉效果偏「重」、深、装饰性强。

目标图（如附件）走的是完全相反的方向：**轻盈、软着色、平面微浮起**——
- 取消极光底层
- 取消 BackdropFilter 模糊
- 卡片用低 alpha accent 着色（≈ 0.10–0.15）+ 1px 微描边
- 图标 chip 是 accent 实色更深一档（alpha 0.20 左右）
- 标题用 accent 着色，count 用主文字色
- 行动入口（开始/箭头）也用 accent

整体观感：从「深色拟物玻璃」切换到「亮色 pastel tinted card」，更接近 Duolingo / 多邻国那种轻量学习应用的风格。

## 目标页结构（与图一致）

```
AppBar   练习  (extension 图标 + 标题，现状保持)
─────────────
[ Hero ]   快速练习 · 尽快匹配单词     (filled teal gradient, 白字, 闪电)
─────────────
今日重点
[ 错题复习 | 复习 ]   (2 列等宽，每张高 190，无 PageView)
─────────────
复习中心
[ 薄弱单词 | 语法复习 ]   (2x2 网格，1.6 aspect ratio)
[ Anki 复习 | 复习   ]
─────────────
```

注：图中只展示 4 个区段。当前代码还有「工具（复习进度 / 词典）」两个 `_PlayHubCard`，图里没体现；这次**保留**它们作为底部的「更多工具」区，避免删功能。

## 关键改动

### 1. 删除极光底层和 BackdropFilter

`build` 末尾的 `Stack`：
- 去掉 `_AuroraBackground` 整个组件
- 去掉 `BackdropFilter`
- `body` 直接 return `CustomScrollView`，外层用 `RepaintBoundary` 包一层

→ 文件瘦身约 70 行，PageView 控制器也可以继续保留（虽然本页不再用，但先不动避免大改）。

### 2. 新增轻量级卡片样式 `_SoftCard`

不替换现有的 `_GlassCard` / `_PlayHubCard` / `_FocusCard` / `_ReviewCell`，而是**重新写一组**更适合浅色 pastel 风格的组件：

| 组件 | 角色 | 关键样式 |
|------|------|---------|
| `_SoftCard` | 基础容器 | 底色 = accent @ 0.10；1px 描边 = accent @ 0.20；圆角 20；阴影 = accent @ 0.08 blur 10 offset (0,4) |
| `_QuickPlayHero` | 顶部「快速练习」 | 渐变 teal→cyan；白字；白色闪电 chip；右侧箭头白 |
| `_FocusTile` | 今日重点 2 列卡 | 宽 = (屏宽 - 40 - 12) / 2，高 190；title = accent w800；count = 主文字色 w800 22pt；底部「开始 ›」accent |
| `_ReviewTile` | 复习中心 2x2 卡 | aspect 1.6；左上角 icon chip = accent @ 0.22 底 + accent 图标；右下角箭头 accent |

每张卡的底色都用 accent.withValues(alpha: 0.10) 当 fill（hero 例外用实色渐变），这样 4 个复习宫格也能根据功能区分配不同 accent，配色方案保持一致。

### 3. 配色映射（保持现有 accent 体系）

| 功能 | 当前 accent | 备注 |
|------|------------|------|
| 快速练习 (hero) | `peacockTeal` | 改用 teal→cyan 渐变 |
| 错题复习 | `error` (red) | 改为更柔和的 `errorLight` (0xFFFF6B6B) |
| 复习 (今日重点) | `success` (0xFFFFD93D 黄) | 保持 |
| 薄弱单词 | `warning` (0xFFFF9F43 橙) | 保持 |
| 语法复习 | `peacockTeal` | 保持 |
| Anki 复习 | `peacockCyan` | 保持 |
| 复习 (复习中心) | `success` (黄) | 保持 |

图里的「错题复习」用偏珊瑚红/粉色，比当前的 `error (0xFFE74C3C)` 柔和；切到 `errorLight` 即可。其他 4 个复习宫格的色彩和图基本对得上。

### 4. 布局细节

- **今日重点**：把现在的 `PageView + _FocusCardPage` 替换成 `Row(children: [Expanded(_FocusTile), SizedBox(12), Expanded(_FocusTile)])`。
- **复习中心**：`GridView.count(crossAxisCount: 2, childAspectRatio: 1.6)` 保持不变，**但** inner widget 从 `_ReviewCell` 替换成 `_ReviewTile`。
- **快速练习**：保留 `_PlayHubCard(filled: true)` 的结构，但 inner widget 换成新的 `_QuickPlayHero`（独立组件，便于彻底重写风格）。
- **工具区**：保留现有「复习进度」「词典」两张卡，作为底部「更多工具」section；为了视觉一致，卡片样式也改用 `_SoftCard`（不是 filled）。

### 5. 可复用的工具方法

在 `VarnamalaTheme` 里加 2 个 helper：

```dart
/// 浅色 tinted 卡片底色（accent @ 0.10 浅色 / 0.14 深色）
static Color softTint(BuildContext, Color accent) => _isDark(context)
    ? accent.withValues(alpha: 0.16)
    : accent.withValues(alpha: 0.10);

/// 浅色 tinted 卡片描边
static Color softBorder(BuildContext, Color accent) => _isDark(context)
    ? accent.withValues(alpha: 0.28)
    : accent.withValues(alpha: 0.22);
```

这样后续如果其他页面要统一走 soft tinted 路线，token 已经有了。

## 不改的部分

- AppBar（`play_app_bar.dart`）—— 图里就是「练习 + 拼图图标」，现状一致
- 底部导航（`bottom_navigator.dart`）—— 图里和现状一致
- 路由跳转逻辑、provider 监听、l10n 文案 —— 全部不动
- `_CountBadge`、`_SectionTitle` —— 复用
- `peacockTeal` / `peacockCyan` 等色彩 token —— 不动
- 删除「工具」section 的功能（复习进度 / 词典入口），只是换皮肤

## 涉及文件

| 文件 | 改动 |
|------|------|
| `lib/views/play/play_hub_screen.dart` | 大改：删 `_AuroraBackground` / BackdropFilter；替换 hero / focus / review 三种 card 的实现 |
| `lib/views/theme.dart` | 新增 2 个 helper（`softTint` / `softBorder`） |
| 其他文件 | 不动 |

预计净变化：`play_hub_screen.dart` 从 ~770 行 → 约 480 行（删 70 行极光 + BackdropFilter；新增约 80 行 `_QuickPlayHero` / `_FocusTile` / `_ReviewTile` 三个新组件；旧的 `_GlassCard` 整组暂时保留，未来如果确认不再用再清）。

## 验证方式

- `flutter analyze lib/views/play/play_hub_screen.dart lib/views/theme.dart` 无新 warning
- `flutter run -d <device>` 切到「练习」tab，目测：
  1. 背景无渐变光斑、无模糊
  2. 4 张「今日重点」「复习中心」卡片有明显的 accent 着色但轻盈
  3. 快速练习 hero 是 teal→cyan 渐变 + 白字
  4. 暗色模式下色彩仍可读（用 helper 的深色分支）
  5. 跳转行为不变（点 hero / 各 card 仍到原来页面）

## 下一步

确认方案 → 我直接按上面的方向改 `play_hub_screen.dart` 和 `theme.dart`。
如果你想保留「极光底层」作为可切换主题、或者想把「错题复习」的红色调得更柔和，告诉我，调起来都很快。
